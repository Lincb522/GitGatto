import SwiftUI

struct ReleaseHistoryView: View {
    @ObservedObject var manager: AppUpdateManager
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedReleaseID: String?
    @State private var browserPage: InAppBrowserPage?

    private var theme: AppVisualTheme {
        AppVisualTheme.resolved(themeRaw)
    }

    private var selectedRelease: AppReleaseNote? {
        manager.releaseNotes.first { $0.id == selectedReleaseID }
            ?? manager.releaseNotes.first
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: theme == .softGlass ? AppThemeLayout.panelSpacing : 0) {
            header(palette)
                .themedReleasePanel(theme: theme, cornerRadius: 16, elevated: false)

            HStack(spacing: theme == .softGlass ? AppThemeLayout.panelSpacing : 0) {
                releaseList(palette)
                    .frame(width: 238)
                    .themedReleasePanel(theme: theme, cornerRadius: 16, elevated: true)

                if theme != .softGlass {
                    Rectangle().fill(palette.divider).frame(width: 1)
                }

                releaseDetail(palette)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .themedReleasePanel(theme: theme, cornerRadius: 16, elevated: true)
            }
        }
        .padding(theme == .softGlass ? AppThemeLayout.workspaceInset : 0)
        .frame(minWidth: 800, minHeight: 570)
        .background(theme == .softGlass ? Color.clear : palette.background)
        .ignoresSafeArea(.container, edges: .top)
        .task {
            selectAvailableRelease()
            await manager.refreshReleaseNotes()
            selectAvailableRelease()
        }
        .onChange(of: manager.releaseNotes) { _, _ in
            selectAvailableRelease()
        }
        .sheet(item: $browserPage) { page in
            InAppBrowserSheet(url: page.url, persistent: page.persistent)
                .frame(minWidth: 940, minHeight: 680)
        }
#if DEBUG
        .background(
            DebugSnapshotCapture(
                isReady: ProcessInfo.processInfo.environment["GITGATTO_RELEASE_HISTORY_PREVIEW"] == "1"
                    && !manager.isLoadingReleaseNotes
            )
        )
#endif
    }

    private func header(_ palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            AppBrandLockup(iconSize: 34, wordmarkWidth: 92, spacing: 7)
                .padding(
                    .leading,
                    AppThemeLayout.titlebarBrandLeading
                        - (theme == .softGlass ? AppThemeLayout.workspaceInset : 0)
                        - 14
                )

            Rectangle().fill(palette.divider).frame(width: 1, height: 25)

            Text(L10n.text("release_history.title"))
                .font(.system(size: 15, weight: .semibold, design: theme == .console ? .monospaced : .default))
                .foregroundStyle(theme == .console ? palette.accent : palette.ink)

            Spacer()

            if manager.isLoadingReleaseNotes {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await manager.refreshReleaseNotes(force: true) }
            } label: {
                GattoLabel(L10n.text("update.release_notes.refresh"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(manager.isLoadingReleaseNotes)
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background(palette.sidebar.opacity(theme == .softGlass ? 0.18 : 1))
    }

    private func releaseList(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(L10n.text("release_history.versions"))
                    .font(.system(size: 12.5, weight: .semibold, design: theme == .console ? .monospaced : .default))
                    .foregroundStyle(palette.ink)
                Spacer()
                Text("\(manager.releaseNotes.count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.mutedInk)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            Rectangle().fill(palette.divider).frame(height: 1)

            if let error = manager.releaseNotesError {
                GattoLabel(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            }

            if manager.releaseNotes.isEmpty, manager.isLoadingReleaseNotes {
                GattoLoadingState(text: L10n.text("loading.generic"))
            } else {
                ScrollView {
                    LazyVStack(spacing: theme == .console ? 2 : 4) {
                        ForEach(manager.releaseNotes) { release in
                            ReleaseHistoryRow(
                                release: release,
                                isCurrent: release.version == manager.currentVersion,
                                isSelected: selectedRelease?.id == release.id,
                                theme: theme
                            ) {
                                selectedReleaseID = release.id
                            }
                        }
                    }
                    .padding(theme == .console ? 6 : 8)
                }
            }
        }
        .background(palette.sidebar.opacity(theme == .softGlass ? 0.18 : 1))
    }

    @ViewBuilder
    private func releaseDetail(_ palette: AppPalette) -> some View {
        if let release = selectedRelease {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(L10n.format("release_history.version", release.version))
                                .font(.system(size: 19, weight: .bold, design: theme == .console ? .monospaced : .default))
                                .foregroundStyle(palette.ink)

                            if release.version == manager.currentVersion {
                                releaseBadge("release_history.current", color: palette.success)
                            }
                            if release.isPrerelease {
                                releaseBadge("update.release_notes.prerelease", color: palette.warning)
                            }
                        }

                        Text(release.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(palette.mutedInk)

                        if let publishedAt = release.publishedAt {
                            Text(publishedAt.formatted(date: .long, time: .omitted))
                                .font(.system(size: 10.5))
                                .foregroundStyle(palette.subtleInk)
                        }
                    }

                    Spacer()

                    Button {
                        browserPage = InAppBrowserPage(url: release.webURL)
                    } label: {
                        GattoLabel(L10n.text("update.release_notes.view_on_github"), systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 17)

                Rectangle().fill(palette.divider).frame(height: 1)

                ScrollView {
                    Group {
                        if release.body.isEmpty {
                            Text(L10n.text("update.release_notes.no_details"))
                                .font(.system(size: 12.5))
                                .foregroundStyle(palette.mutedInk)
                        } else {
                            ReleaseNotesMarkdownView(
                                text: release.body,
                                openURL: { browserPage = InAppBrowserPage(url: $0) }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
                    .frame(maxWidth: 700, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .background(palette.surface.opacity(theme == .softGlass ? 0.18 : 1))
        } else if manager.isLoadingReleaseNotes {
            GattoLoadingState(text: L10n.text("loading.generic"))
                .background(palette.surface.opacity(theme == .softGlass ? 0.18 : 1))
        } else {
            ContentUnavailableView(
                L10n.text("release_history.empty"),
                systemImage: "clock.arrow.circlepath"
            )
            .foregroundStyle(palette.mutedInk)
            .background(palette.surface.opacity(theme == .softGlass ? 0.18 : 1))
        }
    }

    private func releaseBadge(_ key: String, color: Color) -> some View {
        Text(L10n.text(key))
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func selectAvailableRelease() {
        if let selectedReleaseID,
           manager.releaseNotes.contains(where: { $0.id == selectedReleaseID }) {
            return
        }
        selectedReleaseID = manager.releaseNotes.first?.id
    }
}

private struct ReleaseHistoryRow: View {
    let release: AppReleaseNote
    let isCurrent: Bool
    let isSelected: Bool
    let theme: AppVisualTheme
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(release.version)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    if isCurrent {
                        Circle().fill(palette.success).frame(width: 6, height: 6)
                    }
                    Spacer()
                    if let publishedAt = release.publishedAt {
                        Text(publishedAt.formatted(date: .numeric, time: .omitted))
                            .font(.system(size: 9.5))
                            .foregroundStyle(palette.subtleInk)
                    }
                }

                Text(release.title)
                    .font(.system(size: 10.5, weight: .medium, design: theme == .console ? .monospaced : .default))
                    .foregroundStyle(isSelected ? palette.ink : palette.mutedInk)
                    .lineLimit(2)
            }
            .foregroundStyle(isSelected ? (theme == .console ? palette.accent : palette.primary) : palette.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? palette.primarySoft : (isHovering ? palette.raisedSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: theme == .console ? 4 : 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme == .console ? 4 : 9, style: .continuous)
                    .stroke(isSelected ? palette.primary.opacity(0.26) : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension View {
    @ViewBuilder
    func themedReleasePanel(
        theme: AppVisualTheme,
        cornerRadius: CGFloat,
        elevated: Bool
    ) -> some View {
        if theme == .softGlass {
            appGlassPanel(cornerRadius: cornerRadius, elevated: elevated)
        } else {
            self
        }
    }
}
