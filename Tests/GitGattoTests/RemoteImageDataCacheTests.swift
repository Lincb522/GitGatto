import Foundation
import Testing
@testable import GitGatto

@Suite("Remote image data cache", .serialized)
struct RemoteImageDataCacheTests {
    @Test("Coalesces concurrent requests and reuses the cached payload")
    func coalescesRequests() async throws {
        CountingImageURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CountingImageURLProtocol.self]
        let cache = RemoteImageDataCache(session: URLSession(configuration: configuration))
        let url = try #require(URL(string: "https://example.invalid/icon.png"))

        async let first = cache.data(for: url)
        async let second = cache.data(for: url)
        let initial = try await (first, second)
        let cached = try await cache.data(for: url)

        #expect(initial.0 == CountingImageURLProtocol.payload)
        #expect(initial.1 == CountingImageURLProtocol.payload)
        #expect(cached == CountingImageURLProtocol.payload)
        #expect(CountingImageURLProtocol.requestCount == 1)
    }
}

private final class CountingImageURLProtocol: URLProtocol, @unchecked Sendable {
    static let payload = Data("cached-image".utf8)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests = 0

    static var requestCount: Int {
        lock.withLock { requests }
    }

    static func reset() {
        lock.withLock { requests = 0 }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.requests += 1 }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/png"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
