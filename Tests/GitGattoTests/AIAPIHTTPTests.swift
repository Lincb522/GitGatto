import Foundation
import Testing
@testable import GitGatto

@Suite("Native API HTTP transport")
struct AIAPIHTTPTests {
    @Test("Real SSE emits deltas, rejects truncated responses, and cancels a pending read", .enabled(if: ProcessInfo.processInfo.environment["GITGATTO_API_HTTP_FIXTURE"] != nil))
    func streamingWire() async throws {
        let base = try #require(ProcessInfo.processInfo.environment["GITGATTO_API_HTTP_FIXTURE"])
        #expect(URL(string: base)?.host == "127.0.0.1")
        let transport = AIAPIURLTransport()
        let output = HTTPStreamOutput()
        let request = URLRequest(url: try #require(URL(string: base + "/stream")))
        let (data, status) = try await transport.stream(request) { await output.add($0) }
        #expect(status == 200)
        #expect(await output.value == "第一段第二段")
        #expect(await output.count >= 2)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let message = try #require((object["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])
        #expect(message["content"] as? String == "第一段第二段")
        let truncated = URLRequest(url: try #require(URL(string: base + "/truncated")))
        await #expect(throws: AIAPIError.invalidResponse) { try await transport.stream(truncated) { _ in } }
        let slow = URLRequest(url: try #require(URL(string: base + "/slow")))
        let pending = HTTPStreamOutput()
        let task = Task { try await transport.stream(slow) { await pending.add($0) } }
        let deadline = ContinuousClock.now + .seconds(3)
        while await pending.count == 0, ContinuousClock.now < deadline { await Task.yield() }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled response must not be accepted") }
        catch is CancellationError {}
        catch let error as URLError { #expect(error.code == .cancelled) }
    }

    @Test("Loopback HTTP completes a real sandboxed file edit and rejects redirects", .enabled(if: ProcessInfo.processInfo.environment["GITGATTO_API_HTTP_FIXTURE"] != nil))
    func httpRoundTrip() async throws {
        let base = try #require(ProcessInfo.processInfo.environment["GITGATTO_API_HTTP_FIXTURE"])
        #expect(URL(string: base)?.host == "127.0.0.1")
        let client = AIAPIClient(credential: { _ in "synthetic-fixture-key" })
        let config = AIAPIConfiguration(baseURL: base + "/v1", model: "fixture-agent")
        #expect(await client.probe(config).state == .available)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GitGatto-API-HTTP-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var provider = AIProviderConfiguration.preset(.openAICompatible)
        provider.api = config
        let configuration = provider
        let service = CodexService(apiClient: client, configurationSource: { _ in configuration })
        let result = try await service.run(prompt: "Create hello.txt", context: [], in: directory, mode: .edit)
        #expect(result.response == "Created hello.txt")
        #expect(result.fileChangeCount == 1)
        #expect(try String(contentsOf: directory.appendingPathComponent("hello.txt"), encoding: .utf8) == "Hello from the API fixture")
        let redirected = AIAPIConfiguration(baseURL: base + "/redirect", model: "fixture-agent")
        #expect(await client.probe(redirected).state == .unavailable)
    }
}

private actor HTTPStreamOutput {
    private(set) var value = ""
    private(set) var count = 0
    func add(_ delta: String) { value += delta; count += 1 }
}
