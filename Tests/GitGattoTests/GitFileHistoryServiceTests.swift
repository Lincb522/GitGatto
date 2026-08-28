import Foundation
import Testing
@testable import GitGatto

@Suite("File time machine")
struct GitFileHistoryServiceTests {
    @Test("Follows renames, loads historical content, blames working lines, and restores a version")
    func exercisesRealFileHistory() async throws {
        let root = try makeRepository(prefix: "GitGattoFileHistoryTests")
        defer { try? FileManager.default.removeItem(at: root) }

        let oldURL = root.appendingPathComponent("Sources/OldName.swift")
        try FileManager.default.createDirectory(at: oldURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "let value = 1\nlet stable = true\n".write(to: oldURL, atomically: true, encoding: .utf8)
        try runGit(["add", "Sources/OldName.swift"], at: root)
        try runGit(["commit", "-m", "Add original file"], at: root)

        try runGit(["mv", "Sources/OldName.swift", "Sources/Current.swift"], at: root)
        try runGit(["commit", "-m", "Rename source file"], at: root)

        let currentURL = root.appendingPathComponent("Sources/Current.swift")
        try "let value = 2\nlet stable = true\n".write(to: currentURL, atomically: true, encoding: .utf8)
        try runGit(["add", "Sources/Current.swift"], at: root)
        try runGit(["commit", "-m", "Change current value"], at: root)
        try "let value = 2\nlet stable = false\n".write(to: currentURL, atomically: true, encoding: .utf8)

        let service = GitFileHistoryService()
        let files = try await service.trackedFiles(in: root)
        let history = try await service.history(for: "Sources/Current.swift", in: root)

        #expect(files.contains { $0.path == "Sources/Current.swift" })
        #expect(history.map(\.subject) == ["Change current value", "Rename source file", "Add original file"])
        #expect(history.map(\.path) == ["Sources/Current.swift", "Sources/Current.swift", "Sources/OldName.swift"])

        let original = try #require(history.last)
        let document = try await service.document(
            for: "Sources/Current.swift",
            revision: original,
            in: root
        )
        #expect(document.content == "let value = 1\nlet stable = true\n")
        #expect(!document.diff.lines.isEmpty)

        let blame = try await service.blame(
            for: "Sources/Current.swift",
            revision: nil,
            in: root
        )
        #expect(blame.count == 2)
        #expect(blame[0].summary == "Change current value")
        #expect(blame[1].isUncommitted)

        try await service.restore(
            path: "Sources/Current.swift",
            from: original,
            in: root
        )
        #expect(try String(contentsOf: currentURL, encoding: .utf8) == "let value = 1\nlet stable = true\n")
        #expect(try runGitOutput(["status", "--porcelain", "--", "Sources/Current.swift"], at: root) == "M Sources/Current.swift")
    }

    private func makeRepository(prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: root)
        try runGit(["config", "user.name", "GitGatto Test"], at: root)
        try runGit(["config", "user.email", "gitgatto@example.invalid"], at: root)
        return root
    }

    private func runGit(_ arguments: [String], at directory: URL) throws {
        _ = try runGitProcess(arguments, at: directory)
    }

    private func runGitOutput(_ arguments: [String], at directory: URL) throws -> String {
        try runGitProcess(arguments, at: directory)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runGitProcess(_ arguments: [String], at directory: URL) throws -> String {
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
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw GitCommandError(arguments: arguments, exitCode: process.terminationStatus, message: output)
        }
        return output
    }
}
