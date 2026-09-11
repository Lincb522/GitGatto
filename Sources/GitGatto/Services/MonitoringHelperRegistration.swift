import AppKit
import Combine
import ServiceManagement

@MainActor
final class MonitoringHelperRegistration: ObservableObject {
    static let identifier = "dev.gitgatto.monitor"
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var error: String?
    @Published private(set) var isUpdating = false
    private var task: Task<Void, Never>?

    init(initialStatus: SMAppService.Status = .notRegistered) { status = initialStatus }

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
            isUpdating = true
            defer { isUpdating = false }
            let service = SMAppService.loginItem(identifier: Self.identifier)
            do {
                if enabled {
                    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
                    let previousBuild = UserDefaults.standard.string(forKey: "backgroundMonitorRegisteredBuild")
                    if service.status == .enabled, previousBuild != build {
                        try await service.unregister()
                        try Task.checkCancellation()
                    }
                    if service.status != .enabled && service.status != .requiresApproval { try service.register() }
                    if service.status == .enabled || service.status == .requiresApproval {
                        UserDefaults.standard.set(build, forKey: "backgroundMonitorRegisteredBuild")
                    }
                } else if service.status == .enabled || service.status == .requiresApproval {
                    try await service.unregister()
                }
                error = nil
            } catch { self.error = error.localizedDescription }
            status = service.status
        }
    }

    func refreshStatus() {
        guard ForegroundMonitoringSession.isApplicationProcess else { return }
        status = SMAppService.loginItem(identifier: Self.identifier).status
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
