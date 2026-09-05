import AppKit
import SwiftUI

struct MonitoringMenuBarLabel: View {
    @ObservedObject var engine: MonitoringEngine

    var body: some View {
        GattoIcon(symbol: iconName, size: 16)
            .frame(width: 18, height: 18)
            .accessibilityLabel(L10n.text(engine.overallState.localizationKey))
    }

    private var iconName: String {
        switch engine.overallState {
        case .paused: "pause"
        case .healthy, .monitoring: "dot.radiowaves.left.and.right"
        case .attention: "exclamationmark.triangle.fill"
        }
    }
}

struct MonitoringStatusBarView: View {
    @ObservedObject var model: WorkspaceViewModel
    @ObservedObject var engine: MonitoringEngine
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }
    private var palette: AppPalette { AppPalette(colorScheme, theme: theme) }

    var body: some View {
        VStack(spacing: 12) {
            header
            repositorySummary
            activityPanel
            channelPanel
            footer
        }
        .padding(14)
        .frame(width: 430)
        .background(palette.background)
        .task(id: engine.selectedRepositoryURL) {
            engine.refreshActivity()
        }
#if DEBUG
        .background(
            DebugSnapshotCapture(
                isReady: ProcessInfo.processInfo.environment["GITGATTO_MONITORING_PREVIEW"] == "1"
            )
        )
#endif
    }

    private var header: some View {
        HStack(spacing: 11) {
            AppBrandLockup(iconSize: 33, wordmarkWidth: 86, spacing: 8)

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(headerStatusText)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(statusColor.opacity(0.11))
            .clipShape(Capsule())
        }
        .padding(13)
        .monitoringPanel(theme: theme, palette: palette, elevated: true)
    }

    @ViewBuilder
    private var repositorySummary: some View {
        if !engine.repositories.isEmpty {
            HStack(spacing: 10) {
                GattoIcon(
                    symbol: engine.selectedRepositoryURL == nil ? "square.stack.3d.up" : "folder.fill",
                    size: 18
                )
                .foregroundStyle(palette.primary)
                .frame(width: 30, height: 30)
                .background(palette.primarySoft)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Menu {
                        Button {
                            engine.selectRepository(nil)
                        } label: {
                            GattoLabel(
                                L10n.text("monitoring.repository.all"),
                                systemImage: "square.stack.3d.up"
                            )
                        }
                        Divider()
                        ForEach(engine.repositories, id: \.standardizedFileURL.path) { repository in
                            Button {
                                engine.selectRepository(repository)
                            } label: {
                                GattoLabel(repository.lastPathComponent, systemImage: "folder")
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(repositoryScopeTitle)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(palette.ink)
                                .lineLimit(1)
                            GattoIcon(symbol: "chevron.down", size: 11)
                                .foregroundStyle(palette.subtleInk)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.plain)

                    Text(repositoryScopeDetail)
                        .font(.system(size: 9.5, design: engine.selectedRepositoryURL == nil ? .default : .monospaced))
                        .foregroundStyle(palette.subtleInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    engine.refreshActivity()
                } label: {
                    Image(gattoSymbol: "arrow.clockwise")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.mutedInk)
                .help(L10n.text("monitoring.activity.refresh"))
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .monitoringPanel(theme: theme, palette: palette)
        } else {
            HStack(spacing: 9) {
                Image(gattoSymbol: "folder")
                    .foregroundStyle(palette.subtleInk)
                Text(L10n.text("monitoring.repository.none"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.mutedInk)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .monitoringPanel(theme: theme, palette: palette)
        }
    }

    private var repositoryScopeTitle: String {
        engine.selectedRepositoryURL?.lastPathComponent
            ?? L10n.text("monitoring.repository.all")
    }

    private var repositoryScopeDetail: String {
        if let repository = engine.selectedRepositoryURL {
            return repository.deletingLastPathComponent().path(percentEncoded: false)
        }
        return L10n.format("monitoring.repository.all.detail", engine.repositoryCount)
    }

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(L10n.text("monitoring.activity.title"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
                if let today = engine.todayActivity {
                    Text(L10n.format(
                        "monitoring.activity.today",
                        today.commitCount,
                        today.monitoredChangeCount
                    ))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(palette.mutedInk)
                }
            }

            if engine.dailyActivity.isEmpty, engine.activityError == nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.text("loading.generic"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.mutedInk)
                }
                .frame(maxWidth: .infinity, minHeight: 76)
            } else {
                RepositoryActivityHeatmap(
                    activity: engine.dailyActivity,
                    accent: palette.primary,
                    emptyColor: palette.divider.opacity(0.42),
                    futureColor: palette.divider.opacity(0.18),
                    labelColor: palette.subtleInk
                )
                .frame(height: 76)
                .accessibilityLabel(L10n.text("monitoring.activity.accessibility"))
            }

            if let error = engine.activityError {
                Text(L10n.format("monitoring.activity.error", error))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .monitoringPanel(theme: theme, palette: palette)
    }

    private var channelPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text("monitoring.status_overview"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 4)
                .padding(.bottom, 3)

            ForEach(engine.channels) { channel in
                MonitoringChannelRow(
                    channel: channel,
                    detail: monitoringDetail(for: channel),
                    palette: palette
                )
            }
        }
        .padding(9)
        .monitoringPanel(theme: theme, palette: palette)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(L10n.text("monitoring.open_app")) {
                showMainWindow()
            }
            .buttonStyle(PrimaryButtonStyle())

            Button(L10n.text("settings.title")) {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .buttonStyle(SecondaryButtonStyle())

            Spacer()

            Button(L10n.text("monitoring.quit")) {
                WindowCloseRuntime.quit()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(palette.mutedInk)
        }
        .padding(.horizontal, 2)
    }

    private var statusColor: Color {
        switch engine.overallState {
        case .paused: palette.subtleInk
        case .healthy: palette.success
        case .monitoring: palette.primary
        case .attention: palette.warning
        }
    }

    private var headerStatusText: String {
        switch engine.overallState {
        case .attention, .paused:
            L10n.text(engine.overallState.localizationKey)
        case .healthy, .monitoring:
            L10n.format("monitoring.summary", engine.activeChannelCount, engine.repositoryCount)
        }
    }

    private func monitoringDetail(for channel: MonitoringChannelSnapshot) -> String {
        if channel.state == .attention, let detail = channel.detail, !detail.isEmpty {
            return detail
        }
        guard channel.isEnabled else {
            return L10n.text(MonitoringChannelState.paused.localizationKey)
        }

        switch channel.category {
        case .workingTree:
            guard engine.selectedRepositoryURL != nil else {
                return L10n.text("monitoring.detail.all_repositories")
            }
            guard let snapshot = model.snapshot else {
                return L10n.text("monitoring.detail.no_repository")
            }
            guard snapshot.rootURL.standardizedFileURL == engine.selectedRepositoryURL else {
                return L10n.text("monitoring.detail.selected_repository")
            }
            guard !snapshot.changes.isEmpty else {
                return L10n.text("monitoring.detail.working_tree.clean")
            }
            return L10n.format(
                "monitoring.detail.working_tree.changed",
                snapshot.changes.count,
                snapshot.stagedChanges.count
            )

        case .remote:
            guard engine.selectedRepositoryURL != nil else {
                return L10n.text("monitoring.detail.all_repositories")
            }
            guard let snapshot = model.snapshot else {
                return L10n.text("monitoring.detail.no_repository")
            }
            guard snapshot.rootURL.standardizedFileURL == engine.selectedRepositoryURL else {
                return L10n.text("monitoring.detail.selected_repository")
            }
            guard snapshot.upstreamName != nil else {
                return L10n.text("monitoring.detail.remote.no_upstream")
            }
            guard snapshot.aheadCount > 0 || snapshot.behindCount > 0 else {
                return L10n.text("monitoring.detail.remote.synced")
            }
            return L10n.format(
                "monitoring.detail.remote.counts",
                snapshot.aheadCount,
                snapshot.behindCount
            )

        case .repositoryProtection:
            guard let repositoryPath = model.snapshot?.rootURL.standardizedFileURL.path else {
                return L10n.text("monitoring.detail.no_repository")
            }
            let backups = model.repositoryBackups.filter {
                URL(fileURLWithPath: $0.repositoryPath).standardizedFileURL.path == repositoryPath
            }
            guard let latest = backups.max(by: { $0.createdAt < $1.createdAt }) else {
                return L10n.text("monitoring.detail.protection.none")
            }
            return L10n.format(
                "monitoring.detail.protection.count",
                backups.count,
                latest.createdAt.formatted(.relative(presentation: .named))
            )

        case .githubActions:
            let activeCount = model.githubActionRuns.count { run in
                ["queued", "in_progress", "requested", "waiting", "pending"]
                    .contains(run.status.lowercased())
            }
            guard !model.githubActionRuns.isEmpty else {
                return L10n.text("monitoring.detail.actions.none")
            }
            return L10n.format(
                "monitoring.detail.actions.count",
                activeCount,
                model.githubActionRuns.count
            )

        case .projectGoals:
            let repositoryPath = model.snapshot?.rootURL.standardizedFileURL.path
            let goals = model.projectGoals.filter { goal in
                repositoryPath == nil
                    || URL(fileURLWithPath: goal.repositoryPath).standardizedFileURL.path == repositoryPath
            }
            let activeCount = goals.count { [.running, .waiting].contains($0.status) }
            let completedCount = goals.count { $0.status == .completed }
            guard !goals.isEmpty else {
                return L10n.text("monitoring.detail.goals.none")
            }
            return L10n.format(
                "monitoring.detail.goals.count",
                activeCount,
                completedCount
            )
        }
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: {
            $0.canBecomeMain && $0.isVisible && !$0.isMiniaturized
        }) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
    }
}

private struct MonitoringChannelRow: View {
    let channel: MonitoringChannelSnapshot
    let detail: String
    let palette: AppPalette

    var body: some View {
        HStack(spacing: 10) {
            Image(gattoSymbol: channel.category.iconName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(channel.isEnabled ? stateColor : palette.subtleInk)
                .frame(width: 30, height: 30)
                .background((channel.isEnabled ? stateColor : palette.subtleInk).opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(channel.category.titleKey))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text(detail)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(channel.state == .attention ? palette.warning : palette.mutedInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if channel.state == .monitoring {
                ProgressView()
                    .controlSize(.mini)
            } else if channel.state == .attention {
                Image(gattoSymbol: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.warning)
            } else if let lastUpdatedAt = channel.lastUpdatedAt, channel.isEnabled {
                Text(lastUpdatedAt, style: .time)
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(palette.subtleInk)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 44)
        .background(channel.state == .attention ? palette.warningSoft.opacity(0.48) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var stateColor: Color {
        switch channel.state {
        case .paused: palette.subtleInk
        case .healthy: palette.success
        case .monitoring: palette.primary
        case .attention: palette.warning
        }
    }
}

struct RepositoryActivityHeatmap: View {
    let activity: [RepositoryDailyActivity]
    let accent: Color
    let emptyColor: Color
    let futureColor: Color
    let labelColor: Color

    var body: some View {
        Canvas { context, size in
            guard !activity.isEmpty else { return }
            let weekCount = max(1, Int(ceil(Double(activity.count) / 7)))
            let spacing: CGFloat = 2
            let labelHeight: CGFloat = 15
            let availableHeight = size.height - labelHeight
            let cell = min(
                (size.width - CGFloat(weekCount - 1) * spacing) / CGFloat(weekCount),
                (availableHeight - 6 * spacing) / 7
            )
            let gridWidth = CGFloat(weekCount) * cell + CGFloat(weekCount - 1) * spacing
            let originX = max(0, size.width - gridWidth)
            let maximum = max(1, activity.map(\.totalCount).max() ?? 1)
            let calendar = Calendar.current
            var lastMonthLabelX: CGFloat = -100

            for (index, day) in activity.enumerated() {
                let week = index / 7
                let weekday = index % 7
                let x = originX + CGFloat(week) * (cell + spacing)
                let y = labelHeight + CGFloat(weekday) * (cell + spacing)
                let isFuture = day.date > Date()
                let color: Color
                if isFuture {
                    color = futureColor
                } else if day.totalCount == 0 {
                    color = emptyColor
                } else {
                    let level = max(1, min(4, Int(ceil(Double(day.totalCount) / Double(maximum) * 4))))
                    color = accent.opacity(0.24 + Double(level) * 0.18)
                }
                context.fill(
                    Path(roundedRect: CGRect(x: x, y: y, width: cell, height: cell), cornerRadius: cell * 0.28),
                    with: .color(color)
                )

                let dayOfMonth = calendar.component(.day, from: day.date)
                if weekday == 0, dayOfMonth <= 7, x - lastMonthLabelX >= 24 {
                    lastMonthLabelX = x
                    let text = context.resolve(
                        Text(day.date, format: .dateTime.month(.abbreviated))
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(labelColor)
                    )
                    context.draw(text, at: CGPoint(x: x, y: 5), anchor: .topLeading)
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func monitoringPanel(
        theme: AppVisualTheme,
        palette: AppPalette,
        elevated: Bool = false
    ) -> some View {
        switch theme {
        case .softGlass:
            appGlassPanel(cornerRadius: 14, elevated: elevated)
        case .emerald:
            emeraldSurface(elevated ? .elevated : .panel, cornerRadius: 14)
        case .folio:
            folioSurface(elevated ? .elevated : .panel, cornerRadius: 14)
        case .lumen:
            lumenSurface(elevated ? .chrome : .inset, cornerRadius: 14)
        case .console:
            appConsolePanel()
        case .standard:
            background(elevated ? palette.raisedSurface : palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.divider, lineWidth: 1)
                }
        }
    }
}
