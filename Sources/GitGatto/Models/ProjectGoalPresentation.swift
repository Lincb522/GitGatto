import Foundation

enum ProjectGoalListFilter: String, CaseIterable, Identifiable {
    case all, active, history
    var id: String { rawValue }

    func includes(_ goal: ProjectGoal) -> Bool {
        switch self {
        case .all: true
        case .active: !goal.status.isTerminal
        case .history: goal.status.isTerminal
        }
    }
}

enum ProjectGoalAction: String {
    case continueDelivery, repair, prepareRelease, publish, install, merge, refresh

    var titleKey: String {
        switch self {
        case .continueDelivery: "goal.action.continue"
        case .repair: "goal.action.agent_repair"
        case .prepareRelease: "goal.action.prepare_release"
        case .publish: "goal.action.publish_release"
        case .install: "goal.action.install_release"
        case .merge: "goal.action.merge"
        case .refresh: "goal.action.refresh"
        }
    }

    var requiresAgent: Bool { self == .repair || self == .prepareRelease }
}

extension ProjectGoalKind {
    static let templates: [Self] = [.deliverChanges, .githubDelivery, .completeRelease, .custom]

    var titleKey: String {
        switch self {
        case .deliverChanges: "goal.delivery.title"
        case .githubDelivery: "goal.github_delivery.title"
        case .completeRelease: "goal.complete_release.title"
        case .custom: "goal.custom.title"
        }
    }
}

extension ProjectGoal {
    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        if !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return commitMessage }
        return L10n.text(kind.titleKey)
    }

    var satisfiedStepCount: Int { steps.filter(\.status.isSatisfied).count }
    var canEditCommitMessage: Bool { !status.isTerminal && targetHeadSHA == nil }

    var nextAction: ProjectGoalAction? {
        guard !status.isTerminal, status != .running else { return nil }
        if lastActionFailure != nil, monitorsRemoteState { return .repair }
        let preparation: Set<ProjectGoalStepKind> = [.readme, .translation, .version, .changelog, .releasePipeline]
        if usesReleaseFlow, steps.contains(where: { preparation.contains($0.kind) && $0.status == .blocked }) {
            return .prepareRelease
        }
        if nextStep == .localVerification { return .continueDelivery }
        guard let next = nextStep, step(next)?.status == .pending, status != .waiting else { return .refresh }
        switch next {
        case .stageChanges, .commit, .push, .pullRequest: return .continueDelivery
        case .releaseTag: return .publish
        case .localApplication:
            return [.githubRelease, .dmg, .updateFeed].allSatisfy { step($0)?.status == .completed } ? .install : .refresh
        case .merge: return pullRequestNumber != nil ? .merge : .refresh
        default: return .refresh
        }
    }
}

enum ProjectGoalPresentation {
    static func primaryGoal(_ source: [ProjectGoal], selectedID: UUID?) -> ProjectGoal? {
        let ordered = goals(source, filter: .all, query: "")
        return ordered.first { !$0.status.isTerminal }
            ?? ordered.first { $0.id == selectedID }
            ?? ordered.first
    }

    static func goals(_ source: [ProjectGoal], filter: ProjectGoalListFilter, query: String) -> [ProjectGoal] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return source.filter { goal in
            filter.includes(goal) && (query.isEmpty || [goal.displayTitle, goal.branchName, goal.intent ?? "", goal.remoteFullName ?? ""]
                .contains { $0.localizedStandardContains(query) })
        }.sorted {
            if $0.status.isTerminal != $1.status.isTerminal { return !$0.status.isTerminal }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    // An observation belongs to the exact revision it read, not just to a row index.
    static func acceptsObservation(of requested: ProjectGoal, current: ProjectGoal?) -> Bool {
        current == requested && current?.status != .cancelled
    }
}

enum ProjectGoalPhase: String, CaseIterable, Identifiable {
    case prepare, submit, verify, deliver, install
    var id: String { rawValue }

    static func phase(for step: ProjectGoalStepKind) -> Self {
        switch step {
        case .readme, .translation, .version, .changelog, .releasePipeline: .prepare
        case .localVerification: .prepare
        case .stageChanges, .commit, .push: .submit
        case .pullRequest, .review, .actions, .artifact: .verify
        case .merge, .releaseTag, .githubRelease, .dmg, .updateFeed: .deliver
        case .localApplication: .install
        }
    }
}

extension ProjectGoal {
    var phases: [ProjectGoalPhase] {
        ProjectGoalPhase.allCases.filter { phase in steps.contains { ProjectGoalPhase.phase(for: $0.kind) == phase } }
    }

    func phaseIsComplete(_ phase: ProjectGoalPhase) -> Bool {
        let members = steps.filter { ProjectGoalPhase.phase(for: $0.kind) == phase }
        return !members.isEmpty && members.allSatisfy(\.status.isSatisfied)
    }
}

struct ProjectGoalPlanningIdentity: Equatable {
    let repositoryPath: String
    let branch: String
    let head: String?

    init(_ snapshot: RepositorySnapshot) {
        repositoryPath = snapshot.rootURL.standardizedFileURL.path
        branch = snapshot.branchName
        head = snapshot.commits.first?.hash
    }
}
