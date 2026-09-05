import AppKit
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Application themes")
struct AppThemeTests {
    @Test("Uses glass by default and preserves saved theme selections")
    func resolvesStoredTheme() {
        #expect(AppVisualTheme.resolved(nil) == .softGlass)
        #expect(AppVisualTheme.resolved("unknown") == .softGlass)
        #expect(AppVisualTheme.resolved(AppVisualTheme.standard.rawValue) == .standard)
        #expect(AppVisualTheme.resolved(AppVisualTheme.softGlass.rawValue) == .softGlass)
        #expect(AppVisualTheme.resolved(AppVisualTheme.console.rawValue) == .console)
        #expect(AppVisualTheme.resolved(AppVisualTheme.emerald.rawValue) == .emerald)
        #expect(AppVisualTheme.resolved(AppVisualTheme.folio.rawValue) == .folio)
        #expect(AppVisualTheme.resolved(AppVisualTheme.lumen.rawValue) == .lumen)
    }

    @MainActor
    @Test("Secondary text remains readable on the redesigned work surfaces", arguments: [ColorScheme.light, .dark])
    func redesignedThemeTextContrast(colorScheme: ColorScheme) throws {
        func luminance(_ color: Color) throws -> Double {
            let rgb = try #require(NSColor(color).usingColorSpace(.sRGB))
            func linear(_ value: CGFloat) -> Double {
                let value = Double(value)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        }
        for theme in [AppVisualTheme.console, .emerald, .folio] {
            let palette = AppPalette(colorScheme, theme: theme)
            for background in [palette.background, palette.sidebar, palette.surface, palette.raisedSurface] {
                let ink = try luminance(palette.subtleInk)
                let surface = try luminance(background)
                let contrast = (max(ink, surface) + 0.05) / (min(ink, surface) + 0.05)
                #expect(contrast >= 4.5, "\(theme) secondary text contrast: \(contrast)")
            }
        }
    }

    @MainActor
    @Test("Switches every theme while the window is attached", arguments: [ColorScheme.light, .dark])
    func switchesAttachedWindowThemes(colorScheme: ColorScheme) async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(
            rootView: AnyView(
                WindowThemeSurface(theme: .softGlass, colorScheme: colorScheme)
                    .id(AppVisualTheme.softGlass.rawValue)
            )
        )
        window.contentView = hostingView
        window.orderFront(nil)

        for theme in [
            AppVisualTheme.standard,
            .console,
            .emerald,
            .folio,
            .lumen,
            .softGlass,
            .standard,
            .softGlass
        ] {
            hostingView.rootView = AnyView(
                WindowThemeSurface(theme: theme, colorScheme: colorScheme)
                    .id(theme.rawValue)
            )
            hostingView.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
            #expect(window.isOpaque == (theme != .softGlass && theme != .lumen))
        }

        #expect(window.titleVisibility == .hidden)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.isMovableByWindowBackground)
        window.orderOut(nil)
        window.contentView = nil
    }
}
