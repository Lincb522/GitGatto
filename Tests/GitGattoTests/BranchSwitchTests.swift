import AppKit
import Foundation
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Branch switch continuity", .serialized)
struct BranchSwitchTests {
    @Test("Preview is read-only; save and switch preserves index, working files, ignored files and drafts")
    func roundTrip() async throws {
        let root = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectToolsStore(root: root.appendingPathComponent(".git/tools"))
        let service = WorkSceneService(store: store)
        try await edit(root)
        try "ignored\n".write(to: root.appendingPathComponent("cache.log"), atomically: true, encoding: .utf8)
        let fingerprint = try await RepositoryChangeFingerprint.capture(in: root)
        let staged = try await git(root, ["diff", "--cached"])
        let unstaged = try await git(root, ["diff"])
        let preview = try await service.previewSwitch(to: "other", repository: root)
        #expect(preview.changes.count == 2)
        #expect(preview.branch == "main" && preview.targetBranch == "other")
        #expect(try await RepositoryChangeFingerprint.capture(in: root) == fingerprint)
        #expect(try await store.load().scenes.isEmpty)
        let context = BranchWorkspaceDraft(commitMessage: "main draft", agentPrompt: "main agent", selectedPath: "new\n文件.txt")
        let scene = try #require(await service.saveAndSwitch(preview, context: context))
        #expect(scene.draft == context.commitMessage && scene.agentDraft == context.agentPrompt && scene.selectedPath == context.selectedPath)
        #expect(try await git(root, ["branch", "--show-current"]) == "other")
        #expect(try await git(root, ["status", "--porcelain"]).isEmpty)
        #expect(try String(contentsOf: root.appendingPathComponent("cache.log"), encoding: .utf8) == "ignored\n")
        // A newly created service restores the durable record, without replaying the save.
        let resumed = WorkSceneService(store: ProjectToolsStore(root: root.appendingPathComponent(".git/tools")))
        try await resumed.restore(scene)
        #expect(try await git(root, ["branch", "--show-current"]) == "main")
        #expect(try await git(root, ["diff", "--cached"]) == staged)
        #expect(try await git(root, ["diff"]) == unstaged)
        #expect(try String(contentsOf: root.appendingPathComponent("new\n文件.txt"), encoding: .utf8) == "untracked\n")
    }

    @Test("Changed tracked content, untracked content, target head and source branch invalidate the preview", arguments: ["tracked", "untracked", "target", "branch"])
    func stale(kind: String) async throws {
        let root = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectToolsStore(root: root.appendingPathComponent(".git/tools"))
        let service = WorkSceneService(store: store)
        try await edit(root)
        let preview = try await service.previewSwitch(to: "other", repository: root)
        switch kind {
        case "tracked": try "newer edit\n".write(to: root.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        case "untracked": try "newer file\n".write(to: root.appendingPathComponent("new\n文件.txt"), atomically: true, encoding: .utf8)
        case "target":
            let tree = try await git(root, ["rev-parse", "HEAD^{tree}"])
            let commit = try await git(root, ["commit-tree", tree, "-p", "HEAD", "-m", "target moved"])
            _ = try await git(root, ["update-ref", "refs/heads/other", commit])
        default: _ = try await git(root, ["switch", "-c", "another"])
        }
        let before = try await RepositoryChangeFingerprint.capture(in: root)
        await #expect(throws: ProjectToolsError.self) { try await service.saveAndSwitch(preview, context: .init()) }
        #expect(try await RepositoryChangeFingerprint.capture(in: root) == before)
        #expect(try await store.load().scenes.isEmpty)
        #expect(try await git(root, ["stash", "list"]).isEmpty)
    }

    @Test("Occupied target and corrupt store fail before stashing; clean switch creates no scene", arguments: ["occupied", "store", "clean"])
    func preconditions(kind: String) async throws {
        let root = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectToolsStore(root: root.appendingPathComponent(".git/tools"))
        let service = WorkSceneService(store: store)
        if kind != "clean" { try await edit(root) }
        let preview = try await service.previewSwitch(to: "other", repository: root)
        if kind == "clean" {
            #expect(try await service.saveAndSwitch(preview, context: .init()) == nil)
            #expect(try await git(root, ["branch", "--show-current"]) == "other")
            #expect(try await store.load().scenes.isEmpty)
            return
        }
        if kind == "occupied" {
            _ = try await git(root, ["worktree", "add", root.appendingPathComponent(".git/other-worktree").path, "other"])
        } else {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(".git/tools"), withIntermediateDirectories: true)
            try Data("invalid json".utf8).write(to: root.appendingPathComponent(".git/tools").appendingPathComponent("state.json"))
        }
        let before = try await RepositoryChangeFingerprint.capture(in: root)
        await #expect(throws: (any Error).self) { try await service.saveAndSwitch(preview, context: .init()) }
        #expect(try await RepositoryChangeFingerprint.capture(in: root) == before)
        #expect(try await git(root, ["stash", "list"]).isEmpty)
    }

