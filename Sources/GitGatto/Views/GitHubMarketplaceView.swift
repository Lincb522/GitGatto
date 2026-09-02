import AppKit
import SwiftUI

struct GitHubMarketplaceView: View {
    @ObservedObject var model: GitHubMarketplaceViewModel
    @ObservedObject var developerTools: DeveloperToolsViewModel
    @ObservedObject var downloads: AppDownloadManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @State private var inAppBrowserPage: InAppBrowserPage?
    @State private var selectedDetailTab = MarketplaceDetailTab.overview
    @State private var unavailableScreenshotURLs: Set<URL> = []
    @State private var catalogSection: MarketplaceCatalogSection
    @State private var pendingQuickInstallAsset: GitHubReleaseAsset?
    @State private var pendingToolInstall: DevelopmentTool?
    @State private var pendingToolUpgrade: DevelopmentTool?
    @State private var showsBatchUpgradeConfirmation = false

    init(
        model: GitHubMarketplaceViewModel,
        developerTools: DeveloperToolsViewModel,
        downloads: AppDownloadManager,
        showsDeveloperToolsInitially: Bool = false
    ) {
        self.model = model
        self.developerTools = developerTools
        self.downloads = downloads
        _catalogSection = State(
            initialValue: showsDeveloperToolsInitially ? .developerTools : .applications
        )
    }

