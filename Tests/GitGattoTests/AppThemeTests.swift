import AppKit
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Application themes", .serialized)
struct AppThemeTests {
    @MainActor
    @Test("Ambient lights retain their motion configuration and honor visibility and reduced motion")
    func lumenAmbientMotionLifecycle() throws {
        let window = ThemeTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
                                     styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        // Test the compositor independently of accessibility settings that can omit it from the backdrop.
        let view = LumenAmbientLightsView(frame: window.contentLayoutRect)
        view.configure(colorScheme: .light, reduceMotion: false)
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        view.layoutSubtreeIfNeeded()
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
        let ambient = LumenAmbientLightsView(frame: window.contentLayoutRect)
        ambient.configure(colorScheme: colorScheme, reduceMotion: true)
        window.contentView = ambient
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        for size in [CGSize(width: 960, height: 620), CGSize(width: 1416, height: 878)] {
            window.setContentSize(size)
            ambient.layoutSubtreeIfNeeded()
            let lights = try #require(ambient.layer?.sublayers?.compactMap { $0 as? CAGradientLayer })
            #expect(lights.count == 2)
            let radius = max(ambient.bounds.width, ambient.bounds.height) * 0.82
            #expect(lights.allSatisfy { abs($0.bounds.width - radius * 2) < 0.1 && abs($0.bounds.height - radius * 2) < 0.1 })
            #expect(abs(lights[0].position.x - ambient.bounds.width * 0.02) < 0.1)
            #expect(abs(lights[1].position.y - ambient.bounds.height * 0.36) < 0.1)
            #expect(ambient.layer?.masksToBounds == true)
            ambient.displayIfNeeded()
            if let directory = ProcessInfo.processInfo.environment["GITGATTO_THEME_UI_OUTPUT"] {
                let output = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let bitmap = try #require(ambient.bitmapImageRepForCachingDisplay(in: ambient.bounds))
                ambient.cacheDisplay(in: ambient.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: output.appendingPathComponent("lumen-\(Int(size.width))-\(colorScheme).png"))
            }
        }
    }

    @MainActor
    @Test("Frost panels share one native blur in both appearances and widths")
    func frostMaterialRendering() async throws {
        for scheme in [ColorScheme.light, .dark] {
                for width in [480, 960] {
                    let palette = AppPalette(scheme, theme: .frost)
                    let root = ZStack {
                        AppThemeBackdrop(theme: .frost, colorScheme: scheme)
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Repository · 仓库 · Repository with a longer name")
                                .font(.headline).foregroundStyle(palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18).frostSurface(.chrome)
                            VStack(alignment: .leading, spacing: 18) {
                                Text("Changes · 改动").font(.headline).foregroundStyle(palette.ink)
                                Text("Sources / RepositoryStatus.swift")
                                    .foregroundStyle(palette.mutedInk)
                                Text("No changes · 暂无改动").foregroundStyle(palette.subtleInk)
                                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .frostSurface(.inset, cornerRadius: 16)
                            }
                            .padding(20).frostSurface()
                        }
                        .padding(20)
                    }
                    .environment(\.colorScheme, scheme)
                    .frame(width: CGFloat(width), height: 360)
                    let host = NSHostingView(rootView: root)
                    host.sizingOptions = []
                    let bounds = NSRect(x: 0, y: 0, width: width, height: 360)
                    let window = NSWindow(contentRect: bounds, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                    window.contentView = host
                    host.frame = bounds
                    window.orderFront(nil)
                    defer { window.orderOut(nil); window.contentView = nil }
                    await Task.yield()
                    host.layoutSubtreeIfNeeded()
                    func effects(_ view: NSView) -> [NSVisualEffectView] {
                        (view as? NSVisualEffectView).map { [$0] } ?? view.subviews.flatMap(effects)
                    }
                    #expect(effects(host).count == 1)
                    #expect(host.bounds.size == bounds.size)
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    if let directory = ProcessInfo.processInfo.environment["GITGATTO_THEME_UI_OUTPUT"] {
                        let output = URL(fileURLWithPath: directory)
                        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                        let data = try #require(bitmap.representation(using: .png, properties: [:]))
                        try data.write(to: output.appendingPathComponent("frost-material-\(scheme)-\(width).png"))
                    }
                }
        }
    }

