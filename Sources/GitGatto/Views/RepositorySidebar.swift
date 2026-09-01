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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let palette = AppPalette(colorScheme)
        let theme = AppVisualTheme.resolved(themeRaw)
        let isStandard = theme == .standard
        Group {
            if theme == .folio {
                folioSidebar(palette: palette)
            } else if isCollapsed {
                collapsedSidebar(palette: palette, isStandard: isStandard)
            } else {
                VStack(spacing: 0) {
            HStack(spacing: 8) {
                if isStandard {
                    AppBrandLockup(iconSize: 38, wordmarkWidth: 100, spacing: 8)
                } else {
                    Text(L10n.text("sidebar.navigation"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.mutedInk)
                }
                Spacer(minLength: 4)
                sidebarCollapseButton(palette: palette, collapsed: false)
            }
            .padding(.top, isStandard ? 24 : 8)
            .padding(.horizontal, isStandard ? 16 : 12)
            .frame(height: isStandard ? 72 : 48)

            VStack(spacing: 4) {
                sidebarSectionHeader(
                    titleKey: "sidebar.section.projects",
                    isExpanded: $projectsExpanded,
                    palette: palette
                )
                if projectsExpanded {
                SidebarNavigationButton(
                    titleKey: "nav.github",
                    systemImage: "square.grid.2x2",
                    count: model.githubAccountRepositories.isEmpty ? nil : model.githubAccountRepositories.count,
                    isSelected: model.selectedSection == .github
                ) {
                    model.selectedSection = .github
                }

                SidebarNavigationButton(
                    titleKey: "nav.marketplace",
                    systemImage: "arrow.down.app",
                    isSelected: model.selectedSection == .marketplace
                ) {
                    model.selectedSection = .marketplace
                }

                SidebarNavigationButton(
                    titleKey: "nav.goals",
                    systemImage: "checkmark.seal",
                    count: model.activeProjectGoalCount == 0 ? nil : model.activeProjectGoalCount,
                    isSelected: model.selectedSection == .goals
                ) {
                    model.selectedSection = .goals
                }
                }

                sidebarSectionHeader(
                    titleKey: "sidebar.section.repository",
                    isExpanded: $repositoryToolsExpanded,
                    palette: palette
                )
                if repositoryToolsExpanded {

                SidebarNavigationButton(
                    titleKey: "nav.changes",
                    systemImage: "square.stack.3d.up",
                    count: model.snapshot?.changes.count,
                    isSelected: model.selectedSection == .changes
                ) {
                    model.selectedSection = .changes
                }
                SidebarNavigationButton(
                    titleKey: "nav.stash",
                    systemImage: "archivebox",
                    count: model.stashes.isEmpty ? nil : model.stashes.count,
                    isSelected: model.selectedSection == .stash
                ) {
                    model.selectedSection = .stash
                }
                SidebarNavigationButton(
                    titleKey: "nav.history",
                    systemImage: "clock.arrow.circlepath",
                    count: model.commitGraph.nodes.isEmpty ? nil : model.commitGraph.nodes.count,
                    isSelected: model.selectedSection == .history
                ) {
                    model.selectedSection = .history
                }
                SidebarNavigationButton(
                    titleKey: "nav.timeMachine",
                    systemImage: "history.file",
                    count: model.repositoryFiles.isEmpty ? nil : model.repositoryFiles.count,
                    isSelected: model.selectedSection == .timeMachine
                ) {
                    model.selectedSection = .timeMachine
                }
                SidebarNavigationButton(
                    titleKey: "nav.branches",
                    systemImage: "arrow.triangle.branch",
                    count: model.snapshot?.branches.count,
                    isSelected: model.selectedSection == .branches
                ) {
                    model.selectedSection = .branches
                }
                SidebarNavigationButton(
                    titleKey: "nav.worktrees",
                    systemImage: "rectangle.split.2x1",
                    count: model.worktrees.isEmpty ? nil : model.worktrees.count,
                    isSelected: model.selectedSection == .worktrees
                ) {
                    model.selectedSection = .worktrees
                }
                SidebarNavigationButton(
                    titleKey: "nav.diagnostics",
                    systemImage: "stethoscope",
                    count: model.repositoryDiagnostics?.attentionCount,
                    isSelected: model.selectedSection == .diagnostics
                ) {
                    model.selectedSection = .diagnostics
                }
                }

                sidebarSectionHeader(
                    titleKey: "nav.codex",
                    isExpanded: $agentExpanded,
                    palette: palette
                )
                if agentExpanded {

                SidebarNavigationButton(
                    titleKey: "nav.codex",
                    systemImage: "sparkles",
                    isSelected: model.selectedSection == .codex
                ) {
                    model.selectedSection = .codex
                }
                }
            }
            .padding(.horizontal, isStandard ? 10 : 12)
            .padding(.top, isStandard ? 6 : 14)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Button {
                        localRepositoriesExpanded.toggle()
                    } label: {
                        HStack(spacing: 6) {
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
                    Spacer()
                    Menu {
                        Button(L10n.text("action.open_repository")) {
                            model.chooseRepository()
                        }
                        Button(L10n.text("repository.scan.open")) {
                            openWindow(id: "repository-scanner")
                        }
                    } label: {
                        Color.clear
                            .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .overlay {
                        Group {
                            if model.isScanningRepositories {
                                GattoLoadingGlyph(size: 20)
                            } else {
                                GattoIcon(symbol: "folder.badge.plus", size: 22)
                                    .foregroundStyle(palette.ink)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .fixedSize()
                    .help(L10n.text("action.open_repository"))
                }
                .padding(.horizontal, 10)

                if localRepositoriesExpanded {
                if model.localRepositories.isEmpty {
                    Text(L10n.text("repository.scan.empty"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.subtleInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.top, 3)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(model.repositoryCatalogSections) { section in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(L10n.text(section.kind.titleKey))
                                            .font(.system(size: 9.5, weight: .semibold))
                                            .foregroundStyle(palette.subtleInk)
                                        Spacer()
                                        Text(String(section.repositories.count))
                                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                            .foregroundStyle(palette.subtleInk)
                                    }
                                    .padding(.horizontal, 10)

                                    ForEach(section.repositories) { record in
                                        let url = record.url
                                        RepositoryCatalogButton(
                                            record: record,
                                            isCurrent: model.snapshot?.rootURL.standardizedFileURL == url.standardizedFileURL,
                                            reveal: {
                                                NSWorkspace.shared.activateFileViewerSelecting([url])
                                            },
                                            copyPath: {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(url.path, forType: .string)
                                            },
                                            remove: {
                                                model.removeLocalRepository(url)
                                            }
                                        ) {
                                            Task { await model.openRepository(url) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                }
            }
            .padding(.horizontal, isStandard ? 10 : 12)
            .padding(.top, isStandard ? 24 : 16)
            .frame(maxHeight: .infinity, alignment: .top)

            HStack(spacing: 8) {
                AppearanceControl(selection: $appearanceRaw)

                Button {
                    openSettings()
                } label: {
                    sidebarUtilityIcon("gearshape", palette: palette)
                }
                .buttonStyle(.plain)
                .help(L10n.text("ai.settings.title"))

                Button {
                    openWindow(id: "about")
                } label: {
                    sidebarUtilityIcon("info.circle", palette: palette)
                }
                .buttonStyle(.plain)
                .help(L10n.text("about.title"))
            }
            .padding(.horizontal, isStandard ? 12 : 14)
            .padding(.bottom, isStandard ? 13 : 14)
                }
            }
        }
        .background(palette.sidebar)
        .animation(.easeInOut(duration: 0.18), value: isCollapsed)
    }

    private func folioSidebar(palette: AppPalette) -> some View {
        VStack(spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(collapsedSections) { section in
                        FolioRailNavigationButton(
                            section: section,
                            isSelected: model.selectedSection == section,
                            count: count(for: section)
                        ) {
                            model.selectedSection = section
                        }
                    }
                }
                .padding(.top, 54)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: .infinity)
            .folioSurface(.rail, cornerRadius: 22)

            VStack(spacing: 5) {
                Menu {
                    ForEach(model.localRepositories, id: \.standardizedFileURL.path) { url in
                        Button(url.lastPathComponent) {
                            Task { await model.openRepository(url) }
                        }
                    }
                    if !model.localRepositories.isEmpty { Divider() }
                    Button(L10n.text("action.open_repository")) { model.chooseRepository() }
                    Button(L10n.text("repository.scan.open")) { openWindow(id: "repository-scanner") }
                } label: {
                    Color.clear
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .overlay {
                    Image(gattoSymbol: "folder.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .allowsHitTesting(false)
                }
                .fixedSize()
                .help(L10n.text("sidebar.repositories"))

                Button { openSettings() } label: {
                    Image(gattoSymbol: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.ink)
                .help(L10n.text("settings.title"))

                Button { openWindow(id: "about") } label: {
                    Image(gattoSymbol: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.ink)
                .help(L10n.text("about.title"))
            }
            .padding(.vertical, 7)
            .frame(width: 58)
            .folioSurface(.rail, cornerRadius: 22)
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

    private func collapsedSidebar(palette: AppPalette, isStandard: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                AppBrandIcon(size: 26)
                sidebarCollapseButton(palette: palette, collapsed: true)
            }
            .padding(.top, isStandard ? 24 : 7)
            .frame(height: isStandard ? 70 : 46)

            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)
                .padding(.horizontal, 8)

            ScrollView {
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
                .padding(.vertical, 4)
            }

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
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
    }

    private var collapsedSections: [WorkspaceSection] {
        [.github, .marketplace, .goals, .changes, .stash, .history, .timeMachine, .branches, .worktrees, .diagnostics, .codex]
    }

    private func count(for section: WorkspaceSection) -> Int? {
        switch section {
        case .github: model.githubAccountRepositories.count
        case .marketplace: nil
        case .goals: model.activeProjectGoalCount
        case .changes: model.snapshot?.changes.count
        case .stash: model.stashes.count
        case .history: model.commitGraph.nodes.count
        case .timeMachine: model.repositoryFiles.count
        case .branches: model.snapshot?.branches.count
        case .worktrees: model.worktrees.count
        case .diagnostics: model.repositoryDiagnostics?.attentionCount
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
        let isStandard = AppVisualTheme.resolved(themeRaw) == .standard
        return Image(gattoSymbol: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.mutedInk)
            .frame(width: isStandard ? 32 : 34, height: isStandard ? 32 : 34)
            .background(palette.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                    .stroke(
                        isStandard
                            ? palette.divider
                            : Color.white.opacity(colorScheme == .dark ? 0.10 : 0.62),
                        lineWidth: 1
                    )
            }
    }
}

private struct FolioRailNavigationButton: View {
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.sidebar : palette.ink)
                    .frame(width: 38, height: 38)
                    .background(isSelected ? palette.ink : Color.clear)
                    .clipShape(Circle())

                if let count, count > 0 {
                    Circle()
                        .fill(palette.warning)
                        .frame(width: 6, height: 6)
                        .overlay { Circle().stroke(palette.sidebar, lineWidth: 1) }
                        .offset(x: -2, y: 2)
                }
            }
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
        case .stash: "archivebox"
        case .history: "clock.arrow.circlepath"
        case .timeMachine: "history.file"
        case .branches: "arrow.triangle.branch"
        case .worktrees: "rectangle.split.2x1"
        case .diagnostics: "stethoscope"
        case .codex: "sparkles"
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
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

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
        case .stash: "archivebox"
        case .history: "clock.arrow.circlepath"
        case .timeMachine: "history.file"
        case .branches: "arrow.triangle.branch"
        case .worktrees: "rectangle.split.2x1"
        case .diagnostics: "stethoscope"
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
        Button(action: action) {
            HStack(spacing: 10) {
                Image(gattoSymbol: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? palette.primary : palette.mutedInk)
                Text(L10n.text(titleKey))
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? palette.ink : palette.mutedInk)
                Spacer()
                if let count, count > 0 {
                    CountBadge(count: count, emphasized: isSelected)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .contentShape(Rectangle())
            .background(isSelected ? palette.primarySoft : (isHovering ? palette.raisedSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                    .stroke(
                        isSelected ? palette.primary.opacity(0.24) : Color.clear,
                        lineWidth: 1
                    )
            }
            .shadow(color: isSelected ? palette.primary.opacity(0.08) : .clear, radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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
