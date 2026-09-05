import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    let onInitialContentReady: () -> Void
    let canCaptureSnapshot: Bool
    @StateObject private var marketplaceModel = GitHubMarketplaceViewModel()
    @StateObject private var developerToolsModel = DeveloperToolsViewModel()
    @StateObject private var downloads = AppDownloadManager()
    @StateObject private var intelligenceModel = RepositoryIntelligenceViewModel()
    @State private var didReportInitialContentReady = false
    @State private var showsCommandPalette = false
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @AppStorage("workspace.sidebar.collapsed") private var isSidebarCollapsed = false
    @AppStorage("workspace.sidebar.width") private var sidebarWidth = 232.0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

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
            let compactSidebar = proxy.size.width < 1200
            let lumenSidebarCollapsed = isSidebarCollapsed
            let lumenSidebarWidth = Binding<Double>(
                get: { lumenSidebarCollapsed ? 64 : sidebarWidth },
                set: { width in
                    guard !lumenSidebarCollapsed else { return }
                    sidebarWidth = width
                }
            )
            let lumenSidebarCollapsedBinding = Binding<Bool>(
                get: { lumenSidebarCollapsed },
                set: { collapsed in
                    isSidebarCollapsed = collapsed
                }
            )
            ZStack(alignment: .top) {
                switch theme {
                case .standard:
                    HorizontalResizableSplitView(
                        primaryWidth: activeSidebarWidth,
                        minimumPrimaryWidth: isSidebarCollapsed ? 64 : 200,
                        maximumPrimaryWidth: isSidebarCollapsed ? 64 : 330,
                        minimumSecondaryWidth: 690,
                        separatorWidth: 7
                    ) {
                        RepositorySidebar(model: model, appearanceRaw: $appearanceRaw, isCollapsed: $isSidebarCollapsed)
                    } secondary: {
                        VStack(spacing: 0) {
                            RepositoryTopBar(model: model)
                                .padding(.top, 20)
                                .background(palette.surface)
                            Rectangle().fill(palette.divider).frame(height: 1)
                            workspaceDetail
                        }
                        .background(palette.background)
                    }
                case .softGlass:
                    HorizontalResizableSplitView(
                        primaryWidth: activeSidebarWidth,
                        minimumPrimaryWidth: isSidebarCollapsed ? 64 : 200,
                        maximumPrimaryWidth: isSidebarCollapsed ? 64 : 330,
                        minimumSecondaryWidth: 690,
                        separatorWidth: 7
                    ) {
                        RepositorySidebar(model: model, appearanceRaw: $appearanceRaw, isCollapsed: $isSidebarCollapsed)
                    } secondary: {
                        VStack(spacing: 0) {
                            RepositoryTopBar(model: model)
                            Rectangle().fill(palette.divider.opacity(0.65)).frame(height: 1)
                            workspaceDetail
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .appGlassPanel(cornerRadius: 16)
                        .padding(.top, 28)
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                        .padding(.leading, 5)
                    }
                case .emerald:
                    emeraldLayout(palette: palette)
                case .folio:
                    folioLayout(palette: palette, compact: compactSidebar)
                case .lumen:
                    VStack(spacing: 0) {
                        LumenWorkspaceHeader(
                            model: model,
                            sidebarCollapsed: lumenSidebarCollapsed
                        )
                        .frame(height: 94)
                        .lumenSurface(.chrome, cornerRadius: 0)

                        HorizontalResizableSplitView(
                            primaryWidth: lumenSidebarWidth,
                            minimumPrimaryWidth: lumenSidebarCollapsed ? 64 : 196,
                            maximumPrimaryWidth: lumenSidebarCollapsed ? 64 : 320,
                            minimumSecondaryWidth: 710,
                            separatorWidth: 7
                        ) {
                            RepositorySidebar(
                                model: model,
                                appearanceRaw: $appearanceRaw,
                                isCollapsed: lumenSidebarCollapsedBinding
                            )
                            .padding(.top, 8)
                        } secondary: {
                            workspaceDetail
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .lumenSurface(.panel, cornerRadius: 14)
                                .padding(.top, 16)
                                .padding(.trailing, 16)
                                .padding(.bottom, 16)
                                .padding(.leading, 9)
                        }
                    }
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
        .sheet(isPresented: $showsCommandPalette) {
            GlobalCommandPalette(
                model: model,
                openSettings: { openSettings() },
                openScanner: { openWindow(id: "repository-scanner") },
                openHelp: { openWindow(id: "help") },
                dismiss: { showsCommandPalette = false }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .gitGattoShowCommandPalette)) { _ in
            showsCommandPalette = true
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
            case .intelligence:
                RepositoryIntelligenceWorkspaceView(
                    model: intelligenceModel,
                    workspaceModel: model
                )
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

    private func emeraldLayout(palette: AppPalette) -> some View {
        HorizontalResizableSplitView(
            primaryWidth: activeSidebarWidth,
            minimumPrimaryWidth: isSidebarCollapsed ? 64 : 200,
            maximumPrimaryWidth: isSidebarCollapsed ? 64 : 330,
            minimumSecondaryWidth: 690,
            separatorWidth: 7
        ) {
            RepositorySidebar(model: model, appearanceRaw: $appearanceRaw, isCollapsed: $isSidebarCollapsed)
                .environment(\.colorScheme, .dark)
        } secondary: {
            VStack(spacing: 0) {
                RepositoryTopBar(model: model)
                    .padding(.top, 28)
                Rectangle().fill(palette.divider).frame(height: 1)
                workspaceDetail
            }
            .background(palette.background)
        }
    }

    private func folioLayout(palette: AppPalette, compact: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                WorkspaceBrandBar(compact: compact, iconOnly: isSidebarCollapsed)
                    .frame(width: isSidebarCollapsed ? 50 : 184)
                RepositoryTopBar(model: model)
                    .padding(.top, 18)
            }
            .frame(height: 88)
            HorizontalResizableSplitView(
                primaryWidth: activeSidebarWidth,
                minimumPrimaryWidth: isSidebarCollapsed ? 64 : 240,
                maximumPrimaryWidth: isSidebarCollapsed ? 64 : 330,
                minimumSecondaryWidth: 660,
                separatorWidth: 14
            ) {
                RepositorySidebar(model: model, appearanceRaw: $appearanceRaw, isCollapsed: $isSidebarCollapsed)
            } secondary: {
                workspaceDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    private func consoleLayout(palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                AppBrandLockup(iconSize: 26, wordmarkWidth: 80, spacing: 7)
                    .frame(width: 172, alignment: .leading)
                    .padding(.leading, 16)
                RepositoryTopBar(model: model)
            }
            .padding(.top, 24)
            .frame(height: 68)
            .background(palette.sidebar)
            Rectangle().fill(palette.divider).frame(height: 1)
            HorizontalResizableSplitView(
                primaryWidth: activeSidebarWidth,
                minimumPrimaryWidth: isSidebarCollapsed ? 64 : 240,
                maximumPrimaryWidth: isSidebarCollapsed ? 64 : 340,
                minimumSecondaryWidth: 660,
                separatorWidth: 5
            ) {
                RepositorySidebar(model: model, appearanceRaw: $appearanceRaw, isCollapsed: $isSidebarCollapsed)
            } secondary: {
                VStack(spacing: 0) {
                    ConsoleWorkspaceTabs(model: model)
                    workspaceDetail
                }
            }
            if let snapshot = model.snapshot {
                HStack(spacing: 12) {
                    Text(snapshot.rootURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 12)
                    Text(snapshot.branchName).lineLimit(1)
                    RepositorySyncStatusView(state: snapshot.syncState, error: model.liveSyncError)
                }
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(palette.mutedInk)
                .padding(.horizontal, 14)
                .frame(height: 25)
                .background(palette.sidebar)
                .overlay(alignment: .top) { Rectangle().fill(palette.divider).frame(height: 1) }
            }
        }
        .background(palette.background)
    }

}

private struct ConsoleWorkspaceTabs: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var sections: [WorkspaceSection] {
        let common: [WorkspaceSection] = [.changes, .history, .branches, .stash]
        return common.contains(model.selectedSection) ? common : common + [model.selectedSection]
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(sections) { section in
                        Button { model.selectedSection = section } label: {
                            Text(L10n.text("nav.\(section.rawValue)"))
                                .font(.system(size: 11.5, weight: model.selectedSection == section ? .semibold : .regular, design: .monospaced))
                                .foregroundStyle(model.selectedSection == section ? palette.ink : palette.mutedInk)
                                .padding(.horizontal, 18)
                                .frame(height: 36)
                                .background(model.selectedSection == section ? palette.surface : palette.sidebar)
                                .overlay(alignment: .bottom) {
                                    if model.selectedSection == section {
                                        Rectangle().fill(palette.accent).frame(height: 2)
                                    }
                                }
                                .overlay(alignment: .trailing) { Rectangle().fill(palette.divider).frame(width: 1) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.selectedSection == section ? .isSelected : [])
                        .id(section)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.selectedSection) { _, section in proxy.scrollTo(section, anchor: .center) }
        }
        .frame(height: 36)
        .background(palette.sidebar)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.divider).frame(height: 1) }
    }
}

