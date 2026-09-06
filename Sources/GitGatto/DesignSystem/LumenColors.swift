import AppKit
import Observation
import SwiftUI

enum LumenColorPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case coral, coast, forest, dusk
    var id: String { rawValue }
    var titleKey: String { "lumen.preset.\(rawValue)" }
}

enum LumenColorAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case light, dark
    var id: String { rawValue }
    var scheme: ColorScheme { self == .dark ? .dark : .light }
    init(_ scheme: ColorScheme) { self = scheme == .dark ? .dark : .light }
}

enum LumenColorGroup: String, CaseIterable, Identifiable {
    case background, surfaces, text, actions, status
    var id: String { rawValue }
    var roles: [LumenColorRole] {
        switch self {
        case .background: [.background, .ambientLeading, .ambientTrailing, .vignette, .backdropTop, .backdropBottom]
        case .surfaces: [.sidebar, .surface, .raisedSurface, .chrome, .panel, .inset, .divider, .chromeBorder]
        case .text: [.ink, .mutedInk, .subtleInk, .onPrimary]
        case .actions: [.primary, .primarySoft, .accent, .accentSoft]
        case .status: [.success, .successSoft, .warning, .warningSoft, .danger, .dangerSoft]
        }
    }
}

enum LumenColorRole: String, CaseIterable, Codable, Identifiable, Sendable {
    case background, sidebar, surface, raisedSurface, ink, mutedInk, subtleInk, divider
    case primary, primarySoft, accent, accentSoft, success, successSoft, danger, dangerSoft, warning, warningSoft
    case ambientLeading, ambientTrailing, vignette, backdropTop, backdropBottom, chrome, panel, inset, chromeBorder, onPrimary
    var id: String { rawValue }
    var titleKey: String { "lumen.color.\(rawValue)" }
}

struct LumenColorSettings: Codable, Equatable, Sendable {
    var preset: LumenColorPreset = .coral
    // Keep each preset's edits when switching, with independent light and dark variants.
    private(set) var overrides: [String: [String: String]] = [:]

    private func key(_ appearance: LumenColorAppearance) -> String { "\(preset.rawValue).\(appearance.rawValue)" }

    func override(_ role: LumenColorRole, appearance: LumenColorAppearance) -> String? {
        overrides[key(appearance)]?[role.rawValue]
    }

    mutating func set(_ hex: String?, for role: LumenColorRole, appearance: LumenColorAppearance) {
        if let hex {
            guard let normalized = LumenRGBA(hex: hex)?.hex else { return }
            overrides[key(appearance), default: [:]][role.rawValue] = normalized
        } else {
            overrides[key(appearance)]?[role.rawValue] = nil
            if overrides[key(appearance)]?.isEmpty == true { overrides[key(appearance)] = nil }
        }
    }

    mutating func reset(_ appearance: LumenColorAppearance) { overrides[key(appearance)] = nil }

    static func decode(_ data: Data?) -> Self {
        guard let data, let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        var result = Self()
        result.preset = decoded.preset
        for preset in LumenColorPreset.allCases {
            for appearance in LumenColorAppearance.allCases {
                let key = "\(preset.rawValue).\(appearance.rawValue)"
                let entries = decoded.overrides[key, default: [:]].filter {
                    LumenColorRole(rawValue: $0.key) != nil && LumenRGBA(hex: $0.value) != nil
                }
                if !entries.isEmpty { result.overrides[key] = entries }
            }
        }
        return result
    }

