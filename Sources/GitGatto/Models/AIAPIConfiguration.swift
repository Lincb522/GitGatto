import Foundation

struct AIAPIConfiguration: Codable, Sendable, Equatable {
    var baseURL: String
    var model: String
    var credentialID = UUID().uuidString

    func endpoint(_ resource: String) throws -> URL {
        let input = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: input),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.scheme == "https" || (
                components.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)
              ), let url = components.url else { throw AIAPIError.invalidConfiguration }
        if url.path.hasSuffix("/chat/completions") {
            return url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(resource)
        }
        return url.appendingPathComponent(resource)
    }

    var credentialAccount: String {
        // A changed endpoint must never silently receive a key saved for another endpoint.
        let endpoint = (try? endpoint("chat/completions").absoluteString) ?? baseURL
        return credentialID + ":" + endpoint
    }

    func validate() throws {
        _ = try endpoint("chat/completions")
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIAPIError.invalidConfiguration
        }
    }
}

enum AIAPIError: LocalizedError, Sendable, Equatable {
    case invalidConfiguration
    case credentialStore
    case http(Int)
    case invalidResponse
    case toolLimit
    case invalidTool
    case pathDenied
    case busy

    var errorDescription: String? {
        switch self {
        case .http(let status): L10n.format("ai.api.error.http", status)
        case .invalidConfiguration: L10n.text("ai.api.error.configuration")
        case .credentialStore: L10n.text("ai.api.error.keychain")
        case .invalidResponse: L10n.text("ai.api.error.response")
        case .toolLimit: L10n.text("ai.api.error.limit")
        case .invalidTool: L10n.text("ai.api.error.tool")
        case .pathDenied: L10n.text("ai.api.error.path")
        case .busy: L10n.text("ai.api.error.busy")
        }
    }
}
