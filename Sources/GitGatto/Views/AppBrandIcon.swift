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

struct GitGattoLaunchOverlay: View {
    @Binding var isContentReady: Bool
    let holdsForPreview: Bool
    let onFinished: () -> Void

    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @AppStorage(AppStyleDefaults.accentKey) private var accentRaw = AppAccentChoice.coral.rawValue
    @AppStorage(AppStyleDefaults.customAccentKey) private var customAccentHex = "#4F7DFF"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var backdropOpacity = 0.0
    @State private var glowScale = 0.72
    @State private var markOpacity = 0.0
    @State private var markScale = 0.84
    @State private var markOffset: CGFloat = 12
    @State private var markBlur: CGFloat = 9
    @State private var tracerProgress: CGFloat = 0
    @State private var tracerOpacity = 0.0
    @State private var wordmarkReveal: CGFloat = 0
    @State private var wordmarkOpacity = 0.0
    @State private var exitOpacity = 1.0
    @State private var exitScale = 1.0
    @State private var didStart = false

    private var theme: AppVisualTheme {
        AppVisualTheme.resolved(themeRaw)
    }

    private var accentChoice: AppAccentChoice {
        AppAccentChoice(rawValue: accentRaw) ?? .coral
    }

    private var palette: AppPalette {
        AppPalette(
            colorScheme,
            theme: theme,
            accentChoice: accentChoice,
            customAccentHex: customAccentHex
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                launchBackdrop

                HStack(spacing: 24) {
                    launchMark

                    AppBrandWordmark(width: 206)
                        .opacity(wordmarkOpacity)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .scaleEffect(x: wordmarkReveal, anchor: .leading)
                        }
                }
                .offset(y: -8)
                .opacity(exitOpacity)
                .scaleEffect(exitScale)
                .frame(maxWidth: min(proxy.size.width - 64, 520))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task { await play() }
    }

    @ViewBuilder
    private var launchBackdrop: some View {
        ZStack {
            if theme == .softGlass {
                Rectangle()
                    .fill(.regularMaterial)
                palette.background
                    .opacity(colorScheme == .dark ? 0.82 : 0.70)
            } else {
                palette.background
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            palette.primary.opacity(colorScheme == .dark ? 0.16 : 0.11),
                            palette.primary.opacity(0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 210
                    )
                )
                .frame(width: 440, height: 440)
                .scaleEffect(glowScale)

            Circle()
                .stroke(palette.primary.opacity(colorScheme == .dark ? 0.10 : 0.07), lineWidth: 1)
                .frame(width: 340, height: 340)
                .scaleEffect(glowScale * 1.08)
        }
        .opacity(backdropOpacity)
    }

    private var launchMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 33, style: .continuous)
                .fill(palette.raisedSurface.opacity(theme == .softGlass ? 0.34 : 0.72))
                .background {
                    if theme == .softGlass {
                        RoundedRectangle(cornerRadius: 33, style: .continuous)
                            .fill(.thinMaterial)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 33, style: .continuous)
                        .stroke(palette.divider.opacity(0.72), lineWidth: 1)
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.10),
                    radius: 24,
                    y: 12
                )

            RoundedRectangle(cornerRadius: 33, style: .continuous)
                .trim(from: max(0, tracerProgress - 0.34), to: tracerProgress)
                .stroke(
                    palette.primary,
                    style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round)
                )
                .opacity(tracerOpacity)

            Image(nsImage: AppIconAssets.launchImage(for: colorScheme))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 88, height: 88)
        }
        .frame(width: 126, height: 126)
        .opacity(markOpacity)
        .scaleEffect(markScale)
        .offset(y: markOffset)
        .blur(radius: markBlur)
    }

    @MainActor
    private func play() async {
        guard !didStart else { return }
        didStart = true
        let clock = ContinuousClock()
        let startedAt = clock.now

        if holdsForPreview {
            backdropOpacity = 1
            glowScale = 1
            markOpacity = 1
            markScale = 1
            markOffset = 0
            markBlur = 0
            tracerProgress = 1
            tracerOpacity = 1
            wordmarkReveal = 1
            wordmarkOpacity = 1
            return
        }

        if reduceMotion {
            backdropOpacity = 1
            glowScale = 1
            markOpacity = 1
            markScale = 1
            markOffset = 0
            markBlur = 0
            tracerProgress = 1
            wordmarkReveal = 1
            wordmarkOpacity = 1
            try? await clock.sleep(until: startedAt.advanced(by: .milliseconds(260)))
            guard !Task.isCancelled else { return }
            let contentDeadline = startedAt.advanced(by: .milliseconds(2_200))
            while !isContentReady, clock.now < contentDeadline {
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
            }
            withAnimation(.easeOut(duration: 0.20)) {
                exitOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(210))
            guard !Task.isCancelled else { return }
            onFinished()
            return
        }

        withAnimation(.easeOut(duration: 0.38)) {
            backdropOpacity = 1
            glowScale = 0.88
        }
        try? await clock.sleep(until: startedAt.advanced(by: .milliseconds(140)))
        guard !Task.isCancelled else { return }

        withAnimation(.spring(response: 0.72, dampingFraction: 0.84)) {
            markOpacity = 1
            markScale = 1
            markOffset = 0
            markBlur = 0
            glowScale = 1
        }
        try? await clock.sleep(until: startedAt.advanced(by: .milliseconds(500)))
        guard !Task.isCancelled else { return }

        tracerOpacity = 1
        withAnimation(.easeInOut(duration: 1.15)) {
            tracerProgress = 1
        }
        try? await clock.sleep(until: startedAt.advanced(by: .milliseconds(780)))
        guard !Task.isCancelled else { return }

        wordmarkOpacity = 1
        withAnimation(.easeOut(duration: 0.80)) {
            wordmarkReveal = 1
        }
        try? await clock.sleep(until: startedAt.advanced(by: .milliseconds(1_820)))
        guard !Task.isCancelled else { return }

        let contentDeadline = startedAt.advanced(by: .milliseconds(2_750))
        while !isContentReady, clock.now < contentDeadline {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
        }

        withAnimation(.easeOut(duration: 0.26)) {
            tracerOpacity = 0
        }
        withAnimation(.easeInOut(duration: 0.48)) {
            exitOpacity = 0
            exitScale = 1.018
            backdropOpacity = 0
        }
        try? await Task.sleep(for: .milliseconds(490))
        guard !Task.isCancelled else { return }
        onFinished()
    }
}

@MainActor
enum AppIconAssets {
    static let lightIcon = BrandAssets.image(named: "GitGatto-AppIcon", extension: "svg")
    static let darkIcon = BrandAssets.image(named: "GitGatto-AppIcon-Dark", extension: "svg")
    private static let lightLaunchIcon = BrandAssets.image(named: "GitGatto-AppIcon", extension: "png")
    private static let darkLaunchIcon = BrandAssets.image(named: "GitGatto-AppIcon-Dark", extension: "png")

    static func image(for colorScheme: ColorScheme) -> NSImage {
        colorScheme == .dark ? darkIcon : lightIcon
    }

    static func launchImage(for colorScheme: ColorScheme) -> NSImage {
        colorScheme == .dark ? darkLaunchIcon : lightLaunchIcon
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
        guard let url = AppResourceBundle.current.url(forResource: name, withExtension: fileExtension),
              let image = NSImage(contentsOf: url) else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        return image
    }
}
