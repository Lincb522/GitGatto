import SwiftUI

struct DevelopmentToolInstallScopeView: View {
    let tool: DevelopmentTool
    @State private var directories: [URL] = []
    var body: some View {
        DisclosureGroup(L10n.text("developer_tools.install.scope")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("developer_tools.install.scope_body"))
                    .fixedSize(horizontal: false, vertical: true)
                if let formula = tool.homebrewFormula {
                    Text("Homebrew: " + formula).font(.system(.caption, design: .monospaced))
                }
                Text(tool.executableCandidates.joined(separator: ", "))
                    .font(.system(.caption, design: .monospaced))
                ForEach(directories, id: \.path) { directory in
                    Text(directory.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.top, 10)
        }
        .task(id: tool.id) { directories = CodexService.developmentToolWritableDirectories(for: tool) }
    }
}

struct DevelopmentToolReceiptView: View {
    let receipt: DevelopmentToolReceipt
    @State private var isExpanded = true
    var body: some View {
        DisclosureGroup(L10n.text("developer_tools.receipt.title"), isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.text("installer.phase.verifying"), systemImage: receipt.executableVerified ? "checkmark.circle" : "exclamationmark.triangle")
                if let detail = receipt.verificationDetail { Text(detail).textSelection(.enabled) }
                Text(L10n.text("developer_tools.receipt." + receipt.environmentState))
                if let path = receipt.profilePath {
                    Text(path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                if let error = receipt.environmentError { Text(error).foregroundStyle(.secondary).textSelection(.enabled) }
                Text(L10n.text(receipt.agentConfigurationComplete ? "developer_tools.receipt.agent_complete" : "developer_tools.receipt.agent_pending"))
            }
            .font(.caption).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
        }
    }
}

struct DevelopmentToolBundleSheet: View {
    @ObservedObject var model: DeveloperToolsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var bundleID = DevelopmentToolBundle.all[0].id
    @State private var selection = Set<String>()
    private var bundle: DevelopmentToolBundle { DevelopmentToolBundle.all.first { $0.id == bundleID } ?? DevelopmentToolBundle.all[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("developer_tools.bundles")).font(.headline)
            Picker(L10n.text("developer_tools.bundles"), selection: $bundleID) {
                ForEach(DevelopmentToolBundle.all) { Text($0.title).tag($0.id) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(bundle.tools) { tool in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: Binding(get: { selection.contains(tool.id) }, set: {
                                if $0 { selection.insert(tool.id) } else { selection.remove(tool.id) }
                            })) {
                                HStack {
                                    Text(tool.name)
                                    Spacer()
                                    if model.status(for: tool).isInstalled { Text(L10n.text("developer_tools.state.installed")).font(.caption) }
                                }
                            }.disabled(model.isQueuedOrRunning(tool) || (model.status(for: tool).isInstalled && !model.status(for: tool).canUpgrade))
                            DevelopmentToolInstallScopeView(tool: tool)
                        }
                        Divider()
                    }
                }
            }
            Text(L10n.text("developer_tools.install.scope_body")).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L10n.text("action.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.text("developer_tools.bundles.enqueue")) {
                    for tool in bundle.tools where selection.contains(tool.id) && !model.isQueuedOrRunning(tool) {
                        if model.status(for: tool).canUpgrade { model.upgrade(tool) }
                        else if !model.status(for: tool).isInstalled { model.install(tool) }
                    }
                    dismiss()
                }.buttonStyle(PrimaryButtonStyle()).disabled(selection.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(minWidth: 420, idealWidth: 580, maxWidth: 720, minHeight: 480, idealHeight: 650)
        .onChange(of: bundleID, initial: true) { _, _ in
            selection = Set(bundle.tools.filter { !model.isQueuedOrRunning($0) && (!model.status(for: $0).isInstalled || model.status(for: $0).canUpgrade) }.map(\.id))
        }
    }
}
