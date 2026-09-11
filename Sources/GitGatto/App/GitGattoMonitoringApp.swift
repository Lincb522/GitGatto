import AppKit
import OSLog
import SwiftUI

struct GitGattoMonitoringApp: App {
    @NSApplicationDelegateAdaptor(MonitoringHelperDelegate.self) private var delegate
    @StateObject private var host = MonitoringHelperHost.shared

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(host.model?.appPreferences.statusBarMonitoringEnabled == true)) {
            if let model = host.model {
                AppThemeRoot {
                    MonitoringStatusBarView(model: model, engine: model.monitoringEngine)
                }
                .environment(\.locale, model.appPreferences.language.locale)
                .environment(\.layoutDirection, model.appPreferences.language.usesRightToLeftLayout ? .rightToLeft : .leftToRight)
            }
        } label: {
            if let model = host.model { MonitoringMenuBarLabel(model: model) }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class MonitoringHelperHost: ObservableObject {
    static let shared = MonitoringHelperHost()
    @Published private(set) var model: WorkspaceViewModel?
    private var task: Task<Void, Never>?
    private let logger = Logger(subsystem: "dev.gitgatto.monitor", category: "lifecycle")
    private let rootURL: URL
    private let loadPreferences: @MainActor () -> AppPreferences
    private let makeWorkspace: @MainActor () -> WorkspaceViewModel
    private let didFail: @MainActor (any Error) -> Void

    init(rootURL: URL = MonitoringProcessLease.rootURL,
         loadPreferences: @escaping @MainActor () -> AppPreferences = { AppPreferencesStore.load() },
         makeWorkspace: @escaping @MainActor () -> WorkspaceViewModel = { WorkspaceViewModel(isBackgroundMonitor: true) },
         didFail: @escaping @MainActor (any Error) -> Void = { _ in exit(EXIT_FAILURE) }) {
        self.rootURL = rootURL
        self.loadPreferences = loadPreferences
        self.makeWorkspace = makeWorkspace
        self.didFail = didFail
    }

    func start() {
        guard task == nil else { return }
        task = Task {
            var heldRuntime: MonitoringProcessLease?
            defer { heldRuntime?.release() }
            do {
                let presence = try MonitoringProcessLease(url: rootURL.appendingPathComponent("foreground.lock"))
                let runtime = try MonitoringProcessLease(url: rootURL.appendingPathComponent("runtime.lock"))
                heldRuntime = runtime
                while !Task.isCancelled {
                    let preferences = loadPreferences()
                    let foregroundAbsent = try presence.acquire()
                    presence.release()
                    if foregroundAbsent, preferences.backgroundMonitoringEnabled,
                       preferences.monitoringEngineEnabled, try runtime.acquire() {
                        // Recheck after acquiring the runtime lease; the UI may have started in between.
                        guard try presence.acquire() else {
                            runtime.release()
                            try await Task.sleep(for: .seconds(1))
                            continue
                        }
                        presence.release()
                        let workspace = makeWorkspace()
                        L10n.activate(workspace.appPreferences.language)
                        model = workspace
                        logger.info("Background monitoring acquired the runtime lease")
                        await workspace.startBackgroundMonitoring()
                        while !Task.isCancelled {
                            guard try presence.acquire() else { break }
                            presence.release()
                            try await Task.sleep(for: .seconds(1))
                        }
                        model = nil
                        await workspace.stopBackgroundMonitoring()
                        runtime.release()
                        logger.info("Background monitoring released the runtime lease")
                    }
                    try await Task.sleep(for: .seconds(1))
                }
            } catch is CancellationError {
                if let model { await model.stopBackgroundMonitoring() }
                model = nil
            } catch {
                logger.error("Background monitoring stopped: \(error.localizedDescription)")
                if let model { await model.stopBackgroundMonitoring() }
                model = nil
                // A failed login item must exit nonzero so ServiceManagement can restart it.
                didFail(error)
            }
        }
    }

    func stop() async {
        task?.cancel()
        await task?.value
        task = nil
    }

    static func openApplication(category: MonitoringCategory? = nil, repository: URL? = nil, settings: Bool = false) {
        // The signed helper lives at Main.app/Contents/Library/LoginItems/Helper.app.
        let application = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        var arguments: [String] = []
        if let category { arguments += ["--monitoring-channel", category.rawValue] }
        if let repository { arguments += ["--repository", repository.path] }
        if settings { arguments += ["--monitoring-settings"] }
        configuration.arguments = arguments
        NSWorkspace.shared.openApplication(at: application, configuration: configuration) { _, error in
            if let error {
                Logger(subsystem: "dev.gitgatto.monitor", category: "lifecycle")
                    .error("Could not open GitGatto: \(error.localizedDescription)")
            }
        }
    }
}

@MainActor
final class MonitoringHelperDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { MonitoringHelperHost.shared.start() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await MonitoringHelperHost.shared.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

struct MonitoringSettingsLaunchAction: View {
    let model: WorkspaceViewModel
    let ready: Bool
    @Environment(\.openSettings) private var openSettings
    @State private var handled = false

    var body: some View {
        Color.clear.frame(width: 0, height: 0).task(id: ready) {
            guard ready, !handled, ProcessInfo.processInfo.arguments.contains("--monitoring-settings") else { return }
            handled = true
            model.settingsDestination = "monitoring"
            openSettings()
        }
    }
}
