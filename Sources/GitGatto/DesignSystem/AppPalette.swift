import AppKit
import SwiftUI

struct OKLCHColor {
    let lightness: Double
    let chroma: Double
    let hue: Double

    init(_ lightness: Double, _ chroma: Double, _ hue: Double) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = hue
    }

    var color: Color {
        let radians = hue * .pi / 180
        let a = chroma * cos(radians)
        let b = chroma * sin(radians)
        let lPrime = lightness + 0.396_337_777_4 * a + 0.215_803_757_3 * b
        let mPrime = lightness - 0.105_561_345_8 * a - 0.063_854_172_8 * b
        let sPrime = lightness - 0.089_484_177_5 * a - 1.291_485_548 * b
        let l = lPrime * lPrime * lPrime
        let m = mPrime * mPrime * mPrime
        let s = sPrime * sPrime * sPrime
        let redLinear = 4.076_741_662_1 * l - 3.307_711_591_3 * m + 0.230_969_929_2 * s
        let greenLinear = -1.268_438_004_6 * l + 2.609_757_401_1 * m - 0.341_319_396_5 * s
        let blueLinear = -0.004_196_086_3 * l - 0.703_418_614_7 * m + 1.707_614_701 * s

        func gamma(_ value: Double) -> Double {
            let converted = value <= 0.003_130_8
                ? 12.92 * value
                : 1.055 * pow(value, 1 / 2.4) - 0.055
            return min(1, max(0, converted))
        }

        return Color(
            red: gamma(redLinear),
            green: gamma(greenLinear),
            blue: gamma(blueLinear)
        )
    }
}

struct AppPalette {
    let background: Color
    let sidebar: Color
    let surface: Color
    let raisedSurface: Color
    let ink: Color
    let mutedInk: Color
    let subtleInk: Color
    let divider: Color
    let primary: Color
    let primarySoft: Color
    let accent: Color
    let accentSoft: Color
    let success: Color
    let successSoft: Color
    let danger: Color
    let dangerSoft: Color
    let warning: Color
    let warningSoft: Color
    let lumenColors: LumenResolvedColors?
    var onPrimary: Color { lumenColors?[.onPrimary] ?? .white }

