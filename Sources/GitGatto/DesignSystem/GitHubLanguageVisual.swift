import SwiftUI

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
            if let style = GitHubLanguageStyle.resolved(language) {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(style.requiresLightBackdrop ? Color(white: 0.96) : palette.raisedSurface)
                    .overlay {
                        GattoIcon(
                            symbol: "chevron.left.forwardslash.chevron.right",
                            size: size * 0.45
                        )
                            .foregroundStyle(Color(hex: style.colorHex) ?? palette.subtleInk)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                            .stroke(palette.divider, lineWidth: 1)
                    }
            } else {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(palette.raisedSurface)
                    .overlay {
                        GattoIcon(symbol: "shippingbox.fill", size: size * 0.48)
                            .foregroundStyle(palette.subtleInk)
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
