import Foundation

struct MonitoringRepositoryStatus: Identifiable, Equatable {
    let repository: URL
    let branch: String?
    let changed: Int?
    let staged: Int?
    let ahead: Int?
    let behind: Int?

    var id: String { repository.path }

    init(repository: URL, state: RepositoryLiveState?) {
        self.repository = repository.standardizedFileURL
        branch = state?.branchName
        changed = state.map { Set($0.changes.map(\.path)).count }
        staged = state.map { Set($0.changes.filter(\.isStaged).map(\.path)).count }
        ahead = state?.upstreamName == nil ? nil : state?.aheadCount
        behind = state?.upstreamName == nil ? nil : state?.behindCount
    }
}

struct MonitoringStatusSummary: Equatable {
    let repositories: [MonitoringRepositoryStatus]
    let selectedRepository: URL?
    let state: MonitoringOverallState
    let workingTreeEnabled: Bool
    let remoteEnabled: Bool

    init(repositories: [URL], selectedRepository: URL?, snapshot: RepositorySnapshot?,
         backgroundStates: [String: RepositoryLiveState], state: MonitoringOverallState,
         workingTreeEnabled: Bool = true, remoteEnabled: Bool = true) {
        self.selectedRepository = selectedRepository?.standardizedFileURL
        self.state = state
        self.workingTreeEnabled = workingTreeEnabled
        self.remoteEnabled = remoteEnabled
        var paths = Set<String>()
        self.repositories = repositories.map(\.standardizedFileURL).filter {
            paths.insert($0.path).inserted && (selectedRepository == nil || $0 == selectedRepository?.standardizedFileURL)
        }.map { repository in
            let live: RepositoryLiveState?
            if let snapshot, snapshot.rootURL.standardizedFileURL == repository {
                live = RepositoryLiveState(branchName: snapshot.branchName, upstreamName: snapshot.upstreamName,
                    aheadCount: snapshot.aheadCount, behindCount: snapshot.behindCount, changes: snapshot.changes)
            } else { live = backgroundStates[repository.path] }
            return MonitoringRepositoryStatus(repository: repository, state: live)
        }
    }

    var knownCount: Int { repositories.count { $0.changed != nil } }
    var isComplete: Bool { !repositories.isEmpty && knownCount == repositories.count }
    var changed: Int? {
        guard workingTreeEnabled, knownCount > 0 else { return nil }
        return repositories.compactMap(\.changed).reduce(0, +)
    }
    var changedValue: String {
        guard let changed else { return "—" }
        return changed.formatted(.number.locale(L10n.locale)) + (isComplete ? "" : "+")
    }
    var coverageText: String {
        guard workingTreeEnabled else { return L10n.text("monitoring.status.worktree_paused") }
        return L10n.format("monitoring.status.coverage", knownCount, repositories.count)
    }
    var compactTitle: String {
        guard !repositories.isEmpty else { return L10n.text("monitoring.status.no_repositories") }
        let scope: String
        if let name = selectedRepository?.lastPathComponent {
            scope = name.count > 12 ? String(name.prefix(11)) + "…" : name
        } else { scope = L10n.format("monitoring.status.scope", repositories.count) }
        let detail: String
        if state == .paused { detail = L10n.text("monitoring.overall.paused") }
        else if !workingTreeEnabled { detail = L10n.text("monitoring.status.worktree_paused") }
        else if changed == nil { detail = L10n.text("monitoring.status.pending") }
        else if changed == 0 && isComplete { detail = L10n.text("monitoring.status.clean") }
        else { detail = L10n.format("monitoring.status.changes", changedValue) }
        return scope + " · " + detail + (state == .attention ? " · !" : "")
    }
    var accessibilityDescription: String {
        let scope = selectedRepository?.lastPathComponent ?? L10n.text("monitoring.repository.all")
        let status = state == .healthy ? "monitoring.overall.monitoring" : state.localizationKey
        return ["GitGatto", scope, compactTitle, coverageText, L10n.text(status)].joined(separator: " · ")
    }
}
