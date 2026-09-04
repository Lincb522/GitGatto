import SwiftUI

struct RepositorySyncWorkspaceView: View {
    @ObservedObject var syncModel: RepositorySyncViewModel
    let openRepository: (URL) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            summary(palette)
            Rectangle().fill(palette.divider).frame(height: 1)
            operationBar(palette)
            Rectangle().fill(palette.divider).frame(height: 1)

            if syncModel.statuses.isEmpty, syncModel.isRefreshing {
                GattoLoadingState(text: L10n.text("sync.loading"))
            } else if syncModel.statuses.isEmpty {
                InspectorEmptyState(
                    image: "arrow.triangle.2.circlepath",
                    titleKey: "sync.empty.title",
                    bodyKey: "sync.empty.body"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(syncModel.statuses) { status in
                            RepositorySyncRow(
                                status: status,
                                isSelected: syncModel.selectedRepositoryIDs.contains(status.id),
                                runningOperation: syncModel.runningRepositories[status.id],
                                result: result(for: status),
                                toggleSelection: { syncModel.toggleSelection(status) },
                                openRepository: { openRepository(status.repositoryURL) }
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(palette.surface)
    }

    private func summary(_ palette: AppPalette) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text("sync.title"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text(L10n.format("sync.repository_count", syncModel.statuses.count))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
            }

            Spacer(minLength: 8)

            SyncMetric(value: count(.behind), labelKey: "sync.metric.behind", color: palette.warning)
            SyncMetric(value: count(.ahead), labelKey: "sync.metric.ahead", color: palette.primary)
            SyncMetric(value: count(.conflicted) + count(.diverged), labelKey: "sync.metric.attention", color: palette.danger)

            Button {
                syncModel.load(repositories: syncModel.statuses.map(\.repositoryURL), force: true)
            } label: {
                if syncModel.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(gattoSymbol: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .help(L10n.text("action.refresh"))
            .disabled(syncModel.isRefreshing || syncModel.activeBatchOperation != nil)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 68)
        .background(palette.surface)
    }

    private func operationBar(_ palette: AppPalette) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                selectionControls(palette)
                Spacer(minLength: 10)
                operationControls(palette)
            }
            VStack(alignment: .leading, spacing: 8) {
                selectionControls(palette)
                operationControls(palette)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(palette.raisedSurface.opacity(0.62))
    }

    private func selectionControls(_ palette: AppPalette) -> some View {
        HStack(spacing: 8) {
            Text(L10n.format("sync.selected_count", syncModel.selectedRepositoryIDs.count))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.mutedInk)

            Menu {
                ForEach(RepositoryBatchOperation.allCases) { operation in
                    Button(L10n.text("sync.select.\(operation.rawValue)")) {
                        syncModel.selectEligible(for: operation)
                    }
                }
                Divider()
                Button(L10n.text("sync.select.clear")) { syncModel.clearSelection() }
            } label: {
                Label(L10n.text("sync.select.menu"), systemImage: "checklist")
                    .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if !syncModel.failedResults.isEmpty {
                Button {
                    syncModel.retryFailures()
                } label: {
                    Label(
                        L10n.format("sync.retry_failed", syncModel.failedResults.count),
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.borderless)
                .foregroundStyle(palette.danger)
            }
        }
    }

    private func operationControls(_ palette: AppPalette) -> some View {
        HStack(spacing: 8) {
            ForEach(RepositoryBatchOperation.allCases) { operation in
                operationButton(operation, palette: palette)
            }

            if syncModel.activeBatchOperation != nil {
                Button(L10n.text("action.cancel")) { syncModel.cancel() }
                    .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func operationButton(_ operation: RepositoryBatchOperation, palette: AppPalette) -> some View {
        let isRunning = syncModel.activeBatchOperation == operation
        let button = Button {
            syncModel.run(operation)
        } label: {
            HStack(spacing: 6) {
                if isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(gattoSymbol: operation.symbol)
                }
                Text(L10n.text("sync.action.\(operation.rawValue)"))
            }
            .frame(minWidth: 64)
        }
        .disabled(!canRun(operation))

        if operation == .fetch {
            button.buttonStyle(.bordered)
        } else {
            button.buttonStyle(.borderedProminent)
                .tint(operation == .pull ? palette.primary : palette.accent)
        }
    }

    private func canRun(_ operation: RepositoryBatchOperation) -> Bool {
        syncModel.activeBatchOperation == nil
            && syncModel.statuses.contains {
                syncModel.selectedRepositoryIDs.contains($0.id) && $0.supports(operation)
            }
    }

    private func count(_ health: RepositorySyncHealth) -> Int {
        syncModel.statuses.filter { $0.health == health }.count
    }

    private func result(for status: RepositorySyncStatus) -> RepositoryBatchResult? {
        RepositoryBatchOperation.allCases.lazy.compactMap {
            syncModel.lastResults["\($0.rawValue):\(status.repositoryURL.standardizedFileURL.path)"]
        }.first
    }
}

private struct RepositorySyncRow: View {
    let status: RepositorySyncStatus
    let isSelected: Bool
    let runningOperation: RepositoryBatchOperation?
    let result: RepositoryBatchResult?
    let toggleSelection: () -> Void
    let openRepository: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 12) {
            Button(action: toggleSelection) {
                Image(gattoSymbol: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.primary : palette.subtleInk)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text(isSelected ? "sync.selection.remove" : "sync.selection.add"))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(status.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    SyncHealthBadge(health: status.health)
                    if let runningOperation {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.mini)
                            Text(L10n.text("sync.running.\(runningOperation.rawValue)"))
                        }
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(palette.primary)
                    }
                }
                HStack(spacing: 8) {
                    Label(status.branch.isEmpty ? "—" : status.branch, systemImage: "arrow.triangle.branch")
                    if let upstream = status.upstream {
                        Text(upstream).lineLimit(1)
                    }
                    if let date = status.lastCommitAt {
                        Text(date.formatted(.relative(presentation: .named)))
                    }
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.subtleInk)

                if let message = status.errorMessage ?? (result?.succeeded == false ? result?.message : nil) {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.danger)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                if status.aheadCount > 0 {
                    SyncValue(symbol: "arrow.up", value: status.aheadCount, color: palette.primary)
                }
                if status.behindCount > 0 {
                    SyncValue(symbol: "arrow.down", value: status.behindCount, color: palette.warning)
                }
                if status.changedFileCount > 0 {
                    SyncValue(symbol: "doc.badge.ellipsis", value: status.changedFileCount, color: palette.mutedInk)
                }
            }

            Button(action: openRepository) {
                Image(gattoSymbol: "arrow.right")
            }
            .buttonStyle(.bordered)
            .help(L10n.text("sync.open_repository"))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(isSelected ? palette.primarySoft : (isHovering ? palette.raisedSurface : palette.surface))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? palette.primary.opacity(0.45) : palette.divider, lineWidth: 1)
        }
        .onHover { isHovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { toggleSelection() }
    }
}

private struct SyncMetric: View {
    let value: Int
    let labelKey: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(value)").font(.system(size: 12, weight: .bold, design: .rounded))
            Text(L10n.text(labelKey)).font(.system(size: 10.5, weight: .medium))
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(color.opacity(0.09))
        .clipShape(Capsule())
    }
}

private struct SyncValue: View {
    let symbol: String
    let value: Int
    let color: Color

    var body: some View {
        Label("\(value)", systemImage: symbol)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(color.opacity(0.09))
            .clipShape(Capsule())
    }
}

private struct SyncHealthBadge: View {
    let health: RepositorySyncHealth
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        Text(L10n.text("sync.health.\(health.rawValue)"))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color(palette))
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(color(palette).opacity(0.1))
            .clipShape(Capsule())
    }

    private func color(_ palette: AppPalette) -> Color {
        switch health {
        case .clean: palette.success
        case .ahead: palette.primary
        case .behind, .changed, .noUpstream: palette.warning
        case .diverged, .conflicted, .unavailable: palette.danger
        }
    }
}

private extension RepositoryBatchOperation {
    var symbol: String {
        switch self {
        case .fetch: "arrow.triangle.2.circlepath"
        case .pull: "arrow.down"
        case .push: "arrow.up"
        }
    }
}
