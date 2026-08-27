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

    let currentVersion: String
    let currentBuild: String

    private var didStart = false
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        currentVersion = info["CFBundleShortVersionString"] as? String ?? "0.14.0"
        currentBuild = info["CFBundleVersion"] as? String ?? "33"
        state = Self.hasSignedUpdateConfiguration(info) ? .ready : .configurationRequired
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
        state = .failed(message: error.localizedDescription)
    }

    static func hasSignedUpdateConfiguration(_ info: [String: Any]) -> Bool {
        guard let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed),
              url.scheme?.lowercased() == "https",
              let publicKey = info["SUPublicEDKey"] as? String else {
            return false
        }
        return !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
