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

    @Test("Uses the code icon fallback for languages without an asset")
    func mapsUnknownLanguage() {
        #expect(GitHubLanguageStyle.resolved("MoonBit")?.colorHex == "#6E7781")
    }

    @Test("Omits marks when GitHub has no language")
    func omitsMissingLanguage() {
        #expect(GitHubLanguageStyle.resolved(nil) == nil)
        #expect(GitHubLanguageStyle.resolved("  ") == nil)
    }
}
