@preconcurrency import AppKit
import SwiftUI

@main
struct GitGattoApp: App {
    @NSApplicationDelegateAdaptor(GitGattoAppDelegate.self) private var appDelegate
    @StateObject private var model = WorkspaceViewModel()
    @StateObject private var appNavigation = AppNavigationModel()
    @StateObject private var updateManager = AppUpdateManager()
    @State private var showsLaunchAnimation: Bool
    @State private var isWorkspaceReady = false

    init() {
        let preferences = AppPreferencesStore.load()
        let holdsForPreview = ProcessInfo.processInfo.environment["GITGATTO_LAUNCH_PREVIEW"] == "1"
#if DEBUG
        let capturesSnapshot = ProcessInfo.processInfo.arguments.contains("--snapshot")
#else
        let capturesSnapshot = false
#endif
        _showsLaunchAnimation = State(
            initialValue: !capturesSnapshot && (preferences.launchAnimationEnabled || holdsForPreview)
        )
    }

    var body: some Scene {
        WindowGroup {
            AppThemeRoot {
                ZStack {
                    LaunchWorkspaceLayer(isLaunching: showsLaunchAnimation) {
#if DEBUG
                        workspace.overlay { DebugPreviewLauncher(model: model) }
#else
                        workspace
#endif
                    }
                    if showsLaunchAnimation {
                        GitGattoLaunchOverlay(
                            isContentReady: $isWorkspaceReady,
                            holdsForPreview: ProcessInfo.processInfo.environment["GITGATTO_LAUNCH_PREVIEW"] == "1"
                        ) {
                            showsLaunchAnimation = false
                        }
                        .transition(.opacity)
                        .zIndex(10)
                    }
                }
                .background {
                    MainWindowCloseBehaviorBridge(
                        behavior: model.appPreferences.windowCloseBehavior,
                        remember: { behavior in
                            model.rememberWindowCloseBehavior(behavior)
                        }
                    )
                    .frame(width: 0, height: 0)
                }
            }
            .appLocalization(model.appPreferences.language)
        }
        .defaultSize(width: 1416, height: 878)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            GitGattoCommands(model: model, updateManager: updateManager)
        }

        Window(L10n.text("about.title"), id: "about") {
            AppThemeRoot {
                AboutGitGattoView(
                    navigation: appNavigation,
                    updateManager: updateManager
                )
            }
            .appLocalization(model.appPreferences.language)
        }
        .defaultSize(width: 660, height: 361)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Window(L10n.text("update.title"), id: "updates") {
            AppThemeRoot { UpdateCenterView(manager: updateManager) }
                .appLocalization(model.appPreferences.language)
        }
        .defaultSize(width: 760, height: 720)
        .windowStyle(.hiddenTitleBar)

        Window(L10n.text("release_history.title"), id: "release-history") {
            AppThemeRoot { ReleaseHistoryView(manager: updateManager) }
                .appLocalization(model.appPreferences.language)
        }
        .defaultSize(width: 900, height: 640)
        .windowStyle(.hiddenTitleBar)

        Window(L10n.text("legal.title"), id: "legal-documents") {
            AppThemeRoot { LegalDocumentsView(navigation: appNavigation) }
                .appLocalization(model.appPreferences.language)
        }
        .defaultSize(width: 920, height: 680)
        .windowStyle(.hiddenTitleBar)

        Window(L10n.text("help.title"), id: "help") {
            AppThemeRoot { HelpCenterView() }
                .appLocalization(model.appPreferences.language)
        }
        .defaultSize(width: 900, height: 650)
        .windowStyle(.hiddenTitleBar)

