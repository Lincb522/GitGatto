import Foundation
import Testing
@testable import GitGatto

@Suite("Application downloads and installation")
struct AppDownloadManagerTests {
    @Test("Download file names cannot escape or alias the download directory")
    func sanitizesDownloadFileNames() {
        #expect(AppDownloadManager.safeFileName("GitGatto-1.0.dmg") == "GitGatto-1.0.dmg")
        #expect(AppDownloadManager.safeFileName("a/b:c.zip") == "a-b-c.zip")
        #expect(AppDownloadManager.safeFileName("..") == "download")
        #expect(AppDownloadManager.safeFileName(".") == "download")
        #expect(AppDownloadManager.safeFileName("../../etc") == "-..-etc")
        #expect(AppDownloadManager.safeFileName(".hidden.dmg") == "hidden.dmg")
        #expect(AppDownloadManager.safeFileName("  ") == "download")
    }

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

    @Test("Restores download records written before installation metadata existed")
    func decodesLegacyDownloadRecord() throws {
        let record = AppDownloadRecord(
            id: UUID(),
            repositoryName: "example/tool",
            assetID: 9,
            fileName: "tool.zip",
            sourceURL: try #require(URL(string: "https://downloads.example/tool.zip")),
            expectedBytes: 120,
            destinationURL: nil,
            state: .completed,
            progress: 1,
            receivedBytes: 120,
            errorMessage: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 20)
        )
        let encoded = try JSONEncoder().encode(record)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in [
            "installAfterDownload",
            "installationMethod",
            "installationPhase",
            "installationStartedAt",
            "installationMessage",
            "agentResult"
        ] {
            object.removeValue(forKey: key)
        }

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(AppDownloadRecord.self, from: legacyData)

        #expect(decoded.id == record.id)
        #expect(decoded.installAfterDownload == nil)
        #expect(decoded.installationMethod == nil)
        #expect(decoded.installationStartedAt == nil)
        #expect(decoded.agentResult == nil)
    }

    @Test("Quick install hands command-line packages to Agent after download")
    @MainActor
    func quickInstallsCommandLinePackageWithAgent() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGatto-Quick-Install-Test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseAssetURLProtocol.self]
        let agent = DownloadAgentFixture()
        let manager = AppDownloadManager(
            agentInstallerFactory: { agent },
            sessionConfiguration: configuration,
            appSupportDirectory: root.appendingPathComponent("State", isDirectory: true),
            downloadDirectory: root.appendingPathComponent("Downloads", isDirectory: true)
        )
        let source = try #require(URL(string: "https://downloads.example/tool.pkg"))
        let asset = GitHubReleaseAsset(
            id: 42,
            name: "tool.pkg",
            size: Int64(ReleaseAssetURLProtocol.payload.count),
            downloadCount: 0,
            contentType: "application/octet-stream",
            downloadURL: source,
            createdAt: Date()
        )

        manager.quickInstall(asset: asset, repositoryName: "example/tool")

        for _ in 0..<200 where manager.records.first?.state != .installed {
            try await Task.sleep(for: .milliseconds(25))
        }
        let record = try #require(manager.records.first)
        #expect(record.state == .installed)
        #expect(record.installationMethod == .agent)
        #expect(record.agentResult == "Installed and verified")
        #expect(await agent.installedDisplayNames == ["example/tool"])
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

    @Test("Agent setup failures remain retryable instead of becoming installed")
    @MainActor
    func keepsIncompleteArtifactInstallationActionable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try completedRecord(in: root)
        let agent = DownloadAgentFixture(requiresUserAction: true)
        let manager = AppDownloadManager(agentInstallerFactory: { agent }, appSupportDirectory: root,
                                         downloadDirectory: root.appendingPathComponent("Downloads"))
        manager.installWithAgent(record.id)
        try await waitUntil { manager.record(record.id)?.errorMessage != nil }
        #expect(manager.record(record.id)?.state == .completed)
        #expect(manager.record(record.id)?.errorMessage == L10n.text("installer.error.incomplete"))
        #expect(manager.record(record.id)?.agentResult == "Installed and verified")
    }

    @Test("Cancelling an Agent installation cannot cancel or overwrite its replacement")
    @MainActor
    func isolatesArtifactInstallationRetries() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try completedRecord(in: root)
        let first = DownloadAgentFixture(holdsCompletion: true)
        let second = DownloadAgentFixture(holdsCompletion: true)
        var factories = [first, second]
        let manager = AppDownloadManager(agentInstallerFactory: { factories.removeFirst() },
                                         appSupportDirectory: root,
                                         downloadDirectory: root.appendingPathComponent("Downloads"))
        do {
            manager.installWithAgent(record.id)
            try await waitUntil { await first.installedDisplayNames.count == 1 }
            manager.cancelInstallation(record.id)
            manager.installWithAgent(record.id)
            try await waitUntil { await second.installedDisplayNames.count == 1 }
            await first.release()
            try await waitUntil { await first.completedCount == 1 }
            #expect(manager.record(record.id)?.state == .installing)
            #expect(await second.cancelCount == 0)
            await second.release()
            try await waitUntil { manager.record(record.id)?.state == .installed }
            #expect(manager.record(record.id)?.errorMessage == nil)
        } catch {
            await first.release()
            await second.release()
            throw error
        }
    }

    @Test("Download byte progress does not change the catalog summary")
    @MainActor
    func catalogSummaryIgnoresByteProgress() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var record = try completedRecord(in: root)
        record.state = .downloading
        let before = AppDownloadSummary.Snapshot(records: [record])
        record.receivedBytes = 50
        record.progress = 0.5
        record.updatedAt = Date()
        #expect(AppDownloadSummary.Snapshot(records: [record]) == before)
        record.state = .installed
        let installed = AppDownloadSummary.Snapshot(records: [record])
        #expect(installed.activeCount == 0)
        #expect(installed.installedRepositoryNames == [record.repositoryName])
    }

    @Test("Native replacement refuses a different product with the same app name")
    func preservesDifferentInstalledProduct() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source/Preview.app/Contents")
        let existing = root.appendingPathComponent("Applications/Preview.app/Contents")
        for (directory, identifier) in [(source, "test.incoming"), (existing, "test.existing")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": identifier],
                                                          format: .xml, options: 0)
            try data.write(to: directory.appendingPathComponent("Info.plist"))
            try Data(identifier.utf8).write(to: directory.appendingPathComponent("keep.txt"))
        }
        let archive = root.appendingPathComponent("Preview.zip")
        try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", source.deletingLastPathComponent().path, archive.path])
        let installer = MacApplicationInstaller(applicationsDirectory: root.appendingPathComponent("Applications"))
        await #expect(throws: MacApplicationInstallerError.self) {
            try await installer.install(archive, replacingExisting: true)
        }
        #expect(try String(contentsOf: existing.appendingPathComponent("keep.txt"), encoding: .utf8) == "test.existing")
    }

    private func completedRecord(in root: URL) throws -> AppDownloadRecord {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("tool.pkg")
        try Data("fixture".utf8).write(to: file)
        let record = AppDownloadRecord(id: UUID(), repositoryName: "example/tool", assetID: 42,
            fileName: "tool.pkg", sourceURL: URL(fileURLWithPath: "/fixture/tool.pkg"), expectedBytes: 100,
            destinationURL: file, state: .completed, progress: 1, receivedBytes: 100,
            errorMessage: nil, createdAt: Date(), updatedAt: Date())
        try JSONEncoder().encode([record]).write(to: root.appendingPathComponent("downloads.json"))
        return record
    }

    @MainActor
    private func waitUntil(_ predicate: () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(20))
        while !(await predicate()) {
            guard clock.now < deadline else { throw CocoaError(.validationMissingMandatoryProperty) }
            try await Task.sleep(for: .milliseconds(20))
        }
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

