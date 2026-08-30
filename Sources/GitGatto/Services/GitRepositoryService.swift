import Foundation

enum GitRepositoryServiceError: LocalizedError, Sendable {
    case pushFailedAfterCommit(GitFailureDetails)

    var failureDetails: GitFailureDetails {
        switch self {
        case let .pushFailedAfterCommit(details): details
        }
    }

    var errorDescription: String? {
        switch self {
        case let .pushFailedAfterCommit(details):
            "The commit was created, but the push failed: \(details.message)"
        }
    }
}

enum CommitDraftPreparationError: LocalizedError, Sendable, Equatable {
    case unresolvedConflicts(Int)

    var errorDescription: String? {
        switch self {
        case let .unresolvedConflicts(count):
            L10n.format("codex.error.unresolved_conflicts", count)
        }
    }
}

protocol GitRepositoryServing: Sendable {
    func loadRepository(at selectedURL: URL) async throws -> RepositorySnapshot
    func loadRepositoryOverview(at selectedURL: URL) async throws -> RepositorySnapshot
    func loadLiveState(at repositoryURL: URL) async throws -> RepositoryLiveState
    func commitGraph(in repositoryURL: URL) async throws -> CommitGraph
    func fetchRemoteTracking(in repositoryURL: URL) async throws
    func diff(for change: WorkingTreeChange, in repositoryURL: URL) async throws -> DiffDocument
    func diff(for commit: CommitRecord, in repositoryURL: URL) async throws -> DiffDocument
    func mediaPreview(for change: WorkingTreeChange, in repositoryURL: URL) async throws -> URL?
    func mediaItems(for commit: CommitRecord, in repositoryURL: URL) async throws -> [RepositoryMediaItem]
    func mediaPreview(
        for item: RepositoryMediaItem,
        at commit: CommitRecord,
        in repositoryURL: URL
    ) async throws -> URL?
    func stagedDiff(in repositoryURL: URL) async throws -> String
    func prepareCommitDraft(in repositoryURL: URL) async throws -> CommitDraftEvidence
    func stashes(in repositoryURL: URL) async throws -> [StashRecord]
    func stashDiff(reference: String, in repositoryURL: URL) async throws -> DiffDocument
    func stashChanges(message: String?, includeUntracked: Bool, in repositoryURL: URL) async throws -> Bool
    func applyStash(reference: String, in repositoryURL: URL) async throws -> RepositoryOperationTransition
    func popStash(reference: String, in repositoryURL: URL) async throws -> RepositoryOperationTransition
    func dropStash(reference: String, in repositoryURL: URL) async throws
    func stage(paths: [String], in repositoryURL: URL) async throws
    func unstage(paths: [String], in repositoryURL: URL) async throws
    func switchBranch(to branchName: String, in repositoryURL: URL) async throws
    func discard(_ change: WorkingTreeChange, in repositoryURL: URL) async throws
    func ignore(path: String, scope: GitIgnoreScope, in repositoryURL: URL) async throws
    func commit(message: String, in repositoryURL: URL) async throws
    func commitAndPush(message: String, in repositoryURL: URL) async throws
    func stageCommitAndPush(paths: [String], message: String, in repositoryURL: URL) async throws
    func pull(in repositoryURL: URL) async throws
    func push(in repositoryURL: URL) async throws
    func repositoryOperationState(in repositoryURL: URL) async throws -> RepositoryOperationState?
    func repositoryOperationState(
        in repositoryURL: URL,
        changes: [WorkingTreeChange]
    ) async throws -> RepositoryOperationState?
    func conflictDocument(path: String, in repositoryURL: URL) async throws -> ConflictFileDocument
    func resolveConflict(path: String, using side: ConflictSide, in repositoryURL: URL) async throws
    func resolveConflict(path: String, result: String, in repositoryURL: URL) async throws
    func merge(branch: String, in repositoryURL: URL) async throws -> RepositoryOperationTransition
    func rebase(onto branch: String, in repositoryURL: URL) async throws -> RepositoryOperationTransition
    func continueRepositoryOperation(in repositoryURL: URL) async throws -> RepositoryOperationTransition
    func skipRepositoryOperation(in repositoryURL: URL) async throws -> RepositoryOperationTransition
    func abortRepositoryOperation(in repositoryURL: URL) async throws
}

extension GitRepositoryServing {
    func loadRepositoryOverview(at selectedURL: URL) async throws -> RepositorySnapshot {
        try await loadRepository(at: selectedURL)
    }

    func repositoryOperationState(
        in repositoryURL: URL,
        changes: [WorkingTreeChange]
    ) async throws -> RepositoryOperationState? {
        try await repositoryOperationState(in: repositoryURL)
    }

