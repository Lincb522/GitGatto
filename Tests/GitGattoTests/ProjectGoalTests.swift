import Foundation
import Testing
@testable import GitGatto

@Suite("Project convergence goals")
struct ProjectGoalTests {
    @Test("Parses HTTPS and SSH GitHub remotes without retaining credentials")
    func parsesRemoteIdentities() throws {
        let https = try #require(
            RepositoryRemoteIdentity.parse(
                remoteName: "origin",
                remoteURL: "https://github.com/Lincb522/GitGatto.git"
            )
        )
        let ssh = try #require(
            RepositoryRemoteIdentity.parse(
                remoteName: "upstream",
                remoteURL: "git@github.com:openai/codex.git"
            )
        )

        #expect(https.host == "github.com")
        #expect(https.fullName == "Lincb522/GitGatto")
        #expect(ssh.fullName == "openai/codex")
    }

    @Test("Reconciles dirty changes through stage, commit, push, and Actions")
    func reconcilesDeliveryChain() {
        let change = WorkingTreeChange(
            path: "Sources/App.swift",
            originalPath: nil,
            indexStatus: .unmodified,
            workTreeStatus: .modified
        )
        var goal = makeGoal()
        goal = ProjectGoalReconciler.reconcile(
            goal,
            with: observation(changes: [change])
        )
        #expect(goal.nextStep == .stageChanges)
        #expect(goal.status == .ready)

        let staged = WorkingTreeChange(
            path: change.path,
            originalPath: nil,
            indexStatus: .modified,
            workTreeStatus: .unmodified
        )
        goal = ProjectGoalReconciler.reconcile(
            goal,
            with: observation(changes: [staged])
        )
        #expect(goal.step(.stageChanges)?.status == .completed)
        #expect(goal.nextStep == .commit)

        goal.targetHeadSHA = "target"
        goal = ProjectGoalReconciler.reconcile(
            goal,
            with: observation(head: "target", published: false)
        )
        #expect(goal.nextStep == .push)

        goal = ProjectGoalReconciler.reconcile(
            goal,
            with: observation(
                head: "target",
                published: true,
                actions: .running(runNumbers: [42])
            )
        )
        #expect(goal.status == .waiting)
        #expect(goal.step(.actions)?.evidence == "#42")

        goal = ProjectGoalReconciler.reconcile(
            goal,
            with: observation(
                head: "target",
                published: true,
                actions: .passed(runNumbers: [42], artifacts: [], artifactsVerified: true)
            )
        )
        #expect(goal.status == .completed)
        #expect(goal.progress == 1)

    }

    @Test("Blocks a goal when the checked-out branch changes")
    func blocksBranchDrift() {
        let goal = ProjectGoalReconciler.reconcile(
            makeGoal(),
            with: observation(branch: "release")
        )

        #expect(goal.status == .blocked)
        #expect(goal.lastError?.contains("main") == true)
        #expect(goal.lastError?.contains("release") == true)
    }

    @Test("Tracks a GitHub delivery from PR creation through merge")
    func reconcilesGitHubDelivery() {
        var goal = makeGitHubGoal()
        goal = ProjectGoalReconciler.reconcile(
            goal,
            with: observation(
                branch: "feature/delivery",
                head: "target",
                published: true,
                actions: .waiting,
                pullRequest: .absent(defaultBranch: "main"),
                baseBranch: "main"
            )
        )
        #expect(goal.nextStep == .pullRequest)
        #expect(goal.baseBranch == "main")

        let pullRequest = deliveryPullRequest(approvalCount: 1)
        let artifact = ProjectGoalActionArtifact(
            id: 7,
            name: "GitGatto.dmg",
            runID: 42,
            runNumber: 12,
            sizeInBytes: 4096,
            isExpired: false
        )
        goal = ProjectGoalReconciler.reconcile(
            goal,
            with: observation(
                branch: "feature/delivery",
                head: "target",
                published: true,
                actions: .passed(runNumbers: [12], artifacts: [artifact], artifactsVerified: true),
                pullRequest: .open(pullRequest),
                baseBranch: "main"
            )
        )
        #expect(goal.step(.pullRequest)?.status == .completed)
        #expect(goal.step(.review)?.status == .completed)
        #expect(goal.step(.actions)?.status == .completed)
        #expect(goal.step(.artifact)?.status == .completed)
        #expect(goal.nextStep == .merge)
        #expect(goal.status == .ready)
        #expect(goal.artifactNames == ["GitGatto.dmg"])

        goal = ProjectGoalReconciler.reconcile(
            goal,
            with: observation(
                branch: "feature/delivery",
                head: "target",
                published: true,
                actions: .passed(runNumbers: [12], artifacts: [artifact], artifactsVerified: true),
                pullRequest: .merged(deliveryPullRequest(approvalCount: 1, isMerged: true)),
                baseBranch: "main"
            )
        )
        #expect(goal.status == .completed)
        #expect(goal.progress == 1)

        let regression = ProjectGoalActionFailure(
            runID: 13,
            runNumber: 13,
            workflowName: "macOS CI",
            conclusion: "failure",
            webURL: URL(string: "https://github.com/Lincb522/GitGatto/actions/runs/13")!,
            logExcerpt: nil
        )
        goal = ProjectGoalReconciler.reconcile(
            goal,
            with: observation(
                branch: "feature/delivery",
                head: "target",
                published: true,
                actions: .failed(regression),
                pullRequest: .merged(deliveryPullRequest(approvalCount: 1, isMerged: true)),
                baseBranch: "main"
            )
        )
        #expect(goal.status == .blocked)
        #expect(goal.lastActionFailure == regression)
    }

    @Test("Blocks unresolved review feedback before Actions and merge")
    func blocksReviewFeedback() {
        let goal = ProjectGoalReconciler.reconcile(
            makeGitHubGoal(),
            with: observation(
                branch: "feature/delivery",
                head: "target",
                published: true,
                actions: .noWorkflows,
                pullRequest: .open(
                    deliveryPullRequest(changesRequestedCount: 1, unresolvedThreadCount: 2)
                ),
                baseBranch: "main"
            )
        )

        #expect(goal.status == .blocked)
        #expect(goal.step(.review)?.status == .blocked)
        #expect(goal.lastError?.contains("2") == true)
        #expect(goal.step(.merge)?.status == .pending)
    }

    @Test("Preserves Actions evidence and resets a repair attempt")
    func resetsActionsRepairAttempt() throws {
        let failure = ProjectGoalActionFailure(
            runID: 80,
            runNumber: 14,
            workflowName: "macOS CI",
            conclusion: "failure",
            webURL: try #require(URL(string: "https://github.com/Lincb522/GitGatto/actions/runs/80")),
            logExcerpt: "Tests failed"
        )
        var goal = ProjectGoalReconciler.reconcile(
            makeGitHubGoal(),
            with: observation(
                branch: "feature/delivery",
                head: "target",
                published: true,
                actions: .failed(failure),
                pullRequest: .open(deliveryPullRequest()),
                baseBranch: "main"
            )
        )
        #expect(goal.lastActionFailure == failure)
        #expect(goal.step(.actions)?.status == .blocked)

        goal.resetForActionsRepair()
        #expect(goal.repairAttemptCount == 1)
        #expect(goal.targetHeadSHA == nil)
        #expect(goal.lastActionFailure == nil)
        #expect(goal.steps.allSatisfy { $0.status == .pending })
        #expect(goal.status == .ready)
    }

    @Test("Persists and restores a recoverable goal")
    func persistsGoal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoGoalTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectGoalStore(fileURL: root.appendingPathComponent("goals.json"))
        var goal = makeGoal()
        goal.status = .waiting
        goal.targetHeadSHA = "target"
        goal.updateStep(.stageChanges, status: .completed)
        goal.updateStep(.commit, status: .completed, evidence: "target")
        goal.updateStep(.push, status: .completed, evidence: "target")
        goal.updateStep(.actions, status: .waiting, evidence: "42")
        goal.lastActionFailure = ProjectGoalActionFailure(
            runID: 42,
            runNumber: 42,
            workflowName: "macOS CI",
            conclusion: "failure",
            webURL: URL(string: "https://github.com/Lincb522/GitGatto/actions/runs/42")!,
            logExcerpt: "runtime output remains in memory only"
        )

        try await store.save([goal])
        let restored = try await store.load()

        let value = try #require(restored.first)
        #expect(restored.count == 1)
        #expect(value.id == goal.id)
        #expect(value.status == .waiting)
        #expect(value.targetHeadSHA == "target")
        #expect(value.steps.map(\.status) == goal.steps.map(\.status))
        #expect(value.step(.actions)?.evidence == "42")
        #expect(value.lastActionFailure?.runID == 42)
        #expect(value.lastActionFailure?.logExcerpt == nil)
        #expect(abs(value.updatedAt.timeIntervalSince(goal.updatedAt)) < 0.001)
    }

    @Test("Runs a delivery goal through a real repository and remote")
    func deliversRealRepository() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoGoalRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("workspace", isDirectory: true)
        let remote = root.appendingPathComponent("remote.git", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", "--bare", remote.path], at: root)
        try runGit(["init", "-b", "main"], at: repository)
        try runGit(["config", "user.name", "GitGatto Test"], at: repository)
        try runGit(["config", "user.email", "gitgatto@example.invalid"], at: repository)
        try "base\n".write(
            to: repository.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "tracked.txt"], at: repository)
        try runGit(["commit", "-m", "Initial"], at: repository)
        let githubURL = "https://github.com/Lincb522/GitGatto.git"
        try runGit(
            ["config", "url.\(remote.absoluteString).insteadOf", githubURL],
            at: repository
        )
        try runGit(["remote", "add", "origin", githubURL], at: repository)
        try runGit(["push", "-u", "origin", "main"], at: repository)
        let baseline = try runGitOutput(["rev-parse", "HEAD"], at: repository)
        try "delivered\n".write(
            to: repository.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )

        let runtime = ProjectGoalRuntime(
            repositoryService: GitRepositoryService(),
            actionsService: NoWorkflowGoalActionsService()
        )
        var goal = ProjectGoal(
            repositoryPath: repository.path,
            repositoryName: "workspace",
            branchName: "main",
            baselineHeadSHA: baseline,
            commitMessage: "feat: deliver runtime goal"
        )

        for _ in 0..<4 {
            goal = ProjectGoalReconciler.reconcile(goal, with: try await runtime.observe(goal))
            guard !goal.status.isTerminal, let step = goal.nextStep else { break }
            let result = try await runtime.execute(step, goal: goal)
            if case let .committed(hash) = result {
                goal.targetHeadSHA = hash
            }
        }
        goal = ProjectGoalReconciler.reconcile(goal, with: try await runtime.observe(goal))

        #expect(goal.status == .completed)
        #expect(goal.targetHeadSHA != baseline)
        #expect(try runGitOutput(["--git-dir", remote.path, "show", "main:tracked.txt"], at: root) == "delivered")
    }

    @Test("Runs a GitHub delivery through PR creation and explicit merge")
    func deliversPullRequestGoal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoPRGoalRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("workspace", isDirectory: true)
        let remote = root.appendingPathComponent("remote.git", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", "--bare", remote.path], at: root)
        try runGit(["init", "-b", "main"], at: repository)
        try runGit(["config", "user.name", "GitGatto Test"], at: repository)
        try runGit(["config", "user.email", "gitgatto@example.invalid"], at: repository)
        try "base\n".write(
            to: repository.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "tracked.txt"], at: repository)
        try runGit(["commit", "-m", "Initial"], at: repository)
        let githubURL = "https://github.com/Lincb522/GitGatto.git"
        try runGit(["config", "url.\(remote.absoluteString).insteadOf", githubURL], at: repository)
        try runGit(["remote", "add", "origin", githubURL], at: repository)
        try runGit(["push", "-u", "origin", "main"], at: repository)
        try runGit(["checkout", "-b", "feature/delivery"], at: repository)
        let baseline = try runGitOutput(["rev-parse", "HEAD"], at: repository)
        try "pull request\n".write(
            to: repository.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )

        let delivery = GoalDeliveryFixture()
        let runtime = ProjectGoalRuntime(
            repositoryService: GitRepositoryService(),
            actionsService: NoWorkflowGoalActionsService(),
            deliveryService: delivery
        )
        var goal = ProjectGoal(
            kind: .githubDelivery,
            repositoryPath: repository.path,
            repositoryName: "workspace",
            branchName: "feature/delivery",
            baselineHeadSHA: baseline,
            commitMessage: "feat: deliver pull request"
        )

        for _ in 0..<8 {
            goal = ProjectGoalReconciler.reconcile(goal, with: try await runtime.observe(goal))
            guard let step = goal.nextStep,
                  [.stageChanges, .commit, .push, .pullRequest].contains(step) else { break }
            let result = try await runtime.execute(step, goal: goal)
            if case let .committed(hash) = result {
                goal.targetHeadSHA = hash
            }
        }
        goal = ProjectGoalReconciler.reconcile(goal, with: try await runtime.observe(goal))

        #expect(goal.nextStep == .merge)
        #expect(await delivery.createCount == 1)
        _ = try await runtime.execute(.merge, goal: goal)
        goal = ProjectGoalReconciler.reconcile(goal, with: try await runtime.observe(goal))

        #expect(goal.status == .completed)
        #expect(await delivery.mergeCount == 1)
        #expect(try runGitOutput(["--git-dir", remote.path, "show", "feature/delivery:tracked.txt"], at: root) == "pull request")
    }

    private func makeGoal() -> ProjectGoal {
        ProjectGoal(
            repositoryPath: "/tmp/GitGatto",
            repositoryName: "GitGatto",
            branchName: "main",
            baselineHeadSHA: "base",
            commitMessage: "feat: deliver goal"
        )
    }

    private func makeGitHubGoal() -> ProjectGoal {
        ProjectGoal(
            kind: .githubDelivery,
            repositoryPath: "/tmp/GitGatto",
            repositoryName: "GitGatto",
            branchName: "feature/delivery",
            baselineHeadSHA: "base",
            commitMessage: "feat: deliver GitHub goal",
            targetHeadSHA: "target"
        )
    }

    private func deliveryPullRequest(
        approvalCount: Int = 0,
        changesRequestedCount: Int = 0,
        unresolvedThreadCount: Int = 0,
        isMerged: Bool = false
    ) -> GitHubDeliveryPullRequest {
        GitHubDeliveryPullRequest(
            number: 18,
            title: "Deliver feature",
            webURL: URL(string: "https://github.com/Lincb522/GitGatto/pull/18")!,
            headBranch: "feature/delivery",
            headSHA: "target",
            baseBranch: "main",
            isDraft: false,
            isMerged: isMerged,
            isClosed: false,
            mergeable: true,
            reviewDecision: approvalCount > 0 ? "APPROVED" : nil,
            approvalCount: approvalCount,
            changesRequestedCount: changesRequestedCount,
            requestedReviewerCount: 0,
            unresolvedThreadCount: unresolvedThreadCount,
            hasUnscannedReviewThreads: false
        )
    }

    private func observation(
        branch: String = "main",
        changes: [WorkingTreeChange] = [],
        head: String = "base",
        published: Bool = false,
        actions: ProjectGoalActionsState = .unavailable,
        pullRequest: ProjectGoalPullRequestState = .unavailable,
        baseBranch: String? = nil
    ) -> ProjectGoalObservation {
        ProjectGoalObservation(
            branchName: branch,
            upstreamName: published ? "origin/main" : nil,
            aheadCount: published ? 0 : 1,
            changes: changes,
            headSHA: head,
            targetPublished: published,
            remoteIdentity: RepositoryRemoteIdentity(
                remoteName: "origin",
                host: "github.com",
                fullName: "Lincb522/GitGatto"
            ),
            actions: actions,
            pullRequest: pullRequest,
            baseBranch: baseBranch
        )
    }

    private func runGit(_ arguments: [String], at directory: URL) throws {
        _ = try runGitOutput(arguments, at: directory)
    }

    private func runGitOutput(_ arguments: [String], at directory: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = directory
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw GitCommandError(
                arguments: arguments,
                exitCode: process.terminationStatus,
                message: stderr
            )
        }
        return stdout
    }
}

