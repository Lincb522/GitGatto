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
                == .failed(message: "Download failed")
        )
    }
}
