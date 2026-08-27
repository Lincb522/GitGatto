import Foundation
import SwiftUI

enum WorkspaceSection: String, CaseIterable, Identifiable, Sendable, Codable {
    case changes
    case history
    case branches
    case github
    case codex

    var id: String { rawValue }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum GitFileStatus: String, Sendable, Hashable {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case untracked = "?"
    case typeChanged = "T"
    case conflicted = "U"
    case ignored = "!"
    case unmodified = " "

    init(character: Character) {
        self = GitFileStatus(rawValue: String(character)) ?? .conflicted
    }
}

struct WorkingTreeChange: Identifiable, Sendable, Hashable {
    let path: String
    let originalPath: String?
    let indexStatus: GitFileStatus
    let workTreeStatus: GitFileStatus

    var id: String { "\(indexStatus.rawValue)\(workTreeStatus.rawValue):\(path)" }

    var isStaged: Bool {
        indexStatus != .unmodified && indexStatus != .untracked && indexStatus != .ignored
    }

    var primaryStatus: GitFileStatus {
        isStaged ? indexStatus : workTreeStatus
    }
}

struct CommitRecord: Identifiable, Sendable, Hashable {
    let hash: String
    let shortHash: String
    let author: String
    let date: Date
    let subject: String

    var id: String { hash }
}

struct BranchRecord: Identifiable, Sendable, Hashable {
    let name: String
    let shortHash: String
    let upstream: String?
    let isCurrent: Bool

    var id: String { name }
}

struct RepositorySnapshot: Sendable {
    let rootURL: URL
    let branchName: String
    let upstreamName: String?
    let aheadCount: Int
    let behindCount: Int
    let changes: [WorkingTreeChange]
    let commits: [CommitRecord]
    let branches: [BranchRecord]

    var stagedChanges: [WorkingTreeChange] { changes.filter(\.isStaged) }
    var unstagedChanges: [WorkingTreeChange] { changes.filter { !$0.isStaged } }

    var syncState: RepositorySyncState {
        guard upstreamName != nil else { return .noUpstream }
        return switch (aheadCount, behindCount) {
        case (0, 0): .synced
        case let (ahead, 0): .ahead(ahead)
        case let (0, behind): .behind(behind)
        case let (ahead, behind): .diverged(ahead: ahead, behind: behind)
        }
    }
}

struct RepositoryLiveState: Sendable, Equatable {
    let branchName: String
    let upstreamName: String?
    let aheadCount: Int
    let behindCount: Int
    let changes: [WorkingTreeChange]
}

enum RepositorySyncState: Sendable, Equatable {
    case synced
    case ahead(Int)
    case behind(Int)
    case diverged(ahead: Int, behind: Int)
    case noUpstream
}

enum GitIgnoreScope: Sendable, Equatable {
    case file
    case folder(String)
    case fileExtension
}

enum DiffLineKind: Sendable {
    case context
    case addition
    case deletion
    case header
    case hunk
}

struct DiffLine: Identifiable, Sendable {
    let id = UUID()
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let text: String
    let kind: DiffLineKind
}

struct DiffDocument: Sendable {
    let path: String
    let lines: [DiffLine]
}

enum OperationKind: Sendable, Equatable {
    case stage
    case unstage
    case discard
    case ignore
    case commit
    case commitAndPush
    case switchBranch
    case pull
    case push

    var isRemoteSync: Bool {
        self == .pull || self == .push || self == .commitAndPush
    }
}

struct OperationNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

enum CodexRunMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case analyze
    case edit

    var id: String { rawValue }
}

enum CodexAvailabilityState: Sendable, Equatable {
    case checking
    case available
    case unavailable
}

struct CodexAvailability: Sendable, Equatable {
    let state: CodexAvailabilityState
    let version: String?

    static let checking = CodexAvailability(state: .checking, version: nil)
    static let unavailable = CodexAvailability(state: .unavailable, version: nil)
}

struct CodexOperationRecord: Sendable, Equatable, Codable {
    let mode: CodexRunMode
    let commandCount: Int
    let fileChangeCount: Int
    let completedAt: Date
    let events: [CodexOperationEvent]

    init(
        mode: CodexRunMode,
        commandCount: Int,
        fileChangeCount: Int,
        completedAt: Date,
        events: [CodexOperationEvent] = []
    ) {
        self.mode = mode
        self.commandCount = commandCount
        self.fileChangeCount = fileChangeCount
        self.completedAt = completedAt
        self.events = events
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case commandCount
        case fileChangeCount
        case completedAt
        case events
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(CodexRunMode.self, forKey: .mode)
        commandCount = try container.decode(Int.self, forKey: .commandCount)
        fileChangeCount = try container.decode(Int.self, forKey: .fileChangeCount)
        completedAt = try container.decode(Date.self, forKey: .completedAt)
        events = try container.decodeIfPresent([CodexOperationEvent].self, forKey: .events) ?? []
    }
}