        Window(L10n.text("repository.scan.title"), id: "repository-scanner") {
            AppThemeRoot { RepositoryScannerView(model: model) }
                .appLocalization(model.appPreferences.language)
        }
        .defaultSize(width: 760, height: 620)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra(
            isInserted: Binding(
                get: { model.appPreferences.statusBarMonitoringEnabled },
                set: { model.setStatusBarMonitoringEnabled($0) }
            )
        ) {
            AppThemeRoot {
                MonitoringStatusBarView(model: model, engine: model.monitoringEngine)
            }
            .appLocalization(model.appPreferences.language)
        } label: {
            MonitoringMenuBarLabel(engine: model.monitoringEngine)
        }
        .menuBarExtraStyle(.window)

#if DEBUG
        Window("Monitoring", id: "monitoring-status-preview") {
            AppThemeRoot {
                MonitoringStatusBarView(model: model, engine: model.monitoringEngine)
            }
            .appLocalization(model.appPreferences.language)
        }
        .defaultSize(width: 430, height: 620)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
#endif

        Settings {
            AppThemeRoot(resetsContentOnStyleChange: false) {
                AppSettingsView(model: model, updateManager: updateManager)
            }
            .appLocalization(model.appPreferences.language)
        }
        .defaultSize(width: 900, height: 700)
        .windowStyle(.hiddenTitleBar)
    }

    private var workspace: some View {
            WorkspaceView(
                model: model,
                onInitialContentReady: { isWorkspaceReady = true },
                canCaptureSnapshot: !showsLaunchAnimation
                    || ProcessInfo.processInfo.environment["GITGATTO_LAUNCH_PREVIEW"] == "1"
            )
                .frame(minWidth: 960, minHeight: 620)
                .task {
                    await model.start()
#if DEBUG
                    if !ProcessInfo.processInfo.arguments.contains("--snapshot") {
                        updateManager.startIfConfigured()
                    }
#else
                    updateManager.startIfConfigured()
#endif
                }
    }
}

private extension View {
    func appLocalization(_ language: AppLanguage) -> some View {
        environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.usesRightToLeftLayout ? .rightToLeft : .leftToRight)
    }
}

