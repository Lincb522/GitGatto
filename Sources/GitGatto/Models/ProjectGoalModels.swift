import Foundation

enum ProjectGoalKind: String, Codable, Sendable {
    case deliverChanges
    case githubDelivery
    case completeRelease

    var stepKinds: [ProjectGoalStepKind] {
        switch self {
        case .deliverChanges:
            [.stageChanges, .commit, .push, .actions]
        case .githubDelivery:
            [.stageChanges, .commit, .push, .pullRequest, .review, .actions, .artifact, .merge]
        case .completeRelease:
            [
                .readme,
                .translation,
                .version,
                .changelog,
                .releasePipeline,
                .stageChanges,
                .commit,
                .push,
                .releaseTag,
                .githubRelease,
                .dmg,
                .updateFeed,
                .localApplication
            ]
        }
    }
}

enum ProjectGoalStatus: String, Codable, Sendable, Equatable {
    case ready
    case running
    case waiting
    case blocked
    case completed
    case cancelled

    var isTerminal: Bool {
        self == .completed || self == .cancelled
    }
}

enum ProjectGoalStepKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case readme
    case translation
    case version
    case changelog
    case releasePipeline
    case stageChanges
    case commit
    case push
    case pullRequest
    case review
    case actions
    case artifact
    case merge
    case releaseTag
    case githubRelease
    case dmg
    case updateFeed
    case localApplication

    var id: String { rawValue }

    var operation: OperationKind? {
        switch self {
        case .stageChanges: .stage
        case .commit: .commit
        case .push: .push
        case .readme,
             .translation,
             .version,
             .changelog,
             .releasePipeline,
             .pullRequest,
             .review,
             .actions,
             .artifact,
             .merge,
             .releaseTag,
             .githubRelease,
             .dmg,
             .updateFeed,
             .localApplication:
            nil
        }
    }
}

enum ProjectGoalStepStatus: String, Codable, Sendable, Equatable {
    case pending
    case running
    case waiting
    case blocked
    case completed
    case notRequired

    var isSatisfied: Bool {
        self == .completed || self == .notRequired
    }
}

struct ProjectGoalStep: Identifiable, Codable, Sendable, Equatable {
    let kind: ProjectGoalStepKind
    var status: ProjectGoalStepStatus
    var updatedAt: Date
    var evidence: String?
    var error: String?

    var id: ProjectGoalStepKind { kind }
}

