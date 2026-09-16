import Foundation

private final class RelaySessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
public final class RelayClient: Sendable {
    public let identity: RelayIdentity
    public let baseURL: URL
    private let session: URLSession
    public init(baseURL: URL, identity: RelayIdentity, allowsLoopbackHTTP: Bool = false) throws {
        let loopback = allowsLoopbackHTTP && baseURL.scheme == "http" && ["127.0.0.1", "localhost", "[::1]"].contains(baseURL.host)
        guard baseURL.scheme == "https" || loopback, baseURL.host != nil,
              baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil,
              baseURL.path.isEmpty || baseURL.path == "/" else { throw RemoteError.invalidConfiguration }
        self.baseURL = baseURL; self.identity = identity
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration, delegate: RelaySessionDelegate(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    public func request<T: Decodable & Sendable>(_ method: String, _ path: String, body: Data = Data(), as type: T.Type) async throws -> T {
        let request = try signedRequest(method, path, body: body)
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw RemoteError.invalidMessage }
        var data = Data()
        for try await byte in bytes {
            if data.count >= 3 * 1024 * 1024 { throw RemoteError.capacity }
            data.append(byte)
        }
        guard (200..<300).contains(response.statusCode) else {
            let code = (try? JSONDecoder().decode([String: String].self, from: data)["error"]) ?? "request_failed"
            throw RemoteError.transport(response.statusCode, code)
        }
        return try JSONDecoder().decode(type, from: data)
    }
    public func json<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
    private func signedRequest(_ method: String, _ path: String, body: Data) throws -> URLRequest {
        guard path.hasPrefix("/v1/"), !path.contains("?"), !path.contains("#"), !path.contains(".."),
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              url.host == baseURL.host else { throw RemoteError.invalidConfiguration }
        var request = URLRequest(url: url); request.httpMethod = method
        if !body.isEmpty { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (key, value) in try identity.headers(method: method, path: path, body: body) { request.setValue(value, forHTTPHeaderField: key) }
        return request
    }
    public func pairings() async throws -> [RelayPairing] {
        struct Result: Decodable, Sendable { let pairings: [RelayPairing] }
        return try await request("GET", "/v1/pairings", as: Result.self).pairings
    }
    public func createInvitation(_ invitation: RelayInvitation) async throws {
        struct Result: Decodable, Sendable { let id: String }
        let _: Result = try await request("POST", "/v1/pairings", body: json(invitation), as: Result.self)
    }
    public func approve(_ grant: RemoteGrant) async throws -> RelayPairing {
        struct Body: Encodable { var mobileId: String; var repositories: [String] }
        return try await request("POST", "/v1/pairings/\(grant.pairingId)/approve",
            body: json(Body(mobileId: grant.mobile.id, repositories: grant.repositories.map(\.id))), as: RelayPairing.self)
    }
    public func revoke(_ id: String) async throws {
        let _: [String: String] = try await request("DELETE", "/v1/pairings/\(id)", as: [String: String].self)
    }
    public func inbox() async throws -> [RelayEnvelope] {
        struct Result: Decodable, Sendable { let messages: [RelayEnvelope] }
        return try await request("GET", "/v1/messages", as: Result.self).messages
    }
    public func ack(_ envelope: RelayEnvelope) async throws {
        struct Receipt: Encodable { var senderId: String; var id: String }
        struct Body: Encodable { var receipts: [Receipt] }
        let _: [String: Int] = try await request("POST", "/v1/messages/ack",
            body: json(Body(receipts: [.init(senderId: envelope.senderId, id: envelope.id)])), as: [String: Int].self)
    }
    public func send(_ envelope: RelayEnvelope) async throws {
        struct Result: Decodable, Sendable { let state: String }
        let _: Result = try await request("POST", "/v1/messages", body: json(envelope), as: Result.self)
    }
    public func listen(_ event: @escaping @Sendable (String) async throws -> Void) async throws {
        var request = try signedRequest("GET", "/v1/socket", body: Data())
        guard var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) else { throw RemoteError.invalidConfiguration }
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"; request.url = components.url
        let socket = session.webSocketTask(with: request)
        try await withTaskCancellationHandler {
            socket.resume()
            defer { socket.cancel(with: .goingAway, reason: nil) }
            while !Task.isCancelled {
                let message = try await socket.receive()
                guard case let .string(text) = message, text.utf8.count <= 4096 else { throw RemoteError.invalidMessage }
                try await event(text)
            }
        } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
    }
}
