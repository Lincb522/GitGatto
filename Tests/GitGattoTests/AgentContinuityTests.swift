import Foundation
import Testing
@testable import GitGatto

@Suite("Repository-bound Agent continuity", .serialized)
struct AgentContinuityTests {
    @MainActor @Test("A running task and completed output stay in repository A while browsing B", arguments: [false, true], [false, true])
    func switchRepository(cancel: Bool, worktree: Bool) async throws {
        let defaults = UserDefaults.standard
        let keys = ["app.preferences", "recentRepositories", "managedLocalRepositories", "localRepositories", "excludedRepositories"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) } }
        var preferences = AppPreferences()
        preferences.monitoringEngineEnabled = false
        preferences.agentEditProtectionEnabled = false
        preferences.repositoryBackupEnabled = false
        AppPreferencesStore.save(preferences)
        for key in keys.dropFirst() { defaults.removeObject(forKey: key) }
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("GitGatto-agent-continuity-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("A")
        let b = root.appendingPathComponent("B")
        let runner = GitCommandRunner()
        let env = ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_TEMPLATE_DIR": "",
                   "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
                   "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.invalid"]
        for url in (worktree ? [a] : [a, b]) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            _ = try await runner.run(at: url, arguments: ["init", "-b", "main"], environment: env)
            try "\(url.lastPathComponent)\n".write(to: url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
            _ = try await runner.run(at: url, arguments: ["add", "file.txt"], environment: env)
            _ = try await runner.run(at: url, arguments: ["-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-m", "fixture"], environment: env)
        }
        if worktree {
            _ = try await runner.run(at: a, arguments: ["worktree", "add", "-b", "fixture-worktree", b.path], environment: env)
        }
        let agent = ContinuityAgent(holdsCancellation: cancel)
        let store = CodexConversationStore(directoryURL: root.appendingPathComponent("conversations"))
        let coordinator = ContinuityWorktreeCoordinator()
        let model = WorkspaceViewModel(codexService: agent, codexConversationStore: store, worktreeAgentCoordinator: coordinator)
        model.appPreferences = preferences
        await model.openRepository(a)
        #expect(model.snapshot?.rootURL.resolvingSymlinksInPath().path == a.resolvingSymlinksInPath().path)
        model.retryCodexProbe()
        try await wait { model.codexAvailability.state == .available }
        model.codexRunMode = .analyze
        model.codexPrompt = "Analyze A only"
        model.commitMessage = "A draft"
        model.regressionGoodRevision = "v1.0"
        model.regressionVerificationCommand = "swift test"
        model.runCodex()
        try await wait { await agent.running }
        #expect(model.agentRun?.repositoryURL.resolvingSymlinksInPath().path == a.resolvingSymlinksInPath().path)
        model.codexPrompt = "Next question for A"
        await model.openRepository(b)
        #expect(model.snapshot?.rootURL.resolvingSymlinksInPath().path == b.resolvingSymlinksInPath().path)
        #expect(model.isAgentRunningInBackground)
        #expect(model.codexMessages.isEmpty)
        #expect(model.commitMessage.isEmpty)
        #expect(model.codexPrompt.isEmpty)
        #expect(model.regressionGoodRevision == "HEAD~20")
        #expect(model.regressionVerificationCommand.isEmpty)
        model.commitMessage = "B draft"
        if cancel {
            model.cancelCodex(); model.cancelCodex()
            try await wait { await agent.cancelCount == 1 }
            #expect(model.agentRun?.repositoryURL.resolvingSymlinksInPath().path == a.resolvingSymlinksInPath().path)
            #expect(model.isCodexRunning)
            await agent.finish()
        }
        else { await agent.finish() }
        try await wait { !model.isCodexRunning }
        #expect(model.snapshot?.rootURL.resolvingSymlinksInPath().path == b.resolvingSymlinksInPath().path)
        #expect(model.codexMessages.isEmpty)
        #expect(model.commitMessage == "B draft")
        #expect(await agent.repositories.map { $0.resolvingSymlinksInPath().path } == [a.resolvingSymlinksInPath().path])
        #expect(await agent.cancelCount == (cancel ? 1 : 0))
        await model.openRepository(a)
        #expect(model.commitMessage == "A draft")
        #expect(model.regressionGoodRevision == "v1.0")
        #expect(model.regressionVerificationCommand == "swift test")
        #expect(model.codexPrompt == "Next question for A")
        #expect(model.codexMessages.contains { $0.text == "Analyze A only" })
        #expect(model.codexMessages.contains { $0.text == "Result from A" } == !cancel)
        #expect(try await store.load(for: a) == model.codexMessages)
        #expect(try await store.load(for: b).isEmpty)
        for url in [a, b] {
            #expect(try String(contentsOf: url.appendingPathComponent("file.txt"), encoding: .utf8) == "\(worktree ? "A" : url.lastPathComponent)\n")
        }
        if worktree {
            model.refreshWorktrees()
            try await wait { model.worktrees.contains { $0.path.standardizedFileURL == b.standardizedFileURL } }
            let record = try #require(model.worktrees.first { $0.path.standardizedFileURL == b.standardizedFileURL })
            model.selectWorktree(record)
            model.worktreeAgentMode = .analyze
            model.worktreeAgentPrompt = "Inspect linked worktree B"
            model.runWorktreeAgent()
            try await wait { await coordinator.repository != nil }
            await model.openRepository(b)
            #expect(model.worktreeAgentRuns[record.id]?.state == .running)
            #expect(await coordinator.cancelled.isEmpty)
            #expect(await coordinator.repository?.standardizedFileURL == b.standardizedFileURL)
            if cancel { model.cancelWorktreeAgent(record) }
            else { await coordinator.finish() }
            try await wait { model.worktreeAgentRuns[record.id]?.state != .running }
            #expect(model.worktreeAgentRuns[record.id]?.state == (cancel ? .cancelled : .completed))
            #expect(await coordinator.cancelled == (cancel ? [record.id] : []))
            await model.openRepository(a)
            #expect(model.worktreeAgentRuns[record.id]?.response == (cancel ? nil : "Worktree B result"))
        }
        model.restartLiveRefreshLoop()
    }

    @MainActor private func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
        try #require(await condition())
    }
}

