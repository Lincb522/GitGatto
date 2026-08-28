import AppKit
import Testing
import WebKit
@testable import GitGatto

@Suite("GitHub README scrolling")
@MainActor
struct GitHubReadmeScrollTests {
    @Test("Collapses the repository summary after the README leaves the top")
    func reportsScrollAwayFromTop() {
        var reports = 0
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = GitHubReadmeWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        webView.onScrollAwayFromTop = { reports += 1 }

        webView.registerVerticalScroll(12)
        webView.registerVerticalScroll(-12)
        webView.registerVerticalScroll(12)
        #expect(reports == 1)

        webView.registerVerticalScroll(80)
        #expect(reports == 1)

        webView.resetScrollDetection()
        webView.registerVerticalScroll(36)
        #expect(reports == 2)
    }
}
