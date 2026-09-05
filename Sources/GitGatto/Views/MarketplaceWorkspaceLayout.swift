import SwiftUI

struct MarketplaceCatalogHeader<Controls: View>: View {
    @Binding var section: MarketplaceCatalogSection
    let activeDownloadCount: Int
    let showDownloads: () -> Void
    @ViewBuilder var controls: (Bool) -> Controls
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        GeometryReader { proxy in
            let compact = proxy.size.width < 860
            HStack(spacing: compact ? 8 : 10) {
                if compact {
                    Image(gattoSymbol: section == .applications ? "arrow.down.app" : "hammer")
                        .foregroundStyle(palette.primary)
                        .frame(width: 22, height: 32)
                        .help(L10n.text("marketplace.title"))
                        .accessibilityLabel(L10n.text("marketplace.title"))
                } else {
                    HStack(spacing: 8) {
                        Image(gattoSymbol: section == .applications ? "arrow.down.app" : "hammer")
                            .foregroundStyle(palette.primary)
                        Text(L10n.text("marketplace.title"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.ink)
                    }
                    .fixedSize()
                }
                Picker("", selection: $section) {
                    ForEach(MarketplaceCatalogSection.allCases) { section in
                        Text(L10n.text("marketplace.section.\(section.rawValue)")).tag(section)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: compact ? 146 : 196)
                controls(compact)
                Spacer(minLength: 8)
                Button(action: showDownloads) {
                    HStack(spacing: 7) {
                        Image(gattoSymbol: "tray.and.arrow.down")
                        if !compact { Text(L10n.text("downloads.title")) }
                        if activeDownloadCount > 0 {
                            Text("\(activeDownloadCount)")
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
        .frame(height: 62)
        .background(palette.surface)
    }
}

struct MarketplaceWorkspaceLayout<Header: View, Catalog: View, Detail: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var catalog: () -> Catalog
    @ViewBuilder var detail: () -> Detail
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue

    var body: some View {
        let palette = AppPalette(colorScheme)
        let theme = AppVisualTheme.resolved(themeRaw)
        Group {
            if theme == .emerald {
                VStack(spacing: 10) {
                    header()
                        .emeraldSurface(.elevated, cornerRadius: 16)
                    HStack(spacing: 10) {
                        catalog()
                            .frame(minWidth: 220, idealWidth: 280, maxWidth: 380)
                            .emeraldSurface(.elevated, cornerRadius: 16)
                        detail()
                            .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
                            .emeraldSurface(.panel, cornerRadius: 16)
                    }
                }
                .padding(10)
            } else if theme == .folio {
                VStack(spacing: 10) {
                    header()
                        .folioSurface(.elevated, cornerRadius: 16)
                    HStack(spacing: 10) {
                        catalog()
                            .frame(minWidth: 220, idealWidth: 280, maxWidth: 380)
                            .folioSurface(.elevated, cornerRadius: 16)
                        detail()
                            .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
                            .folioSurface(.panel, cornerRadius: 16)
                    }
                }
                .padding(10)
            } else {
                VStack(spacing: 0) {
                    header()
                    Rectangle().fill(palette.divider).frame(height: 1)
                    HSplitView {
                        catalog()
                            .frame(minWidth: 220, idealWidth: 280, maxWidth: 380)
                        detail()
                            .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(palette.background)
    }
}
