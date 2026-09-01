import Foundation

protocol ProjectGoalActionsServing: Sendable {
    func state(
        targetSHA: String,
        branch: String,
        remote: RepositoryRemoteIdentity
    ) async throws -> ProjectGoalActionsState
}

protocol ProjectGoalDeliveryServing: Sendable {
    func pullRequestState(
        targetSHA: String,
        branch: String,
        remote: RepositoryRemoteIdentity
    ) async throws -> (state: ProjectGoalPullRequestState, defaultBranch: String?)
    func createPullRequest(goal: ProjectGoal, remote: RepositoryRemoteIdentity) async throws
    func mergePullRequest(goal: ProjectGoal, remote: RepositoryRemoteIdentity) async throws
}

enum ProjectGoalExecutionResult: Sendable, Equatable {
    case none
    case committed(String)
    case installed(String)
}

actor ProjectGoalRuntime {
    private let repositoryService: any GitRepositoryServing
    private let actionsService: any ProjectGoalActionsServing
    private let deliveryService: any ProjectGoalDeliveryServing
    private let releaseService: any ProjectGoalReleaseServing

    init(
        repositoryService: any GitRepositoryServing,
        githubService: any GitHubServing
    ) {
        self.repositoryService = repositoryService
        self.actionsService = GitHubProjectGoalActionsService(githubService: githubService)
        self.deliveryService = GitHubProjectGoalDeliveryService(githubService: githubService)
        self.releaseService = ProjectGoalReleaseService(githubService: githubService)
    }

    init(
        repositoryService: any GitRepositoryServing,
        actionsService: any ProjectGoalActionsServing,
        deliveryService: any ProjectGoalDeliveryServing = UnavailableProjectGoalDeliveryService(),
        releaseService: any ProjectGoalReleaseServing = UnavailableProjectGoalReleaseService()
    ) {
        self.repositoryService = repositoryService
        self.actionsService = actionsService
        self.deliveryService = deliveryService
        self.releaseService = releaseService
    }

    func observe(_ goal: ProjectGoal) async throws -> ProjectGoalObservation {
        let repositoryURL = URL(fileURLWithPath: goal.repositoryPath, isDirectory: true)
        async let snapshotValue = repositoryService.loadRepository(at: repositoryURL)
        async let remoteValue = repositoryService.remoteIdentity(in: repositoryURL)
        let snapshot = try await snapshotValue
        let remote = try await remoteValue
        let headSHA = snapshot.commits.first?.hash ?? goal.baselineHeadSHA
        let targetPublished: Bool
        if let target = goal.targetHeadSHA {
            targetPublished = try await repositoryService.isCommitPublished(target, in: repositoryURL)
        } else {
            targetPublished = false
        }

        let actions: ProjectGoalActionsState
        if goal.kind != .completeRelease,
           let target = goal.targetHeadSHA,
           let remote,
           remote.isGitHub {
            actions = try await actionsService.state(
                targetSHA: target,
                branch: snapshot.branchName,
                remote: remote
            )
        } else {
            actions = .unavailable
        }

        let pullRequest: ProjectGoalPullRequestState
        var observedBaseBranch = goal.baseBranch
        if goal.kind == .githubDelivery,
           targetPublished,
           let target = goal.targetHeadSHA,
           let remote,
           remote.isGitHub {
            let delivery = try await deliveryService.pullRequestState(
                targetSHA: target,
                branch: snapshot.branchName,
                remote: remote
            )
            pullRequest = delivery.state
            observedBaseBranch = delivery.defaultBranch ?? observedBaseBranch
        } else {
            pullRequest = .unavailable
        }

        let release: ProjectGoalReleaseState?
        if goal.kind == .completeRelease {
            release = try await releaseService.state(goal: goal, remote: remote)
        } else {
            release = nil
        }

        return ProjectGoalObservation(
            branchName: snapshot.branchName,
            upstreamName: snapshot.upstreamName,
            aheadCount: snapshot.aheadCount,
            changes: snapshot.changes,
            headSHA: headSHA,
            targetPublished: targetPublished,
            remoteIdentity: remote,
            actions: actions,
            pullRequest: pullRequest,
            baseBranch: observedBaseBranch,
            release: release
        )
    }

    func execute(_ step: ProjectGoalStepKind, goal: ProjectGoal) async throws -> ProjectGoalExecutionResult {
        let repositoryURL = URL(fileURLWithPath: goal.repositoryPath, isDirectory: true)
        switch step {
        case .stageChanges:
            let state = try await repositoryService.loadLiveState(at: repositoryURL)
            let paths = state.changes.filter { !$0.isStaged }.map(\.path)
            try await repositoryService.stage(paths: paths, in: repositoryURL)
            return .none
        case .commit:
            let message = goal.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { throw ProjectGoalRuntimeError.missingCommitMessage }
            try await repositoryService.commit(message: message, in: repositoryURL)
            let snapshot = try await repositoryService.loadRepositoryOverview(at: repositoryURL)
            guard let hash = snapshot.commits.first?.hash else {
                throw ProjectGoalRuntimeError.repositoryHasNoHead
            }
            return .committed(hash)
        case .push:
            try await repositoryService.push(in: repositoryURL)
            return .none
        case .pullRequest:
            guard let remote = try await repositoryService.remoteIdentity(in: repositoryURL), remote.isGitHub else {
                throw ProjectGoalRuntimeError.githubRemoteRequired
            }
            try await deliveryService.createPullRequest(goal: goal, remote: remote)
            return .none
        case .merge:
            guard let remote = try await repositoryService.remoteIdentity(in: repositoryURL), remote.isGitHub else {
                throw ProjectGoalRuntimeError.githubRemoteRequired
            }
            try await deliveryService.mergePullRequest(goal: goal, remote: remote)
            return .none
        case .releaseTag:
            guard let remote = try await repositoryService.remoteIdentity(in: repositoryURL), remote.isGitHub else {
                throw ProjectGoalRuntimeError.githubRemoteRequired
            }
            try await releaseService.publish(goal: goal, remote: remote)
            return .none
        case .localApplication:
            guard let remote = try await repositoryService.remoteIdentity(in: repositoryURL), remote.isGitHub else {
                throw ProjectGoalRuntimeError.githubRemoteRequired
            }
            let installed = try await releaseService.install(goal: goal, remote: remote)
            return .installed(installed.path)
        case .readme,
             .translation,
             .version,
             .changelog,
             .releasePipeline,
             .review,
             .actions,
             .artifact,
             .githubRelease,
             .dmg,
             .updateFeed:
            return .none
        }
    }

}

