import AppKit
import SwiftUI

struct AboutGitGattoView: View {
    @ObservedObject var navigation: AppNavigationModel
    @ObservedObject var updateManager: AppUpdateManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: AppThemeLayout.panelSpacing) {
            HStack(spacing: 18) {
                AppBrandIcon(size: 72)
                    .padding(.leading, 46)

                VStack(alignment: .leading, spacing: 6) {
                    AppBrandWordmark(width: 148)
                    Text(L10n.text("about.product"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 360, alignment: .leading)
                }

                Spacer(minLength: 14)

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        AboutMetric(titleKey: "about.version", value: updateManager.currentVersion)
                        AboutMetric(titleKey: "about.build", value: updateManager.currentBuild)
                    }
                    Button {
                        openWindow(id: "updates")
                    } label: {
                        Label(L10n.text("update.check"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 132)
            .background(palette.sidebar.opacity(0.18))
            .appGlassPanel()

            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("about.legal"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(palette.ink)

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 10
                ) {
                    ForEach(LegalDocumentKind.allCases) { document in
                        AboutLegalButton(document: document) {
                            navigation.selectedLegalDocument = document
                            openWindow(id: "legal-documents")
                        }
                    }
                }
            }
            .padding(20)
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
            .padding(.horizontal, 18)
            .frame(height: 62)
            .background(palette.sidebar.opacity(0.14))
            .appGlassPanel(cornerRadius: 16, elevated: false)
        }
        .padding(AppThemeLayout.workspaceInset)
        .frame(width: 680, height: 520)
        .background(Color.clear)
        .ignoresSafeArea(.container, edges: .top)
#if DEBUG
        .background(
            DebugSnapshotCapture(
                isReady: ProcessInfo.processInfo.environment["GITGATTO_ABOUT_PREVIEW"] == "1"
            )
        )
#endif
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
        .frame(minWidth: 72, minHeight: 48, alignment: .leading)
        .background(palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    .frame(width: 34, height: 34)
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
            .frame(height: 62)
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
