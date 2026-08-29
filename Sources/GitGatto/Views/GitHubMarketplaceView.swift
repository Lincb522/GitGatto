import SwiftUI

struct GitHubMarketplaceView: View {
    @ObservedObject var model: GitHubMarketplaceViewModel
    @ObservedObject var downloads: AppDownloadManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedReleaseID: Int64?
    @State private var inAppBrowserPage: InAppBrowserPage?

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

            if model.applications.isEmpty && !model.isLoading {
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
                                selectedReleaseID = application.latestRelease.id
                                model.select(application)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 15) {
                        GitHubLanguageIcon(
                            language: application.repository.language,
                            isPrivate: false,
                            size: 58
                        )
                        VStack(alignment: .leading, spacing: 5) {
                            Text(application.repository.name)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(palette.ink)
                            Text(application.repository.fullName)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.subtleInk)
                            if let description = application.repository.description, !description.isEmpty {
                                Text(description)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(palette.mutedInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 7) {
                            GattoLabel(
                                GitHubNumberFormatter.string(application.repository.stars),
                                systemImage: "star"
                            )
                            GattoLabel(
                                GitHubNumberFormatter.string(application.repository.forks),
                                systemImage: "arrow.triangle.branch"
                            )
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.subtleInk)
                    }

                    Picker(L10n.text("marketplace.release"), selection: Binding(
                        get: { selectedReleaseID ?? model.releases.first?.id ?? 0 },
                        set: { selectedReleaseID = $0 }
                    )) {
                        ForEach(model.releases) { release in
                            Text("\(release.name) · \(release.tagName)").tag(release.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 360, alignment: .leading)

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

                        if !release.body.isEmpty {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(L10n.text("github.releases.notes"))
                                    .font(.system(size: 13, weight: .semibold))
                                ReleaseNotesMarkdownView(text: release.body) { url in
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

                    if let error = model.error {
                        Text(error)
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.danger)
                            .textSelection(.enabled)
                    }
                }
                .padding(24)
            }
        } else if model.isLoading {
            ProgressView(L10n.text("marketplace.loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func selectedRelease(for application: MarketplaceApplication) -> GitHubRelease? {
        if let selectedReleaseID, let release = model.releases.first(where: { $0.id == selectedReleaseID }) {
            return release
        }
        return model.releases.first ?? application.latestRelease
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
