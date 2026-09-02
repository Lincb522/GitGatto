import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    let onInitialContentReady: () -> Void
    let canCaptureSnapshot: Bool
    @StateObject private var marketplaceModel = GitHubMarketplaceViewModel()
    @StateObject private var developerToolsModel = DeveloperToolsViewModel()
    @StateObject private var downloads = AppDownloadManager()
    @State private var didReportInitialContentReady = false
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @AppStorage("workspace.sidebar.collapsed") private var isSidebarCollapsed = false
    @AppStorage("workspace.sidebar.width") private var sidebarWidth = 232.0
    @Environment(\.colorScheme) private var colorScheme

    init(
        model: WorkspaceViewModel,
        onInitialContentReady: @escaping () -> Void = {},
        canCaptureSnapshot: Bool = true
    ) {
        self.model = model
        self.onInitialContentReady = onInitialContentReady
        self.canCaptureSnapshot = canCaptureSnapshot
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    private var theme: AppVisualTheme {
        AppVisualTheme.resolved(themeRaw)
    }

    private var activeSidebarWidth: Binding<Double> {
        Binding(
            get: { isSidebarCollapsed ? 64 : sidebarWidth },
            set: { width in
                guard !isSidebarCollapsed else { return }
                sidebarWidth = width
            }
        )
    }

    private var activeErrorBinding: Binding<AppErrorReport?> {
        Binding(
            get: { model.activeError },
            set: { value in
                if value == nil {
                    model.dismissActiveError()
                }
            }
        )
    }

    private var isSnapshotReady: Bool {
        guard model.hasCompletedStartup else { return false }
        if model.selectedSection == .marketplace {
            return marketplaceModel.hasCompletedInitialLoad && !marketplaceModel.isLoading
        }
        if model.selectedSection == .github {
            return model.githubAvailability.state != .checking
                && !model.isLoadingGitHub
                && !model.isLoadingPullRequests
                && !model.isLoadingGitHubReadme
                && !model.isLoadingGitHubContents
                && !model.isLoadingGitHubFile
        }
        guard model.snapshot != nil else { return !model.isRefreshing }
        return switch model.selectedSection {
        case .github, .marketplace:
            true
        case .goals:
            !model.isRefreshingProjectGoals
        case .codex:
            model.codexAvailability.state != .checking
        case .timeMachine:
            !model.isLoadingRepositoryFiles
                && !model.isLoadingFileTimeline
                && model.selectedRepositoryFile != nil
                && model.fileVersionDocument != nil
        case .recovery:
            !model.isLoadingRepositoryBackups
        case .diagnostics:
            model.activeDiagnosticOperation == nil && model.repositoryDiagnostics != nil
        case .regression:
            model.activeRegressionInvestigationID == nil
        default:
            true
        }
    }

    private var isStartupPreloadReady: Bool {
        guard isSnapshotReady,
              marketplaceModel.hasCompletedInitialLoad,
              model.hasCompletedProjectPreload,
              model.hasCompletedRepositorySurfacePreload else { return false }
        guard model.selectedGitHubRepository != nil else { return true }
        return !model.isLoadingGitHub
            && !model.isLoadingPullRequests
            && !model.isLoadingGitHubReadme
            && !model.isLoadingGitHubContents
            && !model.isLoadingGitHubFile
    }

    private var startupLanguages: [String?] {
        Array(model.githubAccountRepositories.prefix(6).map(\.language))
            + Array(model.githubRecommendations.prefix(3).map(\.language))
            + Array(marketplaceModel.applications.prefix(6).map(\.repository.language))
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        GeometryReader { proxy in
            let compactSidebar = proxy.size.width < 1120
            ZStack(alignment: .top) {
                switch theme {
                case .standard:
                    HorizontalResizableSplitView(
                        primaryWidth: activeSidebarWidth,
                        minimumPrimaryWidth: isSidebarCollapsed ? 64 : 190,
                        maximumPrimaryWidth: isSidebarCollapsed ? 64 : 330,
                        minimumSecondaryWidth: 720,
                        separatorWidth: 7
                    ) {
                        RepositorySidebar(
                            model: model,
                            appearanceRaw: $appearanceRaw,
                            isCollapsed: $isSidebarCollapsed
                        )
                    } secondary: {
                        VStack(spacing: 0) {
                            if model.selectedSection != .github && model.selectedSection != .marketplace {
                                RepositoryTopBar(model: model)
                                Rectangle().fill(palette.divider).frame(height: 1)
                            }
                            workspaceDetail
                        }
                        .background(palette.background)
                    }
                case .softGlass:
                    VStack(spacing: AppThemeLayout.panelSpacing) {
                        HStack(spacing: AppThemeLayout.panelSpacing) {
                            if !isSidebarCollapsed {
                                WorkspaceBrandBar(compact: compactSidebar)
                                    .frame(width: activeSidebarWidth.wrappedValue)
                            }

                            RepositoryTopBar(model: model)
                        }

                        HorizontalResizableSplitView(
                            primaryWidth: activeSidebarWidth,
                            minimumPrimaryWidth: isSidebarCollapsed ? 64 : 190,
                            maximumPrimaryWidth: isSidebarCollapsed ? 64 : 330,
                            minimumSecondaryWidth: 720,
                            separatorWidth: AppThemeLayout.panelSpacing
                        ) {
                            RepositorySidebar(
                                model: model,
                                appearanceRaw: $appearanceRaw,
                                isCollapsed: $isSidebarCollapsed
                            )
                                .appGlassPanel()
                        } secondary: {
                            workspaceDetail
                                .background(palette.surface.opacity(0.18))
                                .appGlassPanel()
                        }
                    }
                    .padding(AppThemeLayout.workspaceInset)
                case .emerald:
                    HStack(spacing: 12) {
                        VStack(spacing: 0) {
                            if !isSidebarCollapsed {
                                WorkspaceBrandBar(compact: compactSidebar)
                                    .frame(height: 72)
                            }
                            RepositorySidebar(
                                model: model,
                                appearanceRaw: $appearanceRaw,
                                isCollapsed: $isSidebarCollapsed
                            )
                        }
                        .frame(width: activeSidebarWidth.wrappedValue)
                        .environment(\.colorScheme, .dark)
                        .background(AppPalette(.dark, theme: .emerald).sidebar)

                        VStack(spacing: 12) {
                            RepositoryTopBar(model: model)
                                .emeraldSurface(.elevated, cornerRadius: 16)

                            workspaceDetail
                                .background(palette.surface)
                                .emeraldSurface(.panel, cornerRadius: 16)
                        }
                        .padding(.vertical, 12)
                        .padding(.trailing, 12)
                    }
                case .folio:
                    HStack(spacing: 12) {
                        RepositorySidebar(
                            model: model,
                            appearanceRaw: $appearanceRaw,
                            isCollapsed: $isSidebarCollapsed
                        )
                        .frame(width: 58)
                        .environment(\.colorScheme, .dark)

                        VStack(spacing: 12) {
                            HStack(spacing: 0) {
                                WorkspaceBrandBar(compact: compactSidebar)
                                    .frame(width: 190)

                                Rectangle()
                                    .fill(palette.divider)
                                    .frame(width: 1, height: 34)

                                RepositoryTopBar(model: model)
                            }
                            .folioSurface(.elevated, cornerRadius: 16)

                            workspaceDetail
                                .background(palette.surface)
                                .folioSurface(.panel, cornerRadius: 16)
                        }
                    }
                    .padding(14)
                case .console:
                    consoleLayout(palette: palette)
                }

                if let notice = model.notice {
                    OperationToast(notice: notice)
                        .padding(.top, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(4)
                }
            }
        }
        .background(Color.clear)
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(appearance.colorScheme)
        .animation(.easeOut(duration: 0.2), value: model.notice?.id)
        .animation(.easeOut(duration: 0.2), value: model.activeOperation)
        .task {
            marketplaceModel.loadIfNeeded()
        }
        .task(id: marketplaceModel.selectedLogoURL) {
            guard let url = marketplaceModel.selectedLogoURL else { return }
            _ = try? await RemoteImageDataCache.shared.data(for: url)
        }
        .onChange(of: startupLanguages, initial: true) { _, languages in
            GitHubLanguageIconAssets.prewarm(languages: languages)
        }
        .onChange(of: isStartupPreloadReady, initial: true) { _, isReady in
            guard isReady, !didReportInitialContentReady else { return }
            didReportInitialContentReady = true
            onInitialContentReady()
        }
        .sheet(item: activeErrorBinding) { report in
            GlobalErrorSheet(
                report: report,
                canUseAgent: model.canResolveErrorWithAgent(report),
                useAgent: { model.resolveErrorWithAgent(report) },
                dismiss: { model.dismissActiveError() }
            )
        }
        .sheet(isPresented: $downloads.isPresented) {
            DownloadCenterView(manager: downloads)
            .frame(minWidth: 620, minHeight: 520)
        }
        .onChange(of: model.appPreferences.language) { _, language in
            marketplaceModel.refreshAutomaticTranslation(to: language.translationTarget)
        }
#if DEBUG
        .background(
            DebugSnapshotCapture(
                isReady: canCaptureSnapshot
                    && isSnapshotReady
                    && ProcessInfo.processInfo.environment["GITGATTO_SETTINGS_PREVIEW"] != "1"
                    && ProcessInfo.processInfo.environment["GITGATTO_ABOUT_PREVIEW"] != "1"
                    && ProcessInfo.processInfo.environment["GITGATTO_UPDATE_PREVIEW"] != "1"
                    && ProcessInfo.processInfo.environment["GITGATTO_RELEASE_HISTORY_PREVIEW"] != "1"
                    && ProcessInfo.processInfo.environment["GITGATTO_LEGAL_PREVIEW"] != "1"
                    && ProcessInfo.processInfo.environment["GITGATTO_HELP_PREVIEW"] != "1"
                    && ProcessInfo.processInfo.environment["GITGATTO_SCANNER_PREVIEW"] != "1"
                    && ProcessInfo.processInfo.environment["GITGATTO_ERROR_PREVIEW"] != "1"
            )
        )
#endif
    }

    @ViewBuilder
    private var workspaceDetail: some View {
        if model.selectedSection == .github {
            GitHubWorkspaceView(model: model, downloads: downloads)
        } else if model.selectedSection == .marketplace {
            GitHubMarketplaceView(
                model: marketplaceModel,
                developerTools: developerToolsModel,
                downloads: downloads
            )
        } else if model.selectedSection == .recovery {
            RepositoryRecoveryView(model: model)
        } else if model.snapshot == nil, model.isRefreshing {
            GattoLoadingState(text: L10n.text("loading.generic"))
        } else if model.snapshot == nil {
            WelcomeView(model: model)
        } else {
            switch model.selectedSection {
            case .changes:
                ChangesWorkspaceView(model: model)
            case .stash:
                StashWorkspaceView(model: model)
            case .history:
                HistoryWorkspaceView(model: model)
            case .timeMachine:
                FileTimelineWorkspaceView(model: model)
            case .recovery:
                RepositoryRecoveryView(model: model)
            case .branches:
                BranchesWorkspaceView(model: model)
            case .worktrees:
                WorktreeWorkspaceView(model: model)
            case .diagnostics:
                RepositoryDiagnosticsView(model: model)
            case .regression:
                RegressionInvestigationWorkspaceView(model: model)
            case .goals:
                ProjectGoalsWorkspaceView(model: model)
            case .github:
                GitHubWorkspaceView(model: model, downloads: downloads)
            case .marketplace:
                GitHubMarketplaceView(
                    model: marketplaceModel,
                    developerTools: developerToolsModel,
                    downloads: downloads
                )
            case .codex:
                CodexWorkspaceView(model: model)
            }
        }
    }

    private func consoleLayout(palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ConsoleBrandBar(
                    isBusy: model.activeOperation != nil || model.isCodexRunning || model.isRefreshing
                )
                .frame(width: 218)

                Rectangle().fill(palette.divider).frame(width: 1)
                RepositoryTopBar(model: model)
            }
            .frame(height: 72)

            Rectangle().fill(palette.divider).frame(height: 1)

            HStack(spacing: 0) {
                ConsoleSectionRail(model: model)
                    .frame(width: 88)
                Rectangle().fill(palette.divider).frame(width: 1)
                workspaceDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Rectangle().fill(palette.divider).frame(height: 1)
            ConsoleRepositoryDock(model: model, appearanceRaw: $appearanceRaw)
                .frame(height: 54)
        }
        .background(palette.background)
    }
}

