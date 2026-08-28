import AppKit
import SwiftUI

struct AboutGitGattoView: View {
    @ObservedObject var navigation: AppNavigationModel
    @ObservedObject var updateManager: AppUpdateManager
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let palette = AppPalette(colorScheme)
        let theme = AppVisualTheme.resolved(themeRaw)
        let contentSize = aboutContentSize(for: theme)
        VStack(spacing: theme == .softGlass ? 10 : 0) {
            HStack(spacing: 15) {
                AppBrandIcon(size: 60)
                    .padding(
                        .leading,
                        AppThemeLayout.titlebarBrandLeading
                            - AppThemeLayout.workspaceInset
                            - 16
                    )

                VStack(alignment: .leading, spacing: 5) {
                    AppBrandWordmark(width: 140)
                    Text(L10n.text("about.product"))
                        .font(.system(size: 12))
                        .foregroundStyle(palette.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 330, alignment: .leading)
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 7) {
                    HStack(spacing: 7) {
                        AboutMetric(titleKey: "about.version", value: updateManager.currentVersion)
                        AboutMetric(titleKey: "about.build", value: updateManager.currentBuild)
                    }
                    UpdateActionButton(
                        state: updateManager.state,
                        isEnabled: !updateManager.isConfigured || updateManager.canCheckForUpdates
                    ) {
                        updateManager.checkForUpdates()
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: theme == .softGlass ? 92 : 104)
            .modifier(AboutHeaderChrome(theme: theme))

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    Text(L10n.text("about.legal"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    Button {
                        openWindow(id: "release-history")
                    } label: {
                        Label(L10n.text("release_history.title"), systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 8
                ) {
                    ForEach(LegalDocumentKind.allCases) { document in
                        AboutLegalButton(document: document) {
                            navigation.selectedLegalDocument = document
                            openWindow(id: "legal-documents")
                        }
                    }
                }
            }
            .padding(14)
            .background(palette.surface.opacity(0.18))
            .appGlassPanel()

            HStack(spacing: 10) {
                Label("ZIJIU522", systemImage: "person.crop.circle")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.mutedInk)

                Spacer()

                Button {
                    NSWorkspace.shared.open(AppLinks.website)
                } label: {
                    Label(L10n.text("about.website"), systemImage: "globe")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    NSWorkspace.shared.open(AppLinks.sourceRepository)
                } label: {
                    Label(L10n.text("about.source"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button(L10n.text("action.close")) {
                    dismissWindow(id: "about")
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(palette.sidebar.opacity(0.14))
            .appGlassPanel(cornerRadius: 16, elevated: false)
        }
        .padding(AppThemeLayout.workspaceInset)
        .frame(width: contentSize.width, height: contentSize.height)
        .background(palette.surface)
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.layoutDirection, .leftToRight)
        .background(AboutWindowSizeController(contentSize: contentSize))
#if DEBUG
        .background(
            DebugSnapshotCapture(
                isReady: ProcessInfo.processInfo.environment["GITGATTO_ABOUT_PREVIEW"] == "1"
            )
        )
#endif
    }

    private func aboutContentSize(for theme: AppVisualTheme) -> NSSize {
        switch theme {
        case .softGlass:
            NSSize(width: 660, height: 361)
        case .standard, .console:
            NSSize(width: 660, height: 341)
        }
    }
}

private struct AboutMetric: View {
    let titleKey: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.text(titleKey))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.ink)
        }
        .padding(.horizontal, 11)
        .frame(minWidth: 68, minHeight: 44, alignment: .leading)
        .background(palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct AboutHeaderChrome: ViewModifier {
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if theme == .softGlass {
            content
        } else {
            content.background(AppPalette(colorScheme, theme: theme).sidebar)
        }
    }
}

private struct AboutLegalButton: View {
    let document: LegalDocumentKind
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: document.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .frame(width: 30, height: 30)
                    .background(palette.primarySoft)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text(document.titleKey))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text(L10n.text(document.summaryKey))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.mutedInk)
                        .lineLimit(1)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.subtleInk)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(isHovering ? palette.raisedSurface : palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.divider, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct AboutWindowSizeController: NSViewRepresentable {
    let contentSize: NSSize

    func makeNSView(context: Context) -> NSView {
        AboutWindowSizingView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let sizingView = nsView as? AboutWindowSizingView else { return }
        sizingView.targetSize = contentSize
        sizingView.enforceWindowSize()
    }
}

private final class AboutWindowSizingView: NSView {
    var targetSize = NSSize(width: 660, height: 341)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        enforceWindowSize()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            self?.enforceWindowSize()
        }
    }

    func enforceWindowSize() {
        guard let window else { return }
        window.contentMinSize = targetSize
        window.contentMaxSize = targetSize
        window.setContentSize(targetSize)
    }
}
