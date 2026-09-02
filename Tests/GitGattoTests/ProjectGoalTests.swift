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

    @Test("Inspects the complete local release contract")
    func inspectsReleaseContract() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoReleaseInspectorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("scripts", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".github/workflows", isDirectory: true),
            withIntermediateDirectories: true
        )
        let installedApplication = root.appendingPathComponent("Installed/GitGatto Preview.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: installedApplication.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        let installedInfo: [String: Any] = [
            "CFBundleShortVersionString": "0.19.0",
            "CFBundleVersion": "19000"
        ]
        let installedInfoData = try PropertyListSerialization.data(
            fromPropertyList: installedInfo,
            format: .xml,
            options: 0
        )
        try installedInfoData.write(
            to: installedApplication.appendingPathComponent("Contents/Info.plist")
        )
        try "# GitGatto\n\nA factual repository guide with enough content for release validation.\n".write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# GitGatto\n\n用于发布校验的完整中文项目说明，内容长度满足文档检查要求。\n".write(
            to: root.appendingPathComponent("README.zh-Hans.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        settings:
          base:
            MARKETING_VERSION: 0.19.0
            CURRENT_PROJECT_VERSION: 19000
        """.write(
            to: root.appendingPathComponent("project.yml"),
            atomically: true,
            encoding: .utf8
        )
        try """
        VERSION="${GITGATTO_VERSION:-0.19.0}"
        BUILD_NUMBER="${GITGATTO_BUILD_NUMBER:-19000}"
        """.write(
            to: root.appendingPathComponent("scripts/package-macos.sh"),
            atomically: true,
            encoding: .utf8
        )
        try "## 0.19.0\n\n- Complete release target.\n".write(
            to: root.appendingPathComponent("CHANGELOG.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        on:
          push:
            tags: ["v*"]
        jobs:
          release:
            steps:
              - run: ./scripts/package-macos.sh --output GitGatto.dmg
              - run: ./scripts/generate-appcast.sh > appcast.xml
              - uses: softprops/action-gh-release@v2
        """.write(
            to: root.appendingPathComponent(".github/workflows/release.yml"),
            atomically: true,
            encoding: .utf8
        )

        var goal = makeReleaseGoal(repositoryPath: root.path)
        goal.installedApplicationPath = installedApplication.path
        let state = ProjectReleaseInspector.inspect(goal: goal)

        #expect(state.readmePath == "README.md")
        #expect(state.translationPaths == ["README.zh-Hans.md"])
        #expect(Set(state.versionEvidence.map(\.value)) == ["0.19.0"])
        #expect(Set(state.buildEvidence.map(\.value)) == ["19000"])
        #expect(state.changelogPath == "CHANGELOG.md")
        #expect(state.releasePipelinePath == ".github/workflows/release.yml")
        #expect(state.installedApplication?.path == installedApplication.path)
        #expect(state.installedApplication?.version == "0.19.0")
        #expect(state.installedApplication?.buildNumber == "19000")
        #expect(ProjectReleaseInspector.suggestedVersion(at: root) == "0.19.1")
        #expect(ProjectReleaseInspector.buildNumber(for: "0.19.1") == "19001")
    }

    @Test("Reconciles a complete release through tag, GitHub assets, update feed, and local app")
    func reconcilesCompleteRelease() throws {
        var goal = makeReleaseGoal(targetHeadSHA: "target")
        let local = releaseLocalState()

        goal = ProjectGoalReconciler.reconcile(
            goal,
            with: releaseObservation(local: local, tag: .absent, remote: .absent)
        )
        #expect(goal.nextStep == .releaseTag)
        #expect(goal.status == .ready)
        #expect(goal.step(.version)?.evidence == "0.19.0 (19000)")

        goal = ProjectGoalReconciler.reconcile(
            goal,
            with: releaseObservation(local: local, tag: .published, remote: .waiting(runNumber: 142))
        )
        #expect(goal.status == .waiting)
        #expect(goal.step(.githubRelease)?.evidence == "#142")

        let release = try releaseFixture()
        goal = ProjectGoalReconciler.reconcile(
            goal,
            with: releaseObservation(
                local: local,
                tag: .published,
                remote: .published(release, updateFeedVerified: true)
            )
        )
        #expect(goal.releaseAssetNames == ["GitGatto-0.19.0.dmg", "appcast.xml"])
        #expect(goal.step(.dmg)?.status == .completed)
        #expect(goal.step(.updateFeed)?.status == .completed)
        #expect(goal.nextStep == .localApplication)

        let installed = ProjectGoalReleaseLocalState(
            readmePath: local.readmePath,
            translationPaths: local.translationPaths,
            versionEvidence: local.versionEvidence,
            buildEvidence: local.buildEvidence,
            changelogPath: local.changelogPath,
            releasePipelinePath: local.releasePipelinePath,
            installedApplication: ProjectGoalInstalledApplication(
                path: "/Applications/GitGatto.app",
                version: "0.19.0",
                buildNumber: "19000"
            )
        )
        goal = ProjectGoalReconciler.reconcile(
            goal,
            with: releaseObservation(
                local: installed,
                tag: .published,
                remote: .published(release, updateFeedVerified: true)
            )
        )
        #expect(goal.status == .completed)
        #expect(goal.progress == 1)
        #expect(goal.installedApplicationPath == "/Applications/GitGatto.app")
    }

    @Test("Validates the release update feed against version, build, and DMG")
    func validatesReleaseUpdateFeed() {
        let valid = Data("""
        <item><sparkle:shortVersionString>0.19.0</sparkle:shortVersionString>
        <sparkle:version>19000</sparkle:version>
        <enclosure url="https://example.invalid/GitGatto-0.19.0.dmg" /></item>
        """.utf8)
        let wrongBuild = Data("""
        <item><sparkle:shortVersionString>0.19.0</sparkle:shortVersionString>
        <sparkle:version>18999</sparkle:version>
        <enclosure url="https://example.invalid/GitGatto-0.19.0.dmg" /></item>
        """.utf8)

        #expect(ProjectGoalReleaseService.verifyUpdateFeed(valid, version: "0.19.0", buildNumber: "19000"))
        #expect(!ProjectGoalReleaseService.verifyUpdateFeed(wrongBuild, version: "0.19.0", buildNumber: "19000"))
    }

    @Test("Builds a deterministic custom goal from Agent JSON")
    func buildsCustomGoalCandidate() throws {
        let response = """
        ```json
        {
          "title": "Verify the pull request",
          "commit_message": "feat: verify custom delivery",
          "release_version": null,
          "release_build_number": null,
          "conditions": ["pullRequest", "actions"]
        }
        ```
        """

        let candidate = try ProjectGoalPlanner.candidate(
            from: response,
            intent: "创建 PR 并等待 Actions 通过，但不要合并"
        )

        #expect(candidate.title == "Verify the pull request")
        #expect(candidate.stepKinds == [
            .stageChanges, .commit, .push, .pullRequest, .review, .actions
        ])
        #expect(candidate.releaseVersion == nil)
        #expect(candidate.commitMessage == "feat: verify custom delivery")
    }

    @Test("Normalizes a custom release target and derives its build number")
    func buildsCustomReleaseCandidate() throws {
        let response = """
        {
          "title": "Publish 0.19.0",
          "commit_message": "release: v0.19.0",
          "release_version": "0.19.0",
          "release_build_number": null,
          "conditions": ["updateFeed"]
        }
        """

        let candidate = try ProjectGoalPlanner.candidate(
            from: response,
            intent: "发布 0.19.0 并验证更新源，不替换本机应用"
        )

        #expect(candidate.stepKinds == Array(ProjectGoalPlanner.releaseSteps.prefix(through: 11)))
        #expect(candidate.releaseVersion == "0.19.0")
        #expect(candidate.releaseBuildNumber == "19000")
        #expect(!candidate.stepKinds.contains(.localApplication))
    }

    @Test("Rejects unknown, duplicate, and mixed custom goal conditions")
    func rejectsInvalidCustomConditions() {
        #expect(throws: ProjectGoalPlanningError.unsupportedCondition("deployProduction")) {
            _ = try ProjectGoalPlanner.candidate(
                from: """
                {"title":"Deploy","commit_message":"feat: deploy","release_version":null,
                "release_build_number":null,"conditions":["deployProduction"]}
                """,
                intent: "部署"
            )
        }
        #expect(throws: ProjectGoalPlanningError.duplicateCondition("push")) {
            _ = try ProjectGoalPlanner.candidate(
                from: """
                {"title":"Push","commit_message":"feat: push","release_version":null,
                "release_build_number":null,"conditions":["push","push"]}
                """,
                intent: "推送"
            )
        }
        #expect(throws: ProjectGoalPlanningError.incompatibleConditions) {
            _ = try ProjectGoalPlanner.normalizedSteps(for: [.releaseTag, .merge])
        }
    }

    @Test("Persists a custom goal title, intent, and condition order")
    func persistsCustomGoalContract() throws {
        let source = ProjectGoal(
            kind: .custom,
            repositoryPath: "/tmp/GitGatto",
            repositoryName: "GitGatto",
            branchName: "main",
            baselineHeadSHA: "base",
            title: "Push verified changes",
            intent: "提交并推送当前修改",
            commitMessage: "feat: deliver custom goal",
            stepKinds: [.stageChanges, .commit, .push]
        )

        let restored = try JSONDecoder().decode(
            ProjectGoal.self,
            from: JSONEncoder().encode(source)
        )

        #expect(restored.kind == .custom)
        #expect(restored.title == source.title)
        #expect(restored.intent == source.intent)
        #expect(restored.steps.map(\.kind) == [.stageChanges, .commit, .push])
    }

    @Test("Reconciles a custom pull request goal without merging")
    func reconcilesCustomPullRequestGoal() {
        var goal = ProjectGoal(
            kind: .custom,
            repositoryPath: "/tmp/GitGatto",
            repositoryName: "GitGatto",
            branchName: "feature/custom-goal",
            baselineHeadSHA: "base",
            title: "Verify pull request",
            intent: "创建 PR 并等待检查，但不要合并",
            commitMessage: "feat: verify custom goal",
            stepKinds: [.stageChanges, .commit, .push, .pullRequest, .review, .actions],
            targetHeadSHA: "target"
        )
        let pullRequest = GitHubDeliveryPullRequest(
            number: 28,
            title: "Verify custom goal",
            webURL: URL(string: "https://github.com/Lincb522/GitGatto/pull/28")!,
            headBranch: "feature/custom-goal",
            headSHA: "target",
            baseBranch: "main",
            isDraft: false,
            isMerged: false,
            isClosed: false,
            mergeable: true,
            reviewDecision: "APPROVED",
            approvalCount: 1,
            changesRequestedCount: 0,
            requestedReviewerCount: 0,
            unresolvedThreadCount: 0,
            hasUnscannedReviewThreads: false
        )

        goal = ProjectGoalReconciler.reconcile(
            goal,
            with: observation(
                branch: "feature/custom-goal",
                head: "target",
                published: true,
                actions: .passed(runNumbers: [28], artifacts: [], artifactsVerified: true),
                pullRequest: .open(pullRequest),
                baseBranch: "main"
            )
        )

        #expect(goal.status == .completed)
        #expect(goal.step(.actions)?.status == .completed)
        #expect(goal.step(.merge) == nil)
    }

    @Test("Completes a custom release after update feed verification without local installation")
    func reconcilesCustomReleaseWithoutInstall() throws {
        var goal = ProjectGoal(
            kind: .custom,
            repositoryPath: "/tmp/GitGatto",
            repositoryName: "GitGatto",
            branchName: "main",
            baselineHeadSHA: "base",
            title: "Publish 0.19.0",
            intent: "发布 0.19.0，但不要替换本机应用",
            commitMessage: "release: v0.19.0",
            stepKinds: Array(ProjectGoalPlanner.releaseSteps.prefix(through: 11)),
            targetHeadSHA: "target",
            releaseVersion: "0.19.0",
            releaseBuildNumber: "19000",
            releaseTag: "v0.19.0",
            releaseApplicationName: "GitGatto"
        )

        goal = ProjectGoalReconciler.reconcile(
            goal,
            with: releaseObservation(
                local: releaseLocalState(),
                tag: .published,
                remote: .published(try releaseFixture(), updateFeedVerified: true)
            )
        )

        #expect(goal.status == .completed)
        #expect(goal.step(.updateFeed)?.status == .completed)
        #expect(goal.step(.localApplication) == nil)
    }

    @Test("Keeps custom goal planning read-only and confirmation-based")
    func customGoalPromptContract() {
        let prompt = ProjectGoalPlanner.prompt(
            intent: "提交并推送",
            context: ProjectGoalPlanningContext(
                repositoryName: "GitGatto",
                branchName: "main",
                changeCount: 2,
                suggestedReleaseVersion: "0.19.0",
                suggestedReleaseBuildNumber: "19000"
            )
        )

        #expect(prompt.contains("This is planning only"))
        #expect(prompt.contains("Do not edit files"))
        #expect(prompt.contains("GitGatto will add its prerequisites deterministically"))
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

    private func makeReleaseGoal(
        repositoryPath: String = "/tmp/GitGatto",
        targetHeadSHA: String? = nil
    ) -> ProjectGoal {
        ProjectGoal(
            kind: .completeRelease,
            repositoryPath: repositoryPath,
            repositoryName: "GitGatto",
            branchName: "main",
            baselineHeadSHA: "base",
            commitMessage: "release: v0.19.0",
            targetHeadSHA: targetHeadSHA,
            releaseVersion: "0.19.0",
            releaseBuildNumber: "19000",
            releaseTag: "v0.19.0",
            releaseApplicationName: "GitGatto"
        )
    }

    private func releaseLocalState() -> ProjectGoalReleaseLocalState {
        ProjectGoalReleaseLocalState(
            readmePath: "README.md",
            translationPaths: ["README.en.md"],
            versionEvidence: [
                ProjectGoalReleaseValueEvidence(path: "project.yml", value: "0.19.0"),
                ProjectGoalReleaseValueEvidence(path: "scripts/package-macos.sh", value: "0.19.0")
            ],
            buildEvidence: [
                ProjectGoalReleaseValueEvidence(path: "project.yml", value: "19000"),
                ProjectGoalReleaseValueEvidence(path: "scripts/package-macos.sh", value: "19000")
            ],
            changelogPath: "CHANGELOG.md",
            releasePipelinePath: ".github/workflows/release.yml",
            installedApplication: ProjectGoalInstalledApplication(
                path: "/Applications/GitGatto.app",
                version: "0.18.10",
                buildNumber: "18010"
            )
        )
    }

    private func releaseObservation(
        local: ProjectGoalReleaseLocalState,
        tag: ProjectGoalReleaseTagState,
        remote: ProjectGoalReleaseRemoteState
    ) -> ProjectGoalObservation {
        ProjectGoalObservation(
            branchName: "main",
            upstreamName: "origin/main",
            aheadCount: 0,
            changes: [],
            headSHA: "target",
            targetPublished: true,
            remoteIdentity: RepositoryRemoteIdentity(
                remoteName: "origin",
                host: "github.com",
                fullName: "Lincb522/GitGatto"
            ),
            actions: .unavailable,
            pullRequest: .unavailable,
            baseBranch: nil,
            release: ProjectGoalReleaseState(local: local, tag: tag, remote: remote)
        )
    }

    private func releaseFixture() throws -> GitHubRelease {
        let webURL = try #require(URL(string: "https://github.com/Lincb522/GitGatto/releases/tag/v0.19.0"))
        let downloadRoot = try #require(
            URL(string: "https://github.com/Lincb522/GitGatto/releases/download/v0.19.0/")
        )
        return GitHubRelease(
            id: 19,
            tagName: "v0.19.0",
            name: "GitGatto 0.19.0",
            body: "Release notes",
            publishedAt: Date(),
            webURL: webURL,
            isPrerelease: false,
            assets: [
                GitHubReleaseAsset(
                    id: 1,
                    name: "GitGatto-0.19.0.dmg",
                    size: 4096,
                    downloadCount: 0,
                    contentType: "application/x-apple-diskimage",
                    downloadURL: downloadRoot.appendingPathComponent("GitGatto-0.19.0.dmg"),
                    createdAt: Date()
                ),
                GitHubReleaseAsset(
                    id: 2,
                    name: "appcast.xml",
                    size: 512,
                    downloadCount: 0,
                    contentType: "application/xml",
                    downloadURL: downloadRoot.appendingPathComponent("appcast.xml"),
                    createdAt: Date()
                )
            ]
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