struct ProjectGoal: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let kind: ProjectGoalKind
    let repositoryPath: String
    let repositoryName: String
    let branchName: String
    let baselineHeadSHA: String
    var commitMessage: String
    var targetHeadSHA: String?
    var remoteFullName: String?
    var baseBranch: String?
    var pullRequestNumber: Int?
    var pullRequestTitle: String?
    var pullRequestURL: URL?
    var lastActionFailure: ProjectGoalActionFailure?
    var artifactNames: [String]
    var repairAttemptCount: Int
    var releaseVersion: String?
    var releaseBuildNumber: String?
    var releaseTag: String?
    var releaseApplicationName: String?
    var releaseURL: URL?
    var releaseAssetNames: [String]
    var releaseWorkflowRunNumber: Int?
    var installedApplicationPath: String?
    var installedApplicationVersion: String?
    var installedApplicationBuild: String?
    var status: ProjectGoalStatus
    var steps: [ProjectGoalStep]
    let createdAt: Date
    var updatedAt: Date
    var lastError: String?

    init(
        id: UUID = UUID(),
        kind: ProjectGoalKind = .deliverChanges,
        repositoryPath: String,
        repositoryName: String,
        branchName: String,
        baselineHeadSHA: String,
        commitMessage: String,
        targetHeadSHA: String? = nil,
        remoteFullName: String? = nil,
        baseBranch: String? = nil,
        pullRequestNumber: Int? = nil,
        pullRequestTitle: String? = nil,
        pullRequestURL: URL? = nil,
        lastActionFailure: ProjectGoalActionFailure? = nil,
        artifactNames: [String] = [],
        repairAttemptCount: Int = 0,
        releaseVersion: String? = nil,
        releaseBuildNumber: String? = nil,
        releaseTag: String? = nil,
        releaseApplicationName: String? = nil,
        releaseURL: URL? = nil,
        releaseAssetNames: [String] = [],
        releaseWorkflowRunNumber: Int? = nil,
        installedApplicationPath: String? = nil,
        installedApplicationVersion: String? = nil,
        installedApplicationBuild: String? = nil,
        status: ProjectGoalStatus = .ready,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.repositoryPath = repositoryPath
        self.repositoryName = repositoryName
        self.branchName = branchName
        self.baselineHeadSHA = baselineHeadSHA
        self.commitMessage = commitMessage
        self.targetHeadSHA = targetHeadSHA
        self.remoteFullName = remoteFullName
        self.baseBranch = baseBranch
        self.pullRequestNumber = pullRequestNumber
        self.pullRequestTitle = pullRequestTitle
        self.pullRequestURL = pullRequestURL
        self.lastActionFailure = lastActionFailure
        self.artifactNames = artifactNames
        self.repairAttemptCount = repairAttemptCount
        self.releaseVersion = releaseVersion
        self.releaseBuildNumber = releaseBuildNumber
        self.releaseTag = releaseTag
        self.releaseApplicationName = releaseApplicationName
        self.releaseURL = releaseURL
        self.releaseAssetNames = releaseAssetNames
        self.releaseWorkflowRunNumber = releaseWorkflowRunNumber
        self.installedApplicationPath = installedApplicationPath
        self.installedApplicationVersion = installedApplicationVersion
        self.installedApplicationBuild = installedApplicationBuild
        self.status = status
        self.steps = kind.stepKinds.map {
            ProjectGoalStep(kind: $0, status: .pending, updatedAt: createdAt)
        }
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.lastError = nil
    }

    var progress: Double {
        guard !steps.isEmpty else { return 0 }
        let satisfied = steps.filter { $0.status.isSatisfied }.count
        return Double(satisfied) / Double(steps.count)
    }

    var nextStep: ProjectGoalStepKind? {
        steps.first { !$0.status.isSatisfied }?.kind
    }

    func step(_ kind: ProjectGoalStepKind) -> ProjectGoalStep? {
        steps.first { $0.kind == kind }
    }

    mutating func updateStep(
        _ kind: ProjectGoalStepKind,
        status: ProjectGoalStepStatus,
        evidence: String? = nil,
        error: String? = nil,
        at date: Date = Date()
    ) {
        guard let index = steps.firstIndex(where: { $0.kind == kind }) else { return }
        steps[index].status = status
        steps[index].updatedAt = date
        if let evidence {
            steps[index].evidence = evidence
        }
        steps[index].error = error
        updatedAt = date
    }

    mutating func resetForActionsRepair(at date: Date = Date()) {
        targetHeadSHA = nil
        lastActionFailure = nil
        artifactNames = []
        repairAttemptCount += 1
        lastError = nil
        status = .ready
        for index in steps.indices {
            steps[index].status = .pending
            steps[index].evidence = nil
            steps[index].error = nil
            steps[index].updatedAt = date
        }
        updatedAt = date
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case repositoryPath
        case repositoryName
        case branchName
        case baselineHeadSHA
        case commitMessage
        case targetHeadSHA
        case remoteFullName
        case baseBranch
        case pullRequestNumber
        case pullRequestTitle
        case pullRequestURL
        case lastActionFailure
        case artifactNames
        case repairAttemptCount
        case releaseVersion
        case releaseBuildNumber
        case releaseTag
        case releaseApplicationName
        case releaseURL
        case releaseAssetNames
        case releaseWorkflowRunNumber
        case installedApplicationPath
        case installedApplicationVersion
        case installedApplicationBuild
        case status
        case steps
        case createdAt
        case updatedAt
        case lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(ProjectGoalKind.self, forKey: .kind)
        repositoryPath = try container.decode(String.self, forKey: .repositoryPath)
        repositoryName = try container.decode(String.self, forKey: .repositoryName)
        branchName = try container.decode(String.self, forKey: .branchName)
        baselineHeadSHA = try container.decode(String.self, forKey: .baselineHeadSHA)
        commitMessage = try container.decode(String.self, forKey: .commitMessage)
        targetHeadSHA = try container.decodeIfPresent(String.self, forKey: .targetHeadSHA)
        remoteFullName = try container.decodeIfPresent(String.self, forKey: .remoteFullName)
        baseBranch = try container.decodeIfPresent(String.self, forKey: .baseBranch)
        pullRequestNumber = try container.decodeIfPresent(Int.self, forKey: .pullRequestNumber)
        pullRequestTitle = try container.decodeIfPresent(String.self, forKey: .pullRequestTitle)
        pullRequestURL = try container.decodeIfPresent(URL.self, forKey: .pullRequestURL)
        lastActionFailure = try container.decodeIfPresent(ProjectGoalActionFailure.self, forKey: .lastActionFailure)
        artifactNames = try container.decodeIfPresent([String].self, forKey: .artifactNames) ?? []
        repairAttemptCount = try container.decodeIfPresent(Int.self, forKey: .repairAttemptCount) ?? 0
        releaseVersion = try container.decodeIfPresent(String.self, forKey: .releaseVersion)
        releaseBuildNumber = try container.decodeIfPresent(String.self, forKey: .releaseBuildNumber)
        releaseTag = try container.decodeIfPresent(String.self, forKey: .releaseTag)
        releaseApplicationName = try container.decodeIfPresent(String.self, forKey: .releaseApplicationName)
        releaseURL = try container.decodeIfPresent(URL.self, forKey: .releaseURL)
        releaseAssetNames = try container.decodeIfPresent([String].self, forKey: .releaseAssetNames) ?? []
        releaseWorkflowRunNumber = try container.decodeIfPresent(Int.self, forKey: .releaseWorkflowRunNumber)
        installedApplicationPath = try container.decodeIfPresent(String.self, forKey: .installedApplicationPath)
        installedApplicationVersion = try container.decodeIfPresent(String.self, forKey: .installedApplicationVersion)
        installedApplicationBuild = try container.decodeIfPresent(String.self, forKey: .installedApplicationBuild)
        status = try container.decode(ProjectGoalStatus.self, forKey: .status)
        let storedSteps = try container.decode([ProjectGoalStep].self, forKey: .steps)
        let storedByKind = Dictionary(uniqueKeysWithValues: storedSteps.map { ($0.kind, $0) })
        let fallbackDate = try container.decode(Date.self, forKey: .updatedAt)
        steps = kind.stepKinds.map {
            storedByKind[$0] ?? ProjectGoalStep(kind: $0, status: .pending, updatedAt: fallbackDate)
        }
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = fallbackDate
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }
}

