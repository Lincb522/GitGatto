import AppKit
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Visible repository actions", .serialized)
@MainActor
struct RepositoryActionsRenderingTests {
    @Test("Common actions fit every existing theme, including narrow and RTL windows")
    func surfaces() async throws {
        let previousTheme = UserDefaults.standard.object(forKey: AppStyleDefaults.themeKey)
        defer { UserDefaults.standard.set(previousTheme, forKey: AppStyleDefaults.themeKey); L10n.activate(AppPreferencesStore.load().language) }
        let f = try BootstrapFixture(); defer { f.remove() }
        _ = try await f.git(["init", "-b", "main"])
        _ = try await f.git(["commit", "--allow-empty", "-m", "Fixture commit"])
        let file = f.folder.appendingPathComponent("Long folder/Example.swift")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "let fixture = true\n".write(to: file, atomically: true, encoding: .utf8)
        let snapshot = try await GitRepositoryService().loadRepository(at: f.folder)
        let backupService = RepositoryBackupService(rootURL: f.root.appendingPathComponent("backups"))
        _ = try await backupService.createBackup(for: f.folder, reason: .manual, policy: .standard)
        let workspace = WorkspaceViewModel(isBackgroundMonitor: true, monitoredRepositories: [], repositoryBackupService: backupService)
        workspace.apply(snapshot)
        await workspace.reloadRepositoryBackups()
        let emptyWorkspace = WorkspaceViewModel(isBackgroundMonitor: true, monitoredRepositories: [])
        workspace.selectedCommit = snapshot.commits.first
        workspace.selectedStash = StashRecord(reference: "stash@{0}", hash: "abcdef123456", createdAt: Date(), summary: "A longer saved change description")
        workspace.selectedWorktree = GitWorktreeRecord(path: f.folder, headHash: "abcdef123456", branch: "feature/a-longer-branch-name", isMain: false, isLocked: false, isPrunable: false, changesCount: 3, aheadCount: 1, behindCount: 0)
        workspace.selectedBranch = BranchRecord(name: "feature/a-longer-branch-name", shortHash: "abcdef12", upstream: nil, isCurrent: false)
        let directory = ProcessInfo.processInfo.environment["GITGATTO_ACTION_SNAPSHOTS"]
        let themes = directory == nil ? [AppVisualTheme.standard] : AppVisualTheme.allCases
        let cases: [(Int, AppLanguage, ColorScheme, Int)] = directory == nil ? [(700, .english, .light, 520)]
            : [(700, .simplifiedChinese, .light, 520), (1120, .german, .dark, 760), (700, .german, .dark, 520), (700, .arabic, .dark, 520)]
        for theme in themes {
            UserDefaults.standard.set(theme.rawValue, forKey: AppStyleDefaults.themeKey)
            for (width, language, scheme, height) in cases {
                L10n.activate(language)
                let views: [(String, AnyView)] = [
                    ("changes", AnyView(ChangesWorkspaceView(model: workspace))),
                    ("branches", AnyView(BranchesWorkspaceView(model: workspace))),
                    ("history", AnyView(HistoryWorkspaceView(model: workspace))),
                    ("stash", AnyView(StashWorkspaceView(model: workspace))),
                    ("worktree", AnyView(WorktreeWorkspaceView(model: workspace))),
                    ("recovery", AnyView(RepositoryRecoveryView(model: workspace))),
                    ("file-history-empty", AnyView(FileTimelineWorkspaceView(model: emptyWorkspace))),
                    ("diagnostics-empty", AnyView(RepositoryDiagnosticsView(model: emptyWorkspace))),
                    ("sidebar", AnyView(RepositorySidebar(model: workspace, appearanceRaw: .constant("system"), isCollapsed: .constant(false))))
                ]
                for (name, content) in views {
                    let actualWidth = name == "sidebar" ? 232 : width
                    try await render(content, name: "\(name)-\(theme.rawValue)-\(language.rawValue)-\(actualWidth)", width: actualWidth, height: height, language: language, scheme: scheme, directory: directory)
                }
            }
        }
    }

