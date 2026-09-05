import SwiftUI
import WebKit

final class GitHubReadmeWebView: WKWebView {
    struct Content: Equatable {
        let document: GitHubReadmeDocument
        let colorScheme: ColorScheme
    }

    var loadedContent: Content?
    var onScrollAwayFromTop: () -> Void = {}

    private var accumulatedScrollDistance: CGFloat = 0
    private var didReportScrollAwayFromTop = false

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        registerVerticalScroll(event.scrollingDeltaY)
    }

    func registerVerticalScroll(_ delta: CGFloat) {
        guard !didReportScrollAwayFromTop, delta != 0 else { return }
        accumulatedScrollDistance += abs(delta)
        guard accumulatedScrollDistance >= 36 else { return }
        didReportScrollAwayFromTop = true
        onScrollAwayFromTop()
    }

    func resetScrollDetection() {
        accumulatedScrollDistance = 0
        didReportScrollAwayFromTop = false
    }
}

@MainActor
final class GitHubReadmeRendererCache: NSObject, ObservableObject, WKNavigationDelegate {
    struct Lease {
        let id: UUID
        let webView: GitHubReadmeWebView
    }

    private var idleRenderer: GitHubReadmeWebView?
    private var currentLeaseID: UUID?

    func acquire(for content: GitHubReadmeWebView.Content) -> Lease {
        let webView: GitHubReadmeWebView
        if let idleRenderer, idleRenderer.loadedContent == content {
            webView = idleRenderer
        } else {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            webView = GitHubReadmeWebView(frame: .zero, configuration: configuration)
            webView.setValue(false, forKey: "drawsBackground")
        }
        idleRenderer = nil
        let lease = Lease(id: UUID(), webView: webView)
        currentLeaseID = lease.id
        return lease
    }

    func release(_ lease: Lease) {
        // An outgoing card can finish its transition after the new card mounts.
        guard lease.id == currentLeaseID else { return }
        lease.webView.pauseAllMediaPlayback(completionHandler: nil)
        lease.webView.navigationDelegate = self
        idleRenderer = lease.webView
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        (webView as? GitHubReadmeWebView)?.loadedContent = nil
    }
}

