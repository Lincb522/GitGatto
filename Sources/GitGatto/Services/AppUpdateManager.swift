import Combine
import Foundation
import OSLog
import Sparkle

enum AppUpdateState: Equatable {
    case configurationRequired
    case ready
    case checking
    case current
    case updateAvailable(version: String, build: String)
    case failed(message: String)
}

@MainActor
final class AppUpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var stage: AppUpdateStage = .unknown
    @Published private(set) var diagnostic: AppUpdateDiagnostic?
    @Published private(set) var state: AppUpdateState
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var releaseNotes: [AppReleaseNote]
    @Published private(set) var releaseNotesSource: AppReleaseNotesSource = .bundled
    @Published private(set) var isLoadingReleaseNotes = false
    @Published private(set) var releaseNotesError: String?

    let currentVersion: String
    let currentBuild: String

    private var didStart = false
    private let logger = Logger(subsystem: "dev.gitgatto.client", category: "updates")
    private var didLoadGitHubReleaseNotes = false
    private let releaseService = GitHubReleaseService()
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        currentVersion = info["CFBundleShortVersionString"] as? String ?? "0.18.32"
        currentBuild = info["CFBundleVersion"] as? String ?? "18032"
        releaseNotes = Self.bundledReleaseNotes(version: currentVersion)
        state = Self.hasUpdateConfiguration(info) ? .ready : .configurationRequired
        super.init()
    }

    var isConfigured: Bool {
        if case .configurationRequired = state { return false }
        return true
    }

    var canCheckForUpdates: Bool {
        isConfigured && state != .checking
    }

    func startIfConfigured(checkOnLaunch: Bool = false) {
        guard isConfigured, !didStart else { return }
        didStart = true
        updaterController.startUpdater()
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updaterController.updater.automaticallyDownloadsUpdates
        lastCheckedAt = updaterController.updater.lastUpdateCheckDate
        if checkOnLaunch && automaticallyChecksForUpdates {
            updaterController.updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        startIfConfigured()
        state = .checking
        stage = .checking
        diagnostic = nil
        Task { await refreshReleaseNotes(force: true) }
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard isConfigured else { return }
        startIfConfigured()
        updaterController.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard isConfigured else { return }
        startIfConfigured()
        updaterController.updater.automaticallyDownloadsUpdates = enabled
        automaticallyDownloadsUpdates = enabled
    }

    func refreshReleaseNotes(force: Bool = false) async {
        guard !isLoadingReleaseNotes else { return }
        guard force || !didLoadGitHubReleaseNotes else { return }

        isLoadingReleaseNotes = true
        releaseNotesError = nil
        defer { isLoadingReleaseNotes = false }

        do {
            let githubReleaseNotes = try await releaseService.releases()
            try Task.checkCancellation()
            didLoadGitHubReleaseNotes = true
            if githubReleaseNotes.isEmpty {
                releaseNotesError = L10n.text("update.release_notes.empty")
            } else {
                releaseNotes = githubReleaseNotes
                releaseNotesSource = .github
            }
        } catch is CancellationError {
            return
        } catch {
            didLoadGitHubReleaseNotes = true
            releaseNotesError = L10n.text("update.release_notes.failed")
        }
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        state = .checking
        stage = .checking
        diagnostic = nil
        lastCheckedAt = Date()
        logger.info("Update check started; kind=\(updateCheck.rawValue)")
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        logger.info("Update available; build=\(item.versionString, privacy: .public)")
        state = .updateAvailable(
            version: item.displayVersionString,
            build: item.versionString
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        state = .current
        logger.info("Update check finished; no newer version")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        recordUpdateFailure(error)
    }

    func recordUpdateFailure(_ error: any Error) {
        state = Self.stateAfterAborting(with: error)
        if case .failed = state { diagnostic = .make(error: error as NSError, lastStage: stage) }
        else { diagnostic = nil }
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        stage = .downloading
        diagnostic = nil
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) { stage = .verifying }
    func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) { stage = .verifying }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { stage = .installing }


    static func stateAfterAborting(with error: any Error) -> AppUpdateState {
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain,
           nsError.code == Int(SUError.noUpdateError.rawValue) {
            return .current
        }
        return .failed(message: failureMessage(for: nsError))
    }

    static func failureMessage(for error: NSError) -> String {
        let chain = errorChain(for: error)
        var details: [String] = []
        if chain.contains(where: {
            $0.domain == SUSparkleErrorDomain
                && $0.localizedDescription.contains("Timeout: agent connection was never initiated")
        }) {
            details.append(L10n.text("update.error.helper_startup_timeout"))
        }
        for item in chain {
            for detail in [
                item.localizedDescription,
                item.localizedFailureReason,
                item.localizedRecoverySuggestion
            ].compactMap({ $0 }) where !detail.isEmpty && !details.contains(detail) {
                details.append(detail)
            }
        }
        details.append(chain.map { "\($0.domain) · \($0.code)" }.joined(separator: " → "))
        return ProjectCommandOutput.redact(details.joined(separator: "\n"))
    }

    private static func errorChain(for error: NSError) -> [NSError] {
        var chain: [NSError] = []
        var visited: Set<ObjectIdentifier> = []
        var current: NSError? = error
        while let item = current, visited.insert(ObjectIdentifier(item)).inserted, chain.count < 16 {
            chain.append(item)
            current = item.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return chain
    }

    static func hasUpdateConfiguration(_ info: [String: Any]) -> Bool {
        guard let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed),
              url.scheme?.lowercased() == "https" else {
            return false
        }
        return true
    }

    private static func bundledReleaseNotes(version: String) -> [AppReleaseNote] {
        guard let url = L10n.localizedDocumentURL(named: "ReleaseNotes"),
              let body = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return [
            AppReleaseNote(
                id: "bundled-\(version)",
                version: version,
                title: L10n.format("update.release_notes.current", version),
                body: ReleaseNotesContentFilter.userFacing(body),
                publishedAt: nil,
                webURL: AppLinks.releases,
                isPrerelease: false
            )
        ]
    }
}
