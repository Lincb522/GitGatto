import Foundation

protocol AIAPITransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

final class AIAPIURLTransport: NSObject, AIAPITransport, URLSessionTaskDelegate, @unchecked Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int) {
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
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2_000_000 else { throw AIAPIError.invalidResponse }
            data.append(byte)
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

    func probe(_ configuration: AIAPIConfiguration) async -> CodexAvailability {
        do {
            try configuration.validate()
            var request = try Self.request(configuration, resource: "models", key: credential(configuration))
            request.timeoutInterval = 15
            let (_, status) = try await transport.send(request)
            guard (200..<300).contains(status) else { return .unavailable }
            return CodexAvailability(state: .available, version: configuration.model)
        } catch { return .unavailable }
    }

    func cancel() { task?.cancel() }

    func run(
        configuration: AIAPIConfiguration, prompt: String, timeout: Duration,
        tools: (any AIAPIToolExecuting)? = nil,
        progress: @escaping @Sendable (AgentInstallProgress) async -> Void = { _ in }
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
                        transport: transport, tools: tools, progress: progress
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
        progress: @escaping @Sendable (AgentInstallProgress) async -> Void
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
                "stream": false,
                "messages": try JSONSerialization.jsonObject(with: encodedMessages)
            ]
            if tools != nil { body["tools"] = toolDefinitions }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, status) = try await transport.send(request)
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
