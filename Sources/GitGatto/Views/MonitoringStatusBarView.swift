import AppKit
import Combine
import SwiftUI

struct MonitoringMenuBarLabel: View {
    let model: WorkspaceViewModel
    @State private var summary: MonitoringStatusSummary
    @State private var language: AppLanguage

    init(model: WorkspaceViewModel) {
        self.model = model
        _summary = State(initialValue: model.monitoringStatusSummary)
        _language = State(initialValue: model.appPreferences.language)
    }

    var body: some View {
        MonitoringMenuBarContent(summary: summary)
            .environment(\.locale, language.locale)
            .onReceive(model.monitoringStatusPublisher) { summary = $0 }
            .onReceive(model.$appPreferences.map(\.language).removeDuplicates()) { language = $0 }
    }
}

struct MonitoringMenuBarContent: View {
    let summary: MonitoringStatusSummary

    var body: some View {
        HStack(spacing: 5) {
            Image(nsImage: MonitoringStatusIcon.image(for: summary.state))
            Text(summary.compactTitle)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityDescription)
        .help(summary.accessibilityDescription)
    }
}

struct MonitoringStatusBarView: View {
    @ObservedObject var model: WorkspaceViewModel
    @ObservedObject var engine: MonitoringEngine
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings

    private var summary: MonitoringStatusSummary { model.monitoringStatusSummary }

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }
    private var palette: AppPalette { AppPalette(colorScheme, theme: theme) }

    var body: some View {
        VStack(spacing: 12) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    repositorySummary
                    if !engine.repositories.isEmpty {
                        repositoryPanel
                        activityPanel
                    }
                    if !updateChannels.isEmpty { updatesPanel }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(minHeight: 0, maxHeight: engine.repositories.isEmpty ? 76 : 540)
            footer
        }
        .padding(14)
        .frame(minWidth: 350, idealWidth: 430, maxWidth: 430)
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

    private var repositoryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text("monitoring.status.changes_title"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.mutedInk)
                Text(summary.changedValue)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 6)
                Text(summary.coverageText)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.subtleInk)
                    .multilineTextAlignment(.trailing)
            }
            ForEach(engine.channels.filter { $0.isEnabled && $0.state == .attention && [.workingTree, .remote].contains($0.category) }) { channel in
                Text(channel.detail ?? L10n.text("monitoring.overall.attention"))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(summary.repositories) { repository in
                Button { openChannel(.workingTree, repository: repository.repository) } label: {
                    HStack(spacing: 9) {
                        GattoIcon(symbol: "folder", size: 18)
                            .foregroundStyle(palette.primary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(repository.repository.lastPathComponent)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(repositoryDetail(repository))
                                .font(.system(size: 10))
                                .foregroundStyle(palette.mutedInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        if summary.remoteEnabled, let ahead = repository.ahead, let behind = repository.behind {
                            Text("↑\(ahead.formatted())  ↓\(behind.formatted())")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(ahead + behind > 0 ? palette.primary : palette.subtleInk)
                                .accessibilityLabel(L10n.format("monitoring.detail.remote.counts", ahead, behind))
                        }
                        GattoIcon(symbol: "chevron.right", size: 10)
                            .foregroundStyle(palette.subtleInk)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(repository.repository.path)
            }
        }
        .padding(13)
        .monitoringPanel(theme: theme, palette: palette)
    }

    private func repositoryDetail(_ repository: MonitoringRepositoryStatus) -> String {
        guard summary.workingTreeEnabled else { return L10n.text("monitoring.status.worktree_paused") }
        guard let changed = repository.changed, let staged = repository.staged else {
            return L10n.text("monitoring.status.pending")
        }
        let detail = changed == 0 ? L10n.text("monitoring.detail.working_tree.clean")
            : L10n.format("monitoring.detail.working_tree.changed", changed, staged)
        let upstream = summary.remoteEnabled && repository.ahead == nil
            ? L10n.text("monitoring.detail.remote.no_upstream") : nil
        return [repository.branch, detail, upstream].compactMap { $0 }.joined(separator: " · ")
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

    private var updateChannels: [MonitoringChannelSnapshot] {
        engine.channels.filter { $0.isEnabled && [.repositoryProtection, .githubActions, .projectGoals].contains($0.category) }
    }

    private var updatesPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text("monitoring.status_overview"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 4)
                .padding(.bottom, 3)

            ForEach(updateChannels) { channel in
                if engine.selectedRepositoryURL == nil,
                          [.workingTree, .githubActions, .projectGoals].contains(channel.category) {
                    Menu {
                        ForEach(engine.repositories, id: \.standardizedFileURL.path) { repository in
                            Button(repository.lastPathComponent) { openChannel(channel.category, repository: repository) }
                        }
                    } label: { channelRow(channel) }.menuStyle(.borderlessButton)
                } else {
                    Button { openChannel(channel.category, repository: engine.selectedRepositoryURL) }
                    label: { channelRow(channel) }.buttonStyle(.plain)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .monitoringPanel(theme: theme, palette: palette)
    }

    private func channelRow(_ channel: MonitoringChannelSnapshot) -> some View {
        MonitoringChannelRow(channel: channel, detail: monitoringDetail(for: channel), palette: palette)
    }

    private func openChannel(_ category: MonitoringCategory, repository: URL?) {
        if model.isBackgroundMonitor {
            MonitoringHelperHost.openApplication(category: category, repository: repository)
        } else {
            showMainWindow()
            Task { await model.openMonitoringChannel(category, repositoryURL: repository) }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(L10n.text("monitoring.open_app")) {
                showMainWindow()
            }
            .buttonStyle(PrimaryButtonStyle())

            Button(L10n.text("settings.title")) {
                openMonitoringSettings()
            }
            .buttonStyle(SecondaryButtonStyle())

            Spacer()

            if !model.isBackgroundMonitor {
                Button(L10n.text("monitoring.quit")) { WindowCloseRuntime.quit() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.mutedInk)
            }
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
            L10n.text("monitoring.overall.monitoring")
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
        case .workingTree, .remote:
            return summary.coverageText

        case .repositoryProtection:
            let repositoryPath = engine.selectedRepositoryURL?.standardizedFileURL.path
            let backups = model.repositoryBackups.filter {
                repositoryPath == nil || URL(fileURLWithPath: $0.repositoryPath).standardizedFileURL.path == repositoryPath
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
            if !model.isBackgroundMonitor, let repository = engine.selectedRepositoryURL,
               model.snapshot?.rootURL.standardizedFileURL != repository.standardizedFileURL {
                return L10n.text("monitoring.status.pending")
            }
            let runs = model.monitoringActions(for: engine.selectedRepositoryURL)
            let activeCount = runs.count { run in
                ["queued", "in_progress", "requested", "waiting", "pending"]
                    .contains(run.status.lowercased())
            }
            guard !runs.isEmpty else {
                return L10n.text("monitoring.detail.actions.none")
            }
            let detail = L10n.format("monitoring.detail.actions.count", activeCount, runs.count)
            if !model.isBackgroundMonitor, engine.selectedRepositoryURL == nil,
               let repository = model.snapshot?.rootURL, engine.repositoryCount > 1 {
                return repository.lastPathComponent + ": " + detail
            }
            return detail

        case .projectGoals:
            let repositoryPath = engine.selectedRepositoryURL?.standardizedFileURL.path
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
        if model.isBackgroundMonitor { MonitoringHelperHost.openApplication() }
        else { WindowCloseRuntime.showWorkspace() }
    }

    private func openMonitoringSettings() {
        if model.isBackgroundMonitor { MonitoringHelperHost.openApplication(settings: true) }
        else {
            model.settingsDestination = "monitoring"
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
    }

}

private struct MonitoringChannelRow: View {
    let channel: MonitoringChannelSnapshot
    let detail: String
    let palette: AppPalette

    var body: some View {
        HStack(spacing: 10) {
            Image(gattoSymbol: channel.category.iconName, pointSize: 12.5)
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
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            if channel.state == .attention {
                Image(gattoSymbol: "exclamationmark.triangle.fill", pointSize: 14)
                    .foregroundStyle(palette.warning)
            }

        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
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
