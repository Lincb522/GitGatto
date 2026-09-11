import Foundation

protocol AIAPITransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
    func stream(_ request: URLRequest, text: @escaping @Sendable (String) async -> Void) async throws -> (Data, Int)
}

extension AIAPITransport {
    func stream(_ request: URLRequest, text: @escaping @Sendable (String) async -> Void) async throws -> (Data, Int) {
        try await send(request)
    }
}

final class AIAPIURLTransport: NSObject, AIAPITransport, URLSessionTaskDelegate, @unchecked Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await perform(request, text: nil)
    }

    func stream(_ request: URLRequest, text: @escaping @Sendable (String) async -> Void) async throws -> (Data, Int) {
        try await perform(request, text: text)
    }

    private func perform(_ request: URLRequest, text: (@Sendable (String) async -> Void)?) async throws -> (Data, Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 180
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw AIAPIError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { return (Data(), response.statusCode) }
        let isStream = response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true
        var data = Data()
        var line = Data()
        var decoder = AIAPIStreamDecoder()
        var byteCount = 0
        var pendingText = ""
        let clock = ContinuousClock()
        var lastEmission = clock.now.advanced(by: .milliseconds(-100))
        for try await byte in bytes {
            try Task.checkCancellation()
            byteCount += 1
            guard byteCount <= 2_000_000 else { throw AIAPIError.invalidResponse }
            if isStream {
                if byte == 10 {
                    guard let string = String(data: line, encoding: .utf8) else { throw AIAPIError.invalidResponse }
                    if let delta = try decoder.consume(string.trimmingCharacters(in: .newlines)) { pendingText += delta }
                    line.removeAll(keepingCapacity: true)
                    if !pendingText.isEmpty, clock.now - lastEmission >= .milliseconds(100) {
                        await text?(pendingText)
                        pendingText = ""
                        lastEmission = clock.now
                    }
                } else { line.append(byte) }
            } else { data.append(byte) }
        }
        if isStream {
            if !line.isEmpty {
                guard let string = String(data: line, encoding: .utf8) else { throw AIAPIError.invalidResponse }
                if let delta = try decoder.consume(string.trimmingCharacters(in: .newlines)) { pendingText += delta }
            }
            if !pendingText.isEmpty { await text?(pendingText) }
            return (try decoder.response(), response.statusCode)
        }
        return (data, response.statusCode)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Never forward a configured API credential to a redirect target.
        completionHandler(nil)
    }
}

struct AIAPIToolCall: Codable, Sendable {
    struct Function: Codable, Sendable {
        var name: String
        var arguments: String
    }
    var id: String
    var type: String
    var function: Function
}

struct AIAPIMessage: Codable, Sendable {
    var role: String
    var content: String?
    var tool_calls: [AIAPIToolCall]?
    var tool_call_id: String?
    // Required by reasoning models when an assistant tool call is replayed.
    var reasoning_content: String?
}

struct AIAPIToolOutput: Sendable {
    var content: String
    var event: CodexOperationEvent?
}

protocol AIAPIToolExecuting: Sendable {
    func execute(_ call: AIAPIToolCall) async throws -> AIAPIToolOutput
}

