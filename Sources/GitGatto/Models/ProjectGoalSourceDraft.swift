import Foundation

struct ProjectGoalSourceDraft: Identifiable, Equatable {
    let id = UUID()
    let repositoryPath: String
    let title: String
    let context: String
}

enum ProjectGoalSourceError: LocalizedError {
    case repositoryMismatch
    var errorDescription: String? { L10n.text("goal.source.repository_mismatch") }
}
