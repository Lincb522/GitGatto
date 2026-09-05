import AppKit
import SwiftUI

struct AboutGitGattoView: View {
    @ObservedObject var navigation: AppNavigationModel
    @ObservedObject var updateManager: AppUpdateManager
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let palette = AppPalette(colorScheme)
        let theme = AppVisualTheme.resolved(themeRaw)
        let contentSize = aboutContentSize(for: theme)
        VStack(spacing: theme == .softGlass ? 10 : 0) {
            aboutHeader(theme: theme)

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    Text(L10n.text("about.legal"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    Button {
                        openWindow(id: "release-history")
                    } label: {
                        GattoLabel(L10n.text("release_history.title"), systemImage: "clock.arrow.circlepath")
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
            .modifier(AboutSectionChrome(theme: theme, role: .content))

            HStack(spacing: 10) {
                GattoLabel("ZIJIU522", systemImage: "person.crop.circle")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.mutedInk)

                Spacer()

                Button {
                    NSWorkspace.shared.open(AppLinks.website)
                } label: {
                    GattoLabel(L10n.text("about.website"), systemImage: "globe")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    NSWorkspace.shared.open(AppLinks.sourceRepository)
                } label: {
                    GattoLabel(L10n.text("about.source"), systemImage: "chevron.left.forwardslash.chevron.right")
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
            .modifier(AboutSectionChrome(theme: theme, role: .footer))
        }
        .padding(.horizontal, theme == .lumen ? 14 : AppThemeLayout.workspaceInset)
        .padding(.top, 28)
        .padding(.bottom, theme == .lumen ? 8 : 12)
        .frame(width: contentSize.width, height: contentSize.height)
        .background(theme == .lumen ? Color.clear : palette.surface)
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

    private func aboutHeader(theme: AppVisualTheme) -> some View {
        let palette = AppPalette(theme == .emerald ? .dark : colorScheme)
        return HStack(spacing: 15) {
                AppBrandIcon(size: 60)

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
            .environment(\.colorScheme, theme == .emerald ? .dark : colorScheme)
    }

    private func aboutContentSize(for theme: AppVisualTheme) -> NSSize {
        switch theme {
        case .softGlass:
            NSSize(width: 680, height: 410)
        case .lumen:
            NSSize(width: 680, height: 380)
        case .standard, .console, .emerald, .folio:
            NSSize(width: 680, height: 410)
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
    }
}

private struct AboutHeaderChrome: ViewModifier {
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if theme == .softGlass {
            content
        } else if theme == .lumen {
            content.overlay(alignment: .bottom) {
                Rectangle().fill(AppPalette(colorScheme).divider).frame(height: 1)
            }
        } else {
            content.background(AppPalette(colorScheme, theme: theme).sidebar)
        }
    }
}

private enum AboutSectionRole {
    case content
    case footer
}

private struct AboutSectionChrome: ViewModifier {
    let theme: AppVisualTheme
    let role: AboutSectionRole
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let palette = AppPalette(colorScheme, theme: theme)
        if theme == .lumen {
            content.overlay(alignment: .bottom) {
                if role == .content {
                    Rectangle().fill(palette.divider).frame(height: 1)
                }
            }
        } else if theme == .softGlass {
            content.appGlassPanel(cornerRadius: role == .content ? 16 : 10, elevated: false)
        } else if theme == .folio {
            content.folioSurface(role == .content ? .panel : .elevated, cornerRadius: 16)
        } else {
            content
                .background(palette.background)
                .overlay(alignment: .top) { Rectangle().fill(palette.divider).frame(height: 1) }
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
        let radius: CGFloat = AppStyleDefaults.theme == .lumen ? 12 : AppThemeLayout.controlCornerRadius
        Button(action: action) {
            HStack(spacing: 12) {
                Image(gattoSymbol: document.icon)
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
                Image(gattoSymbol: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.subtleInk)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(isHovering ? palette.raisedSurface : palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
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
    var targetSize = NSSize(width: 680, height: 410)

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
