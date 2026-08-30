import AppKit
import SwiftUI

struct GitHubMarketplaceView: View {
    @ObservedObject var model: GitHubMarketplaceViewModel
    @ObservedObject var downloads: AppDownloadManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var inAppBrowserPage: InAppBrowserPage?
    @State private var selectedDetailTab = MarketplaceDetailTab.overview
    @State private var unavailableScreenshotURLs: Set<URL> = []

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            marketplaceHeader(palette)
            Rectangle().fill(palette.divider).frame(height: 1)
            HSplitView {
                resultPane(palette)
                    .frame(minWidth: 260, idealWidth: 310, maxWidth: 380)
                detailPane(palette)
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(palette.background)
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
    }

    private func marketplaceHeader(_ palette: AppPalette) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(gattoSymbol: "arrow.down.app")
                    .foregroundStyle(palette.primary)
                Text(L10n.text("marketplace.title"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.ink)
            }

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
            .frame(width: 128)

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
            .frame(maxWidth: 430)
            .frame(height: 32)
            .background(palette.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 9).stroke(palette.divider, lineWidth: 1) }

            Button(L10n.text("github.action.search")) { model.search() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isLoading || model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer(minLength: 8)

            Button {
                downloads.isPresented = true
            } label: {
                HStack(spacing: 7) {
                    Image(gattoSymbol: "tray.and.arrow.down")
                    Text(L10n.text("downloads.title"))
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
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .background(palette.surface)
    }

    private func resultPane(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("marketplace.results"))
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
                    Image(gattoSymbol: "shippingbox")
                        .font(.system(size: 22))
                        .foregroundStyle(palette.subtleInk)
                    Text(L10n.text("marketplace.empty"))
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
                                selected: model.selectedApplication?.id == application.id
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
        HStack(alignment: .top, spacing: 16) {
            MarketplaceLogoView(
                url: model.selectedLogoURL,
                language: application.repository.language,
                size: 72
            )
            VStack(alignment: .leading, spacing: 7) {
                Text(application.repository.name)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(palette.ink)
                Text(application.repository.fullName)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.subtleInk)
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
            Spacer(minLength: 12)
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
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
                Label(L10n.text("github.action.open_web"), systemImage: "arrow.up.right.square")
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
                                downloads: downloads
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

                if model.isAgentInstalling {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L10n.text("marketplace.agent.installing"))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(palette.mutedInk)
                    }
                } else if let result = model.agentInstallResult {
                    Text(result)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.ink)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(palette.raisedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

private enum MarketplaceDetailTab: String, CaseIterable, Identifiable {
    case overview
    case releases

    var id: String { rawValue }
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
        .padding(7)
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
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled,
                  data.count <= 8 * 1_024 * 1_024,
                  (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) ?? true,
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
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 11) {
                GitHubLanguageIcon(
                    language: application.repository.language,
                    isPrivate: false,
                    size: 40
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(application.repository.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(application.repository.owner)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(palette.subtleInk)
                    HStack(spacing: 8) {
                        GattoLabel(
                            GitHubNumberFormatter.string(application.repository.stars),
                            systemImage: "star"
                        )
                        Text(application.latestRelease.tagName)
                    }
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
                }
                Spacer(minLength: 4)
                Image(gattoSymbol: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.subtleInk)
            }
            .padding(.horizontal, 10)
            .frame(height: 64)
            .background(selected ? palette.primarySoft : (hovering ? palette.raisedSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