    @MainActor
    init(
        _ scheme: ColorScheme,
        theme: AppVisualTheme = AppStyleDefaults.theme,
        accentChoice: AppAccentChoice = AppStyleDefaults.accent,
        customAccentHex: String = AppStyleDefaults.customAccentHex,
        lumenColors: LumenResolvedColors? = nil
    ) {
        let selectedPrimary = Self.primaryColor(
            for: accentChoice,
            scheme: scheme,
            customHex: customAccentHex
        )

        let resolvedLumen = theme == .lumen ? (lumenColors ?? LumenColorStore.shared.resolved(
            scheme, accentChoice: accentChoice, customAccentHex: customAccentHex
        )) : nil
        self.lumenColors = resolvedLumen
        if let colors = resolvedLumen {
            background = colors[.background]
            sidebar = colors[.sidebar]
            surface = colors[.surface]
            raisedSurface = colors[.raisedSurface]
            ink = colors[.ink]
            mutedInk = colors[.mutedInk]
            subtleInk = colors[.subtleInk]
            divider = colors[.divider]
            primary = colors[.primary]
            primarySoft = colors[.primarySoft]
            accent = colors[.accent]
            accentSoft = colors[.accentSoft]
            success = colors[.success]
            successSoft = colors[.successSoft]
            danger = colors[.danger]
            dangerSoft = colors[.dangerSoft]
            warning = colors[.warning]
            warningSoft = colors[.warningSoft]
        } else if theme == .standard, scheme == .dark {
            background = OKLCHColor(0.225, 0.004, 255).color
            sidebar = OKLCHColor(0.265, 0.004, 255).color
            surface = OKLCHColor(0.250, 0.004, 255).color
            raisedSurface = OKLCHColor(0.295, 0.004, 255).color
            ink = OKLCHColor(0.945, 0.006, 49).color
            mutedInk = OKLCHColor(0.690, 0.012, 49).color
            subtleInk = OKLCHColor(0.640, 0.008, 255).color
            divider = OKLCHColor(0.350, 0.004, 255).color
            primary = selectedPrimary
            primarySoft = accentChoice == .custom
                ? selectedPrimary.opacity(0.20)
                : Self.primarySoftColor(for: accentChoice, scheme: scheme)
            accent = OKLCHColor(0.760, 0.105, 200).color
            accentSoft = OKLCHColor(0.245, 0.040, 200).color
            success = OKLCHColor(0.730, 0.140, 151).color
            successSoft = OKLCHColor(0.245, 0.045, 151).color
            danger = OKLCHColor(0.720, 0.170, 25).color
            dangerSoft = OKLCHColor(0.245, 0.055, 25).color
            warning = OKLCHColor(0.790, 0.150, 86).color
            warningSoft = OKLCHColor(0.255, 0.050, 86).color
        } else if theme == .standard {
            background = OKLCHColor(1.000, 0.000, 0).color
            sidebar = OKLCHColor(0.960, 0.002, 255).color
            surface = OKLCHColor(0.985, 0.002, 49).color
            raisedSurface = OKLCHColor(1.000, 0.000, 0).color
            ink = OKLCHColor(0.180, 0.015, 49).color
            mutedInk = OKLCHColor(0.470, 0.018, 49).color
            subtleInk = OKLCHColor(0.540, 0.008, 255).color
            divider = OKLCHColor(0.895, 0.008, 49).color
            primary = selectedPrimary
            primarySoft = accentChoice == .custom
                ? selectedPrimary.opacity(0.12)
                : Self.primarySoftColor(for: accentChoice, scheme: scheme)
            accent = OKLCHColor(0.410, 0.125, 221).color
            accentSoft = OKLCHColor(0.940, 0.026, 221).color
            success = OKLCHColor(0.480, 0.140, 151).color
            successSoft = OKLCHColor(0.950, 0.035, 151).color
            danger = OKLCHColor(0.530, 0.190, 25).color
            dangerSoft = OKLCHColor(0.950, 0.040, 25).color
            warning = OKLCHColor(0.560, 0.150, 80).color
            warningSoft = OKLCHColor(0.955, 0.045, 86).color
        } else if theme == .emerald, scheme == .dark {
            background = OKLCHColor(0.205, 0.006, 155).color
            sidebar = OKLCHColor(0.225, 0.031, 155).color
            surface = OKLCHColor(0.230, 0.009, 155).color
            raisedSurface = OKLCHColor(0.295, 0.017, 155).color
            ink = OKLCHColor(0.955, 0.018, 150).color
            mutedInk = OKLCHColor(0.735, 0.026, 150).color
            subtleInk = OKLCHColor(0.690, 0.024, 150).color
            divider = OKLCHColor(0.290, 0.025, 155).color
            primary = selectedPrimary
            primarySoft = accentChoice == .custom
                ? selectedPrimary.opacity(0.22)
                : Self.primarySoftColor(for: accentChoice, scheme: scheme)
            accent = OKLCHColor(0.780, 0.205, 145).color
            accentSoft = OKLCHColor(0.245, 0.080, 145).color
            success = OKLCHColor(0.770, 0.180, 145).color
            successSoft = OKLCHColor(0.230, 0.065, 145).color
            danger = OKLCHColor(0.735, 0.175, 25).color
            dangerSoft = OKLCHColor(0.230, 0.060, 25).color
            warning = OKLCHColor(0.825, 0.150, 90).color
            warningSoft = OKLCHColor(0.235, 0.055, 90).color
        } else if theme == .emerald {
            background = OKLCHColor(1.000, 0.000, 0).color
            sidebar = OKLCHColor(1.000, 0.000, 0).color
            surface = OKLCHColor(1.000, 0.000, 0).color
            raisedSurface = OKLCHColor(1.000, 0.000, 0).color
            ink = OKLCHColor(0.185, 0.025, 155).color
            mutedInk = OKLCHColor(0.440, 0.028, 155).color
            subtleInk = OKLCHColor(0.500, 0.024, 155).color
            divider = OKLCHColor(0.865, 0.026, 150).color
            primary = selectedPrimary
            primarySoft = accentChoice == .custom
                ? selectedPrimary.opacity(0.13)
                : Self.primarySoftColor(for: accentChoice, scheme: scheme)
            accent = OKLCHColor(0.600, 0.190, 145).color
            accentSoft = OKLCHColor(0.925, 0.060, 145).color
            success = OKLCHColor(0.505, 0.160, 145).color
            successSoft = OKLCHColor(0.925, 0.050, 145).color
            danger = OKLCHColor(0.540, 0.185, 25).color
            dangerSoft = OKLCHColor(0.945, 0.040, 25).color
            warning = OKLCHColor(0.590, 0.155, 88).color
            warningSoft = OKLCHColor(0.950, 0.045, 88).color
        } else if theme == .folio, scheme == .dark {
            background = OKLCHColor(0.230, 0.005, 255).color
            sidebar = OKLCHColor(0.205, 0.008, 255).color
            surface = OKLCHColor(0.270, 0.007, 255).color
            raisedSurface = OKLCHColor(0.310, 0.008, 255).color
            ink = OKLCHColor(0.955, 0.006, 255).color
            mutedInk = OKLCHColor(0.735, 0.012, 255).color
            subtleInk = OKLCHColor(0.690, 0.012, 255).color
            divider = OKLCHColor(0.305, 0.012, 255).color
            primary = selectedPrimary
            primarySoft = accentChoice == .custom
                ? selectedPrimary.opacity(0.22)
                : Self.primarySoftColor(for: accentChoice, scheme: scheme)
            accent = OKLCHColor(0.735, 0.095, 260).color
            accentSoft = OKLCHColor(0.285, 0.045, 260).color
            success = OKLCHColor(0.745, 0.120, 151).color
            successSoft = OKLCHColor(0.255, 0.040, 151).color
            danger = OKLCHColor(0.730, 0.155, 25).color
            dangerSoft = OKLCHColor(0.255, 0.045, 25).color
            warning = OKLCHColor(0.825, 0.115, 88).color
            warningSoft = OKLCHColor(0.275, 0.040, 88).color
        } else if theme == .folio {
            background = OKLCHColor(0.910, 0.004, 80).color
            sidebar = OKLCHColor(0.950, 0.004, 80).color
            surface = OKLCHColor(0.955, 0.005, 80).color
            raisedSurface = OKLCHColor(0.985, 0.003, 80).color
            ink = OKLCHColor(0.180, 0.008, 255).color
            mutedInk = OKLCHColor(0.455, 0.010, 255).color
            subtleInk = OKLCHColor(0.500, 0.010, 255).color
            divider = OKLCHColor(0.835, 0.008, 80).color
            primary = selectedPrimary
            primarySoft = accentChoice == .custom
                ? selectedPrimary.opacity(0.14)
                : Self.primarySoftColor(for: accentChoice, scheme: scheme)
            accent = OKLCHColor(0.665, 0.105, 260).color
            accentSoft = OKLCHColor(0.875, 0.055, 260).color
            success = OKLCHColor(0.500, 0.115, 151).color
            successSoft = OKLCHColor(0.925, 0.030, 151).color
            danger = OKLCHColor(0.540, 0.165, 25).color
            dangerSoft = OKLCHColor(0.935, 0.035, 25).color
            warning = OKLCHColor(0.610, 0.105, 88).color
            warningSoft = OKLCHColor(0.915, 0.055, 88).color
        } else if theme == .console, scheme == .dark {
            background = OKLCHColor(0.200, 0.004, 255).color
            sidebar = OKLCHColor(0.240, 0.004, 255).color
            surface = OKLCHColor(0.215, 0.004, 255).color
            raisedSurface = OKLCHColor(0.280, 0.005, 255).color
            ink = OKLCHColor(0.925, 0.006, 255).color
            mutedInk = OKLCHColor(0.740, 0.009, 255).color
            subtleInk = OKLCHColor(0.690, 0.010, 255).color
            divider = OKLCHColor(0.365, 0.009, 255).color
            primary = selectedPrimary
            primarySoft = accentChoice == .custom
                ? selectedPrimary.opacity(0.22)
                : Self.primarySoftColor(for: accentChoice, scheme: scheme)
            accent = OKLCHColor(0.760, 0.155, 145).color
            accentSoft = OKLCHColor(0.215, 0.060, 145).color
            success = OKLCHColor(0.770, 0.165, 145).color
            successSoft = OKLCHColor(0.215, 0.060, 145).color
            danger = OKLCHColor(0.720, 0.175, 25).color
            dangerSoft = OKLCHColor(0.215, 0.060, 25).color
            warning = OKLCHColor(0.820, 0.155, 88).color
            warningSoft = OKLCHColor(0.225, 0.060, 88).color
        } else if theme == .console {
            background = OKLCHColor(0.955, 0.003, 145).color
            sidebar = OKLCHColor(0.935, 0.003, 255).color
            surface = OKLCHColor(0.985, 0.002, 145).color
            raisedSurface = OKLCHColor(0.935, 0.006, 145).color
            ink = OKLCHColor(0.200, 0.012, 145).color
            mutedInk = OKLCHColor(0.400, 0.018, 145).color
            subtleInk = OKLCHColor(0.500, 0.015, 145).color
            divider = OKLCHColor(0.785, 0.012, 145).color
            primary = selectedPrimary
            primarySoft = accentChoice == .custom
                ? selectedPrimary.opacity(0.14)
                : Self.primarySoftColor(for: accentChoice, scheme: scheme)
            accent = OKLCHColor(0.440, 0.140, 145).color
            accentSoft = OKLCHColor(0.910, 0.035, 145).color
            success = OKLCHColor(0.450, 0.150, 145).color
            successSoft = OKLCHColor(0.920, 0.035, 145).color
            danger = OKLCHColor(0.540, 0.180, 25).color
            dangerSoft = OKLCHColor(0.930, 0.035, 25).color
            warning = OKLCHColor(0.590, 0.150, 88).color
            warningSoft = OKLCHColor(0.930, 0.035, 88).color
        } else if scheme == .dark {
            background = OKLCHColor(0.135, 0.020, 255).color.opacity(0.08)
            sidebar = OKLCHColor(0.185, 0.014, 255).color.opacity(0.20)
            surface = OKLCHColor(0.165, 0.012, 255).color.opacity(0.24)
            raisedSurface = OKLCHColor(0.235, 0.014, 255).color.opacity(0.36)
            ink = OKLCHColor(0.950, 0.008, 255).color
            mutedInk = OKLCHColor(0.720, 0.018, 255).color
            subtleInk = OKLCHColor(0.575, 0.016, 255).color
            divider = OKLCHColor(0.410, 0.015, 255).color.opacity(0.64)
            primary = selectedPrimary
            primarySoft = accentChoice == .custom
                ? selectedPrimary.opacity(0.22)
                : Self.primarySoftColor(for: accentChoice, scheme: scheme)
            accent = OKLCHColor(0.770, 0.100, 205).color
            accentSoft = OKLCHColor(0.285, 0.040, 205).color.opacity(0.72)
            success = OKLCHColor(0.740, 0.135, 151).color
            successSoft = OKLCHColor(0.285, 0.045, 151).color.opacity(0.72)
            danger = OKLCHColor(0.730, 0.165, 25).color
            dangerSoft = OKLCHColor(0.285, 0.050, 25).color.opacity(0.72)
            warning = OKLCHColor(0.800, 0.145, 86).color
            warningSoft = OKLCHColor(0.295, 0.045, 86).color.opacity(0.72)
        } else {
            background = OKLCHColor(0.955, 0.020, 255).color.opacity(0.04)
            sidebar = OKLCHColor(0.985, 0.008, 255).color.opacity(0.16)
            surface = OKLCHColor(0.995, 0.004, 255).color.opacity(0.20)
            raisedSurface = OKLCHColor(1.000, 0.000, 0).color.opacity(0.32)
            ink = OKLCHColor(0.195, 0.020, 255).color
            mutedInk = OKLCHColor(0.455, 0.022, 255).color
            subtleInk = OKLCHColor(0.600, 0.018, 255).color
            divider = OKLCHColor(0.835, 0.014, 255).color.opacity(0.74)
            primary = selectedPrimary
            primarySoft = accentChoice == .custom
                ? selectedPrimary.opacity(0.13)
                : Self.primarySoftColor(for: accentChoice, scheme: scheme)
            accent = OKLCHColor(0.430, 0.120, 221).color
            accentSoft = OKLCHColor(0.940, 0.026, 221).color.opacity(0.78)
            success = OKLCHColor(0.490, 0.135, 151).color
            successSoft = OKLCHColor(0.950, 0.035, 151).color.opacity(0.78)
            danger = OKLCHColor(0.540, 0.185, 25).color
            dangerSoft = OKLCHColor(0.950, 0.040, 25).color.opacity(0.78)
            warning = OKLCHColor(0.570, 0.145, 80).color
            warningSoft = OKLCHColor(0.955, 0.045, 86).color.opacity(0.78)
        }
    }

