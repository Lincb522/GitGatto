import AppKit
import Foundation
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Brand assets")
struct BrandAssetTests {
    @Test("UI icons preserve their logical ink size at every backing scale")
    func iconRepresentationScale() throws {
        let resourceURL = try #require(AppResourceBundle.current.resourceURL)
        let enumerator = try #require(FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil))
        let symbols = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "svg" && $0.lastPathComponent.hasPrefix("gatto-") }
            .map { $0.deletingPathExtension().lastPathComponent.dropFirst(6).replacingOccurrences(of: "-", with: ".") }
        #expect(symbols.count == 146)
        for symbol in symbols {
            for size: CGFloat in [17, 20, 31, 46] {
                let image = GattoIconAssets.image(for: symbol, pointSize: size)
                let representations = image.representations.compactMap { $0 as? NSBitmapImageRep }
                #expect(representations.count == 3)
                let reference = try inkBounds(#require(representations.first))
                for bitmap in representations {
                    let scale = CGFloat(bitmap.pixelsWide) / size
                    let bounds = try inkBounds(bitmap)
                    // Antialiasing can quantize each edge by one pixel in the 1x reference.
                    #expect(abs(bounds.minX / scale - reference.minX) <= 1)
                    #expect(abs(bounds.maxX / scale - reference.maxX) <= 1)
                    #expect(abs(bounds.minY / scale - reference.minY) <= 1)
                    #expect(abs(bounds.maxY / scale - reference.maxY) <= 1)
                }
            }
        }
    }

    @MainActor
    @Test("Native icon images use explicit point sizes in compact and large controls")
    func explicitImageSize() throws {
        for size: CGFloat in [9, 12.5, 16, 31, 46] {
            let renderer = ImageRenderer(content: Image(gattoSymbol: "arrow.down", pointSize: size)
                .foregroundStyle(.black))
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            #expect(image.width == Int((size * 2).rounded()))
            #expect(image.height == Int((size * 2).rounded()))
        }
    }

    @MainActor
    @Test("Default development tool icons use the requested logo area")
    func defaultToolLogoSize() throws {
        let tool = try #require(DevelopmentTool.catalog.first { $0.id == "lazygit" })
        #expect(tool.brandLogoName == nil)
        for size: CGFloat in [31, 46] {
            let expectedImage = GattoIconAssets.image(for: tool.icon, pointSize: size)
            let reference = try inkBounds(#require(expectedImage.representations.first as? NSBitmapImageRep))
            for scheme in [ColorScheme.light, .dark] {
                let renderer = ImageRenderer(content: DevelopmentToolLogoView(
                    tool: tool, size: size, fallbackColor: .black
                ).environment(\.colorScheme, scheme))
                renderer.scale = 2
                let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
                let bounds = try inkBounds(bitmap)
                #expect(abs(bounds.width / 2 - reference.width) <= 1)
                #expect(abs(bounds.height / 2 - reference.height) <= 1)
                #expect(abs(bounds.midX / 2 - reference.midX) <= 1)
                #expect(abs(bounds.midY / 2 - reference.midY) <= 1)
            }
        }
    }

    private func inkBounds(_ bitmap: NSBitmapImageRep) throws -> CGRect {
        var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        try #require(maxX >= minX && maxY >= minY)
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    @Test("Loads the complete GitGatto UI icon set")
    func gitGattoUIIconsLoad() throws {
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

        #expect(iconURLs.count == 146)
        #expect(GattoIconAssets.assetName(for: "arrow.clockwise") == "gatto-arrow-clockwise")
        #expect(GattoIconAssets.assetName(for: "sun.max") == "gatto-sun-max")
        #expect(GattoIconAssets.assetName(for: "moon") == "gatto-moon")
        #expect(GattoIconAssets.assetName(for: "github") == "gatto-github")
        #expect(GattoIconAssets.assetName(for: "lock.open") == "gatto-lock-open")
        #expect(GattoIconAssets.assetName(for: "trash.slash") == "gatto-trash-slash")
        for symbol in ["externaldrive.badge.timemachine", "lifepreserver", "tag"] {
            let name = GattoIconAssets.assetName(for: symbol)
            #expect(iconURLs.contains { $0.deletingPathExtension().lastPathComponent == name })
        }
        for url in iconURLs {
            let source = try String(contentsOf: url, encoding: .utf8)
            let image = try #require(NSImage(contentsOf: url))
            #expect(source.contains("<svg"))
            #expect(source.contains("viewBox="))
            #expect(image.representations.contains { String(describing: type(of: $0)).contains("SVG") })
        }
        let source = try #require(
            AppResourceBundle.current.url(
                forResource: "gatto-arrow-clockwise",
                withExtension: "svg",
                subdirectory: "UIIcons"
            ) ?? AppResourceBundle.current.url(forResource: "gatto-arrow-clockwise", withExtension: "svg")
        )
        let sourceImage = try #require(NSImage(contentsOf: source))
        #expect(!sourceImage.representations.isEmpty)
        let icon = GattoIconAssets.image(for: "arrow.clockwise")
        #expect(!icon.representations.isEmpty)
        #expect(icon.isTemplate)
        #expect(icon.size == NSSize(width: 20, height: 20))
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