private struct WorkspaceBrandBar: View {
    let compact: Bool

    var body: some View {
        HStack(spacing: 0) {
            AppBrandLockup(
                iconSize: compact ? 34 : 38,
                wordmarkWidth: compact ? 82 : 96,
                spacing: 7
            )
            .padding(.leading, AppThemeLayout.titlebarBrandLeading)
            Spacer(minLength: 8)
        }
        .padding(.trailing, 12)
        .padding(.top, 18)
        .frame(height: 72)
    }
}

private struct ConsoleBrandBar: View {
    let isBusy: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 6) {
            AppBrandLockup(iconSize: 28, wordmarkWidth: 68, spacing: 6)
                .padding(.leading, AppThemeLayout.titlebarBrandLeading)

            Spacer(minLength: 0)

            ConsoleBreathingLight(isBusy: isBusy)
                .help(L10n.text(isBusy ? "console.status.running" : "console.status.ready"))
                .accessibilityLabel(L10n.text(isBusy ? "console.status.running" : "console.status.ready"))
        }
        .padding(.trailing, 8)
        .padding(.top, 18)
        .frame(maxHeight: .infinity)
        .background(palette.sidebar)
    }
}

private struct ConsoleSectionRail: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme

    private let sections: [WorkspaceSection] = [
        .github, .marketplace, .goals, .changes, .history, .timeMachine, .recovery, .branches, .worktrees, .diagnostics, .codex
    ]

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 4) {
            ForEach(sections) { section in
                Button {
                    model.selectedSection = section
                } label: {
                    VStack(spacing: 5) {
                        Image(gattoSymbol: icon(for: section))
                            .font(.system(size: 12, weight: .semibold))
                        Text(L10n.text("nav.\(section.rawValue)"))
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    }
                    .foregroundStyle(model.selectedSection == section ? palette.accent : palette.mutedInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(model.selectedSection == section ? palette.accentSoft : Color.clear)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(model.selectedSection == section ? palette.accent : Color.clear)
                            .frame(width: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.selectedSection == section ? .isSelected : [])
            }

            Spacer(minLength: 0)

            if let count = railCount {
                Text(String(format: "%03d", count))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.subtleInk)
                    .padding(.bottom, 10)
            }
        }
        .padding(.top, 10)
        .background(palette.sidebar)
    }

    private var railCount: Int? {
        switch model.selectedSection {
        case .github: model.githubAccountRepositories.count
        case .marketplace: marketplaceCount
        case .goals: model.activeProjectGoalCount
        case .changes: model.snapshot?.changes.count
        case .stash: model.stashes.count
        case .history: model.commitGraph.nodes.count
        case .timeMachine: model.repositoryFiles.count
        case .recovery: model.repositoryBackups.count
        case .branches: model.snapshot?.branches.count
        case .worktrees: model.worktrees.count
        case .diagnostics: model.repositoryDiagnostics?.attentionCount
        case .regression: model.activeRegressionInvestigationCount
        case .codex: nil
        }
    }

    private func icon(for section: WorkspaceSection) -> String {
        switch section {
        case .github: "square.grid.2x2"
        case .marketplace: "arrow.down.app"
        case .goals: "checkmark.seal"
        case .changes: "square.stack.3d.up"
        case .stash: "archivebox"
        case .history: "clock.arrow.circlepath"
        case .timeMachine: "clock.badge.checkmark"
        case .recovery: "clock.badge.checkmark"
        case .branches: "arrow.triangle.branch"
        case .worktrees: "rectangle.split.2x1"
        case .diagnostics: "stethoscope"
        case .regression: "record.circle"
        case .codex: "sparkles"
        }
    }

    private var marketplaceCount: Int? { nil }
}