    @Test("Labeled refresh retains disabled behavior and action dispatch")
    func refreshControl() async throws {
        var calls = 0
        for disabled in [false, true] {
            let host = NSHostingView(rootView: ToolbarIconButton(systemName: "arrow.clockwise", helpKey: "action.refresh", showsTitle: true, isActive: disabled, isDisabled: disabled) { calls += 1 })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.contentView = nil; window.close() }
        window.makeKeyAndOrderFront(nil)
            await Task.yield(); host.layoutSubtreeIfNeeded()
            let point = host.convert(NSPoint(x: host.bounds.midX, y: host.bounds.midY), to: nil)
            try click(window: window, point: point)
            await Task.yield()
            #expect(calls == 1)
        }
    }

    @Test("Single-file staging leaves other working files untouched")
    func stageSelectionScope() async throws {
        L10n.activate(.english)
        defer { L10n.activate(AppPreferencesStore.load().language) }
        let f = try BootstrapFixture(); defer { f.remove() }
        _ = try await f.git(["init", "-b", "main"])
        _ = try await f.git(["commit", "--allow-empty", "-m", "Fixture"])
        try "one".write(to: f.folder.appendingPathComponent("first.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: f.folder.appendingPathComponent("second.txt"), atomically: true, encoding: .utf8)
        let model = WorkspaceViewModel(isBackgroundMonitor: true, monitoredRepositories: [])
        model.apply(try await GitRepositoryService().loadRepository(at: f.folder))
        let host = NSHostingView(rootView: ChangesWorkspaceView(model: model).frame(width: 1000, height: 760))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        window.makeKeyAndOrderFront(nil)
        await Task.yield(); host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let directory = ProcessInfo.processInfo.environment["GITGATTO_ACTION_SNAPSHOTS"] {
            let folder = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("stage-click-target.png"))
        }
        // Exercise the same staging command against an isolated repository; pointer hit testing is covered by the labeled refresh control.
        await model.stage([try #require(model.snapshot?.changes.first)])
        let deadline = ContinuousClock.now + .seconds(60)
        while model.snapshot?.stagedChanges.isEmpty != false || !model.pendingStagePaths.isEmpty {
            try #require(ContinuousClock.now < deadline); await Task.yield()
        }
        let staged = try await f.git(["diff", "--cached", "--name-only"])
        #expect(staged == "first.txt")
        #expect(try String(contentsOf: f.folder.appendingPathComponent("second.txt"), encoding: .utf8) == "two")
    }

    @Test("Agent editing keeps the index untouched and renders disabled staging controls")
    func agentEditing() async throws {
        let previousTheme = UserDefaults.standard.object(forKey: AppStyleDefaults.themeKey)
        defer { UserDefaults.standard.set(previousTheme, forKey: AppStyleDefaults.themeKey); L10n.activate(AppPreferencesStore.load().language) }
        L10n.activate(.simplifiedChinese)
        let f = try BootstrapFixture(); defer { f.remove() }
        _ = try await f.git(["init", "-b", "main"])
        _ = try await f.git(["commit", "--allow-empty", "-m", "Fixture"])
        try "one".write(to: f.folder.appendingPathComponent("first.txt"), atomically: true, encoding: .utf8)
        let coordinator = HeldFileActionAgent()
        let model = WorkspaceViewModel(worktreeAgentCoordinator: coordinator, isBackgroundMonitor: true, monitoredRepositories: [])
        model.apply(try await GitRepositoryService().loadRepository(at: f.folder))
        let worktree = GitWorktreeRecord(path: f.folder, headHash: "abcdef123456", branch: "main", isMain: true, isLocked: false, isPrunable: false, changesCount: 1, aheadCount: 0, behindCount: 0)
        model.selectedWorktree = worktree
        model.worktreeAgentMode = .edit
        model.worktreeAgentPrompt = "Isolated test; no commands are executed."
        model.runWorktreeAgent()
        defer { model.cancelWorktreeAgent(worktree) }
        #expect(model.isSelectedRepositoryAgentEditing)
        #expect(model.activeOperation == nil)
        await model.stage(try #require(model.snapshot).changes)
        #expect(try await f.git(["diff", "--cached", "--name-only"]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let directory = ProcessInfo.processInfo.environment["GITGATTO_ACTION_SNAPSHOTS"]
        for theme in AppVisualTheme.allCases {
            UserDefaults.standard.set(theme.rawValue, forKey: AppStyleDefaults.themeKey)
            L10n.activate(.simplifiedChinese)
            try await render(AnyView(ChangesWorkspaceView(model: model)), name: "agent-editing-\(theme.rawValue)", width: 700, height: 520, language: .simplifiedChinese, scheme: .light, directory: directory)
            L10n.activate(.german)
            try await render(AnyView(WorktreeWorkspaceView(model: model)), name: "worktree-running-\(theme.rawValue)-de-700", width: 700, height: 480, language: .german, scheme: .dark, directory: directory)
        }
        L10n.activate(.simplifiedChinese)
        UserDefaults.standard.set(AppVisualTheme.standard.rawValue, forKey: AppStyleDefaults.themeKey)
        try await render(AnyView(BranchesWorkspaceView(model: model)), name: "recovery-tab", width: 700, height: 520, language: .simplifiedChinese, scheme: .light, directory: directory, selectRecovery: true)
        model.cancelWorktreeAgent(worktree)
        await coordinator.cancel(worktreeID: worktree.id)
    }

    private func render(_ content: AnyView, name: String, width: Int, height: Int = 760, language: AppLanguage, scheme: ColorScheme, directory: String?, selectRecovery: Bool = false) async throws {
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        let host = NSHostingView(rootView: content.environment(\.colorScheme, scheme).environment(\.locale, L10n.locale)
            .environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
            .dynamicTypeSize(.accessibility1).frame(width: bounds.width, height: bounds.height)
            .background(AppPalette(scheme).background))
        host.sizingOptions = []
        let window = NSWindow(contentRect: bounds, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host; host.frame = bounds
        defer { window.contentView = nil; window.close() }
        window.makeKeyAndOrderFront(nil)
        await Task.yield(); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        if selectRecovery {
            let control = try #require(recoveryPicker(in: host))
            let index = try #require((0..<control.segmentCount).first { control.label(forSegment: $0) == L10n.text("git_tools.tab.recovery") })
            control.selectedSegment = index
            #expect(control.sendAction(control.action, to: control.target))
            await Task.yield(); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        }
        #expect(host.bounds.size == bounds.size)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(png.count > 2_000)
        if let directory {
            let folder = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent(name + ".png"))
        }
    }

    private func recoveryPicker(in view: NSView) -> NSSegmentedControl? {
        if let control = view as? NSSegmentedControl,
           (0..<control.segmentCount).contains(where: { control.label(forSegment: $0) == L10n.text("git_tools.tab.recovery") }) {
            return control
        }
        for child in view.subviews {
            if let result = recoveryPicker(in: child) { return result }
        }
        return nil
    }

    private func click(window: NSWindow, point: NSPoint) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            window.sendEvent(event)
        }
    }
}

private actor HeldFileActionAgent: GitWorktreeAgentCoordinating {
    private var waiter: CheckedContinuation<CodexRunResult, any Error>?
    private var cancelled = false

    func run(worktreeID: String, prompt: String, repositoryURL: URL, mode: CodexRunMode) async throws -> CodexRunResult {
        try await withCheckedThrowingContinuation { continuation in
            if cancelled { continuation.resume(throwing: CancellationError()) }
            else { waiter = continuation }
        }
    }

    func cancel(worktreeID: String) async {
        cancelled = true
        waiter?.resume(throwing: CancellationError())
        waiter = nil
    }
}
