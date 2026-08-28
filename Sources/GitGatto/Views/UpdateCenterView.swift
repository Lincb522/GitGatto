import SwiftUI

struct UpdateCenterView: View {
    @ObservedObject var manager: AppUpdateManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    @State private var browserPage: InAppBrowserPage?

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: AppThemeLayout.panelSpacing) {
            HStack(spacing: 12) {
                AppBrandLockup(iconSize: 36, wordmarkWidth: 94, spacing: 8)
                    .padding(
                        .leading,
                        AppThemeLayout.titlebarBrandLeading
                            - AppThemeLayout.workspaceInset
                            - 12
                    )
                Rectangle().fill(palette.divider).frame(width: 1, height: 26)
                Text(L10n.text("update.title"))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 66)
            .background(palette.sidebar.opacity(0.18))
            .appGlassPanel(cornerRadius: 16, elevated: false)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    statusHeader(palette)

                    HStack(spacing: 10) {
                        VersionMetric(
                            titleKey: "update.current_version",
                            value: manager.currentVersion
                        )
                        VersionMetric(
                            titleKey: "update.current_build",
                            value: manager.currentBuild
                        )
                        VersionMetric(
                            titleKey: "update.channel",
                            value: L10n.text("update.channel.github")
                        )
                    }

                    updatePreferences(palette)
                    releaseNotesSection(palette)
                    updateActions(palette)
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(palette.surface.opacity(0.18))
            .appGlassPanel()
        }
        .padding(AppThemeLayout.workspaceInset)
        .frame(minWidth: 660, minHeight: 560)
        .background(Color.clear)
        .ignoresSafeArea(.container, edges: .top)
        .task {
            await manager.refreshReleaseNotes()
        }
        .sheet(item: $browserPage) { page in
            InAppBrowserSheet(url: page.url, persistent: page.persistent)
                .frame(minWidth: 940, minHeight: 680)
        }
#if DEBUG
        .background(
            DebugSnapshotCapture(
                isReady: ProcessInfo.processInfo.environment["GITGATTO_UPDATE_PREVIEW"] == "1"
            )
        )
