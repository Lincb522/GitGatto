import AppKit
import Foundation
import IOKit.ps

struct MonitoringEnvironment: Equatable, Sendable {
    var appIsActive: Bool
    var usesBattery: Bool
    var lowPowerMode: Bool

    @MainActor static func current() -> MonitoringEnvironment {
        let source = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let type = source.flatMap { IOPSGetProvidingPowerSourceType($0)?.takeUnretainedValue() } as String?
        return MonitoringEnvironment(appIsActive: NSApplication.shared.isActive,
            usesBattery: type == kIOPMBatteryPowerKey || type == kIOPMUPSPowerKey,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}

enum RepositoryMonitoringPolicy: String, Codable, CaseIterable, Sendable {
    case automatic, active, lowFrequency
    var titleKey: String { "monitoring.policy." + rawValue }
}

struct RepositoryMonitoringBudget: Equatable, Sendable {
    enum Mode: String, Sendable { case foreground, recent, background, energySaving }
    let mode: Mode
    let liveDelay: TimeInterval
    let protectionDelay: TimeInterval
    let activityDelay: TimeInterval
    let reconciliationInterval: TimeInterval
    let remoteMultiplier: Int

    init(environment: MonitoringEnvironment, isWorkspaceRepository: Bool, recentlyChanged: Bool,
         policy: RepositoryMonitoringPolicy = .automatic) {
        let isWorkspaceRepository = policy == .lowFrequency ? false : (isWorkspaceRepository || policy == .active)
        let recentlyChanged = policy == .lowFrequency ? false : (recentlyChanged || policy == .active)
        if environment.usesBattery || environment.lowPowerMode {
            mode = .energySaving
            liveDelay = environment.appIsActive && isWorkspaceRepository ? 2 : 4
            protectionDelay = 8; activityDelay = 6
            reconciliationInterval = 180; remoteMultiplier = 3
        } else if environment.appIsActive && isWorkspaceRepository {
            mode = .foreground
            liveDelay = 1; protectionDelay = 3; activityDelay = 2
            reconciliationInterval = 60; remoteMultiplier = 1
        } else if recentlyChanged {
            mode = .recent
            liveDelay = 2; protectionDelay = 6; activityDelay = 4
            reconciliationInterval = 120; remoteMultiplier = 2
        } else {
            mode = .background
            liveDelay = 4; protectionDelay = 8; activityDelay = 6
            reconciliationInterval = 180; remoteMultiplier = 3
        }
    }

    func auditDelay(for event: RepositoryChangeEvent) -> TimeInterval {
        event.requiresPromptAudit ? 0.15 : protectionDelay
    }
}

struct RepositoryChangeEvent: Sendable, Equatable {
    var requiresLiveRefresh = true
    var referencesChanged = false
    var requiresPromptAudit = false
    static let content = RepositoryChangeEvent()
    static let none = RepositoryChangeEvent(requiresLiveRefresh: false)
    static let unknown = RepositoryChangeEvent(referencesChanged: true, requiresPromptAudit: true)

    mutating func merge(_ other: Self) {
        requiresLiveRefresh = requiresLiveRefresh || other.requiresLiveRefresh
        referencesChanged = referencesChanged || other.referencesChanged
        requiresPromptAudit = requiresPromptAudit || other.requiresPromptAudit
    }
}