private actor ContinuityAgent: CodexServing {
    private let holdsCancellation: Bool
    private var cancellation: CheckedContinuation<Void, Never>?
    init(holdsCancellation: Bool) { self.holdsCancellation = holdsCancellation }
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var running = false
    private(set) var repositories: [URL] = []
    private(set) var cancelCount = 0
    func probe() -> CodexAvailability { .init(state: .available, version: "fixture") }
    func run(prompt: String, context: [CodexMessage], in repositoryURL: URL, mode: CodexRunMode) async throws -> CodexRunResult {
        repositories.append(repositoryURL)
        running = true
        await withCheckedContinuation { continuation = $0 }
        try Task.checkCancellation()
        return CodexRunResult(response: "Result from A", commandCount: 0, fileChangeCount: 0)
    }
    func finish() { continuation?.resume(); continuation = nil; cancellation?.resume(); cancellation = nil }
    func cancel() async {
        cancelCount += 1
        if holdsCancellation { await withCheckedContinuation { cancellation = $0 } }
        else { finish() }
    }
    func runWithProvidedContext(prompt: String, context: [CodexMessage]) throws -> CodexRunResult { throw CancellationError() }
    func draftPullRequestReply(context: GitHubPullRequestContext) throws -> String { throw CancellationError() }
    func translate(_ text: String, target: CodexTranslationTarget) throws -> String { throw CancellationError() }
    func translateHTML(_ html: String, target: CodexTranslationTarget, progress: @escaping @Sendable (Int, Int) async -> Void) throws -> String { throw CancellationError() }
}

private actor ContinuityWorktreeCoordinator: GitWorktreeAgentCoordinating {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var repository: URL?
    private(set) var cancelled: [String] = []
    func run(worktreeID: String, prompt: String, repositoryURL: URL, mode: CodexRunMode) async throws -> CodexRunResult {
        repository = repositoryURL
        await withCheckedContinuation { continuation = $0 }
        try Task.checkCancellation()
        return .init(response: "Worktree B result", commandCount: 0, fileChangeCount: 0)
    }
    func cancel(worktreeID: String) { cancelled.append(worktreeID); finish() }
    func finish() { continuation?.resume(); continuation = nil }
}