struct RepositoryRemoteIdentity: Codable, Sendable, Equatable {
    let remoteName: String
    let host: String
    let fullName: String

    var isGitHub: Bool {
        host.caseInsensitiveCompare("github.com") == .orderedSame
    }

    static func parse(remoteName: String, remoteURL: String) -> RepositoryRemoteIdentity? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let host: String
        let path: String
        if let url = URL(string: trimmed), let parsedHost = url.host {
            host = parsedHost
            path = url.path
        } else if let separator = trimmed.firstIndex(of: ":"),
                  trimmed[..<separator].contains("@") {
            let authority = trimmed[..<separator]
            host = String(authority.split(separator: "@").last ?? "")
            path = String(trimmed[trimmed.index(after: separator)...])
        } else {
            return nil
        }

        let fullName = path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: ".git", with: "", options: [.anchored, .backwards])
        guard fullName.split(separator: "/").count >= 2 else { return nil }
        return RepositoryRemoteIdentity(remoteName: remoteName, host: host, fullName: fullName)
    }
}

struct ProjectGoalActionArtifact: Codable, Sendable, Equatable, Identifiable {
    let id: Int64
    let name: String
    let runID: Int64
    let runNumber: Int
    let sizeInBytes: Int
    let isExpired: Bool
}

struct ProjectGoalActionFailure: Codable, Sendable, Equatable {
    let runID: Int64
    let runNumber: Int
    let workflowName: String
    let conclusion: String
    let webURL: URL
    let logExcerpt: String?

    private enum CodingKeys: String, CodingKey {
        case runID
        case runNumber
        case workflowName
        case conclusion
        case webURL
    }

    init(
        runID: Int64,
        runNumber: Int,
        workflowName: String,
        conclusion: String,
        webURL: URL,
        logExcerpt: String?
    ) {
        self.runID = runID
        self.runNumber = runNumber
        self.workflowName = workflowName
        self.conclusion = conclusion
        self.webURL = webURL
        self.logExcerpt = logExcerpt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runID = try container.decode(Int64.self, forKey: .runID)
        runNumber = try container.decode(Int.self, forKey: .runNumber)
        workflowName = try container.decode(String.self, forKey: .workflowName)
        conclusion = try container.decode(String.self, forKey: .conclusion)
        webURL = try container.decode(URL.self, forKey: .webURL)
        logExcerpt = nil
    }
}

enum ProjectGoalActionsState: Sendable, Equatable {
    case unavailable
    case noWorkflows
    case waiting
    case running(runNumbers: [Int])
    case passed(runNumbers: [Int], artifacts: [ProjectGoalActionArtifact], artifactsVerified: Bool)
    case failed(ProjectGoalActionFailure)
}

enum ProjectGoalPullRequestState: Sendable, Equatable {
    case unavailable
    case absent(defaultBranch: String)
    case open(GitHubDeliveryPullRequest)
    case merged(GitHubDeliveryPullRequest)
    case closed(GitHubDeliveryPullRequest)
}

struct ProjectGoalReleaseValueEvidence: Sendable, Equatable {
    let path: String
    let value: String
}

