import Combine

extension WorkspaceViewModel {
    var monitoringStatusSummary: MonitoringStatusSummary {
        MonitoringStatusSummary(repositories: monitoringEngine.repositories,
            selectedRepository: monitoringEngine.selectedRepositoryURL, snapshot: snapshot,
            backgroundStates: backgroundRepositoryStates, state: monitoringEngine.overallState,
            workingTreeEnabled: monitoringEngine.channels.contains { $0.category == .workingTree && $0.isEnabled },
            remoteEnabled: monitoringEngine.channels.contains { $0.category == .remote && $0.isEnabled })
    }

    // Only visible repository values invalidate the collapsed item, not log lines,
    // channel timestamps, activity refreshes, or unrelated workspace operations.
    var monitoringStatusPublisher: AnyPublisher<MonitoringStatusSummary, Never> {
        let scope = monitoringEngine.$repositories.combineLatest(monitoringEngine.$selectedRepositoryURL)
        let enabled = monitoringEngine.$channels
            .map { Set($0.filter(\.isEnabled).map(\.category)) }
            .removeDuplicates()
        let state = monitoringEngine.overallStatePublisher.combineLatest(enabled)
        return $snapshot.combineLatest($backgroundRepositoryStates, scope, state)
            .map { snapshot, background, scope, state in
                MonitoringStatusSummary(repositories: scope.0, selectedRepository: scope.1,
                    snapshot: snapshot, backgroundStates: background, state: state.0,
                    workingTreeEnabled: state.1.contains(.workingTree),
                    remoteEnabled: state.1.contains(.remote))
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
