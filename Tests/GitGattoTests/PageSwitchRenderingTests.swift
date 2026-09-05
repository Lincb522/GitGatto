import AppKit
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Page switch rendering", .serialized)
@MainActor
struct PageSwitchRenderingTests {
    @Test("Returning to the same README reuses its renderer")
    func returnsToReadme() throws {
        let baseURL = try #require(URL(string: "https://example.com/owner/repository/"))
        let document = GitHubReadmeDocument(
            path: "README.md", html: "<h1>Repository</h1><p>README content.</p>",
            linkBaseURL: baseURL, linkRootURL: baseURL,
            assetBaseURL: baseURL, assetRootURL: baseURL
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        let hosting = NSHostingView(rootView: ReadmeSwitchFixture(document: document, showsReadme: true))
        window.contentView = hosting
        defer { window.orderOut(nil); window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()
        let initial = try #require(findWebView(in: hosting))
        var renderers = [initial]
        var durations: [Double] = []
        for _ in 0..<8 {
            hosting.rootView = ReadmeSwitchFixture(document: document, showsReadme: false)
            hosting.layoutSubtreeIfNeeded()
            #expect(findWebView(in: hosting) == nil)
            let duration = ContinuousClock().measure {
                hosting.rootView = ReadmeSwitchFixture(document: document, showsReadme: true)
                hosting.layoutSubtreeIfNeeded()
                hosting.displayIfNeeded()
            }
            renderers.append(try #require(findWebView(in: hosting)))
            durations.append(Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
        }
        let count = Set(renderers.map(ObjectIdentifier.init)).count
        print("PAGE_SWITCH_MEASURE renderer_count=\(count) return_layout_seconds=\(durations)")
        #expect(count == 1)
    }

    private func findWebView(in view: NSView) -> GitHubReadmeWebView? {
        if let webView = view as? GitHubReadmeWebView { return webView }
        return view.subviews.lazy.compactMap { findWebView(in: $0) }.first
    }

    @Test("An outgoing animated card cannot replace the latest idle renderer")
    func overlappingCards() throws {
        let cache = GitHubReadmeRendererCache()
        let content = try content()
        let outgoing = cache.acquire(for: content)
        outgoing.webView.loadedContent = content
        let incoming = cache.acquire(for: content)
        #expect(incoming.webView !== outgoing.webView)
        incoming.webView.loadedContent = content
        cache.release(incoming)
        cache.release(outgoing)
        let resumed = cache.acquire(for: content)
        #expect(resumed.webView === incoming.webView)
        #expect(resumed.webView.configuration.defaultWebpagePreferences.allowsContentJavaScript == false)
        #expect(resumed.webView.configuration.websiteDataStore.isPersistent == false)
    }

    @Test("Changed content, repository URLs, and appearance do not reuse a stale page")
    func invalidatesStalePages() throws {
        let original = try content()
        for changed in [
            try content(html: "<p>Translated content</p>"),
            try content(base: "https://example.com/other/repository/"),
            try content(scheme: .dark)
        ] {
            let cache = GitHubReadmeRendererCache()
            let first = cache.acquire(for: original)
            first.webView.loadedContent = original
            cache.release(first)
            #expect(cache.acquire(for: changed).webView !== first.webView)
        }
    }

    @Test("Detached renderers clear callbacks and recover after WebKit termination")
    func rebindsCallbacks() throws {
        let cache = GitHubReadmeRendererCache()
        let content = try content()
        let lease = cache.acquire(for: content)
        lease.webView.loadedContent = content
        var reports = 0
        lease.webView.onScrollAwayFromTop = { reports += 1 }
        let view = GitHubReadmeView(
            document: content.document, colorScheme: content.colorScheme, rendererCache: cache,
            onScrollAwayFromTop: {}, onOpenLink: { _ in }
        )
        let coordinator = view.makeCoordinator()
        coordinator.lease = lease
        lease.webView.navigationDelegate = coordinator
        GitHubReadmeView.dismantleNSView(lease.webView, coordinator: coordinator)
        lease.webView.registerVerticalScroll(36)
        #expect(reports == 0)
        #expect(lease.webView.navigationDelegate === cache)
        #expect(coordinator.lease == nil)
        let resumed = cache.acquire(for: content)
        #expect(resumed.webView === lease.webView)
        coordinator.webViewWebContentProcessDidTerminate(resumed.webView)
        #expect(resumed.webView.loadedContent == nil)
        resumed.webView.loadedContent = content
        cache.release(resumed)
        cache.webViewWebContentProcessDidTerminate(resumed.webView)
        #expect(cache.acquire(for: content).webView !== resumed.webView)
    }

    @Test("README content and appearance survive page switches", .timeLimit(.minutes(1)))
    func renderedReadme() async throws {
        for (width, height, scheme) in [(960, 620, ColorScheme.light), (1416, 878, ColorScheme.dark)] {
            let document = try content(html: """
                <h1>Repository</h1><p>仓库说明 · Repository documentation</p>
                <pre><code>let message = "Hello"</code></pre>
                <a href="docs/guide.md">Guide</a>
                """).document
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false
            )
            let hosting = NSHostingView(rootView: ReadmeSwitchFixture(
                document: document, showsReadme: true, colorScheme: scheme
            ))
            window.contentView = hosting
            window.orderFront(nil)
            defer { window.orderOut(nil); window.contentView = nil }
            hosting.layoutSubtreeIfNeeded()
            let webView = try #require(findWebView(in: hosting))
            try await waitForPage(webView)
            let text = try await webView.evaluateJavaScript("document.body.innerText") as? String
            #expect(text?.contains("仓库说明") == true)
            let ink = try await webView.evaluateJavaScript("getComputedStyle(document.body).color") as? String
            #expect(ink == (scheme == .dark ? "rgb(240, 246, 252)" : "rgb(31, 35, 40)"))
            #expect(hosting.bounds.width > 0)
            #expect(webView.bounds.width == hosting.bounds.width)
            hosting.rootView = ReadmeSwitchFixture(document: document, showsReadme: false, colorScheme: scheme)
            hosting.layoutSubtreeIfNeeded()
            hosting.rootView = ReadmeSwitchFixture(document: document, showsReadme: true, colorScheme: scheme)
            hosting.layoutSubtreeIfNeeded()
            let returned = try #require(findWebView(in: hosting))
            #expect(returned === webView)
            #expect(webView.isLoading == false)
            // WebKit lays out its remote page asynchronously after reattachment.
            let image = try await renderedSnapshot(webView)
            let returnedText = try await webView.evaluateJavaScript("document.body.innerText") as? String
            #expect(returnedText == text)

            if let directory = ProcessInfo.processInfo.environment["GITGATTO_PAGE_SWITCH_SNAPSHOTS"] {
                let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                    .appendingPathComponent("readme-\(scheme == .dark ? "dark" : "light")-\(width)x\(height).png")
                try png.write(to: url)
            }

            let translated = document.replacingHTML(with: "<h1>翻译后的说明</h1>")
            hosting.rootView = ReadmeSwitchFixture(document: translated, showsReadme: true, colorScheme: scheme)
            hosting.layoutSubtreeIfNeeded()
            let updated = try #require(findWebView(in: hosting))
            try await waitForPage(updated)
            #expect(try await updated.evaluateJavaScript("document.body.innerText") as? String == "翻译后的说明")
        }
    }

    private func waitForPage(_ webView: GitHubReadmeWebView) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(20))
        while webView.isLoading || webView.estimatedProgress < 1 {
            try #require(clock.now < deadline, "README did not finish loading")
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func renderedSnapshot(_ webView: GitHubReadmeWebView) async throws -> NSImage {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(20))
        while clock.now < deadline {
            let image = try await webView.takeSnapshot(configuration: nil)
            let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            var colors = Set<UInt32>()
            for y in stride(from: 0, to: min(300, bitmap.pixelsHigh), by: 4) {
                for x in stride(from: 0, to: min(700, bitmap.pixelsWide), by: 4) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    colors.insert(
                        UInt32(color.redComponent * 255) << 16
                            | UInt32(color.greenComponent * 255) << 8
                            | UInt32(color.blueComponent * 255)
                    )
                    if colors.count > 12 { return image }
                }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw RenderFailure.blankPage
    }

    private enum RenderFailure: Error {
        case blankPage
    }

    private func content(
        html: String = "<p>README</p>",
        base: String = "https://example.com/owner/repository/",
        scheme: ColorScheme = .light
    ) throws -> GitHubReadmeWebView.Content {
        let url = try #require(URL(string: base))
        return .init(document: GitHubReadmeDocument(
            path: "README.md", html: html,
            linkBaseURL: url, linkRootURL: url, assetBaseURL: url, assetRootURL: url
        ), colorScheme: scheme)
    }
}

private struct ReadmeSwitchFixture: View {
    let document: GitHubReadmeDocument
    let showsReadme: Bool
    var colorScheme: ColorScheme = .light
    @StateObject private var rendererCache = GitHubReadmeRendererCache()

    var body: some View {
        if showsReadme {
            GitHubReadmeView(
                document: document, colorScheme: colorScheme,
                rendererCache: rendererCache,
                onScrollAwayFromTop: {}, onOpenLink: { _ in }
            )
        } else {
            Text("Working tree")
        }
    }
}
