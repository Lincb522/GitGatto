import SwiftUI
import AppKit

struct IgnoreRulesPanel: View {
    @ObservedObject var workspace: WorkspaceViewModel
    @ObservedObject var tools: ProjectToolsViewModel
    let confirm: ProjectToolConfirmation
    @State private var path = ""
    @State private var local = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("tools.ignore.help")).font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField(L10n.text("tools.ignore.path"), text: $path).textFieldStyle(.roundedBorder)
                    .onSubmit { inspect() }
                Button(L10n.text("tools.choose")) { choose() }
                Button(L10n.text("tools.inspect")) { inspect() }.disabled(workspace.snapshot == nil || path.isEmpty || tools.busy)
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first, let root = workspace.snapshot?.rootURL, url.path.hasPrefix(root.path + "/") else { return false }
                path = String(url.path.dropFirst(root.path.count + 1)); inspect(); return true
            }
            if let inspection = tools.inspection {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.text(inspection.tracked ? "tools.ignore.tracked" : inspection.ignored ? "tools.ignore.ignored" : "tools.ignore.included")).font(.headline)
                    if !inspection.source.isEmpty { Text(inspection.source + ":" + inspection.line + "\n" + inspection.pattern).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }
                    if inspection.tracked {
                        Text(L10n.text("tools.ignore.trackedHelp")).font(.caption)
                        Button(L10n.text("tools.ignore.untrack")) { confirm(L10n.text("tools.ignore.untrackConfirm") + "\n" + inspection.path) {
                            guard let root = workspace.snapshot?.rootURL else { return }
                            await tools.action { try await workspace.performProjectToolMutation(.ignore) { try await tools.ignores.stopTracking(inspection.path, repository: root) } }
                            await tools.inspect(path: inspection.path, repository: root)
                        } }
                    }
                }.padding(.vertical, 10)
            }
            Divider()
            Picker(L10n.text("tools.scope"), selection: Binding(get: { local }, set: { value in
                let change: @MainActor () async -> Void = { local = value; if let root = workspace.snapshot?.rootURL { await tools.loadRules(repository: root, local: value) } }
                if let draft = tools.ruleDraft, Data(draft.text.utf8) != draft.original { confirm(L10n.text("tools.ignore.discard"), change) } else { Task { await change() } }
            })) { Text(L10n.text("tools.ignore.shared")).tag(false); Text(L10n.text("tools.ignore.local")).tag(true) }.pickerStyle(.segmented)

            if let draft = tools.ruleDraft {
                Text(draft.file.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                TextEditor(text: Binding(get: { tools.ruleDraft?.text ?? "" }, set: { tools.ruleDraft?.text = $0 })).font(.system(size: 12, design: .monospaced)).frame(height: 220).border(Color.secondary.opacity(0.2))
                HStack {
                    Button(L10n.text("tools.preview")) { if let root = workspace.snapshot?.rootURL { Task { await tools.previewRules(repository: root) } } }
                    Button(L10n.text("tools.save")) { confirm(L10n.text("tools.ignore.saveConfirm") + "\n" + draft.file.path) { await tools.saveRules(workspace: workspace) } }.disabled(tools.rulePreviewText != draft.text)
                    Button(L10n.text("tools.reload")) { load() }
                }.disabled(tools.busy)
                Text(L10n.text("tools.ignore.previewHelp")).font(.caption).foregroundStyle(.secondary)
                ForEach(tools.ruleChanges, id: \.self) { Text($0).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }
            }
        }.task(id: workspace.snapshot?.rootURL) { if let root = workspace.snapshot?.rootURL { await tools.loadRules(repository: root, local: local) } }
    }
    private func inspect() { if let root = workspace.snapshot?.rootURL { Task { await tools.inspect(path: path, repository: root) } } }
    private func load() { if let root = workspace.snapshot?.rootURL { Task { await tools.loadRules(repository: root, local: local) } } }
    private func choose() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.directoryURL = workspace.snapshot?.rootURL
        panel.begin { response in
            guard response == .OK, let url = panel.url, let root = workspace.snapshot?.rootURL, url.path.hasPrefix(root.path + "/") else { return }
            path = String(url.path.dropFirst(root.path.count + 1)); inspect()
        }
    }
}
