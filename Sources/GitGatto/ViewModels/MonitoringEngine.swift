import Combine
import Foundation

@MainActor
final class MonitoringEngine: ObservableObject {
    @Published private(set) var isEnabled = true
    @Published private(set) var statusBarEnabled = true
    @Published private(set) var repositoryCount = 0
    @Published private(set) var selectedRepositoryURL: URL?
    @Published private(set) var channels: [MonitoringChannelSnapshot]
    @Published private(set) var dailyActivity: [RepositoryDailyActivity] = []
    @Published private(set) var activityError: String?
    @Published private(set) var lastActivityAt: Date?

    private let backgroundService: BackgroundMonitoringService
    private var activityTask: Task<Void, Never>?

    init(backgroundService: BackgroundMonitoringService = BackgroundMonitoringService()) {
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

    deinit {
        activityTask?.cancel()
    }

    var overallState: MonitoringOverallState {
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
        repositories: [URL],
        selectedRepositoryURL: URL?
    ) {
        isEnabled = preferences.monitoringEngineEnabled
        statusBarEnabled = preferences.statusBarMonitoringEnabled
        repositoryCount = repositories.count
        let enabledCategories: [MonitoringCategory: Bool] = [
            .workingTree: preferences.liveRefreshEnabled,
            .remote: preferences.remoteRefreshEnabled,
            .repositoryProtection: preferences.repositoryBackupEnabled,
            .githubActions: preferences.githubActionsMonitoringEnabled,
            .projectGoals: preferences.projectGoalMonitoringEnabled,
        ]
        for category in MonitoringCategory.allCases {
            update(category) { channel in
                let enabled = preferences.monitoringEngineEnabled && (enabledCategories[category] ?? true)
                channel.isEnabled = enabled
                if !enabled {
                    channel.state = .paused
                    channel.detail = nil
                } else if channel.state == .paused {
                    channel.state = .healthy
                }
            }
        }

        let normalizedSelection = selectedRepositoryURL?.standardizedFileURL
        if self.selectedRepositoryURL != normalizedSelection {
            self.selectedRepositoryURL = normalizedSelection
            for category in [MonitoringCategory.workingTree, .remote] where isChannelEnabled(category) {
                update(category) { channel in
                    channel.state = .healthy
                    channel.detail = nil
                    channel.lastUpdatedAt = nil
                }
            }
            dailyActivity = []
            activityError = nil
            refreshActivity()
        }
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

    func recordRepositoryChange(at repositoryURL: URL) {
        guard isEnabled else { return }
        let repository = repositoryURL.standardizedFileURL
        lastActivityAt = Date()
        Task { [weak self, backgroundService] in
            do {
                let count = try await backgroundService.recordRepositoryChange(at: repository)
                guard let self,
                      self.selectedRepositoryURL == repository,
                      let index = self.dailyActivity.lastIndex(where: {
                          Calendar.current.isDateInToday($0.date)
                      }) else { return }
                self.dailyActivity[index].monitoredChangeCount = count
                self.activityError = nil
            } catch is CancellationError {
                return
            } catch {
                self?.activityError = error.localizedDescription
            }
        }
    }

    func refreshActivity() {
        activityTask?.cancel()
        guard let repository = selectedRepositoryURL else {
            dailyActivity = []
            return
        }
        activityTask = Task { [weak self, backgroundService] in
            do {
                let activity = try await backgroundService.dailyActivity(for: repository)
                try Task.checkCancellation()
                guard let self, self.selectedRepositoryURL == repository else { return }
                self.dailyActivity = activity
                self.activityError = nil
            } catch is CancellationError {
                return
            } catch {
                self?.activityError = error.localizedDescription
            }
        }
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
