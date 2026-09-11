import AppKit
import Combine
import Foundation

@MainActor
final class ProjectToolsViewModel: ObservableObject {
    @Published private(set) var state = ProjectToolsState()
    @Published private(set) var busy = false
    @Published var error: String?
    @Published var notice: String?
    @Published var query = ProjectCodeQuery()
    @Published var repositoryFilter = ""
    @Published private(set) var searchResult = ProjectSearchResult()
    @Published private(set) var searching = false
    @Published private(set) var hasSearched = false
    @Published private(set) var preview = ""
    @Published var selectedMatch: ProjectCodeMatch?
    @Published private(set) var commands: [ProjectCommand] = []
    @Published private(set) var runs: [ProjectCommandRun] = []
    @Published private(set) var inspection: IgnoreInspection?
    @Published var ruleDraft: IgnoreRuleDraft?
    @Published private(set) var ruleChanges: [String] = []
    @Published private(set) var identityValues: [IdentityValue] = []
    let store: ProjectToolsStore
    let scenes: WorkSceneService
    let identities: RepositoryIdentityService
    let ignores = IgnoreRulesService()
    private var searchTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var searchID = UUID()
    private var runTasks: [UUID: Task<Void, Never>] = [:]
    private var processes: [UUID: ProjectCommandProcess] = [:]

    init(store: ProjectToolsStore = ProjectToolsStore()) {
        self.store = store; scenes = WorkSceneService(store: store); identities = RepositoryIdentityService(store: store)
    }

    private var loadID = UUID()
    private var rulesLoadID = UUID()
    @Published private(set) var rulePreviewText: String?

    func load(repository: URL?, tool: ProjectTool? = nil) async {
        let id = UUID(); loadID = id
        do { let loaded = try await store.load(); if loadID == id { state = loaded } }
        catch { if loadID == id { self.error = ProjectCommandOutput.redact(error.localizedDescription) } }
        guard let repository else { commands = []; identityValues = []; return }
        if tool == nil || tool == .commands {
            commands = []
            do {
                let discovered = try await ProjectCommandDiscovery().discover(repository: repository, saved: state.commands)
                guard loadID == id else { return }
                commands = discovered
            } catch is CancellationError { }
            catch { if loadID == id { commands = []; self.error = ProjectCommandOutput.redact(error.localizedDescription) } }
        }
        if tool == nil || tool == .identities {
            identityValues = []
            do { let values = try await identities.effective(repository: repository); if loadID == id { identityValues = values } }
            catch is CancellationError { }
            catch { if loadID == id { identityValues = []; self.error = ProjectCommandOutput.redact(error.localizedDescription) } }
        }
    }

    func action(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; error = nil; notice = nil
        defer { busy = false }
        do { try await operation(); state = try await store.load() }
        catch is CancellationError { }
        catch { self.error = ProjectCommandOutput.redact(error.localizedDescription) }
    }

    func search(repositories: [URL]) {
        cancelSearch(); searchID = UUID(); let id = searchID; let query = query
        let repositories = repositories.filter { repositoryFilter.isEmpty || $0.path == repositoryFilter }
        searching = true; hasSearched = true; error = nil; preview = ""; selectedMatch = nil
        searchTask = Task {
            defer { if searchID == id { searching = false } }
            do {
                let result = try await ProjectCodeSearchService().search(query, repositories: repositories)
                guard searchID == id else { return }; searchResult = result
            } catch is CancellationError { }
            catch { if searchID == id { self.error = ProjectCommandOutput.redact(error.localizedDescription) } }
        }
    }
    func cancelSearch() { searchID = UUID(); searchTask?.cancel(); searching = false }
    func select(_ match: ProjectCodeMatch) {
        selectedMatch = match; preview = ""; previewTask?.cancel()
        previewTask = Task {
            do {
                let result = try await ProjectCodeSearchService().preview(match)
                guard !Task.isCancelled, selectedMatch?.id == match.id else { return }; preview = ProjectCommandOutput.redact(result)
            } catch is CancellationError { }
            catch { if selectedMatch?.id == match.id { self.error = ProjectCommandOutput.redact(error.localizedDescription) } }
        }
    }

    func pin(_ command: ProjectCommand) async throws {
        guard !command.title.isEmpty, !command.executable.isEmpty, (1...86400).contains(command.timeoutSeconds) else { throw ProjectToolsError(key: "command") }
        state = try await store.update { state in state.commands.removeAll { $0.id == command.id }; state.commands.append(command) }
        commands.removeAll { $0.id == command.id }; commands.insert(command, at: 0)
    }
    func unpin(_ command: ProjectCommand) async throws {
        state = try await store.update { $0.commands.removeAll { $0.id == command.id } }
        commands.removeAll { $0.id == command.id }
        let discovered = try await ProjectCommandDiscovery().discover(repository: URL(fileURLWithPath: command.repositoryPath))
        if let original = discovered.first(where: { $0.id == command.id }) { commands.append(original) }
    }

