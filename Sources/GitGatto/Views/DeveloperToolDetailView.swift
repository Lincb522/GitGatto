import SwiftUI

struct DeveloperToolDetailView: View {
    @StateObject private var observation: DeveloperToolsObservation
    @Binding var pendingToolInstall: DevelopmentTool?
    @Binding var pendingToolUpgrade: DevelopmentTool?
    @Environment(\.colorScheme) private var colorScheme
    private var developerTools: DeveloperToolsViewModel { observation.model }

    init(model: DeveloperToolsViewModel, pendingInstall: Binding<DevelopmentTool?>,
         pendingUpgrade: Binding<DevelopmentTool?>) {
        _observation = StateObject(wrappedValue: DeveloperToolsObservation(model: model, scope: .selectedTool))
        _pendingToolInstall = pendingInstall
        _pendingToolUpgrade = pendingUpgrade
    }

    var body: some View {
        developerToolDetailPane(AppPalette(colorScheme))
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
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(gattoSymbol: status.state == .installed
                            ? "terminal"
                            : "exclamationmark.triangle")
                        Text(L10n.text(status.state == .installed
                            ? "developer_tools.result.agent_log"
                            : "developer_tools.result.unverified_agent_log"))
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(status.state == .installed ? palette.mutedInk : palette.warning)

                    Text(result)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.ink)
                        .textSelection(.enabled)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(status.state == .installed ? palette.raisedSurface : palette.warningSoft.opacity(0.42))
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

}