    static func primaryColor(
        for choice: AppAccentChoice,
        scheme: ColorScheme,
        customHex: String
    ) -> Color {
        if choice == .custom {
            return Color(hex: customHex)
                ?? OKLCHColor(scheme == .dark ? 0.720 : 0.620, 0.170, 255).color
        }
        let specification = accentSpecification(for: choice)
        return OKLCHColor(
            scheme == .dark ? specification.darkLightness : specification.lightLightness,
            specification.chroma,
            specification.hue
        ).color
    }

    static func primarySoftColor(for choice: AppAccentChoice, scheme: ColorScheme) -> Color {
        let specification = accentSpecification(for: choice)
        return OKLCHColor(
            scheme == .dark ? 0.285 : 0.945,
            scheme == .dark ? specification.softDarkChroma : specification.softLightChroma,
            specification.hue
        ).color.opacity(scheme == .dark ? 0.72 : 0.80)
    }

    private static func accentSpecification(for choice: AppAccentChoice) -> AccentSpecification {
        switch choice {
        case .coral: AccentSpecification(hue: 49, chroma: 0.180)
        case .amber: AccentSpecification(hue: 82, chroma: 0.155)
        case .blue: AccentSpecification(hue: 255, chroma: 0.170)
        case .teal: AccentSpecification(hue: 190, chroma: 0.125)
        case .green: AccentSpecification(hue: 145, chroma: 0.145)
        case .violet: AccentSpecification(hue: 300, chroma: 0.165)
        case .pink: AccentSpecification(hue: 345, chroma: 0.170)
        case .custom: AccentSpecification(hue: 255, chroma: 0.170)
        }
    }
}

