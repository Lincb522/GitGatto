import AppKit
import SwiftUI

struct RepositoryDiagnosticsView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            commandBar(palette)
            Rectangle().fill(palette.divider).frame(height: 1)
            if let diagnostics = model.repositoryDiagnostics {
                diagnosticsContent(diagnostics, palette: palette)
            } else if model.activeDiagnosticOperation == .refresh {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 9) {
                    Image(gattoSymbol: "stethoscope")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(palette.subtleInk)
                    Text(L10n.text("diagnostics.empty"))
                        .font(font(size: 12, weight: .medium))
                        .foregroundStyle(palette.mutedInk)
                    Button(L10n.text("diagnostics.run")) {
                        model.refreshRepositoryDiagnostics()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme == .softGlass ? Color.clear : palette.background)
        .task(id: model.snapshot?.rootURL.standardizedFileURL.path) {
            if model.repositoryDiagnostics == nil, model.snapshot != nil {
                model.refreshRepositoryDiagnostics()
            }
        }
    }

    private func commandBar(_ palette: AppPalette) -> some View {
        HStack(spacing: 11) {
            Text(L10n.text("diagnostics.title"))
                .font(font(size: 15, weight: .semibold))
                .foregroundStyle(palette.ink)
            if let diagnostics = model.repositoryDiagnostics {
                DiagnosticSummaryBadge(count: diagnostics.attentionCount, theme: theme)
            }
            Spacer()
            if model.repositoryDiagnostics != nil {
                Button(L10n.text("diagnostics.hooks.reveal")) {
                    model.revealHooksDirectory()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            ToolbarIconButton(
                systemName: "arrow.clockwise",
                helpKey: "action.refresh",
                isActive: model.activeDiagnosticOperation == .refresh,
                isDisabled: model.activeDiagnosticOperation != nil
            ) {
                model.refreshRepositoryDiagnostics()
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .background(theme == .softGlass ? palette.surface.opacity(0.16) : palette.surface)
    }

    private func diagnosticsContent(_ diagnostics: RepositoryDiagnostics, palette: AppPalette) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                DiagnosticStatusStrip(diagnostics: diagnostics, theme: theme)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 14) {
                            gitPanel(diagnostics, palette: palette)
                            identityPanel(diagnostics, palette: palette)
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 14) {
                            lfsPanel(diagnostics, palette: palette)
                            hooksPanel(diagnostics, palette: palette)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    VStack(spacing: 14) {
                        gitPanel(diagnostics, palette: palette)
                        identityPanel(diagnostics, palette: palette)
                        lfsPanel(diagnostics, palette: palette)
                        hooksPanel(diagnostics, palette: palette)
                    }
                }
            }
            .padding(16)
        }
    }

    private func gitPanel(_ diagnostics: RepositoryDiagnostics, palette: AppPalette) -> some View {
        DiagnosticPanel(
            titleKey: "diagnostics.git.title",
            icon: "point.3.filled.connected.trianglepath.dotted",
            status: diagnostics.gitStatus,
            theme: theme
        ) {
            DiagnosticValueRow(labelKey: "diagnostics.git.version", value: diagnostics.gitVersion, monospaced: true)
            DiagnosticValueRow(labelKey: "diagnostics.git.executable", value: diagnostics.gitExecutablePath, monospaced: true)
            DiagnosticValueRow(labelKey: "diagnostics.git.repository", value: diagnostics.repositoryRoot.path, monospaced: true)
            DiagnosticValueRow(
                labelKey: "diagnostics.git.integrity",
                value: L10n.text(diagnostics.objectDatabaseHealthy ? "diagnostics.status.passed" : "diagnostics.status.failed"),
                valueColor: diagnostics.objectDatabaseHealthy ? palette.success : palette.danger
            )
            if let message = diagnostics.objectDatabaseMessage {
                Text(message)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(palette.danger)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.dangerSoft)
            }
        }
    }

    private func identityPanel(_ diagnostics: RepositoryDiagnostics, palette: AppPalette) -> some View {
        DiagnosticPanel(
            titleKey: "diagnostics.identity.title",
            icon: "person.crop.circle",
            status: diagnostics.identityStatus,
            theme: theme
        ) {
            DiagnosticValueRow(
                labelKey: "diagnostics.identity.name",
                value: diagnostics.userName ?? L10n.text("diagnostics.not_configured")
            )
            DiagnosticValueRow(
                labelKey: "diagnostics.identity.email",
                value: diagnostics.userEmail ?? L10n.text("diagnostics.not_configured")
            )
        }
    }

    private func lfsPanel(_ diagnostics: RepositoryDiagnostics, palette: AppPalette) -> some View {
        DiagnosticPanel(
            titleKey: "diagnostics.lfs.title",
            icon: "externaldrive.badge.timemachine",
            status: diagnostics.lfsStatus,
            theme: theme
        ) {
            DiagnosticValueRow(
                labelKey: "diagnostics.lfs.runtime",
                value: diagnostics.lfsVersion ?? L10n.text("diagnostics.lfs.unavailable"),
                monospaced: diagnostics.lfsVersion != nil
            )
            DiagnosticValueRow(
                labelKey: "diagnostics.lfs.attributes",
                value: L10n.text(diagnostics.usesLFS ? "diagnostics.lfs.in_use" : "diagnostics.lfs.not_in_use")
            )
            DiagnosticValueRow(
                labelKey: "diagnostics.lfs.filter",
                value: L10n.text(diagnostics.lfsFilterConfigured ? "diagnostics.status.configured" : "diagnostics.status.not_configured")
            )
            DiagnosticValueRow(
                labelKey: "diagnostics.lfs.files",
                value: "\(diagnostics.lfsTrackedFileCount)"
            )
            if let error = diagnostics.lfsError, diagnostics.usesLFS {
                Text(error)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(palette.danger)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.dangerSoft)
            }
            if diagnostics.lfsVersion != nil,
               diagnostics.usesLFS,
               (!diagnostics.lfsFilterConfigured || !diagnostics.hooks.contains(where: { $0.name == "pre-push" })) {
                HStack {
                    Spacer()
                    Button(L10n.text("diagnostics.lfs.configure")) {
                        Task { await model.configureRepositoryLFS() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.activeDiagnosticOperation != nil)
                }
                .padding(.top, 4)
            }
        }
    }

    private func hooksPanel(_ diagnostics: RepositoryDiagnostics, palette: AppPalette) -> some View {
        DiagnosticPanel(
            titleKey: "diagnostics.hooks.title",
            icon: "link",
            status: diagnostics.hooksStatus,
            theme: theme
        ) {
            DiagnosticValueRow(
                labelKey: "diagnostics.hooks.path",
                value: diagnostics.hooksDirectory.path,
                monospaced: true
            )
            if diagnostics.hooks.isEmpty {
                Text(L10n.text("diagnostics.hooks.empty"))
                    .font(font(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(diagnostics.hooks.enumerated()), id: \.element.id) { index, hook in
                        if index > 0 { Rectangle().fill(palette.divider).frame(height: 1) }
                        HStack(spacing: 9) {
                            Image(gattoSymbol: hook.isExecutable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(hook.isExecutable ? palette.success : palette.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hook.name)
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.ink)
                                Text(ByteCountFormatter.string(fromByteCount: hook.size, countStyle: .file))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(palette.subtleInk)
                            }
                            Spacer()
                            if hook.isSymbolicLink {
                                Text(L10n.text("diagnostics.hook.symlink"))
                                    .font(font(size: 9, weight: .semibold))
                                    .foregroundStyle(palette.mutedInk)
                            }
                            if !hook.isExecutable {
                                Button(L10n.text("diagnostics.hook.repair")) {
                                    Task { await model.repairHookPermission(hook) }
                                }
                                .buttonStyle(.borderless)
                                .disabled(model.activeDiagnosticOperation != nil)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func font(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: theme == .console ? .monospaced : .default)
    }
}

private struct DiagnosticSummaryBadge: View {
    let count: Int
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 5) {
            Image(gattoSymbol: count == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(count == 0 ? L10n.text("diagnostics.summary.passed") : L10n.format("diagnostics.summary.attention", count))
        }
        .font(.system(size: 9.5, weight: .semibold, design: theme == .console ? .monospaced : .default))
        .foregroundStyle(count == 0 ? palette.success : palette.warning)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(count == 0 ? palette.successSoft : palette.warningSoft)
        .clipShape(Capsule())
    }
}

private struct DiagnosticStatusStrip: View {
    let diagnostics: RepositoryDiagnostics
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 0) {
            item("diagnostics.git.title", icon: "point.3.filled.connected.trianglepath.dotted", status: diagnostics.gitStatus, palette: palette)
            Rectangle().fill(palette.divider).frame(width: 1, height: 30)
            item("diagnostics.identity.title", icon: "person.crop.circle", status: diagnostics.identityStatus, palette: palette)
            Rectangle().fill(palette.divider).frame(width: 1, height: 30)
            item("diagnostics.lfs.title", icon: "externaldrive", status: diagnostics.lfsStatus, palette: palette)
            Rectangle().fill(palette.divider).frame(width: 1, height: 30)
            item("diagnostics.hooks.title", icon: "link", status: diagnostics.hooksStatus, palette: palette)
        }
        .frame(height: 58)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme == .console ? 4 : 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme == .console ? 4 : 10, style: .continuous)
                .stroke(palette.divider, lineWidth: 1)
        }
    }

    private func item(
        _ key: String,
        icon: String,
        status: RepositoryDiagnosticStatus,
        palette: AppPalette
    ) -> some View {
        HStack(spacing: 8) {
            Image(gattoSymbol: icon)
                .foregroundStyle(status.color(palette))
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(key))
                    .font(.system(size: 10.5, weight: .semibold, design: theme == .console ? .monospaced : .default))
                    .foregroundStyle(palette.ink)
                Text(L10n.text(status.titleKey))
                    .font(.system(size: 9.5, design: theme == .console ? .monospaced : .default))
                    .foregroundStyle(status.color(palette))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
    }
}

