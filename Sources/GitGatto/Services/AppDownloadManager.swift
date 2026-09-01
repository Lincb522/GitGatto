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
    private let agentInstaller: any CodexServing
    private let session: Session
    private var requests: [UUID: DownloadRequest] = [:]
    private var installationTasks: [UUID: Task<Void, Never>] = [:]
    private var resumeData: [UUID: Data] = [:]
    private let storeURL: URL
    private let resumeDirectory: URL
    private let downloadDirectory: URL

    init(
        fileManager: FileManager = .default,
        installer: MacApplicationInstaller = MacApplicationInstaller(),
        agentInstaller: any CodexServing = CodexService(lane: .installer),
        sessionConfiguration: URLSessionConfiguration = .default,
        appSupportDirectory: URL? = nil,
        downloadDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.installer = installer
        self.agentInstaller = agentInstaller
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
#if DEBUG
        if ProcessInfo.processInfo.environment["GITGATTO_DOWNLOAD_PREVIEW"] == "1" {
            records = Self.previewRecords()
            isPresented = true
        }
#endif
    }

    var activeCount: Int {
        records.filter { [.queued, .downloading, .installing].contains($0.state) }.count
    }

#if DEBUG
    private static func previewRecords() -> [AppDownloadRecord] {
        let now = Date()
        let samples: [(String, AppDownloadState, Double, Int64)] = [
            ("GitGatto-0.19.0.dmg", .downloading, 0.64, 76_800_000),
            ("GitGatto-symbols.zip", .paused, 0.38, 24_200_000),
            ("GitGatto-0.18.5.dmg", .completed, 1, 74_600_000),
            ("GitGatto-Tools.pkg", .installing, 1, 12_400_000)
        ]
        return samples.enumerated().map { index, sample in
            AppDownloadRecord(
                id: UUID(),
                repositoryName: "Lincb522/GitGatto",
                assetID: Int64(index + 1),
                fileName: sample.0,
                sourceURL: URL(fileURLWithPath: "/tmp/\(sample.0)"),
                expectedBytes: sample.3,
                destinationURL: sample.1 == .completed
                    ? URL(fileURLWithPath: "/tmp/\(sample.0)")
                    : nil,
                state: sample.1,
                progress: sample.2,
                receivedBytes: Int64(Double(sample.3) * sample.2),
                errorMessage: nil,
                createdAt: now.addingTimeInterval(Double(-index * 900)),
                updatedAt: now
            )
        }
    }