private struct ConsoleRepositoryDock: View {
    @ObservedObject var model: WorkspaceViewModel
    @Binding var appearanceRaw: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(L10n.text("console.command.repositories"))
                    .foregroundStyle(palette.accent)
                Text(L10n.text("sidebar.repositories"))
                    .foregroundStyle(palette.mutedInk)
                Text(String(format: "%02d", model.localRepositories.count))
                    .foregroundStyle(palette.subtleInk)
            }
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))

            Rectangle().fill(palette.divider).frame(width: 1, height: 24)

            if model.localRepositories.isEmpty {
                Text(L10n.text("repository.scan.empty"))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.subtleInk)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.localRepositories, id: \.standardizedFileURL.path) { url in
                            let isCurrent = model.snapshot?.rootURL.standardizedFileURL == url.standardizedFileURL
                            Button {
                                Task { await model.openRepository(url) }
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(isCurrent ? palette.accent : palette.divider)
                                        .frame(width: 5, height: 5)
                                    Text(url.lastPathComponent)
                                        .lineLimit(1)
                                }
                                .font(.system(size: 10.5, weight: isCurrent ? .semibold : .medium, design: .monospaced))
                                .foregroundStyle(isCurrent ? palette.ink : palette.mutedInk)
                                .padding(.horizontal, 9)
                                .frame(height: 28)
                                .background(isCurrent ? palette.accentSoft : palette.raisedSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(isCurrent ? palette.accent : palette.divider, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(url.path)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            Button {
                openWindow(id: "repository-scanner")
            } label: {
                GattoIcon(
                    symbol: model.isScanningRepositories ? "arrow.triangle.2.circlepath" : "folder.badge.plus",
                    size: 24
                )
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.isScanningRepositories ? palette.accent : palette.ink)
            .help(L10n.text("repository.scan.open"))

            Menu {
                ForEach(AppAppearance.allCases) { appearance in
                    Button(L10n.text("appearance.\(appearance.rawValue)")) {
                        appearanceRaw = appearance.rawValue
                    }
                }
            } label: {
                Image(gattoSymbol: "circle.lefthalf.filled")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)

            Button {
                openSettings()
            } label: {
                Image(gattoSymbol: "gearshape")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.mutedInk)
            .help(L10n.text("settings.title"))

            Button {
                openWindow(id: "about")
            } label: {
                Image(gattoSymbol: "info.circle")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.mutedInk)
            .help(L10n.text("about.title"))
        }
        .padding(.horizontal, 12)
        .background(palette.sidebar)
    }
}

