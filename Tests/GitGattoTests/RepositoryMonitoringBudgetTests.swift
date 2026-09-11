import CoreServices
import Darwin
import Foundation
@testable import GitGatto
import Testing

@Suite("Repository monitoring budgets")
struct RepositoryMonitoringBudgetTests {
    @Test("Foreground, recently edited, background and battery repositories have distinct budgets")
    func contexts() {
        let active = MonitoringEnvironment(appIsActive: true, usesBattery: false, lowPowerMode: false)
        let inactive = MonitoringEnvironment(appIsActive: false, usesBattery: false, lowPowerMode: false)
        let foreground = RepositoryMonitoringBudget(environment: active, isWorkspaceRepository: true, recentlyChanged: false)
        let recent = RepositoryMonitoringBudget(environment: inactive, isWorkspaceRepository: false, recentlyChanged: true)
        let background = RepositoryMonitoringBudget(environment: inactive, isWorkspaceRepository: true, recentlyChanged: false)
        #expect(foreground.mode == .foreground)
        #expect(recent.mode == .recent)
        #expect(background.mode == .background)
        #expect(foreground.liveDelay < recent.liveDelay && recent.liveDelay < background.liveDelay)
        #expect(foreground.protectionDelay < recent.protectionDelay)
        #expect(foreground.reconciliationInterval < background.reconciliationInterval)
        for power in [MonitoringEnvironment(appIsActive: true, usesBattery: true, lowPowerMode: false),
                      MonitoringEnvironment(appIsActive: true, usesBattery: false, lowPowerMode: true)] {
            let budget = RepositoryMonitoringBudget(environment: power, isWorkspaceRepository: true, recentlyChanged: true)
            #expect(budget.mode == .energySaving)
            #expect(budget.remoteMultiplier > foreground.remoteMultiplier)
            #expect(budget.auditDelay(for: .unknown) == foreground.auditDelay(for: .unknown))
            #expect(budget.auditDelay(for: .content) > foreground.auditDelay(for: .content))
        }
    }

    @Test func explicitRepositoryPolicyPreservesUrgentAuditsAndPowerBudget() throws {
        let environment = MonitoringEnvironment(appIsActive: true, usesBattery: false, lowPowerMode: false)
        let active = RepositoryMonitoringBudget(environment: environment, isWorkspaceRepository: false, recentlyChanged: false, policy: .active)
        let quiet = RepositoryMonitoringBudget(environment: environment, isWorkspaceRepository: true, recentlyChanged: true, policy: .lowFrequency)
        #expect(active.mode == .foreground)
        #expect(quiet.mode == .background)
        #expect(quiet.auditDelay(for: .unknown) == 0.15)
        #expect(quiet.remoteMultiplier > active.remoteMultiplier)
        let battery = RepositoryMonitoringBudget(environment: .init(appIsActive: true, usesBattery: true, lowPowerMode: false),
            isWorkspaceRepository: true, recentlyChanged: true, policy: .active)
        #expect(battery.mode == .energySaving)
        var preferences = AppPreferences()
        let previous = preferences
        preferences.repositoryMonitoringPolicies["/tmp/fixture"] = .lowFrequency
        #expect(preferences.requiresMonitoringRestart(comparedTo: previous))
        #expect(try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(preferences)) == preferences)
        #expect(try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8)).repositoryMonitoringPolicies.isEmpty)
    }

    @MainActor
    @Test("Workspace focus stays fast while recent background activity expires")
    func scopeAndExpiry() {
        let clock = BudgetClock()
        let engine = MonitoringEngine(environment: { .init(appIsActive: true, usesBattery: false, lowPowerMode: false) }, now: { clock.now })
        let first = URL(fileURLWithPath: "/tmp/budget-first"), second = URL(fileURLWithPath: "/tmp/budget-second")
        engine.setWorkspaceRepository(first)
        #expect(engine.budget(for: first).mode == .foreground)
        #expect(engine.budget(for: second).mode == .background)
        // No configured repositories: this check never starts Git or accesses these paths.
        engine.recordRepositoryChange(at: second, event: .content)
        #expect(engine.budget(for: second).mode == .recent)
        clock.now.addTimeInterval(91)
        #expect(engine.budget(for: second).mode == .background)
        #expect(engine.budget(for: first).mode == .foreground)
    }

    @Test("Atomic saves stay coalescible; missing files, refs and dropped events remain urgent")
    func eventClassification() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("GitGattoBudgetEvents-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let resolved = try #require(realpath(root.path, nil))
        defer { free(resolved) }
        let canonical = URL(fileURLWithPath: String(cString: resolved))
        let monitor = RepositoryChangeMonitor(repositoryURL: root) { _ in }
        let file = canonical.appendingPathComponent("source.swift")
        try Data("saved\n".utf8).write(to: file, options: .atomic)
        let rename = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)
        #expect(monitor.classify(path: file.path, flags: rename) == .content)
        try fm.removeItem(at: file)
        let missing = monitor.classify(path: file.path, flags: rename)
        #expect(missing.requiresPromptAudit && missing.requiresLiveRefresh && !missing.referencesChanged)
        let createdRename = rename | FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)
        #expect(monitor.classify(path: file.path, flags: createdRename) == .content)
        #expect(monitor.classify(path: file.path,
            flags: createdRename | FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)).requiresPromptAudit)
        let ref = monitor.classify(path: canonical.appendingPathComponent(".git/refs/heads/main").path,
                                   flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified))
        #expect(ref.requiresPromptAudit && ref.referencesChanged)
        let object = monitor.classify(path: canonical.appendingPathComponent(".git/objects/ab/blob").path, flags: rename)
        #expect(object.requiresPromptAudit && !object.requiresLiveRefresh)
        #expect(monitor.classify(path: file.path, flags: FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)) == .unknown)
        var combined = RepositoryChangeEvent.none
        combined.merge(object); combined.merge(.content); combined.merge(ref)
        #expect(combined == .unknown)
    }
}

@MainActor
private final class BudgetClock { var now = Date() }
