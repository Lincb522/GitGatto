import Foundation
import Testing
@testable import GitGatto

@Suite("Product workflow optimization", .serialized)
struct ProductOptimizationTests {
    @Test("Only monitoring-related preferences restart the engine")
    func monitoringImpact() {
        let previous = AppPreferences()
        var next = previous
        next.language = .german
        next.commitDraftDetail = .complete
        #expect(!next.requiresMonitoringRestart(comparedTo: previous))
        next.liveRefreshEnabled.toggle()
        #expect(next.requiresMonitoringRestart(comparedTo: previous))
        next = previous
        next.repositoryBackupDirectoryPath = "/tmp/fixture-backup"
        #expect(next.requiresMonitoringRestart(comparedTo: previous))
        next = previous
        next.defaultTranslationTarget = .english
        #expect(!next.requiresMonitoringRestart(comparedTo: previous))
    }

    @Test("Help matches article content and retains specific destinations")
    func helpSearch() {
        #expect(HelpTopic.projectCommands.matches(L10n.text(HelpTopic.projectCommands.titleKey)))
        #expect(!HelpTopic.projectCommands.matches("no-such-fixture-topic"))
        #expect(HelpTopic.projectCommands.projectTool == .commands)
        #expect(HelpTopic.recovery.workspaceSection == .recovery)
        #expect(HelpTopic.gettingStarted.matches("  "))
    }

    @Test("Conflict selections affect one block and preserve CRLF and surrounding edits")
    func conflictBlocks() throws {
        let text = "before\r\n<<<<<<< HEAD\r\nours\r\n||||||| base\r\nbase\r\n=======\r\ntheirs\r\n>>>>>>> other\r\nbetween\r\n<<<<<<< HEAD\r\nsecond\r\n=======\r\nnext\r\n>>>>>>> other\r\nafter"
        let blocks = ConflictBlock.parse(text)
        #expect(blocks.count == 2)
        #expect(blocks[0].base == "base\r\n")
        let result = try #require(ConflictBlock.resolving(blocks[0].id, using: .both, in: text))
        #expect(result.hasPrefix("before\r\nours\r\ntheirs\r\nbetween\r\n"))
        #expect(result.hasSuffix("after"))
        let last = try #require(ConflictBlock.parse(result).first)
        #expect(ConflictBlock.resolving(last.id, using: .incoming, in: result) == "before\r\nours\r\ntheirs\r\nbetween\r\nnext\r\nafter")
        #expect(ConflictBlock.parse("<<<<<<< HEAD\na\n=======\nb").isEmpty)
        #expect(ConflictBlock.parse("<<<<<<< HEAD\n<<<<<<< nested\na\n=======\nb\n>>>>>>> other").isEmpty)
    }

    @Test("Streaming completion requires a terminator and assembles tool arguments before execution")
    func streamCompletion() throws {
        var decoder = AIAPIStreamDecoder()
        func chunk(_ delta: [String: Any], reason: String? = nil) throws -> String {
            var choice: [String: Any] = ["index": 0, "delta": delta]
            if let reason { choice["finish_reason"] = reason }
            return "data: " + String(decoding: try JSONSerialization.data(withJSONObject: ["choices": [choice]]), as: UTF8.self)
        }
        #expect(try decoder.consume(chunk(["content": "hello", "reasoning_content": "private reasoning"])) == "hello")
        #expect(try decoder.consume(chunk(["tool_calls": [["index": 0, "id": "call-1", "function": ["name": "read_file", "arguments": "{\"path\":"]]]])) == nil)
        _ = try decoder.consume(chunk(["tool_calls": [["index": 0, "function": ["arguments": "\"README.md\"}"]]]], reason: "tool_calls"))
        #expect(throws: AIAPIError.invalidResponse) { try decoder.response() }
        _ = try decoder.consume("data: [DONE]")
        let object = try #require(JSONSerialization.jsonObject(with: decoder.response()) as? [String: Any])
        let choice = try #require((object["choices"] as? [[String: Any]])?.first)
        let message = try #require(choice["message"] as? [String: Any])
        #expect(message["content"] as? String == "hello")
        let function = try #require((message["tool_calls"] as? [[String: Any]])?.first?["function"] as? [String: String])
        #expect(function["arguments"] == "{\"path\":\"README.md\"}")
        #expect(throws: AIAPIError.invalidResponse) { try decoder.consume("data: {}") }
        var malformed = AIAPIStreamDecoder()
        #expect(throws: AIAPIError.invalidResponse) { try malformed.consume("data: invalid") }
    }

    @MainActor @Test("Task history retains pending work, caps completed records, and never serializes authorization")
    func taskPersistence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitGatto-task-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DevelopmentToolTaskStore(url: root.appendingPathComponent("tasks.json"))
        let date = Date(timeIntervalSince1970: 0)
        var records = (0..<230).map { i in DevelopmentToolTaskRecord(id: UUID(), toolID: "git", operation: .install,
            createdAt: date.addingTimeInterval(Double(i)), updatedAt: date, state: .completed) }
        let pending = DevelopmentToolTaskRecord(id: UUID(), toolID: "node", operation: .upgrade,
            createdAt: date, updatedAt: date, state: .running)
        records.insert(pending, at: 0)
        try store.save(records)
        let loaded = try store.load()
        #expect(loaded.count == 201)
        #expect(loaded.first == pending)
        let data = try Data(contentsOf: store.url)
        let objects = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(objects.allSatisfy { Set($0.keys).isSubset(of: ["id", "toolID", "operation", "createdAt", "updatedAt", "state", "version", "executablePath"]) })
        try Data("corrupt".utf8).write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
        let model = DeveloperToolsViewModel(taskStore: store)
        model.install(try #require(DevelopmentTool.catalog.first))
        #expect(model.activeOperations.isEmpty)
        #expect(model.taskPersistenceError != nil)
        #expect(try String(contentsOf: store.url, encoding: .utf8) == "corrupt")
    }

