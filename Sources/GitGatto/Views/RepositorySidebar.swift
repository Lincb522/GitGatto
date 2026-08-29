import AppKit
import SwiftUI

struct RepositorySidebar: View {
    @ObservedObject var model: WorkspaceViewModel
    @Binding var appearanceRaw: String
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let palette = AppPalette(colorScheme)
        let isStandard = AppVisualTheme.resolved(themeRaw) == .standard
        VStack(spacing: 0) {
            if isStandard {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 24)
                    AppBrandLockup(iconSize: 40, wordmarkWidth: 108, spacing: 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                }
                .frame(height: 72)
            }

            VStack(spacing: 4) {
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

                Rectangle()
                    .fill(palette.divider)
                    .frame(height: 1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)

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
                    systemImage: "clock.badge.checkmark",
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

                Rectangle()
                    .fill(palette.divider)
                    .frame(height: 1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)

                SidebarNavigationButton(
                    titleKey: "nav.codex",
                    systemImage: "sparkles",
                    isSelected: model.selectedSection == .codex
                ) {
                    model.selectedSection = .codex
                }
            }
            .padding(.horizontal, isStandard ? 10 : 12)
            .padding(.top, isStandard ? 6 : 14)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(L10n.text("sidebar.repositories"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.subtleInk)
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
                        ZStack {
                            if model.isScanningRepositories {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(gattoSymbol: "folder.badge.plus")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(palette.subtleInk)
                            }
                        }
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(L10n.text("action.open_repository"))
                }
                .padding(.horizontal, 10)

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
        .background(palette.sidebar)
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
            appearanceButton(.system, image: "circle.lefthalf.filled")
            appearanceButton(.light, image: "sun.max")
            appearanceButton(.dark, image: "moon")
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

    private func appearanceButton(_ appearance: AppAppearance, image: String) -> some View {
        let palette = AppPalette(colorScheme)
        let isSelected = selection == appearance.rawValue
        return Button {
            selection = appearance.rawValue
        } label: {
            Image(gattoSymbol: image)
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
