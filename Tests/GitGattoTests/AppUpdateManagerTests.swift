import Testing
@testable import GitGatto

@Suite("App update configuration")
struct AppUpdateManagerTests {
    @Test("Requires an HTTPS feed and a nonempty EdDSA public key")
    @MainActor
    func validatesSignedFeedConfiguration() {
        #expect(AppUpdateManager.hasSignedUpdateConfiguration([
            "SUFeedURL": "https://updates.example.com/appcast.xml",
            "SUPublicEDKey": "public-key"
        ]))

        #expect(!AppUpdateManager.hasSignedUpdateConfiguration([
            "SUFeedURL": "http://updates.example.com/appcast.xml",
            "SUPublicEDKey": "public-key"
        ]))

        #expect(!AppUpdateManager.hasSignedUpdateConfiguration([
            "SUFeedURL": "https://updates.example.com/appcast.xml"
        ]))

        #expect(!AppUpdateManager.hasSignedUpdateConfiguration([
            "SUFeedURL": "https://updates.example.com/appcast.xml",
            "SUPublicEDKey": "  \n"
        ]))
    }
}