struct ProjectGoalInstalledApplication: Sendable, Equatable {
    let path: String
    let version: String
    let buildNumber: String
}

struct ProjectGoalReleaseLocalState: Sendable, Equatable {
    let readmePath: String?
    let translationPaths: [String]
    let versionEvidence: [ProjectGoalReleaseValueEvidence]
    let buildEvidence: [ProjectGoalReleaseValueEvidence]
    let changelogPath: String?
    let releasePipelinePath: String?
    let installedApplication: ProjectGoalInstalledApplication?
}

enum ProjectGoalReleaseTagState: Sendable, Equatable {
    case absent
    case localOnly
    case published
    case mismatched(String)
}

enum ProjectGoalReleaseRemoteState: Sendable, Equatable {
    case unavailable
    case absent
    case waiting(runNumber: Int?)
    case failed(ProjectGoalActionFailure)
    case published(GitHubRelease, updateFeedVerified: Bool)
}

struct ProjectGoalReleaseState: Sendable, Equatable {
    let local: ProjectGoalReleaseLocalState
    let tag: ProjectGoalReleaseTagState
    let remote: ProjectGoalReleaseRemoteState
}

struct ProjectGoalObservation: Sendable, Equatable {
    let branchName: String
    let upstreamName: String?
    let aheadCount: Int
    let changes: [WorkingTreeChange]
    let headSHA: String
    let targetPublished: Bool
    let remoteIdentity: RepositoryRemoteIdentity?
    let actions: ProjectGoalActionsState
    let pullRequest: ProjectGoalPullRequestState
    let baseBranch: String?
    let release: ProjectGoalReleaseState?

    init(
        branchName: String,
        upstreamName: String?,
        aheadCount: Int,
        changes: [WorkingTreeChange],
        headSHA: String,
        targetPublished: Bool,
        remoteIdentity: RepositoryRemoteIdentity?,
        actions: ProjectGoalActionsState,
        pullRequest: ProjectGoalPullRequestState,
        baseBranch: String?,
        release: ProjectGoalReleaseState? = nil
    ) {
        self.branchName = branchName
        self.upstreamName = upstreamName
        self.aheadCount = aheadCount
        self.changes = changes
        self.headSHA = headSHA
        self.targetPublished = targetPublished
        self.remoteIdentity = remoteIdentity
        self.actions = actions
        self.pullRequest = pullRequest
        self.baseBranch = baseBranch
        self.release = release
    }
}

enum ProjectGoalRuntimeError: LocalizedError, Sendable, Equatable {
    case missingCommitMessage
    case githubRemoteRequired
    case repositoryHasNoHead
    case pullRequestBranchRequired
    case pullRequestRequired
    case invalidReleaseVersion
    case invalidReleaseBuildNumber
    case releaseMetadataRequired
    case releaseWorkflowRequired
    case releaseTagMismatch
    case releaseAssetRequired

    var errorDescription: String? {
        switch self {
        case .missingCommitMessage: L10n.text("goal.error.commit_message")
        case .githubRemoteRequired: L10n.text("goal.error.github_remote")
        case .repositoryHasNoHead: L10n.text("goal.error.no_head")
        case .pullRequestBranchRequired: L10n.text("goal.error.pr_branch")
        case .pullRequestRequired: L10n.text("goal.error.pr_required")
        case .invalidReleaseVersion: L10n.text("goal.error.release_version")
        case .invalidReleaseBuildNumber: L10n.text("goal.error.release_build")
        case .releaseMetadataRequired: L10n.text("goal.error.release_metadata")
        case .releaseWorkflowRequired: L10n.text("goal.error.release_pipeline")
        case .releaseTagMismatch: L10n.text("goal.error.release_tag_mismatch")
        case .releaseAssetRequired: L10n.text("goal.error.release_asset")
        }
    }
}

