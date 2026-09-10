import AppKit
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Agent provider settings rendering", .serialized)
struct AIProviderRenderingTests {
    @MainActor @Test("API and CLI settings fit narrow, wide, dark, long-label, and RTL layouts")
    func render() async throws {
        let path = ProcessInfo.processInfo.environment["GITGATTO_API_SNAPSHOTS"]
        let original = AppPreferencesStore.load().language
        defer { if path != nil { L10n.activate(original) } }
        let cases: [(AIProviderPreset, AppLanguage, Int, ColorScheme, CodexAvailability)] = path == nil
            ? [(.deepseek, .english, 500, .light, .unavailable)]
            : [(.deepseek, .simplifiedChinese, 500, .light, .unavailable),
               (.deepseek, .simplifiedChinese, 780, .dark, .checking),
               (.openAICompatible, .german, 500, .dark, .unavailable),
               (.openAICompatible, .arabic, 500, .light, .checking),
               (.dsh, .simplifiedChinese, 500, .dark, .init(state: .available, version: "fixture")),
               (.copilot, .german, 780, .light, .unavailable)]
        for (preset, language, width, scheme, state) in cases {
            if path != nil { L10n.activate(language) }
            var config = AIProviderConfiguration.preset(preset)
            if preset == .openAICompatible {
                config.displayName = "Private development API with a deliberately long display name"
                config.api?.baseURL = "https://api.example.com/project/development/compatible/v1"
            }
            let content = ScrollView {
                AIConfigurationEditor(titleKey: "ai.settings.project", descriptionKey: "ai.settings.project.body",
                    lane: .project, configuration: .constant(config), availability: state)
                    .padding(24)
            }
            .background(AppPalette(scheme).background)
            .environment(\.colorScheme, scheme)
            .environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
            .environment(\.locale, L10n.locale)
            .dynamicTypeSize(.accessibility1)
            let host = NSHostingView(rootView: content)
            let rect = NSRect(x: 0, y: 0, width: width, height: 740)
            let window = NSWindow(contentRect: rect, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = host
            host.frame = rect
            defer { window.orderOut(nil); window.contentView = nil; window.close() }
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            #expect(abs(host.bounds.width - CGFloat(width)) < 1)
            let fields = editableFields(host)
            #expect(!fields.isEmpty)
            if let field = fields.first { #expect(window.makeFirstResponder(field)) }

            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            #expect(data.count > 4_096)
            if let path {
                let dir = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: dir.appendingPathComponent("\(preset.rawValue)-\(language.rawValue)-\(width).png"))
            }
            for scroll in scrollViews(host) {
                guard let document = scroll.documentView else { continue }
                #expect(document.bounds.width <= scroll.contentView.bounds.width + 1)
                let end = max(0, document.bounds.height - scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: end))
                scroll.reflectScrolledClipView(scroll.contentView)
                #expect(abs(scroll.contentView.bounds.origin.y - end) < 1)
            }
        }
    }

    @MainActor private func editableFields(_ view: NSView) -> [NSTextField] {
        if let field = view as? NSTextField, field.isEditable { return [field] }
        return view.subviews.flatMap(editableFields)
    }

    @MainActor private func scrollViews(_ view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }
}
