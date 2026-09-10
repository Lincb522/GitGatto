import Foundation
import Testing
@testable import GitGatto

@Suite("API Agent controlled tools")
struct AIAPIToolRunnerTests {
    @Test("Analysis can read but cannot modify a repository, including under /tmp")
    func readOnly() async throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let runner = AIAPIToolRunner(directory: directory, writableDirectories: [], allowsNetwork: false)
        let read = try await runner.execute(command(["/bin/cat", "sample.txt"]))
        #expect(read.content.contains("original"))
        let write = try await runner.execute(command(["/bin/sh", "-c", "printf changed > sample.txt"]))
        #expect(!write.content.contains("\"exit_code\":0"))
        #expect(try String(contentsOf: directory.appendingPathComponent("sample.txt"), encoding: .utf8) == "original")
        await #expect(throws: AIAPIError.pathDenied) { try await runner.execute(file("sample.txt", "wrong")) }
    }

    @Test("Edit mode writes inside the task, denies escapes and credential files")
    func edit() async throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let runner = AIAPIToolRunner(directory: directory, writableDirectories: [directory], allowsNetwork: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.appendingPathComponent("sample.txt").path)
        let output = try await runner.execute(file("sample.txt", "changed"))
        let mode = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("sample.txt").path)[.posixPermissions] as? Int
        #expect(mode == 0o755)
        #expect(output.event?.kind == .fileChange)
        #expect(try String(contentsOf: directory.appendingPathComponent("sample.txt"), encoding: .utf8) == "changed")
        await #expect(throws: AIAPIError.pathDenied) { try await runner.execute(file("../outside.txt", "wrong")) }
        await #expect(throws: AIAPIError.pathDenied) { try await runner.execute(file(".env", "fixture")) }
        let outside = directory.deletingLastPathComponent().appendingPathComponent("outside-\(UUID())")
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("escape"), withDestinationURL: outside)
        await #expect(throws: AIAPIError.pathDenied) { try await runner.execute(file("escape", "wrong")) }
        #expect(!FileManager.default.fileExists(atPath: outside.path))
    }

    @Test("Model commands do not inherit API keys or read project secrets")
    func secrets() async throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try "synthetic-private-value".write(to: directory.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        let runner = AIAPIToolRunner(directory: directory, writableDirectories: [directory], allowsNetwork: false)
        let output = try await runner.execute(command(["/bin/cat", ".env"]))
        #expect(!output.content.contains("synthetic-private-value"))
        let env = try await runner.execute(command(["/usr/bin/env"]))
        #expect(!env.content.contains("API_KEY="))
        #expect(!env.content.contains("TOKEN="))
    }

    @Test("Repository commands inspect actual Git state in the API sandbox")
    func gitInspection() async throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await GitCommandRunner().run(at: directory, arguments: ["init"],
            environment: ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_TEMPLATE_DIR": ""])
        let runner = AIAPIToolRunner(directory: directory, writableDirectories: [], allowsNetwork: false)
        let result = try await runner.execute(command(["/usr/bin/git", "status", "--porcelain"]))
        let data = try #require(result.content.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["exit_code"] as? Int == 0, "\(result.content)")
        #expect((object["stdout"] as? String)?.contains("sample.txt") == true)
    }

    @Test("Ancestor metadata access does not allow directory listings or sibling file reads")
    func ancestorMetadata() async throws {
        let parent = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".GitGatto-API-Ancestor-\(UUID())")
        let directory = parent.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let sibling = parent.appendingPathComponent("private-fixture.txt")
        try "synthetic-sibling-value".write(to: sibling, atomically: true, encoding: .utf8)
        let runner = AIAPIToolRunner(directory: directory, writableDirectories: [directory], allowsNetwork: false)
        for (arguments, allowed) in [
            (["/usr/bin/stat", "-f", "%HT", parent.path], true),
            (["/bin/ls", parent.path], false),
            (["/bin/cat", sibling.path], false)
        ] {
            let result = try await runner.execute(command(arguments))
            let object = try #require(JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any])
            #expect((object["exit_code"] as? Int == 0) == allowed, Comment(rawValue: result.content))
            #expect(!result.content.contains("synthetic-sibling-value"))
        }
    }

    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GitGattoAPITest-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try "original".write(to: url.appendingPathComponent("sample.txt"), atomically: true, encoding: .utf8)
        return url
    }
    private func command(_ args: [String]) throws -> AIAPIToolCall {
        try call("run_command", ["arguments": args])
    }
    private func file(_ path: String, _ content: String) throws -> AIAPIToolCall {
        try call("write_file", ["path": path, "content": content])
    }
    private func call(_ name: String, _ args: [String: Any]) throws -> AIAPIToolCall {
        AIAPIToolCall(id: "fixture", type: "function", function: .init(name: name,
            arguments: String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self)))
    }
}
