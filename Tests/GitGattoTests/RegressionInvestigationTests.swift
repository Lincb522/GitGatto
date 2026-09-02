import Foundation
import Testing
@testable import GitGatto

@Suite("Regression investigation")
struct RegressionInvestigationTests {
    @Test("Finds the first bad commit in an isolated worktree")
    func findsFirstBadCommit() async throws {
        let fixture = try RegressionRepositoryFixture()
        defer { fixture.remove() }
        let workspaceRoot = fixture.root.appendingPathComponent("investigations", isDirectory: true)
        let runtime = RegressionInvestigationRuntime(workspaceRoot: workspaceRoot)

        let prepared = try await runtime.prepare(
            repositoryURL: fixture.repository,
            goodRevision: fixture.goodSHA,
            badRevision: fixture.badSHA,
            verificationCommand: "grep -qx good state.txt",
            mode: .automatic
        )
        #expect(prepared.workspaceURL != nil)
        #expect(prepared.workspaceURL?.standardizedFileURL != fixture.repository.standardizedFileURL)

        let recorder = RegressionUpdateRecorder()
        let completed = try await runtime.runAutomatic(prepared) { update in
            await recorder.append(update)
        }

        #expect(completed.status == .culpritFound)
        #expect(completed.culprit?.sha == fixture.culpritSHA)
        #expect(!completed.probes.isEmpty)
        #expect(completed.bisectLog?.contains(fixture.culpritSHA) == true)
        #expect(try fixture.git(["rev-parse", "HEAD"]) == fixture.badSHA)
        #expect(try fixture.git(["symbolic-ref", "--short", "HEAD"]) == "main")
        #expect(try fixture.git(["status", "--porcelain"]).isEmpty)
        #expect(try fixture.worktreeCount() == 2)
        #expect(await recorder.count >= 2)

        let cleaned = try await runtime.cleanup(completed)
        #expect(cleaned.workspacePath == nil)
        #expect(cleaned.culprit?.sha == fixture.culpritSHA)
        #expect(try fixture.worktreeCount() == 1)
    }

    @Test("Manual verdict advances the same durable bisect session")
    func supportsManualVerdict() async throws {
        let fixture = try RegressionRepositoryFixture()
        defer { fixture.remove() }
        let runtime = RegressionInvestigationRuntime(
            workspaceRoot: fixture.root.appendingPathComponent("manual", isDirectory: true)
        )
        var investigation = try await runtime.prepare(
            repositoryURL: fixture.repository,
            goodRevision: fixture.goodSHA,
            badRevision: fixture.badSHA,
            verificationCommand: "",
            mode: .manual
        )
        #expect(investigation.status == .awaitingManualVerdict)
        #expect(investigation.currentCommit?.sha == fixture.culpritSHA)

        investigation = try await runtime.recordManual(.bad, in: investigation)
        #expect(investigation.status == .culpritFound)
        #expect(investigation.culprit?.sha == fixture.culpritSHA)
        #expect(investigation.probes.first?.exitCode == nil)
        #expect(investigation.probes.first?.verdict == .bad)
        _ = try await runtime.cleanup(investigation)
    }

    @Test("Paused automatic investigation resumes without rebuilding its worktree")
    func pausesAndResumes() async throws {
        let fixture = try RegressionRepositoryFixture()
        defer { fixture.remove() }
        let runtime = RegressionInvestigationRuntime(
            workspaceRoot: fixture.root.appendingPathComponent("resume", isDirectory: true)
        )
        let prepared = try await runtime.prepare(
            repositoryURL: fixture.repository,
            goodRevision: fixture.goodSHA,
            badRevision: fixture.badSHA,
            verificationCommand: "grep -qx good state.txt",
            mode: .automatic
        )
        let workspacePath = prepared.workspacePath
        let paused = await runtime.pause(prepared)
        #expect(paused.status == .paused)
        let resumed = try await runtime.resume(paused)
        #expect(resumed.status == .running)
        #expect(resumed.workspacePath == workspacePath)

        let completed = try await runtime.runAutomatic(resumed) { _ in }
        #expect(completed.culprit?.sha == fixture.culpritSHA)
        _ = try await runtime.cleanup(completed)
    }

    @Test("Verifies an isolated fix, pushes its branch, and records the created PR")
    func publishesVerifiedFix() async throws {
        let fixture = try RegressionRepositoryFixture()
        defer { fixture.remove() }
        let remote = try fixture.addBareOrigin()
        let tools = fixture.root.appendingPathComponent("tools", isDirectory: true)
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let fakeGitHubCLI = tools.appendingPathComponent("gh")
        try Data("#!/bin/sh\necho https://github.com/example/repository/pull/17\n".utf8)
            .write(to: fakeGitHubCLI)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeGitHubCLI.path
        )

        let runtime = RegressionInvestigationRuntime(
            commandRunner: RegressionCommandRunner(additionalSearchPaths: [tools.path]),
            workspaceRoot: fixture.root.appendingPathComponent("publish", isDirectory: true)
        )
        let prepared = try await runtime.prepare(
            repositoryURL: fixture.repository,
            goodRevision: fixture.goodSHA,
            badRevision: fixture.badSHA,
            verificationCommand: "grep -qx good state.txt",
            mode: .automatic
        )
        let located = try await runtime.runAutomatic(prepared) { _ in }
        var fixing = try await runtime.prepareFix(located)
        let workspace = try #require(fixing.workspaceURL)
        try Data("good\n".utf8).write(to: workspace.appendingPathComponent("state.txt"))
        fixing = await runtime.markAgentFixCompleted(fixing, summary: "Restored the expected state.")
        let verified = try await runtime.verifyFix(fixing)
        #expect(verified.status == .fixVerified)
        #expect(verified.fixVerification?.passed == true)
        #expect(try fixture.git(["show", "HEAD:state.txt"]) == "bad")