enum AppThemeLayout {
    static var workspaceInset: CGFloat {
        switch AppStyleDefaults.theme {
        case .softGlass: 12
        case .emerald: 12
        case .folio: 14
        case .lumen: 16
        case .standard, .console: 0
        }
    }
    static var panelSpacing: CGFloat {
        switch AppStyleDefaults.theme {
        case .softGlass: 12
        case .emerald: 12
        case .folio: 16
        case .lumen: 14
        case .standard, .console: 0
        }
    }
    static var panelCornerRadius: CGFloat {
        switch AppStyleDefaults.theme {
        case .softGlass: 16
        case .emerald: 16
        case .folio: 16
        case .lumen: 18
        case .standard, .console: 0
        }
    }
    static let titlebarBrandLeading: CGFloat = 16
    static var controlCornerRadius: CGFloat {
        switch AppStyleDefaults.theme {
        case .standard: 6
        case .softGlass: 10
        case .console: 4
        case .emerald: 10
        case .folio: 12
        case .lumen: 11
        }
    }
    static let topBarHeight: CGFloat = 62
}

struct AppThemeRoot<Content: View>: View {
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @AppStorage(AppStyleDefaults.accentKey) private var accentRaw = AppAccentChoice.coral.rawValue
    @AppStorage(AppStyleDefaults.customAccentKey) private var customAccentHex = "#4F7DFF"
    @Environment(\.colorScheme) private var systemColorScheme