actor UnavailableProjectGoalDeliveryService: ProjectGoalDeliveryServing {
    func pullRequestState(
        targetSHA: String,
        branch: String,
        remote: RepositoryRemoteIdentity
    ) async throws -> (state: ProjectGoalPullRequestState, defaultBranch: String?) {
        (.unavailable, nil)
    }

    func createPullRequest(goal: ProjectGoal, remote: RepositoryRemoteIdentity) async throws {
        throw ProjectGoalRuntimeError.githubRemoteRequired
    }

    func mergePullRequest(goal: ProjectGoal, remote: RepositoryRemoteIdentity) async throws {
        throw ProjectGoalRuntimeError.githubRemoteRequired
    }
}

private actor GitHubProjectGoalDeliveryService: ProjectGoalDeliveryServing {
    private let githubService: any GitHubServing

    init(githubService: any GitHubServing) {
        self.githubService = githubService
    }

    func pullRequestState(
        targetSHA: String,
        branch: String,
        remote: RepositoryRemoteIdentity
    ) async throws -> (state: ProjectGoalPullRequestState, defaultBranch: String?) {
        let repository = Self.repository(remote: remote, defaultBranch: branch)
        let result = try await githubService.deliveryPullRequest(
            headBranch: branch,
            targetSHA: targetSHA,
            in: repository
        )
        guard let pullRequest = result.pullRequest else {
            return (.absent(defaultBranch: result.defaultBranch), result.defaultBranch)
        }
        if pullRequest.isMerged {
            return (.merged(pullRequest), result.defaultBranch)
        }
        if pullRequest.isClosed {
            return (.closed(pullRequest), result.defaultBranch)
        }
        return (.open(pullRequest), result.defaultBranch)
    }

    func createPullRequest(goal: ProjectGoal, remote: RepositoryRemoteIdentity) async throws {
        guard let baseBranch = goal.baseBranch, baseBranch != goal.branchName else {
            throw ProjectGoalRuntimeError.pullRequestBranchRequired
        }
        let title = goal.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ProjectGoalRuntimeError.missingCommitMessage }
        try await githubService.createDeliveryPullRequest(
            title: title,
            body: "",
            headBranch: goal.branchName,
            baseBranch: baseBranch,
            in: Self.repository(remote: remote, defaultBranch: baseBranch)
        )
    }

    func mergePullRequest(goal: ProjectGoal, remote: RepositoryRemoteIdentity) async throws {
        guard let number = goal.pullRequestNumber else {
            throw ProjectGoalRuntimeError.pullRequestRequired
        }
        try await githubService.mergeDeliveryPullRequest(
            number: number,
            in: Self.repository(remote: remote, defaultBranch: goal.baseBranch ?? goal.branchName)
        )
    }

    private static func repository(
        remote: RepositoryRemoteIdentity,
        defaultBranch: String
    ) -> GitHubRepository {
        let parts = remote.fullName.split(separator: "/", maxSplits: 1).map(String.init)
        return GitHubRepository(
            fullName: remote.fullName,
            name: parts.count == 2 ? parts[1] : remote.fullName,
            owner: parts.first ?? "",
            description: nil,
            webURL: URL(string: "https://github.com/\(remote.fullName)")!,
            stars: 0,
            forks: 0,
            openIssues: 0,
            language: nil,
            updatedAt: .distantPast,
            isPrivate: false,
            defaultBranch: defaultBranch
        )
    }
}

