import AppKit
import Observation
import SwiftUI
import Testing
@testable import GitGatto

@MainActor
@Suite("Lumen color settings", .serialized)
struct LumenColorTests {
    @Test("RGBA input preserves opacity and rejects malformed values")
    func rgbaValidation() throws {
        #expect(LumenRGBA(hex: " #aAbBcC ")?.hex == "#AABBCCFF")
        let value = try #require(LumenRGBA(hex: "#12345680"))
        #expect(abs(NSColor(value.color).alphaComponent - 128.0/255) < 0.001)
        #expect(LumenRGBA(value.color)?.hex == value.hex)
        for invalid in ["#123", "#GGGGGG", "#123456789", "##123456", "", "12345+"] {
            #expect(LumenRGBA(hex: invalid) == nil)
        }
    }

    @Test("Every appearance, preset and color role resolves; other themes ignore Lumen edits")
    func completeCoverage() throws {
        #expect(Set(LumenColorGroup.allCases.flatMap(\.roles)) == Set(LumenColorRole.allCases))
        for preset in LumenColorPreset.allCases {
            for appearance in LumenColorAppearance.allCases {
                var settings = LumenColorSettings()
                settings.preset = preset
                let original = settings.resolved(appearance.scheme)
                #expect(original.colors.count == LumenColorRole.allCases.count)
                for role in LumenColorRole.allCases {
                    settings.set("#123456AB", for: role, appearance: appearance)
                    #expect(LumenRGBA(settings.resolved(appearance.scheme)[role])?.hex == "#123456AB")
                }
                let customized = settings.resolved(appearance.scheme)
                let palette = AppPalette(appearance.scheme, theme: .lumen, lumenColors: customized)
                #expect(LumenRGBA(palette.background)?.hex == "#123456AB")
                #expect(LumenRGBA(palette.primary)?.hex == "#123456AB")
                #expect(LumenRGBA(palette.onPrimary)?.hex == "#123456AB")
                for theme in AppVisualTheme.allCases where theme != .lumen {
                    let untouched = AppPalette(appearance.scheme, theme: theme)
                    let withSettings = AppPalette(appearance.scheme, theme: theme, lumenColors: customized)
                    #expect(untouched.background == withSettings.background)
                    #expect(untouched.primary == withSettings.primary)
                    #expect(withSettings.lumenColors == nil)
                }
            }
        }
    }

    @Test("Switching presets and resetting one appearance preserve independent edits")
    func independentVariants() {
        var settings = LumenColorSettings()
        settings.set("#FF0000", for: .background, appearance: .light)
        settings.set("#123456", for: .ink, appearance: .dark)
        settings.preset = .coast
        #expect(settings.override(.background, appearance: .light) == nil)
        settings.set("#ABCDEF", for: .background, appearance: .light)
        settings.preset = .coral
        #expect(settings.override(.background, appearance: .light) == "#FF0000FF")
        settings.reset(.light)
        #expect(settings.override(.background, appearance: .light) == nil)
        #expect(settings.override(.ink, appearance: .dark) == "#123456FF")
        settings.preset = .coast
        #expect(settings.override(.background, appearance: .light) == "#ABCDEFFF")
        settings.set("invalid", for: .background, appearance: .light)
        #expect(settings.override(.background, appearance: .light) == "#ABCDEFFF")
    }

