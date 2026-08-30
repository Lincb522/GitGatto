import AppKit
import SwiftUI

struct RepositoryScannerView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""

    private var filteredResults: [LocalRepositoryRecord] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return model.repositoryScanResults }
        return model.repositoryScanResults.filter {
            $0.url.lastPathComponent.localizedCaseInsensitiveContains(value)
                || $0.url.path.localizedCaseInsensitiveContains(value)
        }
    }

    private var sections: [RepositoryCatalogSection] {
        LocalRepositoryCatalog.sections(
            records: filteredResults,
            recentRepositoryPaths: [],
            currentRepositoryPath: nil
        )
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            header(palette)
            Rectangle().fill(palette.divider).frame(height: 1)

            if model.repositoryScanHasRun, !model.repositoryScanResults.isEmpty {
                selectionBar(palette)
                Rectangle().fill(palette.divider).frame(height: 1)
            }

            results(palette)

            Rectangle().fill(palette.divider).frame(height: 1)
            footer(palette)
        }
        .background(palette.surface.opacity(0.18))
        .appGlassPanel()
        .padding(AppThemeLayout.workspaceInset)
        .frame(minWidth: 700, minHeight: 560)
        .background(Color.clear)
#if DEBUG
        .background(
            DebugSnapshotCapture(
                isReady: ProcessInfo.processInfo.environment["GITGATTO_SCANNER_PREVIEW"] == "1"
                    && model.repositoryScanHasRun
                    && !model.isScanningRepositories
            )
        )
#endif
    }

    private func header(_ palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("repository.scan.title"))
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(palette.ink)
                    Text(statusText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.mutedInk)
                }

                Spacer()

                Button {
                    chooseScanFolders()
                } label: {
                    GattoLabel(L10n.text("repository.scan.choose_folders"), systemImage: "folder.badge.plus")
                }
                .buttonStyle(SecondaryButtonStyle())

                if model.isScanningRepositories {
                    Button(L10n.text("repository.scan.stop")) {
                        model.cancelRepositoryScan()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button {
                        model.scanForRepositories()
                    } label: {
                        GattoLabel(L10n.text("repository.scan.device"), systemImage: "internaldrive")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }

            if model.isScanningRepositories {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.text("repository.scan.background"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.mutedInk)
                }
                .transition(.opacity)
            } else if model.repositoryScanHasRun, !model.repositoryScanRoots.isEmpty {
                Text(scanScopeText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.subtleInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model.repositoryScanRoots.map(\.path).joined(separator: "\n"))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(palette.surface)
    }

    private func selectionBar(_ palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            SearchField(text: $query, placeholderKey: "repository.scan.search")
                .frame(maxWidth: 320)

            Text(L10n.format("repository.scan.available", filteredResults.count))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.subtleInk)

            Spacer()

            Button(L10n.text("repository.scan.select_all")) {
                model.selectRepositoryScanResults(paths: filteredResults.map(\.id))
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(palette.primary)

            Button(L10n.text("repository.scan.select_none")) {
                model.clearRepositoryScanSelection()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(palette.mutedInk)
        }
        .padding(.horizontal, 24)
        .frame(height: 54)
        .background(palette.background)
    }

    @ViewBuilder
    private func results(_ palette: AppPalette) -> some View {
        if !model.repositoryScanHasRun {
            ScannerEmptyState(
                systemImage: "folder.badge.plus",
                titleKey: "repository.scan.idle.title",
                bodyKey: "repository.scan.idle.body"
            )
        } else if model.repositoryScanResults.isEmpty {
            ScannerEmptyState(
                systemImage: model.isScanningRepositories ? "magnifyingglass" : "checkmark.circle",
                titleKey: model.isScanningRepositories
                    ? "repository.scan.waiting.title"
                    : "repository.scan.none.title",
                bodyKey: model.isScanningRepositories
                    ? "repository.scan.waiting.body"
                    : "repository.scan.none.body"
            )
        } else if filteredResults.isEmpty {
            ScannerEmptyState(
                systemImage: "magnifyingglass",
                titleKey: "repository.scan.no_match.title",
                bodyKey: "repository.scan.no_match.body"
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(L10n.text(section.kind.titleKey))
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(palette.mutedInk)
                                Text(String(section.repositories.count))
                                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(palette.subtleInk)
                                Spacer()
                            }

                            ForEach(section.repositories) { record in
                                ScannerRepositoryRow(
                                    record: record,
                                    isSelected: model.selectedRepositoryScanPaths.contains(record.id)
                                ) {
                                    model.setRepositoryScanSelection(
                                        record.id,
                                        isSelected: !model.selectedRepositoryScanPaths.contains(record.id)
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
        }
    }

    private func footer(_ palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            Text(L10n.format("repository.scan.selected", model.selectedRepositoryScanPaths.count))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.mutedInk)

            Spacer()

            Button {
                model.addSelectedScannedRepositories()
            } label: {
                AddSelectionMotionLabel(
                    title: L10n.text("repository.scan.add_selected"),
                    selectedCount: model.selectedRepositoryScanPaths.count,
                    completionID: model.repositoryAddCompletionID
                )
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.selectedRepositoryScanPaths.isEmpty)
            .opacity(model.selectedRepositoryScanPaths.isEmpty ? 0.55 : 1)
        }
        .padding(.horizontal, 24)
        .frame(height: 62)
        .background(palette.surface)
    }

    private var statusText: String {
        if model.isScanningRepositories {
            return L10n.format("repository.scan.progress", model.repositoryScanResults.count)
        }
        if model.repositoryScanHasRun {
            return L10n.format("repository.scan.complete", model.repositoryScanResults.count)
        }
        return L10n.text("repository.scan.manual")
    }

    private var scanScopeText: String {
        if model.repositoryScanRoots.count == 1, let root = model.repositoryScanRoots.first {
            return L10n.format("repository.scan.scope_path", root.path)
        }
        return L10n.format("repository.scan.scope_count", model.repositoryScanRoots.count)
    }

    private func chooseScanFolders() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("repository.scan.folder_panel.title")
        panel.prompt = L10n.text("repository.scan.folder_panel.prompt")
        panel.message = L10n.text("repository.scan.folder_panel.message")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        model.scanForRepositories(in: panel.urls)
    }
}

private struct ScannerRepositoryRow: View {
    let record: LocalRepositoryRecord
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 12) {
                Image(gattoSymbol: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.primary : palette.subtleInk)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.url.lastPathComponent)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(record.url.path)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.subtleInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 16)

                Text(record.sortDate.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            .background(isSelected ? palette.primarySoft : palette.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? palette.primary.opacity(0.28) : palette.divider, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(record.url.lastPathComponent)
        .accessibilityValue(isSelected
            ? L10n.text("repository.scan.accessibility.selected")
            : L10n.text("repository.scan.accessibility.not_selected"))
    }
}

private struct ScannerEmptyState: View {
    let systemImage: String
    let titleKey: String
    let bodyKey: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 10) {
            Image(gattoSymbol: systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            Text(L10n.text(titleKey))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text(L10n.text(bodyKey))
                .font(.system(size: 11.5))
                .foregroundStyle(palette.mutedInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