struct CodexOperationEvent: Sendable, Equatable, Codable {
    enum Kind: String, Sendable, Codable {
        case command
        case fileChange
    }

    let kind: Kind
    let summary: String
}

struct CodexMessage: Identifiable, Sendable, Equatable, Codable {
    enum Role: String, Sendable, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String
    let operation: CodexOperationRecord?

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        operation: CodexOperationRecord? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.operation = operation
    }
}

struct CodexCommitDraft: Sendable, Equatable {
    let messageID: UUID
    let repositoryURL: URL
    let message: String
}

struct CodexRunResult: Sendable, Equatable {
    let response: String
    let commandCount: Int
    let fileChangeCount: Int
    let events: [CodexOperationEvent]

    init(
        response: String,
        commandCount: Int,
        fileChangeCount: Int,
        events: [CodexOperationEvent] = []
    ) {
        self.response = response
        self.commandCount = commandCount
        self.fileChangeCount = fileChangeCount
        self.events = events
    }
}

enum CodexQuickAction: String, CaseIterable, Identifiable, Sendable {
    case explainChanges
    case reviewStaged
    case draftCommit

    var id: String { rawValue }
}

enum CodexTranslationTarget: String, CaseIterable, Identifiable, Sendable, Hashable, Codable {
    case simplifiedChinese
    case english

    var id: String { rawValue }

    var promptName: String {
        switch self {
        case .simplifiedChinese: "Simplified Chinese"
        case .english: "English"
        }
    }
}

enum GitHubAvailabilityState: Sendable, Equatable {
    case checking
    case available
    case unavailable
}

struct GitHubAvailability: Sendable, Equatable {
    let state: GitHubAvailabilityState
    let version: String?

    static let checking = GitHubAvailability(state: .checking, version: nil)
    static let unavailable = GitHubAvailability(state: .unavailable, version: nil)
}

struct GitHubAccount: Sendable, Equatable {
    let login: String
    let name: String?
    let webURL: URL
}

enum GitHubCollection: String, CaseIterable, Identifiable, Sendable {
    case account
    case recommendations

    var id: String { rawValue }
}

enum GitHubSearchScope: String, CaseIterable, Identifiable, Sendable {
    case projects
    case developers

    var id: String { rawValue }
}

struct GitHubDeveloperSummary: Identifiable, Sendable, Hashable {
    let login: String
    let avatarURL: URL
    let webURL: URL
    let accountType: String

    var id: String { login }
}

struct GitHubDeveloperProfile: Identifiable, Sendable, Hashable {
    let login: String
    let name: String?
    let bio: String?
    let avatarURL: URL
    let webURL: URL
    let accountType: String
    let company: String?
    let location: String?
    let followers: Int
    let publicRepositories: Int

    var id: String { login }
}

struct GitHubRepository: Identifiable, Sendable, Hashable {
    let fullName: String
    let name: String
    let owner: String
    let description: String?
    let webURL: URL
    let stars: Int
    let forks: Int
    let openIssues: Int
    let language: String?
    let updatedAt: Date
    let isPrivate: Bool
    let defaultBranch: String

    var id: String { fullName }
}

struct GitHubPullRequest: Identifiable, Sendable, Hashable {
    let number: Int
    let title: String
    let author: String
    let body: String?
    let webURL: URL
    let isDraft: Bool
    let headBranch: String
    let baseBranch: String
    let updatedAt: Date

    var id: Int { number }
}

struct GitHubPullRequestContext: Sendable {
    let repositoryName: String
    let pullRequest: GitHubPullRequest
    let diff: String
}

enum GitHubProjectDetailTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case code
    case pullRequests

    var id: String { rawValue }
}

struct GitHubReadmeDocument: Sendable, Equatable {
    let path: String
    let html: String
    let linkBaseURL: URL
    let linkRootURL: URL
    let assetBaseURL: URL
    let assetRootURL: URL

    func replacingHTML(with html: String) -> GitHubReadmeDocument {
        GitHubReadmeDocument(
            path: path,
            html: html,
            linkBaseURL: linkBaseURL,
            linkRootURL: linkRootURL,
            assetBaseURL: assetBaseURL,
            assetRootURL: assetRootURL
        )
    }
}

struct GitHubContentItem: Identifiable, Sendable, Hashable {
    enum Kind: String, Sendable {
        case directory
        case file
        case symlink
        case submodule
    }

    let name: String
    let path: String
    let kind: Kind
    let size: Int
    let webURL: URL?

    var id: String { path }
}

struct GitHubFileDocument: Sendable, Equatable {
    let name: String
    let path: String
    let text: String?
    let size: Int
    let webURL: URL?
}

enum GitHubOperationKind: Sendable, Equatable {
    case clone
    case fork
    case publishReply
}
