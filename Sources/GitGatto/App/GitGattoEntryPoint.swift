import AppKit
import SwiftUI

@main
enum GitGattoEntryPoint {
    @MainActor static func main() {
        if Bundle.main.bundleIdentifier == MonitoringHelperRegistration.identifier {
            UserDefaults.standard.addSuite(named: "dev.gitgatto.client")
            L10n.activate(AppPreferencesStore.load().language)
            NSApplication.shared.setActivationPolicy(.accessory)
            GitGattoMonitoringApp.main()
        } else {
            ForegroundMonitoringSession.prepare()
            GitGattoApp.main()
        }
    }
}
