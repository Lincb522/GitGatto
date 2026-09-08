import SwiftUI
import AppKit

struct ProjectCommandsPanel: View {
    @ObservedObject var workspace: WorkspaceViewModel
    @ObservedObject var tools: ProjectToolsViewModel
    let confirm: ProjectToolConfirmation
    @State private var title = ""
    @State private var executable = ""
    @State private var arguments = "[]"
    @State private var timeout = 3600
    @State private var localURL = ""
    @State private var editingID: String?
    @State private var expandedRun: UUID?
    @State private var editorExpanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("tools.commands.help")).foregroundStyle(.secondary).font(.callout)
            ForEach(tools.commands) { command in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(command.title).font(.headline)
                        Spacer()
                        Button(L10n.text("tools.edit")) { edit(command) }
                        Button(L10n.text(tools.state.commands.contains(where: { $0.id == command.id }) ? "tools.unpin" : "tools.pin")) {
                            Task { await tools.action { if tools.state.commands.contains(where: { $0.id == command.id }) { try await tools.unpin(command) } else { try await tools.pin(command) } } }
                        }
                        Button(L10n.text("tools.run")) { confirm(command.repositoryPath + "\n" + command.displayCommand) { tools.start(command); expandedRun = tools.runs.first?.id } }
                            .disabled(tools.runs.contains { $0.command.id == command.id && $0.running })
                    }
                    Text(command.displayCommand).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }.padding(.vertical, 6)
                Divider()
            }
            DisclosureGroup(L10n.text("tools.command.custom"), isExpanded: $editorExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(L10n.text("tools.name"), text: $title)
                    TextField(L10n.text("tools.command.executable"), text: $executable)
                    TextField(L10n.text("tools.command.arguments"), text: $arguments)
                    Text(L10n.text("tools.command.argvHelp")).font(.caption).foregroundStyle(.secondary)
                    Stepper(L10n.format("tools.command.timeout", timeout), value: $timeout, in: 1...86400, step: 60)
                    TextField(L10n.text("tools.command.localURL"), text: $localURL)
                    HStack {
                        Button(L10n.text("tools.save")) { Task { await save() } }.disabled(workspace.snapshot == nil)
                        Button(L10n.text("tools.clear")) { editingID = nil; title = ""; executable = ""; arguments = "[]"; localURL = "" }
                    }
                }.textFieldStyle(.roundedBorder).padding(.top, 10)
            }
            if tools.commands.isEmpty { Text(L10n.text("tools.command.empty")).foregroundStyle(.secondary) }
            Text(L10n.text("tools.command.runs")).font(.headline).padding(.top, 8)
            ForEach(tools.runs) { run in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button { expandedRun = expandedRun == run.id ? nil : run.id } label: { Text(run.command.title).font(.headline) }.buttonStyle(.plain)
                        Spacer()
                        if run.running { ProgressView().controlSize(.small); Button(L10n.text("tools.stop")) { tools.stop(run.id) } }
                        else {
                            Text(run.stopped ? L10n.text("tools.stopped") : L10n.format("tools.command.exit", Int(run.exitCode ?? -1))).font(.caption)
                            Button(L10n.text("tools.rerun")) { confirm(run.command.displayCommand) { tools.start(run.command); expandedRun = tools.runs.first?.id } }
                            Button(L10n.text("tools.agent")) { Task { await tools.handoffRun(run, to: workspace) } }
                        }
                    }
                    Text(run.command.repositoryPath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if let end = run.finishedAt { Text(L10n.format("tools.command.elapsed", Int(end.timeIntervalSince(run.startedAt)))).font(.caption) }
                    else { TimelineView(.periodic(from: run.startedAt, by: 1)) { context in Text(L10n.format("tools.command.elapsed", Int(context.date.timeIntervalSince(run.startedAt)))).font(.caption) } }
                    if let url = localLink(run) { Button(L10n.text("tools.command.openLocal")) { NSWorkspace.shared.open(url) } }
                    if expandedRun == run.id {
                        ScrollView { Text(run.output.isEmpty ? L10n.text("tools.command.waiting") : run.output).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 230)
                    }
                }.padding(.vertical, 8)
                Divider()
            }
        }.onAppear { if expandedRun == nil { expandedRun = tools.runs.first?.id } }
    }
    private func edit(_ command: ProjectCommand) {
        editorExpanded = true
        editingID = command.id; title = command.title; executable = command.executable; timeout = command.timeoutSeconds; localURL = command.localURL
        arguments = (try? JSONEncoder().encode(command.arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
    private func save() async {
        guard let root = workspace.snapshot?.rootURL else { return }
        await tools.action {
            guard let data = arguments.data(using: .utf8), let args = try? JSONDecoder().decode([String].self, from: data),
                  localURL.isEmpty || ProjectCommandOutput.localURL(localURL) != nil else { throw ProjectToolsError(key: "command") }
            let command = ProjectCommand(id: editingID ?? UUID().uuidString, title: title, executable: executable, arguments: args, repositoryPath: root.path, timeoutSeconds: timeout, localURL: localURL)
            try await tools.pin(command); editingID = command.id; tools.notice = L10n.text("tools.saved")
        }
    }
    private func localLink(_ run: ProjectCommandRun) -> URL? {
        run.localURL ?? ProjectCommandOutput.localURL(run.command.localURL)
    }
}
