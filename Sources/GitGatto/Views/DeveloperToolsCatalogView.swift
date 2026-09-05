import SwiftUI

struct DeveloperToolsCatalogView: View {
    @StateObject private var observation: DeveloperToolsObservation
    private var developerTools: DeveloperToolsViewModel { observation.model }

    init(developerTools: DeveloperToolsViewModel, downloads: AppDownloadManager,
         activeDownloadCount: Int, catalogSection: Binding<MarketplaceCatalogSection>) {
        _observation = StateObject(wrappedValue: DeveloperToolsObservation(model: developerTools, scope: .catalog))
        self.downloads = downloads
        self.activeDownloadCount = activeDownloadCount
        _catalogSection = catalogSection
    }
    let downloads: AppDownloadManager
    let activeDownloadCount: Int
    @Binding var catalogSection: MarketplaceCatalogSection
    @Environment(\.colorScheme) private var colorScheme
    @State private var pendingToolInstall: DevelopmentTool?
    @State private var pendingToolUpgrade: DevelopmentTool?
    @State private var showsBatchUpgradeConfirmation = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        MarketplaceWorkspaceLayout {
            MarketplaceCatalogHeader(section: $catalogSection, activeDownloadCount: activeDownloadCount,
                                     showDownloads: { downloads.isPresented = true }) { compact in
                Picker("", selection: Binding(
                    get: { developerTools.category },
                    set: { developerTools.changeCategory($0) }
                )) {
                    ForEach(DevelopmentToolCategory.allCases) { category in
                        Text(L10n.text("developer_tools.category.\(category.rawValue)"))
                            .tag(category)
                    }
                }
                .labelsHidden()
                .frame(width: compact ? 132 : 170)

                developerToolSearchField(palette)
                    .frame(minWidth: compact ? 110 : 180)
                    .layoutPriority(1)

                Button {
                    developerTools.refresh()
                } label: {
                    if developerTools.isRefreshing || developerTools.isCheckingUpdates {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(gattoSymbol: "arrow.clockwise")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(developerTools.isRefreshing || developerTools.isCheckingUpdates)
                .help(L10n.text("developer_tools.action.check_updates"))
            }
        } catalog: {
            developerToolResultPane(palette)
        } detail: {
            DeveloperToolDetailView(model: developerTools,
                                    pendingInstall: $pendingToolInstall, pendingUpgrade: $pendingToolUpgrade)
        }
        .onAppear { developerTools.loadIfNeeded() }
        .confirmationDialog(
            L10n.text("developer_tools.install.confirm.title"),
            isPresented: Binding(
                get: { pendingToolInstall != nil },
                set: { if !$0 { pendingToolInstall = nil } }
            )
        ) {
            Button(L10n.text("developer_tools.action.install")) {
                if let tool = pendingToolInstall {
                    developerTools.install(tool)
                }
                pendingToolInstall = nil
            }
            Button(L10n.text("action.cancel"), role: .cancel) {
                pendingToolInstall = nil
            }
        } message: {
            Text(L10n.text("developer_tools.install.confirm.body"))
        }
        .confirmationDialog(
            L10n.text("developer_tools.upgrade.confirm.title"),
            isPresented: Binding(
                get: { pendingToolUpgrade != nil },
                set: { if !$0 { pendingToolUpgrade = nil } }
            )
        ) {
            Button(L10n.text("developer_tools.action.upgrade")) {
                if let tool = pendingToolUpgrade {
                    developerTools.upgrade(tool)
                }
                pendingToolUpgrade = nil
            }
            Button(L10n.text("action.cancel"), role: .cancel) {
                pendingToolUpgrade = nil
            }
        } message: {
            Text(L10n.text("developer_tools.upgrade.confirm.body"))
        }
        .confirmationDialog(
            L10n.text("developer_tools.batch.confirm.title"),
            isPresented: $showsBatchUpgradeConfirmation
        ) {
            Button(L10n.format(
                "developer_tools.action.batch_upgrade",
                developerTools.selectedUpgradeCount
            )) {
                developerTools.upgradeSelectedTools()
            }
            Button(L10n.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.format(
                "developer_tools.batch.confirm.body",
                developerTools.selectedUpgradeCount
            ))
        }
    }

    private func developerToolSearchField(_ palette: AppPalette) -> some View {
        HStack(spacing: 7) {
            Image(gattoSymbol: "magnifyingglass")
                .foregroundStyle(palette.subtleInk)
            TextField(L10n.text("developer_tools.search.placeholder"), text: Binding(get: { developerTools.query }, set: { developerTools.query = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !developerTools.query.isEmpty {
                Button { developerTools.query = "" } label: {
                    Image(gattoSymbol: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: 390)
        .frame(height: 32)
        .background(palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(palette.divider, lineWidth: 1) }
    }

    private func developerToolResultPane(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("developer_tools.results"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.mutedInk)
                Text("\(developerTools.filteredTools.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.subtleInk)
                if developerTools.updateCount > 0 {
                    Text(L10n.format("developer_tools.updates.count", developerTools.updateCount))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(palette.warning)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(palette.warning.opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer()
                if developerTools.isRefreshing || developerTools.isCheckingUpdates {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 43)
            Rectangle().fill(palette.divider).frame(height: 1)

            if developerTools.installQueueCount > 0 || developerTools.upgradeQueueCount > 0 {
                developerToolQueueBar(palette)
                Rectangle().fill(palette.divider).frame(height: 1)
            }

            if developerTools.category == .updates, !developerTools.filteredTools.isEmpty {
                developerToolUpgradeSelectionBar(palette)
                Rectangle().fill(palette.divider).frame(height: 1)
            }

            if developerTools.filteredTools.isEmpty {
                ProjectEmptyState(systemImage: "hammer", titleKey: "developer_tools.empty")
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(developerTools.filteredTools) { tool in
                            developerToolRow(tool, palette: palette)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(palette.sidebar)
    }

    private func developerToolQueueBar(_ palette: AppPalette) -> some View {
        HStack(spacing: 7) {
            if developerTools.installQueueCount > 0 {
                developerToolQueueBadge(
                    title: L10n.text("developer_tools.queue.install"),
                    count: developerTools.installQueueCount,
                    systemImage: "arrow.down.app",
                    palette: palette
                )
            }
            if developerTools.upgradeQueueCount > 0 {
                developerToolQueueBadge(
                    title: L10n.text("developer_tools.queue.upgrade"),
                    count: developerTools.upgradeQueueCount,
                    systemImage: "arrow.up.circle",
                    palette: palette
                )
            }
            Spacer(minLength: 4)
            Text(L10n.format(
                "developer_tools.queue.running",
                developerTools.activeOperationCount
            ))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(palette.subtleInk)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(palette.surface)
    }

    private func developerToolQueueBadge(
        title: String,
        count: Int,
        systemImage: String,
        palette: AppPalette
    ) -> some View {
        HStack(spacing: 5) {
            Image(gattoSymbol: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
            Text("\(count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .padding(.horizontal, 5)
                .frame(height: 17)
                .background(palette.primary.opacity(0.12))
                .clipShape(Capsule())
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(palette.primary)
    }

    private func developerToolUpgradeSelectionBar(_ palette: AppPalette) -> some View {
        HStack(spacing: 8) {
            Button {
                developerTools.selectAllVisibleUpgrades()
            } label: {
                HStack(spacing: 5) {
                    Image(gattoSymbol: developerTools.isAllVisibleUpgradesSelected
                        ? "checkmark.circle.fill"
                        : "record.circle")
                    Text(L10n.text(developerTools.isAllVisibleUpgradesSelected
                        ? "developer_tools.selection.clear"
                        : "developer_tools.selection.select_all"))
                }
                .font(.system(size: 10.5, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.mutedInk)

            Spacer(minLength: 4)

            Button {
                showsBatchUpgradeConfirmation = true
            } label: {
                Text(L10n.format(
                    "developer_tools.action.batch_upgrade",
                    developerTools.selectedUpgradeCount
                ))
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(developerTools.selectedUpgradeCount == 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(palette.surface)
    }

    private func developerToolRow(_ tool: DevelopmentTool, palette: AppPalette) -> some View {
        let status = developerTools.status(for: tool)
        let isSelected = developerTools.selectedTool?.id == tool.id
        return HStack(spacing: 4) {
            if developerTools.category == .updates {
                Button {
                    developerTools.toggleUpgradeSelection(tool)
                } label: {
                    Image(gattoSymbol: developerTools.isUpgradeSelected(tool)
                        ? "checkmark.circle.fill"
                        : "record.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(developerTools.isUpgradeSelected(tool)
                            ? palette.primary
                            : palette.subtleInk)
                        .frame(width: 25, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(!status.canUpgrade)
                .accessibilityLabel(L10n.text("developer_tools.selection.item"))
            }

            Button {
                developerTools.select(tool)
            } label: {
                HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? palette.primary.opacity(0.16) : palette.raisedSurface)
                    DevelopmentToolLogoView(
                        tool: tool,
                        size: 31,
                        fallbackColor: isSelected ? palette.primary : palette.ink
                    )
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(L10n.text("developer_tools.category.\(tool.category.rawValue)"))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(palette.subtleInk)
                    if let version = status.version {
                        Text(status.latestVersion.map { "\(version)  →  \($0)" } ?? version)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(status.updateAvailability == .available ? palette.warning : palette.mutedInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if status.state == .queued {
                    if let position = developerTools.queuePosition(for: tool) {
                        Text("#\(position)")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.primary)
                    }
                } else if status.state == .installing {
                    ProgressView().controlSize(.small)
                } else if status.state == .actionRequired || status.state == .failed {
                    Image(gattoSymbol: "exclamationmark.triangle.fill")
                        .foregroundStyle(status.state == .failed ? palette.danger : palette.warning)
                        .accessibilityLabel(L10n.text("developer_tools.state.\(status.state.rawValue)"))
                } else if status.updateAvailability == .available {
                    Image(gattoSymbol: "arrow.up.circle.fill")
                        .foregroundStyle(status.isUpdatePinned ? palette.subtleInk : palette.warning)
                } else if status.isInstalled {
                    Image(gattoSymbol: "checkmark.circle.fill")
                        .foregroundStyle(palette.success)
                }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 66)
                .background(isSelected ? palette.primarySoft : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

}
