import AppKit
import Foundation
import Testing
@testable import GitGatto

@Suite("Brand assets")
struct BrandAssetTests {
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
