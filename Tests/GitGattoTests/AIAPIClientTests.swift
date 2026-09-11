import Foundation
import Testing
@testable import GitGatto

@Suite("Agent API integration")
struct AIAPIClientTests {
    @Test("Legacy CLI settings still decode without API fields")
    func legacySettings() throws {
        let old = #"{"preset":"claude","displayName":"Personal","executable":"/custom/claude","versionArguments":"--version","analyzeArguments":"-p\n{prompt}","editArguments":"-p\n{prompt}","translationArguments":"-p\n{prompt}","outputFormat":"plainText"}"#
        let config = try JSONDecoder().decode(AIProviderConfiguration.self, from: Data(old.utf8))
        #expect(config.api == nil)
        #expect(config.executable == "/custom/claude")
        #expect(config.displayName == "Personal")
    }

    @Test("API settings round-trip without storing keys")
    func settings() throws {
        let config = AIProviderConfiguration.preset(.deepseek)
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(AIProviderConfiguration.self, from: data) == config)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let api = try #require(object["api"] as? [String: Any])
        #expect(Set(api.keys) == ["baseURL", "model", "credentialID"])
    }

    @Test("Validates HTTPS and normalizes completion endpoints")
    func endpoints() throws {
        var config = AIAPIConfiguration(baseURL: "https://service.test/v1/chat/completions", model: "model")
        #expect(try config.endpoint("chat/completions").absoluteString == "https://service.test/v1/chat/completions")
        #expect(try config.endpoint("models").absoluteString == "https://service.test/v1/models")
        let account = config.credentialAccount
        config.baseURL = "https://different.test/v1"
        #expect(config.credentialAccount != account)
        config.baseURL = "http://127.0.0.1:4321/v1"
        try config.validate()
        for url in ["http://remote.test/v1", "https://user:password@service.test", "https://service.test/?key=fixture", "file:///tmp"] {
            config.baseURL = url
            #expect(throws: AIAPIError.invalidConfiguration) { try config.validate() }
        }
    }

    @Test("Routes translation through native API without a CLI or local tools")
    func translation() async throws {
        let transport = RecordingAPITransport(responses: [Self.reply("译文")])
        let client = AIAPIClient(transport: transport, credential: { _ in "fixture-key" })
        let config = AIProviderConfiguration.preset(.deepseek)
        let service = CodexService(lane: .translation, apiClient: client, configurationSource: { _ in config })
        #expect(try await service.translate("hello", target: .simplifiedChinese) == "译文")
        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
        #expect(request.url?.path == "/chat/completions")
        let body = try Self.body(request)
        #expect(body["tools"] == nil)
        #expect(body["model"] as? String == "deepseek-v4-flash")
    }

    @Test("Replays tool IDs and reasoning, returns actual operation records")
    func toolRoundTrip() async throws {
        let toolReply = #"{"choices":[{"finish_reason":"tool_calls","message":{"role":"assistant","content":null,"reasoning_content":"fixture reasoning","tool_calls":[{"id":"call-1","type":"function","function":{"name":"run_command","arguments":"{\"arguments\":[\"git\",\"status\"]}"}}]}}]}"#
        let transport = RecordingAPITransport(responses: [Data(toolReply.utf8), Self.reply("Ready")])
        let client = AIAPIClient(transport: transport, credential: { _ in nil })
        let result = try await client.run(configuration: Self.config, prompt: "inspect", timeout: .seconds(2), tools: FixtureTool())
        #expect(result.response == "Ready")
        #expect(result.commandCount == 1)
        #expect(result.events == [CodexOperationEvent(kind: .command, summary: "git")])
        let requests = await transport.requests
        #expect(requests.count == 2)
        let body = try Self.body(requests[1])
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages[1]["reasoning_content"] as? String == "fixture reasoning")
        #expect(messages[2]["tool_call_id"] as? String == "call-1")
        #expect((body["tools"] as? [Any])?.count == 2)
    }

    @Test("Rejects tool calls in supplied-context requests")
    func noUnrequestedTools() async throws {
        let data = #"{"choices":[{"finish_reason":"tool_calls","message":{"role":"assistant","tool_calls":[{"id":"a","type":"function","function":{"name":"run_command","arguments":"{}"}}]}}]}"#
        let client = AIAPIClient(transport: RecordingAPITransport(responses: [Data(data.utf8)]), credential: { _ in nil })
        await #expect(throws: AIAPIError.invalidTool) {
            try await client.run(configuration: Self.config, prompt: "translate", timeout: .seconds(1))
        }
    }

    @Test("Does not accept truncated, empty, or malformed output as completion")
    func invalidResponses() async throws {
        for data in [Data("invalid".utf8), Self.reply(""), Self.reply("partial", reason: "length")] {
            let client = AIAPIClient(transport: RecordingAPITransport(responses: [data]), credential: { _ in nil })
            await #expect(throws: AIAPIError.invalidResponse) {
                try await client.run(configuration: Self.config, prompt: "test", timeout: .seconds(1))
            }
        }
    }

    @Test("HTTP errors expose only the status, not response bodies or credentials")
    func httpErrors() async throws {
        let transport = RecordingAPITransport(responses: [Data("private fixture".utf8)], status: 401)
        let client = AIAPIClient(transport: transport, credential: { _ in "fixture-key" })
        await #expect(throws: AIAPIError.http(401)) {
            try await client.run(configuration: Self.config, prompt: "test", timeout: .seconds(1))
        }
        #expect(!AIAPIError.http(401).localizedDescription.contains("fixture"))
    }

    @Test("Cancels an active API request and releases the channel")
    func cancellation() async throws {
        let transport = WaitingAPITransport()
        let client = AIAPIClient(transport: transport, credential: { _ in nil })
        let task = Task { try await client.run(configuration: Self.config, prompt: "test", timeout: .seconds(30)) }
        await transport.waitUntilStarted()
        await client.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.cancelled)
    }

    @Test("Enforces total task timeouts")
    func timeout() async throws {
        let client = AIAPIClient(transport: WaitingAPITransport(), credential: { _ in nil })
        await #expect(throws: CodexServiceError.self) {
            try await client.run(configuration: Self.config, prompt: "test", timeout: .milliseconds(30))
        }
    }

    @Test("New CLI presets use one-shot interfaces and do not request global permission bypass")
    func cliPresets() {
        let dsh = AIProviderConfiguration.preset(.dsh)
        #expect(dsh.arguments(for: .project) == ["--profile", "headless", "{prompt}"])
        for preset in [AIProviderPreset.dsh, .cursor, .copilot, .qwen] {
            let config = AIProviderConfiguration.preset(preset)
            #expect(config.parsedVersionArguments == ["--version"])
            #expect(preset.requiresProjectSandbox)
            #expect(config.arguments(for: .project, mode: .edit).contains("{prompt}"))
            #expect(!config.editArguments.contains("--yolo"))
            #expect(!config.editArguments.contains("--allow-all"))
        }
    }

    @Test("API Agent can stage an explicitly requested file in a linked worktree")
    func linkedWorktree() async throws {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".GitGatto-API-Worktree-\(UUID())")
        let original = root.appendingPathComponent("original")
        let worktree = root.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = GitCommandRunner()
        let environment = ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_TEMPLATE_DIR": "",
            "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
            "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.invalid"]
        _ = try await runner.run(at: original, arguments: ["init"], environment: environment)
        _ = try await runner.run(at: original, arguments: ["-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "--allow-empty", "-m", "fixture"], environment: environment)
        _ = try await runner.run(at: original, arguments: ["worktree", "add", "-b", "fixture-linked", worktree.path], environment: environment)
        try "fixture".write(to: worktree.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        let call = AIAPIToolCall(id: "stage", type: "function", function: .init(name: "run_command", arguments: "{\"arguments\":[\"git\",\"add\",\"hello.txt\"]}"))
        let message = AIAPIMessage(role: "assistant", tool_calls: [call])
        let encoded = try JSONEncoder().encode(message)
        let response: [String: Any] = ["choices": [["finish_reason": "tool_calls", "message": try JSONSerialization.jsonObject(with: encoded)]]]
        let transport = RecordingAPITransport(responses: [try JSONSerialization.data(withJSONObject: response), Self.reply("Staged")])
        let api = AIAPIClient(transport: transport, credential: { _ in nil })
        let config = AIProviderConfiguration.preset(.deepseek)
        let service = CodexService(apiClient: api, configurationSource: { _ in config })
        _ = try await service.run(prompt: "Stage hello.txt", context: [], in: worktree, mode: .edit)
        let staged = try await runner.run(at: worktree, arguments: ["diff", "--cached", "--name-only"], environment: environment)
        #expect(staged.text.trimmingCharacters(in: .whitespacesAndNewlines) == "hello.txt")
        let request = try #require(await transport.requests.last)
        let messages = try #require(Self.body(request)["messages"] as? [[String: Any]])
        let toolOutput = try #require(messages.last?["content"] as? String)
        let tool = try #require(JSONSerialization.jsonObject(with: Data(toolOutput.utf8)) as? [String: Any])
        #expect(tool["exit_code"] as? Int == 0, Comment(rawValue: toolOutput))
    }

    @Test("Catalog discovery is not reported as a tested chat or tested tool protocol")
    func capabilityChecks() async throws {
        let catalog = Data(#"{"data":[{"id":"fixture"},{"id":"other"}]}"#.utf8)
        let client = AIAPIClient(transport: RecordingAPITransport(responses: [catalog, catalog]), credential: { _ in nil })
        #expect(await client.probe(Self.config).noteKey == "ai.api.catalogOnly")
        var missing = Self.config
        missing.model = "absent"
        #expect(await client.probe(missing).noteKey == "ai.api.modelMissing")
        let noModels = AIAPIClient(transport: RecordingAPITransport(responses: [Data()], status: 404), credential: { _ in nil })
        #expect(await noModels.probe(Self.config).noteKey == "ai.api.notTested")
        let failed = AIAPIClient(transport: RecordingAPITransport(responses: [Data()], status: 401), credential: { _ in nil })
        #expect(await failed.probe(Self.config).state == .unavailable)
        let chatOnly = AIAPIClient(transport: RecordingAPITransport(responses: [Self.reply("OK"), Self.reply("OK")]), credential: { _ in nil })
        try await chatOnly.testConnection(Self.config, tools: false)
        await #expect(throws: AIAPIError.invalidTool) { try await chatOnly.testConnection(Self.config, tools: true) }
        let tool = Data(#"{"choices":[{"finish_reason":"tool_calls","message":{"role":"assistant","tool_calls":[{"id":"test","type":"function","function":{"name":"connection_test","arguments":"{}"}}]}}]}"#.utf8)
        let transport = RecordingAPITransport(responses: [tool])
        let tools = AIAPIClient(transport: transport, credential: { _ in nil })
        try await tools.testConnection(Self.config, tools: true)
        #expect(await transport.requests.count == 1)
    }

    private static var config: AIAPIConfiguration { AIAPIConfiguration(baseURL: "https://fixture.test/v1", model: "fixture") }
    private static func reply(_ content: String, reason: String = "stop") -> Data {
        let body: [String: Any] = ["choices": [["finish_reason": reason, "message": ["role": "assistant", "content": content]]]]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }
    private static func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private actor RecordingAPITransport: AIAPITransport {
    var requests: [URLRequest] = []
    private var responses: [Data]
    private let status: Int
    init(responses: [Data], status: Int = 200) { self.responses = responses; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !responses.isEmpty else { throw AIAPIError.invalidResponse }
        return (responses.removeFirst(), status)
    }
}

private struct FixtureTool: AIAPIToolExecuting {
    func execute(_ call: AIAPIToolCall) async throws -> AIAPIToolOutput {
        AIAPIToolOutput(content: "ok", event: CodexOperationEvent(kind: .command, summary: "git"))
    }
}

private actor WaitingAPITransport: AIAPITransport {
    private var started = false
    private var waiter: CheckedContinuation<Void, Never>?
    var cancelled = false
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        started = true
        waiter?.resume(); waiter = nil
        do { try await Task.sleep(for: .seconds(60)) }
        catch { cancelled = true; throw error }
        return (Data(), 200)
    }
}