    let content: Content
    let resetsContentOnStyleChange: Bool

    init(
        resetsContentOnStyleChange: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.resetsContentOnStyleChange = resetsContentOnStyleChange
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    private var effectiveColorScheme: ColorScheme {
        appearance.colorScheme ?? systemColorScheme
    }

    private var theme: AppVisualTheme {
        AppVisualTheme.resolved(themeRaw)
    }

    private var accentChoice: AppAccentChoice {
        AppAccentChoice(rawValue: accentRaw) ?? .coral
    }

    private var styleSignature: String {
        [appearanceRaw, theme.rawValue, accentRaw, customAccentHex].joined(separator: ":")
    }

    var body: some View {
        let palette = AppPalette(
            effectiveColorScheme,
            theme: theme,
            accentChoice: accentChoice,
            customAccentHex: customAccentHex
        )
        ZStack {
            AppThemeBackdrop(
                theme: theme,
                colorScheme: effectiveColorScheme
            )

            Group {
                if resetsContentOnStyleChange {
                    content.id(styleSignature)
                } else {
                    content
                }
            }
        }
        .tint(palette.primary)
        .progressViewStyle(GattoProgressViewStyle())
        .environment(\.layoutDirection, .leftToRight)
        .preferredColorScheme(appearance.colorScheme)
        .onAppear { AppIconAssets.updateApplicationIcon(appearanceRaw: appearanceRaw) }
        .onChange(of: styleSignature) { _, _ in
            AppIconAssets.updateApplicationIcon(appearanceRaw: appearanceRaw)
        }
    }
}

struct AppThemeBackdrop: View {
    let theme: AppVisualTheme
    let colorScheme: ColorScheme
    var lumenColors: LumenResolvedColors? = nil

