import AppKit
import SwiftUI

struct GitHubMarketplaceView: View {
    let model: GitHubMarketplaceViewModel
    let developerTools: DeveloperToolsViewModel
    let downloads: AppDownloadManager
    @StateObject private var downloadSummary: AppDownloadSummary
    @State private var catalogSection: MarketplaceCatalogSection
    @State private var selectedDetailTab = MarketplaceDetailTab.overview
    @State private var unavailableScreenshotURLs: Set<URL> = []
    @State private var inAppBrowserPage: InAppBrowserPage?

    init(
        model: GitHubMarketplaceViewModel,
        developerTools: DeveloperToolsViewModel,
        downloads: AppDownloadManager,
        showsDeveloperToolsInitially: Bool = false
    ) {
        self.model = model
        self.developerTools = developerTools
        self.downloads = downloads
        _downloadSummary = StateObject(wrappedValue: AppDownloadSummary(downloads: downloads))
        _catalogSection = State(initialValue: showsDeveloperToolsInitially ? .developerTools : .applications)
    }

    var body: some View {
        Group {
            switch catalogSection {
            case .applications:
                ApplicationMarketplaceView(
                    model: model, downloads: downloads,
                    installedRepositoryNames: downloadSummary.installedRepositoryNames,
                    activeDownloadCount: downloadSummary.activeCount,
                    catalogSection: $catalogSection, selectedDetailTab: $selectedDetailTab,
                    unavailableScreenshotURLs: $unavailableScreenshotURLs,
                    inAppBrowserPage: $inAppBrowserPage
                )
            case .developerTools:
                DeveloperToolsCatalogView(
                    developerTools: developerTools, downloads: downloads,
                    activeDownloadCount: downloadSummary.activeCount, catalogSection: $catalogSection
                )
            }
        }
        .onAppear {
#if DEBUG
            if ProcessInfo.processInfo.environment["GITGATTO_DEVELOPER_TOOLS_PREVIEW"] == "1" {
                catalogSection = .developerTools
            }
#endif
        }
        .onChange(of: downloadSummary.installedRepositoryNames) { _, names in
            guard model.collection == .installed else { return }
            model.changeCollection(.installed, installedRepositoryNames: names)
        }
    }
}

struct MarketplaceInformationCell: View {
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

struct MarketplaceScreenshotView: View {
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

struct MarketplaceScreenshotCarousel: View {
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

enum MarketplaceCatalogSection: String, CaseIterable, Identifiable {
    case applications
    case developerTools

    var id: String { rawValue }
}

extension MarketplaceCollection {
    var symbolName: String {
        switch self {
        case .discover: "square.grid.2x2"
        case .favorites: "star"
        case .installed: "checkmark.seal"
        case .recent: "clock.arrow.circlepath"
        }
    }
}

enum MarketplaceDetailTab: String, CaseIterable, Identifiable {
    case overview
    case releases

    var id: String { rawValue }
}

struct DevelopmentToolLogoView: View {
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

struct MarketplaceLogoView: View {
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

struct MarketplaceApplicationRow: View {
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
