import Foundation
import Testing
@testable import GitGatto

@Suite("Git worktree service")
struct GitWorktreeServiceTests {
    @Test("Parses porcelain worktree records without losing branch state")
    func parsesPorcelainRecords() {
        let payload = [
            "worktree /tmp/repository", "HEAD abcdef1234567890", "branch refs/heads/main", "",
            "worktree /tmp/repository-feature", "HEAD 1111111111111111", "branch refs/heads/feature/review", "locked", ""
        ].joined(separator: "\0")

        let records = GitWorktreeService.parsePorcelain(Data(payload.utf8))

        #expect(records.count == 2)
        #expect(records[0].branch == "main")
        #expect(records[1].branch == "feature/review")
        #expect(records[1].isLocked)
    }

    @Test("Creates, observes, and removes a real system Git worktree")
    func managesRealWorktree() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGatto-WorktreeProof-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        let destination = root.appendingPathComponent("repository-feature", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "--initial-branch=main"], at: repository)
        try runGit(["config", "user.name", "GitGatto Test"], at: repository)
        try runGit(["config", "user.email", "gitgatto@example.invalid"], at: repository)
        try Data("initial\n".utf8).write(to: repository.appendingPathComponent("README.md"))
        try runGit(["add", "README.md"], at: repository)
        try runGit(["commit", "-m", "Initial"], at: repository)

        let service = GitWorktreeService()
        try await service.createWorktree(
            branch: "feature/parallel-agent",
            startPoint: "HEAD",
            destination: destination,
            in: repository
        )
        try Data("changed\n".utf8).write(to: destination.appendingPathComponent("README.md"))

        let worktrees = try await service.worktrees(in: repository)
        let feature = try #require(worktrees.first { $0.branch == "feature/parallel-agent" })
        #expect(worktrees.first?.isMain == true)
        #expect(feature.path.standardizedFileURL == destination.standardizedFileURL)
        #expect(feature.changesCount == 1)

        try await service.removeWorktree(feature, force: true, in: repository)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try await service.worktrees(in: repository).count == 1)
    }

    private func runGit(_ arguments: [String], at directory: URL) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw GitHubServiceError.commandFailed(message)
        }
    }
}