    var body: some View {
        if theme == .lumen, let colors = AppPalette(colorScheme, theme: theme, lumenColors: lumenColors).lumenColors {
            ZStack {
                WindowThemeSurface(theme: theme, colorScheme: colorScheme, lumenColors: colors)
                LumenBackdrop(colorScheme: colorScheme, colors: colors)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        } else if theme != .softGlass {
            ZStack {
                WindowThemeSurface(theme: theme, colorScheme: colorScheme)
                AppPalette(colorScheme, theme: theme).background
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        } else {
            WindowThemeSurface(theme: theme, colorScheme: colorScheme)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
    }
}

private struct LumenBackdrop: View {
    let colorScheme: ColorScheme
    let colors: LumenResolvedColors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let palette = AppPalette(colorScheme, theme: .lumen, lumenColors: colors)
        GeometryReader { proxy in
            ZStack {
                (reduceTransparency ? colors.opaque(.background) : palette.background.opacity(colorScheme == .dark ? 0.76 : 0.60))

                if !reduceTransparency {
                    LumenAmbientLights(colorScheme: colorScheme, reduceMotion: reduceMotion, colors: colors)

                    RadialGradient(
                        colors: [.clear, .clear, colors[.vignette]],
                        center: UnitPoint(x: 0.50, y: 0.44),
                        startRadius: min(proxy.size.width, proxy.size.height) * 0.20,
                        endRadius: max(proxy.size.width, proxy.size.height) * 0.72
                    )

                    LinearGradient(
                        colors: [colors[.backdropTop], .clear, colors[.backdropBottom]],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .clipped()
    }
}

private struct LumenAmbientLights: NSViewRepresentable {
    let colorScheme: ColorScheme
    let reduceMotion: Bool
    let colors: LumenResolvedColors

    func makeNSView(context: Context) -> LumenAmbientLightsView {
        LumenAmbientLightsView()
    }

    func updateNSView(_ view: LumenAmbientLightsView, context: Context) {
        view.configure(colorScheme: colorScheme, reduceMotion: reduceMotion, colors: colors)
    }
}

final class LumenAmbientLightsView: NSView {
    private let lights = [CAGradientLayer(), CAGradientLayer()]
    private var renderedStops: [[Color]]?
    private var reduceMotion = false
    private var renderedSize = CGSize.zero
    private var animationEpoch: CFTimeInterval?
    private var visibilityObservation: NSKeyValueObservation?
    private let origins = [CGPoint(x: 0.02, y: 0.24), CGPoint(x: 0.96, y: 0.36)]
    private let destinations = [CGPoint(x: 0.12, y: 0.31), CGPoint(x: 0.86, y: 0.29)]
    private let durations: [CFTimeInterval] = [11, 13]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = CALayer()
        layer = root
        wantsLayer = true
        clipsToBounds = true
        for light in lights {
            light.type = .radial
            light.startPoint = CGPoint(x: 0.5, y: 0.5)
            light.endPoint = CGPoint(x: 1, y: 1)
            root.addSublayer(light)
        }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(colorScheme: ColorScheme, reduceMotion: Bool, colors: LumenResolvedColors? = nil) {
        let stops = (colors ?? LumenColorSettings().resolved(colorScheme)).ambientStops
        if renderedStops != stops {
            renderedStops = stops
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (light, colors) in zip(lights, stops) {
                light.colors = colors.map { NSColor($0).cgColor }
            }
            CATransaction.commit()
        }
        if self.reduceMotion != reduceMotion { animationEpoch = nil }
        self.reduceMotion = reduceMotion
        updateAnimations()
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0, renderedSize != bounds.size else { return }
        renderedSize = bounds.size
        let radius = max(bounds.width, bounds.height) * 0.82
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, light) in lights.enumerated() {
            light.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            light.position = point(origins[index])
            light.removeAnimation(forKey: "ambientMotion")
        }
        CATransaction.commit()
        updateAnimations()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        visibilityObservation?.invalidate()
        visibilityObservation = nil
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(updateAnimations),
                name: NSWindow.didChangeOcclusionStateNotification, object: window)
            visibilityObservation = window.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateAnimations() }
            }
        }
        updateAnimations()
    }

    override func viewDidHide() { super.viewDidHide(); updateAnimations() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateAnimations() }

    private func point(_ unit: CGPoint) -> CGPoint {
        CGPoint(x: unit.x * renderedSize.width, y: unit.y * renderedSize.height)
    }

    @objc private func updateAnimations() {
        let shouldAnimate = !reduceMotion && !isHiddenOrHasHiddenAncestor
            && window?.isVisible == true && window?.occlusionState.contains(.visible) == true && renderedSize != .zero
        if shouldAnimate, animationEpoch == nil { animationEpoch = CACurrentMediaTime() }
        for (index, light) in lights.enumerated() {
            guard shouldAnimate, let animationEpoch else {
                light.removeAnimation(forKey: "ambientMotion")
                continue
            }
            guard light.animation(forKey: "ambientMotion") == nil else { continue }
            // Keep the radial fields fixed; the compositor moves them without SwiftUI frame-by-frame layout.
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = NSValue(point: point(origins[index]))
            animation.toValue = NSValue(point: point(destinations[index]))
            animation.duration = durations[index]
            animation.beginTime = light.convertTime(animationEpoch, from: nil)
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.autoreverses = true
            animation.repeatCount = .infinity
            light.add(animation, forKey: "ambientMotion")
        }
    }
}

struct WindowThemeSurface: NSViewRepresentable {
    let theme: AppVisualTheme
    let colorScheme: ColorScheme
    var lumenColors: LumenResolvedColors? = nil

