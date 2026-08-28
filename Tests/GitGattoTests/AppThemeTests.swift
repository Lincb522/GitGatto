import Testing
@testable import GitGatto

@Suite("Application themes")
struct AppThemeTests {
    @Test("Keeps the original theme as the default and preserves saved glass selections")
    func resolvesStoredTheme() {
        #expect(AppVisualTheme.resolved(nil) == .standard)
        #expect(AppVisualTheme.resolved("unknown") == .standard)
        #expect(AppVisualTheme.resolved(AppVisualTheme.standard.rawValue) == .standard)
        #expect(AppVisualTheme.resolved(AppVisualTheme.softGlass.rawValue) == .softGlass)
        #expect(AppVisualTheme.resolved(AppVisualTheme.console.rawValue) == .console)
    }
}
