import Alamofire
import AppKit
import Combine
import Foundation

@MainActor
final class AppDownloadManager: ObservableObject {
    @Published private(set) var records: [AppDownloadRecord] = []
    @Published var isPresented = false

    private let fileManager: FileManager
    private let installer: MacApplicationInstaller
    private let session: Session
    private var requests: [UUID: DownloadRequest] = [:]
    private var resumeData: [UUID: Data] = [:]
    private let storeURL: URL
    private let resumeDirectory: URL
    private let downloadDirectory: URL

    init(
        fileManager: FileManager = .default,
        installer: MacApplicationInstaller = MacApplicationInstaller(),
        sessionConfiguration: URLSessionConfiguration = .default,
        appSupportDirectory: URL? = nil,
        downloadDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.installer = installer
        self.session = Session(configuration: sessionConfiguration)
        let appSupport = appSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("GitGatto", isDirectory: true)
        self.storeURL = appSupport.appendingPathComponent("downloads.json")
        self.resumeDirectory = appSupport.appendingPathComponent("DownloadResumeData", isDirectory: true)
        self.downloadDirectory = downloadDirectory
            ?? fileManager.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("GitGatto", isDirectory: true)
        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: resumeDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: self.downloadDirectory, withIntermediateDirectories: true)
        restore()
    }

    var activeCount: Int {
        records.filter { [.queued, .downloading, .installing].contains($0.state) }.count
    }

    func start(asset: GitHubReleaseAsset, repositoryName: String) {
        start(
            url: asset.downloadURL,
            fileName: asset.name,
            expectedBytes: asset.size,
            repositoryName: repositoryName,
            assetID: asset.id
        )
    }

    func start(
        url: URL,
        fileName: String,
        expectedBytes: Int64,
        repositoryName: String,
        assetID: Int64 = 0
    ) {
        guard url.scheme?.lowercased() == "https" else { return }
        if let existing = records.first(where: {
            $0.assetID == assetID && $0.sourceURL == url && $0.state != .cancelled
        }) {
            if existing.state == .failed || existing.state == .paused {
                resume(existing.id)
            }
            isPresented = true
            return
        }

        let id = UUID()
        let now = Date()
        let record = AppDownloadRecord(
            id: id,
            repositoryName: repositoryName,
            assetID: assetID,
            fileName: Self.safeFileName(fileName),
            sourceURL: url,
            expectedBytes: expectedBytes,
            destinationURL: nil,
            state: .queued,
            progress: 0,
            receivedBytes: 0,
            errorMessage: nil,
            createdAt: now,
            updatedAt: now
        )
        records.insert(record, at: 0)
        persist()
        begin(id: id, resumeData: nil)
        isPresented = true
    }

    func pause(_ id: UUID) {
        guard let request = requests[id] else { return }
        request.cancel(byProducingResumeData: { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                self.requests[id] = nil
                if let data {
                    self.resumeData[id] = data
                    try? data.write(to: self.resumeURL(for: id), options: .atomic)
                }
                self.update(id) {
                    $0.state = .paused
                    $0.updatedAt = Date()
                    $0.errorMessage = nil
                }
            }
        })
    }

    func resume(_ id: UUID) {
        guard let record = record(id), record.state == .paused || record.state == .failed else { return }
        let data = resumeData[id] ?? (try? Data(contentsOf: resumeURL(for: id)))
        begin(id: id, resumeData: data)
    }

    func cancel(_ id: UUID) {
        requests[id]?.cancel()
        requests[id] = nil
        resumeData[id] = nil
        try? fileManager.removeItem(at: resumeURL(for: id))
        update(id) {
            $0.state = .cancelled
            $0.updatedAt = Date()
            $0.errorMessage = nil
        }
    }

    func remove(_ id: UUID) {
        guard record(id)?.state != .downloading else { return }
        requests[id]?.cancel()
        requests[id] = nil
        resumeData[id] = nil
        try? fileManager.removeItem(at: resumeURL(for: id))
        records.removeAll { $0.id == id }
        persist()
    }

    func reveal(_ id: UUID) {
        guard let url = record(id)?.destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func install(_ id: UUID, replacingExisting: Bool = false) {
        guard let record = record(id), let url = record.destinationURL, record.canInstallOnMac else { return }
        update(id) {
            $0.state = .installing
            $0.errorMessage = nil
            $0.updatedAt = Date()
        }
        Task {
            do {
                _ = try await installer.install(url, replacingExisting: replacingExisting)
                update(id) {
                    $0.state = .installed
                    $0.updatedAt = Date()
                }
            } catch {
                update(id) {
                    $0.state = .completed
                    $0.errorMessage = error.localizedDescription
                    $0.updatedAt = Date()
                }
            }
        }
    }

    func record(_ id: UUID) -> AppDownloadRecord? {
        records.first { $0.id == id }
    }

    private func begin(id: UUID, resumeData data: Data?) {
        guard let record = record(id) else { return }
        let destinationURL = uniqueDestination(fileName: record.fileName, id: id)
        let destination: DownloadRequest.Destination = { _, _ in
            (destinationURL, [.createIntermediateDirectories, .removePreviousFile])
        }
        let request: DownloadRequest
        if let data {
            request = session.download(resumingWith: data, to: destination)
        } else {
            request = session.download(record.sourceURL, to: destination)
        }
        requests[id] = request
        resumeData[id] = nil
        try? fileManager.removeItem(at: resumeURL(for: id))
        update(id) {
            $0.state = .downloading
            $0.errorMessage = nil
            $0.updatedAt = Date()
        }

        request
            .validate(statusCode: 200..<400)
            .downloadProgress(queue: .main) { [weak self] progress in
                Task { @MainActor in
                    self?.update(id, persist: false) {
                        $0.progress = progress.fractionCompleted
                        $0.receivedBytes = progress.completedUnitCount
                        $0.updatedAt = Date()
                    }
                }
            }
            .response(queue: .main) { [weak self] response in
                Task { @MainActor in
                    guard let self else { return }
                    self.requests[id] = nil
                    if case let .success(url) = response.result, let url {
                        self.update(id) {
                            $0.destinationURL = url
                            $0.state = .completed
                            $0.progress = 1
                            $0.receivedBytes = max($0.receivedBytes, $0.expectedBytes)
                            $0.errorMessage = nil
                            $0.updatedAt = Date()
                        }
                    } else if self.record(id)?.state != .paused && self.record(id)?.state != .cancelled {
                        if let data = response.resumeData {
                            self.resumeData[id] = data
                            try? data.write(to: self.resumeURL(for: id), options: .atomic)
                        }
                        self.update(id) {
                            $0.state = .failed
                            $0.errorMessage = response.error?.localizedDescription ?? L10n.text("downloads.error.unknown")
                            $0.updatedAt = Date()
                        }
                    }
                }
            }
    }

    private func update(_ id: UUID, persist shouldPersist: Bool = true, _ mutation: (inout AppDownloadRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        mutation(&records[index])
        if shouldPersist { persist() }
    }

    private func restore() {
        guard let data = try? Data(contentsOf: storeURL),
              var saved = try? JSONDecoder().decode([AppDownloadRecord].self, from: data) else { return }
        for index in saved.indices where [.queued, .downloading, .installing].contains(saved[index].state) {
            saved[index].state = fileManager.fileExists(atPath: resumeURL(for: saved[index].id).path) ? .paused : .failed
            saved[index].errorMessage = saved[index].state == .failed ? L10n.text("downloads.error.interrupted") : nil
        }
        records = saved
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func resumeURL(for id: UUID) -> URL {
        resumeDirectory.appendingPathComponent("\(id.uuidString).resume")
    }

    private func uniqueDestination(fileName: String, id: UUID) -> URL {
        let base = downloadDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: base.path) else { return base }
        let stem = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        let name = ext.isEmpty ? "\(stem)-\(id.uuidString.prefix(8))" : "\(stem)-\(id.uuidString.prefix(8)).\(ext)"
        return downloadDirectory.appendingPathComponent(name)
    }

    private static func safeFileName(_ name: String) -> String {
        let sanitized = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return sanitized.isEmpty ? "download" : sanitized
    }
}
