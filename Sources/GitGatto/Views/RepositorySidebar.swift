import AppKit
import SwiftUI

struct RepositorySidebar: View {
    @ObservedObject var model: WorkspaceViewModel
    @Binding var appearanceRaw: String
    @Binding var isCollapsed: Bool
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @AppStorage("sidebar.projects.expanded") private var projectsExpanded = true
    @AppStorage("sidebar.repository.expanded") private var repositoryToolsExpanded = true
    @AppStorage("sidebar.agent.expanded") private var agentExpanded = true
    @AppStorage("sidebar.local.expanded") private var localRepositoriesExpanded = true
    @AppStorage("sidebar.local.active.expanded") private var activeRepositoriesExpanded = true
    @AppStorage("sidebar.local.recent.expanded") private var recentRepositoriesExpanded = true
    @AppStorage("sidebar.local.earlier.expanded") private var earlierRepositoriesExpanded = false
    @State private var repositoryQuery = ""
    @State private var fullyExpandedRepositorySections = Set<String>()
    @State private var showsRepositorySwitcher = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let palette = AppPalette(colorScheme)
        let theme = AppVisualTheme.resolved(themeRaw)
        let showsBrand = theme != .lumen && theme != .folio
        Group {
            if theme == .folio {
                folioSidebar(palette: palette)
            } else if theme == .console {
                consoleSidebar(palette: palette)
            } else if isCollapsed {
                collapsedSidebar(
                    palette: palette,
                    clearsWindowControls: showsBrand,
                    showsBrandIcon: showsBrand
                )
            } else {
                expandedSidebar(palette: palette, showsBrand: showsBrand)
            }
        }
        .background(theme == .lumen || theme == .folio ? Color.clear : palette.sidebar)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: isCollapsed)
    }

    private func consoleSidebar(palette: AppPalette) -> some View {
        HStack(spacing: 0) {
            collapsedSidebar(palette: palette, clearsWindowControls: false, showsBrandIcon: false)
                .frame(width: 54)
            if !isCollapsed {
                Rectangle().fill(palette.divider).frame(width: 1)
                repositorySwitcher(palette: palette, inline: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func expandedSidebar(palette: AppPalette, showsBrand: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if showsBrand {
                    AppBrandLockup(iconSize: 30, wordmarkWidth: 80, spacing: 7)
                } else {
                    Text(L10n.text("sidebar.navigation"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.ink)
                }
                Spacer(minLength: 8)
                sidebarCollapseButton(palette: palette, collapsed: false)
            }
            .padding(.top, showsBrand ? 23 : 8)
            .padding(.horizontal, 14)
            .frame(height: showsBrand ? (AppStyleDefaults.theme == .emerald ? 90 : 82) : 50)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(palette.divider)
                    .frame(height: 1)
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: AppStyleDefaults.theme == .console ? 10 : 18) {
                        projectNavigation(palette: palette)
                        localRepositoryNavigation(palette: palette)
                        repositoryNavigation(palette: palette)
                        agentNavigation(palette: palette)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.visible)
                .onChange(of: model.selectedSection) { _, section in
                    let scroll = { proxy.scrollTo(navigationID(section), anchor: .center) }
                    if reduceMotion {
                        scroll()
                    } else {
                        withAnimation(.easeOut(duration: 0.20), scroll)
                    }
                }
            }

            sidebarFooter(palette: palette, showsBrand: showsBrand)
        }
    }

    private func projectNavigation(palette: AppPalette) -> some View {
        VStack(spacing: 4) {
            sidebarSectionHeader(
                titleKey: "sidebar.section.projects",
                isExpanded: $projectsExpanded,
                palette: palette
            )
            if projectsExpanded {
                navigationButton(
                    .github,
                    titleKey: "nav.github",
                    systemImage: "square.grid.2x2",
                    count: model.githubAccountRepositories.isEmpty ? nil : model.githubAccountRepositories.count
                )
                navigationButton(.marketplace, titleKey: "nav.marketplace", systemImage: "arrow.down.app")
                navigationButton(
                    .goals,
                    titleKey: "nav.goals",
                    systemImage: "checkmark.seal",
                    count: model.activeProjectGoalCount == 0 ? nil : model.activeProjectGoalCount
                )
            }
        }
    }

    private func repositoryNavigation(palette: AppPalette) -> some View {
        VStack(spacing: 4) {
            sidebarSectionHeader(
                titleKey: "sidebar.section.repository",
                isExpanded: $repositoryToolsExpanded,
                palette: palette
            )
            if repositoryToolsExpanded {
                navigationButton(.changes, titleKey: "nav.changes", systemImage: "square.stack.3d.up", count: model.snapshot?.changes.count)
                navigationButton(.intelligence, titleKey: "nav.intelligence", systemImage: "point.3.connected.trianglepath.dotted")
                navigationButton(.stash, titleKey: "nav.stash", systemImage: "archivebox", count: model.stashes.isEmpty ? nil : model.stashes.count)
                navigationButton(.history, titleKey: "nav.history", systemImage: "clock.arrow.circlepath", count: model.commitGraph.nodes.isEmpty ? nil : model.commitGraph.nodes.count)
                navigationButton(.timeMachine, titleKey: "nav.timeMachine", systemImage: "history.file", count: model.repositoryFiles.isEmpty ? nil : model.repositoryFiles.count)
                navigationButton(.recovery, titleKey: "nav.recovery", systemImage: "clock.badge.checkmark", count: model.repositoryBackups.isEmpty ? nil : model.repositoryBackups.count)
                navigationButton(.branches, titleKey: "nav.branches", systemImage: "arrow.triangle.branch", count: model.snapshot?.branches.count)
                navigationButton(.worktrees, titleKey: "nav.worktrees", systemImage: "rectangle.split.2x1", count: model.worktrees.isEmpty ? nil : model.worktrees.count)
                navigationButton(.diagnostics, titleKey: "nav.diagnostics", systemImage: "stethoscope", count: model.repositoryDiagnostics?.attentionCount)
                navigationButton(
                    .regression,
                    titleKey: "nav.regression",
                    systemImage: "record.circle",
                    count: model.activeRegressionInvestigationCount == 0 ? nil : model.activeRegressionInvestigationCount
                )
            }
        }
    }

    private func agentNavigation(palette: AppPalette) -> some View {
        VStack(spacing: 4) {
            sidebarSectionHeader(titleKey: "nav.codex", isExpanded: $agentExpanded, palette: palette)
            if agentExpanded {
                navigationButton(.codex, titleKey: "nav.codex", systemImage: "sparkles")
            }
        }
    }

    private func navigationButton(
        _ section: WorkspaceSection,
        titleKey: String,
        systemImage: String,
        count: Int? = nil
    ) -> some View {
        SidebarNavigationButton(
            titleKey: titleKey,
            systemImage: systemImage,
            count: count,
            isSelected: model.selectedSection == section
        ) {
            model.selectedSection = section
        }
        .id(navigationID(section))
    }

    private func navigationID(_ section: WorkspaceSection) -> String {
        "sidebar-navigation-\(section.rawValue)"
    }

    private func localRepositoryNavigation(palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Button {
                    localRepositoriesExpanded.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(gattoSymbol: localRepositoriesExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 12)
                        Text(L10n.text("sidebar.repositories"))
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(palette.subtleInk)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !model.localRepositories.isEmpty {
                    CountBadge(count: model.localRepositories.count, emphasized: false)
                }

                Spacer(minLength: 4)
                repositoryMenu(palette: palette)
            }
            .padding(.leading, 8)

            if localRepositoriesExpanded {
                if model.localRepositories.isEmpty {
                    Text(L10n.text("repository.scan.empty"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.subtleInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                } else {
                    Button {
                        showsRepositorySwitcher.toggle()
                    } label: {
                        HStack(spacing: 9) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(palette.primarySoft)
                                GattoIcon(symbol: "folder", size: 17)
                                    .foregroundStyle(palette.primary)
                            }
                            .frame(width: 30, height: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.repositoryName ?? L10n.text("action.open_repository"))
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(palette.ink)
                                    .lineLimit(1)
                                Text(L10n.text("sidebar.repositories.switch"))
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(palette.subtleInk)
                            }
                            Spacer(minLength: 4)
                            Image(gattoSymbol: "chevron.right")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(palette.subtleInk)
                        }
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(palette.raisedSurface.opacity(0.66))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(palette.divider, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showsRepositorySwitcher, arrowEdge: .trailing) {
                        repositorySwitcher(palette: palette)
                    }
                }
            }
        }
    }

    private func repositorySwitcher(palette: AppPalette, inline: Bool = false) -> some View {
        let catalog = LocalRepositoryCatalog.sidebarCatalog(
            sections: model.repositoryCatalogSections,
            currentRepositoryPath: model.snapshot?.rootURL.path,
            query: repositoryQuery
        )

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(L10n.text("sidebar.repositories"))
                    .font(.system(size: inline ? 12 : 15, weight: .semibold, design: AppStyleDefaults.theme == .console ? .monospaced : .default))
                    .lineLimit(1)
                    .foregroundStyle(palette.ink)
                CountBadge(count: model.localRepositories.count, emphasized: false)
                Spacer(minLength: 8)
                repositoryMenu(palette: palette)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 48)

            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)

            SidebarRepositorySearchField(text: $repositoryQuery)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    if catalog.isEmpty {
                        Text(L10n.text("sidebar.repositories.no_match"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.subtleInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    } else if repositoryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if let currentRepository = catalog.currentRepository {
                            currentRepositoryBlock(currentRepository, palette: palette)
                        }
                        ForEach(catalog.sections) { section in
                            repositoryCatalogSection(section, palette: palette)
                        }
                    } else {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            if let currentRepository = catalog.currentRepository {
                                repositoryRow(currentRepository, isCurrent: true)
                            }
                            ForEach(catalog.sections.flatMap(\.repositories)) { record in
                                repositoryRow(record, isCurrent: false)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.visible)
        }
        .frame(width: inline ? nil : 310, height: inline ? nil : 480)
        .background(palette.sidebar)
        .onDisappear {
            repositoryQuery = ""
        }
    }

    private func currentRepositoryBlock(
        _ record: LocalRepositoryRecord,
        palette: AppPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.text("sidebar.repositories.current"))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(palette.subtleInk)
                .padding(.horizontal, 8)
            repositoryRow(record, isCurrent: true)
        }
    }

    private func repositoryCatalogSection(
        _ section: RepositoryCatalogSection,
        palette: AppPalette
    ) -> some View {
        let isExpanded = repositorySectionIsExpanded(section.kind)
        let isFullyExpanded = fullyExpandedRepositorySections.contains(section.id)
        let displayLimit = 4
        let visibleRepositories = isFullyExpanded
            ? section.repositories
            : Array(section.repositories.prefix(displayLimit))
        let hiddenCount = max(0, section.repositories.count - visibleRepositories.count)

        return VStack(alignment: .leading, spacing: 3) {
            Button {
                setRepositorySection(section.kind, expanded: !isExpanded)
            } label: {
                HStack(spacing: 6) {
                    Image(gattoSymbol: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .frame(width: 11)
                    Text(L10n.text(section.kind.titleKey))
                        .font(.system(size: 9.5, weight: .semibold))
                    Spacer(minLength: 4)
                    Text(String(section.repositories.count))
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                }
                .foregroundStyle(palette.subtleInk)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(visibleRepositories) { record in
                    repositoryRow(record, isCurrent: false)
                }

                if hiddenCount > 0 || isFullyExpanded {
                    Button {
                        if isFullyExpanded {
                            fullyExpandedRepositorySections.remove(section.id)
                        } else {
                            fullyExpandedRepositorySections.insert(section.id)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(gattoSymbol: isFullyExpanded ? "chevron.compact.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                            Text(
                                isFullyExpanded
                                    ? L10n.text("sidebar.repositories.show_less")
                                    : L10n.format("sidebar.repositories.show_more", hiddenCount)
                            )
                                .font(.system(size: 10.5, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(palette.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func repositoryRow(
        _ record: LocalRepositoryRecord,
        isCurrent: Bool
    ) -> some View {
        let url = record.url
        return RepositoryCatalogButton(
            record: record,
            isCurrent: isCurrent,
            reveal: { NSWorkspace.shared.activateFileViewerSelecting([url]) },
            copyPath: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            },
            remove: { model.removeLocalRepository(url) }
        ) {
            showsRepositorySwitcher = false
            Task { await model.openRepository(url) }
        }
    }

    private func repositorySectionIsExpanded(_ kind: RepositoryCatalogSectionKind) -> Bool {
        switch kind {
        case .active: activeRepositoriesExpanded
        case .recent: recentRepositoriesExpanded
        case .earlier: earlierRepositoriesExpanded
        }
    }

    private func setRepositorySection(_ kind: RepositoryCatalogSectionKind, expanded: Bool) {
        switch kind {
        case .active: activeRepositoriesExpanded = expanded
        case .recent: recentRepositoriesExpanded = expanded
        case .earlier: earlierRepositoriesExpanded = expanded
        }
    }

    private func repositoryMenu(palette: AppPalette) -> some View {
        Menu {
            Button(L10n.text("action.open_repository")) { model.chooseRepository() }
            Button(L10n.text("repository.scan.open")) { openWindow(id: "repository-scanner") }
        } label: {
            Color.clear
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .overlay {
            Group {
                if model.isScanningRepositories {
                    GattoLoadingGlyph(size: 18)
                } else {
                    GattoIcon(symbol: "folder.badge.plus", size: 20)
                        .foregroundStyle(palette.ink)
                }
            }
            .allowsHitTesting(false)
        }
        .fixedSize()
        .help(L10n.text("action.open_repository"))
    }

    private func sidebarFooter(palette: AppPalette, showsBrand: Bool) -> some View {
        HStack(spacing: 8) {
            AppearanceControl(selection: $appearanceRaw)

            Button { openSettings() } label: {
                sidebarUtilityIcon("gearshape", palette: palette)
            }
            .buttonStyle(.plain)
            .help(L10n.text("ai.settings.title"))

            Button { openWindow(id: "about") } label: {
                sidebarUtilityIcon("info.circle", palette: palette)
            }
            .buttonStyle(.plain)
            .help(L10n.text("about.title"))
        }
        .padding(.horizontal, AppStyleDefaults.theme == .lumen ? 14 : 8)
        .padding(.top, 9)
        .padding(.bottom, showsBrand ? 13 : 14)
        .background(palette.sidebar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func folioSidebar(palette: AppPalette) -> some View {
        if isCollapsed {
            collapsedSidebar(palette: palette, clearsWindowControls: false, showsBrandIcon: false)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text(L10n.text("sidebar.navigation"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.subtleInk)
                    Spacer()
                    sidebarCollapseButton(palette: palette, collapsed: false)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)

                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            localRepositoryNavigation(palette: palette)
                            projectNavigation(palette: palette)
                            repositoryNavigation(palette: palette)
                            agentNavigation(palette: palette)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 18)
                    }
                    .scrollIndicators(.visible)
                    .onChange(of: model.selectedSection) { _, section in
                        let scroll = { proxy.scrollTo(navigationID(section), anchor: .center) }
                        if reduceMotion {
                            scroll()
                        } else {
                            withAnimation(.easeOut(duration: 0.20), scroll)
                        }
                    }
                }

                HStack(spacing: 8) {
                    railAppearanceMenu(palette: palette)
                    Spacer(minLength: 8)
                    Button { openSettings() } label: {
                        sidebarUtilityIcon("gearshape", palette: palette)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.text("settings.title"))
                    Button { openWindow(id: "about") } label: {
                        sidebarUtilityIcon("info.circle", palette: palette)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.text("about.title"))
                }
                .padding(.horizontal, 12)
                .frame(height: 52)
                .overlay(alignment: .top) {
                    Rectangle().fill(palette.divider).frame(height: 1)
                        .padding(.horizontal, 12)
                }
            }
        }
    }

    private func sidebarSectionHeader(
        titleKey: String,
        isExpanded: Binding<Bool>,
        palette: AppPalette
    ) -> some View {
        Button {
            isExpanded.wrappedValue.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(gattoSymbol: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 12)
                Text(L10n.text(titleKey))
                    .font(.system(size: 10.5, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.subtleInk)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func collapsedSidebar(
        palette: AppPalette,
        clearsWindowControls: Bool,
        showsBrandIcon: Bool
    ) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: showsBrandIcon ? 7 : 0) {
                if showsBrandIcon {
                    AppBrandIcon(size: 27)
                        .accessibilityHidden(true)
                }
                sidebarCollapseButton(palette: palette, collapsed: isCollapsed)
            }
            .padding(.top, clearsWindowControls ? 23 : 8)
            .padding(.bottom, showsBrandIcon ? 9 : 0)
            .frame(height: showsBrandIcon ? 104 : 50)

            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)

            ScrollView(.vertical) {
                VStack(spacing: 5) {
                    ForEach(collapsedSections) { section in
                        CollapsedSidebarNavigationButton(
                            section: section,
                            isSelected: model.selectedSection == section,
                            count: count(for: section)
                        ) {
                            model.selectedSection = section
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: .infinity)

            VStack(spacing: 6) {
                if [.console, .folio].contains(AppStyleDefaults.theme) { railAppearanceMenu(palette: palette) }
                Menu {
                    ForEach(model.localRepositories, id: \.standardizedFileURL.path) { url in
                        Button(url.lastPathComponent) {
                            Task { await model.openRepository(url) }
                        }
                    }
                    if !model.localRepositories.isEmpty {
                        Divider()
                    }
                    Button(L10n.text("action.open_repository")) { model.chooseRepository() }
                    Button(L10n.text("repository.scan.open")) { openWindow(id: "repository-scanner") }
                } label: {
                    Color.clear
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .overlay {
                    sidebarUtilityIcon("folder.badge.plus", palette: palette)
                        .allowsHitTesting(false)
                }
                .fixedSize()
                .frame(height: [.console, .emerald, .folio].contains(AppStyleDefaults.theme) ? 34 : nil)
                .help(L10n.text("sidebar.repositories"))

                Button { openSettings() } label: {
                    sidebarUtilityIcon("gearshape", palette: palette)
                }
                .buttonStyle(.plain)
                .help(L10n.text("settings.title"))

                Button { openWindow(id: "about") } label: {
                    sidebarUtilityIcon("info.circle", palette: palette)
                }
                .buttonStyle(.plain)
                .help(L10n.text("about.title"))
            }
            .padding(.top, 9)
            .padding(.bottom, 12)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(palette.divider)
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, 8)
    }

    private func railAppearanceMenu(palette: AppPalette) -> some View {
        Menu {
            Picker(L10n.text("settings.appearance.mode"), selection: $appearanceRaw) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(L10n.text("appearance.\(appearance.rawValue)")).tag(appearance.rawValue)
                }
            }
        } label: {
            Color.clear
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 34, height: 34)
        .fixedSize()
        .overlay {
            GattoIcon(symbol: "circle.lefthalf.filled", size: 17)
                .foregroundStyle(palette.ink)
                .allowsHitTesting(false)
        }
        .help(L10n.text("settings.appearance.mode"))
        .accessibilityLabel(L10n.text("settings.appearance.mode"))
    }

    private var collapsedSections: [WorkspaceSection] {
        [.github, .marketplace, .goals, .changes, .intelligence, .stash, .history, .timeMachine, .recovery, .branches, .worktrees, .diagnostics, .regression, .codex]
    }

    private func count(for section: WorkspaceSection) -> Int? {
        switch section {
        case .github: model.githubAccountRepositories.count
        case .marketplace: nil
        case .goals: model.activeProjectGoalCount
        case .changes: model.snapshot?.changes.count
        case .intelligence: nil
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

    private func sidebarCollapseButton(palette: AppPalette, collapsed: Bool) -> some View {
        Button {
            isCollapsed.toggle()
        } label: {
            Image(gattoSymbol: collapsed ? "chevron.right" : "chevron.left")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.mutedInk)
                .frame(width: 28, height: 28)
                .background(palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(palette.divider, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(L10n.text(collapsed ? "sidebar.expand" : "sidebar.collapse"))
    }

    private func sidebarUtilityIcon(_ systemName: String, palette: AppPalette) -> some View {
        let theme = AppVisualTheme.resolved(themeRaw)
        let isStandard = theme == .standard
        return Image(gattoSymbol: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.mutedInk)
            .frame(width: isStandard ? 32 : 34, height: isStandard ? 32 : 34)
            .background(theme == .folio ? Color.clear : palette.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                    .stroke(
                        theme == .folio ? Color.clear : isStandard
                            ? palette.divider
                            : Color.white.opacity(colorScheme == .dark ? 0.10 : 0.62),
                        lineWidth: 1
                    )
            }
    }
}

private struct CollapsedSidebarNavigationButton: View {
    let section: WorkspaceSection
    let isSelected: Bool
    let count: Int?
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(gattoSymbol: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.primary : palette.mutedInk)
                    .frame(width: 38, height: 36)
                    .background(isSelected ? palette.primarySoft : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: AppStyleDefaults.theme == .console ? 3 : 9, style: .continuous))

                if let count, count > 0 {
                    Circle()
                        .fill(palette.primary)
                        .frame(width: 6, height: 6)
                        .overlay { Circle().stroke(palette.sidebar, lineWidth: 1) }
                        .offset(x: -3, y: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.text("nav.\(section.rawValue)"))
        .accessibilityLabel(L10n.text("nav.\(section.rawValue)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var icon: String {
        switch section {
        case .github: "square.grid.2x2"
        case .marketplace: "arrow.down.app"
        case .goals: "checkmark.seal"
        case .changes: "square.stack.3d.up"
        case .intelligence: "point.3.connected.trianglepath.dotted"
        case .stash: "archivebox"
        case .history: "clock.arrow.circlepath"
        case .timeMachine: "history.file"
        case .recovery: "clock.badge.checkmark"
        case .branches: "arrow.triangle.branch"
        case .worktrees: "rectangle.split.2x1"
        case .diagnostics: "stethoscope"
        case .regression: "record.circle"
        case .codex: "sparkles"
        }
    }
}

private struct SidebarNavigationButton: View {
    let titleKey: String
    let systemImage: String
    var count: Int?
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        let theme = AppStyleDefaults.theme
        let isLumen = theme == .lumen
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    if theme == .softGlass {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? palette.primary.opacity(0.12) : palette.raisedSurface.opacity(0.72))
                    }
                    Image(gattoSymbol: systemImage)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(isSelected ? palette.primary : palette.mutedInk)
                }
                .frame(width: 28, height: 28)
                Text(L10n.text(titleKey))
                    .font(.system(size: theme == .console ? 12 : 13, weight: isSelected ? .semibold : .medium, design: theme == .console ? .monospaced : .default))
                    .foregroundStyle(isSelected ? palette.ink : palette.mutedInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Spacer()
                if let count, count > 0 {
                    if theme == .folio {
                        Text(count.formatted())
                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(palette.subtleInk)
                    } else {
                        CountBadge(count: count, emphasized: isSelected)
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: isLumen ? 40 : (theme == .console ? 34 : (theme == .emerald ? 44 : 38)))
            .contentShape(Rectangle())
            .background(isSelected ? ((isLumen || theme == .folio || theme == .emerald) ? palette.raisedSurface : palette.primarySoft) : (isHovering ? palette.raisedSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                    .stroke(
                        isSelected && (isLumen || theme == .softGlass || theme == .folio) ? ((isLumen || theme == .folio) ? palette.divider : palette.primary.opacity(0.24)) : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct RepositoryCatalogButton: View {
    let record: LocalRepositoryRecord
    let isCurrent: Bool
    let reveal: () -> Void
    let copyPath: () -> Void
    let remove: () -> Void
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var url: URL { record.url }

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 9) {
                Circle()
                    .fill(isCurrent ? palette.primary : palette.divider)
                    .frame(width: 6, height: 6)
                Text(url.lastPathComponent)
                    .font(.system(size: 11.5, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(isCurrent ? palette.ink : palette.mutedInk)
                    .lineLimit(1)
                Spacer()
                Text(
                    record.sortDate.formatted(
                        .relative(presentation: .numeric, unitsStyle: .abbreviated)
                    )
                )
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(isCurrent ? palette.primarySoft.opacity(0.64) : (isHovering ? palette.raisedSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(url.path)
        .contextMenu {
            Button(L10n.text("action.open"), action: action)
            Button(L10n.text("action.reveal_finder"), action: reveal)
            Button(L10n.text("action.copy_path"), action: copyPath)
            Divider()
            Button(L10n.text("action.remove_repository"), role: .destructive, action: remove)
        }
    }
}

private struct SidebarRepositorySearchField: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 7) {
            Image(gattoSymbol: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.subtleInk)

            TextField(L10n.text("sidebar.repositories.search"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(gattoSymbol: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.subtleInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("sidebar.repositories.clear_search"))
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 31)
        .background(palette.raisedSurface.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.divider, lineWidth: 1)
        }
        .padding(.horizontal, 2)
    }
}

private struct AppearanceControl: View {
    @Binding var selection: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 2) {
            appearanceButton(.system, systemImage: "circle.lefthalf.filled")
            appearanceButton(.light, systemImage: "sun.max")
            appearanceButton(.dark, systemImage: "moon")
        }
        .padding(3)
        .background(palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.62), lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private func appearanceButton(_ appearance: AppAppearance, systemImage: String) -> some View {
        let palette = AppPalette(colorScheme)
        let isSelected = selection == appearance.rawValue
        return Button {
            selection = appearance.rawValue
        } label: {
            Image(gattoSymbol: systemImage)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isSelected ? palette.primary : palette.subtleInk)
                .frame(maxWidth: .infinity)
                .frame(height: 25)
                .background(isSelected ? palette.primarySoft : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(L10n.text("appearance.\(appearance.rawValue)"))
    }
}