    @Test("Applying is observable and persistent without touching theme, accent or unrelated preferences")
    func persistenceAndObservation() throws {
        let suite = "GitGatto.LumenTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("folio", forKey: AppStyleDefaults.themeKey)
        defaults.set("green", forKey: AppStyleDefaults.accentKey)
        defaults.set("kept", forKey: "unrelated")
        let store = LumenColorStore(defaults: defaults)
        var draft = store.settings
        draft.preset = .forest
        draft.set("#123456", for: .background, appearance: .dark)
        #expect(defaults.data(forKey: LumenColorStore.storageKey) == nil)
        let changed = ObservationSignal()
        withObservationTracking {
            _ = store.resolved(.dark, accentChoice: .coral, customAccentHex: "#4F7DFF")
        } onChange: { changed.mark() }
        try store.apply(draft)
        #expect(changed.value)
        #expect(LumenColorStore(defaults: defaults).settings == draft)
        #expect(LumenRGBA(store.resolved(.dark, accentChoice: .coral, customAccentHex: "#4F7DFF")[.background])?.hex == "#123456FF")
        let noChange = ObservationSignal()
        withObservationTracking { _ = store.settings } onChange: { noChange.mark() }
        try store.apply(draft)
        #expect(!noChange.value)
        #expect(defaults.string(forKey: AppStyleDefaults.themeKey) == "folio")
        #expect(defaults.string(forKey: AppStyleDefaults.accentKey) == "green")
        #expect(defaults.string(forKey: "unrelated") == "kept")
        #expect(LumenColorSettings.decode(Data("invalid".utf8)) == LumenColorSettings())
    }

    @Test("Coral retains the existing palette and custom global accent until explicitly changed")
    func defaultCompatibility() throws {
        let light = LumenColorSettings().resolved(.light, accentChoice: .custom, customAccentHex: "#13579B")
        let dark = LumenColorSettings().resolved(.dark, accentChoice: .custom, customAccentHex: "#13579B")
        #expect(LumenRGBA(light[.background])?.hex == "#F6F2ECFF")
        #expect(LumenRGBA(dark[.background])?.hex == "#050505FF")
        #expect(LumenRGBA(light[.primary])?.hex == "#13579BFF")
        #expect(LumenRGBA(dark[.primary])?.hex == "#13579BFF")
        #expect(LumenRGBA(light.ambientStops[0][1])?.hex == "#F7706A24")
        #expect(LumenRGBA(dark.ambientStops[1][1])?.hex == "#7265FF17")
    }

    @Test("Changing light colors preserves geometry and reduced motion")
    func nativeColorUpdate() throws {
        let view = LumenAmbientLightsView(frame: NSRect(x: 0, y: 0, width: 960, height: 620))
        view.configure(colorScheme: .light, reduceMotion: true)
        view.layoutSubtreeIfNeeded()
        let layers = try #require(view.layer?.sublayers as? [CAGradientLayer])
        let bounds = layers.map(\.bounds)
        var settings = LumenColorSettings()
        settings.set("#0088FF80", for: .ambientLeading, appearance: .light)
        view.configure(colorScheme: .light, reduceMotion: true, colors: settings.resolved(.light))
        let colors = try #require(layers[0].colors as? [CGColor])
        #expect(abs(colors[0].alpha - 128.0/255) < 0.001)
        #expect(layers.map(\.bounds) == bounds)
        #expect(layers.allSatisfy { $0.animationKeys()?.isEmpty != false })
    }

    @Test("New presets keep readable body text and primary buttons", arguments: [ColorScheme.light, .dark])
    func presetContrast(_ scheme: ColorScheme) throws {
        func luminance(_ color: Color) throws -> Double {
            let rgb = try #require(NSColor(color).usingColorSpace(.sRGB))
            func linear(_ value: Double) -> Double { value <= 0.04045 ? value/12.92 : pow((value+0.055)/1.055, 2.4) }
            return 0.2126*linear(rgb.redComponent) + 0.7152*linear(rgb.greenComponent) + 0.0722*linear(rgb.blueComponent)
        }
        func contrast(_ a: Color, _ b: Color) throws -> Double {
            let x = try luminance(a), y = try luminance(b)
            return (max(x,y)+0.05)/(min(x,y)+0.05)
        }
        for preset in [LumenColorPreset.coast, .forest, .dusk] {
            var settings = LumenColorSettings()
            settings.preset = preset
            let colors = settings.resolved(scheme)
            for ink in [LumenColorRole.ink, .mutedInk, .subtleInk] {
                #expect(try contrast(colors[ink], colors[.background]) >= 4.5)
                #expect(try contrast(colors[ink], colors[.raisedSurface]) >= 4.5)
            }
            #expect(try contrast(colors[.primary], colors[.onPrimary]) >= 4.5)
        }
    }

