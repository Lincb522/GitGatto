import AppKit
import SwiftUI
import Testing
import Vision
@testable import GitGatto

@Suite("Sidebar count rendering", .serialized)
@MainActor
struct SidebarCountRenderingTests {
    @Test("Expanded sidebars widen saved narrow widths without wrapping counts", .timeLimit(.minutes(3)))
    func countLayout() async throws {
        let defaults = UserDefaults.standard
        let savedTheme = defaults.object(forKey: AppStyleDefaults.themeKey)
        defer {
            defaults.set(savedTheme, forKey: AppStyleDefaults.themeKey)
            L10n.activate(AppPreferencesStore.load().language)
        }
        let themes: [AppVisualTheme] = [.standard, .softGlass, .emerald, .folio, .lumen]
        for theme in themes {
            defaults.set(theme.rawValue, forKey: AppStyleDefaults.themeKey)
            for width in [960.0, 1416.0] {
                for scheme in [ColorScheme.light, .dark] {
                    L10n.activate(.simplifiedChinese)
                    try await render(theme: theme, width: width, scheme: scheme, language: .simplifiedChinese)
                }
            }
        }
        defaults.set(AppVisualTheme.softGlass.rawValue, forKey: AppStyleDefaults.themeKey)
        for language in [AppLanguage.german, .arabic] {
            L10n.activate(language)
            try await render(theme: .softGlass, width: 960, scheme: .dark, language: language)
        }
    }

    @Test("Wider sidebars fit the complete workspace at narrow and wide sizes",
          .enabled(if: ProcessInfo.processInfo.environment["GITGATTO_WORKSPACE_PREVIEW"] == "1" &&
                       ProcessInfo.processInfo.environment["GITGATTO_MARKETPLACE_PREVIEW"] == "1"))
    func workspaceLayout() async throws {
        let defaults = UserDefaults.standard
        let keys = [AppStyleDefaults.themeKey, "appearance", "workspace.sidebar.width", "workspace.sidebar.collapsed"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) }
            L10n.activate(AppPreferencesStore.load().language)
        }
        L10n.activate(.simplifiedChinese)
        defaults.set(228.5, forKey: "workspace.sidebar.width")
        defaults.set(false, forKey: "workspace.sidebar.collapsed")
        let model = WorkspaceViewModel(isBackgroundMonitor: true, monitoredRepositories: [])
        await model.start()
        model.selectedSection = .changes
        for theme in [AppVisualTheme.standard, .softGlass, .emerald, .folio, .lumen, .console] {
            defaults.set(theme.rawValue, forKey: AppStyleDefaults.themeKey)
            for (width, scheme) in [(960, ColorScheme.light), (1416, .dark)] {
                defaults.set(scheme == .dark ? "dark" : "light", forKey: "appearance")
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 878),
                                      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                let host = NSHostingView(rootView: AppThemeRoot {
                    WorkspaceView(model: model, canCaptureSnapshot: false)
                })
                host.sizingOptions = []
                window.contentView = host
                window.setContentSize(NSSize(width: width, height: 878))
                window.orderFront(nil)
                defer { window.orderOut(nil); window.contentView = nil }
                for _ in 0..<20 { await Task.yield() }
                host.layoutSubtreeIfNeeded()
                func descendants(_ view: NSView) -> [NSView] {
                    view.subviews.flatMap { [$0] + descendants($0) }
                }
                #expect(abs(host.bounds.width - Double(width)) < 1)
                for scroll in descendants(host).compactMap({ $0 as? NSScrollView }) {
                    let frame = scroll.convert(scroll.bounds, to: host)
                    #expect(frame.minX >= -2 && frame.maxX <= host.bounds.maxX + 2,
                            "\(theme)/\(width) scroll frame \(frame) exceeds \(host.bounds)")
                }
                if let field = descendants(host).compactMap({ $0 as? NSTextField }).first(where: \.isEditable) {
                    #expect(window.makeFirstResponder(field))
                    window.makeFirstResponder(nil)
                }
                if let directory = ProcessInfo.processInfo.environment["GITGATTO_SIDEBAR_OUTPUT"] {
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: URL(fileURLWithPath: directory)
                        .appendingPathComponent("workspace-\(theme.rawValue)-\(width)-\(scheme).png"))
                }
            }
        }
    }

    private func render(theme: AppVisualTheme, width: Double, scheme: ColorScheme, language: AppLanguage) async throws {
        let minimumWidth = WorkspaceView.expandedSidebarMinimumWidth
        let root = HorizontalResizableSplitView(
            primaryWidth: .constant(228.5), minimumPrimaryWidth: minimumWidth,
            maximumPrimaryWidth: 330, minimumSecondaryWidth: 690, separatorWidth: 7
        ) {
            VStack(spacing: 4) {
                SidebarNavigationButton(titleKey: "nav.changes", systemImage: "square.stack.3d.up",
                                        count: 38_452, isSelected: true, action: {})
                SidebarNavigationButton(titleKey: "nav.timeMachine", systemImage: "history.file",
                                        count: 13_639, isSelected: false, action: {})
                SidebarNavigationButton(titleKey: "nav.history", systemImage: "clock.arrow.circlepath",
                                        count: 1_234_567, isSelected: false, action: {})
                SidebarNavigationButton(titleKey: "nav.marketplace", systemImage: "arrow.down.app",
                                        count: nil, isSelected: false, action: {})
                SidebarNavigationButton(titleKey: "nav.goals", systemImage: "checkmark.seal",
                                        count: 0, isSelected: false, action: {})
                    .disabled(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(SidebarBoundsProbe())
        } secondary: {
            Color.clear
        }
        .environment(\.colorScheme, scheme)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.layoutDirection, language.usesRightToLeftLayout ? .rightToLeft : .leftToRight)
        .background(AppPalette(scheme).sidebar)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 276),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        for _ in 0..<10 { await Task.yield() }
        hosting.layoutSubtreeIfNeeded()
        func findProbe(_ view: NSView) -> NSView? {
            if view.identifier?.rawValue == "sidebar-bounds-probe" { return view }
            return view.subviews.lazy.compactMap { findProbe($0) }.first
        }
        let probe = try #require(findProbe(hosting))
        #expect(abs(probe.bounds.width - minimumWidth) < 1)
        let bounds = probe.convert(probe.bounds, to: hosting)
        #expect(bounds.minX >= -1 && bounds.maxX <= hosting.bounds.maxX + 1)
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: bounds))
        hosting.cacheDisplay(in: bounds, to: bitmap)
        let image = try #require(bitmap.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.minimumTextHeight = 0
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        // Vision can mistake pale capsule edges for digit boundaries; verify inactive counts in dark appearance.
        let expectedCounts = scheme == .dark ? ["38452", "13639", "1234567"] : ["38452"]
        for count in expectedCounts {
            #expect(lines.contains { $0.filter(\.isNumber) == count },
                    "\(theme.rawValue)/\(scheme)/\(width)/\(language.rawValue): count must stay on one line: \(lines)")
        }
        if language == .simplifiedChinese {
            #expect(lines.contains { $0.contains("工作区变更") }, "The navigation title must remain complete: \(lines)")
        }
        if let directory = ProcessInfo.processInfo.environment["GITGATTO_SIDEBAR_OUTPUT"] {
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: directory)
                .appendingPathComponent("\(theme.rawValue)-\(Int(width))-\(scheme)-\(language.rawValue).png"))
        }
    }
}

private struct SidebarBoundsProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier("sidebar-bounds-probe")
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
