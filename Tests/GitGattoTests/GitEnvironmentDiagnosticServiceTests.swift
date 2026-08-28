import Foundation
import Testing
@testable import GitGatto

@Suite("Git environment diagnostics")
struct GitEnvironmentDiagnosticServiceTests {
    @Test("Checks a real repository and repairs a hook execute permission")
    func diagnosesRepositoryEnvironment() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitGatto Test"], at: root)
        try runGit(["config", "user.email", "gitgatto@example.invalid"], at: root)
        try "*.bin filter=lfs diff=lfs merge=lfs -text\n".write(
            to: root.appendingPathComponent(".gitattributes"),
            atomically: true,
            encoding: .utf8
        )
        try "content\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", ".gitattributes", "README.md"], at: root)
        try runGit(["commit", "-m", "Create diagnostic fixture"], at: root)

        let hooksDirectory = root.appendingPathComponent(".git/hooks", isDirectory: true)
        let hookURL = hooksDirectory.appendingPathComponent("pre-commit")
        try "#!/bin/sh\nexit 0\n".write(to: hookURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: hookURL.path)

        let service = GitEnvironmentDiagnosticService()
        let first = try await service.diagnose(repositoryURL: root)

        #expect(first.gitExecutablePath == "/usr/bin/git")
        #expect(first.gitVersion.hasPrefix("git version"))
        #expect(first.objectDatabaseHealthy)
        #expect(first.identityStatus == .passed)
        #expect(first.usesLFS)
        let hook = try #require(first.hooks.first { $0.name == "pre-commit" })
        #expect(!hook.isExecutable)
        #expect(first.hooksStatus == .attention)

        try await service.makeHookExecutable(hook)
        let repaired = try await service.diagnose(repositoryURL: root)
        #expect(repaired.hooks.first { $0.name == "pre-commit" }?.isExecutable == true)
    }

    private func runGit(_ arguments: [String], at directory: URL) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, value in value }
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitCommandError(
                arguments: arguments,
                exitCode: process.terminationStatus,
                message: String(decoding: data, as: UTF8.self)
            )
        }
    }
}
