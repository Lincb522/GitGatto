import Foundation

actor WorkSceneService {
    let store: ProjectToolsStore
    private var busy = false
    init(store: ProjectToolsStore) { self.store = store }

    func save(name: String, repository: URL, draft: String, agentDraft: String, selectedPath: String?, goalID: UUID?, relatedURL: String, section: String) async throws -> WorkScene {
        guard !busy else { throw ProjectToolsError(key: "busy") }
        busy = true; defer { busy = false }
        return try await saveScene(name: name, repository: repository, draft: draft, agentDraft: agentDraft,
            selectedPath: selectedPath, goalID: goalID, relatedURL: relatedURL, section: section)
    }

    private func saveScene(name: String, repository: URL, draft: String, agentDraft: String, selectedPath: String?, goalID: UUID?, relatedURL: String, section: String) async throws -> WorkScene {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProjectToolsError(key: "name") }
        try await checkOperation(repository)
        let branch = try await ProjectToolsPolicy.text(repository, ["symbolic-ref", "--short", "HEAD"])
        let head = try await ProjectToolsPolicy.text(repository, ["rev-parse", "HEAD"])
        var scene = WorkScene(name: name, repositoryPath: repository.path, branch: branch, head: head, selectedPath: selectedPath,
            draft: draft, agentDraft: agentDraft, goalID: goalID, relatedURL: relatedURL, section: section)
        let pending = scene
        try await store.update { $0.scenes.append(pending) }
        // The durable pending record precedes stash mutation; interrupted saves remain discoverable.
        let dirty = try await ProjectToolsPolicy.text(repository, ["status", "--porcelain=v1", "--untracked-files=all"])
        if !dirty.isEmpty {
            _ = try await ProjectToolsPolicy.git(repository, ["stash", "push", "--include-untracked", "-m", scene.marker])
            let subject = try await ProjectToolsPolicy.text(repository, ["log", "-1", "--format=%s", "refs/stash"])
            guard subject.contains(scene.marker) else { throw ProjectToolsError(key: "sceneInterrupted") }
            scene.stash = try await ProjectToolsPolicy.text(repository, ["rev-parse", "refs/stash"])
            if let stash = scene.stash { _ = try await ProjectToolsPolicy.git(repository, ["update-ref", scene.ref, stash, String(repeating: "0", count: head.count)]) }
        }
        scene.phase = .saved
        let saved = scene
        try await store.update { state in state.scenes = state.scenes.map { $0.id == saved.id ? saved : $0 } }
        return scene
    }

    func previewSwitch(to targetBranch: String, repository: URL) async throws -> WorkSceneSwitchPreview {
        guard !busy else { throw ProjectToolsError(key: "busy") }
        try await checkOperation(repository)
        _ = try await ProjectToolsPolicy.git(repository, ["check-ref-format", "--branch", targetBranch])
        let branch = try await ProjectToolsPolicy.text(repository, ["symbolic-ref", "--short", "HEAD"])
        guard branch != targetBranch else { throw ProjectToolsError(key: "branchChanged") }
        let targetHead = try await ProjectToolsPolicy.text(repository, ["rev-parse", "--verify", "refs/heads/" + targetBranch])
        let status = try await ProjectToolsPolicy.git(repository, ["status", "--porcelain=v1", "-z", "--branch", "--untracked-files=all"])
        guard let parsed = GitParsers.statusSnapshot(from: status.standardOutput) else { throw ProjectToolsError(key: "branchChanged") }
        guard !parsed.changes.contains(where: { $0.indexStatus == .conflicted || $0.workTreeStatus == .conflicted }) else {
            throw ProjectToolsError(key: "operation")
        }
        let fingerprint: String
        do {
            fingerprint = try await RepositoryChangeFingerprint.capture(in: repository, expectedStatus: status.standardOutput)
        } catch ChangeIntentError.repositoryChanged {
            throw ProjectToolsError(key: "branchChanged")
        }
        return WorkSceneSwitchPreview(repository: repository, branch: branch, targetBranch: targetBranch,
            targetHead: targetHead, fingerprint: fingerprint, changes: parsed.changes)
    }

    func saveAndSwitch(_ preview: WorkSceneSwitchPreview, context: BranchWorkspaceDraft) async throws -> WorkScene? {
        guard !busy else { throw ProjectToolsError(key: "busy") }
        busy = true; defer { busy = false }
        let repository = preview.repository
        try await checkOperation(repository)
        guard try await RepositoryChangeFingerprint.capture(in: repository) == preview.fingerprint,
              try await ProjectToolsPolicy.text(repository, ["symbolic-ref", "--short", "HEAD"]) == preview.branch,
              try await ProjectToolsPolicy.text(repository, ["rev-parse", "--verify", "refs/heads/" + preview.targetBranch]) == preview.targetHead else {
            throw ProjectToolsError(key: "branchChanged")
        }
        // A local branch already checked out elsewhere must not cause a needless stash.
        let worktrees = try await ProjectToolsPolicy.git(repository, ["worktree", "list", "--porcelain", "-z"])
        guard !worktrees.outputText.split(separator: "\0").contains("branch refs/heads/" + preview.targetBranch) else {
            throw ProjectToolsError(key: "branchOccupied")
        }
        try Task.checkCancellation()
        let scene: WorkScene?
        if !preview.changes.isEmpty {
            scene = try await saveScene(name: preview.branch, repository: repository, draft: context.commitMessage,
                agentDraft: context.agentPrompt, selectedPath: context.selectedPath, goalID: context.goalID,
                relatedURL: "", section: context.section.rawValue)
        } else { scene = nil }
        do {
            try Task.checkCancellation()
            guard try await ProjectToolsPolicy.text(repository, ["status", "--porcelain=v1", "--untracked-files=all"]).isEmpty else {
                throw ProjectToolsError(key: "dirty")
            }
            _ = try await ProjectToolsPolicy.git(repository, ["switch", "--no-guess", "--no-overwrite-ignore", "--", preview.targetBranch])
            guard try await ProjectToolsPolicy.text(repository, ["symbolic-ref", "--short", "HEAD"]) == preview.targetBranch else {
                throw ProjectToolsError(key: "branchChanged")
            }
        } catch {
            // Never roll back over work another process may have created after the save.
            if let scene { throw WorkSceneSwitchFailure(scene: scene, reason: error.localizedDescription) }
            throw error
        }
        return scene
    }

    func recoverPending(_ scene: WorkScene) async throws {
        guard !busy, scene.phase == .saving else { throw ProjectToolsError(key: "sceneInterrupted") }
        busy = true; defer { busy = false }
        guard try await store.load().scenes.first(where: { $0.id == scene.id })?.phase == .saving else { throw ProjectToolsError(key: "sceneInterrupted") }
        let repository = URL(fileURLWithPath: scene.repositoryPath)
        let log = try await ProjectToolsPolicy.git(repository, ["stash", "list", "--format=%H%x00%s"], codes: [0])
        let entry = log.outputText.components(separatedBy: "\n").first { $0.contains(scene.marker) }
        guard let entry, let sha = entry.split(separator: "\0").first else { throw ProjectToolsError(key: "sceneInterrupted") }
        var recovered = scene; recovered.stash = String(sha); recovered.phase = .saved
        let existing = try await ProjectToolsPolicy.git(repository, ["rev-parse", "--verify", "--quiet", scene.ref], codes: [0, 1])
        if existing.exitCode == 0 {
            guard existing.outputText.trimmingCharacters(in: .newlines) == String(sha) else { throw ProjectToolsError(key: "sceneInterrupted") }
        } else {
            _ = try await ProjectToolsPolicy.git(repository, ["update-ref", scene.ref, String(sha), String(repeating: "0", count: scene.head.count)])
        }
        let value = recovered
        try await store.update { $0.scenes = $0.scenes.map { $0.id == value.id ? value : $0 } }
    }

    func restore(_ scene: WorkScene) async throws {
        guard !busy else { throw ProjectToolsError(key: "busy") }
        busy = true; defer { busy = false }
        guard try await store.load().scenes.first(where: { $0.id == scene.id })?.phase == .saved, scene.phase == .saved else { throw ProjectToolsError(key: "sceneInterrupted") }
        let repository = URL(fileURLWithPath: scene.repositoryPath)
        try await checkOperation(repository)
        guard try await ProjectToolsPolicy.text(repository, ["status", "--porcelain=v1", "--untracked-files=all"]).isEmpty else { throw ProjectToolsError(key: "dirty") }
        let tip = try await ProjectToolsPolicy.text(repository, ["rev-parse", "--verify", "--end-of-options", "refs/heads/" + scene.branch])
        guard tip == scene.head else { throw ProjectToolsError(key: "headChanged") }
        if let stash = scene.stash {
            guard try await ProjectToolsPolicy.text(repository, ["rev-parse", scene.ref]) == stash else { throw ProjectToolsError(key: "sceneInterrupted") }
        }
        var pending = scene; pending.phase = .restoring
        let restoring = pending
        try await store.update { $0.scenes = $0.scenes.map { $0.id == restoring.id ? restoring : $0 } }
        _ = try await ProjectToolsPolicy.git(repository, ["switch", "--no-overwrite-ignore", "--", scene.branch])
        guard try await ProjectToolsPolicy.text(repository, ["rev-parse", "HEAD"]) == scene.head else { throw ProjectToolsError(key: "headChanged") }
        if let stash = scene.stash { _ = try await ProjectToolsPolicy.git(repository, ["stash", "apply", "--index", stash]) }
        var finished = scene; finished.phase = .restored
        let restored = finished
        try await store.update { $0.scenes = $0.scenes.map { $0.id == restored.id ? restored : $0 } }
    }

    func acknowledge(_ scene: WorkScene) async throws {
        guard !busy, scene.phase == .restoring || scene.phase == .saving else { throw ProjectToolsError(key: "busy") }
        busy = true; defer { busy = false }
        guard try await store.load().scenes.first(where: { $0.id == scene.id })?.phase == scene.phase else { throw ProjectToolsError(key: "sceneInterrupted") }
        var value = scene
        if value.stash == nil {
            let root = URL(fileURLWithPath: scene.repositoryPath)
            let ref = try await ProjectToolsPolicy.git(root, ["rev-parse", "--verify", "--quiet", scene.ref], codes: [0, 1])
            if ref.exitCode == 0 {
                let subject = try await ProjectToolsPolicy.text(root, ["log", "-1", "--format=%s", scene.ref])
                guard subject.contains(scene.marker) else { throw ProjectToolsError(key: "sceneInterrupted") }
                value.stash = ref.outputText.trimmingCharacters(in: .newlines)
            }
        }
        value.phase = .handled
        let updated = value
        try await store.update { $0.scenes = $0.scenes.map { $0.id == updated.id ? updated : $0 } }
    }

    func rename(_ scene: WorkScene, name: String) async throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProjectToolsError(key: "name") }
        try await store.update { state in
            guard let index = state.scenes.firstIndex(where: { $0.id == scene.id }) else { return }
            state.scenes[index].name = name
        }
    }

    func delete(_ scene: WorkScene) async throws {
        guard !busy, scene.phase != .restoring, scene.phase != .saving else { throw ProjectToolsError(key: "sceneInterrupted") }
        busy = true; defer { busy = false }
        if let stash = scene.stash {
            _ = try await ProjectToolsPolicy.git(URL(fileURLWithPath: scene.repositoryPath), ["update-ref", "-d", scene.ref, stash])
        }
        do { try await store.update { $0.scenes.removeAll { $0.id == scene.id } } }
        catch {
            if let stash = scene.stash { _ = try await ProjectToolsPolicy.git(URL(fileURLWithPath: scene.repositoryPath), ["update-ref", scene.ref, stash, String(repeating: "0", count: scene.head.count)]) }
            throw error
        }
    }

    func createWorktree(for scene: WorkScene, at destination: URL) async throws {
        guard !busy, scene.phase == .saved || scene.phase == .restored, !FileManager.default.fileExists(atPath: destination.path) else { throw ProjectToolsError(key: "destination") }
        busy = true; defer { busy = false }
        _ = try await ProjectToolsPolicy.git(URL(fileURLWithPath: scene.repositoryPath), ["worktree", "add", "--detach", "--", destination.path, scene.head])
        if let stash = scene.stash { _ = try await ProjectToolsPolicy.git(destination, ["stash", "apply", "--index", stash]) }
    }

    private func checkOperation(_ repository: URL) async throws {
        for marker in ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply"] {
            let path = try await ProjectToolsPolicy.text(repository, ["rev-parse", "--git-path", marker])
            let file = path.hasPrefix("/") ? URL(fileURLWithPath: path) : repository.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: file.path) { throw ProjectToolsError(key: "operation") }
        }
    }
}