private struct RepositoryTopBar: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue

    @ViewBuilder
    var body: some View {
        let palette = AppPalette(colorScheme)
        if AppVisualTheme.resolved(themeRaw) == .standard
            || AppVisualTheme.resolved(themeRaw) == .emerald
            || AppVisualTheme.resolved(themeRaw) == .folio {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.repositoryName ?? L10n.text("app.name"))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)

                    if let path = model.snapshot?.rootURL.path {
                        Text(path)
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.subtleInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(L10n.text("app.subtitle"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.subtleInk)
                    }
                }
                .frame(maxWidth: 220, alignment: .leading)

                if let snapshot = model.snapshot {
                    BranchQuickSwitcher(model: model, snapshot: snapshot)
                    RepositorySyncStatusView(
                        state: snapshot.syncState,
                        error: model.liveSyncError
                    )
                }

                Spacer(minLength: 16)
                repositoryActions(palette: palette, compact: false)
            }
            .padding(.leading, 18)
            .padding(.trailing, 16)
            .frame(height: AppThemeLayout.topBarHeight)
            .background(palette.surface)
        } else if AppVisualTheme.resolved(themeRaw) == .softGlass {
            GeometryReader { proxy in
            let compact = proxy.size.width < 820
            HStack(spacing: 12) {
                HStack(spacing: compact ? 9 : 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.repositoryName ?? L10n.text("app.name"))
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)

                        if !compact, let path = model.snapshot?.rootURL.path {
                            Text(path)
                                .font(.system(size: 10.5, weight: .regular))
                                .foregroundStyle(palette.subtleInk)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else if !compact {
                            Text(L10n.text("app.subtitle"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(palette.subtleInk)
                        }
                    }
                    .frame(width: compact ? 124 : 190, alignment: .leading)

                    if let snapshot = model.snapshot {
                        BranchQuickSwitcher(model: model, snapshot: snapshot)

                        RepositorySyncStatusView(
                            state: snapshot.syncState,
                            error: model.liveSyncError
                        )
                    }
                }
                .padding(.horizontal, 14)
                .frame(width: compact ? 350 : 450, height: AppThemeLayout.topBarHeight)
                .background(palette.sidebar.opacity(0.14))
                .appGlassPanel(cornerRadius: 16, elevated: false)

                Spacer(minLength: 0)

                repositoryActions(palette: palette, compact: compact)
                .padding(.horizontal, 10)
                .frame(height: AppThemeLayout.topBarHeight)
                .background(palette.sidebar.opacity(0.14))
                .appGlassPanel(cornerRadius: 16, elevated: false)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(height: AppThemeLayout.topBarHeight)
        } else {
            GeometryReader { proxy in
                let compact = proxy.size.width < 820
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(L10n.text("console.command.git"))
                                .foregroundStyle(palette.accent)
                            Text(model.repositoryName ?? L10n.text("app.name"))
                                .foregroundStyle(palette.ink)
                                .lineLimit(1)
                        }
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))

                        if !compact, let path = model.snapshot?.rootURL.path {
                            Text(path)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(palette.subtleInk)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: compact ? 150 : 250, alignment: .leading)

                    if let snapshot = model.snapshot {
                        BranchQuickSwitcher(model: model, snapshot: snapshot)
                        RepositorySyncStatusView(
                            state: snapshot.syncState,
                            error: model.liveSyncError
                        )
                    }

                    Spacer(minLength: 8)
                    repositoryActions(palette: palette, compact: compact)
                }
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)
                .background(palette.surface)
            }
            .frame(height: AppThemeLayout.topBarHeight)
        }
    }

    private func repositoryActions(palette: AppPalette, compact: Bool) -> some View {
        HStack(spacing: compact ? 9 : 12) {
            if model.snapshot != nil {
                RemoteSyncButton(
                    titleKey: "action.pull",
                    activity: .pull,
                    compact: compact,
                    isActive: model.activeOperation == .pull,
                    isDisabled: model.activeOperation != nil,
                    completionID: model.notice?.message == L10n.text("notice.pulled")
                        ? model.notice?.id
                        : nil
                ) {
                    Task { await model.pull() }
                }

                RemoteSyncButton(
                    titleKey: "action.push",
                    activity: .push,
                    compact: compact,
                    isActive: model.activeOperation == .push || model.activeOperation == .commitAndPush,
                    isDisabled: model.activeOperation != nil,
                    completionID: model.notice?.message == L10n.text("notice.pushed")
                        || model.notice?.message == L10n.text("notice.committed_pushed")
                        ? model.notice?.id
                        : nil
                ) {
                    Task { await model.push() }
                }

                Rectangle()
                    .fill(palette.divider)
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 2)

                ToolbarIconButton(
                    systemName: "arrow.clockwise",
                    helpKey: "action.refresh",
                    isActive: model.isRefreshing,
                    isDisabled: model.isRefreshing
                ) {
                    Task { await model.refresh() }
                }
            }

            Button(L10n.text("action.open_repository")) {
                model.chooseRepository()
            }
            .buttonStyle(SecondaryButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct BranchQuickSwitcher: View {
    @ObservedObject var model: WorkspaceViewModel
    let snapshot: RepositorySnapshot

    @Environment(\.colorScheme) private var colorScheme
    @State private var showsBranches = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button {
            showsBranches.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(gattoSymbol: "arrow.triangle.branch")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(snapshot.branchName)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                Image(gattoSymbol: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(palette.subtleInk)
            }
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 9)
            .frame(height: 27)
            .background(palette.accentSoft)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(model.activeOperation != nil || model.isRefreshing || snapshot.branches.isEmpty)
        .help(L10n.text("branches.quick_switch"))
        .popover(isPresented: $showsBranches, arrowEdge: .top) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(snapshot.branches) { branch in
                        Button {
                            showsBranches = false
                            Task { await model.switchBranch(to: branch.name) }
                        } label: {
                            HStack(spacing: 9) {
                                Image(gattoSymbol: "arrow.triangle.branch")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(branch.name == snapshot.branchName ? palette.primary : palette.subtleInk)
                                    .frame(width: 18)
                                Text(branch.name)
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(palette.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if branch.name == snapshot.branchName {
                                    Image(gattoSymbol: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(palette.primary)
                                }
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 34)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(branch.name == snapshot.branchName)
                    }
                }
                .padding(8)
            }
            .frame(width: 260, height: min(CGFloat(snapshot.branches.count) * 36 + 16, 304))
            .background(palette.surface)
        }
    }
}

private struct RepositorySyncStatusView: View {
    let state: RepositorySyncState
    let error: String?

    @Environment(\.colorScheme) private var colorScheme

    private var presentation: (text: String, icon: String) {
        switch state {
        case .synced:
            (L10n.text("sync.status.synced"), "checkmark")
        case let .ahead(count):
            (L10n.format("sync.status.ahead", count), "arrow.up")
        case let .behind(count):
            (L10n.format("sync.status.behind", count), "arrow.down")
        case let .diverged(ahead, behind):
            (L10n.format("sync.status.diverged", ahead, behind), "arrow.up.arrow.down")
        case .noUpstream:
            (L10n.text("sync.status.no_upstream"), "link.badge.plus")
        }
    }

    private func foreground(_ palette: AppPalette) -> Color {
        return switch state {
        case .synced: palette.success
        case .ahead, .diverged, .noUpstream: palette.warning
        case .behind: palette.primary
        }
    }

    private func background(_ palette: AppPalette) -> Color {
        return switch state {
        case .synced: palette.successSoft
        case .ahead, .diverged, .noUpstream: palette.warningSoft
        case .behind: palette.primarySoft
        }
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 6) {
            GattoIcon(symbol: presentation.icon, size: 14)
            Text(presentation.text)
        }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(foreground(palette))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 25)
            .background(background(palette))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(foreground(palette).opacity(0.22), lineWidth: 1)
            }
            .help(error ?? L10n.text("sync.status.live"))
    }
}

