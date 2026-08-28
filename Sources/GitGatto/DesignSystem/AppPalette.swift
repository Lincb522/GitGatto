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

    init(
        _ scheme: ColorScheme,
        theme: AppVisualTheme = AppStyleDefaults.theme,
        accentChoice: AppAccentChoice = AppStyleDefaults.accent,
        customAccentHex: String = AppStyleDefaults.customAccentHex
    ) {
        let selectedPrimary = Self.primaryColor(
            for: accentChoice,
            scheme: scheme,
            customHex: customAccentHex
        )

        if theme == .standard, scheme == .dark {
            background = OKLCHColor(0.100, 0.000, 0).color
            sidebar = OKLCHColor(0.135, 0.006, 49).color
            surface = OKLCHColor(0.145, 0.005, 49).color
            raisedSurface = OKLCHColor(0.175, 0.006, 49).color
            ink = OKLCHColor(0.945, 0.006, 49).color
            mutedInk = OKLCHColor(0.690, 0.012, 49).color
            subtleInk = OKLCHColor(0.520, 0.010, 49).color
            divider = OKLCHColor(0.260, 0.009, 49).color
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
            sidebar = OKLCHColor(0.970, 0.004, 49).color
            surface = OKLCHColor(0.985, 0.002, 49).color
            raisedSurface = OKLCHColor(1.000, 0.000, 0).color
            ink = OKLCHColor(0.180, 0.015, 49).color
            mutedInk = OKLCHColor(0.470, 0.018, 49).color
            subtleInk = OKLCHColor(0.630, 0.014, 49).color
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
        } else if theme == .console, scheme == .dark {
            background = OKLCHColor(0.090, 0.018, 150).color
            sidebar = OKLCHColor(0.115, 0.022, 150).color
            surface = OKLCHColor(0.125, 0.020, 150).color
            raisedSurface = OKLCHColor(0.165, 0.026, 150).color
            ink = OKLCHColor(0.920, 0.040, 145).color
            mutedInk = OKLCHColor(0.690, 0.050, 145).color
            subtleInk = OKLCHColor(0.570, 0.045, 145).color
            divider = OKLCHColor(0.285, 0.055, 145).color
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
            sidebar = OKLCHColor(0.915, 0.008, 145).color
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

    private static func primaryColor(
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

    private static func primarySoftColor(for choice: AppAccentChoice, scheme: ColorScheme) -> Color {
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
    static var workspaceInset: CGFloat { AppStyleDefaults.theme == .softGlass ? 12 : 0 }
    static var panelSpacing: CGFloat { AppStyleDefaults.theme == .softGlass ? 12 : 0 }
    static var panelCornerRadius: CGFloat { AppStyleDefaults.theme == .softGlass ? 18 : 0 }
    static let titlebarBrandLeading: CGFloat = 76
    static var controlCornerRadius: CGFloat {
        switch AppStyleDefaults.theme {
        case .standard: 8
        case .softGlass: 10
        case .console: 4
        }
    }
    static let topBarHeight: CGFloat = 62
}

struct AppThemeRoot<Content: View>: View {
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue
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

    var body: some View {
        if theme != .softGlass {
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

private struct WindowThemeSurface: NSViewRepresentable {
    let theme: AppVisualTheme
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> NSVisualEffectView {
        GlassEffectView()
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        let usesGlass = theme == .softGlass
        nsView.material = usesGlass ? .underWindowBackground : .contentBackground
        nsView.blendingMode = usesGlass ? .behindWindow : .withinWindow
        nsView.state = usesGlass ? .followsWindowActiveState : .inactive
        if let effectView = nsView as? GlassEffectView {
            effectView.usesGlass = usesGlass
            effectView.opaqueBackgroundColor = colorScheme == .dark
                ? NSColor(calibratedWhite: 0.10, alpha: 1)
                : .white
        }
    }
}

private final class GlassEffectView: NSVisualEffectView {
    var usesGlass = true {
        didSet { configureWindow() }
    }
    var opaqueBackgroundColor = NSColor.white {
        didSet { configureWindow() }
    }

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
        configureWindow()
    }

    private func configureWindow() {
        guard let window else { return }
        window.isOpaque = !usesGlass
        window.backgroundColor = usesGlass ? .clear : opaqueBackgroundColor
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
    }
}

private struct AppGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let elevated: Bool
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue

    @ViewBuilder
    func body(content: Content) -> some View {
        let palette = AppPalette(colorScheme)
        if AppVisualTheme.resolved(themeRaw) == .softGlass {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            colorScheme == .dark
                                ? Color.black.opacity(elevated ? 0.50 : 0.38)
                                : Color.white.opacity(elevated ? 0.58 : 0.44)
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            colorScheme == .dark
                                ? Color.white.opacity(0.12)
                                : Color.white.opacity(0.72),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: Color.black.opacity(elevated ? (colorScheme == .dark ? 0.28 : 0.10) : 0),
                    radius: elevated ? 14 : 0,
                    y: elevated ? 6 : 0
                )
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
}

private struct AppConsolePanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue

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
