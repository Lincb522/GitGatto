import AppKit
import Foundation
import SwiftUI

enum GitHubLanguageIconAssets {
    private struct Manifest: Decodable {
        let totalLanguages: Int
        let items: [Item]
    }

    private struct Item: Decodable {
        let name: String
        let resourceName: String
    }

    private static let manifest: Manifest? = {
        guard let url = AppResourceBundle.current.url(
            forResource: "GitHubLanguageIcons",
            withExtension: "json"
        ), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(Manifest.self, from: data)
    }()

    private static let resourceNames: [String: String] = {
        guard let manifest else { return [:] }
        return Dictionary(uniqueKeysWithValues: manifest.items.map { item in
            (item.name.lowercased(), item.resourceName)
        })
    }()

    @MainActor private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 192
        cache.totalCostLimit = 40 * 1_024 * 1_024
        return cache
    }()
    @MainActor private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 24 * 1_024 * 1_024
        return cache
    }()
    @MainActor private static let placeholderCache: NSCache<NSNumber, NSImage> = {
        let cache = NSCache<NSNumber, NSImage>()
        cache.countLimit = 8
        return cache
    }()

    private static let availablePixelSizes = [16, 24, 48, 128]

    static var count: Int { manifest?.totalLanguages ?? 0 }

    static func resourceName(for language: String?) -> String? {
        guard let language else { return nil }
        let key = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return resourceNames[key]
    }

    @MainActor
    static func image(for language: String?) -> NSImage? {
        guard let resourceName = resourceName(for: language) else { return nil }
        return sourceImage(resourceName: resourceName, pixelSize: 128)
    }

    static func sourcePixelSize(pointSize: CGFloat, scale: Int) -> Int {
        let requiredPixels = Int(ceil(max(12, pointSize) * CGFloat(max(1, scale))))
        return availablePixelSizes.first(where: { $0 >= requiredPixels })
            ?? availablePixelSizes[availablePixelSizes.count - 1]
    }

    @MainActor
    private static func sourceImage(resourceName: String, pixelSize: Int) -> NSImage? {
        let sizedResourceName = "\(resourceName)-\(pixelSize)"
        let cacheKey = sizedResourceName as NSString
        if let cached = imageCache.object(forKey: cacheKey) { return cached }
        let bundle = AppResourceBundle.current
        guard let url = bundle.url(forResource: sizedResourceName, withExtension: "png")
                ?? bundle.url(
                    forResource: sizedResourceName,
                    withExtension: "png",
                    subdirectory: "LanguageIcons"
                ),
              let image = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(image, forKey: cacheKey, cost: pixelSize * pixelSize * 4)
        return image
    }

    @MainActor
    static func thumbnail(for language: String?, pointSize: CGFloat) -> NSImage? {
        guard let resourceName = resourceName(for: language) else { return nil }
        let resolvedSize = max(12, pointSize)
        let key = "\(resourceName):\(Int((resolvedSize * 100).rounded()))" as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let rendered = PixelAlignedImageRenderer.render(pointSize: resolvedSize, sourceForScale: { scale in
            sourceImage(
                resourceName: resourceName,
                pixelSize: sourcePixelSize(pointSize: resolvedSize, scale: scale)
            )
        }) else { return nil }
        rendered.isTemplate = false
        let pixelSize = Int(ceil(resolvedSize))
        thumbnailCache.setObject(rendered, forKey: key, cost: pixelSize * pixelSize * 4 * 14)
        return rendered
    }

    @MainActor
    static func placeholder(pointSize: CGFloat) -> NSImage? {
        let resolvedSize = max(12, pointSize)
        let key = NSNumber(value: Int((resolvedSize * 100).rounded()))
        if let cached = placeholderCache.object(forKey: key) { return cached }
        let bundle = AppResourceBundle.current
        guard let url = bundle.url(forResource: "placeholder", withExtension: "svg")
                ?? bundle.url(
                    forResource: "placeholder",
                    withExtension: "svg",
                    subdirectory: "LanguageIcons"
                ),
              let source = NSImage(contentsOf: url) else { return nil }
        let rendered = PixelAlignedImageRenderer.render(source, pointSize: resolvedSize)
        rendered.isTemplate = false
        placeholderCache.setObject(rendered, forKey: key)
        return rendered
    }

    @MainActor
    static func prewarm(languages: [String?], pointSizes: [CGFloat] = [18, 40]) {
        var seen = Set<String>()
        let visibleLanguages = languages.compactMap { language -> String? in
            guard let language else { return nil }
            let key = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return language
        }.prefix(12)
        for language in visibleLanguages {
            for pointSize in pointSizes {
                _ = thumbnail(for: language, pointSize: pointSize)
            }
        }
    }
}

struct GitHubLanguageStyle: Equatable, Sendable {
    let colorHex: String
    let requiresLightBackdrop: Bool

    init(colorHex: String, requiresLightBackdrop: Bool = false) {
        self.colorHex = colorHex
        self.requiresLightBackdrop = requiresLightBackdrop
    }

    static func resolved(_ language: String?) -> GitHubLanguageStyle? {
        guard let language else { return nil }
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let known = knownStyles[trimmed.lowercased()] {
            return known
        }

        return GitHubLanguageStyle(colorHex: "#6E7781")
    }