        let published = try await runtime.publishFix(
            verified,
            title: "fix: restore repository state",
            body: "Regression evidence attached."
        )
        #expect(published.status == .completed)
        #expect(published.pullRequestURL?.absoluteString == "https://github.com/example/repository/pull/17")
        #expect(published.fixCommitSHA != nil)
        let branch = try #require(published.fixBranch)
        #expect(
            try fixture.git([
                "--git-dir", remote.path,
                "show-ref", "--verify", "refs/heads/\(branch)"
            ]).contains("refs/heads/\(branch)")
        )
        #expect(try fixture.git(["rev-parse", "HEAD"]) == fixture.badSHA)
        _ = try await runtime.cleanup(published)
    }

    @Test("Persists recovery state and evidence atomically")
    func persistsEvidence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGatto-RegressionStore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("investigations.json")
        let store = RegressionInvestigationStore(fileURL: fileURL)
        let investigation = RegressionInvestigation(
            repositoryPath: "/tmp/repository",
            repositoryName: "repository",
            sourceBranch: "main",
            sourceHeadSHA: String(repeating: "a", count: 40),
            goodRevision: "v1.0.0",
            badRevision: "HEAD",
            goodSHA: String(repeating: "b", count: 40),
            badSHA: String(repeating: "a", count: 40),
            verificationCommand: "swift test",
            mode: .automatic,
            status: .paused,
            workspacePath: "/tmp/worktree",
            candidateCount: 18
        )

        try await store.save([investigation])
        let loaded = try #require(try await store.load().first)
        #expect(loaded.id == investigation.id)
        #expect(loaded.repositoryPath == investigation.repositoryPath)
        #expect(loaded.status == .paused)
        #expect(loaded.workspacePath == investigation.workspacePath)
        #expect(loaded.verificationCommand == investigation.verificationCommand)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("Parses only Git's first bad commit result")
    func parsesFirstBadCommit() {
        let sha = "0123456789abcdef0123456789abcdef01234567"
        #expect(
            RegressionInvestigationRuntime.firstBadCommitSHA(
                in: "\(sha) is the first bad commit\ncommit \(sha)"
            ) == sha
        )
        #expect(RegressionInvestigationRuntime.firstBadCommitSHA(in: "Bisecting: 2 revisions left") == nil)
    }

    @Test("Removes credentials from stored command evidence")
    func redactsEvidence() {
        let output = RegressionInvestigationRuntime.evidenceOutput(
            "authorization: Bearer secret-value\nhttps://user:password@example.com/repo\nghp_abcdefghijklmnopqrstuvwxyz"
        )
        #expect(!output.contains("secret-value"))
        #expect(!output.contains("user:password"))
        #expect(!output.contains("ghp_abcdefghijklmnopqrstuvwxyz"))
        #expect(output.contains("***"))
    }
}

private actor RegressionUpdateRecorder {
    private var updates: [RegressionInvestigation] = []

    var count: Int { updates.count }

    func append(_ update: RegressionInvestigation) {
        updates.append(update)
    }
}

private final class RegressionRepositoryFixture {
    let root: URL
    let repository: URL
    let goodSHA: String
    let culpritSHA: String
    let badSHA: String

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGatto-RegressionProof-\(UUID().uuidString)", isDirectory: true)
        repository = root.appendingPathComponent("repository", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try Self.git(["init", "--initial-branch=main"], at: repository)
        try Self.git(["config", "user.name", "GitGatto Test"], at: repository)
        try Self.git(["config", "user.email", "gitgatto@example.invalid"], at: repository)

        try Data("good\n".utf8).write(to: repository.appendingPathComponent("state.txt"))
        try Self.git(["add", "state.txt"], at: repository)
        try Self.git(["commit", "-m", "Known good"], at: repository)
        goodSHA = try Self.git(["rev-parse", "HEAD"], at: repository)

        try Data("bad\n".utf8).write(to: repository.appendingPathComponent("state.txt"))
        try Self.git(["commit", "-am", "Introduce regression"], at: repository)
        culpritSHA = try Self.git(["rev-parse", "HEAD"], at: repository)

        try Data("unrelated\n".utf8).write(to: repository.appendingPathComponent("notes.txt"))
        try Self.git(["add", "notes.txt"], at: repository)
        try Self.git(["commit", "-m", "Later unrelated change"], at: repository)
        badSHA = try Self.git(["rev-parse", "HEAD"], at: repository)
    }

    func git(_ arguments: [String]) throws -> String {
        try Self.git(arguments, at: repository)
    }

    func worktreeCount() throws -> Int {
        let output = try git(["worktree", "list", "--porcelain"])
        return output.split(separator: "\n").filter { $0.hasPrefix("worktree ") }.count
    }

    func addBareOrigin() throws -> URL {
        let remote = root.appendingPathComponent("origin.git", isDirectory: true)
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try Self.git(["init", "--bare"], at: remote)
        _ = try git(["remote", "add", "origin", remote.path])
        _ = try git(["push", "--set-upstream", "origin", "main"])
        return remote
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private static func git(_ arguments: [String], at directory: URL) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw RegressionInvestigationError.commandFailed(process.terminationStatus, output)
        }
        return output
    }
}
