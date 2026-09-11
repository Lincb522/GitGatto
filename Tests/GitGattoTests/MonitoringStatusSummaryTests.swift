import AppKit
import Combine
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Monitoring status information", .serialized)
@MainActor
struct MonitoringStatusSummaryTests {
    private let first = URL(fileURLWithPath: "/tmp/GitGatto")
    private let second = URL(fileURLWithPath: "/tmp/another-repository-with-a-long-name")

    private func live(changes: Int, ahead: Int = 0, upstream: String? = "origin/main") -> RepositoryLiveState {
        RepositoryLiveState(branchName: "main", upstreamName: upstream, aheadCount: ahead, behindCount: 0,
            changes: (0..<changes).map { WorkingTreeChange(path: "\($0).swift", originalPath: nil,
                indexStatus: .modified, workTreeStatus: .modified) })
    }

    @Test("Collapsed information counts real files and keeps unknown repositories distinct from clean ones")
    func countsAndCoverage() {
        let partial = MonitoringStatusSummary(repositories: [first, second, first], selectedRepository: nil,
            snapshot: nil, backgroundStates: [first.path: live(changes: 12)], state: .healthy)
        #expect(partial.repositories.count == 2)
        #expect(partial.knownCount == 1)
        #expect(partial.changed == 12)
        #expect(partial.changedValue.hasSuffix("+"))
        #expect(!partial.isComplete)
        #expect(partial.compactTitle.contains("12+"))
        let complete = MonitoringStatusSummary(repositories: [first, second], selectedRepository: nil,
            snapshot: nil, backgroundStates: [first.path: live(changes: 12), second.path: live(changes: 3)], state: .attention)
        #expect(complete.changed == 15)
        #expect(complete.isComplete)
        #expect(complete.compactTitle.contains("15"))
        #expect(complete.compactTitle.hasSuffix("!"))
        #expect(complete.repositories[0].staged == 12)
    }

    @Test("Selecting another repository never reuses the foreground repository snapshot")
    func independentScope() {
        let snapshot = RepositorySnapshot(rootURL: first, branchName: "main", upstreamName: "origin/main",
            aheadCount: 99, behindCount: 0, changes: live(changes: 99).changes, commits: [], branches: [])
        let unknown = MonitoringStatusSummary(repositories: [first, second], selectedRepository: second,
            snapshot: snapshot, backgroundStates: [:], state: .healthy)
        #expect(unknown.changed == nil)
        #expect(unknown.changedValue == "—")
        #expect(unknown.repositories.first?.ahead == nil)
        #expect(!unknown.compactTitle.contains("99"))
        let known = MonitoringStatusSummary(repositories: [first, second], selectedRepository: second,
            snapshot: snapshot, backgroundStates: [second.path: live(changes: 2, ahead: 3)], state: .healthy)
        #expect(known.changed == 2)
        #expect(known.repositories.first?.ahead == 3)
        #expect(known.compactTitle.contains("…"))
        #expect(known.accessibilityDescription.contains(second.lastPathComponent))
    }

    @Test("Paused, disabled, empty and no-upstream states do not imply a healthy zero")
    func unavailableStates() {
        let paused = MonitoringStatusSummary(repositories: [first], selectedRepository: nil, snapshot: nil,
            backgroundStates: [first.path: live(changes: 0, upstream: nil)], state: .paused, workingTreeEnabled: false)
        #expect(paused.changed == nil)
        #expect(paused.repositories[0].ahead == nil)
        #expect(paused.compactTitle.contains(L10n.text("monitoring.overall.paused")))
        let pending = MonitoringStatusSummary(repositories: [first], selectedRepository: nil, snapshot: nil,
            backgroundStates: [:], state: .healthy)
        #expect(pending.compactTitle.contains(L10n.text("monitoring.status.pending")))
        let empty = MonitoringStatusSummary(repositories: [], selectedRepository: nil, snapshot: nil,
            backgroundStates: [:], state: .healthy)
        #expect(empty.compactTitle == L10n.text("monitoring.status.no_repositories"))
    }

    @Test("Menu bar information ignores channel timestamps and unrelated workspace publications")
    func projectionIsQuiet() async {
        var preferences = AppPreferences()
        preferences.monitoringEngineEnabled = true
        preferences.liveRefreshEnabled = true
        let model = WorkspaceViewModel(isBackgroundMonitor: true, monitoredRepositories: [], initialPreferences: preferences)
        var values: [MonitoringStatusSummary] = []
        let observation = model.monitoringStatusPublisher.sink { values.append($0) }
        #expect(values.count == 1)
        model.monitoringEngine.markHealthy(.workingTree)
        model.monitoringEngine.markHealthy(.workingTree)
        model.settingsDestination = "monitoring"
        #expect(values.count == 1)
        model.monitoringEngine.markAttention(.workingTree, error: "Fixture read failure")
        #expect(values.last?.state == .attention)
        let count = values.count
        model.monitoringEngine.markAttention(.workingTree, error: "Fixture read failure")
        #expect(values.count == count)
        await model.monitoringEngine.stopActivity()
        withExtendedLifetime(observation) {}
    }