struct GitHubReadmeView: NSViewRepresentable {
    let document: GitHubReadmeDocument
    let colorScheme: ColorScheme
    let rendererCache: GitHubReadmeRendererCache
    let onScrollAwayFromTop: () -> Void
    let onOpenLink: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            rendererCache: rendererCache,
            onOpenLink: onOpenLink,
            linkBaseURL: document.linkBaseURL
        )
    }

    func makeNSView(context: Context) -> GitHubReadmeWebView {
        let lease = rendererCache.acquire(for: .init(document: document, colorScheme: colorScheme))
        context.coordinator.lease = lease
        let webView = lease.webView
        webView.onScrollAwayFromTop = onScrollAwayFromTop
        webView.resetScrollDetection()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: GitHubReadmeWebView, context: Context) {
        webView.onScrollAwayFromTop = onScrollAwayFromTop
        context.coordinator.onOpenLink = onOpenLink
        context.coordinator.linkBaseURL = document.linkBaseURL
        let content = GitHubReadmeWebView.Content(document: document, colorScheme: colorScheme)
        guard webView.loadedContent != content else { return }
        webView.loadedContent = content
        webView.resetScrollDetection()
        webView.loadHTMLString(pageHTML, baseURL: document.linkBaseURL)
    }

    static func dismantleNSView(_ webView: GitHubReadmeWebView, coordinator: Coordinator) {
        webView.onScrollAwayFromTop = {}
        webView.navigationDelegate = nil
        if let lease = coordinator.lease {
            coordinator.rendererCache.release(lease)
            coordinator.lease = nil
        }
    }

    private var pageHTML: String {
        let dark = colorScheme == .dark
        let canvas = dark ? "#0d1117" : "#ffffff"
        let ink = dark ? "#f0f6fc" : "#1f2328"
        let muted = dark ? "#8b949e" : "#656d76"
        let border = dark ? "#30363d" : "#d0d7de"
        let surface = dark ? "#161b22" : "#f6f8fa"
        let link = dark ? "#58a6ff" : "#0969da"
        let accent = dark ? "#3fb950" : "#1f883d"
        let danger = dark ? "#f85149" : "#cf222e"
        let attention = dark ? "#d29922" : "#9a6700"

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root { color-scheme: \(dark ? "dark" : "light"); }
            * { box-sizing: border-box; }
            html { background: \(canvas); }
            body {
              margin: 0;
              color: \(ink);
              background: \(canvas);
              font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              overflow-wrap: break-word;
              -webkit-text-size-adjust: 100%;
            }
            .markdown-body { width: 100%; max-width: 1012px; margin: 0 auto; padding: 32px 40px 64px; }
            .markdown-body::before, .markdown-body::after { display: table; content: ""; }
            .markdown-body::after { clear: both; }
            .markdown-body > :first-child { margin-top: 0 !important; }
            .markdown-body > :last-child { margin-bottom: 0 !important; }
            h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 24px 0 16px; font-weight: 600; }
            h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid \(border); }
            h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid \(border); }
            h3 { font-size: 1.25em; }
            h4 { font-size: 1em; }
            h5 { font-size: .875em; }
            h6 { font-size: .85em; color: \(muted); }
            p, blockquote, ul, ol, dl, table, pre, details { margin-top: 0; margin-bottom: 16px; }
            ul, ol { padding-left: 2em; }
            li + li { margin-top: .25em; }
            li > p { margin-top: 16px; }
            a { color: \(link); text-decoration: none; }
            a:hover { text-decoration: underline; }
            a:not([href]) { color: inherit; text-decoration: none; }
            .markdown-heading { position: relative; }
            .markdown-heading .anchor { float: left; margin-left: -20px; padding-right: 4px; line-height: 1; }
            .markdown-heading .anchor .octicon { visibility: hidden; vertical-align: middle; }
            .markdown-heading:hover .anchor .octicon { visibility: visible; }
            img, picture, video, svg { max-width: 100%; }
            img, video { height: auto; }
            img { box-sizing: content-box; background-color: \(canvas); }
            img[align="right"] { padding-left: 20px; }
            img[align="left"] { padding-right: 20px; }
            .emoji { max-width: none; vertical-align: text-top; background: transparent; }
            code {
              font: 85%/1.45 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
              background: \(dark ? "rgba(110,118,129,.4)" : "rgba(175,184,193,.2)");
              padding: .2em .4em;
              border-radius: 6px;
            }
            pre { overflow: auto; padding: 16px; background: \(surface); border-radius: 6px; line-height: 1.45; }
            pre code { padding: 0; background: transparent; }
            blockquote { color: \(muted); padding: 0 1em; border-left: .25em solid \(border); }
            blockquote > :first-child { margin-top: 0; }
            blockquote > :last-child { margin-bottom: 0; }
            table { border-collapse: collapse; width: max-content; max-width: 100%; overflow: auto; display: block; }
            tr { background: \(canvas); border-top: 1px solid \(border); }
            tr:nth-child(2n) { background: \(surface); }
            th, td { border: 1px solid \(border); padding: 6px 13px; }
            th { font-weight: 600; }
            hr { height: .25em; border: 0; background: \(border); margin: 24px 0; }
            kbd { display: inline-block; padding: 3px 5px; font: 11px ui-monospace, SFMono-Regular, Menlo, monospace; line-height: 10px; color: \(ink); vertical-align: middle; background: \(surface); border: 1px solid \(border); border-radius: 6px; box-shadow: inset 0 -1px 0 \(border); }
            details summary { cursor: pointer; }
            details:not([open]) > *:not(summary) { display: none !important; }
            .task-list-item { list-style-type: none; }
            .task-list-item input[type="checkbox"] { margin: 0 .2em .25em -1.6em; vertical-align: middle; }
            .markdown-alert { padding: .5rem 1em; margin-bottom: 16px; color: inherit; border-left: .25em solid \(border); }
            .markdown-alert > :first-child { margin-top: 0; }
            .markdown-alert > :last-child { margin-bottom: 0; }
            .markdown-alert-title { display: flex; align-items: center; gap: 8px; font-weight: 500; }
            .markdown-alert-note, .markdown-alert-tip { border-left-color: \(accent); }
            .markdown-alert-warning, .markdown-alert-important { border-left-color: \(attention); }
            .markdown-alert-caution { border-left-color: \(danger); }
            .footnotes { color: \(muted); font-size: 12px; border-top: 1px solid \(border); }
            @media (max-width: 700px) { .markdown-body { padding: 24px 22px 48px; } }
          </style>
        </head>
        <body><article class="markdown-body">\(normalizedHTML)</article></body>
        </html>
        """
    }

    private var normalizedHTML: String {
        GitHubReadmeHTML.normalized(
            document.html,
            linkBaseURL: document.linkBaseURL,
            linkRootURL: document.linkRootURL,
            assetBaseURL: document.assetBaseURL,
            assetRootURL: document.assetRootURL
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let rendererCache: GitHubReadmeRendererCache
        var lease: GitHubReadmeRendererCache.Lease?
        var onOpenLink: (URL) -> Void
        var linkBaseURL: URL

        init(
            rendererCache: GitHubReadmeRendererCache,
            onOpenLink: @escaping (URL) -> Void,
            linkBaseURL: URL
        ) {
            self.rendererCache = rendererCache
            self.onOpenLink = onOpenLink
            self.linkBaseURL = linkBaseURL
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if Self.isSamePageReference(url, baseURL: linkBaseURL) {
                decisionHandler(.allow)
                return
            }

            if url.scheme == "https" || url.scheme == "http" {
                onOpenLink(url)
            }
            decisionHandler(.cancel)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            (webView as? GitHubReadmeWebView)?.loadedContent = nil
        }

        private static func isSamePageReference(_ url: URL, baseURL: URL) -> Bool {
            guard url.fragment != nil else { return false }
            if url.scheme == nil || url.scheme == "about" { return true }
            var destination = URLComponents(url: url, resolvingAgainstBaseURL: true)
            var base = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
            destination?.fragment = nil
            base?.fragment = nil
            return destination?.url?.absoluteURL == base?.url?.absoluteURL
        }
    }
}
