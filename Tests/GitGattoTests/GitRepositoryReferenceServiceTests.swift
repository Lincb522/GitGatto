import AppKit
import Foundation
import SwiftUI
@testable import GitGatto
import Testing

@Suite("Repository reference tools", .serialized)
struct GitRepositoryReferenceServiceTests {
    @Test("Loads branches, tags, remotes, and reflog from a real repository")
    func loadsReferenceSnapshot() async throws {
        let fixture = try makeReferenceRepository()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try referenceGit(["branch", "feature/topic"], at: fixture.repository)
        try referenceGit(["tag", "-a", "v1.0.0", "-m", "First release"], at: fixture.repository)
        try referenceGit(["remote", "add", "origin", fixture.remote.path], at: fixture.repository)
        try referenceGit(["push", "-u", "origin", "main"], at: fixture.repository)

        let snapshot = try await GitRepositoryService().referenceSnapshot(in: fixture.repository)

        #expect(snapshot.references.contains { $0.name == "feature/topic" && $0.kind == .localBranch })
        #expect(snapshot.references.contains { $0.name == "origin/main" && $0.kind == .remoteBranch })
        #expect(snapshot.references.first?.kind == .head)
        #expect(snapshot.tags.first(where: { $0.name == "v1.0.0" })?.isAnnotated == true)
        #expect(snapshot.remotes.first?.name == "origin")
        #expect(snapshot.reflog.contains { $0.subject.contains("commit") })
    }

    @Test("Compares divergent references without treating revisions as command options")
    func comparesReferences() async throws {
        let fixture = try makeReferenceRepository()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try referenceGit(["switch", "-c", "feature/compare"], at: fixture.repository)
        try "feature\n".write(
            to: fixture.repository.appendingPathComponent("feature.txt"),
            atomically: true,
            encoding: .utf8
        )
        try referenceGit(["add", "feature.txt"], at: fixture.repository)
        try referenceGit(["commit", "-m", "Add feature"], at: fixture.repository)

        let document = try await GitRepositoryService().compare(
            from: "main",
            to: "feature/compare",
            mode: .commonAncestor,
            in: fixture.repository
        )

        #expect(document.lines.contains { $0.text.contains("feature.txt") })
        #expect(document.lines.contains { $0.kind == .addition && $0.text.contains("feature") })
    }

    @Test("Manages local branches, tags, and remote configuration")
    func managesReferencesAndRemotes() async throws {
        let fixture = try makeReferenceRepository()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = GitRepositoryService()

        try await service.addRemote(named: "origin", fetchURL: fixture.remote.path, pushURL: nil, in: fixture.repository)
        try await service.createBranch(named: "feature/new", from: "HEAD", checksOut: false, in: fixture.repository)
        try await service.renameBranch(from: "feature/new", to: "feature/renamed", in: fixture.repository)
        try await service.createTag(named: "preview-1", at: "HEAD", message: "Preview", signed: false, in: fixture.repository)
        try await service.pushTag(named: "preview-1", to: "origin", in: fixture.repository)
        try await service.testRemote(named: "origin", in: fixture.repository)

        var snapshot = try await service.referenceSnapshot(in: fixture.repository)
        #expect(snapshot.references.contains { $0.name == "feature/renamed" && $0.kind == .localBranch })
        #expect(snapshot.tags.contains { $0.name == "preview-1" })
        #expect(snapshot.remotes.first?.fetchURL == fixture.remote.path)

        try await service.updateRemote(
            named: "origin",
            newName: "backup",
            fetchURL: fixture.remote.path,
            pushURL: fixture.remote.path,
            in: fixture.repository
        )
        try await service.deleteRemoteTag(named: "preview-1", from: "backup", in: fixture.repository)
        try await service.deleteTag(named: "preview-1", in: fixture.repository)
        try await service.deleteBranch(named: "feature/renamed", force: false, in: fixture.repository)
        snapshot = try await service.referenceSnapshot(in: fixture.repository)
        #expect(snapshot.tags.isEmpty)
        #expect(!snapshot.references.contains { $0.name == "feature/renamed" })
        #expect(snapshot.remotes.map(\.name) == ["backup"])
        try await service.deleteRemote(named: "backup", in: fixture.repository)
        #expect(try await service.referenceSnapshot(in: fixture.repository).remotes.isEmpty)
    }