private actor NoWorkflowGoalActionsService: ProjectGoalActionsServing {
    func state(
        targetSHA: String,
        branch: String,
        remote: RepositoryRemoteIdentity
    ) async throws -> ProjectGoalActionsState {
        .noWorkflows
    }
}

private actor GoalDeliveryFixture: ProjectGoalDeliveryServing {
    private(set) var createCount = 0
    private(set) var mergeCount = 0
    private var created = false
    private var merged = false

    func pullRequestState(
        targetSHA: String,
        branch: String,
        remote: RepositoryRemoteIdentity
    ) async throws -> (state: ProjectGoalPullRequestState, defaultBranch: String?) {
        guard created else { return (.absent(defaultBranch: "main"), "main") }
        let pullRequest = GitHubDeliveryPullRequest(
            number: 21,
            title: "Deliver pull request",
            webURL: URL(string: "https://github.com/Lincb522/GitGatto/pull/21")!,
            headBranch: branch,
            headSHA: targetSHA,
            baseBranch: "main",
            isDraft: false,
            isMerged: merged,
            isClosed: false,
            mergeable: true,
            reviewDecision: nil,
            approvalCount: 0,
            changesRequestedCount: 0,
            requestedReviewerCount: 0,
            unresolvedThreadCount: 0,
            hasUnscannedReviewThreads: false
        )
        return (merged ? .merged(pullRequest) : .open(pullRequest), "main")
    }

    func createPullRequest(goal: ProjectGoal, remote: RepositoryRemoteIdentity) async throws {
        createCount += 1
        created = true
    }

    func mergePullRequest(goal: ProjectGoal, remote: RepositoryRemoteIdentity) async throws {
        mergeCount += 1
        merged = true
    }
}
