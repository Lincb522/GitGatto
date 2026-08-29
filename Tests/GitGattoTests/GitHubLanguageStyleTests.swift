import AppKit
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

    @Test("Chooses readable badge text for light and dark language colors")
    func choosesBadgeForeground() {
        #expect(GitHubLanguageStyle.resolved("JavaScript")?.prefersDarkForeground == true)
        #expect(GitHubLanguageStyle.resolved("Shell")?.prefersDarkForeground == true)
        #expect(GitHubLanguageStyle.resolved("Swift")?.prefersDarkForeground == false)
        #expect(GitHubLanguageStyle.resolved("Python")?.prefersDarkForeground == false)
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

    @Test("Selects the nearest raster source for each backing scale")
    func selectsRasterSourceSizes() {
        #expect(GitHubLanguageIconAssets.sourcePixelSize(pointSize: 13, scale: 1) == 16)
        #expect(GitHubLanguageIconAssets.sourcePixelSize(pointSize: 13, scale: 2) == 48)
        #expect(GitHubLanguageIconAssets.sourcePixelSize(pointSize: 24, scale: 1) == 24)
        #expect(GitHubLanguageIconAssets.sourcePixelSize(pointSize: 24, scale: 2) == 48)
        #expect(GitHubLanguageIconAssets.sourcePixelSize(pointSize: 24, scale: 3) == 128)
        #expect(GitHubLanguageIconAssets.sourcePixelSize(pointSize: 58, scale: 2) == 128)
    }

    @Test("Bundles every optimized raster size")
    func bundlesOptimizedRasterSizes() throws {
        for pixelSize in [16, 24, 48, 128] {
            let resourceName = "691-swift-\(pixelSize)"
            let url = try #require(
                AppResourceBundle.current.url(forResource: resourceName, withExtension: "png")
                    ?? AppResourceBundle.current.url(
                        forResource: resourceName,
                        withExtension: "png",
                        subdirectory: "LanguageIcons"
                    )
            )
            let image = try #require(NSImage(contentsOf: url))
            let representation = try #require(image.representations.first)
            #expect(representation.pixelsWide == pixelSize)
            #expect(representation.pixelsHigh == pixelSize)
        }
    }

    @Test("Uses the catalog placeholder when no language logo matches")
    @MainActor
    func loadsPlaceholder() throws {
        let image = try #require(GitHubLanguageIconAssets.placeholder(pointSize: 24))
        #expect(image.size.width == 24)
        #expect(Set(image.representations.map(\.pixelsWide)) == [24, 48, 72])
        #expect(Set(image.representations.map(\.pixelsHigh)) == [24, 48, 72])
    }

    @Test("Builds exact backing-scale thumbnails for small language logos")
    @MainActor
    func buildsSmallLanguageThumbnails() throws {
        let image = try #require(GitHubLanguageIconAssets.thumbnail(for: "Swift", pointSize: 24))
        #expect(image.size.width == 24)
        #expect(Set(image.representations.map(\.pixelsWide)) == [24, 48, 72])
        #expect(Set(image.representations.map(\.pixelsHigh)) == [24, 48, 72])
    }
}