    @Test("Checkout failure leaves a durable recovery scene, without discarding or replaying work")
    func switchFailure() async throws {
        let root = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectToolsStore(root: root.appendingPathComponent(".git/tools"))
        let service = WorkSceneService(store: store)
        try await edit(root)
        let before = try await git(root, ["diff", "--cached"])
        let preview = try await service.previewSwitch(to: "other", repository: root)
        let hooks = root.appendingPathComponent(".git/fixture-hooks")
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        let hook = hooks.appendingPathComponent("post-checkout")
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: hook)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hook.path)
        _ = try await git(root, ["config", "core.hooksPath", hooks.path])
        var saved: WorkScene?
        do { _ = try await service.saveAndSwitch(preview, context: .init(commitMessage: "keep draft")); Issue.record("Expected checkout failure") }
        catch let failure as WorkSceneSwitchFailure { saved = failure.scene }
        let scene = try #require(saved)
        #expect(scene.phase == .saved)
        #expect(try await store.load().scenes.first == scene)
        _ = try await git(root, ["config", "core.hooksPath", "/dev/null"])
        try await service.restore(scene)
        #expect(try await git(root, ["diff", "--cached"]) == before)
        #expect(scene.draft == "keep draft")
    }

    @Test("An ignored file tracked by the target branch is not overwritten during switch or restore")
    func ignoredCollision() async throws {
        let root = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectToolsStore(root: root.appendingPathComponent(".git/tools"))
        let service = WorkSceneService(store: store)
        _ = try await git(root, ["switch", "other"])
        try Data("tracked on other\n".utf8).write(to: root.appendingPathComponent("cache.log"))
        _ = try await git(root, ["add", "-f", "cache.log"])
        _ = try await git(root, ["commit", "-m", "track cache on other"])
        let otherScene = try await service.save(name: "other", repository: root, draft: "", agentDraft: "",
            selectedPath: nil, goalID: nil, relatedURL: "", section: "changes")
        _ = try await git(root, ["switch", "main"])
        try Data("local ignored\n".utf8).write(to: root.appendingPathComponent("cache.log"))
        try await edit(root)
        let preview = try await service.previewSwitch(to: "other", repository: root)
        var saved: WorkScene?
        do { _ = try await service.saveAndSwitch(preview, context: .init()); Issue.record("Expected ignored-file collision") }
        catch let failure as WorkSceneSwitchFailure { saved = failure.scene }
        let scene = try #require(saved)
        #expect(try await git(root, ["branch", "--show-current"]) == "main")
        #expect(try String(contentsOf: root.appendingPathComponent("cache.log"), encoding: .utf8) == "local ignored\n")
        // The old restoration entry must obey the same no-overwrite rule.
        await #expect(throws: (any Error).self) { try await service.restore(otherScene) }
        #expect(try String(contentsOf: root.appendingPathComponent("cache.log"), encoding: .utf8) == "local ignored\n")
        try await service.restore(scene)
        #expect(try String(contentsOf: root.appendingPathComponent("new\n文件.txt"), encoding: .utf8) == "untracked\n")
    }

    @MainActor @Test("Branch refresh restores drafts and file selection")
    func drafts() async throws {
        let model = WorkspaceViewModel()
        let root = URL(fileURLWithPath: "/tmp/gitgatto-branch-draft-fixture")
        let changes = [WorkingTreeChange(path: "a", originalPath: nil, indexStatus: .unmodified, workTreeStatus: .modified),
                       WorkingTreeChange(path: "b", originalPath: nil, indexStatus: .unmodified, workTreeStatus: .modified)]
        func snapshot(_ branch: String, _ url: URL) -> RepositorySnapshot {
            .init(rootURL: url, branchName: branch, upstreamName: nil, aheadCount: 0, behindCount: 0,
                changes: changes, commits: [], branches: [])
        }
        // Github does not load local diff surfaces from these synthetic paths.
        model.selectedSection = .github
        model.apply(snapshot("main", root))
        model.commitMessage = "main draft"; model.codexPrompt = "main question"; model.selectedChange = changes[1]
        model.apply(snapshot("other", root), preservingSelection: true)
        #expect(model.commitMessage.isEmpty && model.codexPrompt.isEmpty)
        model.commitMessage = "other draft"; model.codexPrompt = "other question"
        model.apply(snapshot("main", root), preservingSelection: true)
        #expect(model.commitMessage == "main draft" && model.codexPrompt == "main question")
        #expect(model.selectedChange?.path == "b")
        model.apply(snapshot("other", root), preservingSelection: true)
        #expect(model.commitMessage == "other draft" && model.codexPrompt == "other question")
    }

    private func fixture() async throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("GitGatto-branch-switch-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try await git(root, ["init", "-b", "main"])
        for (key, value) in [("user.name", "Fixture"), ("user.email", "fixture@example.invalid"), ("commit.gpgsign", "false"), ("core.hooksPath", "/dev/null")] {
            _ = try await git(root, ["config", key, value])
        }
        try Data("base\n".utf8).write(to: root.appendingPathComponent("file.txt"))
        try Data("*.log\n".utf8).write(to: root.appendingPathComponent(".gitignore"))
        _ = try await git(root, ["add", "."]); _ = try await git(root, ["commit", "-m", "fixture"])
        _ = try await git(root, ["branch", "other"])
        return root
    }
    private func edit(_ root: URL) async throws {
        try Data("staged\n".utf8).write(to: root.appendingPathComponent("file.txt"))
        _ = try await git(root, ["add", "file.txt"])
        try Data("staged\nworking\n".utf8).write(to: root.appendingPathComponent("file.txt"))
        try Data("untracked\n".utf8).write(to: root.appendingPathComponent("new\n文件.txt"))
    }
    private func git(_ root: URL, _ args: [String]) async throws -> String { try await ProjectToolsPolicy.text(root, args) }
}