enum ProjectGoalReconciler {
    static func reconcile(_ source: ProjectGoal, with observation: ProjectGoalObservation) -> ProjectGoal {
        guard source.status != .cancelled else { return source }
        var goal = source
        let now = Date()
        goal.remoteFullName = observation.remoteIdentity?.fullName
        goal.lastError = nil

        if observation.branchName != goal.branchName {
            let error = L10n.format("goal.error.branch_changed", goal.branchName, observation.branchName)
            let step = goal.nextStep ?? .push
            goal.updateStep(step, status: .blocked, error: error, at: now)
            goal.status = .blocked
            goal.lastError = error
            return goal
        }

        if goal.kind == .completeRelease {
            reconcileCompleteRelease(&goal, observation: observation, at: now)
            finalize(&goal, at: now)
            return goal
        }

        if goal.targetHeadSHA == nil {
            let unstaged = observation.changes.contains { !$0.isStaged }
            goal.updateStep(
                .stageChanges,
                status: unstaged ? .pending : .completed,
                evidence: unstaged ? nil : String(observation.changes.filter(\.isStaged).count),
                at: now
            )

            if observation.changes.isEmpty {
                goal.targetHeadSHA = observation.headSHA
                goal.updateStep(
                    .commit,
                    status: observation.headSHA == goal.baselineHeadSHA ? .notRequired : .completed,
                    evidence: String(observation.headSHA.prefix(12)),
                    at: now
                )
            } else {
                goal.updateStep(.commit, status: .pending, at: now)
            }
        } else {
            goal.updateStep(.stageChanges, status: .completed, at: now)
            goal.updateStep(
                .commit,
                status: .completed,
                evidence: goal.targetHeadSHA.map { String($0.prefix(12)) },
                at: now
            )
        }

        if let target = goal.targetHeadSHA {
            goal.updateStep(
                .push,
                status: observation.targetPublished ? .completed : .pending,
                evidence: observation.targetPublished ? String(target.prefix(12)) : nil,
                at: now
            )
        } else {
            goal.updateStep(.push, status: .pending, at: now)
        }

        if goal.step(.push)?.status == .completed {
            if goal.kind == .githubDelivery {
                reconcileGitHubDelivery(&goal, observation: observation, at: now)
            } else {
                reconcileActions(&goal, state: observation.actions, at: now)
            }
        } else {
            for kind in goal.kind.stepKinds.dropFirst(3) {
                goal.updateStep(kind, status: .pending, at: now)
            }
        }

        finalize(&goal, at: now)
        return goal
    }

