import Foundation
import Testing
@testable import GitGatto

@Suite("Upstream configuration", .serialized)
struct RepositoryUpstreamTests {
    @Test("Agent action actually creates a remote and configures tracking without uploading existing files")
    func agentConfigures() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        try await createHistory(f)
        let sha = try await f.git(["rev-parse", "HEAD"])
        let indexURL = f.folder.appendingPathComponent(".git/index")
        let index = try Data(contentsOf: indexURL)
        let agent = UpstreamAgentFixture()
        let github = BootstrapGitHub()
        var request = f.request; request.pushInitialCommit = false
        let result = try await executeAgent(request, agent: agent, service: f.service(github))
        #expect(!result.pushed)
        #expect(await agent.calls == 1)
        #expect(await github.createCalls == 1)
        #expect(try await f.git(["config", "branch.main.remote"]) == "origin")
        #expect(try await f.git(["config", "branch.main.merge"]) == "refs/heads/main")
        #expect(try await f.git(["config", "remote.origin.url"]) == f.remoteURL)
        #expect(try await f.git(["rev-parse", "HEAD"]) == sha)
        #expect(try Data(contentsOf: indexURL) == index)
        #expect(try await f.git(["status", "--porcelain"]).contains("draft.txt"))
    }

    @Test("Publishing approved history uploads only the approved commit, never concurrent work")
    func publishApprovedHistory() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        try await createHistory(f); try await f.initBare()
        var request = f.request
        request.approvedExistingHead = try await f.git(["rev-parse", "HEAD"])
        await f.runner.commitBeforePush()
        let result = try await executeAgent(request, agent: UpstreamAgentFixture(), service: f.service())
        #expect(result.pushed)
        #expect(try await f.git(["rev-parse", "refs/heads/main"], at: f.bare) == request.approvedExistingHead)
        let files = try await f.git(["ls-tree", "--name-only", "refs/heads/main"], at: f.bare)
        #expect(files == "project.txt")
    }

    @Test("JSON-decoded folder URLs retain the repository-root boundary")
    func decodedFolder() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        try await createHistory(f)
        let decoded = try JSONDecoder().decode(URL.self, from: JSONEncoder().encode(f.folder))
        let inspected = try await f.service().inspect(decoded)
        #expect(inspected.isRepository && inspected.folder.path == f.folder.path)
        let child = f.folder.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let nested = try JSONDecoder().decode(URL.self, from: JSONEncoder().encode(child))
        await #expect(throws: RepositoryBootstrapError.nested) { try await f.service().inspect(nested) }
    }

    @Test("A changed approved HEAD is rejected before creating or linking a remote")
    func staleApproval() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        try await createHistory(f)
        let github = BootstrapGitHub()
        var request = f.request; request.approvedExistingHead = "0000000000000000000000000000000000000000"
        await #expect(throws: RepositoryBootstrapError.history) { try await f.service(github).create(request) { _ in } }
        #expect(await github.createCalls == 0)
        #expect(try await f.git(["remote"]).isEmpty)
    }

    @Test("Agent refusal, prose and altered arguments cannot trigger mutations", arguments: ["prose", "owner", "push", "folder", "public", "name", "branch", "identity"])
    func rejectsOutOfScope(mode: String) async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        let github = BootstrapGitHub()
        let agent = UpstreamAgentFixture(mode: mode)
        await #expect(throws: RepositoryBootstrapError.agentAction) {
            try await RepositoryUpstreamAgent(agent: agent, service: f.service(github)).prepare(f.request) { _ in }
        }
        #expect(await github.createCalls == 0)
        #expect(!FileManager.default.fileExists(atPath: f.folder.appendingPathComponent(".git").path))
    }

    @Test("Existing SSH origin is preserved and reused, not replaced or duplicated")
    func existingSSH() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        try await createHistory(f)
        let origin = "git@github.com:fixture-owner/demo.git"
        _ = try await f.git(["remote", "add", "origin", origin])
        let github = BootstrapGitHub(existing: true)
        var request = f.request; request.pushInitialCommit = false; request.connectExisting = true
        _ = try await f.service(github).create(request) { _ in }
        #expect(await github.createCalls == 0)
        #expect(try await f.git(["config", "remote.origin.url"]) == origin)
        #expect(try await f.git(["config", "branch.main.remote"]) == "origin")
    }

    @Test("UI freezes approval, supports automatic Agent setup and requires consent for publishing")
    @MainActor func approvalAndOneClick() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        try await createHistory(f)
        let model = RepositoryBootstrapViewModel(service: f.service(), folder: f.folder, automaticAgent: true, agent: UpstreamAgentFixture())
        model.name = "demo"
        await model.inspectFolder(); await model.refreshAccount()
        model.startAutomaticAgentIfReady()
        #expect(model.isRunning && !model.showsConfirmation)
        await model.performRequest()
        #expect(model.result?.pushed == false)
        #expect(try await f.git(["config", "branch.main.merge"]) == "refs/heads/main")

        let manual = RepositoryBootstrapViewModel(service: f.service(BootstrapGitHub(existing: true)), folder: f.folder)
        await manual.inspectFolder(); await manual.refreshAccount()
        manual.pushInitialCommit = true
        manual.requestCreate()
        #expect(manual.showsConfirmation && !manual.isRunning)
        #expect(manual.confirmationText.contains("fixture-owner/demo"))
        manual.cancelConfirmation()
        await manual.performRequest()
        #expect(manual.result == nil)
        manual.isPrivate = false; manual.pushInitialCommit = false
        manual.requestCreate(usingAgent: true)
        #expect(manual.isRunning && !manual.showsConfirmation)
    }

    private func executeAgent(_ request: RepositoryBootstrapRequest, agent: any RepositoryConfigurationAgent,
                              service: RepositoryBootstrapService) async throws -> RepositoryBootstrapResult {
        let prepared = try await RepositoryUpstreamAgent(agent: agent, service: service).prepare(request) { _ in }
        return try await service.create(prepared) { _ in }
    }

    @Test("Agent fills every required field from folder, Git state and account without form input")
    @MainActor func automaticDetails() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        try await f.initBare()
        let agent = UpstreamAgentFixture()
        let github = BootstrapGitHub()
        let model = RepositoryBootstrapViewModel(service: f.service(github), folder: f.folder, automaticAgent: true, agent: agent)
        await model.inspectFolder(); await model.refreshAccount()
        // The folder contains spaces; the manual form cannot submit it as a repository name.
        #expect(!model.canCreate && model.canRunAgent)
        model.startAutomaticAgentIfReady()
        await model.performRequest()
        #expect(model.result?.pushed == true)
        #expect(model.name == "demo" && model.owner == "fixture-owner" && model.branch == "main")
        #expect(try await f.git(["config", "user.email"]) == "fixture-owner@users.noreply.github.com")
        let head = try await f.git(["rev-parse", "HEAD"])
        #expect(try await f.git(["rev-parse", "@{upstream}"]) == head)
        #expect(await agent.calls == 1)
    }

    private func createHistory(_ f: BootstrapFixture) async throws {
        _ = try await f.git(["init", "--initial-branch=main"])
        try Data("committed content".utf8).write(to: f.folder.appendingPathComponent("project.txt"))
        _ = try await f.git(["add", "project.txt"])
        _ = try await f.git(["commit", "-m", "Project"])
        try Data("private uncommitted draft".utf8).write(to: f.folder.appendingPathComponent("draft.txt"))
    }
}