    private var installedRepositoryNames: [String] {
        var seen = Set<String>()
        return downloads.records
            .filter { $0.state == .installed }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(\.repositoryName)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private var installedRepositoryNameSet: Set<String> {
        Set(installedRepositoryNames.map { $0.lowercased() })
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        let theme = AppVisualTheme.resolved(themeRaw)
        Group {
            if theme == .emerald {
                VStack(spacing: 10) {
                    marketplaceHeader(palette)
                        .emeraldSurface(.elevated, cornerRadius: 16)
                    HStack(spacing: 10) {
                        catalogResultPane(palette)
                            .frame(minWidth: 220, idealWidth: 280, maxWidth: 380)
                            .emeraldSurface(.elevated, cornerRadius: 16)
                        catalogDetailPane(palette)
                            .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
                            .emeraldSurface(.panel, cornerRadius: 16)
                    }
                }
                .padding(10)
            } else if theme == .folio {
                VStack(spacing: 10) {
                    marketplaceHeader(palette)
                        .folioSurface(.elevated, cornerRadius: 16)
                    HStack(spacing: 10) {
                        catalogResultPane(palette)
                            .frame(minWidth: 220, idealWidth: 280, maxWidth: 380)
                            .folioSurface(.elevated, cornerRadius: 16)
                        catalogDetailPane(palette)
                            .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
                            .folioSurface(.panel, cornerRadius: 16)
                    }
                }
                .padding(10)
            } else {
                VStack(spacing: 0) {
                    marketplaceHeader(palette)
                    Rectangle().fill(palette.divider).frame(height: 1)
                    HSplitView {
                        catalogResultPane(palette)
                            .frame(minWidth: 220, idealWidth: 280, maxWidth: 380)
                        catalogDetailPane(palette)
                            .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(palette.background)
        .onAppear {
            model.loadIfNeeded()
#if DEBUG
            if ProcessInfo.processInfo.environment["GITGATTO_DEVELOPER_TOOLS_PREVIEW"] == "1" {
                catalogSection = .developerTools
            }
#endif
        }
        .onChange(of: catalogSection, initial: true) { _, section in
            if section == .developerTools {
                developerTools.loadIfNeeded()
            }
        }
        .onChange(of: installedRepositoryNames) { _, names in
            guard model.collection == .installed else { return }
            model.changeCollection(.installed, installedRepositoryNames: names)
        }
        .onChange(of: model.selectedApplication?.id) { _, _ in
            selectedDetailTab = .overview
            unavailableScreenshotURLs = []
        }
        .onChange(of: model.selectedDetails?.screenshots) { _, screenshots in
            unavailableScreenshotURLs.formIntersection(screenshots ?? [])
        }
        .onChange(of: selectedDetailTab) { _, tab in
            if tab == .releases {
                model.loadReleasesIfNeeded()
            }
        }
        .sheet(item: $inAppBrowserPage) { page in
            InAppBrowserSheet(url: page.url, persistent: page.persistent)
        }
        .confirmationDialog(
            L10n.text("marketplace.quick_install.confirm.title"),
            isPresented: Binding(
                get: { pendingQuickInstallAsset != nil },
                set: { if !$0 { pendingQuickInstallAsset = nil } }
            )
        ) {
            Button(L10n.text("marketplace.quick_install.action")) {
                if let asset = pendingQuickInstallAsset,
                   let application = model.selectedApplication {
                    downloads.quickInstall(
                        asset: asset,
                        repositoryName: application.repository.fullName
                    )
                }
                pendingQuickInstallAsset = nil
            }
            Button(L10n.text("action.cancel"), role: .cancel) {
                pendingQuickInstallAsset = nil
            }
        } message: {
            Text(L10n.text("marketplace.quick_install.confirm.body"))
        }
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

    private func marketplaceHeader(_ palette: AppPalette) -> some View {
        GeometryReader { proxy in
            marketplaceHeaderRow(palette, compact: proxy.size.width < 860)
        }
        .frame(height: 62)
        .background(palette.surface)
    }

    private func marketplaceHeaderRow(_ palette: AppPalette, compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 10) {
            if compact {
                Image(gattoSymbol: catalogSection == .applications ? "arrow.down.app" : "hammer")
                    .foregroundStyle(palette.primary)
                    .frame(width: 22, height: 32)
                    .help(L10n.text("marketplace.title"))
                    .accessibilityLabel(L10n.text("marketplace.title"))
            } else {
                HStack(spacing: 8) {
                    Image(gattoSymbol: catalogSection == .applications ? "arrow.down.app" : "hammer")
                        .foregroundStyle(palette.primary)
                    Text(L10n.text("marketplace.title"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.ink)
                }
                .fixedSize()
            }

            Picker("", selection: $catalogSection) {
                ForEach(MarketplaceCatalogSection.allCases) { section in
                    Text(L10n.text("marketplace.section.\(section.rawValue)"))
                        .tag(section)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: compact ? 146 : 196)

            if catalogSection == .applications {
                Picker("", selection: Binding(
                    get: { model.platform },
                    set: { model.changePlatform($0) }
                )) {
                    ForEach(MarketplacePlatform.allCases) { platform in
                        Text(L10n.text("marketplace.platform.\(platform.rawValue)"))
                            .tag(platform)
                    }
                }
                .labelsHidden()
                .frame(width: compact ? 96 : 124)

                marketplaceSearchField(palette)
                    .frame(minWidth: compact ? 110 : 180)
                    .layoutPriority(1)

                Button { model.search() } label: {
                    if compact {
                        Image(gattoSymbol: "magnifyingglass")
                            .frame(width: 16, height: 16)
                    } else {
                        Text(L10n.text("github.action.search"))
                    }
                }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isLoading || model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(L10n.text("github.action.search"))
            } else {
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

            Spacer(minLength: 8)

            Button {
                downloads.isPresented = true
            } label: {
                HStack(spacing: 7) {
                    Image(gattoSymbol: "tray.and.arrow.down")
                    if !compact {
                        Text(L10n.text("downloads.title"))
                    }
                    if downloads.activeCount > 0 {
                        Text("\(downloads.activeCount)")
                            .font(.system(size: 9.5, weight: .bold))
                            .padding(.horizontal, 5)
                            .frame(height: 17)
                            .background(palette.primarySoft)
                            .clipShape(Capsule())
                    }
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .help(L10n.text("downloads.title"))
        }
        .padding(.horizontal, compact ? 12 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func marketplaceSearchField(_ palette: AppPalette) -> some View {
        HStack(spacing: 7) {
            Image(gattoSymbol: model.isUsingAgent ? "sparkles" : "magnifyingglass")
                .foregroundStyle(model.isUsingAgent ? palette.primary : palette.subtleInk)
            TextField(L10n.text("marketplace.search.placeholder"), text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onSubmit { model.search() }
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
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

    private func developerToolSearchField(_ palette: AppPalette) -> some View {
        HStack(spacing: 7) {
            Image(gattoSymbol: "magnifyingglass")
                .foregroundStyle(palette.subtleInk)
            TextField(L10n.text("developer_tools.search.placeholder"), text: $developerTools.query)
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

    @ViewBuilder
    private func catalogResultPane(_ palette: AppPalette) -> some View {
        switch catalogSection {
        case .applications:
            resultPane(palette)
        case .developerTools:
            developerToolResultPane(palette)
        }
    }

    @ViewBuilder
    private func catalogDetailPane(_ palette: AppPalette) -> some View {
        switch catalogSection {
        case .applications:
            detailPane(palette)
        case .developerTools:
            developerToolDetailPane(palette)
        }
    }

    private func resultPane(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            applicationCollectionBar(palette)
            Rectangle().fill(palette.divider).frame(height: 1)

            HStack {
                Text(applicationResultTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.mutedInk)
                if !model.applications.isEmpty {
                    Text("\(model.applications.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.subtleInk)
                }
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12)
            .frame(height: 43)
            Rectangle().fill(palette.divider).frame(height: 1)

            if model.applications.isEmpty && model.isLoading {
                GattoLoadingState(text: L10n.text("marketplace.loading"))
            } else if model.applications.isEmpty {
                VStack(spacing: 9) {
                    Image(gattoSymbol: applicationEmptyIcon)
                        .font(.system(size: 22))
                        .foregroundStyle(palette.subtleInk)
                    Text(L10n.text(applicationEmptyKey))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.mutedInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(model.applications) { application in
                            MarketplaceApplicationRow(
                                application: application,
                                selected: model.selectedApplication?.id == application.id,
                                isFavorite: model.collection == .favorites,
                                isInstalled: installedRepositoryNameSet.contains(
                                    application.repository.fullName.lowercased()
                                )
                            ) {
                                model.select(application)
                            }
                        }
                        if model.canLoadMore {
                            HStack(spacing: 7) {
                                ProgressView().controlSize(.small)
                                Text(L10n.text("github.search.loading_more"))
                            }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.mutedInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .padding(.vertical, 7)
                            .task(id: model.searchPage) {
                                model.loadMore()
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(palette.sidebar)
    }

    private func applicationCollectionBar(_ palette: AppPalette) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(MarketplaceCollection.allCases) { collection in
                    Button {
                        model.changeCollection(
                            collection,
                            installedRepositoryNames: installedRepositoryNames
                        )
                    } label: {
                        HStack(spacing: 4) {
                            Image(gattoSymbol: collection.symbolName)
                                .font(.system(size: 11, weight: .semibold))
                            Text(L10n.text("marketplace.collection.\(collection.rawValue)"))
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .foregroundStyle(model.collection == collection ? palette.primary : palette.mutedInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(model.collection == collection ? palette.primarySoft : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if model.collection == .discover, !model.isShowingSearchResults {
                HStack(spacing: 5) {
                    ForEach(MarketplaceFeed.allCases) { feed in
                        Button {
                            model.changeFeed(feed)
                        } label: {
                            Text(L10n.text("marketplace.feed.\(feed.rawValue)"))
                                .font(.system(size: 10.5, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity)
                                .frame(height: 27)
                                .foregroundStyle(model.feed == feed ? palette.primary : palette.mutedInk)
                                .background(model.feed == feed ? palette.primarySoft : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isLoading && model.feed == feed)
                    }
                }
            }
        }
        .padding(8)
        .background(palette.surface)
    }

    private var applicationResultTitle: String {
        if model.isShowingSearchResults {
            return L10n.text("marketplace.results.search")
        }
        if model.collection == .discover {
            return L10n.text("marketplace.feed.\(model.feed.rawValue)")
        }
        return L10n.text("marketplace.collection.\(model.collection.rawValue)")
    }

    private var applicationEmptyKey: String {
        switch model.collection {
        case .discover: "marketplace.empty"
        case .favorites: "marketplace.favorites.empty"
        case .installed: "marketplace.installed.empty"
        case .recent: "marketplace.recent.empty"
        }
    }

    private var applicationEmptyIcon: String {
        switch model.collection {
        case .discover: "shippingbox"
        case .favorites: "star"
        case .installed: "checkmark.seal"
        case .recent: "clock.arrow.circlepath"
        }
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

    @ViewBuilder
    private func developerToolDetailPane(_ palette: AppPalette) -> some View {
        if let tool = developerTools.selectedTool {
            let status = developerTools.status(for: tool)
            VStack(spacing: 0) {
                HStack(spacing: 15) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(palette.primarySoft)
                        DevelopmentToolLogoView(
                            tool: tool,
                            size: 46,
                            fallbackColor: palette.primary
                        )
                    }
                    .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(tool.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(palette.ink)
                        Text(L10n.text("developer_tools.category.\(tool.category.rawValue)"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.mutedInk)
                        if let version = status.version {
                            Text(version)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.subtleInk)
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    if status.state == .queued || status.state == .installing {
                        Button(L10n.text("action.cancel")) {
                            developerTools.cancel(tool)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    } else if status.authorizationRequest != nil {
                        Button {
                            developerTools.authorizeAndRetry(tool)
                        } label: {
                            HStack(spacing: 7) {
                                Image(gattoSymbol: "lock.open")
                                Text(L10n.text("developer_tools.action.authorize_retry"))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(developerTools.isQueuedOrRunning(tool))
                    } else if status.state == .actionRequired {
                        Button {
                            developerTools.retry(tool)
                        } label: {
                            HStack(spacing: 7) {
                                Image(gattoSymbol: "arrow.clockwise")
                                Text(L10n.text("developer_tools.action.retry"))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(developerTools.isQueuedOrRunning(tool))
                    } else if status.canUpgrade {
                        Button(L10n.text("developer_tools.action.upgrade")) {
                            pendingToolUpgrade = tool
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(developerTools.isQueuedOrRunning(tool))
                    } else if status.updateAvailability == .available && status.isUpdatePinned {
                        Button(L10n.text("developer_tools.action.pinned")) {}
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(true)
                    } else {
                        Button(L10n.text(status.isInstalled
                            ? "developer_tools.action.reinstall"
                            : "developer_tools.action.install")) {
                            pendingToolInstall = tool
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(developerTools.isQueuedOrRunning(tool))
                    }
                }
                .padding(20)
                .background(palette.surface)

                Rectangle().fill(palette.divider).frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(L10n.text(tool.summaryKey))
                            .font(.system(size: 13))
                            .foregroundStyle(palette.mutedInk)
                            .lineSpacing(3)

                        HStack(spacing: 10) {
                            MarketplaceInformationCell(
                                title: L10n.text("developer_tools.detail.installation"),
                                value: L10n.text("developer_tools.detail.agent"),
                                systemImage: "sparkles"
                            )
                            MarketplaceInformationCell(
                                title: L10n.text("developer_tools.detail.scope"),
                                value: L10n.text("developer_tools.detail.current_user"),
                                systemImage: "person.circle"
                            )
                        }

                        if status.isInstalled {
                            HStack(spacing: 10) {
                                MarketplaceInformationCell(
                                    title: L10n.text("developer_tools.detail.installed_version"),
                                    value: status.version ?? "—",
                                    systemImage: "checkmark.circle"
                                )
                                MarketplaceInformationCell(
                                    title: L10n.text("developer_tools.detail.latest_version"),
                                    value: status.latestVersion ?? "—",
                                    systemImage: "arrow.up.circle"
                                )
                            }
                            developerToolUpdateStatus(status, palette: palette)
                        }

                        developerToolInstallationStatus(tool, status: status, palette: palette)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            ProjectEmptyState(systemImage: "hammer", titleKey: "developer_tools.select")
        }
    }

    private func developerToolUpdateStatus(
        _ status: DevelopmentToolStatus,
        palette: AppPalette
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if status.updateAvailability == .checking {
                ProgressView().controlSize(.small)
            } else {
                Image(gattoSymbol: updateStatusIcon(status.updateAvailability))
                    .foregroundStyle(updateStatusColor(status.updateAvailability, palette: palette))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("developer_tools.detail.update"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.subtleInk)
                Text(L10n.text("developer_tools.update.\(status.updateAvailability.rawValue)"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                if let detail = status.updateDetail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.mutedInk)
                        .textSelection(.enabled)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(palette.divider, lineWidth: 1)
        }
    }

    private func updateStatusIcon(_ availability: DevelopmentToolUpdateAvailability) -> String {
        switch availability {
        case .unknown: "clock.arrow.circlepath"
        case .checking: "arrow.triangle.2.circlepath"
        case .current: "checkmark.circle.fill"
        case .available: "arrow.up.circle.fill"
        case .unavailable: "minus.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func updateStatusColor(
        _ availability: DevelopmentToolUpdateAvailability,
        palette: AppPalette
    ) -> Color {
        switch availability {
        case .current: palette.success
        case .available: palette.warning
        case .failed: palette.danger
        default: palette.subtleInk
        }
    }

    @ViewBuilder
    private func developerToolInstallationStatus(
        _ tool: DevelopmentTool,
        status: DevelopmentToolStatus,
        palette: AppPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(gattoSymbol: developerToolStatusIcon(status))
                    .foregroundStyle(developerToolStatusColor(status, palette: palette))
                Text(L10n.text(status.state == .queued
                    ? "developer_tools.state.queued"
                    : status.operation == .upgrade
                        ? "developer_tools.state.upgrading"
                        : "developer_tools.state.\(status.state.rawValue)"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
            }

            if status.state == .installing, let phase = status.phase {
                AgentInstallationProgressView(
                    phase: phase,
                    detail: status.detail ?? L10n.text("installer.phase.\(phase.rawValue)"),
                    startedAt: status.operationStartedAt
                )
            } else if let detail = status.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(status.state == .failed ? palette.danger : palette.mutedInk)
                    .textSelection(.enabled)
            }

            if let result = status.result, !result.isEmpty {
                Text(result)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.ink)
                    .textSelection(.enabled)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.raisedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(14)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(palette.divider, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(tool.name), \(L10n.text("developer_tools.state.\(status.state.rawValue)"))")
    }

    private func developerToolStatusIcon(_ status: DevelopmentToolStatus) -> String {
        switch status.state {
        case .idle: "arrow.down.app"
        case .queued: "clock.arrow.circlepath"
        case .installing: "arrow.triangle.2.circlepath"
        case .installed: "checkmark.circle.fill"
        case .actionRequired: "exclamationmark.triangle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func developerToolStatusColor(_ status: DevelopmentToolStatus, palette: AppPalette) -> Color {
        switch status.state {
        case .installed: palette.success
        case .queued: palette.warning
        case .actionRequired: palette.warning
        case .failed: palette.danger
        default: palette.primary
        }
    }

    @ViewBuilder
    private func detailPane(_ palette: AppPalette) -> some View {
        if let application = model.selectedApplication {
            VStack(spacing: 0) {
                applicationHeader(application, palette: palette)
                Rectangle().fill(palette.divider).frame(height: 1)
                HStack(spacing: 12) {
                    Picker("", selection: $selectedDetailTab) {
                        ForEach(MarketplaceDetailTab.allCases) { tab in
                            Text(L10n.text("marketplace.detail.\(tab.rawValue)"))
                                .tag(tab)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    Spacer()
                    translationMenu(palette)
                }
                .padding(.horizontal, 20)
                .frame(height: 50)
                .background(palette.surface)
                Rectangle().fill(palette.divider).frame(height: 1)

                switch selectedDetailTab {
                case .overview:
                    overviewPane(application, palette: palette)
                case .releases:
                    releasesPane(application, palette: palette)
                }
            }
        } else if model.isLoading {
            GattoLoadingState(text: L10n.text("marketplace.loading"))
        } else if let error = model.error {
            Text(error)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.danger)
                .textSelection(.enabled)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ProjectEmptyState(systemImage: "arrow.down.app", titleKey: "marketplace.select")
        }
    }

    private func applicationHeader(
        _ application: MarketplaceApplication,
        palette: AppPalette
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                applicationIdentity(application, logoSize: 72, palette: palette)
                    .frame(minWidth: 340, maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 8) {
                    applicationActionButtons(application)
                    applicationMetadata(application, compact: false, palette: palette)
                }
            }
            .frame(minWidth: 600)

            VStack(alignment: .leading, spacing: 12) {
                applicationIdentity(application, logoSize: 58, palette: palette)
                applicationActionButtons(application)
                applicationMetadata(application, compact: true, palette: palette)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
    }

    private func applicationIdentity(
        _ application: MarketplaceApplication,
        logoSize: CGFloat,
        palette: AppPalette
    ) -> some View {
        HStack(alignment: .top, spacing: logoSize >= 70 ? 16 : 12) {
            MarketplaceLogoView(
                url: model.selectedLogoURL,
                language: application.repository.language,
                size: logoSize
            )
            VStack(alignment: .leading, spacing: 7) {
                Text(application.repository.name)
                    .font(.system(size: logoSize >= 70 ? 23 : 19, weight: .bold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Text(application.repository.fullName)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.subtleInk)
                    .lineLimit(1)
                if let description = model.displayedDescription(for: application), !description.isEmpty {
                    Text(description)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.mutedInk)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if let language = application.repository.language {
                        GitHubLanguageStackBadge(language: language)
                    }
                    Text(application.latestRelease.tagName)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.primary)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(palette.primarySoft)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
        }
    }

    private func applicationActionButtons(_ application: MarketplaceApplication) -> some View {
        HStack(spacing: 8) {
            Button {
                model.toggleStar()
            } label: {
                if model.isUpdatingStar {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    GattoLabel(
                        L10n.text(model.isStarred
                            ? "marketplace.favorite.remove"
                            : "marketplace.favorite.add"),
                        systemImage: model.isStarred ? "star.fill" : "star"
                    )
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.isUpdatingStar)

            if let asset = preferredInstallAsset(for: application) {
                Button {
                    pendingQuickInstallAsset = asset
                } label: {
                    GattoLabel(
                        L10n.text("marketplace.quick_install.action"),
                        systemImage: "arrow.down.app"
                    )
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func applicationMetadata(
        _ application: MarketplaceApplication,
        compact: Bool,
        palette: AppPalette
    ) -> some View {
        if compact {
            HStack(spacing: 12) {
                GattoLabel(
                    GitHubNumberFormatter.string(application.repository.stars),
                    systemImage: "star"
                )
                GattoLabel(
                    GitHubNumberFormatter.string(application.repository.forks),
                    systemImage: "arrow.triangle.branch"
                )
                Text(application.repository.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 9.5, weight: .medium))
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(palette.subtleInk)
        } else {
            VStack(alignment: .trailing, spacing: 8) {
                GattoLabel(
                    GitHubNumberFormatter.string(application.repository.stars),
                    systemImage: "star"
                )
                GattoLabel(
                    GitHubNumberFormatter.string(application.repository.forks),
                    systemImage: "arrow.triangle.branch"
                )
                Text(application.repository.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 9.5, weight: .medium))
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(palette.subtleInk)
        }
    }

    @ViewBuilder
    private func overviewPane(
        _ application: MarketplaceApplication,
        palette: AppPalette
    ) -> some View {
        if model.isLoadingDetails, model.selectedDetails == nil {
            GattoLoadingState(text: L10n.text("marketplace.detail.loading"))
        } else {
            let details = model.displayedDetails(for: application)
            let screenshotURLs = details.screenshots.filter { !unavailableScreenshotURLs.contains($0) }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let error = model.starError {
                        Text(error)
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.danger)
                            .textSelection(.enabled)
                    }
                    if let error = model.translationError {
                        Text(error)
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.danger)
                            .textSelection(.enabled)
                    }

                    if !details.paragraphs.isEmpty {
                        marketplaceDetailSection(L10n.text("marketplace.detail.about"), palette: palette) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(details.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                    Text(paragraph)
                                        .font(.system(size: 13))
                                        .foregroundStyle(palette.mutedInk)
                                        .lineSpacing(3)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    } else if details.summary?.isEmpty != false {
                        Text(L10n.text("marketplace.detail.unavailable"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.mutedInk)
                    }

                    marketplaceDetailSection(L10n.text("marketplace.detail.screenshots"), palette: palette) {
                        if screenshotURLs.isEmpty {
                            Text(L10n.text("marketplace.detail.screenshots.empty"))
                                .font(.system(size: 12.5))
                                .foregroundStyle(palette.mutedInk)
                        } else {
                            MarketplaceScreenshotCarousel(urls: screenshotURLs) { url in
                                unavailableScreenshotURLs.insert(url)
                            }
                        }
                    }

                    if !details.features.isEmpty {
                        marketplaceDetailSection(L10n.text("marketplace.detail.features"), palette: palette) {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 220, maximum: 420), spacing: 10)],
                                spacing: 10
                            ) {
                                ForEach(details.features, id: \.self) { feature in
                                    HStack(alignment: .top, spacing: 9) {
                                        Image(gattoSymbol: "checkmark.circle.fill")
                                            .foregroundStyle(palette.primary)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(feature)
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(palette.ink)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(12)
                                    .background(palette.raisedSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .strokeBorder(palette.divider, lineWidth: 1)
                                    }
                                }
                            }
                        }
                    }

                    marketplaceInformation(application, palette: palette)
                }
                .padding(24)
            }
        }
    }

    private func marketplaceInformation(
        _ application: MarketplaceApplication,
        palette: AppPalette
    ) -> some View {
        marketplaceDetailSection(L10n.text("marketplace.detail.information"), palette: palette) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150, maximum: 280), spacing: 10)],
                spacing: 10
            ) {
                MarketplaceInformationCell(
                    title: L10n.text("marketplace.detail.developer"),
                    value: application.repository.owner,
                    systemImage: "person.circle"
                )
                MarketplaceInformationCell(
                    title: L10n.text("marketplace.detail.latest_version"),
                    value: application.latestRelease.tagName,
                    systemImage: "shippingbox"
                )
                MarketplaceInformationCell(
                    title: L10n.text("marketplace.detail.updated"),
                    value: application.repository.updatedAt.formatted(date: .abbreviated, time: .omitted),
                    systemImage: "clock.arrow.circlepath"
                )
                if let language = application.repository.language {
                    MarketplaceInformationCell(
                        title: L10n.text("github.repository.language.primary"),
                        value: language,
                        systemImage: "code"
                    )
                }
                MarketplaceInformationCell(
                    title: L10n.text("marketplace.detail.download_size"),
                    value: ByteCountFormatter.string(
                        fromByteCount: application.matchingAssets.reduce(0) { $0 + $1.size },
                        countStyle: .file
                    ),
                    systemImage: "internaldrive"
                )
            }

            Button {
                inAppBrowserPage = InAppBrowserPage(url: application.repository.webURL, persistent: true)
            } label: {
                GattoLabel(L10n.text("github.action.open_web"), systemImage: "arrow.up.right.square")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func marketplaceDetailSection<Content: View>(
        _ title: String,
        palette: AppPalette,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.ink)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func releasesPane(
        _ application: MarketplaceApplication,
        palette: AppPalette
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Picker(L10n.text("marketplace.release"), selection: Binding(
                        get: { model.selectedReleaseID ?? model.releases.first?.id ?? 0 },
                        set: { model.selectRelease($0) }
                    )) {
                        ForEach(model.releases) { release in
                            Text("\(release.name) · \(release.tagName)").tag(release.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 420, alignment: .leading)
                    if model.isLoadingReleases {
                        ProgressView().controlSize(.small)
                    }
                }

                if let release = selectedRelease(for: application) {
                    let assets = release.assets.filter { model.platform.supports($0) }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("github.releases.assets"))
                            .font(.system(size: 13, weight: .semibold))
                        ForEach(assets) { asset in
                            ReleaseAssetRow(
                                asset: asset,
                                repositoryName: application.repository.fullName,
                                downloads: downloads,
                                quickInstall: supportsQuickInstall(asset) ? {
                                    pendingQuickInstallAsset = asset
                                } : nil
                            )
                        }
                        if assets.isEmpty {
                            Text(L10n.text("github.releases.assets.empty"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.mutedInk)
                        }
                    }

                    let displayedNotes = model.displayedReleaseNotes(for: release)
                    if !displayedNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(L10n.text("github.releases.notes"))
                                .font(.system(size: 13, weight: .semibold))
                            ReleaseNotesMarkdownView(text: displayedNotes) { url in
                                inAppBrowserPage = InAppBrowserPage(url: url, persistent: true)
                            }
                        }
                    }
                }

                if let error = model.detailError ?? model.error {
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.danger)
                        .textSelection(.enabled)
                }
                if let error = model.translationError {
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.danger)
                        .textSelection(.enabled)
                }
            }
            .padding(24)
        }
    }

    private func selectedRelease(for application: MarketplaceApplication) -> GitHubRelease? {
        model.selectedRelease ?? application.latestRelease
    }

    private func preferredInstallAsset(for application: MarketplaceApplication) -> GitHubReleaseAsset? {
        guard model.platform == .macOS else { return nil }
        return application.matchingAssets.min { lhs, rhs in
            installAssetPriority(lhs) < installAssetPriority(rhs)
        }
    }

    private func supportsQuickInstall(_ asset: GitHubReleaseAsset) -> Bool {
        model.platform == .macOS && MarketplacePlatform.macOS.supports(asset)
    }

    private func installAssetPriority(_ asset: GitHubReleaseAsset) -> Int {
        switch asset.fileExtension {
        case "dmg": 0
        case "zip": 1
        case "pkg": 2
        default: 3
        }
    }

    @ViewBuilder
    private func translationMenu(_ palette: AppPalette) -> some View {
        if model.isTranslating {
            Button {} label: {
                DocumentTranslationActionLabel(
                    title: L10n.text("codex.action.translate"),
                    activeTitle: L10n.text("codex.status.translating"),
                    isActive: true,
                    completionID: model.translationCompletionID
                )
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(true)
        } else {
            let title = model.activeTranslationTarget.map {
                L10n.text("codex.translate.short.\($0.rawValue)")
            } ?? L10n.text("codex.action.translate")
            MotionLabelMenu(
                accessibilityLabel: title,
                isDisabled: model.isLoadingDetails
            ) {
                Button(L10n.text("marketplace.translation.original")) { model.showOriginal() }
                if !model.availableTranslationTargets.isEmpty {
                    Divider()
                    ForEach(model.availableTranslationTargets) { target in
                        Button(L10n.text("codex.translate.short.\(target.rawValue)")) {
                            model.showTranslation(target)
                        }
                    }
                }
                Divider()
                ForEach(CodexTranslationTarget.allCases) { target in
                    Button(L10n.text("codex.translate.\(target.rawValue)")) {
                        model.translateSelected(to: target)
                    }
                }
            } label: {
                DocumentTranslationActionLabel(
                    title: title,
                    activeTitle: L10n.text("codex.status.translating"),
                    isActive: false,
                    completionID: model.translationCompletionID,
                    showsInitialCompletion: true
                )
                .foregroundStyle(model.activeTranslationTarget == nil ? palette.ink : palette.primary)
            }
        }
    }
}

private struct MarketplaceInformationCell: View {
    let title: String
    let value: String
    let systemImage: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 10) {
            Image(gattoSymbol: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.primary)
                .frame(width: 28, height: 28)
                .background(palette.primarySoft)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(palette.divider, lineWidth: 1)
        }
    }
}

private struct MarketplaceScreenshotView: View {
    let url: URL
    var height: CGFloat = 176
    let onFailure: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
            switch phase {
            case let .success(image):
                screenshotContainer {
                    image
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                }
            case .failure:
                EmptyView()
                    .onAppear(perform: onFailure)
            case .empty:
                screenshotContainer {
                    ProgressView().controlSize(.small)
                }
            @unknown default:
                EmptyView()
            }
        }
    }

    private func screenshotContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        let palette = AppPalette(colorScheme)
        return content()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(palette.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(palette.divider, lineWidth: 1)
            }
    }
}

private struct MarketplaceScreenshotCarousel: View {
    let urls: [URL]
    let onFailure: (URL) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIndex = 0
    @State private var movesBackward = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 10) {
            ZStack {
                MarketplaceScreenshotView(url: urls[selectedIndex], height: 238) {
                    onFailure(urls[selectedIndex])
                }
                .id(urls[selectedIndex])
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: movesBackward ? .leading : .trailing)
                                .combined(with: .opacity),
                            removal: .move(edge: movesBackward ? .trailing : .leading)
                                .combined(with: .opacity)
                        )
                )

                if urls.count > 1 {
                    HStack {
                        carouselButton(systemName: "chevron.left", isDisabled: selectedIndex == 0) {
                            select(selectedIndex - 1)
                        }
                        Spacer()
                        carouselButton(systemName: "chevron.right", isDisabled: selectedIndex == urls.count - 1) {
                            select(selectedIndex + 1)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 28)
                    .onEnded { value in
                        if value.translation.width < -60, selectedIndex < urls.count - 1 {
                            select(selectedIndex + 1)
                        } else if value.translation.width > 60, selectedIndex > 0 {
                            select(selectedIndex - 1)
                        }
                    }
            )

            if urls.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(urls.enumerated()), id: \.element.absoluteString) { index, url in
                            Button {
                                select(index)
                            } label: {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case let .success(image):
                                        image
                                            .resizable()
                                            .interpolation(.high)
                                            .scaledToFill()
                                    case .empty:
                                        ProgressView().controlSize(.mini)
                                    default:
                                        Color.clear
                                    }
                                }
                                .frame(width: 74, height: 46)
                                .background(palette.raisedSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(
                                            index == selectedIndex ? palette.primary : palette.divider,
                                            lineWidth: index == selectedIndex ? 2 : 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .onChange(of: urls) { _, newValue in
            selectedIndex = min(selectedIndex, max(0, newValue.count - 1))
        }
    }

    private func select(_ index: Int) {
        guard urls.indices.contains(index), index != selectedIndex else { return }
        movesBackward = index < selectedIndex
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.32)) {
            selectedIndex = index
        }
    }

    private func carouselButton(
        systemName: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let palette = AppPalette(colorScheme)
        return Button(action: action) {
            Image(gattoSymbol: systemName)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(palette.ink)
                .frame(width: 30, height: 30)
                .background(.regularMaterial)
                .clipShape(Circle())
                .overlay { Circle().stroke(palette.divider, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.3 : 1)
    }
}

private enum MarketplaceCatalogSection: String, CaseIterable, Identifiable {
    case applications
    case developerTools

    var id: String { rawValue }
}

private extension MarketplaceCollection {
    var symbolName: String {
        switch self {
        case .discover: "square.grid.2x2"
        case .favorites: "star"
        case .installed: "checkmark.seal"
        case .recent: "clock.arrow.circlepath"
        }
    }
}

private enum MarketplaceDetailTab: String, CaseIterable, Identifiable {
    case overview
    case releases

    var id: String { rawValue }
}

private struct DevelopmentToolLogoView: View {
    let tool: DevelopmentTool
    let size: CGFloat
    let fallbackColor: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let logoName = tool.brandLogoName,
               let image = DevelopmentToolLogoAssets.image(named: logoName) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .padding(colorScheme == .dark ? size * 0.08 : 0)
                    .background(colorScheme == .dark ? Color.white.opacity(0.94) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            } else {
                GattoIcon(symbol: tool.icon, size: size * 0.68)
                    .foregroundStyle(fallbackColor)
            }
        }
        .frame(width: size, height: size)
    }
}

private enum DevelopmentToolLogoAssets {
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 96
        cache.totalCostLimit = 12 * 1_024 * 1_024
        return cache
    }()

    static func image(named name: String) -> NSImage? {
        let key = name as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let bundle = AppResourceBundle.current
        let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "ToolLogos")
            ?? bundle.url(forResource: name, withExtension: "png")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false
        cache.setObject(image, forKey: key, cost: 256 * 256 * 4)
        return image
    }
}

private struct MarketplaceLogoView: View {
    let url: URL?
    let language: String?
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?
    @State private var isLoading = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .transition(.opacity)
            } else if isLoading {
                ProgressView().controlSize(.small)
            } else {
                fallback
            }
        }
        .padding(size >= 60 ? 7 : 4)
        .frame(width: size, height: size)
        .background(palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(palette.divider, lineWidth: 1)
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private var fallback: some View {
        GitHubLanguageIcon(language: language, size: size - 14)
    }

    private func loadImage() async {
        image = nil
        guard let url else {
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await RemoteImageDataCache.shared.data(for: url)
            guard !Task.isCancelled,
                  let loaded = NSImage(data: data) else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                image = loaded
            }
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }
}

private struct MarketplaceApplicationRow: View {
    let application: MarketplaceApplication
    let selected: Bool
    let isFavorite: Bool
    let isInstalled: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                MarketplaceLogoView(
                    url: application.ownerAvatarURL,
                    language: application.repository.language,
                    size: 44
                )
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(application.repository.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if isInstalled {
                            Image(gattoSymbol: "checkmark.seal.fill")
                                .foregroundStyle(palette.success)
                                .help(L10n.text("marketplace.collection.installed"))
                        }
                        if isFavorite {
                            Image(gattoSymbol: "star.fill")
                                .foregroundStyle(palette.warning)
                                .help(L10n.text("marketplace.collection.favorites"))
                        }
                    }
                    if let description = application.repository.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.mutedInk)
                            .lineLimit(2)
                    }
                    HStack(spacing: 7) {
                        Text(application.repository.owner)
                        GattoLabel(
                            GitHubNumberFormatter.string(application.repository.stars),
                            systemImage: "star"
                        )
                        Text(application.latestRelease.tagName)
                            .lineLimit(1)
                    }
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
                }
            }
            .padding(10)
            .frame(minHeight: 84)
            .background(selected ? palette.primarySoft : (hovering ? palette.raisedSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
