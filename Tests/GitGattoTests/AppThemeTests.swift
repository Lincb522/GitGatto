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
    @Test("Frost pages and sheets fit wide and compact windows", .timeLimit(.minutes(10)))
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
        var cases: [(Int, Int, ColorScheme, Bool, Bool, AppLanguage, String)] = [
            (1416, 878, ColorScheme.light, false, false, AppLanguage.simplifiedChinese, "workspace"),
            (1416, 878, ColorScheme.dark, false, false, AppLanguage.simplifiedChinese, "workspace"),
            (960, 620, ColorScheme.light, false, false, AppLanguage.simplifiedChinese, "workspace"),
            (960, 620, ColorScheme.dark, true, false, AppLanguage.simplifiedChinese, "compact"),
            (960, 760, ColorScheme.light, false, true, AppLanguage.simplifiedChinese, "settings"),
            (960, 620, ColorScheme.light, false, false, AppLanguage.german, "empty"),
            (960, 620, ColorScheme.dark, false, false, AppLanguage.arabic, "attention")
        ]
        if ProcessInfo.processInfo.environment["GITGATTO_THEME_ALL_PAGES"] == "1" {
            for section in WorkspaceSection.allCases {
                cases.append((960, 720, .light, false, false, .simplifiedChinese, "page-\(section.rawValue)"))
                cases.append((1416, 878, .dark, false, false, .simplifiedChinese, "page-\(section.rawValue)"))
            }
            for scheme in [ColorScheme.light, .dark] {
                cases.append((720, 720, scheme, false, false, .simplifiedChinese, "monitor"))
                cases.append((740, 660, scheme, false, false, .german, "error-sheet"))
                cases.append((680, 460, scheme, false, false, .simplifiedChinese, "about"))
                cases.append((620, 660, scheme, false, false, .simplifiedChinese, "guide"))
                cases.append((960, 720, scheme, false, false, .simplifiedChinese, "developer-tools"))
                cases.append((960, 720, scheme, false, false, .simplifiedChinese, "help"))
                cases.append((960, 720, scheme, false, false, .simplifiedChinese, "releases"))
                cases.append((960, 720, scheme, false, false, .german, "conflict"))
                cases.append((480, 660, scheme, false, false, .arabic, "bootstrap"))
                for mode in [GitHubWorkspaceMode.synchronization, .inbox, .issues] {
                    cases.append((960, 720, scheme, false, false, .simplifiedChinese, "github-\(mode.rawValue)"))
                }
            }
        }
        if let selected = ProcessInfo.processInfo.environment["GITGATTO_THEME_CASES"] {
            let names = Set(selected.split(separator: ",").map(String.init))
            cases = cases.filter { names.contains($0.6) }
        }
        for (width, height, scheme, collapsed, settings, language, state) in cases {
            model.githubWorkspaceMode = .repositories
            if state.hasPrefix("github-"), let mode = GitHubWorkspaceMode(rawValue: String(state.dropFirst(7))) {
                model.githubWorkspaceMode = mode
            }
            model.selectedSection = state.hasPrefix("page-")
                ? (WorkspaceSection(rawValue: String(state.dropFirst(5))) ?? .changes) : .changes
            if state.hasPrefix("github-") { model.selectedSection = .github }
            if state == "developer-tools" {
                model.selectedSection = .marketplace
                model.marketplaceRequestedSection = .developerTools
            }
            L10n.activate(language)
            NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            model.notice = state == "attention" ? OperationNotice(message: "Connection unavailable. Check your network and retry.", tone: .attention) : nil
            defaults.set(scheme == .dark ? "dark" : "light", forKey: "appearance")
            defaults.set(collapsed, forKey: "workspace.sidebar.collapsed")
            let content: AnyView
            if state == "monitor" {
                content = AnyView(MonitoringStatusBarView(model: model, engine: model.monitoringEngine,
                                                         availableSize: CGSize(width: width, height: height)))
            } else if state == "about" {
                content = AnyView(AboutGitGattoView(navigation: AppNavigationModel(), updateManager: AppUpdateManager()))
            } else if state == "help" {
                content = AnyView(HelpCenterView())
            } else if state == "releases" {
                content = AnyView(ReleaseHistoryView(manager: AppUpdateManager()))
            } else if state == "bootstrap" {
                let fixture = try BootstrapFixture()
                defer { fixture.remove() }
                let bootstrap = RepositoryBootstrapViewModel(service: fixture.service(), manualOptions: true)
                bootstrap.name = "Repository with a longer name"
                content = AnyView(RepositoryBootstrapSheet(workspace: model, model: bootstrap) { _, _ in })
            } else if state == "conflict" {
                let previous = ProcessInfo.processInfo.environment["GITGATTO_CONFLICT_PREVIEW"]
                setenv("GITGATTO_CONFLICT_PREVIEW", "1", 1)
                let conflictModel = WorkspaceViewModel(isBackgroundMonitor: true, monitoredRepositories: [])
                await conflictModel.start()
                if let previous { setenv("GITGATTO_CONFLICT_PREVIEW", previous, 1) }
                else { unsetenv("GITGATTO_CONFLICT_PREVIEW") }
                let operation = try #require(conflictModel.repositoryOperationState)
                content = AnyView(ConflictResolutionWorkspaceView(model: conflictModel, state: operation).padding(20))
            } else if state == "guide" {
                content = AnyView(WorkspaceQuickGuideSheet(guide: .goals))
            } else if state == "error-sheet" {
                let report = GlobalErrorHandler.report(for: GitCommandError(arguments: ["push"], exitCode: 1,
                    message: "Permission denied"), context: .git(.push), repositoryURL: URL(fileURLWithPath: "/tmp/fixture"))
                content = AnyView(GlobalErrorSheet(report: report, canUseAgent: false, useAgent: {}, dismiss: {}))
            } else if settings {
                content = AnyView(AppSettingsView(model: model, updateManager: AppUpdateManager()))
            } else {
                content = AnyView(WorkspaceView(model: state == "empty" ? emptyModel : model, canCaptureSnapshot: false))
            }
            let bounds = NSRect(x: 0, y: 0, width: width, height: height)
            let host = NSHostingView(rootView: AppThemeRoot {
                content.environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
            })
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
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            let scrolls = descendants(host).compactMap { $0 as? NSScrollView }
            for scroll in scrolls where !scroll.isHiddenOrHasHiddenAncestor {
                let frame = host.convert(scroll.bounds, from: scroll)
                #expect(frame.minX >= -2 && frame.maxX <= host.bounds.maxX + 2,
                        "\(state) scroll frame \(frame) exceeds \(host.bounds)")
            }
            if let field = descendants(host).compactMap({ $0 as? NSTextField }).first(where: \.isEditable) {
                #expect(window.makeFirstResponder(field), "\(state) field cannot receive keyboard focus")
                window.makeFirstResponder(nil)
            }
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let name = state
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("frost-\(name)-\(scheme)-\(width).png"))
            if ["page-goals", "page-regression", "help", "guide"].contains(state),
               let scroll = scrolls.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }),
               let document = scroll.documentView, document.bounds.height > scroll.contentView.bounds.height {
                document.scrollToVisible(NSRect(x: 0, y: document.bounds.maxY - 1, width: 1, height: 1))
                host.layoutSubtreeIfNeeded()
                #expect(scroll.documentVisibleRect.maxY >= document.bounds.maxY - 2)
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let bottom = try #require(bitmap.representation(using: .png, properties: [:]))
                try bottom.write(to: URL(fileURLWithPath: directory).appendingPathComponent("frost-\(name)-\(scheme)-\(width)-bottom.png"))
            }
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
