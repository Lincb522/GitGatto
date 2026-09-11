import AppKit
import SwiftUI
import Testing
import WebKit
@testable import GitGatto

@Suite("Appearance rendering regressions", .serialized)
@MainActor
struct AppearanceRenderingTests {
    @Test("Appearance and accent changes preserve page state and its loading task")
    func preservesThemeRootState() async throws {
        let name = "GitGatto.ThemeIdentity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(AppVisualTheme.standard.rawValue, forKey: AppStyleDefaults.themeKey)
        defaults.set(AppAppearance.light.rawValue, forKey: "appearance")
        let probe = ThemeIdentityProbe()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: AppThemeRoot { ThemeIdentityFixture(probe: probe) }.defaultAppStorage(defaults))
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()
        try await eventually { probe.loads == 1 }
        let identity = try #require(probe.identity)
        for scheme in [AppAppearance.dark, .light, .dark] {
            defaults.set(scheme.rawValue, forKey: "appearance")
            hosting.layoutSubtreeIfNeeded()
            try await eventually { probe.scheme == scheme.colorScheme }
            #expect(probe.identity == identity)
            #expect(probe.loads == 1)
        }
        for theme in AppVisualTheme.allCases {
            defaults.set(theme.rawValue, forKey: AppStyleDefaults.themeKey)
            defaults.set(AppAccentChoice.coral.rawValue, forKey: AppStyleDefaults.accentKey)
            hosting.layoutSubtreeIfNeeded()
            // Rendering flushes invalidation; the following appearance change gives a
            // deterministic observation boundary without arbitrary wait durations.
            defaults.set(AppAppearance.light.rawValue, forKey: "appearance")
            try await eventually { probe.scheme == .light }
            #expect(probe.identity == identity)
            #expect(probe.loads == 1)
            defaults.set(AppAppearance.dark.rawValue, forKey: "appearance")
            try await eventually { probe.scheme == .dark }
        }
    }

    @Test("README switches CSS, picture sources and fragment images without replacing the document", .timeLimit(.minutes(1)))
    func switchesReadmeInPlace() async throws {
        for width in [480, 1000] {
            let base = try #require(URL(string: "https://example.com/repository/"))
            let dot = "data:image/svg+xml;base64," + Data("<svg xmlns='http://www.w3.org/2000/svg' width='30' height='30'><circle cx='15' cy='15' r='12' fill='red'/></svg>".utf8).base64EncodedString()
            let darkDot = dot + "#dark"
            let document = GitHubReadmeDocument(path: "README.md", html: """
                <h1>说明 · README</h1>
                <picture><source media="(prefers-color-scheme: dark)" srcset="\(darkDot)"><img id="picture" src="\(dot)"></picture>
                <a id="light" href="#gh-light-mode-only"><img src="\(dot)"></a>
                <img id="dark" src="\(dot)#gh-dark-mode-only">
                <details open id="expanded"><summary>Details</summary>Keep this open</details>
                <script>document.body.dataset.untrusted = 'executed';</script>
                <p>\(String(repeating: "内容 content<br>", count: 150))</p>
                """, linkBaseURL: base, linkRootURL: base, assetBaseURL: base, assetRootURL: base)
            let cache = GitHubReadmeRendererCache()
            func view(_ scheme: ColorScheme) -> GitHubReadmeView {
                GitHubReadmeView(document: document, colorScheme: scheme, rendererCache: cache,
                                 onScrollAwayFromTop: {}, onOpenLink: { _ in })
            }
            let content = GitHubReadmeWebView.Content(document: document, colorScheme: .light)
            let lease = cache.acquire(for: content)
            let web = lease.webView
            let coordinator = view(.light).makeCoordinator()
            web.navigationDelegate = coordinator
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
                                  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentView = web
            window.orderFront(nil)
            defer { window.orderOut(nil); window.contentView = nil }
            web.display(content, pageHTML: view(.light).pageHTML, style: view(.light).pageStyle)
            try await eventually { !web.isLoading && web.estimatedProgress == 1 }
            _ = try await web.evaluateJavaScript("document.body.dataset.identity = 'retained'; window.scrollTo(0, 350)")
            for scheme in [ColorScheme.dark, .light, .dark] {
                let v = view(scheme)
                web.display(.init(document: document, colorScheme: scheme), pageHTML: v.pageHTML, style: v.pageStyle)
                let dark = scheme == .dark
                try await eventually {
                    let value = try await web.evaluateJavaScript("getComputedStyle(document.body).color") as? String
                    let media = try await web.evaluateJavaScript("matchMedia('(prefers-color-scheme: dark)').matches") as? Bool
                    return value == (dark ? "rgb(240, 246, 252)" : "rgb(31, 35, 40)") && media == dark
                }
                let state = try await web.evaluateJavaScript("({identity: document.body.dataset.identity, scroll: scrollY, light: getComputedStyle(document.getElementById('light')).display, dark: getComputedStyle(document.getElementById('dark')).display, open: document.getElementById('expanded').open, source: document.getElementById('picture').currentSrc, unsafe: document.body.dataset.untrusted || '', overflow: document.documentElement.scrollWidth > innerWidth})") as? [String: Any]
                #expect(state?["identity"] as? String == "retained")
                #expect((state?["scroll"] as? Double ?? 0) >= 340)
                #expect(state?["open"] as? Bool == true)
                #expect(state?["unsafe"] as? String == "")
                #expect(state?["overflow"] as? Bool == false)
                #expect((state?["source"] as? String)?.hasSuffix("#dark") == dark)
                #expect((state?["light"] as? String == "none") == dark)
                #expect((state?["dark"] as? String == "none") == !dark)
                if let directory = ProcessInfo.processInfo.environment["GITGATTO_APPEARANCE_OUTPUT"] {
                    _ = try await web.evaluateJavaScript("window.scrollTo(0, 0)")
                    let snapshot = try await web.takeSnapshot(configuration: nil)
                    let bitmap = try #require(snapshot.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
                    try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("readme-\(width)-\(scheme).png"))
                    _ = try await web.evaluateJavaScript("window.scrollTo(0, 350)")
                }
            }
        }
    }

    @Test("Unrelated updates and color changes do not regenerate document HTML")
    func avoidsRegeneratingHTML() throws {
        let url = try #require(URL(string: "https://example.com/"))
        let document = GitHubReadmeDocument(path: "README.md", html: "<p>Document</p>",
            linkBaseURL: url, linkRootURL: url, assetBaseURL: url, assetRootURL: url)
        let cache = GitHubReadmeRendererCache()
        let light = GitHubReadmeWebView.Content(document: document, colorScheme: .light)
        let web = cache.acquire(for: light).webView
        var documents = 0
        var styles = 0
        func html() -> String { documents += 1; return "<p>Document</p>" }
        func css() -> String { styles += 1; return "body { color: black; }" }
        web.display(light, pageHTML: html(), style: css())
        web.display(light, pageHTML: html(), style: css())
        web.display(.init(document: document, colorScheme: .dark), pageHTML: html(), style: css())
        #expect(documents == 1)
        #expect(styles == 2)
    }

    @Test("Relative srcsets and mode fragments survive normalization and local embedding")
    func normalizesPictureAssets() throws {
        let base = try #require(URL(string: "https://raw.githubusercontent.com/example/app/main/docs/"))
        let root = try #require(URL(string: "https://raw.githubusercontent.com/example/app/main/"))
        let html = """
        <picture><source srcset="../dark.svg 1x, /dark@2.svg 2x" media="(prefers-color-scheme: dark)"><img src="light.svg#gh-light-mode-only" data-src="untouched.png"></picture>
        """
        let result = GitHubReadmeHTML.normalized(html, linkBaseURL: base, linkRootURL: root, assetBaseURL: base, assetRootURL: root)
        #expect(result.contains("main/dark.svg 1x, https://raw.githubusercontent.com/example/app/main/dark@2.svg 2x"))
        #expect(result.contains("data-src=\"untouched.png\""))
        #expect(GitHubReadmeHTML.relativeAssetReferences(in: html).count == 3)
        let embedded = GitHubReadmeHTML.replacingAssetReferences(in: html, replacements: ["light.svg#gh-light-mode-only": "data:image/svg+xml;base64,AAAA", "../dark.svg": "data:image/svg+xml;base64,BBBB"])
        #expect(embedded.contains("data:image/svg+xml;base64,AAAA#gh-light-mode-only"))
        #expect(embedded.contains("data:image/svg+xml;base64,BBBB 1x"))
        let again = GitHubReadmeHTML.normalized(embedded, linkBaseURL: base, linkRootURL: root, assetBaseURL: base, assetRootURL: root)
        #expect(again.contains("data:image/svg+xml;base64,BBBB 1x"))
    }

    @Test("Issue HTML images are separate attachments without dropping surrounding prose")
    func parsesIssueAttachments() throws {
        let source = """
        功能很完善，图标有些小。
        <img width="872" height="59" alt="Image" src="https://github.com/user-attachments/assets/5c9ededf-cd90-4fcb-8b40-e78cd72b6b83" />
        这是后续说明。
        ![界面](https://example.com/screen.png)
        """
        let blocks = ReleaseNotesMarkdownBlock.parse(source)
        let images = blocks.compactMap { block -> ReleaseNotesMarkdownBlock.Attachment? in
            if case .image(let attachment) = block.kind { return attachment }; return nil
        }
        #expect(images.count == 2)
        #expect(images.first?.width == 872)
        #expect(images.last?.alt == "界面")
        #expect(blocks.contains { $0.text.contains("功能很完善") })
        #expect(blocks.contains { $0.text.contains("这是后续说明") })
        #expect(!blocks.contains { $0.text.contains("<img") })
    }

    @Test("Code examples and unsafe image sources remain text; multiline and unquoted images render")
    func handlesImageBoundaries() {
        let input = """
        ```html
        <img src="https://example.com/example.png">
        ```
        `<img src="https://example.com/inline.png">`
        <img src="file:///etc/passwd"><img src="javascript:alert(1)">
        <img\n alt='A &amp; B'\n src=https://example.com/real.png width='-5'>
        """
        let blocks = ReleaseNotesMarkdownBlock.parse(input)
        let images = blocks.compactMap { block -> ReleaseNotesMarkdownBlock.Attachment? in
            if case .image(let value) = block.kind { return value }; return nil
        }
        #expect(images.count == 1)
        #expect(images.first?.url.absoluteString == "https://example.com/real.png")
        #expect(images.first?.alt == "A & B")
        #expect(images.first?.width == nil)
        #expect(blocks.contains { $0.kind == .code && $0.text.contains("example.png") })
    }

    private func eventually(_ predicate: () async throws -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(15))
        while try await !predicate() {
            try #require(clock.now < deadline, "Appearance did not settle")
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

@MainActor
private final class ThemeIdentityProbe {
    var identity: UUID?
    var loads = 0
    var scheme: ColorScheme?
}

@MainActor
private final class ThemeState: ObservableObject {
    let identity = UUID()
}

private struct ThemeIdentityFixture: View {
    let probe: ThemeIdentityProbe
    @StateObject private var state = ThemeState()
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text("Theme state")
            .task { probe.identity = state.identity; probe.loads += 1 }
            .onChange(of: scheme, initial: true) { _, value in probe.scheme = value }
    }
}