    func makeNSView(context: Context) -> NSVisualEffectView {
        GlassEffectView()
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        let usesGlass = theme == .softGlass || theme == .lumen
        nsView.material = usesGlass ? .underWindowBackground : .contentBackground
        nsView.blendingMode = usesGlass ? .behindWindow : .withinWindow
        nsView.state = usesGlass ? .followsWindowActiveState : .inactive
        if let effectView = nsView as? GlassEffectView {
            effectView.usesGlass = usesGlass
            if theme == .lumen {
                effectView.opaqueBackgroundColor = NSColor(AppPalette(colorScheme, theme: .lumen, lumenColors: lumenColors).background)
            } else {
                effectView.opaqueBackgroundColor = colorScheme == .dark
                    ? NSColor(calibratedWhite: 0.10, alpha: 1)
                    : .white
            }
        }
    }
}

private final class GlassEffectView: NSVisualEffectView {
    var usesGlass = true {
        didSet {
            guard oldValue != usesGlass else { return }
            scheduleWindowConfiguration()
        }
    }
    var opaqueBackgroundColor = NSColor.white {
        didSet {
            guard !oldValue.isEqual(opaqueBackgroundColor) else { return }
            scheduleWindowConfiguration()
        }
    }

    private var isWindowConfigurationScheduled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .followsWindowActiveState
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleWindowConfiguration()
    }

    private func scheduleWindowConfiguration() {
        guard window != nil, !isWindowConfigurationScheduled else { return }
        isWindowConfigurationScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isWindowConfigurationScheduled = false
            self.configureWindow()
        }
    }

    private func configureWindow() {
        guard let window else { return }
        let shouldBeOpaque = !usesGlass
        let backgroundColor = usesGlass ? NSColor.clear : opaqueBackgroundColor

        if window.isOpaque != shouldBeOpaque {
            window.isOpaque = shouldBeOpaque
        }
        if !window.backgroundColor.isEqual(backgroundColor) {
            window.backgroundColor = backgroundColor
        }
        if !window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = true
        }
        if window.titleVisibility != .hidden {
            window.titleVisibility = .hidden
        }
        if window.titlebarSeparatorStyle != .none {
            window.titlebarSeparatorStyle = .none
        }
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        if !window.isMovableByWindowBackground {
            window.isMovableByWindowBackground = true
        }
    }
}

private struct AppGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let elevated: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue

    @ViewBuilder
    func body(content: Content) -> some View {
        let palette = AppPalette(colorScheme)
        if AppVisualTheme.resolved(themeRaw) == .softGlass {
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            colorScheme == .dark
                                ? Color.black.opacity(reduceTransparency ? 1 : (elevated ? 0.40 : 0.24))
                                : Color.white.opacity(reduceTransparency ? 1 : (elevated ? 0.58 : 0.32))
                        )
                        .shadow(
                            color: Color.black.opacity(
                                elevated ? (colorScheme == .dark ? 0.16 : 0.06) : 0
                            ),
                            radius: elevated ? 5 : 0,
                            y: elevated ? 2 : 0
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            colorScheme == .dark
                                ? Color.white.opacity(0.12)
                                : Color.white.opacity(0.72),
                            lineWidth: 1
                        )
                }
        } else {
            content.background(palette.surface)
        }
    }
}

extension View {
    func appGlassPanel(
        cornerRadius: CGFloat = AppThemeLayout.panelCornerRadius,
        elevated: Bool = true
    ) -> some View {
        modifier(AppGlassPanelModifier(cornerRadius: cornerRadius, elevated: elevated))
    }

    func appConsolePanel() -> some View {
        modifier(AppConsolePanelModifier())
    }

    func emeraldSurface(
        _ style: EmeraldSurfaceStyle = .panel,
        cornerRadius: CGFloat = 16
    ) -> some View {
        modifier(EmeraldSurfaceModifier(style: style, cornerRadius: cornerRadius))
    }

    func folioSurface(
        _ style: FolioSurfaceStyle = .panel,
        cornerRadius: CGFloat = 16
    ) -> some View {
        modifier(FolioSurfaceModifier(style: style, cornerRadius: cornerRadius))
    }

    func lumenSurface(
        _ style: LumenSurfaceStyle = .panel,
        cornerRadius: CGFloat = 18
    ) -> some View {
        modifier(LumenSurfaceModifier(style: style, cornerRadius: cornerRadius))
    }
}

enum LumenSurfaceStyle: Sendable {
    case chrome
    case panel
    case inset
}