    func mediaPreview(for change: WorkingTreeChange, in repositoryURL: URL) async throws -> URL? {
        nil
    }

    func mediaItems(for commit: CommitRecord, in repositoryURL: URL) async throws -> [RepositoryMediaItem] {
        []
    }

    func stageCommitAndPush(paths: [String], message: String, in repositoryURL: URL) async throws {
        try await stage(paths: paths, in: repositoryURL)
        try await commitAndPush(message: message, in: repositoryURL)
    }

    func mediaPreview(
        for item: RepositoryMediaItem,
        at commit: CommitRecord,
        in repositoryURL: URL
    ) async throws -> URL? {
        nil
    }

    func prepareCommitDraft(in repositoryURL: URL) async throws -> CommitDraftEvidence {
        let currentState = try await loadLiveState(at: repositoryURL)
        let conflictCount = currentState.changes.filter {
            $0.indexStatus == .conflicted || $0.workTreeStatus == .conflicted
        }.count
        guard conflictCount == 0 else {
            throw CommitDraftPreparationError.unresolvedConflicts(conflictCount)
        }

        let existingDiff = try await stagedDiff(in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard existingDiff.isEmpty else {
            return CommitDraftEvidence(
                stagedDiff: existingDiff,
                automaticallyStagedPaths: [],
                liveState: nil
            )
        }

        let paths = currentState.changes
            .filter { !$0.isStaged }
            .map(\.path)
        guard !paths.isEmpty else {
            return CommitDraftEvidence(
                stagedDiff: "",
                automaticallyStagedPaths: [],
                liveState: currentState
            )
        }

        try await stage(paths: paths, in: repositoryURL)
        let updatedState = try await loadLiveState(at: repositoryURL)
        let stagedDiff = try await stagedDiff(in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CommitDraftEvidence(
            stagedDiff: stagedDiff,
            automaticallyStagedPaths: paths,
            liveState: updatedState
        )
    }
}

actor GitRepositoryService: GitRepositoryServing {
    private let runner: GitCommandRunner
    private var gitDirectoriesByRepositoryPath: [String: URL] = [:]

    init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    func loadRepository(at selectedURL: URL) async throws -> RepositorySnapshot {
        try await loadRepository(at: selectedURL, untrackedFiles: "all")
    }

    func loadRepositoryOverview(at selectedURL: URL) async throws -> RepositorySnapshot {
        try await loadRepository(at: selectedURL, untrackedFiles: "no")
    }

    private func loadRepository(
        at selectedURL: URL,
        untrackedFiles: String
    ) async throws -> RepositorySnapshot {
        let rootResult = try await runner.run(
            at: selectedURL,
            arguments: ["rev-parse", "--show-toplevel", "--absolute-git-dir"]
        )
        let rootFields = rootResult.text
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
        guard let rootPath = rootFields.first else {
            throw GitCommandError(
                arguments: ["rev-parse", "--show-toplevel", "--absolute-git-dir"],
                exitCode: 128,
                message: "Git did not return a repository root."
            )
        }
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        if rootFields.count > 1 {
            gitDirectoriesByRepositoryPath[rootURL.standardizedFileURL.path] = URL(
                fileURLWithPath: rootFields[1],
                isDirectory: true
            )
        }

        async let statusResult = runner.run(
            at: rootURL,
            arguments: ["status", "--porcelain=v1", "-z", "--branch", "--untracked-files=\(untrackedFiles)"]
        )
        async let commitResult = runner.run(
            at: rootURL,
            arguments: ["log", "-n", "100", "--date=iso-strict", "--pretty=format:%H%x1f%h%x1f%an%x1f%ad%x1f%s%x1e"],
            acceptedExitCodes: [0, 128]
        )
        async let branchListResult = runner.run(
            at: rootURL,
            arguments: ["for-each-ref", "--format=%(refname:short)%00%(objectname:short)%00%(upstream:short)%00", "refs/heads"]
        )
        let (statusOutput, commitOutput, branchListOutput) = try await (
            statusResult,
            commitResult,
            branchListResult
        )
        let status = try await parsedStatus(
            statusOutput,
            in: rootURL,
            untrackedFiles: untrackedFiles
        )

        return RepositorySnapshot(
            rootURL: rootURL,
            branchName: status.branchName,
            upstreamName: status.upstreamName,
            aheadCount: status.aheadCount,
            behindCount: status.behindCount,
            changes: status.changes,
            commits: GitParsers.commits(from: commitOutput.text),
            branches: GitParsers.branches(from: branchListOutput.output, currentBranch: status.branchName)
        )
    }

    func loadLiveState(at repositoryURL: URL) async throws -> RepositoryLiveState {
        let statusResult = try await runner.run(
            at: repositoryURL,
            arguments: ["status", "--porcelain=v1", "-z", "--branch", "--untracked-files=all"]
        )
        let status = try await parsedStatus(
            statusResult,
            in: repositoryURL,
            untrackedFiles: "all"
        )

        return RepositoryLiveState(
            branchName: status.branchName,
            upstreamName: status.upstreamName,
            aheadCount: status.aheadCount,
            behindCount: status.behindCount,
            changes: status.changes
        )
    }

    func commitGraph(in repositoryURL: URL) async throws -> CommitGraph {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: [
                "log",
                "--all",
                "--topo-order",
                "-n", "300",
                "--date=iso-strict",
                "--pretty=format:%H%x1f%h%x1f%P%x1f%D%x1f%an%x1f%ad%x1f%s%x1e"
            ],
            acceptedExitCodes: [0, 128]
        )
        guard result.exitCode == 0 else { return .empty }
        return Self.parseCommitGraph(result.text)
    }

    func fetchRemoteTracking(in repositoryURL: URL) async throws {
        let upstream = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            acceptedExitCodes: [0, 128]
        )
        guard upstream.exitCode == 0 else { return }
        let upstreamName = upstream.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let remote = upstreamName.split(separator: "/", maxSplits: 1).first, !remote.isEmpty else { return }
        _ = try await runner.run(
            at: repositoryURL,
            arguments: ["fetch", "--quiet", "--no-tags", String(remote)]
        )
    }