#endif
    }

    private func statusHeader(_ palette: AppPalette) -> some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(statusColor(palette).opacity(0.12))
                statusIcon
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(statusColor(palette))
            }
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 5) {
                Text(statusTitle)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(palette.ink)
                if let statusErrorDetail {
                    Text(statusErrorDetail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
    }

    private func updatePreferences(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            UpdateToggleRow(
                titleKey: "update.automatic_checks",
                isOn: Binding(
                    get: { manager.automaticallyChecksForUpdates },
                    set: { manager.setAutomaticallyChecksForUpdates($0) }
                ),
                isEnabled: manager.isConfigured
            )
            Rectangle().fill(palette.divider).frame(height: 1)
            UpdateToggleRow(
                titleKey: "update.automatic_downloads",
                isOn: Binding(
                    get: { manager.automaticallyDownloadsUpdates },
                    set: { manager.setAutomaticallyDownloadsUpdates($0) }
                ),
                isEnabled: manager.isConfigured
            )
        }
        .background(palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.divider, lineWidth: 1)
        }
    }

    private func releaseNotesSection(_ palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Text(L10n.text("update.release_notes.title"))
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(palette.ink)

                Text(L10n.text(
                    manager.releaseNotesSource == .github
                        ? "update.release_notes.source.github"
                        : "update.release_notes.source.bundled"
                ))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.primary)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(palette.primarySoft)
                .clipShape(Capsule())

                Spacer()

                Button(L10n.text("release_history.open")) {
                    openWindow(id: "release-history")
                }
                .buttonStyle(SecondaryButtonStyle())

                if manager.isLoadingReleaseNotes {
                    ProgressView().controlSize(.small)
                }

                Button {
                    Task { await manager.refreshReleaseNotes(force: true) }
                } label: {
                    Image(gattoSymbol: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(manager.isLoadingReleaseNotes)
                .help(L10n.text("update.release_notes.refresh"))
            }

            if let error = manager.releaseNotesError {
                GattoLabel(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.warning)
            }

            if manager.releaseNotes.isEmpty, !manager.isLoadingReleaseNotes {
                Text(L10n.text("update.release_notes.empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.mutedInk)
            } else if let latestRelease = manager.releaseNotes.first {
                ReleaseNoteCard(
                    release: latestRelease,
                    startsExpanded: true,
                    openURL: { browserPage = InAppBrowserPage(url: $0) }
                )
            }
        }
    }

    private func updateActions(_ palette: AppPalette) -> some View {
        HStack(spacing: 10) {
            if let lastCheckedAt = manager.lastCheckedAt {
                Text(L10n.format(
                    "update.last_checked",
                    lastCheckedAt.formatted(date: .abbreviated, time: .shortened)
                ))
                .font(.system(size: 10.5))
                .foregroundStyle(palette.subtleInk)
            }

            Spacer()

            Button(L10n.text("update.view_releases")) {
                browserPage = InAppBrowserPage(url: AppLinks.releases)
            }
            .buttonStyle(SecondaryButtonStyle())

            UpdateActionButton(
                state: manager.state,
                isEnabled: !manager.isConfigured || manager.canCheckForUpdates
            ) {
                manager.checkForUpdates()
            }
        }
    }

    private var statusTitle: String {
        switch manager.state {
        case .configurationRequired: L10n.text("update.status.configuration_required")
        case .ready: L10n.text("update.status.ready")
        case .checking: L10n.text("update.status.checking")
        case .current: L10n.text("update.status.current")
        case let .updateAvailable(version, _): L10n.format("update.status.available", version)
        case .failed: L10n.text("update.status.failed")
        }
    }

    private var statusErrorDetail: String? {
        guard case let .failed(message) = manager.state else { return nil }
        return message
    }

    @ViewBuilder
    private var statusIcon: some View {
        if manager.state == .checking {
            ProgressView().controlSize(.small)
        } else {
            Image(gattoSymbol: statusSymbol)
        }
    }

    private var statusSymbol: String {
        switch manager.state {
        case .configurationRequired: "arrow.down.circle"
        case .ready: "arrow.down.app"
        case .checking: "arrow.triangle.2.circlepath"
        case .current: "checkmark.seal.fill"
        case .updateAvailable: "arrow.down.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(_ palette: AppPalette) -> Color {
        switch manager.state {
        case .current: palette.success
        case .failed: palette.warning
        case .configurationRequired: palette.primary
        default: palette.primary
        }
    }
}

private struct ReleaseNoteCard: View {
    let release: AppReleaseNote
    let openURL: (URL) -> Void
    @State private var isExpanded: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(release: AppReleaseNote, startsExpanded: Bool, openURL: @escaping (URL) -> Void) {
        self.release = release
        self.openURL = openURL
        _isExpanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Text(release.version)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.primary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(palette.primarySoft)
                        .clipShape(Capsule())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(release.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        if let publishedAt = release.publishedAt {
                            Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 10.5))
                                .foregroundStyle(palette.subtleInk)
                        }
                    }

                    if release.isPrerelease {
                        Text(L10n.text("update.release_notes.prerelease"))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(palette.warning)
                    }

                    Spacer()
                    Image(gattoSymbol: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.subtleInk)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(14)

            if isExpanded {
                Rectangle().fill(palette.divider).frame(height: 1)
                VStack(alignment: .leading, spacing: 14) {
                    if release.body.isEmpty {
                        Text(L10n.text("update.release_notes.no_details"))
                            .font(.system(size: 12))
                            .foregroundStyle(palette.mutedInk)
                    } else {
                        ReleaseNotesMarkdownView(text: release.body, openURL: openURL)
                    }

                    HStack {
                        Spacer()
                        Button(L10n.text("update.release_notes.view_on_github")) {
                            openURL(release.webURL)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.divider, lineWidth: 1)
        }
    }
}

struct ReleaseNotesMarkdownView: View {
    let text: String
    let openURL: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        LazyVStack(alignment: .leading, spacing: 9) {
            ForEach(ReleaseNotesMarkdownBlock.parse(text)) { block in
                switch block.kind {
                case .heading:
                    Text(block.text)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(palette.ink)
                        .padding(.top, 3)
                case .paragraph:
                    markdownText(block.text, palette: palette)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(palette.primary)
                            .frame(width: 4, height: 4)
                        markdownText(block.text, palette: palette)
                    }
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            openURL(url)
            return .handled
        })
    }

    private func markdownText(_ text: String, palette: AppPalette) -> some View {
        Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
            .font(.system(size: 11.5))
            .foregroundStyle(palette.mutedInk)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

private struct ReleaseNotesMarkdownBlock: Identifiable {
    enum Kind { case heading, paragraph, bullet }

    let id: Int
    let kind: Kind
    let text: String

    static func parse(_ source: String) -> [ReleaseNotesMarkdownBlock] {
        var blocks: [ReleaseNotesMarkdownBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.init(
                id: blocks.count,
                kind: .paragraph,
                text: paragraph.joined(separator: " ")
            ))
            paragraph.removeAll(keepingCapacity: true)
        }

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("#") {
                flushParagraph()
                let heading = line.drop(while: { $0 == "#" || $0 == " " })
                blocks.append(.init(id: blocks.count, kind: .heading, text: String(heading)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.init(id: blocks.count, kind: .bullet, text: String(line.dropFirst(2))))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return blocks
    }
}

private struct VersionMetric: View {
    let titleKey: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(titleKey))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.ink)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct UpdateToggleRow: View {
    let titleKey: String
    @Binding var isOn: Bool
    let isEnabled: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 16) {
            Text(L10n.text(titleKey))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.ink)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .disabled(!isEnabled)
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 50)
    }
}
