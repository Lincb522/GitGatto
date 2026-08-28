import AppKit
import SwiftUI

extension Image {
    init(gattoSymbol: String) {
        self.init(nsImage: GattoIconAssets.image(for: gattoSymbol))
    }
}

struct GattoIcon: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        Image(nsImage: GattoIconAssets.image(for: symbol))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

enum GattoIconAssets {
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSImage>()

    static func image(for symbol: String) -> NSImage {
        let name = assetName(for: symbol)
        if let cached = cache.object(forKey: name as NSString) {
            return cached
        }

        let bundle = AppResourceBundle.current
        let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "UIIcons")
            ?? bundle.url(forResource: name, withExtension: "png")
        let image = url.flatMap(NSImage.init(contentsOf:)) ?? NSImage(size: NSSize(width: 19, height: 19))
        image.size = NSSize(width: 19, height: 19)
        image.isTemplate = true
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    static func assetName(for symbol: String) -> String {
        "gatto-" + symbol.replacingOccurrences(of: ".", with: "-")
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