#endif

    func start(asset: GitHubReleaseAsset, repositoryName: String) {
        start(
            url: asset.downloadURL,
            fileName: asset.name,
            expectedBytes: asset.size,
            repositoryName: repositoryName,
            assetID: asset.id
        )
    }

    func quickInstall(asset: GitHubReleaseAsset, repositoryName: String) {
        start(
            url: asset.downloadURL,
            fileName: asset.name,
            expectedBytes: asset.size,
            repositoryName: repositoryName,
            assetID: asset.id,
            installAfterDownload: true
        )
    }

    func start(
        url: URL,
        fileName: String,
        expectedBytes: Int64,
        repositoryName: String,
        assetID: Int64 = 0,
        installAfterDownload: Bool = false
    ) {
        guard url.scheme?.lowercased() == "https" else { return }
        if let existing = records.first(where: {
            $0.assetID == assetID && $0.sourceURL == url && $0.state != .cancelled
        }) {
            if installAfterDownload {
                update(existing.id) {
                    $0.installAfterDownload = true
                    $0.errorMessage = nil
                }
            }
            if existing.state == .failed || existing.state == .paused {
                resume(existing.id)
            } else if installAfterDownload, existing.state == .completed {
                install(existing.id, replacingExisting: true)
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
            installAfterDownload: installAfterDownload,
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
        if record(id)?.state == .installing {
            cancelInstallation(id)
            return
        }
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
        guard let state = record(id)?.state, state != .downloading, state != .installing else { return }
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
        guard let record = record(id), let url = record.destinationURL, record.state == .completed else { return }
        if record.canInstallOnMac {
            installNatively(id, url: url, replacingExisting: replacingExisting)
        } else {
            installWithAgent(id)
        }
    }

    func installWithAgent(_ id: UUID) {
        guard let record = record(id), let url = record.destinationURL, record.state == .completed else { return }
        installationTasks[id]?.cancel()
        update(id) {
            $0.state = .installing
            $0.installationMethod = .agent
            $0.installationPhase = .preparing
            $0.installationMessage = L10n.text("installer.phase.preparing")
            $0.agentResult = nil
            $0.errorMessage = nil
            $0.updatedAt = Date()
        }
        let agentInstaller = self.agentInstaller
        installationTasks[id] = Task {
            do {
                let result = try await agentInstaller.installDownloadedArtifact(
                    at: url,
                    displayName: record.repositoryName
                ) { [weak self] progress in
                    await MainActor.run {
                        self?.apply(progress, to: id)
                    }
                }
                guard !Task.isCancelled else { return }
                update(id) {
                    $0.state = .installed
                    $0.installationPhase = nil
                    $0.installationMessage = nil
                    $0.agentResult = result.response
                    $0.updatedAt = Date()
                }
            } catch is CancellationError {
                update(id) {
                    $0.state = .completed
                    $0.installationPhase = nil
                    $0.installationMessage = nil
                    $0.errorMessage = L10n.text("installer.error.cancelled")
                    $0.updatedAt = Date()
                }
            } catch {
                update(id) {
                    $0.state = .completed
                    $0.installationPhase = nil
                    $0.installationMessage = nil
                    $0.errorMessage = error.localizedDescription
                    $0.updatedAt = Date()
                }
            }
            installationTasks[id] = nil
        }
    }

    func cancelInstallation(_ id: UUID) {
        guard record(id)?.state == .installing else { return }
        installationTasks[id]?.cancel()
        installationTasks[id] = nil
        let agentInstaller = self.agentInstaller
        Task { await agentInstaller.cancel() }
        update(id) {
            $0.state = .completed
            $0.installationPhase = nil
            $0.installationMessage = nil
            $0.errorMessage = L10n.text("installer.error.cancelled")
            $0.updatedAt = Date()
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
                        if self.record(id)?.shouldInstallAutomatically == true {
                            self.install(id, replacingExisting: true)
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
            if saved[index].state == .installing, saved[index].destinationURL != nil {
                saved[index].state = .completed
                saved[index].errorMessage = L10n.text("installer.error.interrupted")
                saved[index].installationPhase = nil
                saved[index].installationMessage = nil
            } else {
                saved[index].state = fileManager.fileExists(atPath: resumeURL(for: saved[index].id).path) ? .paused : .failed
                saved[index].errorMessage = saved[index].state == .failed ? L10n.text("downloads.error.interrupted") : nil
            }
        }
        records = saved
    }

    private func installNatively(_ id: UUID, url: URL, replacingExisting: Bool) {
        installationTasks[id]?.cancel()
        update(id) {
            $0.state = .installing
            $0.installationMethod = .native
            $0.installationPhase = .preparing
            $0.installationMessage = L10n.text("installer.phase.preparing")
            $0.agentResult = nil
            $0.errorMessage = nil
            $0.updatedAt = Date()
        }
        installationTasks[id] = Task {
            do {
                update(id) {
                    $0.installationPhase = .installing
                    $0.installationMessage = L10n.text("installer.phase.installing")
                }
                _ = try await installer.install(url, replacingExisting: replacingExisting)
                guard !Task.isCancelled else { return }
                update(id) {
                    $0.state = .installed
                    $0.installationPhase = nil
                    $0.installationMessage = nil
                    $0.updatedAt = Date()
                }
            } catch is CancellationError {
                update(id) {
                    $0.state = .completed
                    $0.installationPhase = nil
                    $0.installationMessage = nil
                    $0.errorMessage = L10n.text("installer.error.cancelled")
                }
            } catch {
                if record(id)?.shouldInstallAutomatically == true {
                    update(id) {
                        $0.state = .completed
                        $0.installationPhase = nil
                        $0.installationMessage = nil
                    }
                    installationTasks[id] = nil
                    Task { @MainActor [weak self] in
                        self?.installWithAgent(id)
                    }
                    return
                }
                update(id) {
                    $0.state = .completed
                    $0.installationPhase = nil
                    $0.installationMessage = nil
                    $0.errorMessage = error.localizedDescription
                    $0.updatedAt = Date()
                }
            }
            installationTasks[id] = nil
        }
    }

    private func apply(_ progress: AgentInstallProgress, to id: UUID) {
        update(id) {
            $0.installationPhase = switch progress.phase {
            case .preparing: .preparing
            case .inspecting: .inspecting
            case .installing: .installing
            case .configuring: .configuring
            case .verifying: .verifying
            }
            $0.installationMessage = progress.detail
                ?? L10n.text("installer.phase.\(progress.phase.rawValue)")
            $0.updatedAt = Date()
        }
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
