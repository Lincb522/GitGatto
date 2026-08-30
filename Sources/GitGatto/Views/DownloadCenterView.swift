import SwiftUI

struct DownloadCenterView: View {
    @ObservedObject var manager: AppDownloadManager
    let installWithAgent: (AppDownloadRecord) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var pendingInstallID: UUID?

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("downloads.title"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.ink)
                if !manager.records.isEmpty {
                    Text("\(manager.records.count)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.subtleInk)
                }
                Spacer()
                Button {
                    manager.isPresented = false
                } label: {
                    Image(gattoSymbol: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(palette.surface)

            Rectangle().fill(palette.divider).frame(height: 1)

            if manager.records.isEmpty {
                VStack(spacing: 10) {
                    Image(gattoSymbol: "tray.and.arrow.down")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(palette.subtleInk)
                    Text(L10n.text("downloads.empty"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.mutedInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(manager.records) { record in
                            downloadCard(record, palette: palette)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(palette.background)
        .confirmationDialog(
            L10n.text("installer.confirm.title"),
            isPresented: Binding(
                get: { pendingInstallID != nil },
                set: { if !$0 { pendingInstallID = nil } }
            )
        ) {
            Button(L10n.text("installer.action.install")) {
                if let id = pendingInstallID { manager.install(id, replacingExisting: true) }
                pendingInstallID = nil
            }
            Button(L10n.text("action.cancel"), role: .cancel) { pendingInstallID = nil }
        } message: {
            Text(L10n.text("installer.confirm.body"))
        }
    }

    private func downloadCard(_ record: AppDownloadRecord, palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                CircularDownloadIndicator(
                    state: record.state,
                    progress: record.progress,
                    size: 38
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.fileName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(record.repositoryName)
                        Text("·")
                        Text(L10n.text("downloads.state.\(record.state.rawValue)"))
                        if record.expectedBytes > 0 {
                            Text("·")
                            Text(ByteCountFormatter.string(fromByteCount: record.expectedBytes, countStyle: .file))
                        }
                        if record.state == .downloading {
                            Text("·")
                            Text("\(Int(min(1, max(0, record.progress)) * 100))%")
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
                }
                Spacer(minLength: 8)
                actions(record, palette: palette)
            }

            if let error = record.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.danger)
                    .textSelection(.enabled)
            }
        }
        .padding(13)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(palette.divider, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func actions(_ record: AppDownloadRecord, palette: AppPalette) -> some View {
        HStack(spacing: 5) {
            switch record.state {
            case .queued, .downloading:
                miniButton("downloads.action.pause", icon: "pause") { manager.pause(record.id) }
                miniButton("downloads.action.cancel", icon: "xmark") { manager.cancel(record.id) }
            case .paused, .failed:
                miniButton("downloads.action.resume", icon: "play.circle") { manager.resume(record.id) }
                miniButton("downloads.action.cancel", icon: "xmark") { manager.cancel(record.id) }
            case .completed:
                miniButton("downloads.action.reveal", icon: "folder") { manager.reveal(record.id) }
                if record.canInstallOnMac {
                    miniButton("installer.action.install", icon: "arrow.down.app") { pendingInstallID = record.id }
                } else {
                    miniButton("installer.action.agent", icon: "sparkles") { installWithAgent(record) }
                }
            case .installed:
                miniButton("downloads.action.reveal", icon: "folder") { manager.reveal(record.id) }
            case .cancelled:
                miniButton("downloads.action.remove", icon: "trash") { manager.remove(record.id) }
            case .installing:
                EmptyView()
            }
        }
    }

    private func miniButton(_ key: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(gattoSymbol: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 25, height: 25)
        }
        .buttonStyle(.plain)
        .help(L10n.text(key))
    }

}