actor UpstreamAgentFixture: RepositoryConfigurationAgent {
    private(set) var calls = 0
    let mode: String
    init(mode: String = "valid") { self.mode = mode }
    func repositoryConfigurationAction(prompt: String) async throws -> String {
        calls += 1
        if mode == "delay" { try await Task.sleep(for: .seconds(30)) }
        let json = try #require(prompt.components(separatedBy: "Action template:\n").last)
        let action = try JSONDecoder().decode(RepositoryUpstreamAgent.Action.self, from: Data(json.utf8))
        var request = action.arguments
        if request.name.isEmpty { request.name = "demo" }
        switch mode {
        case "prose": return "Everything is configured."
        case "owner": request.owner = "someone-else"
        case "push": request.pushInitialCommit.toggle()
        case "folder": request.folder = URL(fileURLWithPath: "/tmp/another-project")
        case "public": request.isPrivate.toggle()
        case "name": request.name = "../outside"
        case "branch": request.branch = "other"
        case "identity": request.authorEmail = "other@example.invalid"
        default: break
        }
        return String(decoding: try JSONEncoder().encode(RepositoryUpstreamAgent.Action(tool: action.tool, arguments: request)), as: UTF8.self)
    }
}

@Suite("Upstream completion gaps", .serialized)
struct RepositoryUpstreamCompletionTests {
    @Test("Agent resolves a name collision without attaching the unrelated repository")
    func nameCollision() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        let github = BootstrapNameAvailabilityFixture()
        let service = RepositoryBootstrapService(git: f.runner, github: github, environment: f.environment)
        let agent = BootstrapRenamingAgent()
        var request = f.request; request.pushInitialCommit = false
        let prepared = try await RepositoryUpstreamAgent(agent: agent, service: service).prepare(request) { _ in }
        #expect(prepared.name == "demo-client" && !prepared.connectExisting)
        #expect(await agent.calls == 2)
        #expect(await github.created.isEmpty)
        let result = try await service.create(prepared) { _ in }
        #expect(result.remote?.name == "demo-client")
        #expect(await github.created == ["demo-client"])
        #expect(try await f.git(["config", "remote.origin.url"]) == "https://github.com/fixture-owner/demo-client.git")
    }

    @Test("Repeated collisions are bounded and leave the folder untouched")
    func exhaustedNames() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        let github = BootstrapNameAvailabilityFixture(alwaysOccupied: true)
        let service = RepositoryBootstrapService(git: f.runner, github: github, environment: f.environment)
        let agent = BootstrapRenamingAgent()
        await #expect(throws: RepositoryBootstrapError.remoteExists) {
            try await RepositoryUpstreamAgent(agent: agent, service: service).prepare(f.request) { _ in }
        }
        #expect(await agent.calls == 3)
        #expect(await github.created.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: f.folder.appendingPathComponent(".git").path))
    }

    @Test("Current repository status and remotes refresh after setup without navigation")
    @MainActor func refreshCurrent() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        var local = f.request; local.createRemote = false
        _ = try await f.service().create(local) { _ in }
        let workspace = WorkspaceViewModel(isBackgroundMonitor: true, monitoredRepositories: [])
        let before = try await GitRepositoryService().loadRepositoryOverview(at: f.folder)
        workspace.apply(before)
        workspace.selectedSection = .branches
        workspace.commitMessage = "keep draft"
        var request = f.request; request.pushInitialCommit = false
        _ = try await f.service().create(request) { _ in }
        await workspace.repositoryConfigurationCompleted(in: f.folder)
        #expect(workspace.gitReferenceSnapshot.remotes.first?.name == "origin")
        #expect(workspace.snapshot?.branches.first?.upstream == "origin/main")
        #expect(workspace.selectedSection == .branches && workspace.commitMessage == "keep draft")
        let untouched = workspace.snapshot?.rootURL
        await workspace.repositoryConfigurationCompleted(in: f.root.appendingPathComponent("not-selected"))
        #expect(workspace.snapshot?.rootURL == untouched)
    }
}

