import SwiftUI
import AppKit

struct ProjectToolsPanel: View {
    @ObservedObject var workspace: WorkspaceViewModel
    @ObservedObject var tools: ProjectToolsViewModel
    @State var selection: ProjectTool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var confirmation = ""
    @State private var showsConfirmation = false
    @State private var pending: (@MainActor () async -> Void)?

    var body: some View {
        let palette = AppPalette(scheme)
        VStack(spacing: 0) {
            HStack {
                Text(selection.title).font(.system(size: 17, weight: .semibold))
                Spacer()
                if tools.busy { ProgressView().controlSize(.small) }
                Button {
                    UserDefaults.standard.set(HelpTopic.topic(for: selection).rawValue, forKey: "help.selectedTopic")
                    openWindow(id: "help")
                } label: {
                    Text(L10n.text("help.short_title"))
                }
                .accessibilityLabel(L10n.text("help.menu.guide"))
                .help(L10n.text("help.menu.guide"))
                Button(L10n.text("tools.close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ProjectTool.allCases) { tool in
                        Button(tool.title) { selection = tool; tools.error = nil }
                            .buttonStyle(.bordered).tint(selection == tool ? palette.primary : palette.mutedInk)
                    }
                }.padding(.horizontal, 18).padding(.bottom, 12)
            }
            Divider()
            if let error = tools.error {
                HStack(alignment: .top) { Image(gattoSymbol: "exclamationmark.triangle.fill"); Text(error).textSelection(.enabled); Spacer(); Button(L10n.text("tools.dismiss")) { tools.error = nil } }
                    .font(.system(size: 12)).padding(12).background(palette.warning.opacity(0.10))
            }
            if let notice = tools.notice { Text(notice).font(.system(size: 12)).padding(8) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if selection != .search { Text(workspace.snapshot?.rootURL.path ?? L10n.text("tools.noRepository")).font(.system(size: 11)).foregroundStyle(palette.mutedInk).textSelection(.enabled) }
                    switch selection {
                    case .search: ProjectCodeSearchPanel(workspace: workspace, tools: tools)
                    case .scenes: WorkScenesPanel(workspace: workspace, tools: tools, confirm: confirm)
                    case .commands: ProjectCommandsPanel(workspace: workspace, tools: tools, confirm: confirm)
                    case .ignore: IgnoreRulesPanel(workspace: workspace, tools: tools, confirm: confirm)
                    case .identities: RepositoryIdentitiesPanel(workspace: workspace, tools: tools, confirm: confirm)
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(palette.ink).background(palette.surface)
        .frame(minWidth: 560, idealWidth: 940, minHeight: 580, idealHeight: 740)
        .task(id: (workspace.snapshot?.rootURL.path ?? "") + "#" + selection.rawValue) { await tools.load(repository: workspace.snapshot?.rootURL, tool: selection) }
        .confirmationDialog(confirmation, isPresented: $showsConfirmation, titleVisibility: .visible) {
            Button(L10n.text("tools.confirm")) { let operation = pending; pending = nil; Task { await operation?() } }
            Button(L10n.text("tools.cancel"), role: .cancel) { pending = nil }
        }
        .onDisappear { tools.cancelSearch() }
    }
    private func confirm(_ text: String, _ action: @escaping @MainActor () async -> Void) {
        confirmation = text; pending = action; showsConfirmation = true
    }
}

typealias ProjectToolConfirmation = (String, @escaping @MainActor () async -> Void) -> Void

struct ProjectCodeSearchPanel: View {
    @ObservedObject var workspace: WorkspaceViewModel
    @ObservedObject var tools: ProjectToolsViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField(L10n.text("tools.search.placeholder"), text: $tools.query.text).textFieldStyle(.roundedBorder)
                    .onSubmit { tools.search(repositories: workspace.localRepositories) }
                if tools.searching { Button(L10n.text("tools.stop")) { tools.cancelSearch() } }
                else { Button(L10n.text("tools.search")) { tools.search(repositories: workspace.localRepositories) }.keyboardShortcut(.return, modifiers: []) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210))], alignment: .leading) {
                Picker(L10n.text("tools.repository"), selection: $tools.repositoryFilter) {
                    Text(L10n.text("tools.allRepositories")).tag("")
                    ForEach(workspace.localRepositories, id: \.path) { Text($0.lastPathComponent).tag($0.path) }
                }
                Picker(L10n.text("tools.scope"), selection: $tools.query.scope) {
                    ForEach(ProjectCodeQuery.Scope.allCases, id: \.self) { Text(L10n.text("tools.scope." + $0.rawValue)).tag($0) }
                }
                if tools.query.scope == .revision { TextField(L10n.text("tools.revision"), text: $tools.query.revision).textFieldStyle(.roundedBorder) }
                TextField(L10n.text("tools.directoryFilter"), text: $tools.query.directory).textFieldStyle(.roundedBorder)
                Picker(L10n.text("tools.language"), selection: $tools.query.language) {
                    Text(L10n.text("tools.allLanguages")).tag("")
                    ForEach(ProjectCodeQuery.languageExtensions.keys.sorted(), id: \.self) { Text($0).tag($0) }
                }
                TextField(L10n.text("tools.extension"), text: $tools.query.fileExtension).textFieldStyle(.roundedBorder)
                Toggle(L10n.text("tools.filenames"), isOn: $tools.query.filenamesOnly).disabled(tools.query.scope == .history)
            }
            if tools.searching { ProgressView(L10n.text("tools.searching")) }
            if tools.searchResult.limited { Text(L10n.text("tools.search.limit")).font(.caption) }
            ForEach(tools.searchResult.failures, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
            if tools.searchResult.matches.isEmpty, !tools.searching { Text(L10n.text(tools.hasSearched ? "tools.search.noMatches" : "tools.search.empty")).foregroundStyle(.secondary).padding(.vertical, 20) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(tools.searchResult.matches) { match in
                        Button { tools.select(match) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(match.repository.lastPathComponent + " · " + (match.path.isEmpty ? String((match.revision ?? "").prefix(10)) : match.path)).font(.system(size: 12, weight: .semibold))
                                Text((match.line.map { "\($0): " } ?? "") + match.text).font(.system(size: 11, design: .monospaced)).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                .background(tools.selectedMatch?.id == match.id ? Color.accentColor.opacity(0.10) : .clear)
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }.frame(height: tools.searchResult.matches.isEmpty ? 0 : 250)
            if let match = tools.selectedMatch {
                HStack {
                    Text(L10n.text("tools.preview")).font(.headline)
                    Spacer()
                    if match.revision == nil { Button(L10n.text("tools.openFile")) { tools.openFile(match) } }
                    Button(L10n.text("tools.agent")) { Task { await tools.handoffSearch(to: workspace) } }
                }
                Text(tools.preview.isEmpty ? L10n.text("tools.loading") : tools.preview).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct WorkScenesPanel: View {
    @ObservedObject var workspace: WorkspaceViewModel
    @ObservedObject var tools: ProjectToolsViewModel
    let confirm: ProjectToolConfirmation
    @State private var name = ""
    @State private var relatedURL = ""
    @State private var renameID: UUID?
    @State private var renameText = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("tools.scenes.help")).font(.callout).foregroundStyle(.secondary)
            TextField(L10n.text("tools.scene.name"), text: $name).textFieldStyle(.roundedBorder)
            TextField(L10n.text("tools.scene.link"), text: $relatedURL).textFieldStyle(.roundedBorder)
            Button(L10n.text("tools.scene.save")) {
                confirm(L10n.text("tools.scene.saveConfirm")) { await save() }
            }.buttonStyle(PrimaryButtonStyle()).disabled(tools.busy || workspace.snapshot == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let scenes = tools.state.scenes.filter { $0.repositoryPath == workspace.snapshot?.rootURL.path }.sorted { $0.createdAt > $1.createdAt }
            if scenes.isEmpty { Text(L10n.text("tools.scene.empty")).foregroundStyle(.secondary).padding(.vertical, 24) }
            ForEach(scenes) { scene in
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text(scene.name).font(.headline); Spacer(); Text(L10n.text("tools.scene." + scene.phase.rawValue)).font(.caption) }
                    Text(scene.branch + " · " + String(scene.head.prefix(10)) + " · " + scene.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    if !scene.relatedURL.isEmpty { Text(scene.relatedURL).font(.caption).textSelection(.enabled) }
                    if renameID == scene.id {
                        HStack { TextField(L10n.text("tools.scene.name"), text: $renameText); Button(L10n.text("tools.save")) { Task { await tools.action { try await tools.scenes.rename(scene, name: renameText); renameID = nil } } } }
                    }
                    actions(scene)
                    if scene.phase == .saving || scene.phase == .restoring { Text(L10n.text("tools.scene.interrupted")).font(.caption).textSelection(.enabled) }
                }.padding(.vertical, 12)
                Divider()
            }
        }
    }
    private func actions(_ scene: WorkScene) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading) {
            if scene.phase == .saved {
                Button(L10n.text("tools.scene.restore")) { confirm(L10n.text("tools.scene.restoreConfirm")) { await restore(scene) } }
            }
            if scene.phase == .saved || scene.phase == .restored {
                Button(L10n.text("tools.scene.worktree")) { createWorktree(scene) }
            }
            if scene.phase == .saving { Button(L10n.text("tools.retry")) { Task { await tools.action { try await tools.scenes.recoverPending(scene) } } } }
            if scene.phase == .saving || scene.phase == .restoring {
                Button(L10n.text("tools.scene.acknowledge")) { confirm(L10n.text("tools.scene.acknowledgeConfirm")) { await tools.action { try await tools.scenes.acknowledge(scene) } } }
            }
            Button(L10n.text("tools.rename")) { renameID = scene.id; renameText = scene.name }
            Button(L10n.text("tools.delete"), role: .destructive) { confirm(L10n.text("tools.scene.deleteConfirm")) { await tools.action { try await tools.scenes.delete(scene) } } }.disabled(scene.phase == .saving || scene.phase == .restoring)
        }.disabled(tools.busy)
    }
    private func save() async {
        guard let snapshot = workspace.snapshot else { return }
        await tools.action {
            _ = try await workspace.performProjectToolMutation(.stashSave) {
                try await tools.scenes.save(name: name, repository: snapshot.rootURL, draft: workspace.commitMessage, agentDraft: workspace.codexPrompt,
                    selectedPath: workspace.selectedChange?.path, goalID: workspace.selectedProjectGoal?.id, relatedURL: relatedURL, section: workspace.selectedSection.rawValue)
            }
            workspace.commitMessage = ""; workspace.codexPrompt = ""; name = ""
        }
    }
    private func restore(_ scene: WorkScene) async {
        await tools.action {
            try await workspace.performProjectToolMutation(.stashApply) { try await tools.scenes.restore(scene) }
            workspace.commitMessage = scene.draft; workspace.codexPrompt = scene.agentDraft
            if let section = WorkspaceSection(rawValue: scene.section) { workspace.selectedSection = section }
            if let goal = workspace.projectGoals.first(where: { $0.id == scene.goalID }) { workspace.selectProjectGoal(goal) }
            if let change = workspace.snapshot?.changes.first(where: { $0.path == scene.selectedPath }) { workspace.selectChange(change) }
            tools.notice = L10n.text("tools.scene.restored")
        }
    }
    private func createWorktree(_ scene: WorkScene) {
        let panel = NSSavePanel(); panel.canCreateDirectories = true; panel.nameFieldStringValue = scene.name
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            confirm(L10n.text("tools.scene.worktree") + "\n" + url.path) {
                await tools.action {
                    try await workspace.performProjectToolMutation(.stashApply) { try await tools.scenes.createWorktree(for: scene, at: url) }
                    await workspace.openRepository(url)
                    if workspace.snapshot?.rootURL.standardizedFileURL == url.standardizedFileURL {
                        workspace.commitMessage = scene.draft; workspace.codexPrompt = scene.agentDraft
                        if let section = WorkspaceSection(rawValue: scene.section) { workspace.selectedSection = section }
                        if let change = workspace.snapshot?.changes.first(where: { $0.path == scene.selectedPath }) { workspace.selectChange(change) }
                    }
                    tools.notice = url.path
                }
            }
        }
    }
}
