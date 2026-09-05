import Foundation
import Sparkle
import Testing
@testable import GitGatto

@Suite("App update configuration")
struct AppUpdateManagerTests {
    @Test("Uses the HTTPS GitHub release feed")
    @MainActor
    func validatesFeedConfiguration() {
        #expect(AppUpdateManager.hasUpdateConfiguration([
            "SUFeedURL": "https://github.com/Lincb522/GitGatto/releases/latest/download/appcast.xml"
        ]))

        #expect(!AppUpdateManager.hasUpdateConfiguration([
            "SUFeedURL": "http://github.com/Lincb522/GitGatto/releases/latest/download/appcast.xml"
        ]))

        #expect(!AppUpdateManager.hasUpdateConfiguration([:]))
    }

    @Test("Treats Sparkle's no-update result as the current version")
    @MainActor
    func classifiesNoUpdateResult() {
        let noUpdate = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.noUpdateError.rawValue)
        )
        #expect(AppUpdateManager.stateAfterAborting(with: noUpdate) == .current)

        let failure = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.downloadError.rawValue),
            userInfo: [NSLocalizedDescriptionKey: "Download failed"]
        )
        #expect(
            AppUpdateManager.stateAfterAborting(with: failure)
                == .failed(message: "Download failed\nSUSparkleErrorDomain · \(SUError.downloadError.rawValue)")
        )
    }

    @Test("Preserves Sparkle's underlying failure and error code")
    @MainActor
    func preservesUpdateFailureDetails() {
        let underlying = NSError(
            domain: NSPOSIXErrorDomain,
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"]
        )
        let error = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.installationError.rawValue),
            userInfo: [
                NSLocalizedDescriptionKey: "Updater stopped",
                NSLocalizedFailureReasonErrorKey: "The updater connection closed.",
                NSUnderlyingErrorKey: underlying
            ]
        )

        let message = AppUpdateManager.failureMessage(for: error)

        #expect(message.contains("Updater stopped"))
        #expect(message.contains("The updater connection closed."))
        #expect(message.contains("Operation not permitted"))
        #expect(message.contains("SUSparkleErrorDomain · \(SUError.installationError.rawValue)"))
    }

    @Test("Preserves nested installer failures and their recovery action")
    @MainActor
    func preservesNestedInstallationFailure() {
        let cause = NSError(domain: NSPOSIXErrorDomain, code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Operation not permitted",
            NSLocalizedRecoverySuggestionErrorKey: "Allow this app in App Management."
        ])
        let installer = NSError(domain: SUSparkleErrorDomain, code: 10, userInfo: [
            NSLocalizedDescriptionKey: "Installer failed",
            NSUnderlyingErrorKey: cause
        ])
        let error = NSError(domain: SUSparkleErrorDomain, code: 4005, userInfo: [
            NSLocalizedDescriptionKey: "Installer failed",
            NSUnderlyingErrorKey: installer
        ])

        let message = AppUpdateManager.failureMessage(for: error)
        #expect(message.contains("Operation not permitted"))
        #expect(message.contains("Allow this app in App Management."))
        #expect(message.contains("SUSparkleErrorDomain · 4005 → SUSparkleErrorDomain · 10 → NSPOSIXErrorDomain · 1"))
        #expect(message.components(separatedBy: "Installer failed").count == 2)
        #expect(!message.contains(L10n.text("update.error.helper_startup_timeout")))
    }

    @Test("Explains the reproduced helper startup timeout without treating every installer error as a timeout")
    @MainActor
    func explainsHelperStartupTimeout() {
        let cause = NSError(domain: SUSparkleErrorDomain, code: 10, userInfo: [
            NSLocalizedDescriptionKey: "Timeout: agent connection was never initiated"
        ])
        let error = NSError(domain: SUSparkleErrorDomain, code: 4005, userInfo: [
            NSLocalizedDescriptionKey: "An error occurred while running the updater.",
            NSUnderlyingErrorKey: cause
        ])
        let message = AppUpdateManager.failureMessage(for: error)
        let localizedRecoveryMessages = AppLanguage.allCases.filter { $0 != .system }.map {
            L10n.bundle(preferredLanguages: $0.preferredLanguages).localizedString(
                forKey: "update.error.helper_startup_timeout", value: nil, table: nil
            )
        }
        #expect(localizedRecoveryMessages.contains(where: { message.hasPrefix($0) }))
        #expect(message.contains("Timeout: agent connection was never initiated"))
        guard case let .failed(detail) = AppUpdateManager.stateAfterAborting(with: error) else {
            Issue.record("A helper startup timeout must remain a failed update.")
            return
        }
        #expect(detail.contains("Timeout: agent connection was never initiated"))
    }
}
