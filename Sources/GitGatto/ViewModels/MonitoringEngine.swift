import Combine
import Foundation

@MainActor
final class MonitoringEngine: ObservableObject {
    @Published private(set) var isEnabled = true
    @Published private(set) var statusBarEnabled = true
    @Published private(set) var repositories: [URL] = []
    @Published private(set) var selectedRepositoryURL: URL?
    @Published private(set) var channels: [MonitoringChannelSnapshot]
    @Published private(set) var dailyActivity: [RepositoryDailyActivity] = []
    @Published private(set) var activityError: String?
    @Published private(set) var lastActivityAt: Date?

    private let environment: @MainActor () -> MonitoringEnvironment
    private let now: @MainActor () -> Date
    private var repositoryPolicies: [String: RepositoryMonitoringPolicy] = [:]
    private var workspaceRepository: URL?
    private var lastChangeByRepository: [URL: Date] = [:]
    private var pendingReferenceReads: [URL: UUID] = [:]
    private let backgroundService: BackgroundMonitoringService
    private let activityScheduler = RepositoryEventScheduler()
    private var pendingActivityRepositories = Set<URL>()
    private var pendingRecordedRepositories = Set<URL>()
    private var activityByRepository: [URL: [RepositoryDailyActivity]] = [:]

    init(backgroundService: BackgroundMonitoringService = BackgroundMonitoringService(),
        environment: @escaping @MainActor () -> MonitoringEnvironment = MonitoringEnvironment.current,
        now: @escaping @MainActor () -> Date = Date.init) {
        self.environment = environment
        self.now = now
        self.backgroundService = backgroundService
        channels = MonitoringCategory.allCases.map {
            MonitoringChannelSnapshot(
                category: $0,
                isEnabled: true,
                state: .healthy,
                lastUpdatedAt: nil,
                detail: nil
            )
        }
    }

    var isActivityRefreshPending: Bool { !activityScheduler.isIdle }

    func setWorkspaceRepository(_ repository: URL?) {
        workspaceRepository = repository?.standardizedFileURL
    }

    func budget(for repository: URL?) -> RepositoryMonitoringBudget {
        let repository = repository?.standardizedFileURL
        let recent = repository.flatMap { lastChangeByRepository[$0] }.map { now().timeIntervalSince($0) < 90 } ?? false
        return RepositoryMonitoringBudget(environment: environment(),
            isWorkspaceRepository: repository != nil && repository == workspaceRepository, recentlyChanged: recent,
            policy: repository.flatMap { repositoryPolicies[$0.path] } ?? .automatic)
    }

    var overallState: MonitoringOverallState {
        Self.overallState(isEnabled: isEnabled, channels: channels)
    }

