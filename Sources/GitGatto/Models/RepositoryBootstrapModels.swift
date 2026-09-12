import Foundation

struct RepositoryBootstrapRequest: Sendable, Equatable, Codable {
    var folder: URL
    var branch = "main"
    var createRemote = true
    var name = ""
    var owner = ""
    var isPrivate = true
    var connectExisting = false
    var pushInitialCommit = true
    var approvedExistingHead: String?
    var authorName = ""
    var authorEmail = ""
}

struct RepositoryBootstrapInspection: Sendable {
    let folder: URL
    let isRepository: Bool
    let head: String?
    var hasHEAD: Bool { head != nil }
    let isEmptyInitialCommit: Bool
    let branch: String?
    let origin: String?
    let authorName: String
    let authorEmail: String

    var canPushInitialCommit: Bool { !hasHEAD || isEmptyInitialCommit }
}

enum RepositoryBootstrapStep: String, CaseIterable, Identifiable, Sendable {
    case agent, check, local, remote, link, push, verify
    var id: String { rawValue }
    var titleKey: String { "repository.create.step.\(rawValue)" }
}

struct RepositoryBootstrapEvent: Sendable {
    enum State: Sendable { case running, complete, skipped }
    let step: RepositoryBootstrapStep
    let state: State
}

struct RepositoryBootstrapResult: Sendable {
    let folder: URL
    let branch: String?
    let remote: GitHubRepository?
    let pushed: Bool
}

enum RepositoryBootstrapError: String, LocalizedError, Sendable {
    case agentAction, folder, nested, name, branch, identity, origin, remoteExists, remoteMismatch, history, changed, busy, verification
    var errorDescription: String? { L10n.text("repository.create.error.\(rawValue)") }
}
