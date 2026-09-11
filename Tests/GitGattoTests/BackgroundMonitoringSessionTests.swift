import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Background monitoring ownership", .serialized)
@MainActor
struct BackgroundMonitoringSessionTests {
    @Test("Lease blocks a second owner, releases without deleting its inode, and rejects symlinks")
    func leases() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("runtime.lock")
        let first = try MonitoringProcessLease(url: url), second = try MonitoringProcessLease(url: url)
        #expect(try first.acquire())
        #expect(try !second.acquire())
        first.release()
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try second.acquire())
        second.release()
        let alias = root.appendingPathComponent("alias.lock")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: url)
        #expect(throws: (any Error).self) { try MonitoringProcessLease(url: alias) }
    }

    @Test("Old preferences do not register a new background item without opt-in")
    func preferences() throws {
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
        #expect(!preferences.backgroundMonitoringEnabled)
        var enabled = preferences
        enabled.backgroundMonitoringEnabled = true
        #expect(try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(enabled)).backgroundMonitoringEnabled)
        #expect(enabled.monitoringEngineEnabled)
    }

    @Test("Background mode observes two repositories without a selected main window and stops before releasing ownership", .timeLimit(.minutes(2)))
    func realRepositories() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        for repository in [a, b] {
            try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
            _ = try await ExternalProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["init", "--initial-branch=main", repository.path], environment: ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_TEMPLATE_DIR": ""])
        }
        var preferences = AppPreferences()
        preferences.backgroundMonitoringEnabled = true
        preferences.repositoryBackupEnabled = false
        preferences.remoteRefreshEnabled = false
        preferences.githubActionsMonitoringEnabled = false
        preferences.projectGoalMonitoringEnabled = false
        let engine = MonitoringEngine(backgroundService: BackgroundMonitoringService(rootURL: root.appendingPathComponent("activity")))
        let model = WorkspaceViewModel(projectGoalStore: ProjectGoalStore(fileURL: root.appendingPathComponent("goals.json")),
            monitoringEngine: engine, isBackgroundMonitor: true, monitoredRepositories: [a, b], loadPreferences: { preferences },
            activityLedger: RepositoryActivityLedger(rootURL: root.appendingPathComponent("ledger")),
            repositoryBackupService: RepositoryBackupService(rootURL: root.appendingPathComponent("backups")))
        await model.startBackgroundMonitoring()
        try "first".write(to: a.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "second".write(to: b.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let deadline = ContinuousClock.now + .seconds(35)
        while (model.backgroundRepositoryStates[a.path]?.changes.count != 1 || model.backgroundRepositoryStates[b.path]?.changes.count != 1), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(model.snapshot == nil)
        #expect(model.backgroundRepositoryStates[a.path]?.changes.count == 1)
        #expect(model.backgroundRepositoryStates[b.path]?.changes.count == 1)
        #expect(model.monitoringSnapshot(for: b)?.rootURL == b)
        #expect(!engine.isChannelEnabled(.remote))
        #expect(!engine.isChannelEnabled(.repositoryProtection))
        await model.stopBackgroundMonitoring()
        let state = model.backgroundRepositoryStates
        try "after shutdown".write(to: a.appendingPathComponent("later.txt"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .seconds(5))
        #expect(model.backgroundRepositoryStates == state)
        #expect(!engine.isActivityRefreshPending)
    }

    @Test("Helper yields all work to the foreground and reloads the repository on its next takeover", .timeLimit(.minutes(2)))
    func handoff() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = root.appendingPathComponent("repository")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        let runner = ExternalProcessRunner()
        let git = URL(fileURLWithPath: "/usr/bin/git")
        let environment = ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_TEMPLATE_DIR": ""]
        for arguments in [["init", "-b", "main"], ["config", "user.name", "Test"], ["config", "user.email", "test@example.invalid"]] {
            _ = try await runner.run(executable: git, arguments: ["-C", repository.path] + arguments, environment: environment)
        }
        try "base".write(to: repository.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        for arguments in [["add", "tracked.txt"], ["commit", "-m", "fixture"]] {
            _ = try await runner.run(executable: git, arguments: ["-C", repository.path] + arguments, environment: environment)
        }
        let leaseRoot = root.appendingPathComponent("Process")
        let foreground = try MonitoringProcessLease(url: leaseRoot.appendingPathComponent("foreground.lock"))
        let runtime = try MonitoringProcessLease(url: leaseRoot.appendingPathComponent("runtime.lock"))
        #expect(try foreground.acquire())
        var preferences = AppPreferences()
        preferences.backgroundMonitoringEnabled = true
        preferences.repositoryBackupEnabled = true
        preferences.externalRepositoryProtectionEnabled = true
        preferences.remoteRefreshEnabled = false
        preferences.githubActionsMonitoringEnabled = false
        preferences.projectGoalMonitoringEnabled = false
        var creations = 0
        var failures = 0
        let host = MonitoringHelperHost(rootURL: leaseRoot, loadPreferences: { preferences }, makeWorkspace: {
            creations += 1
            return WorkspaceViewModel(projectGoalStore: ProjectGoalStore(fileURL: root.appendingPathComponent("goals.json")),
                monitoringEngine: MonitoringEngine(backgroundService: BackgroundMonitoringService(rootURL: root.appendingPathComponent("activity"))),
                isBackgroundMonitor: true, monitoredRepositories: [repository], loadPreferences: { preferences },
                activityLedger: RepositoryActivityLedger(rootURL: root.appendingPathComponent("ledger")),
                repositoryBackupService: RepositoryBackupService(rootURL: root.appendingPathComponent("backups")))
        }, didFail: { _ in failures += 1 })
        do {
            host.start()
            try await Task.sleep(for: .milliseconds(1_200))
            #expect(host.model == nil)
            #expect(creations == 0)
            foreground.release()
            try await waitUntil { host.model?.repositoryBackups.isEmpty == false }
            let first = try #require(host.model)
            #expect(try !runtime.acquire())
            #expect(first.monitoringEngine.isChannelEnabled(.repositoryProtection))
            try "edit".write(to: repository.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
            try await waitUntil { first.backgroundRepositoryStates[repository.path]?.changes.count == 1 }
            #expect(try foreground.acquire())
            try await waitUntil { try runtime.acquire() }
            #expect(host.model == nil)
            let stoppedState = first.backgroundRepositoryStates
            try "new".write(to: repository.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
            try await Task.sleep(for: .milliseconds(1_200))
            #expect(first.backgroundRepositoryStates == stoppedState)
            runtime.release()
            foreground.release()
            try await waitUntil { host.model?.backgroundRepositoryStates[repository.path]?.changes.count == 2 }
            #expect(creations == 2)
            #expect(host.model !== first)
            #expect(failures == 0)
            await host.stop()
            #expect(host.model == nil)
            #expect(try runtime.acquire())
            runtime.release()
        } catch {
            await host.stop()
            throw error
        }
    }

    @Test("Helper reports lease failure instead of remaining silently idle")
    func helperFailure() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("foreground.lock"), withDestinationURL: root.appendingPathComponent("not-a-lock"))
        var didFail = false
        let host = MonitoringHelperHost(rootURL: root, didFail: { _ in didFail = true })
        host.start()
        try await waitUntil { didFail }
        await host.stop()
        #expect(host.model == nil)
    }

    private func waitUntil(_ predicate: () throws -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(35)
        while try !predicate() {
            guard ContinuousClock.now < deadline else { throw CocoaError(.fileReadUnknown) }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test("Background permission and settings fit narrow, wide, dark and RTL surfaces")
    func settingsRendering() async throws {
        for language in [AppLanguage.simplifiedChinese, .german, .arabic] {
            let previous = AppPreferencesStore.load().language
            L10n.activate(language)
            defer { L10n.activate(previous) }
            var preferences = AppPreferences()
            preferences.backgroundMonitoringEnabled = true
            let registration = MonitoringHelperRegistration(initialStatus: .requiresApproval)
            let view = ScrollView {
                MonitoringSettingsPage(engine: MonitoringEngine(), registration: registration, preferences: .constant(preferences))
                    .padding(18)
            }
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.usesRightToLeftLayout ? .rightToLeft : .leftToRight)
            try await verifyCenterRendering(view, name: "background-monitor-\(language.rawValue)")
        }
    }
}
