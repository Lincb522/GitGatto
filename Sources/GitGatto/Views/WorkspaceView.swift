import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    private var theme: AppVisualTheme {
        AppVisualTheme.resolved(themeRaw)
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
        guard model.snapshot != nil else { return false }
        return switch model.selectedSection {
        case .github:
            model.githubAvailability.state != .checking
                && !model.isLoadingGitHub
                && !model.isLoadingPullRequests
                && !model.isLoadingGitHubReadme
                && !model.isLoadingGitHubContents
                && !model.isLoadingGitHubFile
        case .codex:
            model.codexAvailability.state != .checking
        default:
            true
        }
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        GeometryReader { proxy in
            let compactSidebar = proxy.size.width < 1120
            let sidebarWidth: CGFloat = compactSidebar ? 214 : 238
            ZStack(alignment: .top) {
                if theme == .standard {
                    HStack(spacing: 0) {
                        RepositorySidebar(model: model, appearanceRaw: $appearanceRaw)
                            .frame(width: proxy.size.width < 1120 ? 208 : 232)

                        Rectangle().fill(palette.divider).frame(width: 1)

                        VStack(spacing: 0) {
                            if model.selectedSection != .github {
                                RepositoryTopBar(model: model)
                                Rectangle().fill(palette.divider).frame(height: 1)
                            }
                            workspaceDetail
                        }
                        .background(palette.background)
                    }
                } else {
                    VStack(spacing: AppThemeLayout.panelSpacing) {
                        HStack(spacing: AppThemeLayout.panelSpacing) {
                            WorkspaceBrandBar(compact: compactSidebar)
                                .frame(width: sidebarWidth)
                                .appGlassPanel(cornerRadius: 16, elevated: false)

                            RepositoryTopBar(model: model)
                        }

                        HStack(spacing: AppThemeLayout.panelSpacing) {
                            RepositorySidebar(model: model, appearanceRaw: $appearanceRaw)
                                .frame(width: sidebarWidth)
                                .appGlassPanel()

                            workspaceDetail
                                .background(palette.surface.opacity(0.18))
                                .appGlassPanel()
                        }
                    }
                    .padding(AppThemeLayout.workspaceInset)
                }

                if let operation = model.activeOperation, operation.isRemoteSync {
                    RepositoryOperationBanner(operation: operation)
                        .padding(.top, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(4)
                } else if let notice = model.notice {
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
        .sheet(item: activeErrorBinding) { report in
            GlobalErrorSheet(report: report) {
                model.dismissActiveError()
            }
        }
#if DEBUG
        .background(
            DebugSnapshotCapture(
                isReady: isSnapshotReady
                    && ProcessInfo.processInfo.environment["GITGATTO_SETTINGS_PREVIEW"] != "1"
                    && ProcessInfo.processInfo.environment["GITGATTO_ABOUT_PREVIEW"] != "1"
                    && ProcessInfo.processInfo.environment["GITGATTO_UPDATE_PREVIEW"] != "1"
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
            GitHubWorkspaceView(model: model)
        } else if model.snapshot == nil {
            WelcomeView(model: model)
        } else {
            switch model.selectedSection {
            case .changes:
                ChangesWorkspaceView(model: model)
            case .history:
                HistoryWorkspaceView(model: model)
            case .branches:
                BranchesWorkspaceView(model: model)
            case .github:
                GitHubWorkspaceView(model: model)
            case .codex:
                CodexWorkspaceView(model: model)
            }
        }
    }
}

private struct WorkspaceBrandBar: View {
    let compact: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 0) {
            AppBrandLockup(
                iconSize: compact ? 34 : 38,
                wordmarkWidth: compact ? 82 : 96,
                spacing: 7
            )
            .padding(.leading, compact ? 48 : 52)
            Spacer(minLength: 8)
        }
        .padding(.trailing, 12)
        .frame(height: AppThemeLayout.topBarHeight)
        .background(palette.sidebar.opacity(0.18))
    }
}

private struct RepositoryTopBar: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue

    @ViewBuilder
    var body: some View {
        let palette = AppPalette(colorScheme)
        if AppVisualTheme.resolved(themeRaw) == .standard {
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
                        isMonitoring: model.isLiveRefreshing || model.isCodexRunning,
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
        } else {
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
                            isMonitoring: model.isLiveRefreshing || model.isCodexRunning,
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
        }
    }

    private func repositoryActions(palette: AppPalette, compact: Bool) -> some View {
        HStack(spacing: compact ? 9 : 12) {
            if model.snapshot != nil {
                RemoteSyncButton(
                    titleKey: "action.pull",
                    direction: .down,
                    isActive: model.activeOperation == .pull,
                    isDisabled: model.activeOperation != nil
                ) {
                    Task { await model.pull() }
                }

                RemoteSyncButton(
                    titleKey: "action.push",
                    direction: .up,
                    isActive: model.activeOperation == .push,
                    isDisabled: model.activeOperation != nil
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
                    isActive: model.isRefreshing || model.isLiveRefreshing || model.isCodexRunning,
                    isDisabled: model.isRefreshing
                ) {
                    Task { await model.refresh() }
                }
            }

            Button(L10n.text("action.open_repository")) {
                model.chooseRepository()
            }
            .buttonStyle(SecondaryButtonStyle())
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
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(snapshot.branchName)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
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
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(branch.name == snapshot.branchName ? palette.primary : palette.subtleInk)
                                    .frame(width: 18)
                                Text(branch.name)
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(palette.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if branch.name == snapshot.branchName {
                                    Image(systemName: "checkmark")
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
    let isMonitoring: Bool
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

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 6) {
            if isMonitoring {
                LiveSyncGlyph()
            } else {
                Image(systemName: error == nil ? presentation.icon : "exclamationmark.triangle.fill")
            }
            Text(presentation.text)
        }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(error != nil ? palette.warning : (state == .synced ? palette.success : palette.mutedInk))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 25)
            .background(state == .synced ? palette.successSoft : palette.raisedSurface)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(palette.divider, lineWidth: state == .synced ? 0 : 1)
            }
            .help(error ?? L10n.text(isMonitoring ? "sync.status.monitoring" : "sync.status.live"))
    }
}

private struct LiveSyncGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = 0.0

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 9.5, weight: .bold))
            .rotationEffect(.degrees(rotation))
            .onAppear { updateAnimation() }
            .onChange(of: reduceMotion) { _, _ in updateAnimation() }
    }

    private func updateAnimation() {
        guard !reduceMotion else {
            rotation = 0
            return
        }
        rotation = 0
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

private struct RemoteSyncButton: View {
    let titleKey: String
    let direction: SyncActivityGlyph.Direction
    let isActive: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isActive {
                    SyncActivityGlyph(direction: direction, size: 10)
                } else {
                    Image(systemName: direction == .up ? "arrow.up" : "arrow.down")
                        .font(.system(size: 11.5, weight: .bold))
                }
                Text(L10n.text(isActive ? (direction == .up ? "sync.progress.push" : "sync.progress.pull") : titleKey))
                    .lineLimit(1)
            }
            .font(.system(size: 11.5, weight: .semibold))
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(isDisabled)
        .accessibilityLabel(L10n.text(isActive ? (direction == .up ? "sync.progress.push" : "sync.progress.pull") : titleKey))
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
                                Image(systemName: "folder")
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
                                Image(systemName: "chevron.right")
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
