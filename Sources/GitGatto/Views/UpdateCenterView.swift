import AppKit
import SwiftUI

struct UpdateCenterView: View {
    @ObservedObject var manager: AppUpdateManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: AppThemeLayout.panelSpacing) {
            HStack(spacing: 12) {
                AppBrandLockup(iconSize: 36, wordmarkWidth: 94, spacing: 8)
                    .padding(.leading, 46)
                Rectangle().fill(palette.divider).frame(width: 1, height: 26)
                Text(L10n.text("update.title"))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 66)
            .background(palette.sidebar.opacity(0.18))
            .appGlassPanel(cornerRadius: 16, elevated: false)

            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(statusColor(palette).opacity(0.12))
                        statusIcon
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(statusColor(palette))
                    }
                    .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(statusTitle)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(palette.ink)
                        Text(statusDetail)
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    VersionMetric(
                        titleKey: "update.current_version",
                        value: manager.currentVersion
                    )
                    VersionMetric(
                        titleKey: "update.current_build",
                        value: manager.currentBuild
                    )
                    VersionMetric(
                        titleKey: "update.channel",
                        value: L10n.text("update.channel.stable")
                    )
                }

                VStack(spacing: 0) {
                    UpdateToggleRow(
                        titleKey: "update.automatic_checks",
                        detailKey: "update.automatic_checks.body",
                        isOn: Binding(
                            get: { manager.automaticallyChecksForUpdates },
                            set: { enabled in
                                manager.setAutomaticallyChecksForUpdates(enabled)
                            }
                        ),
                        isEnabled: manager.isConfigured
                    )
                    Rectangle().fill(palette.divider).frame(height: 1)
                    UpdateToggleRow(
                        titleKey: "update.automatic_downloads",
                        detailKey: "update.automatic_downloads.body",
                        isOn: Binding(
                            get: { manager.automaticallyDownloadsUpdates },
                            set: { enabled in
                                manager.setAutomaticallyDownloadsUpdates(enabled)
                            }
                        ),
                        isEnabled: manager.isConfigured
                    )
                }
                .background(palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.divider, lineWidth: 1)
                }

                HStack(spacing: 10) {
                    if let lastCheckedAt = manager.lastCheckedAt {
                        Text(L10n.format(
                            "update.last_checked",
                            lastCheckedAt.formatted(date: .abbreviated, time: .shortened)
                        ))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.subtleInk)
                    }
                    Spacer()
                    if manager.isConfigured {
                        Button(L10n.text("update.check")) {
                            manager.checkForUpdates()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!manager.canCheckForUpdates)
                    } else {
                        Button(L10n.text("update.view_releases")) {
                            NSWorkspace.shared.open(AppLinks.releases)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.surface.opacity(0.18))
            .appGlassPanel()
        }
        .padding(AppThemeLayout.workspaceInset)
        .frame(minWidth: 620, minHeight: 500)
        .background(Color.clear)
        .ignoresSafeArea(.container, edges: .top)
#if DEBUG
        .background(
            DebugSnapshotCapture(
                isReady: ProcessInfo.processInfo.environment["GITGATTO_UPDATE_PREVIEW"] == "1"
            )
        )
#endif
    }

    private var statusTitle: String {
        switch manager.state {
        case .configurationRequired: L10n.text("update.status.configuration_required")
        case .ready: L10n.text("update.status.ready")
        case .checking: L10n.text("update.status.checking")
        case .current: L10n.text("update.status.current")
        case let .updateAvailable(version, _): L10n.format("update.status.available", version)
        case .failed: L10n.text("update.status.failed")
        }
    }

    private var statusDetail: String {
        switch manager.state {
        case .configurationRequired: L10n.text("update.status.configuration_required.body")
        case .ready: L10n.text("update.status.ready.body")
        case .checking: L10n.text("update.status.checking.body")
        case .current: L10n.text("update.status.current.body")
        case let .updateAvailable(_, build): L10n.format("update.status.available.body", build)
        case let .failed(message): message
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if manager.state == .checking {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: statusSymbol)
        }
    }

    private var statusSymbol: String {
        switch manager.state {
        case .configurationRequired: "key.slash"
        case .ready: "arrow.down.app"
        case .checking: "arrow.triangle.2.circlepath"
        case .current: "checkmark.seal.fill"
        case .updateAvailable: "arrow.down.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(_ palette: AppPalette) -> Color {
        switch manager.state {
        case .current: palette.success
        case .failed, .configurationRequired: palette.warning
        default: palette.primary
        }
    }
}

private struct VersionMetric: View {
    let titleKey: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(titleKey))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.ink)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct UpdateToggleRow: View {
    let titleKey: String
    let detailKey: String
    @Binding var isOn: Bool
    let isEnabled: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(titleKey))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text(L10n.text(detailKey))
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.mutedInk)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .disabled(!isEnabled)
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 62)
    }
}
