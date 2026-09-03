import Foundation

enum MonitoringCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case workingTree
    case remote
    case repositoryProtection
    case githubActions
    case projectGoals

    var id: String { rawValue }

    var titleKey: String { "monitoring.channel.\(rawValue)" }
    var descriptionKey: String { "monitoring.channel.\(rawValue).body" }

    var iconName: String {
        switch self {
        case .workingTree: "square.stack.3d.up"
        case .remote: "arrow.triangle.2.circlepath"
        case .repositoryProtection: "checkmark.shield"
        case .githubActions: "play.circle"
        case .projectGoals: "record.circle"
        }
    }
}

enum MonitoringChannelState: String, Codable, Sendable {
    case paused
    case healthy
    case monitoring
    case attention

    var localizationKey: String { "monitoring.state.\(rawValue)" }
}

struct MonitoringChannelSnapshot: Identifiable, Equatable, Sendable {
    let category: MonitoringCategory
    var isEnabled: Bool
    var state: MonitoringChannelState
    var lastUpdatedAt: Date?
    var detail: String?

    var id: MonitoringCategory { category }
}

enum MonitoringOverallState: String, Sendable {
    case paused
    case healthy
    case monitoring
    case attention

    var localizationKey: String { "monitoring.overall.\(rawValue)" }
}

struct RepositoryDailyActivity: Identifiable, Codable, Equatable, Sendable {
    let date: Date
    var commitCount: Int
    var monitoredChangeCount: Int

    var id: Date { date }
    var totalCount: Int { commitCount + monitoredChangeCount }
}