    var overallStatePublisher: AnyPublisher<MonitoringOverallState, Never> {
        $isEnabled.combineLatest($channels)
            .map { Self.overallState(isEnabled: $0, channels: $1) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private static func overallState(
        isEnabled: Bool,
        channels: [MonitoringChannelSnapshot]
    ) -> MonitoringOverallState {
        guard isEnabled, channels.contains(where: \.isEnabled) else { return .paused }
        if channels.contains(where: { $0.isEnabled && $0.state == .attention }) {
            return .attention
        }
        if channels.contains(where: { $0.isEnabled && $0.state == .monitoring }) {
            return .monitoring
        }
        return .healthy
    }

    var activeChannelCount: Int {
        guard isEnabled else { return 0 }
        return channels.count(where: \.isEnabled)
    }

    var repositoryCount: Int { repositories.count }

    var todayActivity: RepositoryDailyActivity? {
        guard let last = dailyActivity.last(where: { Calendar.current.isDateInToday($0.date) }) else {
            return nil
        }
        return last
    }

    var selectedRepositoryName: String? {
        selectedRepositoryURL?.lastPathComponent
    }

    func configure(
        preferences: AppPreferences,
        repositories: [URL]
    ) {
        repositoryPolicies = preferences.repositoryMonitoringPolicies
        if isEnabled != preferences.monitoringEngineEnabled {
            isEnabled = preferences.monitoringEngineEnabled
        }
        if statusBarEnabled != preferences.statusBarMonitoringEnabled {
            statusBarEnabled = preferences.statusBarMonitoringEnabled
        }
        let normalizedRepositories = Array(
            Dictionary(
                repositories.map { ($0.standardizedFileURL.path, $0.standardizedFileURL) },
                uniquingKeysWith: { first, _ in first }
            ).values
        ).sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        var activityScopeChanged = false
        if self.repositories != normalizedRepositories {
            self.repositories = normalizedRepositories
            lastChangeByRepository = lastChangeByRepository.filter { normalizedRepositories.contains($0.key) }
            pendingReferenceReads = pendingReferenceReads.filter { normalizedRepositories.contains($0.key) }
            activityScopeChanged = true
        }
        if let selectedRepositoryURL,
           !normalizedRepositories.contains(selectedRepositoryURL)
        {
            self.selectedRepositoryURL = nil
            activityScopeChanged = true
        }
        let enabledCategories: [MonitoringCategory: Bool] = [
            .workingTree: preferences.liveRefreshEnabled,
            .remote: preferences.remoteRefreshEnabled,
            .repositoryProtection: preferences.repositoryBackupEnabled,
            .githubActions: preferences.githubActionsMonitoringEnabled,
            .projectGoals: preferences.projectGoalMonitoringEnabled,
        ]
        var configuredChannels = channels
        for category in MonitoringCategory.allCases {
            guard let index = configuredChannels.firstIndex(where: { $0.category == category }) else {
                continue
            }
            let enabled = preferences.monitoringEngineEnabled && (enabledCategories[category] ?? true)
            configuredChannels[index].isEnabled = enabled
            if !enabled {
                configuredChannels[index].state = .paused
                configuredChannels[index].detail = nil
            } else if configuredChannels[index].state == .paused {
                configuredChannels[index].state = .healthy
            }
        }
        if channels != configuredChannels {
            channels = configuredChannels
        }

        if activityScopeChanged {
            refreshActivity()
        }
    }

    func selectRepository(_ repositoryURL: URL?) {
        let normalizedSelection = repositoryURL?.standardizedFileURL
        if let normalizedSelection, !repositories.contains(normalizedSelection) { return }
        guard selectedRepositoryURL != normalizedSelection else { return }
        selectedRepositoryURL = normalizedSelection
        dailyActivity = []
        activityError = nil
        refreshActivity()
    }

    func markMonitoring(_ category: MonitoringCategory, detail: String? = nil) {
        guard isChannelEnabled(category) else { return }
        update(category) { channel in
            channel.state = .monitoring
            channel.detail = detail
            channel.lastUpdatedAt = Date()
        }
    }

    func markHealthy(_ category: MonitoringCategory, detail: String? = nil) {
        guard isChannelEnabled(category) else { return }
        update(category) { channel in
            channel.state = .healthy
            channel.detail = detail
            channel.lastUpdatedAt = Date()
        }
    }

    func markAttention(_ category: MonitoringCategory, error: String) {
        guard isChannelEnabled(category) else { return }
        update(category) { channel in
            channel.state = .attention
            channel.detail = error
            channel.lastUpdatedAt = Date()
        }
    }

    func recordRepositoryChange(at repositoryURL: URL, event: RepositoryChangeEvent = .unknown) {
        guard isEnabled else { return }
        let repository = repositoryURL.standardizedFileURL
        lastActivityAt = now()
        lastChangeByRepository[repository] = now()
        if event.referencesChanged { pendingReferenceReads[repository] = UUID() }
        pendingRecordedRepositories.insert(repository)
        enqueueActivity(for: [repository])
    }

    func refreshActivity() {
        let targets = selectedRepositoryURL.map { [$0] } ?? repositories
        guard !targets.isEmpty else {
            dailyActivity = []
            activityError = nil
            return
        }
        activityByRepository = activityByRepository.filter { repositories.contains($0.key) }
        for repository in targets { pendingReferenceReads[repository] = UUID() }
        enqueueActivity(for: targets, immediate: true)
    }

    private func enqueueActivity(for repositories: [URL], immediate: Bool = false) {
        pendingActivityRepositories.formUnion(repositories)
        let delay = immediate ? 0.5 : (repositories.map { budget(for: $0).activityDelay }.min() ?? 2)
        activityScheduler.schedule(key: "activity", delay: .seconds(delay)) { [weak self] in
            guard let self else { return }
            let targets = self.pendingActivityRepositories.sorted { $0.path < $1.path }
            self.pendingActivityRepositories.removeAll()
            do {
                // Only changed repositories are read, and only one history reader runs at a time.
                for repository in targets where self.repositories.contains(repository) {
                    try Task.checkCancellation()
                    if self.pendingRecordedRepositories.remove(repository) != nil {
                        try await self.backgroundService.recordRepositoryChange(at: repository)
                    }
                    let referenceRead = self.pendingReferenceReads[repository]
                    self.activityByRepository[repository] = try await self.backgroundService.dailyActivity(
                        for: repository, refreshHistory: referenceRead != nil)
                    if self.pendingReferenceReads[repository] == referenceRead { self.pendingReferenceReads[repository] = nil }
                }
                try Task.checkCancellation()
                let displayed = self.selectedRepositoryURL.map { [$0] } ?? self.repositories
                self.dailyActivity = Self.mergedActivity(displayed.compactMap { self.activityByRepository[$0] })
                self.activityError = nil
            } catch is CancellationError {
                return
            } catch {
                self.activityError = error.localizedDescription
            }
        }
    }

    private static func mergedActivity(
        _ activitySets: [[RepositoryDailyActivity]]
    ) -> [RepositoryDailyActivity] {
        var merged: [Date: RepositoryDailyActivity] = [:]
        for activity in activitySets {
            for day in activity {
                let date = Calendar.current.startOfDay(for: day.date)
                var total = merged[date] ?? RepositoryDailyActivity(
                    date: date,
                    commitCount: 0,
                    monitoredChangeCount: 0
                )
                total.commitCount += day.commitCount
                total.monitoredChangeCount += day.monitoredChangeCount
                merged[date] = total
            }
        }
        return merged.values.sorted { $0.date < $1.date }
    }

    func isChannelEnabled(_ category: MonitoringCategory) -> Bool {
        isEnabled && channels.first(where: { $0.category == category })?.isEnabled == true
    }

    private func update(
        _ category: MonitoringCategory,
        mutation: (inout MonitoringChannelSnapshot) -> Void
    ) {
        guard let index = channels.firstIndex(where: { $0.category == category }) else { return }
        mutation(&channels[index])
    }
}