private actor GitHubProjectGoalActionsService: ProjectGoalActionsServing {
    private let githubService: any GitHubServing

    init(githubService: any GitHubServing) {
        self.githubService = githubService
    }

    func state(
        targetSHA: String,
        branch: String,
        remote: RepositoryRemoteIdentity
    ) async throws -> ProjectGoalActionsState {
        let parts = remote.fullName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return .unavailable }
        let repository = GitHubRepository(
            fullName: remote.fullName,
            name: parts[1],
            owner: parts[0],
            description: nil,
            webURL: URL(string: "https://github.com/\(remote.fullName)")!,
            stars: 0,
            forks: 0,
            openIssues: 0,
            language: nil,
            updatedAt: .distantPast,
            isPrivate: false,
            defaultBranch: branch
        )
        let workflows = try await githubService.actionWorkflows(for: repository)
            .filter { $0.state.caseInsensitiveCompare("active") == .orderedSame }
        guard !workflows.isEmpty else { return .noWorkflows }
        let runs = try await githubService.actionRuns(for: repository)
        let activeWorkflowIDs = Set(workflows.map(\.id))
        let matching = Dictionary(
            grouping: runs.filter { $0.headSHA == targetSHA && activeWorkflowIDs.contains($0.workflowID) },
            by: \.workflowID
        )
        let latestRuns = matching.values.compactMap {
            $0.max(by: { $0.runNumber < $1.runNumber })
        }
        guard !latestRuns.isEmpty else { return .waiting }

        if let failed = latestRuns.first(where: { Self.isFailedConclusion($0.conclusion) }) {
            let detail = try? await githubService.actionRunDetail(failed, in: repository, includeLog: true)
            let excerpt = detail?.log.map { String($0.suffix(24_000)) }
            return .failed(
                ProjectGoalActionFailure(
                    runID: failed.id,
                    runNumber: failed.runNumber,
                    workflowName: failed.name,
                    conclusion: failed.conclusion ?? "failure",
                    webURL: failed.webURL,
                    logExcerpt: excerpt
                )
            )
        }
        if latestRuns.contains(where: { Self.isActiveStatus($0.status) }) {
            return .running(runNumbers: latestRuns.map(\.runNumber).sorted())
        }
        let passedConclusions = Set(["success", "neutral", "skipped"])
        if latestRuns.allSatisfy({ run in
            guard let conclusion = run.conclusion?.lowercased() else { return false }
            return passedConclusions.contains(conclusion)
        }) {
            var artifacts: [ProjectGoalActionArtifact] = []
            var artifactsVerified = true
            for run in latestRuns {
                do {
                    let detail = try await githubService.actionRunDetail(run, in: repository, includeLog: false)
                    artifacts.append(contentsOf: detail.artifacts.map {
                        ProjectGoalActionArtifact(
                            id: $0.id,
                            name: $0.name,
                            runID: run.id,
                            runNumber: run.runNumber,
                            sizeInBytes: $0.sizeInBytes,
                            isExpired: $0.isExpired
                        )
                    })
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    artifactsVerified = false
                }
            }
            return .passed(
                runNumbers: latestRuns.map(\.runNumber).sorted(),
                artifacts: artifacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
                artifactsVerified: artifactsVerified
            )
        }
        return .waiting
    }

    private static func isActiveStatus(_ status: String) -> Bool {
        ["queued", "in_progress", "waiting", "requested", "pending"].contains(status.lowercased())
    }

    private static func isFailedConclusion(_ conclusion: String?) -> Bool {
        guard let conclusion = conclusion?.lowercased() else { return false }
        return ["failure", "cancelled", "timed_out", "action_required", "startup_failure", "stale"]
            .contains(conclusion)
    }
}
