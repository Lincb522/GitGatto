import SwiftUI

struct FileRestorePreviewSheet: View {
    let repository: URL
    let path: String
    let revision: FileRevisionRecord
    let restored: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var preview: FileRestorePreview?
    @State private var error: String?
    @State private var busy = false
    @State private var attempt = 0
    private let service = FileRestorePreviewService()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("file_timeline.restore.preview")).font(.headline)
            Text(path + " · " + revision.shortHash).textSelection(.enabled)
                .font(.system(.caption, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
            if let preview { DiffCodeView(document: preview.diff) }
            else if error == nil { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            if let error {
                Text(error).foregroundStyle(.secondary).textSelection(.enabled)
                Button(L10n.text("action.retry")) { attempt += 1 }.disabled(busy)
            }
            Text(L10n.format("file_timeline.restore.confirm.message", revision.shortHash)).font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L10n.text("action.cancel")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
                Spacer()
                Button(L10n.text("file_timeline.restore.action"), role: .destructive) {
                    guard let preview else { return }
                    busy = true
                    Task {
                        do { try await service.restore(preview); restored(); dismiss() }
                        catch { self.error = error.localizedDescription; self.preview = nil }
                        busy = false
                    }
                }.disabled(preview == nil || busy).buttonStyle(PrimaryButtonStyle())
            }
        }.padding(20).frame(minWidth: 480, idealWidth: 800, minHeight: 500, idealHeight: 680)
        .task(id: attempt) {
            error = nil; preview = nil
            do { let value = try await service.preview(path: path, revision: revision, repository: repository)
                try Task.checkCancellation(); preview = value }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}