    @MainActor
    @Test("Frost folder workspace and settings fit wide and compact windows", .timeLimit(.minutes(2)))
    func frostWorkspaceRendering() async throws {
        guard let directory = ProcessInfo.processInfo.environment["GITGATTO_THEME_UI_OUTPUT"],
              ProcessInfo.processInfo.environment["GITGATTO_WORKSPACE_PREVIEW"] == "1",
              ProcessInfo.processInfo.environment["GITGATTO_MARKETPLACE_PREVIEW"] == "1" else { return }
        let defaults = UserDefaults.standard
        let keys = [AppStyleDefaults.themeKey, "appearance", "workspace.sidebar.collapsed", AppStyleDefaults.accentKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) }
            L10n.activate(AppPreferencesStore.load().language)
        }
        defaults.set("frost", forKey: AppStyleDefaults.themeKey)
        defaults.set("blue", forKey: AppStyleDefaults.accentKey)
        let model = WorkspaceViewModel(isBackgroundMonitor: true, monitoredRepositories: [])
        await model.start()
        model.selectedSection = .changes
        let emptyModel = WorkspaceViewModel(isBackgroundMonitor: true, monitoredRepositories: [])
        emptyModel.selectedSection = .changes
        let originalAppearance = NSApp.appearance
        defer { NSApp.appearance = originalAppearance }
        for (width, height, scheme, collapsed, settings, language, state) in [
            (1416, 878, ColorScheme.light, false, false, AppLanguage.simplifiedChinese, "workspace"),
            (1416, 878, ColorScheme.dark, false, false, AppLanguage.simplifiedChinese, "workspace"),
            (960, 620, ColorScheme.light, false, false, AppLanguage.simplifiedChinese, "workspace"),
            (960, 620, ColorScheme.dark, true, false, AppLanguage.simplifiedChinese, "compact"),
            (960, 760, ColorScheme.light, false, true, AppLanguage.simplifiedChinese, "settings"),
            (960, 620, ColorScheme.light, false, false, AppLanguage.german, "empty"),
            (960, 620, ColorScheme.dark, false, false, AppLanguage.arabic, "attention")
        ] {
            L10n.activate(language)
            NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            model.notice = state == "attention" ? OperationNotice(message: "Connection unavailable. Check your network and retry.", tone: .attention) : nil
            defaults.set(scheme == .dark ? "dark" : "light", forKey: "appearance")
            defaults.set(collapsed, forKey: "workspace.sidebar.collapsed")
            let content: AnyView
            if settings {
                content = AnyView(AppSettingsView(model: model, updateManager: AppUpdateManager()))
            } else {
                content = AnyView(WorkspaceView(model: state == "empty" ? emptyModel : model, canCaptureSnapshot: false))
            }
            let bounds = NSRect(x: 0, y: 0, width: width, height: height)
            let host = NSHostingView(rootView: AppThemeRoot { content })
            host.sizingOptions = []
            let window = NSWindow(contentRect: bounds, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = host; host.frame = bounds
            window.orderFront(nil)
            defer { window.orderOut(nil); window.contentView = nil }
            for _ in 0..<10 { await Task.yield() }
            // The material installs a full-size content view; size the frame only after that transition.
            window.setFrame(bounds, display: true)
            for _ in 0..<10 { await Task.yield() }
            host.layoutSubtreeIfNeeded()
            #expect(host.bounds.size == bounds.size)
            #expect(AppStyleDefaults.theme == .frost)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let name = state
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("frost-\(name)-\(scheme)-\(width).png"))
        }
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
        #expect(AppVisualTheme.resolved("frost") == .frost)
        #expect(AppVisualTheme.allCases.filter { $0 == .frost }.count == 1)
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
        for theme in [AppVisualTheme.console, .emerald, .folio, .frost] {
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
            .frost,
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
            #expect(window.isOpaque == (theme != .softGlass && theme != .lumen && theme != .frost))
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
