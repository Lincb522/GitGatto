import SwiftUI

/// Reads the same saved and discovered commands as the project command panel; selection never executes them.
struct ProjectCommandPicker: View {
    let repository: URL?
    @Binding var command: String
    var store = ProjectToolsStore()
    var onSelect: (ProjectCommand) -> Void = { _ in }
    @State private var commands: [ProjectCommand] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Menu(L10n.text("tools.command.choose")) {
                    ForEach(commands) { item in
                        Button(item.title + " — " + item.displayCommand) { command = item.displayCommand; onSelect(item) }
                    }
                }
                .disabled(isLoading || commands.isEmpty)
                if isLoading { ProgressView().controlSize(.small) }
                if error != nil {
                    Button(L10n.text("action.retry")) { attempt += 1 }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        .task(id: "\(repository?.path ?? ""):\(attempt)") {
            commands = []; error = nil; isLoading = false
            guard let repository else { return }
            isLoading = true
            defer { if !Task.isCancelled { isLoading = false } }
            do {
                let saved = try await store.load().commands
                let loaded = try await ProjectCommandDiscovery().discover(repository: repository, saved: saved)
                try Task.checkCancellation()
                commands = loaded
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                self.error = ProjectCommandOutput.redact(error.localizedDescription)
            }
        }
    }
}