    private static func reconcileCompleteRelease(
        _ goal: inout ProjectGoal,
        observation: ProjectGoalObservation,
        at date: Date
    ) {
        guard let release = observation.release,
              let version = goal.releaseVersion,
              let buildNumber = goal.releaseBuildNumber,
              let tag = goal.releaseTag else {
            goal.updateStep(
                .version,
                status: .blocked,
                error: L10n.text("goal.error.release_metadata"),
                at: date
            )
            resetReleaseSteps(after: .releasePipeline, in: &goal, at: date)
            return
        }

        let local = release.local
        if let path = local.readmePath {
            goal.updateStep(.readme, status: .completed, evidence: path, at: date)
        } else {
            goal.updateStep(
                .readme,
                status: .blocked,
                error: L10n.text("goal.error.release_readme"),
                at: date
            )
        }

        if local.translationPaths.isEmpty {
            goal.updateStep(
                .translation,
                status: .blocked,
                error: L10n.text("goal.error.release_translation"),
                at: date
            )
        } else {
            goal.updateStep(
                .translation,
                status: .completed,
                evidence: local.translationPaths.joined(separator: ", "),
                at: date
            )
        }

        let versionsMatch = !local.versionEvidence.isEmpty
            && local.versionEvidence.allSatisfy { $0.value == version }
        let buildsMatch = !local.buildEvidence.isEmpty
            && local.buildEvidence.allSatisfy { $0.value == buildNumber }
        if versionsMatch && buildsMatch {
            goal.updateStep(
                .version,
                status: .completed,
                evidence: "(version) ((buildNumber))",
                at: date
            )
        } else {
            let evidence = (local.versionEvidence + local.buildEvidence)
                .map { "\($0.path): \($0.value)" }
                .joined(separator: ", ")
            goal.updateStep(
                .version,
                status: .blocked,
                evidence: evidence.isEmpty ? nil : evidence,
                error: L10n.format("goal.error.release_version_mismatch", version, buildNumber),
                at: date
            )
        }

        if let path = local.changelogPath {
            goal.updateStep(.changelog, status: .completed, evidence: path, at: date)
        } else {
            goal.updateStep(
                .changelog,
                status: .blocked,
                error: L10n.format("goal.error.release_changelog", version),
                at: date
            )
        }

        if let path = local.releasePipelinePath {
            goal.updateStep(.releasePipeline, status: .completed, evidence: path, at: date)
        } else {
            goal.updateStep(
                .releasePipeline,
                status: .blocked,
                error: L10n.text("goal.error.release_pipeline"),
                at: date
            )
        }

        let preparationSteps: [ProjectGoalStepKind] = [
            .readme, .translation, .version, .changelog, .releasePipeline
        ]
        guard preparationSteps.allSatisfy({ goal.step($0)?.status.isSatisfied == true }) else {
            resetReleaseSteps(after: .releasePipeline, in: &goal, at: date)
            return
        }

        if goal.targetHeadSHA == nil {
            let unstaged = observation.changes.contains { !$0.isStaged }
            goal.updateStep(
                .stageChanges,
                status: unstaged ? .pending : .completed,
                evidence: unstaged ? nil : String(observation.changes.filter(\.isStaged).count),
                at: date
            )
            if observation.changes.isEmpty {
                goal.targetHeadSHA = observation.headSHA
                goal.updateStep(
                    .commit,
                    status: observation.headSHA == goal.baselineHeadSHA ? .notRequired : .completed,
                    evidence: String(observation.headSHA.prefix(12)),
                    at: date
                )
            } else {
                goal.updateStep(.commit, status: .pending, at: date)
            }
        } else {
            goal.updateStep(.stageChanges, status: .completed, at: date)
            goal.updateStep(
                .commit,
                status: .completed,
                evidence: goal.targetHeadSHA.map { String($0.prefix(12)) },
                at: date
            )
        }

        if let target = goal.targetHeadSHA {
            goal.updateStep(
                .push,
                status: observation.targetPublished ? .completed : .pending,
                evidence: observation.targetPublished ? String(target.prefix(12)) : nil,
                at: date
            )
        } else {
            goal.updateStep(.push, status: .pending, at: date)
        }
        guard goal.step(.push)?.status == .completed else {
            resetReleaseSteps(after: .push, in: &goal, at: date)
            return
        }

        switch release.tag {
        case .absent, .localOnly:
            goal.updateStep(.releaseTag, status: .pending, evidence: tag, at: date)
        case .published:
            goal.updateStep(.releaseTag, status: .completed, evidence: tag, at: date)
        case let .mismatched(actual):
            goal.updateStep(
                .releaseTag,
                status: .blocked,
                evidence: actual,
                error: L10n.text("goal.error.release_tag_mismatch"),
                at: date
            )
        }
        guard goal.step(.releaseTag)?.status == .completed else {
            resetReleaseSteps(after: .releaseTag, in: &goal, at: date)
            return
        }

        if let installed = local.installedApplication {
            goal.installedApplicationPath = installed.path
            goal.installedApplicationVersion = installed.version
            goal.installedApplicationBuild = installed.buildNumber
        } else {
            goal.installedApplicationPath = nil
            goal.installedApplicationVersion = nil
            goal.installedApplicationBuild = nil
        }

        switch release.remote {
        case .unavailable:
            goal.updateStep(
                .githubRelease,
                status: .blocked,
                error: L10n.text("goal.error.github_remote"),
                at: date
            )
            resetReleaseSteps(after: .githubRelease, in: &goal, at: date)
        case .absent:
            goal.updateStep(.githubRelease, status: .waiting, evidence: tag, at: date)
            resetReleaseSteps(after: .githubRelease, in: &goal, at: date)
        case let .waiting(runNumber):
            goal.releaseWorkflowRunNumber = runNumber
            goal.updateStep(
                .githubRelease,
                status: .waiting,
                evidence: runNumber.map { "#\($0)" } ?? tag,
                at: date
            )
            resetReleaseSteps(after: .githubRelease, in: &goal, at: date)
        case let .failed(failure):
            goal.lastActionFailure = failure
            goal.releaseWorkflowRunNumber = failure.runNumber
            goal.updateStep(
                .githubRelease,
                status: .blocked,
                evidence: "#\(failure.runNumber) · \(failure.workflowName)",
                error: actionFailureExplanation(failure.conclusion),
                at: date
            )
            resetReleaseSteps(after: .githubRelease, in: &goal, at: date)
        case let .published(publication, updateFeedVerified):
            goal.lastActionFailure = nil
            goal.releaseURL = publication.webURL
            goal.releaseAssetNames = publication.assets.map(\.name)
            goal.updateStep(
                .githubRelease,
                status: .completed,
                evidence: publication.tagName,
                at: date
            )

            let diskImages = publication.assets.filter {
                $0.name.lowercased().hasSuffix(".dmg")
            }
            if diskImages.isEmpty {
                goal.updateStep(
                    .dmg,
                    status: .blocked,
                    error: L10n.text("goal.error.release_dmg"),
                    at: date
                )
            } else {
                goal.updateStep(
                    .dmg,
                    status: .completed,
                    evidence: diskImages.map(\.name).joined(separator: ", "),
                    at: date
                )
            }

            let updateFeed = publication.assets.first {
                $0.name.caseInsensitiveCompare("appcast.xml") == .orderedSame
            }
            if updateFeed == nil || !updateFeedVerified {
                goal.updateStep(
                    .updateFeed,
                    status: .blocked,
                    evidence: updateFeed?.name,
                    error: L10n.text("goal.error.release_update_feed"),
                    at: date
                )
            } else {
                goal.updateStep(
                    .updateFeed,
                    status: .completed,
                    evidence: updateFeed?.name,
                    at: date
                )
            }

            if local.installedApplication?.version == version,
               local.installedApplication?.buildNumber == buildNumber {
                goal.updateStep(
                    .localApplication,
                    status: .completed,
                    evidence: local.installedApplication?.path,
                    at: date
                )
            } else {
                goal.updateStep(
                    .localApplication,
                    status: .pending,
                    evidence: local.installedApplication.map {
                        "\($0.version) (\($0.buildNumber))"
                    },
                    at: date
                )
            }
        }
    }