private struct MainWindowCloseBehaviorBridge: NSViewRepresentable {
    let behavior: WindowCloseBehavior
    let remember: (WindowCloseBehavior) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(behavior: behavior, remember: remember)
    }

    func makeNSView(context: Context) -> WindowProbeView {
        let view = WindowProbeView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.install(on: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowProbeView, context: Context) {
        context.coordinator.behavior = behavior
        context.coordinator.remember = remember
        context.coordinator.install(on: nsView.window)
    }

    static func dismantleNSView(_ nsView: WindowProbeView, coordinator: Coordinator) {
        nsView.onWindowChange = nil
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator: NSObject {
        var behavior: WindowCloseBehavior
        var remember: (WindowCloseBehavior) -> Void

        private weak var window: NSWindow?
        private var delegateProxy: MainWindowCloseDelegateProxy?

        init(
            behavior: WindowCloseBehavior,
            remember: @escaping (WindowCloseBehavior) -> Void
        ) {
            self.behavior = behavior
            self.remember = remember
        }

        func install(on window: NSWindow?) {
            guard let window, self.window !== window else { return }
            uninstall()

            let proxy = MainWindowCloseDelegateProxy(
                forwardedDelegate: window.delegate,
                behavior: { [weak self] in self?.behavior ?? .ask },
                remember: { [weak self] behavior in self?.remember(behavior) }
            )
            self.window = window
            delegateProxy = proxy
            window.delegate = proxy
        }

        func uninstall() {
            guard let window, let delegateProxy else { return }
            if window.delegate === delegateProxy {
                window.delegate = delegateProxy.forwardedDelegate
            }
            self.window = nil
            self.delegateProxy = nil
        }
    }
}

private final class WindowProbeView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

@MainActor
private final class MainWindowCloseDelegateProxy: NSObject, NSWindowDelegate {
    nonisolated(unsafe) let forwardedDelegate: (any NSWindowDelegate)?

    private let behavior: () -> WindowCloseBehavior
    private let remember: (WindowCloseBehavior) -> Void
    private var isShowingPrompt = false

    init(
        forwardedDelegate: (any NSWindowDelegate)?,
        behavior: @escaping () -> WindowCloseBehavior,
        remember: @escaping (WindowCloseBehavior) -> Void
    ) {
        self.forwardedDelegate = forwardedDelegate
        self.behavior = behavior
        self.remember = remember
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if WindowCloseRuntime.isTerminating {
            return forwardedDelegate?.windowShouldClose?(sender) ?? true
        }

        switch behavior() {
        case .ask:
            presentClosePrompt(for: sender)
        case .minimize:
            sender.miniaturize(nil)
        case .quit:
            WindowCloseRuntime.quit()
        }
        return false
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || forwardedDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if forwardedDelegate?.responds(to: selector) == true {
            return forwardedDelegate
        }
        return super.forwardingTarget(for: selector)
    }

    private func presentClosePrompt(for window: NSWindow) {
        guard !isShowingPrompt else { return }
        isShowingPrompt = true

        let rememberChoice = NSButton(
            checkboxWithTitle: L10n.text("window.close.remember"),
            target: nil,
            action: nil
        )
        rememberChoice.frame = NSRect(x: 0, y: 0, width: 260, height: 22)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("window.close.title")
        alert.informativeText = L10n.text("window.close.message")
        alert.addButton(withTitle: L10n.text("window.close.minimize"))
        alert.addButton(withTitle: L10n.text("window.close.quit"))
        alert.accessoryView = rememberChoice
        alert.beginSheetModal(for: window) { [weak self, weak window] response in
            guard let self else { return }
            self.isShowingPrompt = false

            let choice: WindowCloseBehavior = response == .alertFirstButtonReturn ? .minimize : .quit
            if rememberChoice.state == .on {
                self.remember(choice)
            }

            switch choice {
            case .ask:
                break
            case .minimize:
                window?.miniaturize(nil)
            case .quit:
                WindowCloseRuntime.quit()
            }
        }
    }
}

private struct LaunchWorkspaceLayer<Content: View>: View {
    let isLaunching: Bool
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isLaunching: Bool, @ViewBuilder content: () -> Content) {
        self.isLaunching = isLaunching
        self.content = content()
    }

    var body: some View {
        content
            .blur(radius: isLaunching && !reduceMotion ? 12 : 0)
            .opacity(isLaunching ? 0.82 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.20) : .easeOut(duration: 0.36),
                value: isLaunching
            )
    }
}

#if DEBUG
private struct DebugPreviewLauncher: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var didOpen = false

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                guard !didOpen else { return }
                let environment = ProcessInfo.processInfo.environment
                let destination: String?
                if environment["GITGATTO_SETTINGS_PREVIEW"] == "1" {
                    destination = "settings"
                } else if environment["GITGATTO_ABOUT_PREVIEW"] == "1" {
                    destination = "about"
                } else if environment["GITGATTO_UPDATE_PREVIEW"] == "1" {
                    destination = "updates"
                } else if environment["GITGATTO_RELEASE_HISTORY_PREVIEW"] == "1" {
                    destination = "release-history"
                } else if environment["GITGATTO_LEGAL_PREVIEW"] == "1" {
                    destination = "legal-documents"
                } else if environment["GITGATTO_HELP_PREVIEW"] == "1" {
                    destination = "help"
                } else if environment["GITGATTO_SCANNER_PREVIEW"] == "1" {
                    destination = "repository-scanner"
                } else if environment["GITGATTO_MONITORING_PREVIEW"] == "1" {
                    destination = "monitoring-status-preview"
                } else {
                    destination = nil
                }
                guard let destination else { return }
                didOpen = true
                try? await Task.sleep(for: .seconds(2))
                NSApp.activate(ignoringOtherApps: true)
                if destination == "settings" {
                    openSettings()
                } else {
                    if destination == "repository-scanner",
                       let root = Self.scanRootFromArguments() {
                        model.scanForRepositories(in: [root])
                    }
                    openWindow(id: destination)
                }
            }
    }

    private static func scanRootFromArguments() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--scan-root"),
              arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }
}
#endif