    func resolved(
        _ scheme: ColorScheme,
        accentChoice: AppAccentChoice = AppStyleDefaults.accent,
        customAccentHex: String = AppStyleDefaults.customAccentHex
    ) -> LumenResolvedColors {
        let dark = scheme == .dark
        let primary = AppPalette.primaryColor(for: accentChoice, scheme: scheme, customHex: customAccentHex)
        let originalInk = dark ? Color(red: 246/255, green: 245/255, blue: 241/255) : Color(red: 23/255, green: 22/255, blue: 25/255)
        var colors: [LumenColorRole: Color] = [
            .background: dark ? rgb("050505") : rgb("F6F2EC"),
            .sidebar: dark ? rgb("0D0C0E").opacity(0.28) : .white.opacity(0.18),
            .surface: dark ? rgb("0F0E10").opacity(0.48) : .white.opacity(0.48),
            .raisedSurface: dark ? rgb("181619") : .white,
            .ink: originalInk, .mutedInk: originalInk.opacity(dark ? 0.62 : 0.66),
            .subtleInk: originalInk.opacity(dark ? 0.58 : 0.60),
            .divider: dark ? .white.opacity(0.10) : rgb("1D181B").opacity(0.10),
            .primary: primary,
            .primarySoft: accentChoice == .custom ? primary.opacity(dark ? 0.22 : 0.14) : AppPalette.primarySoftColor(for: accentChoice, scheme: scheme),
            .accent: OKLCHColor(dark ? 0.735 : 0.610, dark ? 0.100 : 0.115, 285).color,
            .accentSoft: OKLCHColor(dark ? 0.245 : 0.925, dark ? 0.050 : 0.035, 285).color,
            .success: OKLCHColor(dark ? 0.760 : 0.495, 0.135, 151).color,
            .successSoft: OKLCHColor(dark ? 0.235 : 0.940, dark ? 0.045 : 0.035, 151).color,
            .danger: OKLCHColor(dark ? 0.735 : 0.550, dark ? 0.175 : 0.185, 25).color,
            .dangerSoft: OKLCHColor(dark ? 0.235 : 0.945, dark ? 0.055 : 0.040, 25).color,
            .warning: OKLCHColor(dark ? 0.820 : 0.590, 0.145, 86).color,
            .warningSoft: OKLCHColor(dark ? 0.245 : 0.945, dark ? 0.050 : 0.045, 86).color,
            .ambientLeading: dark ? rgb("FF5442").opacity(0.22) : rgb("FF5D48").opacity(0.28),
            .ambientTrailing: dark ? rgb("7265FF").opacity(0.19) : rgb("7E71FF").opacity(0.24),
            .vignette: dark ? .black.opacity(0.44) : rgb("EEE8E1").opacity(0.64),
            .backdropTop: dark ? .black.opacity(0.12) : .white.opacity(0.08),
            .backdropBottom: dark ? .black.opacity(0.46) : rgb("ECE7E0").opacity(0.34),
            .chrome: dark ? .black.opacity(0.18) : .white.opacity(0.26),
            .panel: dark ? .black.opacity(0.20) : .white.opacity(0.40),
            .inset: dark ? .black.opacity(0.14) : .white.opacity(0.22),
            .chromeBorder: dark ? .white.opacity(0.18) : rgb("1D181B").opacity(0.16),
            .onPrimary: .white
        ]
        if preset != .coral {
            let hues: (Double, Double) = switch preset {
            case .coast: (235, 195)
            case .forest: (160, 85)
            case .dusk: (300, 345)
            case .coral: (49, 285)
            }
            colors[.background] = OKLCHColor(dark ? 0.17 : 0.96, 0.012, hues.0).color
            colors[.sidebar] = OKLCHColor(dark ? 0.21 : 0.98, 0.018, hues.0).color.opacity(dark ? 0.28 : 0.18)
            colors[.surface] = OKLCHColor(dark ? 0.22 : 0.99, 0.012, hues.0).color.opacity(0.48)
            colors[.raisedSurface] = OKLCHColor(dark ? 0.25 : 0.995, 0.008, hues.0).color
            colors[.ink] = OKLCHColor(dark ? 0.96 : 0.20, 0.012, hues.0).color
            colors[.mutedInk] = OKLCHColor(dark ? 0.75 : 0.43, 0.018, hues.0).color
            colors[.subtleInk] = OKLCHColor(dark ? 0.71 : 0.46, 0.016, hues.0).color
            colors[.divider] = OKLCHColor(dark ? 0.90 : 0.25, 0.020, hues.0).color.opacity(0.13)
            colors[.primary] = OKLCHColor(dark ? 0.74 : 0.51, 0.125, hues.0).color
            colors[.onPrimary] = dark ? rgb("101418") : .white
            colors[.primarySoft] = OKLCHColor(dark ? 0.30 : 0.90, 0.040, hues.0).color
            colors[.accent] = OKLCHColor(dark ? 0.75 : 0.52, 0.100, hues.1).color
            colors[.accentSoft] = OKLCHColor(dark ? 0.29 : 0.92, 0.035, hues.1).color
            colors[.ambientLeading] = OKLCHColor(0.70, 0.15, hues.0).color.opacity(dark ? 0.22 : 0.28)
            colors[.ambientTrailing] = OKLCHColor(0.72, 0.13, hues.1).color.opacity(dark ? 0.19 : 0.24)
            colors[.vignette] = OKLCHColor(dark ? 0.13 : 0.92, 0.020, hues.0).color.opacity(dark ? 0.44 : 0.64)
            colors[.backdropBottom] = OKLCHColor(dark ? 0.13 : 0.91, 0.022, hues.0).color.opacity(dark ? 0.46 : 0.34)
            for role in [LumenColorRole.chrome, .panel, .inset] {
                let opacity = NSColor(colors[role] ?? .clear).alphaComponent
                colors[role] = OKLCHColor(dark ? 0.16 : 0.99, 0.015, hues.0).color.opacity(opacity)
            }
            colors[.chromeBorder] = OKLCHColor(dark ? 0.90 : 0.25, 0.020, hues.0).color.opacity(dark ? 0.18 : 0.16)
        }
        let edits = overrides[key(LumenColorAppearance(scheme)), default: [:]]
        for role in LumenColorRole.allCases {
            if let hex = edits[role.rawValue], let rgba = LumenRGBA(hex: hex) { colors[role] = rgba.color }
        }
        let originalStops: [[Color]] = dark ? [
            [rgb("FF5442").opacity(0.22), rgb("FF5442").opacity(0.10), rgb("B9314B").opacity(0.035), .clear],
            [rgb("7265FF").opacity(0.19), rgb("7265FF").opacity(0.09), rgb("433BA6").opacity(0.03), .clear]
        ] : [
            [rgb("FF5D48").opacity(0.28), rgb("F7706A").opacity(0.14), rgb("E27E8A").opacity(0.043), .clear],
            [rgb("7E71FF").opacity(0.24), rgb("897EF0").opacity(0.12), rgb("9289D8").opacity(0.04), .clear]
        ]
        let stops = [LumenColorRole.ambientLeading, .ambientTrailing].enumerated().map { index, role in
            if preset == .coral, edits[role.rawValue] == nil { return originalStops[index] }
            let color = colors[role] ?? .clear
            return [color, color.opacity(0.5), color.opacity(0.16), .clear]
        }
        return LumenResolvedColors(colors: colors, ambientStops: stops)
    }

