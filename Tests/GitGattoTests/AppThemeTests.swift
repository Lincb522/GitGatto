import AppKit
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Application themes")
struct AppThemeTests {
    @MainActor
    @Test("Ambient lights retain their motion configuration and honor visibility and reduced motion")
    func lumenAmbientMotionLifecycle() throws {
        let window = ThemeTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
                                     styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: AppThemeBackdrop(theme: .lumen, colorScheme: .light)
            .environment(\.accessibilityReduceTransparency, false))
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()
        let view = try #require(ambientView(in: hosting))
        view.configure(colorScheme: .light, reduceMotion: false)
        let lights = try #require(view.layer?.sublayers?.compactMap { $0 as? CAGradientLayer })
        #expect(lights.count == 2)
        #expect(lights.allSatisfy { $0.animationKeys()?.isEmpty != false })
        window.setTestVisibility(true)
        let animations = try lights.map { try #require($0.animation(forKey: "ambientMotion") as? CABasicAnimation) }
        #expect(animations.map(\.duration) == [11, 13])
        #expect(animations.allSatisfy { $0.keyPath == "position" && $0.autoreverses && $0.repeatCount.isInfinite })
        #expect(lights.allSatisfy { $0.type == .radial && $0.colors?.count == 4 })
        #expect(view.hitTest(.zero) == nil)
        #expect(!view.isAccessibilityElement())
        view.configure(colorScheme: .light, reduceMotion: false)
        #expect(lights.first?.animation(forKey: "ambientMotion")?.beginTime == animations.first?.beginTime)
        view.configure(colorScheme: .dark, reduceMotion: true)
        #expect(lights.allSatisfy { $0.animationKeys()?.isEmpty != false })
        let colors = try #require(lights[0].colors as? [CGColor])
        let coral = try #require(colors.first)
        #expect(abs(coral.alpha - 0.22) < 0.001)
        view.configure(colorScheme: .dark, reduceMotion: false)
        #expect(lights.allSatisfy { $0.animation(forKey: "ambientMotion") != nil })
        window.orderOut(nil)
        #expect(lights.allSatisfy { $0.animationKeys()?.isEmpty != false })
        window.orderFront(nil)
        #expect(lights.allSatisfy { $0.animation(forKey: "ambientMotion") != nil })
        window.setTestVisibility(false)
        #expect(lights.allSatisfy { $0.animationKeys()?.isEmpty != false })
        window.setTestVisibility(true)
        #expect(lights.allSatisfy { $0.animation(forKey: "ambientMotion") != nil })
        window.contentView = nil
        #expect(lights.allSatisfy { $0.animationKeys()?.isEmpty != false })
    }

    @MainActor
    @Test("Lumen light geometry follows window resizing in both appearances", arguments: [ColorScheme.light, .dark])
    func lumenResizesWithoutClipping(colorScheme: ColorScheme) async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: AppThemeBackdrop(theme: .lumen, colorScheme: colorScheme)
            .environment(\.accessibilityReduceTransparency, false))
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        for size in [CGSize(width: 960, height: 620), CGSize(width: 1416, height: 878)] {
            window.setContentSize(size)
            hosting.layoutSubtreeIfNeeded()
            let ambient = try #require(ambientView(in: hosting))
            ambient.configure(colorScheme: colorScheme, reduceMotion: true)
            ambient.layoutSubtreeIfNeeded()
            let lights = try #require(ambient.layer?.sublayers?.compactMap { $0 as? CAGradientLayer })
            #expect(lights.count == 2)
            let radius = max(ambient.bounds.width, ambient.bounds.height) * 0.82
            #expect(lights.allSatisfy { abs($0.bounds.width - radius * 2) < 0.1 && abs($0.bounds.height - radius * 2) < 0.1 })
            #expect(abs(lights[0].position.x - ambient.bounds.width * 0.02) < 0.1)
            #expect(abs(lights[1].position.y - ambient.bounds.height * 0.36) < 0.1)
            #expect(ambient.layer?.masksToBounds == true)
            hosting.displayIfNeeded()
            if let directory = ProcessInfo.processInfo.environment["GITGATTO_THEME_UI_OUTPUT"] {
                let output = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: output.appendingPathComponent("lumen-\(Int(size.width))-\(colorScheme).png"))
            }
        }
    }

    @MainActor
    @Test("Lumen omits ambient effects when transparency is reduced")
    func lumenReducedTransparency() {
        let hosting = NSHostingView(rootView: AppThemeBackdrop(theme: .lumen, colorScheme: .light)
            .environment(\.accessibilityReduceTransparency, true))
        hosting.frame = NSRect(x: 0, y: 0, width: 960, height: 620)
        hosting.layoutSubtreeIfNeeded()
        #expect(ambientView(in: hosting) == nil)
    }

    @MainActor
    private func ambientView(in view: NSView) -> LumenAmbientLightsView? {
        (view as? LumenAmbientLightsView) ?? view.subviews.lazy.compactMap { ambientView(in: $0) }.first
    }

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

@MainActor
private final class ThemeTestWindow: NSWindow {
    private var testOcclusion: NSWindow.OcclusionState = []
    override var occlusionState: NSWindow.OcclusionState { testOcclusion }

    func setTestVisibility(_ visible: Bool) {
        testOcclusion = visible ? [.visible] : []
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: self)
    }
}
