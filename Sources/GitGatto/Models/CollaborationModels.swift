import Foundation

enum RepositoryBatchOperation: String, Sendable, CaseIterable, Identifiable {
    case fetch
    case pull
    case push

    var id: String { rawValue }
}

enum RepositorySyncHealth: String, Sendable, Equatable {
    case clean
    case changed
    case ahead
    case behind
    case diverged
    case conflicted
    case noUpstream
    case unavailable
}

struct RepositorySyncStatus: Identifiable, Sendable, Equatable {
    let repositoryURL: URL
    let branch: String
    let upstream: String?
    let hasRemote: Bool
    let aheadCount: Int
    let behindCount: Int
    let changedFileCount: Int
    let conflictCount: Int
    let lastCommitAt: Date?
    let errorMessage: String?

    var id: String { repositoryURL.standardizedFileURL.path }
    var name: String { repositoryURL.lastPathComponent }

    var health: RepositorySyncHealth {
        if errorMessage != nil { return .unavailable }
        if conflictCount > 0 { return .conflicted }
        if upstream == nil { return .noUpstream }
        if aheadCount > 0, behindCount > 0 { return .diverged }
        if behindCount > 0 { return .behind }
        if aheadCount > 0 { return .ahead }
        if changedFileCount > 0 { return .changed }
        return .clean
    }

    func supports(_ operation: RepositoryBatchOperation) -> Bool {
        guard errorMessage == nil else { return false }
        switch operation {
        case .fetch:
            return hasRemote
        case .pull:
            return upstream != nil && behindCount > 0 && aheadCount == 0
                && changedFileCount == 0 && conflictCount == 0
        case .push:
            return upstream != nil && aheadCount > 0 && conflictCount == 0
        }
    }

    static func unavailable(repositoryURL: URL, message: String) -> RepositorySyncStatus {
        RepositorySyncStatus(
            repositoryURL: repositoryURL,
            branch: "",
            upstream: nil,
            hasRemote: false,
            aheadCount: 0,
            behindCount: 0,
            changedFileCount: 0,
            conflictCount: 0,
            lastCommitAt: nil,
            errorMessage: message
        )
    }
}

struct RepositoryBatchResult: Identifiable, Sendable, Equatable {
    let repositoryURL: URL
    let operation: RepositoryBatchOperation
    let succeeded: Bool
    let message: String?

    var id: String { "\(operation.rawValue):\(repositoryURL.standardizedFileURL.path)" }
}

enum GitHubWorkspaceMode: String, CaseIterable, Identifiable, Sendable {
    case repositories
    case synchronization
    case inbox
    case issues

    var id: String { rawValue }
}

enum GitHubInboxCategory: String, CaseIterable, Identifiable, Sendable, Hashable {
    case reviewRequested
    case authored
    case changesRequested
    case mentioned
    case actionsFailed
    case mergeable
    case conflicted
    case release

    var id: String { rawValue }
}

enum GitHubInboxSubjectKind: String, Sendable, Equatable {
    case pullRequest
    case issue
    case action
    case release
    case discussion
    case other
}

struct GitHubInboxItem: Identifiable, Sendable, Equatable {
    let id: String
    let repositoryName: String
    let number: Int?
    let title: String
    let author: String?
    let webURL: URL
    let updatedAt: Date
    let subjectKind: GitHubInboxSubjectKind
    let categories: Set<GitHubInboxCategory>
    let isDraft: Bool

    func merging(categories additionalCategories: Set<GitHubInboxCategory>) -> GitHubInboxItem {
        GitHubInboxItem(
            id: id,
            repositoryName: repositoryName,
            number: number,
            title: title,
            author: author,
            webURL: webURL,
            updatedAt: updatedAt,
            subjectKind: subjectKind,
            categories: categories.union(additionalCategories),
            isDraft: isDraft
        )
    }
}

enum GitHubIssueState: String, CaseIterable, Identifiable, Sendable {
    case open
    case closed
    case all

    var id: String { rawValue }
}

struct GitHubIssueLabel: Identifiable, Sendable, Hashable {
    let name: String
    let colorHex: String

    var id: String { name }
}

struct GitHubIssueMilestone: Identifiable, Sendable, Hashable {
    let number: Int
    let title: String

    var id: Int { number }
}

struct GitHubIssue: Identifiable, Sendable, Hashable {
    let number: Int
    let title: String
    let body: String?
    let author: String
    let state: GitHubIssueState
    let webURL: URL
    let labels: [GitHubIssueLabel]
    let assignees: [String]
    let milestone: GitHubIssueMilestone?
    let commentCount: Int
    let createdAt: Date
    let updatedAt: Date

    var id: Int { number }
}

struct GitHubIssueComment: Identifiable, Sendable, Equatable {
    let id: Int64
    let author: String
    let body: String
    let createdAt: Date
    let updatedAt: Date
}

struct GitHubIssueReplyContext: Sendable, Equatable {
    let repositoryName: String
    let issue: GitHubIssue
    let comments: [GitHubIssueComment]
}

struct GitHubIssueDraft: Sendable, Equatable {
    var title = ""
    var body = ""
    var labels: [String] = []
    var assignees: [String] = []
    var milestoneNumber: Int?
}

struct CommitSearchQuery: Sendable, Equatable {
    var hash = ""
    var message = ""
    var author = ""
    var path = ""
    var revision = "--all"
    var changedText = ""
    var fileExtension = ""
    var since: Date?
    var until: Date?
    var mergesOnly = false

    var isEmpty: Bool {
        hash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && changedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && since == nil && until == nil && !mergesOnly
            && revision.trimmingCharacters(in: .whitespacesAndNewlines) == "--all"
    }
}