    @Test("README updates selected colors without replacing the page", .timeLimit(.minutes(1)))
    func readmeColors() async throws {
        let url = try #require(URL(string: "https://example.com/repository/"))
        let document = GitHubReadmeDocument(path: "README.md", html: "<h1>Repository</h1><p>README</p>",
            linkBaseURL: url, linkRootURL: url, assetBaseURL: url, assetRootURL: url)
        var settings = LumenColorSettings()
        settings.set("#123456", for: .ink, appearance: .light)
        settings.set("#EEEEEE", for: .background, appearance: .light)
        let colors = settings.resolved(.light)
        let cache = GitHubReadmeRendererCache()
        let old = GitHubReadmeWebView.Content(document: document, colorScheme: .light)
        let lease = cache.acquire(for: old)
        lease.webView.loadedContent = old
        cache.release(lease)
        let themed = GitHubReadmeWebView.Content(document: document, colorScheme: .light, lumenColors: colors)
        #expect(cache.acquire(for: themed).webView === lease.webView)
        let view = GitHubReadmeView(document: document, colorScheme: .light, lumenColors: colors,
            rendererCache: cache, onScrollAwayFromTop: {}, onOpenLink: { _ in })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: view)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        func findWeb(_ view: NSView) -> GitHubReadmeWebView? {
            (view as? GitHubReadmeWebView) ?? view.subviews.lazy.compactMap { findWeb($0) }.first
        }
        let web = try #require(findWeb(host))
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        var ink: String?
        while ContinuousClock.now < deadline {
            ink = try? await web.evaluateJavaScript("getComputedStyle(document.body).color") as? String
            if ink == "rgb(18, 52, 86)" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(ink == "rgb(18, 52, 86)")
        #expect(try await web.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") as? String == "rgb(238, 238, 238)")
        _ = try await web.evaluateJavaScript("document.body.dataset.retained = 'yes'")
        settings.set("#654321", for: .ink, appearance: .light)
        host.rootView = GitHubReadmeView(document: document, colorScheme: .light, lumenColors: settings.resolved(.light),
            rendererCache: cache, onScrollAwayFromTop: {}, onOpenLink: { _ in })
        host.layoutSubtreeIfNeeded()
        #expect(findWeb(host) === web)
        let recolorDeadline = ContinuousClock.now.advanced(by: .seconds(15))
        while ContinuousClock.now < recolorDeadline {
            ink = try await web.evaluateJavaScript("getComputedStyle(document.body).color") as? String
            if ink == "rgb(101, 67, 33)" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(ink == "rgb(101, 67, 33)")
        let retained = try await web.evaluateJavaScript("document.body.dataset.retained") as? String
        #expect(retained == "yes")
    }

    @Test("Color settings render in narrow and wide, light and dark windows")
    func renderSettings() throws {
        let suite = "GitGatto.LumenUITests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LumenColorStore(defaults: defaults)
        let output = ProcessInfo.processInfo.environment["GITGATTO_LUMEN_UI_OUTPUT"].map { URL(fileURLWithPath: $0) }
        for scheme in [ColorScheme.light, .dark] {
            for width in [740.0, 1020.0] {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 1060), styleMask: [.titled], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                let host = NSHostingView(rootView: ScrollView {
                    LumenColorSettingsView(store: store, appearance: scheme).padding(20)
                }.environment(\.colorScheme, scheme))
                window.contentView = host
                window.orderFront(nil)
                host.layoutSubtreeIfNeeded()
                #expect(abs(host.bounds.width - width) < 0.01)
                if let output {
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try #require(bitmap.representation(using: .png, properties: [:]))
                        .write(to: output.appendingPathComponent("editor-\(Int(width))-\(scheme).png"))
                }
                window.orderOut(nil)
                window.contentView = nil
            }
        }
    }
}

private final class ObservationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var signaled = false
    func mark() { lock.lock(); defer { lock.unlock() }; signaled = true }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return signaled }
}
