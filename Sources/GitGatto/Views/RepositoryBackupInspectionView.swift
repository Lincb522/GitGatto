import AppKit
import SwiftUI

struct RepositoryBackupInspectionView: View {
    let backup: RepositoryBackup
    let service: RepositoryBackupInspectionService
    @Environment(\.dismiss) private var dismiss
    @State private var files: [RepositoryBackupFile] = []
    @State private var selection: Set<String> = []
    @State private var selectedPath: String?
    @State private var query = ""
    @State private var document: DiffDocument?
    @State private var loading = true
    @State private var comparing = false
    @State private var exportRequest: ExportRequest?
    @State private var exporting = false
    @State private var error: String?
    @State private var exportedURL: URL?

    private var visibleFiles: [RepositoryBackupFile] {
        files.filter { query.isEmpty || $0.path.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("recovery.compare.title")).font(.headline)
                Text(backup.repositoryName).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("action.close")) { dismiss() }.buttonStyle(SecondaryButtonStyle()).disabled(exporting)
            }
            Text(L10n.text("recovery.compare.help")).font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if loading {
                ProgressView(L10n.text("recovery.loading")).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextField(L10n.text("recovery.compare.search"), text: $query).textFieldStyle(.roundedBorder)
                HSplitView {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(visibleFiles) { file in
                                HStack {
                                    Toggle("", isOn: Binding(get: { selection.contains(file.path) }, set: { checked in
                                        if checked { selection.insert(file.path) } else { selection.remove(file.path) }
                                    })).labelsHidden().accessibilityLabel(file.path)
                                    Button { selectedPath = file.path } label: {
                                        Text(file.path).font(.system(size: 11, design: .monospaced))
                                            .lineLimit(2).truncationMode(.middle)
                                            .frame(maxWidth: .infinity, alignment: .leading).padding(5)
                                            .background(selectedPath == file.path ? Color.accentColor.opacity(0.1) : Color.clear)
                                    }.buttonStyle(.plain)
                                }.padding(.vertical, 2)
                            }
                        }.padding(6)
                    }.frame(minWidth: 240, idealWidth: 290, maxWidth: 360)
                    Group {
                        if let document { DiffCodeView(document: document) }
                        else if comparing { ProgressView() }
                        else { Text(L10n.text("recovery.compare.select")).foregroundStyle(.secondary) }
                    }.frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack {
                    Text(L10n.format("recovery.compare.selected", selection.count)).font(.caption)
                    Spacer()
                    if let exportedURL {
                        Button(L10n.text("recovery.action.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([exportedURL]) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Button(L10n.text("recovery.compare.export")) { exportSelection() }
                        .buttonStyle(PrimaryButtonStyle()).disabled(selection.isEmpty || exporting)
                }
            }
        }
        .padding(18).frame(minWidth: 720, idealWidth: 1000, minHeight: 560)
        .task {
            do { files = try await service.prepare(backup); loading = false }
            catch is CancellationError { return }
            catch { self.error = error.localizedDescription; loading = false }
        }
        .task(id: selectedPath) {
            document = nil
            guard let selectedPath else { return }
            comparing = true
            defer { if self.selectedPath == selectedPath { comparing = false } }
            do {
                let result = try await service.compare(path: selectedPath)
                guard !Task.isCancelled else { return }
                document = result; error = nil
            } catch is CancellationError { return }
            catch { guard !Task.isCancelled else { return }; self.error = error.localizedDescription }
        }
        .task(id: exportRequest?.id) {
            guard let exportRequest else { return }
            defer { exporting = false }
            do { exportedURL = try await service.export(paths: exportRequest.paths, to: exportRequest.destination); error = nil }
            catch is CancellationError { return }
            catch { self.error = error.localizedDescription }
        }
        .interactiveDismissDisabled(exporting)
        .onDisappear { Task { try? await service.close() } }
    }

    private func exportSelection() {
        let panel = NSSavePanel()
        panel.title = L10n.text("recovery.compare.export")
        panel.nameFieldStringValue = "\(backup.repositoryName)-recovered-files"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        exporting = true
        exportRequest = ExportRequest(paths: selection, destination: destination)
    }

    private struct ExportRequest {
        let id = UUID()
        let paths: Set<String>
        let destination: URL
    }
}