    @Test("Compact labels and template icons render in light, dark and RTL at menu bar sizes")
    func renderCompactInformation() throws {
        _ = NSApplication.shared
        let states: [MonitoringOverallState] = [.healthy, .monitoring, .attention, .paused]
        for scheme in [ColorScheme.light, .dark] {
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                let summaries = states.map {
                    MonitoringStatusSummary(repositories: [first, second], selectedRepository: nil, snapshot: nil,
                        backgroundStates: [first.path: live(changes: 12)], state: $0)
                }
                let view = VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(summaries.enumerated()), id: \.offset) { _, summary in
                        MonitoringMenuBarContent(summary: summary)
                            .frame(height: 24)
                    }
                    HStack(spacing: 22) {
                        ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                            Image(nsImage: MonitoringStatusIcon.image(for: state))
                        }
                    }
                }
                .padding(20)
                .frame(width: 390, height: 240, alignment: .leading)
                .environment(\.colorScheme, scheme)
                .environment(\.layoutDirection, direction)
                .foregroundStyle(scheme == .dark ? Color.white : .black)
                .background(scheme == .dark ? Color(white: 0.12) : .white)
                try render(view, size: NSSize(width: 390, height: 240),
                    name: "collapsed-\(scheme)-\(direction)", scheme: scheme)
            }
        }
        for state in states {
            let image = MonitoringStatusIcon.image(for: state)
            #expect(image.isTemplate)
            #expect(image.size == NSSize(width: 18, height: 18))
        }
    }

    @Test("Popup keeps repository information and actions reachable in narrow and wide themed surfaces", .timeLimit(.minutes(3)))
    func renderPopup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonitoringUI-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "GitGatto.MonitoringUI.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = AppPreferences()
        preferences.backgroundMonitoringEnabled = true
        preferences.repositoryBackupEnabled = false
        preferences.remoteRefreshEnabled = false
        preferences.githubActionsMonitoringEnabled = false
        preferences.projectGoalMonitoringEnabled = false
        let engine = MonitoringEngine(backgroundService: BackgroundMonitoringService(rootURL: root.appendingPathComponent("activity")))
        let repositories = [root.appendingPathComponent("GitGatto"), root.appendingPathComponent("repository-with-a-long-name-需要检查的仓库")]
        for repository in repositories {
            let result = try await ExternalProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["init", "--initial-branch=main", repository.path],
                environment: ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_TEMPLATE_DIR": ""])
            #expect(result.exitCode == 0)
        }
        let model = WorkspaceViewModel(projectGoalStore: ProjectGoalStore(fileURL: root.appendingPathComponent("goals.json")),
            monitoringEngine: engine, isBackgroundMonitor: true, monitoredRepositories: repositories,
            initialPreferences: preferences, activityLedger: RepositoryActivityLedger(rootURL: root.appendingPathComponent("ledger")),
            repositoryBackupService: RepositoryBackupService(rootURL: root.appendingPathComponent("backups")))
        try render(MonitoringStatusBarView(model: model, engine: engine).defaultAppStorage(defaults),
            size: NSSize(width: 350, height: 680), name: "popup-loading", scheme: .light)
        for repository in repositories {
            try "fixture".write(to: repository.appendingPathComponent("example.swift"), atomically: true, encoding: .utf8)
        }
        await model.startBackgroundMonitoring()
        let deadline = ContinuousClock.now + .seconds(35)
        while model.monitoringStatusSummary.changed != 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(model.monitoringStatusSummary.changed == 2)
        #expect(model.monitoringStatusSummary.knownCount == 2)
        for theme in [AppVisualTheme.softGlass, .lumen, .folio] {
            defaults.set(theme.rawValue, forKey: AppStyleDefaults.themeKey)
            for scheme in [ColorScheme.light, .dark] {
                for width in [350, 430] {
                    let view = AppThemeRoot { MonitoringStatusBarView(model: model, engine: engine) }
                        .defaultAppStorage(defaults)
                        .environment(\.colorScheme, scheme)
                        .environment(\.layoutDirection, width == 350 ? .rightToLeft : .leftToRight)
                        .frame(width: CGFloat(width), height: 680)
                    try render(view, size: NSSize(width: width, height: 680),
                        name: "popup-\(theme)-\(scheme)-\(width)", scheme: scheme)
                }
            }
        }
        engine.selectRepository(repositories[1])
        #expect(model.monitoringStatusSummary.changed == 1)
        try render(MonitoringStatusBarView(model: model, engine: engine).defaultAppStorage(defaults),
            size: NSSize(width: 350, height: 680), name: "popup-selected", scheme: .dark)
        await model.stopBackgroundMonitoring()
        engine.markAttention(.workingTree, error: "Fixture: repository access failed. Check access in Settings. 仓库无法读取，请在设置中检查访问权限。")
        try render(MonitoringStatusBarView(model: model, engine: engine).defaultAppStorage(defaults),
            size: NSSize(width: 350, height: 680), name: "popup-error", scheme: .light)
        engine.markHealthy(.workingTree)
        engine.configure(preferences: preferences, repositories: [])
        try render(MonitoringStatusBarView(model: model, engine: engine).defaultAppStorage(defaults),
            size: NSSize(width: 350, height: 680), name: "popup-empty", scheme: .light)
        await engine.stopActivity()
    }

    private func render<Content: View>(_ view: Content, size: NSSize, name: String, scheme: ColorScheme) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.contentView = hosting
        defer { window.orderOut(nil); window.contentView = nil }
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(png.count > 1_024)
        #expect(hosting.bounds.width == size.width)
        if let path = ProcessInfo.processInfo.environment["GITGATTO_MONITORING_UI_DIR"] {
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }
}