    func start(_ command: ProjectCommand) {
        guard !runs.contains(where: { $0.command.id == command.id && $0.running }) else { return }
        let run = ProjectCommandRun(command: command); runs.insert(run, at: 0)
        runs = Array(runs.filter { $0.running || $0.id == run.id } + runs.filter { !$0.running && $0.id != run.id }.prefix(20))
        let process = ProjectCommandProcess(); processes[run.id] = process
        runTasks[run.id] = Task {
            var output = ""; var last = Date.distantPast
            for await event in process.events(command: command) {
                guard let index = runs.firstIndex(where: { $0.id == run.id }) else { break }
                switch event.kind {
                case .output(let text):
                    output += text
                    if runs[index].localURL == nil {
                        if let url = ProjectCommandOutput.localURL(command.localURL) ?? text.split(whereSeparator: { $0.isWhitespace || $0 == "\"" || $0 == "'" }).lazy.compactMap({ ProjectCommandOutput.localURL(String($0)) }).first { runs[index].localURL = url }
                    }
                    if output.utf8.count > 100_000 { output = L10n.text("tools.output.omitted") + "\n" + String(output.suffix(70_000)) }
                    if Date().timeIntervalSince(last) >= 0.15 { runs[index].output = output; last = Date() }
                case .finished(let code): runs[index].exitCode = code; runs[index].running = false
                case .stopped: runs[index].stopped = true; runs[index].running = false
                case .failed(let message): output += "\n" + message; runs[index].running = false; runs[index].exitCode = -1
                }
                if !runs[index].running { runs[index].output = output; runs[index].finishedAt = Date() }
            }
            processes[run.id] = nil; runTasks[run.id] = nil
        }
    }
    func stop(_ id: UUID) { processes[id]?.cancel() }
    func inspect(path: String, repository: URL) async { await action { inspection = try await ignores.inspect(path, repository: repository) } }
    func loadRules(repository: URL, local: Bool) async {
        let id = UUID(); rulesLoadID = id
        do {
            let draft = try await ignores.load(repository: repository, localOnly: local)
            guard rulesLoadID == id else { return }
            ruleDraft = draft; ruleChanges = []; rulePreviewText = nil
        } catch is CancellationError { }
        catch { if rulesLoadID == id { ruleDraft = nil; self.error = ProjectCommandOutput.redact(error.localizedDescription) } }
    }
    func previewRules(repository: URL) async {
        await action {
            if let ruleDraft { ruleChanges = try await ignores.preview(ruleDraft, repository: repository); rulePreviewText = ruleDraft.text }
        }
    }
    func saveRules(workspace: WorkspaceViewModel) async {
        await action {
            if let draft = ruleDraft {
                guard rulePreviewText == draft.text else { throw ProjectToolsError(key: "previewRequired") }
                try await workspace.performProjectToolMutation(.ignore) { try await ignores.save(draft) }
                ruleDraft?.original = Data(draft.text.utf8); rulePreviewText = nil; notice = L10n.text("tools.saved")
            }
        }
    }
    func openFile(_ match: ProjectCodeMatch) {
        let url = match.repository.appendingPathComponent(match.path).resolvingSymlinksInPath()
        guard url.path.hasPrefix(match.repository.resolvingSymlinksInPath().path + "/"), ProjectToolsPolicy.allowsContent(match.path) else {
            error = ProjectToolsError(key: "path").localizedDescription; return
        }
        NSWorkspace.shared.open(url)
    }

    func handoffSearch(to workspace: WorkspaceViewModel) async {
        guard let match = selectedMatch else { return }
        await workspace.openRepository(match.repository)
        guard workspace.snapshot?.rootURL.standardizedFileURL == match.repository.standardizedFileURL else { return }
        workspace.codexPrompt = L10n.text("tools.agent.search") + "\n" + (match.revision ?? "WORKTREE") + "\n" + match.path + (match.line.map { ":\($0)" } ?? "") + "\n" + preview
        workspace.selectedSection = .codex; workspace.projectTool = nil
    }
    func handoffRun(_ run: ProjectCommandRun, to workspace: WorkspaceViewModel) async {
        let root = URL(fileURLWithPath: run.command.repositoryPath)
        await workspace.openRepository(root)
        guard workspace.snapshot?.rootURL.standardizedFileURL == root.standardizedFileURL else { return }
        workspace.codexPrompt = L10n.text("tools.agent.command") + "\n" + run.command.displayCommand + "\n" + run.output
        workspace.selectedSection = .codex; workspace.projectTool = nil
    }
}

struct ProjectCommandRun: Identifiable {
    let id = UUID()
    let command: ProjectCommand
    let startedAt = Date()
    var finishedAt: Date?
    var output = ""
    var running = true
    var stopped = false
    var exitCode: Int32?
    var localURL: URL?
}
