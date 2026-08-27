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
}