actor AIAPIClient {
    private let transport: any AIAPITransport
    private let credential: @Sendable (AIAPIConfiguration) throws -> String?
    private var task: Task<CodexRunResult, any Error>?

    init(
        transport: any AIAPITransport = AIAPIURLTransport(),
        credential: @escaping @Sendable (AIAPIConfiguration) throws -> String? = AIAPICredentialStore.read
    ) {
        self.transport = transport
        self.credential = credential
    }

    func models(_ configuration: AIAPIConfiguration) async throws -> [String] {
        var request = try Self.request(configuration, resource: "models", key: credential(configuration))
        request.timeoutInterval = 15
        let (data, status) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw AIAPIError.http(status) }
        struct Catalog: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        guard let catalog = try? JSONDecoder().decode(Catalog.self, from: data), catalog.data.count <= 10_000 else {
            throw AIAPIError.invalidResponse
        }
        return Array(Set(catalog.data.map(\.id).filter { !$0.isEmpty })).sorted()
    }

    func probe(_ configuration: AIAPIConfiguration) async -> CodexAvailability {
        do {
            try configuration.validate()
            let available = try await models(configuration)
            guard available.contains(configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return CodexAvailability(state: .unavailable, version: nil, noteKey: "ai.api.modelMissing")
            }
            return CodexAvailability(state: .available, version: configuration.model, noteKey: "ai.api.catalogOnly")
        } catch AIAPIError.http(let status) where status == 404 || status == 405 {
            // Some compatible servers expose completions without a model catalogue.
            return CodexAvailability(state: .available, version: configuration.model, noteKey: "ai.api.notTested")
        } catch { return .unavailable }
    }

    func testConnection(_ configuration: AIAPIConfiguration, tools: Bool) async throws {
        try configuration.validate()
        var request = try Self.request(configuration, resource: "chat/completions", key: credential(configuration))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        var body: [String: Any] = ["model": configuration.model, "stream": false,
            "messages": [["role": "user", "content": tools ? "Call connection_test with no arguments." : "Reply OK."]]]
        if tools {
            body["tools"] = [["type": "function", "function": ["name": "connection_test",
                "description": "Connection check only. Does not execute commands or modify files.",
                "parameters": ["type": "object", "properties": [:], "additionalProperties": false]]]]
            body["tool_choice"] = ["type": "function", "function": ["name": "connection_test"]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, status) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw AIAPIError.http(status) }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let choice = response.choices.first, choice.message.role == "assistant" else { throw AIAPIError.invalidResponse }
        if tools {
            guard choice.finish_reason == "tool_calls", let calls = choice.message.tool_calls, calls.count == 1,
                  calls[0].type == "function", !calls[0].id.isEmpty,
                  calls[0].function.name == "connection_test",
                  let arguments = calls[0].function.arguments.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: arguments) as? [String: Any], object.isEmpty else {
                throw AIAPIError.invalidTool
            }
        } else {
            guard choice.finish_reason == "stop", (choice.message.tool_calls ?? []).isEmpty,
                  !(choice.message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIAPIError.invalidResponse
            }
        }
    }

    func cancel() { task?.cancel() }

    func run(
        configuration: AIAPIConfiguration, prompt: String, timeout: Duration,
        tools: (any AIAPIToolExecuting)? = nil,
        progress: @escaping @Sendable (AgentInstallProgress) async -> Void = { _ in },
        text: @escaping @Sendable (String) async -> Void = { _ in }
    ) async throws -> CodexRunResult {
        guard task == nil else { throw AIAPIError.busy }
        try configuration.validate()
        let key = try credential(configuration)
        let transport = transport
        let task = Task {
            try await withThrowingTaskGroup(of: CodexRunResult.self) { group in
                group.addTask {
                    try await Self.conversation(
                        configuration: configuration, key: key, prompt: prompt,
                        transport: transport, tools: tools, progress: progress, text: text
                    )
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw CodexServiceError.timedOut
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw AIAPIError.invalidResponse }
                return result
            }
        }
        self.task = task
        defer { self.task = nil }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }

    private static func request(_ configuration: AIAPIConfiguration, resource: String, key: String?) throws -> URLRequest {
        var request = URLRequest(url: try configuration.endpoint(resource))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key, !key.isEmpty {
            guard !key.contains("\n"), !key.contains("\r") else { throw AIAPIError.invalidConfiguration }
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static func conversation(
        configuration: AIAPIConfiguration, key: String?, prompt: String,
        transport: any AIAPITransport, tools: (any AIAPIToolExecuting)?,
        progress: @escaping @Sendable (AgentInstallProgress) async -> Void,
        text: @escaping @Sendable (String) async -> Void
    ) async throws -> CodexRunResult {
        var messages = [AIAPIMessage(role: "user", content: prompt)]
        var events: [CodexOperationEvent] = []
        var executed = 0
        for _ in 0..<24 {
            try Task.checkCancellation()
            var request = try request(configuration, resource: "chat/completions", key: key)
            request.httpMethod = "POST"
            let encodedMessages = try JSONEncoder().encode(messages)
            var body: [String: Any] = [
                "model": configuration.model.trimmingCharacters(in: .whitespacesAndNewlines),
                "stream": true,
                "messages": try JSONSerialization.jsonObject(with: encodedMessages)
            ]
            if tools != nil { body["tools"] = toolDefinitions }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, status) = try await transport.stream(request, text: text)
            try Task.checkCancellation()
            guard (200..<300).contains(status) else { throw AIAPIError.http(status) }
            guard data.count <= 2_000_000,
                  let response = try? JSONDecoder().decode(Response.self, from: data),
                  let choice = response.choices.first,
                  choice.message.role == "assistant",
                  choice.finish_reason == "stop" || choice.finish_reason == "tool_calls" else {
                throw AIAPIError.invalidResponse
            }
            let message = choice.message
            let calls = message.tool_calls ?? []
            if calls.isEmpty {
                guard choice.finish_reason == "stop",
                      let text = message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { throw AIAPIError.invalidResponse }
                return CodexRunResult(
                    response: text,
                    commandCount: events.filter { $0.kind == .command }.count,
                    fileChangeCount: events.filter { $0.kind == .fileChange }.count,
                    events: events
                )
            }
            guard let tools, calls.count <= 16, executed + calls.count <= 96,
                  Set(calls.map(\.id)).count == calls.count,
                  calls.allSatisfy({ !$0.id.isEmpty && $0.type == "function" }) else {
                throw AIAPIError.invalidTool
            }
            messages.append(message)
            for call in calls {
                try Task.checkCancellation()
                executed += 1
                await progress(AgentInstallProgress(.installing, detail: L10n.text("ai.api.progress.tool")))
                // A rejected tool call is not a successful operation. Let the caller report the
                // failed task instead of accepting a model's unsupported success claim.
                let output = try await tools.execute(call)
                if let event = output.event { events.append(event) }
                messages.append(AIAPIMessage(role: "tool", content: String(output.content.prefix(64_000)), tool_call_id: call.id))
            }
        }
        throw AIAPIError.toolLimit
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            var message: AIAPIMessage
            var finish_reason: String?
        }
        var choices: [Choice]
    }

    private static var toolDefinitions: [[String: Any]] {
        [
            ["type": "function", "function": [
                "name": "run_command",
                "description": "Run an executable with an argument array in the current task directory. No implicit shell. Check exit_code and output; failed commands do not prove success. Network and filesystem access follow the task sandbox.",
                "parameters": ["type": "object", "properties": [
                    "arguments": ["type": "array", "items": ["type": "string"], "minItems": 1]
                ], "required": ["arguments"], "additionalProperties": false]
            ]],
            ["type": "function", "function": [
                "name": "write_file",
                "description": "Write a UTF-8 file relative to the current project. Requires edit mode. Inspect the original file before editing. Cannot access credentials or paths outside the project.",
                "parameters": ["type": "object", "properties": [
                    "path": ["type": "string"], "content": ["type": "string"]
                ], "required": ["path", "content"], "additionalProperties": false]
            ]]
        ]
    }
}
