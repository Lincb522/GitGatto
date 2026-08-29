import AppKit
import Foundation
import Testing
@testable import GitGatto

@Suite("Brand assets")
struct BrandAssetTests {
    @Test("Loads the complete Zappicon UI icon set")
    func zappiconUIIconsLoad() throws {
        let resourceURL = try #require(AppResourceBundle.current.resourceURL)
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: resourceURL,
                includingPropertiesForKeys: nil
            )
        )
        let iconURLs = enumerator.compactMap { $0 as? URL }.filter {
            $0.pathExtension == "svg" && $0.deletingPathExtension().lastPathComponent.hasPrefix("gatto-")
        }

        #expect(iconURLs.count == 126)
        #expect(GattoIconAssets.assetName(for: "arrow.clockwise") == "gatto-arrow-clockwise")
        #expect(GattoIconAssets.assetName(for: "sun.max") == "gatto-sun-max")
        #expect(GattoIconAssets.assetName(for: "moon") == "gatto-moon")
        let source = try #require(
            AppResourceBundle.current.url(
                forResource: "gatto-arrow-clockwise",
                withExtension: "svg",
                subdirectory: "UIIcons"
            ) ?? AppResourceBundle.current.url(forResource: "gatto-arrow-clockwise", withExtension: "svg")
        )
        let sourceImage = try #require(NSImage(contentsOf: source))
        #expect(sourceImage.representations.contains { String(describing: type(of: $0)).contains("SVG") })
        let icon = GattoIconAssets.image(for: "arrow.clockwise")
        #expect(!icon.representations.isEmpty)
        #expect(icon.isTemplate)
    }

    @Test("Keeps an editable master and a high-resolution in-app icon")
    func appIconIsVector() throws {
        let url = try #require(
            AppResourceBundle.current.url(forResource: "GitGatto-AppIcon", withExtension: "svg")
        )
        let source = try String(contentsOf: url, encoding: .utf8)
        let image = try #require(NSImage(contentsOf: url))

        #expect(source.contains("viewBox=\"0 0 1024 1024\""))
        #expect(!source.contains("<image"))
        #expect(!source.contains("<filter"))
        #expect(!source.contains("<rect"))
        #expect(!source.contains("id=\"base\""))
        #expect(source.contains("scale(1.18)"))
        #expect(image.representations.contains { String(describing: type(of: $0)).contains("SVG") })

        let pngURL = try #require(
            AppResourceBundle.current.url(forResource: "GitGatto-AppIcon", withExtension: "png")
        )
        let png = try #require(NSBitmapImageRep(data: Data(contentsOf: pngURL)))
        #expect(png.pixelsWide == 1024)
        #expect(png.pixelsHigh == 1024)
        #expect(png.colorAt(x: 0, y: 0)?.alphaComponent == 0)

        let darkURL = try #require(
            AppResourceBundle.current.url(forResource: "GitGatto-AppIcon-Dark", withExtension: "svg")
        )
        let darkSource = try String(contentsOf: darkURL, encoding: .utf8)
        let darkImage = try #require(NSImage(contentsOf: darkURL))
        #expect(darkSource.contains("#F4F3F1"))
        #expect(!darkSource.contains("<rect"))
        #expect(darkImage.representations.contains { String(describing: type(of: $0)).contains("SVG") })
    }
}
