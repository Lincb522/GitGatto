import AppKit
import Foundation
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Help guides", .serialized)
struct HelpGuideTests {
    @Test("Every workspace and project tool resolves to a task guide")
    func routes() {
        let expected: [WorkspaceSection: HelpTopic] = [
            .changes: .changes, .intelligence: .intelligence, .stash: .stash,
            .history: .history, .timeMachine: .fileHistory, .recovery: .recovery,
            .branches: .branches, .worktrees: .worktrees, .diagnostics: .diagnostics,
            .regression: .regression, .github: .github, .marketplace: .applications,
            .goals: .goals, .codex: .agent
        ]
        #expect(Set(expected.keys) == Set(WorkspaceSection.allCases))
        for section in WorkspaceSection.allCases {
            #expect(HelpTopic.topic(for: section) == expected[section])
        }
        let toolTopics = ProjectTool.allCases.map { HelpTopic.topic(for: $0) }
        #expect(toolTopics == [.codeSearch, .workScenes, .projectCommands, .ignoreRules, .identities])
        #expect(Set(toolTopics).count == ProjectTool.allCases.count)
        #expect(HelpTopic(rawValue: WorkspaceQuickGuideKind.goals.helpTopicRawValue) == .goals)
        #expect(HelpTopic(rawValue: WorkspaceQuickGuideKind.regression.helpTopicRawValue) == .regression)
        #expect(HelpTopic(rawValue: "unknown") == nil)
    }

    @MainActor @Test("Every guide icon resolves to a decodable bundled asset")
    func icons() throws {
        for topic in HelpTopic.allCases {
            let name = GattoIconAssets.assetName(for: topic.icon)
            let bundle = AppResourceBundle.current
            let url = try #require(
                bundle.url(forResource: name, withExtension: "svg", subdirectory: "UIIcons")
                    ?? bundle.url(forResource: name, withExtension: "svg"),
                "Missing icon for \(topic.rawValue): \(name)"
            )
            let image = try #require(NSImage(contentsOf: url))
            #expect(!image.representations.isEmpty)
            #expect(image.size.width > 0 && image.size.height > 0)
        }
    }

    @Test("All guide text is present in each language without relying on fallback")
    func translations() throws {
        let languages = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "fr", "de", "es", "pt-BR", "ru", "ar"]
        for language in languages {
            let bundle = L10n.bundle(preferredLanguages: [language])
            let url = try #require(bundle.url(forResource: "Localizable", withExtension: "strings"))
            let data = try Data(contentsOf: url)
            let values = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            for topic in HelpTopic.allCases {
                #expect(!topic.sections.isEmpty)
                var keys = [topic.titleKey, topic.summaryKey]
                for section in topic.sections {
                    #expect(!section.bulletKeys.isEmpty)
                    #expect(Set(section.bulletKeys).count == section.bulletKeys.count)
                    keys += [section.titleKey] + section.bulletKeys
                }
                for key in keys {
                    let value = try #require(values[key], "Missing \(language): \(key)")
                    #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    #expect(value != key)
                }
            }
            #expect(values["help.current_workspace"] != nil)
            for tool in ProjectTool.allCases {
                #expect(values[HelpTopic.topic(for: tool).titleKey] == values["tools.\(tool.rawValue)"])
            }
        }
    }

    @MainActor @Test("Guides render and scroll at minimum and wide sizes, including long and RTL text")
    func render() async throws {
        let output = ProcessInfo.processInfo.environment["GITGATTO_HELP_UI_OUTPUT"].map { URL(fileURLWithPath: $0) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        let oldLanguage = AppPreferencesStore.load().language
        defer { if output != nil { L10n.activate(oldLanguage) } }
        let topics: [HelpTopic] = output == nil ? [.recovery] : HelpTopic.allCases
        for topic in topics {
            if output != nil { L10n.activate(.simplifiedChinese) }
            try await capture(
                HelpArticleView(topic: topic).appGlassPanel().background(Color.white).environment(\.colorScheme, .light),
                size: NSSize(width: 570, height: 600),
                name: "article-\(topic.rawValue)-minimum-zh", output: output
            )
        }
        let suite = "GitGattoHelpTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let variants: [(AppLanguage, Int, Bool, HelpTopic)] = output == nil
            ? [(.german, 820, true, .projectCommands)]
            : [(.simplifiedChinese, 820, false, .recovery), (.english, 1200, false, .developerTools),
               (.german, 820, true, .projectCommands), (.arabic, 820, true, .monitoring)]
        for (language, width, dark, topic) in variants {
            if output != nil { L10n.activate(language) }
            defaults.set(topic.rawValue, forKey: "help.selectedTopic")
            let content = HelpCenterView()
                .defaultAppStorage(defaults)
                .environment(\.locale, L10n.locale)
                .environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
                .environment(\.colorScheme, dark ? .dark : .light)
            try await capture(content, size: NSSize(width: width, height: 700), name: "center-\(language.rawValue)-\(width)", output: output)
        }
    }

    @MainActor private func capture(_ content: some View, size: NSSize, name: String, output: URL?) async throws {
        let host = NSHostingView(rootView: content)
        host.wantsLayer = true
        let window = HelpGuideRenderWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        window.makeKeyAndOrderFront(nil)
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        #expect(abs(host.bounds.width - size.width) < 1)
        #expect(abs(host.bounds.height - size.height) < 1)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(data.count > 1000)
        if let output { try data.write(to: output.appendingPathComponent(name + ".png")) }
        let scrolls = scrollViews(in: host)
        #expect(!scrolls.isEmpty)
        for scroll in scrolls {
            guard let document = scroll.documentView else { continue }
            #expect(document.bounds.width <= scroll.contentView.bounds.width + 1)
            let bottom = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
            scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
            scroll.reflectScrolledClipView(scroll.contentView)
            #expect(abs(scroll.contentView.bounds.origin.y - bottom) < 1)
        }
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        if let output {
            CATransaction.flush()
            let bottom = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try #require(NSGraphicsContext(bitmapImageRep: bottom))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            try #require(host.layer).render(in: context.cgContext)
            try #require(bottom.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + "-bottom.png"))
        }
    }

    @MainActor private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
}

@MainActor private final class HelpGuideRenderWindow: NSWindow {
    // Snapshot dimensions must not shrink to the CI runner's virtual display.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
