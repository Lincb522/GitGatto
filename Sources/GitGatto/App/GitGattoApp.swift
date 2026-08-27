import AppKit
import SwiftUI

@main
struct GitGattoApp: App {
    @NSApplicationDelegateAdaptor(GitGattoAppDelegate.self) private var appDelegate
    @StateObject private var model = WorkspaceViewModel()
    @StateObject private var appNavigation = AppNavigationModel()
    @StateObject private var updateManager = AppUpdateManager()

    var body: some Scene {
        WindowGroup {
            AppThemeRoot {
#if DEBUG
                workspace.overlay { DebugPreviewLauncher(model: model) }
#else
                workspace
#endif
            }
        }
        .defaultSize(width: 1280, height: 780)
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
        }
        .defaultSize(width: 680, height: 520)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Window(L10n.text("update.title"), id: "updates") {
            AppThemeRoot { UpdateCenterView(manager: updateManager) }
        }
        .defaultSize(width: 660, height: 540)
        .windowStyle(.hiddenTitleBar)

        Window(L10n.text("legal.title"), id: "legal-documents") {
            AppThemeRoot { LegalDocumentsView(navigation: appNavigation) }
        }
        .defaultSize(width: 920, height: 680)
        .windowStyle(.hiddenTitleBar)

        Window(L10n.text("help.title"), id: "help") {
            AppThemeRoot { HelpCenterView() }
        }
        .defaultSize(width: 900, height: 650)
        .windowStyle(.hiddenTitleBar)

        Window(L10n.text("repository.scan.title"), id: "repository-scanner") {
            AppThemeRoot { RepositoryScannerView(model: model) }
        }
        .defaultSize(width: 760, height: 620)
        .windowStyle(.hiddenTitleBar)

        Settings {
            AppThemeRoot(resetsContentOnStyleChange: false) { AppSettingsView(model: model) }
        }
        .defaultSize(width: 900, height: 700)
        .windowStyle(.hiddenTitleBar)
    }

    private var workspace: some View {
            WorkspaceView(model: model)
                .frame(minWidth: 960, minHeight: 620)
                .task {
                    updateManager.startIfConfigured()
                    await model.start()
                }
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
                } else if environment["GITGATTO_LEGAL_PREVIEW"] == "1" {
                    destination = "legal-documents"
                } else if environment["GITGATTO_HELP_PREVIEW"] == "1" {
                    destination = "help"
                } else if environment["GITGATTO_SCANNER_PREVIEW"] == "1" {
                    destination = "repository-scanner"
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
                openWindow(id: "updates")
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
            workspaceCommand(.changes, shortcut: "2")
            workspaceCommand(.history, shortcut: "3")
            workspaceCommand(.branches, shortcut: "4")
            workspaceCommand(.codex, shortcut: "5")
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