    private static func resetReleaseSteps(
        after step: ProjectGoalStepKind,
        in goal: inout ProjectGoal,
        at date: Date
    ) {
        guard let index = goal.steps.firstIndex(where: { $0.kind == step }),
              index + 1 < goal.steps.count else { return }
        for next in goal.steps[(index + 1)...] {
            goal.updateStep(next.kind, status: .pending, at: date)
        }
    }

    private static func reconcileGitHubDelivery(
        _ goal: inout ProjectGoal,
        observation: ProjectGoalObservation,
        at date: Date
    ) {
        goal.baseBranch = observation.baseBranch ?? goal.baseBranch
        let pullRequest: GitHubDeliveryPullRequest?
        let isMerged: Bool
        switch observation.pullRequest {
        case .unavailable:
            goal.updateStep(
                .pullRequest,
                status: .blocked,
                error: L10n.text("goal.error.github_remote"),
                at: date
            )
            pullRequest = nil
            isMerged = false
        case let .absent(defaultBranch):
            goal.baseBranch = defaultBranch
            if defaultBranch == goal.branchName {
                goal.updateStep(
                    .pullRequest,
                    status: .blocked,
                    error: L10n.text("goal.error.pr_branch"),
                    at: date
                )
            } else {
                goal.updateStep(.pullRequest, status: .pending, at: date)
            }
            pullRequest = nil
            isMerged = false
        case let .open(value):
            record(value, in: &goal)
            goal.updateStep(
                .pullRequest,
                status: .completed,
                evidence: L10n.format("goal.evidence.pr", value.number, value.baseBranch),
                at: date
            )
            pullRequest = value
            isMerged = false
        case let .merged(value):
            record(value, in: &goal)
            goal.updateStep(
                .pullRequest,
                status: .completed,
                evidence: L10n.format("goal.evidence.pr", value.number, value.baseBranch),
                at: date
            )
            pullRequest = value
            isMerged = true
        case let .closed(value):
            record(value, in: &goal)
            goal.updateStep(
                .pullRequest,
                status: .blocked,
                evidence: L10n.format("goal.evidence.pr", value.number, value.baseBranch),
                error: L10n.text("goal.error.pr_closed"),
                at: date
            )
            pullRequest = value
            isMerged = false
        }

        guard let pullRequest else {
            for kind in [ProjectGoalStepKind.review, .actions, .artifact, .merge] {
                goal.updateStep(kind, status: .pending, at: date)
            }
            return
        }

        if pullRequest.isDraft && !isMerged {
            goal.updateStep(
                .review,
                status: .waiting,
                evidence: L10n.text("goal.evidence.pr_draft"),
                at: date
            )
        } else if pullRequest.hasReviewBlockers {
            let error = pullRequest.hasUnscannedReviewThreads
                ? L10n.text("goal.error.review_scan_incomplete")
                : L10n.format(
                    "goal.error.review_blocked",
                    pullRequest.changesRequestedCount,
                    pullRequest.unresolvedThreadCount
                )
            goal.updateStep(.review, status: .blocked, error: error, at: date)
        } else if (pullRequest.requestedReviewerCount > 0
            || pullRequest.reviewDecision?.caseInsensitiveCompare("REVIEW_REQUIRED") == .orderedSame)
            && pullRequest.approvalCount == 0
            && !isMerged {
            goal.updateStep(
                .review,
                status: .waiting,
                evidence: pullRequest.requestedReviewerCount > 0
                    ? L10n.format("goal.evidence.review_waiting", pullRequest.requestedReviewerCount)
                    : L10n.text("goal.evidence.review_required"),
                at: date
            )
        } else if pullRequest.approvalCount > 0 {
            goal.updateStep(
                .review,
                status: .completed,
                evidence: L10n.format("goal.evidence.review_approved", pullRequest.approvalCount),
                at: date
            )
        } else {
            goal.updateStep(.review, status: .notRequired, at: date)
        }

        reconcileActions(&goal, state: observation.actions, at: date)
        reconcileArtifacts(&goal, state: observation.actions, at: date)

        if isMerged {
            goal.updateStep(
                .merge,
                status: .completed,
                evidence: L10n.format("goal.evidence.merged", pullRequest.number),
                at: date
            )
        } else if pullRequest.isClosed {
            goal.updateStep(.merge, status: .blocked, error: L10n.text("goal.error.pr_closed"), at: date)
        } else if pullRequest.mergeable == false {
            goal.updateStep(.merge, status: .blocked, error: L10n.text("goal.error.pr_not_mergeable"), at: date)
        } else if pullRequest.mergeable == nil {
            goal.updateStep(.merge, status: .waiting, at: date)
        } else {
            goal.updateStep(.merge, status: .pending, at: date)
        }
    }

