import AppKit
import SwiftUI

struct AppBrandIcon: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: AppIconAssets.image(for: colorScheme))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct AppBrandWordmark: View {
    let width: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var image: NSImage {
        colorScheme == .dark ? BrandAssets.darkWordmark : BrandAssets.lightWordmark
    }

    private var height: CGFloat {
        guard image.size.width > 0 else { return width / 4 }
        return width * image.size.height / image.size.width
    }

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: height)
            .accessibilityLabel(L10n.text("app.name"))
    }
}

struct AppBrandLockup: View {
    let iconSize: CGFloat
    let wordmarkWidth: CGFloat
    var spacing: CGFloat = 10

    var body: some View {
        HStack(spacing: spacing) {
            AppBrandIcon(size: iconSize)
            AppBrandWordmark(width: wordmarkWidth)
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor
enum AppIconAssets {
    static let lightIcon = BrandAssets.image(named: "GitGatto-AppIcon", extension: "svg")
    static let darkIcon = BrandAssets.image(named: "GitGatto-AppIcon-Dark", extension: "svg")

    static func image(for colorScheme: ColorScheme) -> NSImage {
        colorScheme == .dark ? darkIcon : lightIcon
    }

    static func updateApplicationIcon(appearanceRaw: String? = nil) {
        let storedAppearance = appearanceRaw
            ?? UserDefaults.standard.string(forKey: "appearance")
            ?? AppAppearance.system.rawValue
        let appearance = AppAppearance(rawValue: storedAppearance) ?? .system
        let isDark: Bool
        switch appearance {
        case .dark:
            isDark = true
        case .light:
            isDark = false
        case .system:
            isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        NSApp.applicationIconImage = isDark ? darkIcon : lightIcon
    }
}

@MainActor
private enum BrandAssets {
    static let lightWordmark = image(named: "GitGatto-Wordmark-Light", extension: "svg")
    static let darkWordmark = image(named: "GitGatto-Wordmark-Dark", extension: "svg")

    static func image(named name: String, extension fileExtension: String) -> NSImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension),
              let image = NSImage(contentsOf: url) else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        return image
    }
}
