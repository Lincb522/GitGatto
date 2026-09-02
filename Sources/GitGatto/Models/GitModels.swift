import Foundation
import NaturalLanguage
import SwiftUI

enum WorkspaceSection: String, CaseIterable, Identifiable, Sendable, Codable {
    case changes
    case stash
    case history
    case timeMachine
    case branches
    case worktrees
    case diagnostics
    case regression
    case github
    case marketplace
    case goals
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

    func stagingPreview(stages: Bool) -> WorkingTreeChange {
        if stages {
            return WorkingTreeChange(
                path: path,
                originalPath: originalPath,
                indexStatus: workTreeStatus == .untracked ? .added : workTreeStatus,
                workTreeStatus: .unmodified
            )
        }

        let previewWorkTreeStatus: GitFileStatus
        if workTreeStatus != .unmodified {
            previewWorkTreeStatus = workTreeStatus
        } else if indexStatus == .added {
            previewWorkTreeStatus = .untracked
        } else {
            previewWorkTreeStatus = indexStatus
        }
        return WorkingTreeChange(
            path: path,
            originalPath: originalPath,
            indexStatus: .unmodified,
            workTreeStatus: previewWorkTreeStatus
        )
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

struct CommitGraphNode: Identifiable, Sendable, Equatable {
    let hash: String
    let shortHash: String
    let parentHashes: [String]
    let references: [String]
    let author: String
    let date: Date
    let subject: String
    let lane: Int

    var id: String { hash }

    var commit: CommitRecord {
        CommitRecord(
            hash: hash,
            shortHash: shortHash,
            author: author,
            date: date,
            subject: subject
        )
    }
}

struct CommitGraph: Sendable, Equatable {
    let nodes: [CommitGraphNode]
    let laneCount: Int

    static let empty = CommitGraph(nodes: [], laneCount: 0)
}

struct BranchRecord: Identifiable, Sendable, Hashable {
    let name: String
    let shortHash: String
    let upstream: String?
    let isCurrent: Bool

    var id: String { name }
}

struct RepositorySnapshot: Sendable, Equatable {
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

struct CommitDraftEvidence: Sendable, Equatable {
    let stagedDiff: String
    let automaticallyStagedPaths: [String]
    let liveState: RepositoryLiveState?
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
    case merge
    case rebase
    case resolveConflict
    case continueConflictOperation
    case skipConflictOperation
    case abortConflictOperation
    case stashSave
    case stashApply
    case stashPop
    case stashDrop

    var isRemoteSync: Bool {
        self == .pull || self == .push || self == .commitAndPush
    }
}

enum RepositoryOperationKind: String, Sendable, Equatable {
    case merge
    case rebase
    case cherryPick
    case revert
    case unknown

    var supportsSkip: Bool {
        self == .rebase || self == .cherryPick || self == .revert
    }

    var supportsAbort: Bool {
        self != .unknown
    }
}

struct RepositoryOperationProgress: Sendable, Equatable {
    let current: Int
    let total: Int
}

struct RepositoryOperationState: Sendable, Equatable {
    let kind: RepositoryOperationKind
    let conflictedPaths: [String]
    let progress: RepositoryOperationProgress?

    var canContinue: Bool { conflictedPaths.isEmpty && kind != .unknown }
}

enum ConflictSide: Sendable, Equatable {
    case ours
    case theirs
}

struct ConflictFileDocument: Sendable, Equatable {
    let path: String
    let base: String?
    let ours: String?
    let theirs: String?
    let result: String?
    let isBinary: Bool
}

enum RepositoryOperationTransition: Sendable, Equatable {
    case completed
    case paused(RepositoryOperationState)
}

struct StashRecord: Identifiable, Sendable, Equatable {
    let reference: String
    let hash: String
    let createdAt: Date
    let summary: String

    var id: String { hash }

    var index: Int? {
        guard let opening = reference.firstIndex(of: "{"),
              let closing = reference.firstIndex(of: "}") else { return nil }
        return Int(reference[reference.index(after: opening)..<closing])
    }
}

struct GitWorktreeRecord: Identifiable, Sendable, Equatable {
    let path: URL
    let headHash: String
    let branch: String?
    let isMain: Bool
    let isLocked: Bool
    let isPrunable: Bool
    let changesCount: Int
    let aheadCount: Int
    let behindCount: Int

    var id: String { path.standardizedFileURL.path }
    var shortHash: String { String(headHash.prefix(8)) }
}

enum GitWorktreeOperationKind: Sendable, Equatable {
    case refresh
    case create
    case remove
}

enum GitWorktreeAgentState: Sendable, Equatable {
    case running
    case completed
    case failed
    case cancelled
}

struct GitWorktreeAgentRun: Sendable, Equatable {
    let worktreeID: String
    let prompt: String
    let mode: CodexRunMode
    let state: GitWorktreeAgentState
    let response: String?
    let error: String?
    let startedAt: Date
    let completedAt: Date?
    let operation: CodexOperationRecord?
}

struct OperationNotice: Identifiable, Equatable {
    enum Tone: Equatable {
        case success
        case attention
    }

    let id = UUID()
    let message: String
    var tone: Tone = .success
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
    let automaticallyStagedCount: Int
}

struct CodexRunResult: Sendable, Equatable {
    let response: String
    let commandCount: Int
    let fileChangeCount: Int
    let events: [CodexOperationEvent]
    let requiresUserAction: Bool

    init(
        response: String,
        commandCount: Int,
        fileChangeCount: Int,
        events: [CodexOperationEvent] = [],
        requiresUserAction: Bool = false
    ) {
        self.response = response
        self.commandCount = commandCount
        self.fileChangeCount = fileChangeCount
        self.events = events
        self.requiresUserAction = requiresUserAction
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
    case traditionalChinese
    case english
    case japanese
    case korean
    case french
    case german
    case spanish
    case portuguese
    case russian
    case arabic

    var id: String { rawValue }

    var promptName: String {
        switch self {
        case .simplifiedChinese: "Simplified Chinese"
        case .traditionalChinese: "Traditional Chinese"
        case .english: "English"
        case .japanese: "Japanese"
        case .korean: "Korean"
        case .french: "French"
        case .german: "German"
        case .spanish: "Spanish"
        case .portuguese: "Brazilian Portuguese"
        case .russian: "Russian"
        case .arabic: "Arabic"
        }
    }

    var naturalLanguage: NLLanguage {
        switch self {
        case .simplifiedChinese: .simplifiedChinese
        case .traditionalChinese: .traditionalChinese
        case .english: .english
        case .japanese: .japanese
        case .korean: .korean
        case .french: .french
        case .german: .german
        case .spanish: .spanish
        case .portuguese: .portuguese
        case .russian: .russian
        case .arabic: .arabic
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
    let headSHA: String
    let baseBranch: String
    let nodeID: String
    let updatedAt: Date

    var id: Int { number }
}

enum GitHubPullRequestReviewTab: String, CaseIterable, Identifiable, Sendable {
    case conversation
    case commits
    case files
    case checks

    var id: String { rawValue }
}

enum GitHubPullRequestReviewEvent: String, CaseIterable, Identifiable, Sendable {
    case comment = "COMMENT"
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"

    var id: String { rawValue }
}

struct GitHubPullRequestReview: Identifiable, Sendable, Equatable {
    let id: Int64
    let author: String
    let body: String?
    let state: String
    let submittedAt: Date?
}

struct GitHubPullRequestComment: Identifiable, Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case conversation
        case review
    }

    let id: Int64
    let author: String
    let body: String
    let createdAt: Date
    let path: String?
    let line: Int?
    let kind: Kind
}

struct GitHubPullRequestCommit: Identifiable, Sendable, Equatable {
    let sha: String
    let message: String
    let author: String
    let date: Date?

    var id: String { sha }
    var shortSHA: String { String(sha.prefix(8)) }
}

struct GitHubPullRequestFile: Identifiable, Sendable, Equatable {
    let path: String
    let status: String
    let additions: Int
    let deletions: Int
    let changes: Int
    let patch: String?

    var id: String { path }
}

struct GitHubPullRequestCheck: Identifiable, Sendable, Equatable {
    let id: Int64
    let name: String
    let status: String
    let conclusion: String?
    let detailsURL: URL?
    let startedAt: Date?
    let completedAt: Date?
}

struct GitHubPullRequestReviewCenter: Sendable, Equatable {
    let reviews: [GitHubPullRequestReview]
    let comments: [GitHubPullRequestComment]
    let commits: [GitHubPullRequestCommit]
    let files: [GitHubPullRequestFile]
    let checks: [GitHubPullRequestCheck]
}

struct GitHubPullRequestContext: Sendable {
    let repositoryName: String
    let pullRequest: GitHubPullRequest
    let diff: String
}

struct GitHubDeliveryPullRequest: Sendable, Equatable {
    let number: Int
    let title: String
    let webURL: URL
    let headBranch: String
    let headSHA: String
    let baseBranch: String
    let isDraft: Bool
    let isMerged: Bool
    let isClosed: Bool
    let mergeable: Bool?
    let reviewDecision: String?
    let approvalCount: Int
    let changesRequestedCount: Int
    let requestedReviewerCount: Int
    let unresolvedThreadCount: Int
    let hasUnscannedReviewThreads: Bool

    var hasReviewBlockers: Bool {
        changesRequestedCount > 0 || unresolvedThreadCount > 0 || hasUnscannedReviewThreads
    }
}

enum GitHubProjectDetailTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case code
    case releases
    case pullRequests
    case actions

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
    let downloadURL: URL?

    init(
        name: String,
        path: String,
        kind: Kind,
        size: Int,
        webURL: URL?,
        downloadURL: URL? = nil
    ) {
        self.name = name
        self.path = path
        self.kind = kind
        self.size = size
        self.webURL = webURL
        self.downloadURL = downloadURL
    }

    var id: String { path }
}

struct GitHubFileDocument: Sendable, Equatable {
    let name: String
    let path: String
    let text: String?
    let size: Int
    let webURL: URL?
    let downloadURL: URL?
    let localPreviewURL: URL?

    init(
        name: String,
        path: String,
        text: String?,
        size: Int,
        webURL: URL?,
        downloadURL: URL? = nil,
        localPreviewURL: URL? = nil
    ) {
        self.name = name
        self.path = path
        self.text = text
        self.size = size
        self.webURL = webURL
        self.downloadURL = downloadURL
        self.localPreviewURL = localPreviewURL
    }
}

struct GitHubReleaseAsset: Identifiable, Sendable, Hashable, Codable {
    let id: Int64
    let name: String
    let size: Int64
    let downloadCount: Int
    let contentType: String
    let downloadURL: URL
    let createdAt: Date

    var fileExtension: String {
        let lower = name.lowercased()
        if lower.hasSuffix(".tar.gz") { return "tar.gz" }
        if lower.hasSuffix(".tar.xz") { return "tar.xz" }
        return (name as NSString).pathExtension.lowercased()
    }
}

struct GitHubRelease: Identifiable, Sendable, Hashable {
    let id: Int64
    let tagName: String
    let name: String
    let body: String
    let publishedAt: Date?
    let webURL: URL
    let isPrerelease: Bool
    let assets: [GitHubReleaseAsset]
}

enum MarketplacePlatform: String, CaseIterable, Identifiable, Sendable, Codable {
    case all
    case macOS
    case windows
    case linux
    case iOS
    case android

    var id: String { rawValue }

    func supports(_ asset: GitHubReleaseAsset) -> Bool {
        guard self != .all else { return true }
        let name = asset.name.lowercased()
        return switch self {
        case .all: true
        case .macOS:
            ["dmg", "pkg", "app", "zip"].contains(asset.fileExtension)
                && !name.contains("windows") && !name.contains("linux")
        case .windows:
            ["exe", "msi", "msix", "zip"].contains(asset.fileExtension)
                && !name.contains("macos") && !name.contains("darwin")
        case .linux:
            ["appimage", "deb", "rpm", "tar.gz", "tar.xz"].contains(asset.fileExtension)
                || name.contains("linux")
        case .iOS: ["ipa"].contains(asset.fileExtension)
        case .android: ["apk", "aab"].contains(asset.fileExtension)
        }
    }
}

enum MarketplaceCollection: String, CaseIterable, Identifiable, Sendable, Codable {
    case discover
    case favorites
    case installed
    case recent

    var id: String { rawValue }
}

enum MarketplaceFeed: String, CaseIterable, Identifiable, Sendable, Codable {
    case hotReleases
    case trending
    case popular

    var id: String { rawValue }
}

enum GitHubRepositorySearchSort: String, Sendable {
    case stars
    case updated
}

struct MarketplaceApplication: Identifiable, Sendable, Hashable {
    let repository: GitHubRepository
    let latestRelease: GitHubRelease
    let matchingAssets: [GitHubReleaseAsset]

    var id: String { repository.id }
    var ownerAvatarURL: URL? {
        URL(string: "https://github.com/\(repository.owner).png?size=160")
    }
}

enum ReadmeAgentStyle: String, CaseIterable, Identifiable, Sendable {
    case professional
    case minimal
    case openSource
    case product

    var id: String { rawValue }
}

enum GitHubOperationKind: Sendable, Equatable {
    case clone
    case fork
    case publishReply
    case submitReview
    case publishReviewComment
    case markFileViewed
    case rerunWorkflow
    case cancelWorkflow
    case downloadArtifact
}

struct GitHubActionsWorkflow: Identifiable, Sendable, Equatable {
    let id: Int64
    let name: String
    let path: String
    let state: String
}

struct GitHubActionsRun: Identifiable, Sendable, Equatable {
    let id: Int64
    let workflowID: Int64
    let name: String
    let displayTitle: String
    let event: String
    let status: String
    let conclusion: String?
    let branch: String?
    let headSHA: String
    let runNumber: Int
    let actor: String
    let createdAt: Date
    let updatedAt: Date
    let webURL: URL
}

struct GitHubActionsStep: Identifiable, Sendable, Equatable {
    let number: Int
    let name: String
    let status: String
    let conclusion: String?
    let startedAt: Date?
    let completedAt: Date?

    var id: Int { number }
}

struct GitHubActionsJob: Identifiable, Sendable, Equatable {
    let id: Int64
    let name: String
    let status: String
    let conclusion: String?
    let startedAt: Date?
    let completedAt: Date?
    let webURL: URL?
    let steps: [GitHubActionsStep]
}

struct GitHubActionsArtifact: Identifiable, Sendable, Equatable {
    let id: Int64
    let name: String
    let sizeInBytes: Int
    let isExpired: Bool
    let expiresAt: Date?
}

struct GitHubActionsRunDetail: Sendable, Equatable {
    let jobs: [GitHubActionsJob]
    let artifacts: [GitHubActionsArtifact]
    let log: String?
    let logError: String?
}