private struct LumenWorkspaceHeader: View {
    @ObservedObject var model: WorkspaceViewModel
    let sidebarCollapsed: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 20) {
            Group {
                if sidebarCollapsed {
                    AppBrandIcon(size: 36)
                } else {
                    AppBrandLockup(
                        iconSize: 36,
                        wordmarkWidth: 108,
                        spacing: 9
                    )
                }
            }
            .frame(width: sidebarCollapsed ? 36 : 188, alignment: .leading)

            Rectangle()
                .fill(palette.divider.opacity(0.72))
                .frame(width: 1, height: 28)

            RepositoryTopBar(model: model)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WorkspaceBrandBar: View {
    let compact: Bool
    var iconOnly = false

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if iconOnly {
                    AppBrandIcon(size: 30)
                } else {
                    AppBrandLockup(
                        iconSize: compact ? 34 : 38,
                        wordmarkWidth: compact ? 82 : 96,
                        spacing: 7
                    )
                }
            }
            .padding(.leading, AppThemeLayout.titlebarBrandLeading)
            Spacer(minLength: 8)
        }
        .padding(.trailing, 12)
        .padding(.top, 18)
        .frame(height: 72)
    }
}

private struct RepositoryTopBar: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue

    @ViewBuilder
    var body: some View {
        let palette = AppPalette(colorScheme)
        if AppVisualTheme.resolved(themeRaw) == .lumen {
            GeometryReader { proxy in
                let compact = proxy.size.width < 860
                HStack(spacing: compact ? 10 : 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.repositoryName ?? L10n.text("app.name"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)

                        if !compact, let path = model.snapshot?.rootURL.path {
                            Text(path)
                                .font(.system(size: 10.5))
                                .foregroundStyle(palette.subtleInk)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: compact ? 150 : 230, alignment: .leading)

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
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: AppThemeLayout.topBarHeight)
        } else if AppVisualTheme.resolved(themeRaw) == .console {
            GeometryReader { proxy in
                HStack(spacing: 12) {
                    Text(model.repositoryName ?? L10n.text("app.name"))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .frame(maxWidth: 200, alignment: .leading)
                    if let snapshot = model.snapshot {
                        BranchQuickSwitcher(model: model, snapshot: snapshot)
                    }
                    Spacer(minLength: 4)
                    repositoryActions(palette: palette, compact: true, iconOnly: proxy.size.width < 790)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 42)
        } else if AppVisualTheme.resolved(themeRaw) == .emerald {
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text(L10n.text("nav.\(model.selectedSection.rawValue)"))
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 8)
                        repositoryActions(palette: palette, compact: true, iconOnly: proxy.size.width < 940)
                    }
                    HStack(spacing: 10) {
                        Text(model.repositoryName ?? L10n.text("app.name"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.mutedInk)
                            .lineLimit(1)
                        if let snapshot = model.snapshot {
                            BranchQuickSwitcher(model: model, snapshot: snapshot)
                            RepositorySyncStatusView(state: snapshot.syncState, error: model.liveSyncError)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 102)
        } else if AppVisualTheme.resolved(themeRaw) == .folio {
            GeometryReader { proxy in
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.text("nav.\(model.selectedSection.rawValue)"))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Text(model.repositoryName ?? L10n.text("app.name"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.mutedInk)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 240, alignment: .leading)
                    if let snapshot = model.snapshot {
                        BranchQuickSwitcher(model: model, snapshot: snapshot)
                        RepositorySyncStatusView(state: snapshot.syncState, error: model.liveSyncError)
                    }
                    Spacer(minLength: 4)
                    repositoryActions(palette: palette, compact: true, iconOnly: proxy.size.width < 820)
                }
                .padding(.trailing, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 62)
        } else {
            GeometryReader { proxy in
                let compact = proxy.size.width < 860
                HStack(spacing: compact ? 8 : 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.repositoryName ?? L10n.text("app.name"))
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        if !compact, let path = model.snapshot?.rootURL.path {
                            Text(path)
                                .font(.system(size: 10.5))
                                .foregroundStyle(palette.subtleInk)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: compact ? 140 : 240, alignment: .leading)
                    if let snapshot = model.snapshot {
                        BranchQuickSwitcher(model: model, snapshot: snapshot)
                        RepositorySyncStatusView(state: snapshot.syncState, error: model.liveSyncError)
                    }
                    Spacer(minLength: 4)
                    repositoryActions(palette: palette, compact: compact, iconOnly: proxy.size.width < 790)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: AppThemeLayout.topBarHeight)
        }
    }

    private func repositoryActions(palette: AppPalette, compact: Bool, iconOnly: Bool = false) -> some View {
        HStack(spacing: compact ? 9 : 12) {
            if model.snapshot != nil {
                RemoteSyncButton(
                    titleKey: "action.pull",
                    activity: .pull,
                    compact: compact,
                    iconOnly: iconOnly,
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
                    iconOnly: iconOnly,
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

            if iconOnly {
                ToolbarIconButton(systemName: "folder.badge.plus", helpKey: "action.open_repository") {
                    model.chooseRepository()
                }
            } else {
                Button(L10n.text("action.open_repository")) {
                    model.chooseRepository()
                }
                .buttonStyle(SecondaryButtonStyle())
                .fixedSize(horizontal: true, vertical: false)
            }
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
    var iconOnly = false
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
        iconOnly ? 40 : (compact ? 108 : 120)
    }

    private var leadingPlateWidth: CGFloat {
        iconOnly ? 32 : (isExpanded ? width - 6 : (compact ? 36 : 42))
    }

    private var cornerRadius: CGFloat {
        AppThemeLayout.controlCornerRadius
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            if [.console, .emerald, .folio].contains(AppStyleDefaults.theme) {
                HStack(spacing: 7) {
                    if showsCompletion {
                        GattoIcon(symbol: "checkmark", size: 16)
                    } else if isActive {
                        CloneActivityGlyph(systemImage: syncSymbol, tint: palette.primary, travelsUp: activity == .push)
                            .frame(width: 18, height: 18)
                    } else {
                        GattoIcon(symbol: syncSymbol, size: 17)
                    }
                    if !iconOnly {
                        Text(buttonTitle)
                            .font(.system(size: 11.5, weight: .medium,
                                          design: AppStyleDefaults.theme == .console ? .monospaced : .default))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(showsCompletion ? palette.success : palette.ink)
                .padding(.horizontal, iconOnly ? 9 : 12)
                .frame(height: AppStyleDefaults.theme == .console ? 30 : 34)
                .background(AppStyleDefaults.theme == .folio ? palette.raisedSurface : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    if isActive {
                        CloneProgressBorder(tint: palette.primary, cornerRadius: cornerRadius)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .contentShape(Rectangle())
            } else {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(palette.raisedSurface)
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(palette.divider, lineWidth: 1)
                        }

                    Text(iconOnly ? "" : L10n.text(titleKey))
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
                                if !iconOnly {
                                    Text(buttonTitle).lineLimit(1)
                                }
                            }
                            .font(.system(size: compact ? 10 : 11, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, iconOnly ? 4 : 9)
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
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
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
