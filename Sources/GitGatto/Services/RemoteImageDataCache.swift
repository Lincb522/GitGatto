import Foundation

enum RemoteImageDataError: LocalizedError {
    case invalidResponse
    case payloadTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The image server returned an invalid response."
        case .payloadTooLarge:
            "The image exceeds the cache size limit."
        }
    }
}

actor RemoteImageDataCache {
    static let shared = RemoteImageDataCache()

    private let session: URLSession
    private let memoryCache: NSCache<NSURL, NSData>
    private var inFlight: [URL: Task<Data, Error>] = [:]

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            configuration.urlCache = URLCache(
                memoryCapacity: 32 * 1_024 * 1_024,
                diskCapacity: 128 * 1_024 * 1_024,
                directory: FileManager.default.urls(
                    for: .cachesDirectory,
                    in: .userDomainMask
                ).first?.appendingPathComponent("GitGatto/RemoteImages", isDirectory: true)
            )
            self.session = URLSession(configuration: configuration)
        }
        memoryCache = NSCache<NSURL, NSData>()
        memoryCache.countLimit = 160
        memoryCache.totalCostLimit = 40 * 1_024 * 1_024
    }

    func data(for url: URL, maximumByteCount: Int = 8 * 1_024 * 1_024) async throws -> Data {
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached as Data
        }
        if let running = inFlight[url] {
            return try await running.value
        }

        let session = self.session
        let task = Task<Data, Error> {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            if let response = response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                throw RemoteImageDataError.invalidResponse
            }
            guard data.count <= maximumByteCount else {
                throw RemoteImageDataError.payloadTooLarge
            }
            return data
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let data = try await task.value
        memoryCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        return data
    }

    func prefetch(_ urls: [URL], maximumCount: Int = 12) async {
        let targets = Array(urls.prefix(maximumCount))
        await withTaskGroup(of: Void.self) { group in
            for url in targets {
                group.addTask {
                    _ = try? await self.data(for: url)
                }
            }
        }
    }
}