private struct RemoteSyncButton: View {
    let titleKey: String
    let activity: TaskButtonActivityKind
    let compact: Bool
    let isActive: Bool
    let isDisabled: Bool
    let completionID: UUID?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsCompletion = false
    @State private var lastCompletionID: UUID?

    private var isExpanded: Bool {
        isActive || showsCompletion
    }

    private var width: CGFloat {
        compact ? 108 : 120
    }

    private var leadingPlateWidth: CGFloat {
        isExpanded ? width - 6 : (compact ? 36 : 42)
    }

    private var cornerRadius: CGFloat {
        AppThemeLayout.controlCornerRadius
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.raisedSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(palette.divider, lineWidth: 1)
                    }

                Text(L10n.text(titleKey))
                    .font(.system(size: compact ? 10.5 : 11.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .offset(x: compact ? 8 : 10)

                RoundedRectangle(
                    cornerRadius: max(3, cornerRadius - 2),
                    style: .continuous
                )
                .fill(showsCompletion ? palette.success : (isExpanded ? palette.primary : palette.primarySoft))
                .frame(width: leadingPlateWidth, height: 32)
                .overlay {
                    if isActive || showsCompletion {
                        HStack(spacing: 7) {
                            if showsCompletion {
                                GattoIcon(symbol: "checkmark", size: 15)
                            } else {
                                CloneActivityGlyph(
                                    systemImage: syncSymbol,
                                    tint: Color.white,
                                    travelsUp: activity == .push
                                )
                            }
                            Text(buttonTitle)
                                .lineLimit(1)
                        }
                        .font(.system(size: compact ? 10 : 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 9)
                    } else {
                        GattoIcon(symbol: syncSymbol, size: compact ? 17 : 19)
                            .foregroundStyle(isExpanded ? Color.white : palette.primary)
                    }
                }
                .overlay {
                    if isActive {
                        CloneProgressBorder(
                            tint: Color.white.opacity(0.92),
                            cornerRadius: max(3, cornerRadius - 2)
                        )
                    }
                }
                .padding(.leading, 3)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: isExpanded)
            }
            .frame(width: width, height: 38)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isDisabled)
        .opacity(isDisabled && !isActive ? 0.42 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: isActive)
        .onAppear {
            lastCompletionID = completionID
        }
        .task(id: completionID) {
            guard let completionID, completionID != lastCompletionID else { return }
            lastCompletionID = completionID
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                showsCompletion = true
            }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 500 : 950))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                showsCompletion = false
            }
        }
        .help(L10n.text(titleKey))
        .accessibilityLabel(buttonTitle)
    }

    private var buttonTitle: String {
        if showsCompletion {
            return L10n.text("downloads.state.completed")
        }
        if isActive {
            return L10n.text(activity == .push ? "sync.progress.push" : "sync.progress.pull")
        }
        return L10n.text(titleKey)
    }

    private var syncSymbol: String {
        activity == .push ? "arrow.up" : "arrow.down"
    }
}

private struct WelcomeView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            Spacer()

            AppBrandIcon(size: 76)

            Text(L10n.text("welcome.title"))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.ink)
                .padding(.top, 20)

            Text(L10n.text("welcome.body"))
                .font(.system(size: 13.5))
                .foregroundStyle(palette.mutedInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.top, 8)

            Button(L10n.text("action.open_repository")) {
                model.chooseRepository()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 22)

            if !model.recentRepositories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("sidebar.recent"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.mutedInk)
                    ForEach(model.recentRepositories.prefix(3), id: \.path) { url in
                        Button {
                            Task { await model.openRepository(url) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(gattoSymbol: "folder")
                                    .foregroundStyle(palette.primary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                        .foregroundStyle(palette.ink)
                                    Text(url.deletingLastPathComponent().path)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(palette.subtleInk)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Image(gattoSymbol: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(palette.subtleInk)
                            }
                            .font(.system(size: 12.5, weight: .medium))
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(palette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 390)
                .padding(.top, 34)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
    }
}
