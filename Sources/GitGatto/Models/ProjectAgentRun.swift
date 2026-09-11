import Foundation

struct ProjectAgentRun: Identifiable, Sendable {
    let id: UUID
    let repositoryURL: URL
    let mode: CodexRunMode
    var activity: String?
    var partialResponse = ""
}