    @Test("Partial staging preserves EOF markers, CRLF, empty files and insertion-only hunks")
    func partialIndexEdges() async throws {
        let cases = [("", "first\n"), ("first\n", ""), ("old", "new"), ("same\nold", "same\nnew\n"),
                     ("one\r\ntwo\r\n", "one\r\nnew\r\ntwo\r\n"), ("one\ntwo\n", "zero\none\ntwo\nlast\n")]
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("GitGatto-index-edges-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = GitCommandRunner()
        let environment = ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_TEMPLATE_DIR": "",
            "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
            "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.invalid"]
        for (index, pair) in cases.enumerated() {
            let directory = root.appendingPathComponent(String(index))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            @discardableResult func git(_ arguments: [String]) async throws -> String {
                try await runner.run(at: directory, arguments: arguments, environment: environment).text
            }
            try await git(["init", "-b", "main"])
            try await git(["config", "core.autocrlf", "false"])
            let file = directory.appendingPathComponent("file.txt")
            try pair.0.write(to: file, atomically: true, encoding: .utf8)
            try await git(["add", "file.txt"])
            try await git(["-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-m", "fixture"])
            try pair.1.write(to: file, atomically: true, encoding: .utf8)
            let service = GitRepositoryService()
            let change = WorkingTreeChange(path: "file.txt", originalPath: nil, indexStatus: .unmodified, workTreeStatus: .modified)
            let document = try await service.diff(for: change, in: directory)
            let ids = Set(document.lines.filter { $0.kind == .addition || $0.kind == .deletion }.map(\.id))
            try await service.stageSelection(ids, document: document, change: change, in: directory)
            #expect(try await git(["show", ":file.txt"]) == pair.1, "Case \(index)")
            let staged = WorkingTreeChange(path: "file.txt", originalPath: nil, indexStatus: .modified, workTreeStatus: .unmodified)
            let reverse = try await service.diff(for: staged, in: directory)
            try await service.stageSelection(Set(reverse.lines.filter { $0.kind == .addition || $0.kind == .deletion }.map(\.id)),
                document: reverse, change: staged, in: directory)
            #expect(try await git(["show", ":file.txt"]) == pair.0, "Case \(index)")
            #expect(try String(contentsOf: file, encoding: .utf8) == pair.1, "Case \(index)")
        }
    }

    @Test("Line staging and unstaging preserve unrelated index and worktree data; stale diffs are rejected")
    func partialIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitGatto-partial-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = GitCommandRunner()
        let env = ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_TEMPLATE_DIR": "",
                   "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
                   "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.invalid"]
        @discardableResult func git(_ arguments: [String]) async throws -> String {
            try await runner.run(at: root, arguments: arguments, environment: env).text
        }
        try await git(["init", "-b", "main"])
        let path = "测试 file.txt"
        let file = root.appendingPathComponent(path)
        let before = (1...40).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try before.write(to: file, atomically: true, encoding: .utf8)
        try "other\n".write(to: root.appendingPathComponent("other.txt"), atomically: true, encoding: .utf8)
        try await git(["add", "."])
        try await git(["-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-m", "fixture"])
        let after = before.replacingOccurrences(of: "line 2\n", with: "changed two\n").replacingOccurrences(of: "line 32\n", with: "changed thirty-two\n")
        try after.write(to: file, atomically: true, encoding: .utf8)
        try "already staged\n".write(to: root.appendingPathComponent("other.txt"), atomically: true, encoding: .utf8)
        try await git(["add", "other.txt"])
        let service = GitRepositoryService()
        let change = WorkingTreeChange(path: path, originalPath: nil, indexStatus: .unmodified, workTreeStatus: .modified)
        let doc = try await service.diff(for: change, in: root)
        let selected = Set(doc.lines.filter { $0.text == "-line 2" || $0.text == "+changed two" }.map(\.id))
        try await service.stageSelection(selected, document: doc, change: change, in: root)
        #expect(try await git(["show", ":" + path]) == before.replacingOccurrences(of: "line 2\n", with: "changed two\n"))
        #expect(try await git(["show", ":other.txt"]) == "already staged\n")
        #expect(try String(contentsOf: file, encoding: .utf8) == after)
        await #expect(throws: PartialDiffError.changed) { try await service.stageSelection(selected, document: doc, change: change, in: root) }
        let staged = WorkingTreeChange(path: path, originalPath: nil, indexStatus: .modified, workTreeStatus: .unmodified)
        let stagedDoc = try await service.diff(for: staged, in: root)
        let reverseIDs = Set(stagedDoc.lines.filter { $0.kind == .addition || $0.kind == .deletion }.map(\.id))
        try await service.stageSelection(reverseIDs, document: stagedDoc, change: staged, in: root)
        #expect(try await git(["show", ":" + path]) == before)
        #expect(try String(contentsOf: file, encoding: .utf8) == after)
    }
}
