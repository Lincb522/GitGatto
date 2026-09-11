import AppKit
import Combine
import OSLog
import ServiceManagement

@MainActor
protocol MonitoringAppService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

extension SMAppService: MonitoringAppService {}

@MainActor
final class MonitoringHelperRegistration: ObservableObject {
    static let identifier = "dev.gitgatto.monitor"
    static let servicePlistName = "dev.gitgatto.monitor.agent.plist"
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var error: String?
    @Published private(set) var isUpdating = false
    private var task: Task<Void, Never>?
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "dev.gitgatto.client", category: "background-registration")

    init(initialStatus: SMAppService.Status = .notRegistered, defaults: UserDefaults = .standard) {
        status = initialStatus
        self.defaults = defaults
    }

    var statusKey: String {
        switch status {
        case .enabled: "monitoring.background.enabled"
        case .requiresApproval: "monitoring.background.approval"
        case .notFound: "monitoring.background.unavailable"
        default: "monitoring.background.disabled"
        }
    }

    func configure(enabled: Bool) {
        guard ForegroundMonitoringSession.isApplicationProcess else { return }
        task?.cancel()
        let previous = task
        task = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await applyConfiguration(
                enabled: enabled,
                service: SMAppService.agent(plistName: Self.servicePlistName),
                legacy: SMAppService.loginItem(identifier: Self.identifier),
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            )
        }
    }

    func applyConfiguration(enabled: Bool, service: any MonitoringAppService,
                            legacy: any MonitoringAppService, build: String) async {
        isUpdating = true
        defer { isUpdating = false; status = service.status }
        do {
            // Remove the old login-item job before registering the same helper as a
            // launch agent with an explicit BundleProgram instead of bundle-ID lookup.
            if legacy.status == .enabled || legacy.status == .requiresApproval {
                try await legacy.unregister()
            }
            try Task.checkCancellation()
            if enabled {
                let previousBuild = defaults.string(forKey: "backgroundMonitorRegisteredBuild")
                if service.status == .enabled, previousBuild != build {
                    try await service.unregister()
                    try Task.checkCancellation()
                }
                if service.status != .enabled && service.status != .requiresApproval { try service.register() }
                if service.status == .enabled || service.status == .requiresApproval {
                    defaults.set(build, forKey: "backgroundMonitorRegisteredBuild")
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try await service.unregister()
            }
            error = nil
            logger.info("Background service registration updated; enabled=\(enabled), status=\(service.status.rawValue)")
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            logger.error("Background service registration failed: \(error.localizedDescription)")
        }
    }

    func refreshStatus() {
        guard ForegroundMonitoringSession.isApplicationProcess else { return }
        status = SMAppService.agent(plistName: Self.servicePlistName).status
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