private struct LumenSurfaceModifier: ViewModifier {
    let style: LumenSurfaceStyle
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue

    @ViewBuilder
    func body(content: Content) -> some View {
        if AppVisualTheme.resolved(themeRaw) == .lumen {
            let palette = AppPalette(colorScheme)
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content
                .clipShape(shape)
                .background {
                    ZStack {
                        if reduceTransparency {
                            shape.fill(palette.lumenColors?.opaque(.background) ?? palette.background)
                        } else {
                            shape.fill(.ultraThinMaterial)
                                .opacity(style == .chrome ? 0.42 : 0.18)
                            shape.fill(fill(palette))
                        }
                    }
                }
                .overlay {
                    if style == .chrome {
                        VStack {
                            Spacer(minLength: 0)
                            Rectangle().fill(borderColor(palette)).frame(height: 1)
                        }
                    } else {
                        shape.stroke(borderColor(palette), lineWidth: 1)
                    }
                }
        } else {
            content
        }
    }

    private func fill(_ palette: AppPalette) -> Color {
        let role: LumenColorRole = switch style {
        case .chrome: .chrome
        case .panel: .panel
        case .inset: .inset
        }
        return palette.lumenColors?[role] ?? palette.surface
    }

    private func borderColor(_ palette: AppPalette) -> Color {
        style == .chrome ? (palette.lumenColors?[.chromeBorder] ?? palette.divider) : palette.divider
    }
}

enum FolioSurfaceStyle: Sendable {
    case panel
    case elevated
    case accent
}

private struct FolioSurfaceModifier: ViewModifier {
    let style: FolioSurfaceStyle
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue

    @ViewBuilder
    func body(content: Content) -> some View {
        if AppVisualTheme.resolved(themeRaw) == .folio {
            let palette = AppPalette(colorScheme)
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fill(palette))
                        .shadow(
                            color: style == .elevated
                                ? Color.black.opacity(colorScheme == .dark ? 0.20 : 0.10)
                                : .clear,
                            radius: 7,
                            y: 3
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(borderColor(palette), lineWidth: 1)
                }
        } else {
            content
        }
    }

    private func fill(_ palette: AppPalette) -> Color {
        switch style {
        case .panel: palette.surface
        case .elevated: palette.raisedSurface
        case .accent: palette.accentSoft
        }
    }

    private func borderColor(_ palette: AppPalette) -> Color {
        palette.divider.opacity(0.86)
    }
}

enum EmeraldSurfaceStyle: Sendable {
    case panel
    case elevated
    case inset
    case dark
}

private struct EmeraldSurfaceModifier: ViewModifier {
    let style: EmeraldSurfaceStyle
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue

    @ViewBuilder
    func body(content: Content) -> some View {
        if AppVisualTheme.resolved(themeRaw) == .emerald {
            let palette = AppPalette(colorScheme)
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fill(palette))
                        .shadow(
                            color: shadowColor,
                            radius: style == .elevated ? 3 : 0,
                            x: 0,
                            y: style == .elevated ? 1 : 0
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(borderColor(palette), lineWidth: 1)
                }
        } else {
            content
        }
    }

    private func fill(_ palette: AppPalette) -> Color {
        switch style {
        case .panel: palette.surface
        case .elevated: palette.raisedSurface
        case .inset: palette.background.opacity(colorScheme == .dark ? 0.72 : 0.58)
        case .dark: OKLCHColor(0.225, 0.031, 155).color
        }
    }

    private var shadowColor: Color {
        switch style {
        case .inset: .clear
        case .dark: Color.black.opacity(colorScheme == .dark ? 0.34 : 0.22)
        case .panel, .elevated: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.04)
        }
    }

    private func borderColor(_ palette: AppPalette) -> Color {
        style == .dark
            ? Color.white.opacity(0.08)
            : palette.divider.opacity(colorScheme == .dark ? 0.70 : 0.82)
    }
}

private struct AppConsolePanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue

    @ViewBuilder
    func body(content: Content) -> some View {
        let palette = AppPalette(colorScheme)
        if AppVisualTheme.resolved(themeRaw) == .console {
            content
                .background(palette.surface)
                .overlay {
                    Rectangle().stroke(palette.divider, lineWidth: 1)
                }
        } else {
            content
        }
    }
}

private struct AccentSpecification {
    let hue: Double
    let chroma: Double
    var lightLightness: Double { 0.620 }
    var darkLightness: Double { 0.720 }
    var softLightChroma: Double { chroma * 0.19 }
    var softDarkChroma: Double { chroma * 0.31 }
}

extension Color {
    init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