    func diff(for change: WorkingTreeChange, in repositoryURL: URL) async throws -> DiffDocument {
        let result: GitCommandResult
        if change.isStaged {
            result = try await runner.run(
                at: repositoryURL,
                arguments: ["diff", "--cached", "--no-ext-diff", "--no-textconv", "--no-color", "--unified=4", "--", change.path]
            )
        } else if change.workTreeStatus == .untracked {
            result = try await runner.run(
                at: repositoryURL,
                arguments: ["diff", "--no-index", "--no-ext-diff", "--no-textconv", "--no-color", "--unified=4", "/dev/null", change.path],
                acceptedExitCodes: [0, 1]
            )
        } else {
            result = try await runner.run(
                at: repositoryURL,
                arguments: ["diff", "--no-ext-diff", "--no-textconv", "--no-color", "--unified=4", "--", change.path]
            )
        }
        return GitParsers.diff(from: result.text, path: change.path)
    }

    func diff(for commit: CommitRecord, in repositoryURL: URL) async throws -> DiffDocument {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["show", "--format=", "--no-ext-diff", "--no-textconv", "--no-color", "--unified=4", commit.hash]
        )
        return GitParsers.diff(from: result.text, path: commit.shortHash)
    }

    func mediaPreview(for change: WorkingTreeChange, in repositoryURL: URL) async throws -> URL? {
        guard RepositoryMediaKind(fileName: change.path) != nil else { return nil }
        let workingURL = try validatedFileURL(path: change.path, in: repositoryURL)
        if !change.isStaged, FileManager.default.fileExists(atPath: workingURL.path) {
            return workingURL
        }

        let revision = change.isStaged && change.indexStatus != .deleted ? ":" : "HEAD:"
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["show", "\(revision)\(change.path)"]
        )
        return try RepositoryMediaCache.store(
            result.output,
            key: "change:\(revision):\(change.path)",
            path: change.path
        )
    }

    func mediaItems(for commit: CommitRecord, in repositoryURL: URL) async throws -> [RepositoryMediaItem] {
        async let changedResult = runner.run(
            at: repositoryURL,
            arguments: [
                "diff-tree", "--root", "--no-commit-id", "--name-only", "-r", "-z", commit.hash
            ]
        )
        async let treeResult = runner.run(
            at: repositoryURL,
            arguments: ["ls-tree", "-r", "--name-only", "-z", commit.hash]
        )
        let changed = try await changedResult
        let tree = try await treeResult
        let existingPaths = Set(tree.output.split(separator: 0).map { String(decoding: $0, as: UTF8.self) })
        return changed.output
            .split(separator: 0)
            .map { RepositoryMediaItem(path: String(decoding: $0, as: UTF8.self)) }
            .filter { $0.kind != nil && existingPaths.contains($0.path) }
    }

    func mediaPreview(
        for item: RepositoryMediaItem,
        at commit: CommitRecord,
        in repositoryURL: URL
    ) async throws -> URL? {
        guard item.kind != nil else { return nil }
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["show", "\(commit.hash):\(item.path)"]
        )
        return try RepositoryMediaCache.store(
            result.output,
            key: "commit:\(commit.hash):\(item.path)",
            path: item.path
        )
    }

    func stagedDiff(in repositoryURL: URL) async throws -> String {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["diff", "--cached", "--no-color", "--no-ext-diff", "--unified=4"]
        )
        return result.text
    }

    func stashes(in repositoryURL: URL) async throws -> [StashRecord] {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["stash", "list", "--format=%gd%x1f%H%x1f%ct%x1f%gs%x1e"]
        )
        return Self.parseStashes(result.text)
    }

    func stashDiff(reference: String, in repositoryURL: URL) async throws -> DiffDocument {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["stash", "show", "--patch", "--include-untracked", "--no-color", reference]
        )
        return GitParsers.diff(from: result.text, path: reference)
    }

    func stashChanges(
        message: String?,
        includeUntracked: Bool,
        in repositoryURL: URL
    ) async throws -> Bool {
        let previous = try await stashHead(in: repositoryURL)
        var arguments = ["stash", "push"]
        if includeUntracked {
            arguments.append("--include-untracked")
        }
        if let message, !message.isEmpty {
            arguments += ["--message", message]
        }
        _ = try await runner.run(at: repositoryURL, arguments: arguments)
        return try await stashHead(in: repositoryURL) != previous
    }

    func applyStash(reference: String, in repositoryURL: URL) async throws -> RepositoryOperationTransition {
        let arguments = ["stash", "apply", "--index", reference]
        let result = try await runner.run(
            at: repositoryURL,
            arguments: arguments,
            acceptedExitCodes: [0, 1]
        )
        return try await transition(for: result, arguments: arguments, in: repositoryURL)
    }

    func popStash(reference: String, in repositoryURL: URL) async throws -> RepositoryOperationTransition {
        let arguments = ["stash", "pop", "--index", reference]
        let result = try await runner.run(
            at: repositoryURL,
            arguments: arguments,
            acceptedExitCodes: [0, 1]
        )
        return try await transition(for: result, arguments: arguments, in: repositoryURL)
    }

    func dropStash(reference: String, in repositoryURL: URL) async throws {
        _ = try await runner.run(
            at: repositoryURL,
            arguments: ["stash", "drop", reference]
        )
    }

    func stage(paths: [String], in repositoryURL: URL) async throws {
        guard !paths.isEmpty else { return }
        let currentChanges = try await changes(at: paths, in: repositoryURL)
        let unstagedPaths = Set(
            currentChanges
                .filter { $0.workTreeStatus != .unmodified }
                .map(\.path)
        )
        let pathsToStage = paths.filter { unstagedPaths.contains($0) }
        guard !pathsToStage.isEmpty else { return }
        _ = try await runner.run(at: repositoryURL, arguments: ["add", "--"] + pathsToStage)
    }

    func unstage(paths: [String], in repositoryURL: URL) async throws {
        guard !paths.isEmpty else { return }
        let currentChanges = try await changes(at: paths, in: repositoryURL)
        let stagedPaths = Set(currentChanges.filter(\.isStaged).map(\.path))
        let pathsToUnstage = paths.filter { stagedPaths.contains($0) }
        guard !pathsToUnstage.isEmpty else { return }
        _ = try await runner.run(at: repositoryURL, arguments: ["reset", "--"] + pathsToUnstage)
    }

    func switchBranch(to branchName: String, in repositoryURL: URL) async throws {
        _ = try await runner.run(
            at: repositoryURL,
            arguments: ["switch", "--no-guess", branchName]
        )
    }

    func discard(_ change: WorkingTreeChange, in repositoryURL: URL) async throws {
        let paths = [change.path, change.originalPath].compactMap { $0 }
        var pathsInHead: [String] = []
        var pathsOutsideHead: [String] = []

        for path in paths {
            let result = try await runner.run(
                at: repositoryURL,
                arguments: ["cat-file", "-e", "HEAD:\(path)"],
                acceptedExitCodes: [0, 128]
            )
            if result.exitCode == 0 {
                pathsInHead.append(path)
            } else {
                pathsOutsideHead.append(path)
            }
        }

        if !pathsInHead.isEmpty {
            _ = try await runner.run(
                at: repositoryURL,
                arguments: ["restore", "--source=HEAD", "--staged", "--worktree", "--"] + pathsInHead
            )
        }

        if !pathsOutsideHead.isEmpty {
            _ = try await runner.run(
                at: repositoryURL,
                arguments: ["rm", "--cached", "--ignore-unmatch", "--"] + pathsOutsideHead,
                acceptedExitCodes: [0, 128]
            )
            for path in pathsOutsideHead {
                let fileURL = repositoryURL.appendingPathComponent(path)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    _ = try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                }
            }
        }
    }

    func ignore(path: String, scope: GitIgnoreScope, in repositoryURL: URL) async throws {
        let pattern: String
        switch scope {
        case .file:
            pattern = "/\(Self.escapeGitIgnore(path))"
        case let .folder(folderPath):
            guard !folderPath.isEmpty else { return }
            pattern = "/\(Self.escapeGitIgnore(folderPath))/"
        case .fileExtension:
            let fileExtension = (path as NSString).pathExtension
            guard !fileExtension.isEmpty else { return }
            pattern = "*.\(Self.escapeGitIgnore(fileExtension))"
        }

        let ignoreURL = repositoryURL.appendingPathComponent(".gitignore")
        var data = (try? Data(contentsOf: ignoreURL)) ?? Data()
        let existing = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard !existing.contains(pattern) else { return }

        if let last = data.last, last != 0x0A {
            data.append(0x0A)
        }
        data.append(contentsOf: pattern.utf8)
        data.append(0x0A)
        try data.write(to: ignoreURL, options: .atomic)
    }

    func commit(message: String, in repositoryURL: URL) async throws {
        _ = try await runner.run(at: repositoryURL, arguments: ["commit", "-m", message])
    }

    func commitAndPush(message: String, in repositoryURL: URL) async throws {
        try await commit(message: message, in: repositoryURL)
        do {
            try await push(in: repositoryURL)
        } catch let error as GitCommandError {
            throw GitRepositoryServiceError.pushFailedAfterCommit(error.failureDetails)
        } catch {
            throw GitRepositoryServiceError.pushFailedAfterCommit(
                GitFailureDetails(
                    arguments: ["push"],
                    exitCode: nil,
                    message: error.localizedDescription
                )
            )
        }
    }

    func stageCommitAndPush(paths: [String], message: String, in repositoryURL: URL) async throws {
        guard !paths.isEmpty else { return }
        try await stage(paths: paths, in: repositoryURL)
        _ = try await runner.run(
            at: repositoryURL,
            arguments: ["commit", "-m", message, "--"] + paths
        )
        do {
            try await push(in: repositoryURL)
        } catch let error as GitCommandError {
            throw GitRepositoryServiceError.pushFailedAfterCommit(error.failureDetails)
        } catch {
            throw GitRepositoryServiceError.pushFailedAfterCommit(
                GitFailureDetails(
                    arguments: ["push"],
                    exitCode: nil,
                    message: error.localizedDescription
                )
            )
        }
    }

    func pull(in repositoryURL: URL) async throws {
        _ = try await runner.run(at: repositoryURL, arguments: ["pull", "--ff-only"])
    }

    func push(in repositoryURL: URL) async throws {
        let upstream = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            acceptedExitCodes: [0, 128]
        )
        if upstream.exitCode == 0 {
            _ = try await runner.run(at: repositoryURL, arguments: ["push"])
            return
        }

        let branchResult = try await runner.run(at: repositoryURL, arguments: ["branch", "--show-current"])
        let branch = branchResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteResult = try await runner.run(at: repositoryURL, arguments: ["remote"])
        let remotes = remoteResult.text.split(whereSeparator: \Character.isNewline).map(String.init)
        guard !branch.isEmpty, let remote = remotes.contains("origin") ? "origin" : remotes.first else {
            _ = try await runner.run(at: repositoryURL, arguments: ["push"])
            return
        }
        _ = try await runner.run(
            at: repositoryURL,
            arguments: ["push", "--set-upstream", remote, branch]
        )
    }

    func repositoryOperationState(in repositoryURL: URL) async throws -> RepositoryOperationState? {
        let gitDirectory = try await gitDirectory(in: repositoryURL)
        let conflictedPaths = try await conflictPaths(in: repositoryURL)
        return operationState(gitDirectory: gitDirectory, conflictedPaths: conflictedPaths)
    }

    func repositoryOperationState(
        in repositoryURL: URL,
        changes: [WorkingTreeChange]
    ) async throws -> RepositoryOperationState? {
        let gitDirectory = try await gitDirectory(in: repositoryURL)
        let conflictedPaths = changes.filter(Self.isConflicted).map(\.path)
        return operationState(gitDirectory: gitDirectory, conflictedPaths: conflictedPaths)
    }

    private func operationState(
        gitDirectory: URL,
        conflictedPaths: [String]
    ) -> RepositoryOperationState? {
        let fileManager = FileManager.default

        let rebaseMerge = gitDirectory.appendingPathComponent("rebase-merge", isDirectory: true)
        let rebaseApply = gitDirectory.appendingPathComponent("rebase-apply", isDirectory: true)
        if fileManager.fileExists(atPath: rebaseMerge.path) {
            return RepositoryOperationState(
                kind: .rebase,
                conflictedPaths: conflictedPaths,
                progress: rebaseProgress(in: rebaseMerge, currentName: "msgnum", totalName: "end")
            )
        }
        if fileManager.fileExists(atPath: rebaseApply.path) {
            return RepositoryOperationState(
                kind: .rebase,
                conflictedPaths: conflictedPaths,
                progress: rebaseProgress(in: rebaseApply, currentName: "next", totalName: "last")
            )
        }
        if fileManager.fileExists(atPath: gitDirectory.appendingPathComponent("MERGE_HEAD").path) {
            return RepositoryOperationState(kind: .merge, conflictedPaths: conflictedPaths, progress: nil)
        }
        if fileManager.fileExists(atPath: gitDirectory.appendingPathComponent("CHERRY_PICK_HEAD").path) {
            return RepositoryOperationState(kind: .cherryPick, conflictedPaths: conflictedPaths, progress: nil)
        }
        if fileManager.fileExists(atPath: gitDirectory.appendingPathComponent("REVERT_HEAD").path) {
            return RepositoryOperationState(kind: .revert, conflictedPaths: conflictedPaths, progress: nil)
        }
        guard !conflictedPaths.isEmpty else { return nil }
        return RepositoryOperationState(kind: .unknown, conflictedPaths: conflictedPaths, progress: nil)
    }

    func conflictDocument(path: String, in repositoryURL: URL) async throws -> ConflictFileDocument {
        let stages = try await conflictStages(for: path, in: repositoryURL)
        let baseData = try await conflictBlob(stage: 1, path: path, availableStages: stages, in: repositoryURL)
        let oursData = try await conflictBlob(stage: 2, path: path, availableStages: stages, in: repositoryURL)
        let theirsData = try await conflictBlob(stage: 3, path: path, availableStages: stages, in: repositoryURL)
        let fileURL = try validatedFileURL(path: path, in: repositoryURL)
        let resultData = try? Data(contentsOf: fileURL)
        let allData = [baseData, oursData, theirsData, resultData].compactMap { $0 }

        return ConflictFileDocument(
            path: path,
            base: baseData.flatMap(Self.textContent),
            ours: oursData.flatMap(Self.textContent),
            theirs: theirsData.flatMap(Self.textContent),
            result: resultData.flatMap(Self.textContent),
            isBinary: allData.contains { Self.textContent($0) == nil }
        )
    }

    func resolveConflict(path: String, using side: ConflictSide, in repositoryURL: URL) async throws {
        let stages = try await conflictStages(for: path, in: repositoryURL)
        let stage = side == .ours ? 2 : 3
        if stages.contains(stage) {
            _ = try await runner.run(
                at: repositoryURL,
                arguments: ["checkout", side == .ours ? "--ours" : "--theirs", "--", path]
            )
            _ = try await runner.run(at: repositoryURL, arguments: ["add", "--", path])
        } else {
            _ = try await runner.run(
                at: repositoryURL,
                arguments: ["rm", "--ignore-unmatch", "--", path]
            )
        }
    }

    func resolveConflict(path: String, result: String, in repositoryURL: URL) async throws {
        let fileURL = try validatedFileURL(path: path, in: repositoryURL)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(result.utf8).write(to: fileURL, options: .atomic)
        _ = try await runner.run(at: repositoryURL, arguments: ["add", "--", path])
    }

    func merge(branch: String, in repositoryURL: URL) async throws -> RepositoryOperationTransition {
        let arguments = ["merge", "--no-edit", "--", branch]
        let result = try await runner.run(
            at: repositoryURL,
            arguments: arguments,
            acceptedExitCodes: [0, 1]
        )
        return try await transition(for: result, arguments: arguments, in: repositoryURL)
    }

    func rebase(onto branch: String, in repositoryURL: URL) async throws -> RepositoryOperationTransition {
        let arguments = ["rebase", "--", branch]
        let result = try await runner.run(
            at: repositoryURL,
            arguments: arguments,
            acceptedExitCodes: [0, 1]
        )
        return try await transition(for: result, arguments: arguments, in: repositoryURL)
    }

    func continueRepositoryOperation(in repositoryURL: URL) async throws -> RepositoryOperationTransition {
        guard let state = try await repositoryOperationState(in: repositoryURL), state.kind != .unknown else {
            throw GitCommandError(arguments: ["continue"], exitCode: 128, message: "No Git operation is waiting to continue.")
        }
        let arguments = ["-c", "core.editor=true", state.kind.commandName, "--continue"]
        let result = try await runner.run(
            at: repositoryURL,
            arguments: arguments,
            acceptedExitCodes: [0, 1]
        )
        return try await transition(for: result, arguments: arguments, in: repositoryURL)
    }

    func skipRepositoryOperation(in repositoryURL: URL) async throws -> RepositoryOperationTransition {
        guard let state = try await repositoryOperationState(in: repositoryURL), state.kind.supportsSkip else {
            throw GitCommandError(arguments: ["skip"], exitCode: 128, message: "The current Git operation cannot skip a step.")
        }
        let arguments = [state.kind.commandName, "--skip"]
        let result = try await runner.run(
            at: repositoryURL,
            arguments: arguments,
            acceptedExitCodes: [0, 1]
        )
        return try await transition(for: result, arguments: arguments, in: repositoryURL)
    }

    func abortRepositoryOperation(in repositoryURL: URL) async throws {
        guard let state = try await repositoryOperationState(in: repositoryURL), state.kind.supportsAbort else {
            throw GitCommandError(arguments: ["abort"], exitCode: 128, message: "The current Git operation cannot be aborted.")
        }
        _ = try await runner.run(
            at: repositoryURL,
            arguments: [state.kind.commandName, "--abort"]
        )
    }

    private func parsedStatus(
        _ result: GitCommandResult,
        in repositoryURL: URL,
        untrackedFiles: String
    ) async throws -> GitStatusSnapshot {
        guard let status = GitParsers.statusSnapshot(from: result.output) else {
            throw GitCommandError(
                arguments: ["status", "--porcelain=v1", "-z", "--branch", "--untracked-files=\(untrackedFiles)"],
                exitCode: result.exitCode,
                message: "Git did not return branch status metadata."
            )
        }
        guard status.branchName == "HEAD (no branch)"
                || status.branchName.hasPrefix("HEAD (detached ") else {
            return status
        }
        let head = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "--short", "HEAD"]
        )
        return GitStatusSnapshot(
            branchName: head.text.trimmingCharacters(in: .whitespacesAndNewlines),
            upstreamName: nil,
            aheadCount: 0,
            behindCount: 0,
            changes: status.changes
        )
    }

    private func gitDirectory(in repositoryURL: URL) async throws -> URL {
        let repositoryPath = repositoryURL.standardizedFileURL.path
        if let cached = gitDirectoriesByRepositoryPath[repositoryPath] {
            return cached
        }
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "--absolute-git-dir"]
        )
        let directory = URL(
            fileURLWithPath: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            isDirectory: true
        )
        gitDirectoriesByRepositoryPath[repositoryPath] = directory
        return directory
    }

    private static func isConflicted(_ change: WorkingTreeChange) -> Bool {
        switch (change.indexStatus, change.workTreeStatus) {
        case (.deleted, .deleted),
             (.added, .conflicted),
             (.conflicted, .deleted),
             (.conflicted, .added),
             (.deleted, .conflicted),
             (.added, .added),
             (.conflicted, .conflicted):
            true
        default:
            false
        }
    }

    private func changes(at paths: [String], in repositoryURL: URL) async throws -> [WorkingTreeChange] {
        let status = try await runner.run(
            at: repositoryURL,
            arguments: ["status", "--porcelain=v1", "-z", "--untracked-files=all", "--"] + paths
        )
        return GitParsers.status(from: status.output)
    }

    private func stashHead(in repositoryURL: URL) async throws -> String? {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "--verify", "refs/stash"],
            acceptedExitCodes: [0, 128]
        )
        guard result.exitCode == 0 else { return nil }
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func conflictPaths(in repositoryURL: URL) async throws -> [String] {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["diff", "--name-only", "--diff-filter=U", "-z"]
        )
        return result.output
            .split(separator: 0)
            .map { String(decoding: $0, as: UTF8.self) }
            .filter { !$0.isEmpty }
    }

    private func conflictStages(for path: String, in repositoryURL: URL) async throws -> Set<Int> {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["ls-files", "-u", "-z", "--", path]
        )
        return Set(result.output.split(separator: 0).compactMap { entry in
            let text = String(decoding: entry, as: UTF8.self)
            guard let tab = text.firstIndex(of: "\t") else { return nil }
            return text[..<tab]
                .split(separator: " ")
                .last
                .flatMap { Int($0) }
        })
    }

    private func conflictBlob(
        stage: Int,
        path: String,
        availableStages: Set<Int>,
        in repositoryURL: URL
    ) async throws -> Data? {
        guard availableStages.contains(stage) else { return nil }
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["show", ":\(stage):\(path)"]
        )
        return result.output
    }

    private func transition(
        for result: GitCommandResult,
        arguments: [String],
        in repositoryURL: URL
    ) async throws -> RepositoryOperationTransition {
        if let state = try await repositoryOperationState(in: repositoryURL) {
            return .paused(state)
        }
        guard result.exitCode == 0 else {
            throw Self.commandError(result: result, arguments: arguments)
        }
        return .completed
    }

    private func rebaseProgress(
        in directory: URL,
        currentName: String,
        totalName: String
    ) -> RepositoryOperationProgress? {
        guard let current = Self.integer(in: directory.appendingPathComponent(currentName)),
              let total = Self.integer(in: directory.appendingPathComponent(totalName)),
              current > 0,
              total > 0 else { return nil }
        return RepositoryOperationProgress(current: current, total: total)
    }

    private func validatedFileURL(path: String, in repositoryURL: URL) throws -> URL {
        let root = repositoryURL.standardizedFileURL
        let candidate = root.appendingPathComponent(path).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else {
            throw GitCommandError(arguments: ["resolve", "--", path], exitCode: 128, message: "Conflict path is outside the repository.")
        }
        return candidate
    }

    private static func textContent(_ data: Data) -> String? {
        guard !data.contains(0) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func integer(in url: URL) -> Int? {
        guard let value = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func commandError(result: GitCommandResult, arguments: [String]) -> GitCommandError {
        let stdout = String(decoding: result.output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(decoding: result.errorOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        return GitCommandError(
            arguments: arguments,
            exitCode: result.exitCode,
            message: message.isEmpty ? "git exited with status \(result.exitCode)" : message
        )
    }

    private static func parseStashes(_ value: String) -> [StashRecord] {
        value.split(separator: "\u{1e}").compactMap { rawRecord in
            let record = rawRecord.trimmingCharacters(in: .whitespacesAndNewlines)
            let fields = record.split(separator: "\u{1f}", omittingEmptySubsequences: false)
            guard fields.count == 4,
                  let timestamp = TimeInterval(fields[2]) else { return nil }
            return StashRecord(
                reference: String(fields[0]),
                hash: String(fields[1]),
                createdAt: Date(timeIntervalSince1970: timestamp),
                summary: String(fields[3])
            )
        }
    }

    private static func parseCommitGraph(_ value: String) -> CommitGraph {
        struct Entry {
            let hash: String
            let shortHash: String
            let parents: [String]
            let references: [String]
            let author: String
            let date: Date
            let subject: String
        }

        let entries: [Entry] = value.split(separator: "\u{1e}").compactMap { rawRecord in
            let record = rawRecord.trimmingCharacters(in: .whitespacesAndNewlines)
            let fields = record.split(separator: "\u{1f}", omittingEmptySubsequences: false)
            guard fields.count == 7,
                  let date = ISO8601DateFormatter().date(from: String(fields[5])) else { return nil }
            return Entry(
                hash: String(fields[0]),
                shortHash: String(fields[1]),
                parents: fields[2].split(separator: " ").map(String.init),
                references: parseReferences(String(fields[3])),
                author: String(fields[4]),
                date: date,
                subject: String(fields[6])
            )
        }

        var activeLanes: [String] = []
        var nodes: [CommitGraphNode] = []
        var laneCount = 0
        for entry in entries {
            let lane: Int
            if let existing = activeLanes.firstIndex(of: entry.hash) {
                lane = existing
            } else {
                lane = activeLanes.count
                activeLanes.append(entry.hash)
            }
            laneCount = max(laneCount, lane + 1)

            if let firstParent = entry.parents.first {
                activeLanes[lane] = firstParent
                for index in activeLanes.indices.reversed()
                    where index != lane && activeLanes[index] == firstParent {
                    activeLanes.remove(at: index)
                }
                for parent in entry.parents.dropFirst().reversed() where !activeLanes.contains(parent) {
                    activeLanes.insert(parent, at: min(lane + 1, activeLanes.count))
                }
            } else {
                activeLanes.remove(at: lane)
            }
            laneCount = max(laneCount, activeLanes.count)
            nodes.append(
                CommitGraphNode(
                    hash: entry.hash,
                    shortHash: entry.shortHash,
                    parentHashes: entry.parents,
                    references: entry.references,
                    author: entry.author,
                    date: entry.date,
                    subject: entry.subject,
                    lane: lane
                )
            )
        }
        return CommitGraph(nodes: nodes, laneCount: laneCount)
    }

    private static func parseReferences(_ value: String) -> [String] {
        value.split(separator: ",").map { raw in
            var reference = raw.trimmingCharacters(in: .whitespaces)
            if reference.hasPrefix("HEAD -> ") {
                reference.removeFirst("HEAD -> ".count)
            }
            for prefix in ["tag: refs/tags/", "refs/heads/", "refs/remotes/"] where reference.hasPrefix(prefix) {
                reference.removeFirst(prefix.count)
                break
            }
            return reference
        }.filter { !$0.isEmpty }
    }

    private static func escapeGitIgnore(_ value: String) -> String {
        let specialCharacters: Set<Character> = ["\\", " ", "*", "?", "[", "]", "#", "!"]
        return value.reduce(into: "") { result, character in
            if specialCharacters.contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
    }
}

private extension RepositoryOperationKind {
    var commandName: String {
        switch self {
        case .merge: "merge"
        case .rebase: "rebase"
        case .cherryPick: "cherry-pick"
        case .revert: "revert"
        case .unknown: ""
        }
    }
}