    var prefersDarkForeground: Bool {
        let hex = colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return false }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.62
    }

    private static let knownStyles: [String: GitHubLanguageStyle] = [
        "assembly": .init(colorHex: "#6E4C13"),
        "astro": .init(colorHex: "#FF5A03"),
        "c": .init(colorHex: "#555555"),
        "c#": .init(colorHex: "#178600"),
        "c++": .init(colorHex: "#F34B7D"),
        "clojure": .init(colorHex: "#DB5855"),
        "cmake": .init(colorHex: "#DA3434"),
        "css": .init(colorHex: "#663399"),
        "dart": .init(colorHex: "#00B4AB"),
        "dockerfile": .init(colorHex: "#384D54"),
        "elixir": .init(colorHex: "#6E4A7E"),
        "erlang": .init(colorHex: "#B83998"),
        "go": .init(colorHex: "#00ADD8"),
        "haskell": .init(colorHex: "#5E5086"),
        "html": .init(colorHex: "#E34C26"),
        "java": .init(colorHex: "#B07219"),
        "javascript": .init(colorHex: "#F1E05A"),
        "julia": .init(colorHex: "#A270BA"),
        "jupyter notebook": .init(colorHex: "#DA5B0B"),
        "kotlin": .init(colorHex: "#A97BFF"),
        "lua": .init(colorHex: "#000080"),
        "makefile": .init(colorHex: "#427819"),
        "objective-c": .init(colorHex: "#438EFF"),
        "objective-c++": .init(colorHex: "#6866FB"),
        "perl": .init(colorHex: "#0298C3"),
        "php": .init(colorHex: "#4F5D95"),
        "powershell": .init(colorHex: "#012456"),
        "python": .init(colorHex: "#3572A5"),
        "r": .init(colorHex: "#198CE7"),
        "ruby": .init(colorHex: "#701516"),
        "rust": .init(colorHex: "#DEA584", requiresLightBackdrop: true),
        "scala": .init(colorHex: "#C22D40"),
        "scss": .init(colorHex: "#C6538C"),
        "shell": .init(colorHex: "#89E051", requiresLightBackdrop: true),
        "solidity": .init(colorHex: "#AA6746", requiresLightBackdrop: true),
        "svelte": .init(colorHex: "#FF3E00"),
        "swift": .init(colorHex: "#F05138"),
        "typescript": .init(colorHex: "#3178C6"),
        "vue": .init(colorHex: "#41B883"),
        "zig": .init(colorHex: "#EC915C")
    ]
}

struct GitHubLanguageIcon: View {
    let language: String?
    let isPrivate: Bool
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    init(language: String?, isPrivate: Bool = false, size: CGFloat = 32) {
        self.language = language
        self.isPrivate = isPrivate
        self.size = size
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        ZStack(alignment: .bottomTrailing) {
            if let image = GitHubLanguageIconAssets.thumbnail(for: language, pointSize: size) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else if let image = GitHubLanguageIconAssets.placeholder(pointSize: size) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                let style = GitHubLanguageStyle.resolved(language)
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(style?.requiresLightBackdrop == true ? Color(white: 0.96) : palette.raisedSurface)
                    .overlay {
                        GattoIcon(
                            symbol: "chevron.left.forwardslash.chevron.right",
                            size: size * 0.45
                        )
                            .foregroundStyle(
                                style.flatMap { Color(hex: $0.colorHex) } ?? palette.subtleInk
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                            .stroke(palette.divider, lineWidth: 1)
                    }
            }

            if isPrivate {
                Circle()
                    .fill(palette.surface)
                    .frame(width: size * 0.42, height: size * 0.42)
                    .overlay {
                        GattoIcon(symbol: "lock.fill", size: size * 0.24)
                            .foregroundStyle(palette.ink)
                    }
                    .overlay {
                        Circle().stroke(palette.divider, lineWidth: 1)
                    }
                    .offset(x: size * 0.08, y: size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(!isPrivate)
        .accessibilityLabel(L10n.text("github.repository.visibility.private"))
    }
}

struct GitHubLanguageLabel: View {
    let language: String
    var fontSize: CGFloat = 10.5

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(languageColor)
                .frame(width: 7, height: 7)
            Text(language)
                .lineLimit(1)
        }
        .font(.system(size: fontSize, weight: .medium))
    }

    private var languageColor: Color {
        guard let style = GitHubLanguageStyle.resolved(language) else {
            return Color.secondary
        }
        return Color(hex: style.colorHex) ?? Color.secondary
    }
}

struct GitHubLanguageStackBadge: View {
    let language: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let style = GitHubLanguageStyle.resolved(language)
        let stackColor = style.flatMap { Color(hex: $0.colorHex) } ?? Color.secondary
        let detailInk = style?.prefersDarkForeground == true ? Color.black.opacity(0.82) : Color.white

        HStack(spacing: 0) {
            HStack(spacing: 4) {
                GitHubLanguageIcon(language: language, size: 13)
                Text(language.uppercased())
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            .padding(.trailing, 6)
            .frame(height: 20)
            .foregroundStyle(Color.white)
            .background(colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.29))

            Text(L10n.text("github.repository.language.primary"))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .foregroundStyle(detailInk)
                .background(stackColor)
        }
        .font(.system(size: 9.5, weight: .bold))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.black.opacity(colorScheme == .dark ? 0.24 : 0.10), lineWidth: 0.5)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.format("github.repository.language.primary.accessibility", language)
        )
    }
}
