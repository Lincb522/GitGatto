import SwiftUI
import WebKit

struct InAppBrowserPage: Identifiable {
    let id = UUID()
    let url: URL
    let persistent: Bool

    init(url: URL, persistent: Bool = false) {
        self.url = url
        self.persistent = persistent
    }
}

@MainActor
struct InAppBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let url: URL
    private let persistent: Bool

    init(url: URL, persistent: Bool = false) {
        self.url = url
        self.persistent = persistent
    }

    var body: some View {
        EmbeddedBrowserView(url: url, persistent: persistent) {
            dismiss()
        }
    }
}

@MainActor
private struct EmbeddedBrowserView: View {
    @StateObject private var browser: InAppBrowserModel
    @Environment(\.colorScheme) private var colorScheme
    private let closeAction: (() -> Void)?

    init(url: URL, persistent: Bool, closeAction: (() -> Void)? = nil) {
        _browser = StateObject(
            wrappedValue: InAppBrowserModel(url: url, persistent: persistent)
        )
        self.closeAction = closeAction
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { browser.goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!browser.canGoBack)
                .help(L10n.text("github.browser.back"))

                Button { browser.goForward() } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!browser.canGoForward)
                .help(L10n.text("github.browser.forward"))

                Button { browser.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L10n.text("action.refresh"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(browser.title ?? browser.host)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(browser.displayURL)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.leading, 5)

                Spacer(minLength: 12)

                if browser.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                if let closeAction {
                    Button(L10n.text("action.close"), action: closeAction)
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(palette.surface)

            Rectangle().fill(palette.divider).frame(height: 1)

            ZStack(alignment: .top) {
                InAppWebView(webView: browser.webView)
                if let error = browser.error {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(L10n.format("github.browser.error", error))
                            .textSelection(.enabled)
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.danger)
                    .padding(10)
                    .background(palette.dangerSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(12)
                }
            }
        }
        .background(palette.background)
        .onAppear { browser.loadIfNeeded() }
    }
}

@MainActor
private final class InAppBrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published private(set) var title: String?
    @Published private(set) var displayURL: String
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    let webView: WKWebView
    let host: String
    private let initialURL: URL

    init(url: URL, persistent: Bool) {
        initialURL = url
        host = url.host ?? url.absoluteString
        displayURL = url.absoluteString
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = persistent ? .default() : .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func loadIfNeeded() {
        guard webView.url == nil else { return }
        webView.load(URLRequest(url: initialURL))
    }

    func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    func goForward() {
        if webView.canGoForward { webView.goForward() }
    }

    func reload() {
        webView.reload()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        isLoading = true
        error = nil
        updateState(webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        isLoading = false
        updateState(webView)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        isLoading = false
        self.error = error.localizedDescription
        updateState(webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        isLoading = false
        self.error = error.localizedDescription
        updateState(webView)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    private func updateState(_ webView: WKWebView) {
        title = webView.title
        displayURL = webView.url?.absoluteString ?? initialURL.absoluteString
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

private struct InAppWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
