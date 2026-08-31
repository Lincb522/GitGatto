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
}