private struct DiagnosticPanel<Content: View>: View {
    let titleKey: String
    let icon: String
    let status: RepositoryDiagnosticStatus
    let theme: AppVisualTheme
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(gattoSymbol: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(status.color(palette))
                Text(L10n.text(titleKey))
                    .font(.system(size: 12, weight: .semibold, design: theme == .console ? .monospaced : .default))
                    .foregroundStyle(palette.ink)
                Spacer()
                Text(L10n.text(status.titleKey))
                    .font(.system(size: 9, weight: .semibold, design: theme == .console ? .monospaced : .default))
                    .foregroundStyle(status.color(palette))
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            Rectangle().fill(palette.divider).frame(height: 1)
            VStack(spacing: 0) {
                content
            }
            .padding(12)
        }
        .background(theme == .softGlass ? palette.surface.opacity(0.15) : palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme == .console ? 4 : 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme == .console ? 4 : 10, style: .continuous)
                .stroke(palette.divider, lineWidth: 1)
        }
    }
}

private struct DiagnosticValueRow: View {
    let labelKey: String
    let value: String
    var monospaced = false
    var valueColor: Color?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(L10n.text(labelKey))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.mutedInk)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: monospaced ? .monospaced : .default))
                .foregroundStyle(valueColor ?? palette.ink)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}

private extension RepositoryDiagnosticStatus {
    var titleKey: String {
        switch self {
        case .passed: "diagnostics.status.passed"
        case .attention: "diagnostics.status.attention"
        case .failed: "diagnostics.status.failed"
        case .unavailable: "diagnostics.status.unavailable"
        }
    }

    func color(_ palette: AppPalette) -> Color {
        switch self {
        case .passed: palette.success
        case .attention: palette.warning
        case .failed: palette.danger
        case .unavailable: palette.subtleInk
        }
    }
}
