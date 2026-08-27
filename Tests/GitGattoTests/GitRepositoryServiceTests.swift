import Foundation
import Testing
@testable import GitGatto

@Suite("Repository service")
struct GitRepositoryServiceTests {
    @Test("Adds common macOS executable locations to a Finder-style PATH")
    func resolvesGitExtensionsOutsideSystemPath() {
        let path = GitCommandRunner.commandPath(
            inheritedPath: "/usr/bin:/bin:/usr/local/bin",
            additionalSearchPaths: ["/usr/local/bin", "/opt/homebrew/bin"]
        )

        #expect(path == "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin")
    }

    @Test("Loads a real repository and its staged and unstaged changes")
    func loadsRepositoryState() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitGatto Test"], at: root)
        try runGit(["config", "user.email", "gitgatto@example.invalid"], at: root)

        try "first\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], at: root)
        try runGit(["commit", "-m", "Initial commit"], at: root)

        try "first\nsecond\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "new\n".write(to: root.appendingPathComponent("staged.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "staged.txt"], at: root)

        let service = GitRepositoryService()
        let snapshot = try await service.loadRepository(at: root)
        let stagedDiff = try await service.stagedDiff(in: root)

        #expect(snapshot.branchName == "main")
        #expect(snapshot.commits.first?.subject == "Initial commit")
        #expect(snapshot.stagedChanges.map(\.path) == ["staged.txt"])
        #expect(snapshot.unstagedChanges.map(\.path) == ["tracked.txt"])
        #expect(stagedDiff.contains("staged.txt"))
        #expect(stagedDiff.contains("+new"))
        #expect(!stagedDiff.contains("tracked.txt"))
        #expect(!stagedDiff.contains("+second"))
    }

    @Test("Reloads working-tree and staging state without rebuilding history")
    func loadsLiveRepositoryState() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoLiveStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitGatto Test"], at: root)
        try runGit(["config", "user.email", "gitgatto@example.invalid"], at: root)
        try "before\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], at: root)
        try runGit(["commit", "-m", "Initial commit"], at: root)

        try "after\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "new\n".write(to: root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

        let service = GitRepositoryService()
        let unstaged = try await service.loadLiveState(at: root)
        #expect(unstaged.changes.filter(\.isStaged).isEmpty)
        #expect(Set(unstaged.changes.filter { !$0.isStaged }.map(\.path)) == ["tracked.txt", "new.txt"])

        try runGit(["add", "tracked.txt", "new.txt"], at: root)

        let staged = try await service.loadLiveState(at: root)
        #expect(staged.changes.filter { !$0.isStaged }.isEmpty)
        #expect(Set(staged.changes.filter(\.isStaged).map(\.path)) == ["tracked.txt", "new.txt"])
    }

    @Test("Switches to a selected local branch")
    func switchesLocalBranch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoBranchSwitchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitGatto Test"], at: root)
        try runGit(["config", "user.email", "gitgatto@example.invalid"], at: root)
        try "initial\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], at: root)
        try runGit(["commit", "-m", "Initial commit"], at: root)
        try runGit(["branch", "feature/quick-switch"], at: root)

        let service = GitRepositoryService()
        try await service.switchBranch(to: "feature/quick-switch", in: root)
        let snapshot = try await service.loadRepository(at: root)

        #expect(snapshot.branchName == "feature/quick-switch")
        #expect(snapshot.branches.first(where: { $0.name == "feature/quick-switch" })?.isCurrent == true)
    }

    @MainActor
    @Test("Live monitoring updates staging after an external Git command", .timeLimit(.minutes(1)))
    func monitorsExternalStagingChanges() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoLiveMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitGatto Test"], at: root)
        try runGit(["config", "user.email", "gitgatto@example.invalid"], at: root)
        try "initial\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], at: root)
        try runGit(["commit", "-m", "Initial commit"], at: root)
        try "changed\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)

        let model = WorkspaceViewModel()
        model.appPreferences.liveRefreshEnabled = true
        model.appPreferences.liveRefreshInterval = 0.5
        model.appPreferences.remoteRefreshEnabled = false
        await model.openRepository(root)
        #expect(model.snapshot?.unstagedChanges.map(\.path) == ["tracked.txt"])

        try runGit(["add", "tracked.txt"], at: root)

        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while model.snapshot?.stagedChanges.map(\.path) != ["tracked.txt"], ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(model.snapshot?.stagedChanges.map(\.path) == ["tracked.txt"])
        #expect(model.snapshot?.unstagedChanges.isEmpty == true)
    }

    @Test("Fetches the configured upstream before reporting remote divergence")
    func refreshesRemoteTrackingState() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoRemoteTrackingTests-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("working", isDirectory: true)
        let writer = root.appendingPathComponent("writer", isDirectory: true)
        let remote = root.appendingPathComponent("remote.git", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "--bare", remote.path], at: root)
        try runGit(["init", "-b", "main"], at: repository)
        try runGit(["config", "user.name", "GitGatto Test"], at: repository)
        try runGit(["config", "user.email", "gitgatto@example.invalid"], at: repository)
        try "first\n".write(to: repository.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], at: repository)
        try runGit(["commit", "-m", "Initial commit"], at: repository)
        try runGit(["remote", "add", "origin", remote.path], at: repository)
        try runGit(["push", "-u", "origin", "main"], at: repository)
        try runGit(["symbolic-ref", "HEAD", "refs/heads/main"], at: remote)

        try runGit(["clone", remote.path, writer.path], at: root)
        try runGit(["config", "user.name", "GitGatto Test"], at: writer)
        try runGit(["config", "user.email", "gitgatto@example.invalid"], at: writer)
        try "second\n".write(to: writer.appendingPathComponent("second.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "second.txt"], at: writer)
        try runGit(["commit", "-m", "Second commit"], at: writer)
        try runGit(["push", "origin", "main"], at: writer)

        let service = GitRepositoryService()
        #expect(try await service.loadLiveState(at: repository).behindCount == 0)

        try await service.fetchRemoteTracking(in: repository)

        let refreshed = try await service.loadLiveState(at: repository)
        #expect(refreshed.upstreamName == "origin/main")
        #expect(refreshed.aheadCount == 0)
        #expect(refreshed.behindCount == 1)
    }

    @Test("Reads a staged diff larger than the process pipe buffer", .timeLimit(.minutes(1)))
    func readsLargeStagedDiff() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoLargeDiffTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        let content = String(repeating: "0123456789abcdef\n", count: 30_000)
        try content.write(
            to: root.appendingPathComponent("large.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "large.txt"], at: root)

        let stagedDiff = try await GitRepositoryService().stagedDiff(in: root)

        #expect(stagedDiff.utf8.count > 400_000)
        #expect(stagedDiff.contains("large.txt"))
        #expect(stagedDiff.contains("+0123456789abcdef"))
    }

    @Test("First push creates an upstream on the available remote")
    func pushesNewBranch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoPushTests-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("working", isDirectory: true)
        let remote = root.appendingPathComponent("remote.git", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "--bare", remote.path], at: root)
        try runGit(["init", "-b", "main"], at: repository)
        try runGit(["config", "user.name", "GitGatto Test"], at: repository)
        try runGit(["config", "user.email", "gitgatto@example.invalid"], at: repository)
        try "push proof\n".write(to: repository.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], at: repository)
        try runGit(["commit", "-m", "Initial commit"], at: repository)
        try runGit(["remote", "add", "origin", remote.path], at: repository)

        try await GitRepositoryService().push(in: repository)

        #expect(try runGitOutput(["rev-parse", "--abbrev-ref", "@{upstream}"], at: repository) == "origin/main")
        #expect(!(try runGitOutput(["rev-parse", "refs/heads/main"], at: remote)).isEmpty)
    }

    @Test("Commits the staged draft and pushes it to the remote")
    func commitsAndPushesDraft() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoCommitPushTests-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("working", isDirectory: true)
        let remote = root.appendingPathComponent("remote.git", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "--bare", remote.path], at: root)
        try runGit(["init", "-b", "main"], at: repository)
        try runGit(["config", "user.name", "GitGatto Test"], at: repository)
        try runGit(["config", "user.email", "gitgatto@example.invalid"], at: repository)
        try runGit(["remote", "add", "origin", remote.path], at: repository)
        try "draft action\n".write(
            to: repository.appendingPathComponent("draft.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "draft.txt"], at: repository)

        try await GitRepositoryService().commitAndPush(
            message: "Add draft action",
            in: repository
        )

        #expect(try runGitOutput(["log", "-1", "--pretty=%s"], at: repository) == "Add draft action")
        #expect(try runGitOutput(["rev-parse", "HEAD"], at: repository)
            == runGitOutput(["rev-parse", "refs/heads/main"], at: remote))
        #expect(try runGitOutput(["status", "--porcelain"], at: repository).isEmpty)
    }

    @Test("Reports a push failure without losing the created commit")
    func preservesCommitWhenPushFails() async throws {
        let repository = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoCommitFailureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repository) }

        try runGit(["init", "-b", "main"], at: repository)
        try runGit(["config", "user.name", "GitGatto Test"], at: repository)
        try runGit(["config", "user.email", "gitgatto@example.invalid"], at: repository)
        try "local commit\n".write(
            to: repository.appendingPathComponent("local.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "local.txt"], at: repository)

        do {
            try await GitRepositoryService().commitAndPush(
                message: "Keep local commit",
                in: repository
            )
            Issue.record("Expected push to fail without a remote")
        } catch let error as GitRepositoryServiceError {
            guard case .pushFailedAfterCommit = error else {
                Issue.record("Expected pushFailedAfterCommit")
                return
            }
        }

        #expect(try runGitOutput(["log", "-1", "--pretty=%s"], at: repository) == "Keep local commit")
        #expect(try runGitOutput(["status", "--porcelain"], at: repository).isEmpty)
    }

    @Test("Staging a stale selection ignores an already staged deletion")
    func stagesStaleSelection() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoStaleStageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitGatto Test"], at: root)
        try runGit(["config", "user.email", "gitgatto@example.invalid"], at: root)
        try "original\n".write(to: root.appendingPathComponent("modified.txt"), atomically: true, encoding: .utf8)
        try "delete me\n".write(to: root.appendingPathComponent("deleted.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "modified.txt", "deleted.txt"], at: root)
        try runGit(["commit", "-m", "Initial commit"], at: root)

        try "changed\n".write(to: root.appendingPathComponent("modified.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: root.appendingPathComponent("deleted.txt"))

        let service = GitRepositoryService()
        let staleSnapshot = try await service.loadRepository(at: root)
        let stalePaths = staleSnapshot.unstagedChanges.map(\.path)
        #expect(Set(stalePaths) == ["modified.txt", "deleted.txt"])

        try runGit(["add", "--"] + stalePaths, at: root)
        try await service.stage(paths: stalePaths, in: root)

        let refreshedSnapshot = try await service.loadRepository(at: root)
        #expect(refreshedSnapshot.unstagedChanges.isEmpty)
        #expect(Set(refreshedSnapshot.stagedChanges.map(\.path)) == ["modified.txt", "deleted.txt"])
    }

    @Test("Discards staged and unstaged edits back to HEAD")
    func discardsTrackedChanges() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoDiscardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitGatto Test"], at: root)
        try runGit(["config", "user.email", "gitgatto@example.invalid"], at: root)
        let fileURL = root.appendingPathComponent("tracked.txt")
        try "original\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], at: root)
        try runGit(["commit", "-m", "Initial commit"], at: root)

        try "staged\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], at: root)
        try "unstaged too\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let service = GitRepositoryService()
        let change = try #require(await service.loadRepository(at: root).changes.first)
        try await service.discard(change, in: root)

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "original\n")
        #expect(try runGitOutput(["status", "--porcelain"], at: root).isEmpty)
    }

    @Test("Adds idempotent file, folder, and extension ignore rules")
    func writesGitIgnoreRules() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoIgnoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = GitRepositoryService()
        try await service.ignore(path: "Sources/App.swift", scope: .file, in: root)
        try await service.ignore(path: "Sources/App.swift", scope: .folder("Sources"), in: root)
        try await service.ignore(path: "Sources/App.swift", scope: .fileExtension, in: root)
        try await service.ignore(path: "Sources/App.swift", scope: .file, in: root)
        try await service.ignore(path: "notes file.md", scope: .file, in: root)

        let contents = try String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8)
        #expect(contents == "/Sources/App.swift\n/Sources/\n*.swift\n/notes\\ file.md\n")
    }

    private func runGit(_ arguments: [String], at url: URL) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", url.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw TestGitError(message: message)
        }
    }

    private func runGitOutput(_ arguments: [String], at url: URL) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", url.path] + arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw TestGitError(message: message)
        }
        return String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct TestGitError: Error {
    let message: String
}
