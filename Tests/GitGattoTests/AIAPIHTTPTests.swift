import Foundation
import Testing
@testable import GitGatto

@Suite("Native API HTTP transport")
struct AIAPIHTTPTests {
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