    @Test("Restores an unreachable commit from reflog as a new branch")
    func restoresReflogEntry() async throws {
        let fixture = try makeReferenceRepository()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try "lost\n".write(to: fixture.repository.appendingPathComponent("lost.txt"), atomically: true, encoding: .utf8)
        try referenceGit(["add", "lost.txt"], at: fixture.repository)
        try referenceGit(["commit", "-m", "Temporary work"], at: fixture.repository)
        let lostHash = try referenceGitOutput(["rev-parse", "HEAD"], at: fixture.repository)
        try referenceGit(["reset", "--hard", "HEAD^"], at: fixture.repository)

        let service = GitRepositoryService()
        let snapshot = try await service.referenceSnapshot(in: fixture.repository)
        let entry = try #require(snapshot.reflog.first { $0.hash == lostHash })
        try await service.restoreReflogEntry(entry, as: "recovered/work", in: fixture.repository)

        #expect(try referenceGitOutput(["rev-parse", "recovered/work"], at: fixture.repository) == lostHash)
        #expect(try referenceGitOutput(["branch", "--show-current"], at: fixture.repository) == "main")
    }

    @Test("Rewords and folds local commits while blocking published history")
    func rewritesLocalHistorySafely() async throws {
        let fixture = try makeReferenceRepository()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try commitFile("second.txt", contents: "second\n", message: "Second", in: fixture.repository)
        let secondHash = try referenceGitOutput(["rev-parse", "HEAD"], at: fixture.repository)
        try commitFile("third.txt", contents: "third\n", message: "Third", in: fixture.repository)

        let service = GitRepositoryService()
        let reword = try await service.rewriteCommit(
            secondHash,
            mode: .reword,
            newMessage: "Second revised",
            in: fixture.repository
        )
        guard case .completed = reword else {
            Issue.record("Expected reword to complete")
            return
        }
        #expect(try referenceGitOutput(["log", "--format=%s"], at: fixture.repository).contains("Second revised"))

        let currentHead = try referenceGitOutput(["rev-parse", "HEAD"], at: fixture.repository)
        let fold = try await service.rewriteCommit(currentHead, mode: .fixup, newMessage: nil, in: fixture.repository)
        guard case .completed = fold else {
            Issue.record("Expected fixup to complete")
            return
        }
        #expect(try referenceGitOutput(["rev-list", "--count", "HEAD"], at: fixture.repository) == "2")

        try await service.addRemote(named: "origin", fetchURL: fixture.remote.path, pushURL: nil, in: fixture.repository)
        try referenceGit(["push", "-u", "origin", "main"], at: fixture.repository)
        let published = try referenceGitOutput(["rev-parse", "HEAD"], at: fixture.repository)
        do {
            _ = try await service.rewriteCommit(published, mode: .reword, newMessage: "Blocked", in: fixture.repository)
            Issue.record("Expected a published commit rewrite to be blocked")
        } catch let error as GitReferenceServiceError {
            #expect(error == .publishedCommitCannotBeRewritten)
        }
    }

    @Test("Reorders the complete unpublished suffix of a linear branch")
    func reordersLocalCommits() async throws {
        let fixture = try makeReferenceRepository()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try commitFile("second.txt", contents: "second\n", message: "Second", in: fixture.repository)
        let second = try referenceGitOutput(["rev-parse", "HEAD"], at: fixture.repository)
        try commitFile("third.txt", contents: "third\n", message: "Third", in: fixture.repository)
        let third = try referenceGitOutput(["rev-parse", "HEAD"], at: fixture.repository)

        let transition = try await GitRepositoryService().reorderCommits([third, second], in: fixture.repository)
        guard case .completed = transition else {
            Issue.record("Expected reorder to complete")
            return
        }
        let subjects = try referenceGitOutput(["log", "--reverse", "--format=%s"], at: fixture.repository)
            .split(whereSeparator: \Character.isNewline).map(String.init)
        #expect(subjects == ["Initial", "Third", "Second"])
    }

