import AppKit
import SwiftUI

extension Image {
    init(gattoSymbol: String) {
        self.init(nsImage: GattoIconAssets.image(for: gattoSymbol, pointSize: GattoIconAssets.defaultPointSize))
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
    static let defaultPointSize: CGFloat = 20

    // Reicon masters already use the complete 24 pt design canvas. Enlarging
    // them inside an equally sized bitmap cuts paths that sit near the edge.
    private static let opticalScale: CGFloat = 1

    nonisolated(unsafe) private static let sourceCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 24 * 1_024 * 1_024
        return cache
    }()
    nonisolated(unsafe) private static let renderedCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()

    static func image(for symbol: String) -> NSImage {
        image(for: symbol, pointSize: defaultPointSize)
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
            pointSize: resolvedSize,
            contentScale: opticalScale
        )
        image.isTemplate = true
        let pixels = Int(ceil(resolvedSize))
        renderedCache.setObject(image, forKey: cacheKey, cost: pixels * pixels * 4 * 14)
        return image
    }

    private static func sourceImage(named name: String) -> NSImage {
        if let cached = sourceCache.object(forKey: name as NSString) {
            return cached
        }
        let bundle = AppResourceBundle.current
        let url = bundle.url(forResource: name, withExtension: "svg", subdirectory: "UIIcons")
            ?? bundle.url(forResource: name, withExtension: "svg")
            ?? bundle.url(forResource: name, withExtension: "png", subdirectory: "UIIcons")
            ?? bundle.url(forResource: name, withExtension: "png")
        let image = url.flatMap(NSImage.init(contentsOf:)) ?? NSImage(size: NSSize(width: 18, height: 18))
        sourceCache.setObject(image, forKey: name as NSString, cost: 64 * 1_024)
        return image
    }

    static func assetName(for symbol: String) -> String {
        return "gatto-" + symbol.replacingOccurrences(of: ".", with: "-")
    }
}

enum PixelAlignedImageRenderer {
    static func render(
        _ source: NSImage,
        pointSize: CGFloat,
        contentScale: CGFloat = 1
    ) -> NSImage {
        render(
            pointSize: pointSize,
            contentScale: contentScale,
            sourceForScale: { _ in source }
        ) ?? NSImage(
            size: NSSize(width: pointSize, height: pointSize)
        )
    }

    static func render(
        pointSize: CGFloat,
        contentScale: CGFloat = 1,
        sourceForScale: (Int) -> NSImage?
    ) -> NSImage? {
        let logicalSize = NSSize(width: pointSize, height: pointSize)
        let output = NSImage(size: logicalSize)
        var renderedRepresentation = false
        for scale in [1, 2, 3] {
            guard let source = sourceForScale(scale),
                  let representation = NSBitmapImageRep(
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
            let pixelScale = CGFloat(scale)
            let opticalWidth = (logicalSize.width * contentScale * pixelScale).rounded() / pixelScale
            let opticalHeight = (logicalSize.height * contentScale * pixelScale).rounded() / pixelScale
            let opticalSize = NSSize(width: opticalWidth, height: opticalHeight)
            let opticalRect = NSRect(
                x: (((base.width - opticalSize.width) / 2) * pixelScale).rounded() / pixelScale,
                y: (((base.height - opticalSize.height) / 2) * pixelScale).rounded() / pixelScale,
                width: opticalSize.width,
                height: opticalSize.height
            )
            source.draw(in: opticalRect, from: .zero, operation: .sourceOver, fraction: 1)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            output.addRepresentation(representation)
            renderedRepresentation = true
        }
        output.size = logicalSize
        return renderedRepresentation ? output : nil
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