private actor BootstrapRenamingAgent: RepositoryConfigurationAgent {
    private(set) var calls = 0
    func repositoryConfigurationAction(prompt: String) throws -> String {
        calls += 1
        let json = try #require(prompt.components(separatedBy: "Action template:\n").last)
        let action = try JSONDecoder().decode(RepositoryUpstreamAgent.Action.self, from: Data(json.utf8))
        var request = action.arguments
        request.name = calls == 1 ? "demo" : "demo-client"
        return String(decoding: try JSONEncoder().encode(RepositoryUpstreamAgent.Action(tool: action.tool, arguments: request)), as: UTF8.self)
    }
}

private actor BootstrapNameAvailabilityFixture: GitHubRepositoryCreating {
    let alwaysOccupied: Bool
    private(set) var created: [String] = []
    init(alwaysOccupied: Bool = false) { self.alwaysOccupied = alwaysOccupied }
    func currentAccount() throws -> GitHubAccount {
        GitHubAccount(login: "fixture-owner", name: nil, webURL: try #require(URL(string: "https://github.com/fixture-owner")))
    }
    func repositoryForCreation(owner: String, name: String) throws -> GitHubRepository? {
        alwaysOccupied || name == "demo" || created.contains(name) ? try repository(name, isPrivate: true) : nil
    }
    func createRepository(name: String, isPrivate: Bool) throws -> GitHubRepository {
        created.append(name)
        return try repository(name, isPrivate: isPrivate)
    }
    func configureRepositoryAuthentication(in folder: URL) {}
    private func repository(_ name: String, isPrivate: Bool) throws -> GitHubRepository {
        GitHubRepository(fullName: "fixture-owner/\(name)", name: name, owner: "fixture-owner", description: nil,
                         webURL: try #require(URL(string: "https://github.com/fixture-owner/\(name)")),
                         stars: 0, forks: 0, openIssues: 0, language: nil, updatedAt: Date(), isPrivate: isPrivate, defaultBranch: "main")
    }
}
