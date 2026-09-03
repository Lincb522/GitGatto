import Combine
import Foundation
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
    private var didLoadGitHubReleaseNotes = false
    private let releaseService = GitHubReleaseService()
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        currentVersion = info["CFBundleShortVersionString"] as? String ?? "0.18.15"
        currentBuild = info["CFBundleVersion"] as? String ?? "18015"
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

    func startIfConfigured() {
        guard isConfigured, !didStart else { return }
        didStart = true
        updaterController.startUpdater()
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updaterController.updater.automaticallyDownloadsUpdates
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        startIfConfigured()
        state = .checking
        lastCheckedAt = Date()
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
        lastCheckedAt = Date()
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

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        state = .updateAvailable(
            version: item.displayVersionString,
            build: item.versionString
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        state = .current
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        state = Self.stateAfterAborting(with: error)
    }

    static func stateAfterAborting(with error: any Error) -> AppUpdateState {
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain,
           nsError.code == Int(SUError.noUpdateError.rawValue) {
            return .current
        }
        return .failed(message: failureMessage(for: nsError))
    }

    static func failureMessage(for error: NSError) -> String {
        var details = [error.localizedDescription]
        if let reason = error.localizedFailureReason, !details.contains(reason) {
            details.append(reason)
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            let description = underlying.localizedDescription
            if !details.contains(description) {
                details.append(description)
            }
            if let reason = underlying.localizedFailureReason, !details.contains(reason) {
                details.append(reason)
            }
        }
        details.append("\(error.domain) · \(error.code)")
        return details.joined(separator: "\n")
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