    @MainActor
    @Test("Reference and history workspaces render with real repository data")
    func rendersReferenceWorkspaces() async throws {
        let fixture = try makeReferenceRepository()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try referenceGit(["branch", "feature/topic"], at: fixture.repository)
        try referenceGit(["tag", "-a", "v1.0.0", "-m", "First release"], at: fixture.repository)
        try referenceGit(["remote", "add", "origin", fixture.remote.path], at: fixture.repository)
        try referenceGit(["push", "-u", "origin", "main"], at: fixture.repository)
        try commitFile("second.txt", contents: "second\n", message: "Second", in: fixture.repository)

        let model = WorkspaceViewModel(service: GitRepositoryService())
        await model.openRepository(fixture.repository)
        model.refreshGitTools()
        try await waitUntil {
            !model.isLoadingGitTools && !model.gitReferenceSnapshot.references.isEmpty
        }

        let branches = BranchesWorkspaceView(model: model)
            .frame(width: 1_160, height: 700)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
            .environment(\.colorScheme, .light)
        let history = HistoryWorkspaceView(model: model)
            .frame(width: 1_160, height: 700)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
            .environment(\.colorScheme, .dark)

        let branchData = try render(branches, width: 1_160, height: 700)
        let historyData = try render(history, width: 1_160, height: 700)
        #expect(branchData.count > 20_000)
        #expect(historyData.count > 20_000)

        if let outputDirectory = ProcessInfo.processInfo.environment["GITGATTO_GIT_TOOLS_UI_SNAPSHOT_DIRECTORY"] {
            let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try branchData.write(to: directory.appendingPathComponent("branches.png"), options: .atomic)
            try historyData.write(to: directory.appendingPathComponent("history.png"), options: .atomic)
        }
    }

    @MainActor
    @Test("Returning to branches refreshes references changed outside the app")
    func refreshesReferencesOnNavigation() async throws {
        let fixture = try makeReferenceRepository()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = WorkspaceViewModel(service: GitRepositoryService())
        model.appPreferences.monitoringEngineEnabled = false
        model.appPreferences.repositoryBackupEnabled = false
        await model.openRepository(fixture.repository)
        model.selectedSection = .branches
        try await waitUntil {
            !model.isLoadingGitTools && !model.gitReferenceSnapshot.references.isEmpty
        }
        model.selectedSection = .github
        try referenceGit(["tag", "created-while-away"], at: fixture.repository)
        model.selectedSection = .branches
        try await waitUntil {
            !model.isLoadingGitTools
                && model.gitReferenceSnapshot.tags.contains { $0.name == "created-while-away" }
        }
        model.selectedSection = .github
    }

    @MainActor
    private func render<Content: View>(_ content: Content, width: CGFloat, height: CGFloat) throws -> Data {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        let representation = try #require(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        #expect(representation.pixelsWide == Int(width))
        #expect(representation.pixelsHigh == Int(height))
        return try #require(representation.representation(using: .png, properties: [:]))
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(60),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for Git reference workspace state")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func makeReferenceRepository() throws -> (root: URL, repository: URL, remote: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoReferenceTests-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("working", isDirectory: true)
        let remote = root.appendingPathComponent("remote.git", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try referenceGit(["init", "--bare", remote.path], at: root)
        try referenceGit(["init", "-b", "main"], at: repository)
        try referenceGit(["config", "user.name", "GitGatto Test"], at: repository)
        try referenceGit(["config", "user.email", "gitgatto@example.invalid"], at: repository)
        try commitFile("README.md", contents: "base\n", message: "Initial", in: repository)
        try referenceGit(["symbolic-ref", "HEAD", "refs/heads/main"], at: remote)
        return (root, repository, remote)
    }

    private func commitFile(_ path: String, contents: String, message: String, in repository: URL) throws {
        try contents.write(to: repository.appendingPathComponent(path), atomically: true, encoding: .utf8)
        try referenceGit(["add", "--", path], at: repository)
        try referenceGit(["commit", "-m", message], at: repository)
    }

    private func referenceGit(_ arguments: [String], at url: URL) throws {
        _ = try runReferenceGit(arguments, at: url)
    }

    private func referenceGitOutput(_ arguments: [String], at url: URL) throws -> String {
        try runReferenceGit(arguments, at: url)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runReferenceGit(_ arguments: [String], at url: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", url.path] + arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw ReferenceGitTestError(message: stderr.isEmpty ? stdout : stderr)
        }
        return stdout
    }
}

private struct ReferenceGitTestError: Error {
    let message: String
}
