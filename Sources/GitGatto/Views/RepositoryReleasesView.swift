import SwiftUI

struct RepositoryReleasesView: View {
    @ObservedObject var model: WorkspaceViewModel
    @ObservedObject var downloads: AppDownloadManager
    let openURL: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedReleaseID: Int64?
    @State private var platform: MarketplacePlatform = .macOS

    private var selectedRelease: GitHubRelease? {
        model.githubReleases.first { $0.id == selectedReleaseID } ?? model.githubReleases.first
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text(L10n.text("github.releases.title"))
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    if model.isLoadingGitHubReleases { ProgressView().controlSize(.small) }
                    Button { model.loadGitHubReleases() } label: {
                        Image(gattoSymbol: "arrow.clockwise")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.text("action.refresh"))
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                Rectangle().fill(palette.divider).frame(height: 1)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.githubReleases) { release in
                            Button {
                                selectedReleaseID = release.id
                            } label: {
                                HStack(spacing: 9) {
                                    Image(gattoSymbol: "shippingbox")
                                        .foregroundStyle(palette.primary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(release.name)
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundStyle(palette.ink)
                                            .lineLimit(1)
                                        Text(release.tagName)
                                            .font(.system(size: 9.5, design: .monospaced))
                                            .foregroundStyle(palette.subtleInk)
                                    }
                                    Spacer()
                                    Text("\(release.assets.count)")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(palette.subtleInk)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 44)
                                .background(selectedRelease?.id == release.id ? palette.primarySoft : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(7)
                }
            }
            .frame(minWidth: 205, idealWidth: 240, maxWidth: 320)
            .background(palette.sidebar)

            releaseDetail(selectedRelease, palette: palette)
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            selectedReleaseID = selectedRelease?.id
            if model.githubReleases.isEmpty { model.loadGitHubReleases() }
        }
    }

    @ViewBuilder
    private func releaseDetail(_ release: GitHubRelease?, palette: AppPalette) -> some View {
        if model.isLoadingGitHubReleases, release == nil {
            GattoLoadingState(text: L10n.text("github.releases.loading"))
        } else if let error = model.githubReleasesError, release == nil {
            Text(error)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.danger)
                .textSelection(.enabled)
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let release {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(release.name)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(palette.ink)
                            HStack(spacing: 8) {
                                Text(release.tagName)
                                if release.isPrerelease { Text(L10n.text("github.releases.prerelease")) }
                                if let date = release.publishedAt {
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                }
                            }
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.subtleInk)
                        }
                        Spacer()
                        Button {
                            downloads.isPresented = true
                        } label: {
                            GattoLabel(L10n.text("downloads.title"), systemImage: "tray.and.arrow.down")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    Picker(L10n.text("marketplace.platform"), selection: $platform) {
                        ForEach(MarketplacePlatform.allCases) { platform in
                            Text(L10n.text("marketplace.platform.\(platform.rawValue)"))
                                .tag(platform)
                        }
                    }
                    .pickerStyle(.segmented)

                    let assets = release.assets.filter { platform.supports($0) }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("github.releases.assets"))
                            .font(.system(size: 13, weight: .semibold))
                        if assets.isEmpty {
                            Text(L10n.text("github.releases.assets.empty"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.mutedInk)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(assets) { asset in
                                ReleaseAssetRow(
                                    asset: asset,
                                    repositoryName: model.selectedGitHubRepository?.fullName ?? "",
                                    downloads: downloads
                                )
                            }
                        }
                    }

                    if !release.body.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.text("github.releases.notes"))
                                .font(.system(size: 13, weight: .semibold))
                            ReleaseNotesMarkdownView(text: release.body, openURL: openURL)
                        }
                    }
                }
                .padding(22)
            }
        } else {
            ProjectEmptyState(systemImage: "shippingbox", titleKey: "github.releases.empty")
        }
    }
}

struct ReleaseAssetRow: View {
    let asset: GitHubReleaseAsset
    let repositoryName: String
    @ObservedObject var downloads: AppDownloadManager
    var quickInstall: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    private var record: AppDownloadRecord? {
        downloads.records.first { $0.assetID == asset.id && $0.sourceURL == asset.downloadURL }
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.primarySoft)
                Image(gattoSymbol: assetIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.primary)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(asset.name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file))
                    Text(L10n.format("github.releases.downloads", asset.downloadCount))
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            }
            Spacer(minLength: 8)
            if let record {
                HStack(spacing: 7) {
                    Button {
                        downloads.isPresented = true
                    } label: {
                        HStack(spacing: 7) {
                            CircularDownloadIndicator(
                                state: record.state,
                                progress: record.progress,
                                size: 28
                            )
                            Text(downloadStatus(record))
                                .font(.system(size: 10.5, weight: .semibold))
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    if record.state == .completed, let quickInstall {
                        Button(L10n.text("marketplace.quick_install.action"), action: quickInstall)
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
            } else {
                if let quickInstall {
                    HStack(spacing: 7) {
                        Button(L10n.text("github.releases.download")) {
                            downloads.start(asset: asset, repositoryName: repositoryName)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        Button(L10n.text("marketplace.quick_install.action"), action: quickInstall)
                            .buttonStyle(PrimaryButtonStyle())
                    }
                } else {
                    Button(L10n.text("github.releases.download")) {
                        downloads.start(asset: asset, repositoryName: repositoryName)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .padding(11)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(palette.divider, lineWidth: 1) }
    }

    private var assetIcon: String {
        switch asset.fileExtension {
        case "dmg", "pkg": "arrow.down.app"
        case "zip", "tar.gz", "tar.xz": "archivebox"
        default: "doc"
        }
    }

    private func downloadStatus(_ record: AppDownloadRecord) -> String {
        if record.state == .downloading {
            return "\(Int(min(1, max(0, record.progress)) * 100))%"
        }
        return L10n.text("downloads.state.\(record.state.rawValue)")
    }
}