    private func rgb(_ hex: String) -> Color { Color(hex: hex) ?? .clear }
}

struct LumenResolvedColors: Equatable {
    let colors: [LumenColorRole: Color]
    let ambientStops: [[Color]]
    subscript(_ role: LumenColorRole) -> Color { colors[role] ?? .clear }

    func opaque(_ role: LumenColorRole) -> Color {
        Color(nsColor: NSColor(self[role]).withAlphaComponent(1))
    }
}

struct LumenRGBA: Equatable {
    let color: Color
    let hex: String

    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard [6, 8].contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let value = UInt32(digits, radix: 16) else { return nil }
        let rgba = digits.count == 6 ? (value << 8) | 0xFF : value
        self.hex = String(format: "#%08X", rgba)
        color = Color(.sRGB, red: Double((rgba >> 24) & 255)/255,
                      green: Double((rgba >> 16) & 255)/255, blue: Double((rgba >> 8) & 255)/255,
                      opacity: Double(rgba & 255)/255)
    }

    init?(_ color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
        guard components.allSatisfy(\.isFinite) else { return nil }
        self.init(hex: "#" + components.map { String(format: "%02X", Int((min(1, max(0, $0)) * 255).rounded())) }.joined())
    }
}

@MainActor @Observable
final class LumenColorStore {
    static let shared = LumenColorStore(defaults: .standard)
    static let storageKey = "lumenColorSettings"
    private(set) var settings: LumenColorSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var cache: [String: LumenResolvedColors] = [:]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        settings = LumenColorSettings.decode(defaults.data(forKey: Self.storageKey))
    }

    func apply(_ settings: LumenColorSettings) throws {
        guard self.settings != settings else { return }
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: Self.storageKey)
        cache.removeAll(keepingCapacity: true)
        self.settings = settings
    }

    func resolved(_ scheme: ColorScheme, accentChoice: AppAccentChoice, customAccentHex: String) -> LumenResolvedColors {
        let settings = settings // Register only palette consumers; do not replace the workspace's identity.
        let key = "\(scheme):\(accentChoice.rawValue):\(customAccentHex)"
        if let colors = cache[key] { return colors }
        let colors = settings.resolved(scheme, accentChoice: accentChoice, customAccentHex: customAccentHex)
        if cache.count > 16 { cache.removeAll(keepingCapacity: true) }
        cache[key] = colors
        return colors
    }
}
