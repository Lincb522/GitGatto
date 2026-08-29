import Testing
@testable import GitGatto

@Suite("GitHub language styles")
struct GitHubLanguageStyleTests {
    @Test("Maps common GitHub languages to stable colors")
    func mapsKnownLanguages() {
        #expect(GitHubLanguageStyle.resolved("Swift")?.colorHex == "#F05138")
        #expect(GitHubLanguageStyle.resolved("JavaScript")?.colorHex == "#F1E05A")
        #expect(GitHubLanguageStyle.resolved("C++")?.colorHex == "#F34B7D")
        #expect(GitHubLanguageStyle.resolved("PHP")?.colorHex == "#4F5D95")
    }

    @Test("Uses the neutral color for an unknown language")
    func mapsUnknownLanguage() {
        #expect(GitHubLanguageStyle.resolved("Unknown Fixture Language")?.colorHex == "#6E7781")
    }

    @Test("Omits marks when GitHub has no language")
    func omitsMissingLanguage() {
        #expect(GitHubLanguageStyle.resolved(nil) == nil)
        #expect(GitHubLanguageStyle.resolved("  ") == nil)
    }

    @Test("Loads the complete GitHub language logo catalog")
    @MainActor
    func loadsLanguageLogoCatalog() throws {
        #expect(GitHubLanguageIconAssets.count == 833)
        #expect(GitHubLanguageIconAssets.resourceName(for: "C") == "081-c")
        #expect(GitHubLanguageIconAssets.resourceName(for: "C#") == "082-c")
        #expect(GitHubLanguageIconAssets.resourceName(for: "C++") == "083-c")
        #expect(GitHubLanguageIconAssets.resourceName(for: "Objective-C++") == "490-objective-c")
        #expect(GitHubLanguageIconAssets.resourceName(for: "Swift") == "691-swift")
        #expect(GitHubLanguageIconAssets.resourceName(for: "MoonBit") == "443-moonbit")
        #expect(GitHubLanguageIconAssets.image(for: "Swift") != nil)
        #expect(GitHubLanguageIconAssets.image(for: "Unknown Fixture Language") == nil)
    }
}
