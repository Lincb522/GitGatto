import AppKit
import SwiftUI

struct ApplicationMarketplaceView: View {
    @ObservedObject var model: GitHubMarketplaceViewModel
    let downloads: AppDownloadManager
    let installedRepositoryNames: [String]
    let activeDownloadCount: Int
    @Binding var catalogSection: MarketplaceCatalogSection
    @Binding var selectedDetailTab: MarketplaceDetailTab
    @Binding var unavailableScreenshotURLs: Set<URL>
    @Binding var inAppBrowserPage: InAppBrowserPage?
    @Environment(\.colorScheme) private var colorScheme
    @State private var pendingQuickInstallAsset: GitHubReleaseAsset?

    private var installedRepositoryNameSet: Set<String> {
        Set(installedRepositoryNames.map { $0.lowercased() })
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        MarketplaceWorkspaceLayout {
            MarketplaceCatalogHeader(section: $catalogSection, activeDownloadCount: activeDownloadCount,
                                     showDownloads: { downloads.isPresented = true }) { compact in
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
            }
        } catalog: {
            resultPane(palette)
        } detail: {
            detailPane(palette)
        }
        .onAppear { model.loadIfNeeded() }
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
