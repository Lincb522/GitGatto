import AppKit
import SwiftUI

extension Image {
    init(gattoSymbol: String) {
        self.init(nsImage: GattoIconAssets.image(for: gattoSymbol, pointSize: 18))
    }
}

struct GattoIcon: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        Image(nsImage: GattoIconAssets.image(for: symbol, pointSize: size))
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

enum GattoIconAssets {
    nonisolated(unsafe) private static let sourceCache = NSCache<NSString, NSImage>()
    nonisolated(unsafe) private static let renderedCache = NSCache<NSString, NSImage>()

    static func image(for symbol: String) -> NSImage {
        image(for: symbol, pointSize: 18)
    }

    static func image(for symbol: String, pointSize: CGFloat) -> NSImage {
        let name = assetName(for: symbol)
        let resolvedSize = max(8, pointSize)
        let cacheKey = "\(name):\(Int((resolvedSize * 100).rounded()))" as NSString
        if let cached = renderedCache.object(forKey: cacheKey) {
            return cached
        }

        let source = sourceImage(named: name)
        let image = PixelAlignedImageRenderer.render(
            source,
            pointSize: resolvedSize
        )
        image.isTemplate = true
        renderedCache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func sourceImage(named name: String) -> NSImage {
        if let cached = sourceCache.object(forKey: name as NSString) {
            return cached
        }
        let bundle = AppResourceBundle.current
        let url = bundle.url(forResource: name, withExtension: "svg", subdirectory: "UIIcons")
            ?? bundle.url(forResource: name, withExtension: "svg")
        let image = url.flatMap(NSImage.init(contentsOf:)) ?? NSImage(size: NSSize(width: 18, height: 18))
        sourceCache.setObject(image, forKey: name as NSString)
        return image
    }

    static func assetName(for symbol: String) -> String {
        "gatto-" + symbol.replacingOccurrences(of: ".", with: "-")
    }
}

enum PixelAlignedImageRenderer {
    static func render(_ source: NSImage, pointSize: CGFloat) -> NSImage {
        let logicalSize = NSSize(width: pointSize, height: pointSize)
        let output = NSImage(size: logicalSize)
        for scale in [1, 2, 3] {
            guard let representation = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: max(1, Int((pointSize * CGFloat(scale)).rounded())),
                pixelsHigh: max(1, Int((pointSize * CGFloat(scale)).rounded())),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: representation) else { continue }
            representation.size = logicalSize
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            context.shouldAntialias = true

            let base = NSRect(origin: .zero, size: logicalSize)
            source.draw(in: base, from: .zero, operation: .sourceOver, fraction: 1)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            output.addRepresentation(representation)
        }
        output.size = logicalSize
        return output
    }
}

struct GattoLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(gattoSymbol: systemImage)
        }
    }
}
