import AppKit
import Foundation
import SwiftUI
@testable import GitGatto
import Testing

@Suite("Second batch Git tools", .serialized)
struct SecondBatchGitToolsTests {
    @Test("Multi-repository synchronization reads, fetches, pulls, and pushes real repositories")
    func repositorySynchronization() async throws {
        let fixture = try makeRemoteFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = RepositorySyncService()

        var first = await service.status(for: fixture.first)
        #expect(first.health == .clean)
        #expect(first.upstream == "origin/main")

        try write("remote\n", to: fixture.second.appendingPathComponent("remote.txt"))
        try git(["add", "remote.txt"], at: fixture.second)
        try git(["commit", "-m", "Remote update"], at: fixture.second)
        try git(["push"], at: fixture.second)

        let fetch = await service.perform(.fetch, in: fixture.first)
        #expect(fetch.succeeded)
        first = await service.status(for: fixture.first)
        #expect(first.behindCount == 1)
        #expect(first.supports(.pull))

        let pull = await service.perform(.pull, in: fixture.first)
        #expect(pull.succeeded)
        #expect(await service.status(for: fixture.first).health == .clean)

        try write("local\n", to: fixture.first.appendingPathComponent("local.txt"))
        try git(["add", "local.txt"], at: fixture.first)
        try git(["commit", "-m", "Local update"], at: fixture.first)
        first = await service.status(for: fixture.first)
        #expect(first.aheadCount == 1)
        #expect(first.supports(.push))

        let push = await service.perform(.push, in: fixture.first)
        #expect(push.succeeded)
        #expect(await service.status(for: fixture.first).health == .clean)
    }

    @Test("Concurrent repository status checks do not starve process output readers")
    func concurrentRepositoryStatusChecks() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = RepositorySyncService()