private struct GitGattoCommands: Commands {
    @ObservedObject var model: WorkspaceViewModel
    @ObservedObject var updateManager: AppUpdateManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L10n.text("about.title")) {
                openWindow(id: "about")
            }

            Button(L10n.text("update.check")) {
                updateManager.checkForUpdates()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button(L10n.text("action.open_repository")) {
                model.chooseRepository()
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button(L10n.text("repository.scan.open")) {
                openWindow(id: "repository-scanner")
            }

            Divider()

            Menu(L10n.text("menu.file.open_recent")) {
                if model.recentRepositories.isEmpty {
                    Button(L10n.text("menu.file.no_recent")) {}
                        .disabled(true)
                } else {
                    ForEach(model.recentRepositories, id: \.path) { url in
                        Button(url.lastPathComponent) {
                            Task { await model.openRepository(url) }
                        }
                        .help(url.path)
                    }
                }
            }
        }

        CommandGroup(after: .sidebar) {
            Divider()
            workspaceCommand(.github, shortcut: "1")
            workspaceCommand(.marketplace, shortcut: "2")
            workspaceCommand(.changes, shortcut: "3")
            workspaceCommand(.history, shortcut: "4")
            workspaceCommand(.branches, shortcut: "5")
            workspaceCommand(.codex, shortcut: "6")
            workspaceCommand(.timeMachine, shortcut: "7")
            workspaceCommand(.diagnostics, shortcut: "8")
            workspaceCommand(.goals, shortcut: "9")
        }

        CommandMenu(L10n.text("menu.repository")) {
            Button(L10n.text("action.refresh")) {
                Task { await model.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.snapshot == nil || model.isRefreshing)

            Divider()

            Button(L10n.text("action.reveal_repository")) {
                model.revealRepositoryInFinder()
            }
            .disabled(model.snapshot == nil)

            Button(L10n.text("action.copy_repository_path")) {
                model.copyRepositoryPath()
            }
            .disabled(model.snapshot == nil)

            Divider()

            Button(L10n.text("action.pull")) {
                Task { await model.pull() }
            }
            .disabled(model.snapshot == nil || model.activeOperation != nil)

            Button(L10n.text("action.push")) {
                Task { await model.push() }
            }
            .disabled(model.snapshot == nil || model.activeOperation != nil)

            Divider()

            Button(L10n.text("action.stage_all")) {
                if let changes = model.snapshot?.unstagedChanges {
                    Task { await model.stage(changes) }
                }
            }
            .disabled(model.snapshot?.unstagedChanges.isEmpty != false || model.activeOperation != nil)

            Button(L10n.text("action.unstage_all")) {
                if let changes = model.snapshot?.stagedChanges {
                    Task { await model.unstage(changes) }
                }
            }
            .disabled(model.snapshot?.stagedChanges.isEmpty != false || model.activeOperation != nil)

            Button(L10n.text("action.commit")) {
                Task { await model.commit() }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(
                model.snapshot?.stagedChanges.isEmpty != false
                    || model.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.activeOperation != nil
            )
        }

        CommandGroup(replacing: .help) {
            Button(L10n.text("help.menu.guide")) {
                openWindow(id: "help")
            }
            .keyboardShortcut("?", modifiers: .command)

            Divider()

            Button(L10n.text("settings.open")) {
                openSettings()
            }
        }
    }

    private func workspaceCommand(_ section: WorkspaceSection, shortcut: KeyEquivalent) -> some View {
        Button(L10n.text("nav.\(section.rawValue)")) {
            model.selectedSection = section
        }
        .keyboardShortcut(shortcut, modifiers: .command)
    }
}