private actor DownloadAgentFixture: CodexServing {
    private(set) var installedDisplayNames: [String] = []
    private(set) var cancelCount = 0
    private(set) var completedCount = 0
    private var holdsCompletion: Bool
    private let requiresUserAction: Bool
    private var continuation: CheckedContinuation<Void, Never>?

    init(holdsCompletion: Bool = false, requiresUserAction: Bool = false) {
        self.holdsCompletion = holdsCompletion
        self.requiresUserAction = requiresUserAction
    }

    func release() {
        holdsCompletion = false
        continuation?.resume()
        continuation = nil
    }

    func probe() async -> CodexAvailability { .unavailable }

    func run(
        prompt: String,
        context: [CodexMessage],
        in repositoryURL: URL,
        mode: CodexRunMode
    ) async throws -> CodexRunResult {
        throw CodexServiceError.executionFailed(-1)
    }

    func runWithProvidedContext(
        prompt: String,
        context: [CodexMessage]
    ) async throws -> CodexRunResult {
        throw CodexServiceError.executionFailed(-1)
    }

    func draftPullRequestReply(context: GitHubPullRequestContext) async throws -> String {
        throw CodexServiceError.executionFailed(-1)
    }

    func translate(_ text: String, target: CodexTranslationTarget) async throws -> String {
        throw CodexServiceError.executionFailed(-1)
    }

    func translateHTML(
        _ html: String,
        target: CodexTranslationTarget,
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> String {
        throw CodexServiceError.executionFailed(-1)
    }

    func installDownloadedArtifact(at url: URL, displayName: String) async throws -> CodexRunResult {
        installedDisplayNames.append(displayName)
        if holdsCompletion {
            await withCheckedContinuation { continuation = $0 }
        }
        completedCount += 1
        return CodexRunResult(response: "Installed and verified", commandCount: 1, fileChangeCount: 0,
                              requiresUserAction: requiresUserAction)
    }

    func cancel() async { cancelCount += 1 }
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
