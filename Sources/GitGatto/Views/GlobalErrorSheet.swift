import AppKit
import SwiftUI

struct GlobalErrorSheet: View {
    let report: AppErrorReport
    let canUseAgent: Bool
    let useAgent: () -> Void
    let dismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(palette.danger)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 7) {
                    Text(report.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.ink)
                    Text(report.code)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.danger)
                        .textSelection(.enabled)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Rectangle().fill(palette.divider).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailSection(
                        title: L10n.text("error.section.output"),
                        content: report.message,
                        monospaced: true,
                        palette: palette
                    )

                    VStack(alignment: .leading, spacing: 9) {
                        Text(L10n.text("error.section.details"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(palette.ink)

                        ErrorDetailRow(labelKey: "error.detail.code", value: report.code)
                        ErrorDetailRow(labelKey: "error.detail.operation", value: report.operation)
                        ErrorDetailRow(labelKey: "error.detail.domain", value: report.domain)
                        if let exitCode = report.exitCode {
                            ErrorDetailRow(labelKey: "error.detail.exit_code", value: String(exitCode))
                        }
                        if let systemCode = report.systemCode {
                            ErrorDetailRow(labelKey: "error.detail.system_code", value: String(systemCode))
                        }
                        if let command = report.command {
                            ErrorDetailRow(labelKey: "error.detail.command", value: command)
                        }
                        if let repositoryPath = report.repositoryPath {
                            ErrorDetailRow(labelKey: "error.detail.repository", value: repositoryPath)
                        }
                        ErrorDetailRow(
                            labelKey: "error.detail.time",
                            value: report.occurredAt.formatted(date: .numeric, time: .standard)
                        )
                    }

                    detailSection(
                        title: L10n.text("error.section.recovery"),
                        content: report.recoverySuggestion,
                        monospaced: false,
                        palette: palette
                    )
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Rectangle().fill(palette.divider).frame(height: 1)

            HStack(spacing: 10) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.diagnosticText, forType: .string)
                    copied = true
                } label: {
                    Label(
                        L10n.text(copied ? "error.action.copied" : "error.action.copy"),
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button(L10n.text("action.close"), action: dismiss)
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button(action: useAgent) {
                    Label(L10n.text("error.action.agent_resolve"), systemImage: "sparkles")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canUseAgent)
                .opacity(canUseAgent ? 1 : 0.48)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .frame(height: 64)
            .background(palette.surface)
        }
        .frame(minWidth: 640, idealWidth: 700, minHeight: 480, idealHeight: 560)
        .background(palette.background)
#if DEBUG
        .background(
            DebugSnapshotCapture(
                isReady: ProcessInfo.processInfo.environment["GITGATTO_ERROR_PREVIEW"] == "1"
            )
        )
#endif
    }

    private func detailSection(
        title: String,
        content: String,
        monospaced: Bool,
        palette: AppPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text(content)
                .font(.system(size: 12, weight: .regular, design: monospaced ? .monospaced : .default))
                .foregroundStyle(palette.mutedInk)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(palette.divider, lineWidth: 1)
                }
        }
    }
}

private struct ErrorDetailRow: View {
    let labelKey: String
    let value: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(L10n.text(labelKey))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.subtleInk)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(palette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
