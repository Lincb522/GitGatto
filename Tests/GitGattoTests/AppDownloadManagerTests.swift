import Foundation
import Testing
@testable import GitGatto

@Suite("Application downloads and installation")
struct AppDownloadManagerTests {
    @Test("Downloads a release asset through the managed engine")
    @MainActor
    func downloadsReleaseAsset() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGatto-Download-Test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseAssetURLProtocol.self]
        let manager = AppDownloadManager(
            sessionConfiguration: configuration,
            appSupportDirectory: root.appendingPathComponent("State", isDirectory: true),
            downloadDirectory: root.appendingPathComponent("Downloads", isDirectory: true)
        )
        let source = try #require(URL(string: "https://downloads.example/GitGatto.zip"))
        manager.start(
            url: source,
            fileName: "GitGatto.zip",
            expectedBytes: Int64(ReleaseAssetURLProtocol.payload.count),
            repositoryName: "ZIJIU522/GitGatto"
        )

        for _ in 0..<100 where manager.records.first?.state != .completed {
            try await Task.sleep(for: .milliseconds(30))
        }
        let record = try #require(manager.records.first)
        #expect(record.state == .completed)
        let destination = try #require(record.destinationURL)
        #expect(try Data(contentsOf: destination) == ReleaseAssetURLProtocol.payload)
    }

    @Test("Installs a zipped macOS application into the selected Applications directory")
    func installsZippedApplication() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("GitGatto-Install-Test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let sourceApp = root.appendingPathComponent("Preview.app", isDirectory: true)
        let contents = sourceApp.appendingPathComponent("Contents", isDirectory: true)
        try fileManager.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data("preview".utf8).write(to: contents.appendingPathComponent("fixture.txt"))
        let archive = root.appendingPathComponent("Preview.zip")
        try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", sourceApp.path, archive.path])

        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let installer = MacApplicationInstaller(
            applicationsDirectory: applications
        )
        let installed = try await installer.install(archive, replacingExisting: false)

        #expect(installed == applications.appendingPathComponent("Preview.app", isDirectory: true))
        #expect(fileManager.fileExists(atPath: installed.appendingPathComponent("Contents/fixture.txt").path))
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}

private final class ReleaseAssetURLProtocol: URLProtocol, @unchecked Sendable {
    static let payload = Data("GitGatto release fixture".utf8)

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "downloads.example"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/zip",
                    "Content-Length": "\(Self.payload.count)"
                ]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