        let statuses = await withTaskGroup(of: RepositorySyncStatus.self) { group in
            for _ in 0..<16 {
                group.addTask { await service.status(for: root) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        #expect(statuses.count == 16)
        #expect(statuses.allSatisfy { $0.health != .unavailable })
        #expect(statuses.allSatisfy { $0.errorMessage == nil })
    }

    @Test("Commit search combines SHA, message, author, path, extension, and pickaxe filters")
    func commitSearch() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("let original = true\n", to: root.appendingPathComponent("Feature.swift"))
        try git(["add", "Feature.swift"], at: root)
        try git(["-c", "user.name=Alice", "-c", "user.email=alice@example.com", "commit", "-m", "Add search feature"], at: root)
        let targetHash = try gitOutput(["rev-parse", "HEAD"], at: root)

        let service = GitCommitSearchService()
        var query = CommitSearchQuery()
        query.message = "search feature"
        query.author = "Alice"
        query.path = "Feature.swift"
        query.fileExtension = "swift"
        query.changedText = "original"
        var matches = try await service.search(query, in: root)
        #expect(matches.map(\.hash) == [targetHash])

        query = CommitSearchQuery()
        query.hash = String(targetHash.prefix(12))
        matches = try await service.search(query, in: root)
        #expect(matches.first?.hash == targetHash)

        query = CommitSearchQuery()
        query.path = "../outside"
        do {
            _ = try await service.search(query, in: root)
            Issue.record("Expected repository traversal to be rejected")
        } catch let error as GitCommitSearchError {
            #expect(error == .invalidPath)
        }
    }

    @Test("GitHub inbox and issue payloads retain actionable fields")
    func collaborationParsing() throws {
        let graphQL = Data(#"""
        {
          "data": {
            "viewer": {"login":"lin"},
            "search": {"nodes":[{
              "number":42,"title":"Fix sync","url":"https://github.com/acme/repo/pull/42",
              "updatedAt":"2026-09-04T08:00:00Z","isDraft":false,"mergeable":"CONFLICTING",
              "reviewDecision":"CHANGES_REQUESTED","author":{"login":"dev"},
              "repository":{"nameWithOwner":"acme/repo"},
              "reviewRequests":{"nodes":[{"requestedReviewer":{"login":"lin"}}]},
              "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}
            }]}
          }
        }
        """#.utf8)
        let inbox = try GitHubCollaborationParser.inboxPullRequests(from: graphQL)
        let item = try #require(inbox.first)
        #expect(item.categories.contains(.reviewRequested))
        #expect(item.categories.contains(.changesRequested))
        #expect(item.categories.contains(.conflicted))
        #expect(item.categories.contains(.actionsFailed))

        let issueData = Data(#"""
        [{
          "number":7,"title":"Broken installer","body":"Steps","user":{"login":"dev"},
          "state":"open","html_url":"https://github.com/acme/repo/issues/7",
          "labels":[{"name":"bug","color":"ff0000"}],"assignees":[{"login":"lin"}],
          "milestone":{"number":2,"title":"Next"},"comments":3,
          "created_at":"2026-09-01T08:00:00Z","updated_at":"2026-09-04T08:00:00Z"
        }]
        """#.utf8)
        let issues = try GitHubCollaborationParser.issues(from: issueData)
        let issue = try #require(issues.first)
        #expect(issue.number == 7)
        #expect(issue.labels.map(\.name) == ["bug"])
        #expect(issue.assignees == ["lin"])
        #expect(issue.milestone?.number == 2)
    }

    @Test("Agent reply prompts retain PR and issue discussion context")
    func agentReplyPrompts() throws {
        let pullRequestURL = try #require(URL(string: "https://github.com/acme/repo/pull/42"))
        let pullRequest = GitHubPullRequest(
            number: 42,
            title: "Keep refresh bounded",
            author: "author",
            body: "This separates local and remote refresh lanes.",
            webURL: pullRequestURL,
            isDraft: false,
            headBranch: "fix/refresh",
            headSHA: "abc123",
            baseBranch: "main",
            nodeID: "PR_test",
            updatedAt: Date()
        )
        let pullRequestPrompt = CodexService.pullRequestReplyPrompt(context: GitHubPullRequestContext(
            repositoryName: "acme/repo",
            pullRequest: pullRequest,
            diff: "+ let remoteRefreshTask: Task<Void, Never>?",
            comments: [GitHubPullRequestComment(
                id: 1,
                author: "reviewer",
                body: "Can this remote refresh be cancelled independently?",
                createdAt: Date(),
                path: "Sources/Refresh.swift",
                line: 18,
                kind: .review
            )],
            reviews: [GitHubPullRequestReview(
                id: 2,
                author: "reviewer",
                body: "Please address cancellation.",
                state: "CHANGES_REQUESTED",
                submittedAt: Date()
            )],
            reviewEvent: .requestChanges
        ))
        #expect(pullRequestPrompt.contains("requestChanges") == false)
        #expect(pullRequestPrompt.contains("Request changes"))
        #expect(pullRequestPrompt.contains("Can this remote refresh be cancelled independently?"))
        #expect(pullRequestPrompt.contains("Sources/Refresh.swift:18"))
        #expect(pullRequestPrompt.contains("CHANGES_REQUESTED"))

        let issueURL = try #require(URL(string: "https://github.com/acme/repo/issues/7"))
        let issue = GitHubIssue(
            number: 7,
            title: "Installer cannot find Node",
            body: "node is missing after the upgrade.",
            author: "reporter",
            state: .open,
            webURL: issueURL,
            labels: [GitHubIssueLabel(name: "bug", colorHex: "ff0000")],
            assignees: [],
            milestone: nil,
            commentCount: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
        let issuePrompt = CodexService.issueReplyPrompt(context: GitHubIssueReplyContext(
            repositoryName: "acme/repo",
            issue: issue,
            comments: [GitHubIssueComment(
                id: 3,
                author: "maintainer",
                body: "Please share the output of `which node`.",
                createdAt: Date(),
                updatedAt: Date()
            )]
        ))
        #expect(issuePrompt.contains("Installer cannot find Node"))
        #expect(issuePrompt.contains("Please share the output of `which node`."))
        #expect(issuePrompt.contains("Labels: bug"))
        #expect(issuePrompt.contains("Never claim that code changed"))
    }

    @MainActor
    @Test("Agent drafts an editable issue reply and publishes only after confirmation")
    func issueAgentReplyFlow() async throws {
        let github = try GitHubAgentReplyGitHubFixture()
        let agent = GitHubAgentReplyAIFixture()
        let model = GitHubCollaborationViewModel(service: github, replyService: agent)
        let repository = github.repository
        model.configure(repositories: [repository])
        model.loadIssues()
        try await waitUntil { model.selectedIssue != nil && !model.isLoadingIssueComments }

        model.draftIssueReply()
        try await waitUntil { !model.isDraftingIssueReply && !model.issueReplyDraft.isEmpty }
        #expect(model.issueReplyDraft == "Thanks. Please share the output of `which node` so we can verify the active runtime.")
        let receivedContext = await agent.receivedContext
        #expect(receivedContext?.repositoryName == repository.fullName)
        #expect(receivedContext?.comments.last?.body == "Node remains unavailable after restart.")
        #expect(await github.publishedBodies.isEmpty)

        model.issueReplyDraft += "\n\nThis reply was reviewed before publishing."
        #expect(await model.publishIssueReply())
        #expect(await github.publishedBodies == [model.issueComments.last?.body].compactMap { $0 })
        #expect(model.issueReplyDraft.isEmpty)
    }

    @MainActor
    @Test("Second batch workspaces render in light and dark appearances")
    func rendersSecondBatchWorkspaces() async throws {
        let repository = URL(fileURLWithPath: "/tmp/GitGatto-second-batch-fixture", isDirectory: true)
        let status = RepositorySyncStatus(
            repositoryURL: repository,
            branch: "main",
            upstream: "origin/main",
            hasRemote: true,
            aheadCount: 2,
            behindCount: 0,
            changedFileCount: 3,
            conflictCount: 0,
            lastCommitAt: Date(),
            errorMessage: nil
        )
        let syncModel = RepositorySyncViewModel(service: StaticSyncService(status: status))
        syncModel.load(repositories: [repository], force: true)
        try await waitUntil { syncModel.statuses.count == 1 }

        let sync = RepositorySyncWorkspaceView(syncModel: syncModel, openRepository: { _ in })
            .frame(width: 1_080, height: 680)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
            .environment(\.colorScheme, .light)
        let inbox = GitHubInboxView(collaborationModel: GitHubCollaborationViewModel(), openURL: { _ in })
            .frame(width: 1_080, height: 680)
            .environment(\.locale, Locale(identifier: "en"))
            .environment(\.colorScheme, .dark)
        let github = try GitHubAgentReplyGitHubFixture()
        let issueModel = GitHubCollaborationViewModel(
            service: github,
            replyService: GitHubAgentReplyAIFixture()
        )
        issueModel.configure(repositories: [github.repository])
        issueModel.loadIssues()
        try await waitUntil { issueModel.selectedIssue != nil && !issueModel.isLoadingIssueComments }
        let issues = GitHubIssuesView(
            collaborationModel: issueModel,
            openURL: { _ in },
            localRepositoryURL: { _ in nil },
            createBranch: { _, _, _ in },
            sendToAgent: { _, _, _ in }
        )
        .frame(width: 1_080, height: 680)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .environment(\.colorScheme, .light)

        let syncData = try render(sync, width: 1_080, height: 680)
        let inboxData = try render(inbox, width: 1_080, height: 680)
        let issueData = try render(issues, width: 1_080, height: 680)
        #expect(syncData.count > 20_000)
        #expect(inboxData.count > 20_000)
        #expect(issueData.count > 20_000)
        if let outputPath = ProcessInfo.processInfo.environment["GITGATTO_SECOND_BATCH_SNAPSHOT_DIRECTORY"] {
            let output = URL(fileURLWithPath: outputPath, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try syncData.write(to: output.appendingPathComponent("multi-repository-sync.png"), options: .atomic)
            try inboxData.write(to: output.appendingPathComponent("github-inbox-empty-dark.png"), options: .atomic)
            try issueData.write(to: output.appendingPathComponent("github-issue-agent-reply.png"), options: .atomic)
        }
    }

    private func makeRemoteFixture() throws -> (root: URL, first: URL, second: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGatto-Sync-\(UUID().uuidString)", isDirectory: true)
        let seed = root.appendingPathComponent("seed", isDirectory: true)
        let remote = root.appendingPathComponent("remote.git", isDirectory: true)
        let first = root.appendingPathComponent("first", isDirectory: true)
        let second = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: seed, withIntermediateDirectories: true)
        try git(["init", "--bare", remote.path], at: root)
        try git(["init", "-b", "main"], at: seed)
        try git(["config", "user.name", "GitGatto Tests"], at: seed)
        try git(["config", "user.email", "tests@example.com"], at: seed)
        try write("initial\n", to: seed.appendingPathComponent("README.md"))
        try git(["add", "README.md"], at: seed)
        try git(["commit", "-m", "Initial"], at: seed)
        try git(["remote", "add", "origin", remote.path], at: seed)
        try git(["push", "-u", "origin", "main"], at: seed)
        try git(["symbolic-ref", "HEAD", "refs/heads/main"], at: remote)
        try git(["clone", remote.path, first.path], at: root)
        try git(["clone", remote.path, second.path], at: root)
        for directory in [first, second] {
            try git(["config", "user.name", "GitGatto Tests"], at: directory)
            try git(["config", "user.email", "tests@example.com"], at: directory)
        }
        return (root, first, second)
    }

    private func makeRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGatto-Search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-b", "main"], at: root)
        try git(["config", "user.name", "GitGatto Tests"], at: root)
        try git(["config", "user.email", "tests@example.com"], at: root)
        try write("# Fixture\n", to: root.appendingPathComponent("README.md"))
        try git(["add", "README.md"], at: root)
        try git(["commit", "-m", "Initial"], at: root)
        return root
    }

    private func git(_ arguments: [String], at directory: URL) throws {
        _ = try gitOutput(arguments, at: directory)
    }

    private func gitOutput(_ arguments: [String], at directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "SecondBatchGitToolsTests", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: text])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor
    private func render<Content: View>(_ content: Content, width: CGFloat, height: CGFloat) throws -> Data {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        let representation = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        return try #require(representation.representation(using: .png, properties: [:]))
    }
}

private struct StaticSyncService: RepositorySyncServing {
    let status: RepositorySyncStatus

    func status(for repositoryURL: URL) async -> RepositorySyncStatus { status }

    func perform(_ operation: RepositoryBatchOperation, in repositoryURL: URL) async -> RepositoryBatchResult {
        RepositoryBatchResult(repositoryURL: repositoryURL, operation: operation, succeeded: true, message: nil)
    }
}

private actor GitHubAgentReplyAIFixture: CodexServing {
    private(set) var receivedContext: GitHubIssueReplyContext?

    func probe() async -> CodexAvailability { CodexAvailability(state: .available, version: "fixture") }
    func run(prompt: String, context: [CodexMessage], in repositoryURL: URL, mode: CodexRunMode) async throws -> CodexRunResult {
        throw CodexServiceError.executionFailed(-1)
    }
    func runWithProvidedContext(prompt: String, context: [CodexMessage]) async throws -> CodexRunResult {
        throw CodexServiceError.executionFailed(-1)
    }
    func draftPullRequestReply(context: GitHubPullRequestContext) async throws -> String {
        throw CodexServiceError.executionFailed(-1)
    }
    func draftIssueReply(context: GitHubIssueReplyContext) async throws -> String {
        receivedContext = context
        return "Thanks. Please share the output of `which node` so we can verify the active runtime."
    }
    func translate(_ text: String, target: CodexTranslationTarget) async throws -> String {
        throw CodexServiceError.executionFailed(-1)
    }
    func translateHTML(
        _ html: String,
        target: CodexTranslationTarget,
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> String {
        throw CodexServiceError.executionFailed(-1)
    }
    func cancel() async {}
}

private actor GitHubAgentReplyGitHubFixture: GitHubServing {
    let repository: GitHubRepository
    let issue: GitHubIssue
    private(set) var publishedBodies: [String] = []

    init() throws {
        repository = GitHubRepository(
            fullName: "acme/repo",
            name: "repo",
            owner: "acme",
            description: "Fixture",
            webURL: try #require(URL(string: "https://github.com/acme/repo")),
            stars: 0,
            forks: 0,
            openIssues: 1,
            language: "Swift",
            updatedAt: Date(),
            isPrivate: false,
            defaultBranch: "main"
        )
        issue = GitHubIssue(
            number: 7,
            title: "Node runtime unavailable",
            body: "Node stopped working after an upgrade.",
            author: "reporter",
            state: .open,
            webURL: try #require(URL(string: "https://github.com/acme/repo/issues/7")),
            labels: [GitHubIssueLabel(name: "bug", colorHex: "ff0000")],
            assignees: [],
            milestone: nil,
            commentCount: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func probe() async -> GitHubAvailability { .unavailable }
    func beginLogin() async throws { throw GitHubServiceError.invalidResponse }
    func currentAccount() async throws -> GitHubAccount { throw GitHubServiceError.invalidResponse }
    func accountRepositories() async throws -> [GitHubRepository] { [repository] }
    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepository] { [] }
    func searchDevelopers(query: String, page: Int) async throws -> [GitHubDeveloperSummary] { [] }
    func developerProfile(login: String) async throws -> GitHubDeveloperProfile { throw GitHubServiceError.invalidResponse }
    func repositories(forDeveloper login: String, page: Int) async throws -> [GitHubRepository] { [] }
    func dailyRecommendations() async throws -> [GitHubRepository] { [] }
    func readme(for repository: GitHubRepository) async throws -> GitHubReadmeDocument? { nil }
    func markdown(at path: String, in repository: GitHubRepository) async throws -> GitHubReadmeDocument {
        throw GitHubServiceError.invalidResponse
    }
    func contents(at path: String, in repository: GitHubRepository) async throws -> [GitHubContentItem] { [] }
    func file(_ item: GitHubContentItem, in repository: GitHubRepository) async throws -> GitHubFileDocument {
        throw GitHubServiceError.invalidResponse
    }
    func pullRequests(for repository: GitHubRepository) async throws -> [GitHubPullRequest] { [] }
    func issues(for repository: GitHubRepository, state: GitHubIssueState, page: Int) async throws -> [GitHubIssue] { [issue] }
    func issueComments(for issue: GitHubIssue, in repository: GitHubRepository) async throws -> [GitHubIssueComment] {
        [GitHubIssueComment(
            id: 1,
            author: "reporter",
            body: "Node remains unavailable after restart.",
            createdAt: Date(),
            updatedAt: Date()
        )]
    }
    func addIssueComment(_ body: String, to issue: GitHubIssue, in repository: GitHubRepository) async throws -> GitHubIssueComment {
        publishedBodies.append(body)
        return GitHubIssueComment(id: 2, author: "maintainer", body: body, createdAt: Date(), updatedAt: Date())
    }
    func pullRequestContext(for pullRequest: GitHubPullRequest, in repository: GitHubRepository) async throws -> GitHubPullRequestContext {
        throw GitHubServiceError.invalidResponse
    }
    func cloneReadmeWorkspace(_ repository: GitHubRepository, into parentDirectory: URL) async throws -> URL {
        throw GitHubServiceError.invalidResponse
    }
    func clone(_ repository: GitHubRepository, into parentDirectory: URL) async throws -> URL {
        throw GitHubServiceError.invalidResponse
    }
    func forkAndClone(_ repository: GitHubRepository, into parentDirectory: URL) async throws -> URL {
        throw GitHubServiceError.invalidResponse
    }
    func postComment(_ body: String, to pullRequest: GitHubPullRequest, in repository: GitHubRepository) async throws {
        throw GitHubServiceError.invalidResponse
    }
    func cancel() async {}
}