    private static func reconcileActions(
        _ goal: inout ProjectGoal,
        state: ProjectGoalActionsState,
        at date: Date
    ) {
        switch state {
        case .unavailable:
            goal.updateStep(.actions, status: .blocked, error: L10n.text("goal.error.github_remote"), at: date)
        case .noWorkflows:
            goal.lastActionFailure = nil
            goal.updateStep(.actions, status: .notRequired, at: date)
        case .waiting:
            goal.updateStep(.actions, status: .waiting, at: date)
        case let .running(runNumbers):
            goal.updateStep(
                .actions,
                status: .waiting,
                evidence: runNumbers.map { "#\($0)" }.joined(separator: ", "),
                at: date
            )
        case let .passed(runNumbers, _, _):
            goal.lastActionFailure = nil
            goal.updateStep(
                .actions,
                status: .completed,
                evidence: runNumbers.map { "#\($0)" }.joined(separator: ", "),
                at: date
            )
        case let .failed(failure):
            goal.lastActionFailure = failure
            goal.updateStep(
                .actions,
                status: .blocked,
                evidence: "#\(failure.runNumber) · \(failure.workflowName)",
                error: actionFailureExplanation(failure.conclusion),
                at: date
            )
        }
    }

    private static func reconcileArtifacts(
        _ goal: inout ProjectGoal,
        state: ProjectGoalActionsState,
        at date: Date
    ) {
        switch state {
        case .noWorkflows:
            goal.artifactNames = []
            goal.updateStep(.artifact, status: .notRequired, at: date)
        case let .passed(_, artifacts, true):
            let current = artifacts.filter { !$0.isExpired }
            goal.artifactNames = current.map(\.name)
            if current.isEmpty {
                goal.updateStep(.artifact, status: .notRequired, at: date)
            } else {
                goal.updateStep(
                    .artifact,
                    status: .completed,
                    evidence: current.map(\.name).joined(separator: ", "),
                    at: date
                )
            }
        case .passed(_, _, false):
            goal.updateStep(
                .artifact,
                status: .blocked,
                error: L10n.text("goal.error.artifact_unavailable"),
                at: date
            )
        case .unavailable, .waiting, .running, .failed:
            goal.updateStep(.artifact, status: .pending, at: date)
        }
    }

    private static func record(_ pullRequest: GitHubDeliveryPullRequest, in goal: inout ProjectGoal) {
        goal.pullRequestNumber = pullRequest.number
        goal.pullRequestTitle = pullRequest.title
        goal.pullRequestURL = pullRequest.webURL
        goal.baseBranch = pullRequest.baseBranch
    }

    private static func actionFailureExplanation(_ conclusion: String) -> String {
        switch conclusion.lowercased() {
        case "failure": L10n.text("goal.actions.conclusion.failure")
        case "cancelled": L10n.text("goal.actions.conclusion.cancelled")
        case "timed_out": L10n.text("goal.actions.conclusion.timed_out")
        case "action_required": L10n.text("goal.actions.conclusion.action_required")
        case "startup_failure": L10n.text("goal.actions.conclusion.startup_failure")
        case "stale": L10n.text("goal.actions.conclusion.stale")
        default: L10n.format("goal.actions.conclusion.unknown", conclusion)
        }
    }

    private static func finalize(_ goal: inout ProjectGoal, at date: Date) {
        if let blocked = goal.steps.first(where: { $0.status == .blocked }) {
            goal.status = .blocked
            goal.lastError = blocked.error
        } else if goal.steps.allSatisfy(\.status.isSatisfied) {
            goal.status = .completed
        } else if goal.steps.contains(where: { $0.status == .waiting }) {
            goal.status = .waiting
        } else if goal.steps.contains(where: { $0.status == .running }) {
            goal.status = .running
        } else {
            goal.status = .ready
        }
        goal.updatedAt = date
    }
}
