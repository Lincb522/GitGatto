import Foundation

/// Assembles one completion without exposing reasoning or incomplete tool calls to execution.
struct AIAPIStreamDecoder {
    private var content = ""
    private var reasoning = ""
    private var calls: [Int: AIAPIToolCall] = [:]
    private var finishReason: String?
    private var finished = false

    mutating func consume(_ line: String) throws -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { finished = true; return nil }
        guard !finished, let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]] else { throw AIAPIError.invalidResponse }
        guard let choice = choices.first else { return nil }
        guard choice["index"] as? Int == 0 else { throw AIAPIError.invalidResponse }
        guard finishReason == nil, let delta = choice["delta"] as? [String: Any] else { throw AIAPIError.invalidResponse }
        if let reason = choice["finish_reason"] as? String { finishReason = reason }
        if let text = delta["reasoning_content"] as? String { reasoning += text }
        if let parts = delta["tool_calls"] as? [[String: Any]] {
            for part in parts {
                guard let index = part["index"] as? Int, (0..<16).contains(index) else { throw AIAPIError.invalidTool }
                var call = calls[index] ?? AIAPIToolCall(id: "", type: "function", function: .init(name: "", arguments: ""))
                if let id = part["id"] as? String { call.id += id }
                if let type = part["type"] as? String { call.type = type }
                if let function = part["function"] as? [String: Any] {
                    call.function.name += function["name"] as? String ?? ""
                    call.function.arguments += function["arguments"] as? String ?? ""
                }
                calls[index] = call
            }
        }
        if let text = delta["content"] as? String, !text.isEmpty {
            content += text
            return text
        }
        return nil
    }

    func response() throws -> Data {
        guard finished, let finishReason, ["stop", "tool_calls"].contains(finishReason) else {
            throw AIAPIError.invalidResponse
        }
        let ordered = calls.keys.sorted().compactMap { calls[$0] }
        let message = AIAPIMessage(role: "assistant", content: content,
                                   tool_calls: ordered.isEmpty ? nil : ordered,
                                   reasoning_content: reasoning.isEmpty ? nil : reasoning)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(message))
        return try JSONSerialization.data(withJSONObject: ["choices": [["message": object, "finish_reason": finishReason]]])
    }
}
