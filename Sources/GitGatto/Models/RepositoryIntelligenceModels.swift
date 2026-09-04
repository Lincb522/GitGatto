import Foundation

enum RepositoryIntelligenceTab: String, CaseIterable, Identifiable, Sendable {
    case intent
    case provenance
    case capsules
    case activity

    var id: String { rawValue }
}

enum ChangeIntentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case implementation
    case fix
    case refactor
    case tests
    case documentation
    case configuration
    case assets
    case other

    var id: String { rawValue }
}

enum ChangeIntentUnitKind: String, Codable, Sendable {
    case hunk
    case wholeFile
}

struct ChangeIntentUnit: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let path: String
    let originalPath: String?
    let kind: ChangeIntentUnitKind
    let status: String
    let hunkHeader: String?
    let patch: String?
    let addedLineCount: Int
    let deletedLineCount: Int

    var displayName: String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        guard let hunkHeader else { return name }
        return "\(name) · \(hunkHeader)"
    }
}

struct ChangeIntentGroup: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var title: String
    var commitMessage: String
    var kind: ChangeIntentKind
    var unitIDs: [String]

    init(
        id: UUID = UUID(),
        title: String,
        commitMessage: String,
        kind: ChangeIntentKind,
        unitIDs: [String]
    ) {
        self.id = id
        self.title = title
        self.commitMessage = commitMessage
        self.kind = kind
        self.unitIDs = unitIDs
    }
}

struct ChangeIntentPlan: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let repositoryPath: String
    let repositoryFingerprint: String
    let createdAt: Date
    var units: [ChangeIntentUnit]
    var groups: [ChangeIntentGroup]

    init(
        id: UUID = UUID(),
        repositoryPath: String,
        repositoryFingerprint: String,
        createdAt: Date = Date(),
        units: [ChangeIntentUnit],
        groups: [ChangeIntentGroup]
    ) {
        self.id = id
        self.repositoryPath = repositoryPath
        self.repositoryFingerprint = repositoryFingerprint
        self.createdAt = createdAt
        self.units = units
        self.groups = groups
    }

    var unassignedUnitIDs: [String] {
        let assigned = Set(groups.flatMap(\.unitIDs))
        return units.map(\.id).filter { !assigned.contains($0) }
    }
}

struct ChangeIntentApplyResult: Sendable, Equatable {
    let commitHashes: [String]
    let verificationOutputs: [String]
}

enum ChangeIntentError: LocalizedError, Sendable, Equatable {
    case noChanges
    case unresolvedConflicts
    case repositoryChanged
    case invalidPlan(String)
    case unsupportedChange(String)
    case verificationFailed(command: String, output: String)

    var errorDescription: String? {
        switch self {
        case .noChanges:
            L10n.text("intelligence.intent.error.no_changes")
        case .unresolvedConflicts:
            L10n.text("intelligence.intent.error.conflicts")
        case .repositoryChanged:
            L10n.text("intelligence.intent.error.changed")
        case let .invalidPlan(message):
            message
        case let .unsupportedChange(path):
            L10n.format("intelligence.intent.error.unsupported", path)
        case let .verificationFailed(command, output):
            L10n.format("intelligence.intent.error.verification", command, output)
        }
    }
}

struct CodeProvenanceCommit: Sendable, Equatable {
    let hash: String
    let shortHash: String
    let author: String
    let authoredAt: Date?
    let subject: String
    let body: String
    let changedPaths: [String]
}

struct CodeProvenancePullRequest: Sendable, Equatable, Identifiable {
    let number: Int
    let title: String
    let body: String
    let state: String
    let author: String
    let url: URL?
    let mergedAt: Date?

    var id: Int { number }
}

struct CodeProvenanceIssue: Sendable, Equatable, Identifiable {
    let number: Int
    let title: String
    let state: String
    let url: URL?

    var id: Int { number }
}

struct CodeProvenanceReview: Sendable, Equatable, Identifiable {
    let id: Int64
    let author: String
    let state: String
    let body: String
    let submittedAt: Date?
}

struct CodeProvenanceCheck: Sendable, Equatable, Identifiable {
    let id: Int64
    let name: String
    let status: String
    let conclusion: String?
    let url: URL?
}

struct CodeProvenanceReport: Sendable, Equatable {
    let repositoryPath: String
    let filePath: String
    let line: Int
    let sourceText: String?
    let commit: CodeProvenanceCommit
    let pullRequest: CodeProvenancePullRequest?
    let issues: [CodeProvenanceIssue]
    let reviews: [CodeProvenanceReview]
    let checks: [CodeProvenanceCheck]
    let remoteUnavailableReason: String?
}

enum CodeProvenanceError: LocalizedError, Sendable {
    case invalidPath
    case invalidLine
    case lineNotCommitted
    case malformedGitOutput

    var errorDescription: String? {
        switch self {
        case .invalidPath: L10n.text("intelligence.provenance.error.path")
        case .invalidLine: L10n.text("intelligence.provenance.error.line")
        case .lineNotCommitted: L10n.text("intelligence.provenance.error.uncommitted")
        case .malformedGitOutput: L10n.text("intelligence.provenance.error.output")
        }
    }
}

struct ReproductionCapsuleTool: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let version: String

    var id: String { name }
}

struct ReproductionCapsuleManifest: Codable, Sendable, Equatable, Identifiable {
    static let formatVersion = 1

    let id: UUID
    let formatVersion: Int
    let createdAt: Date
    let repositoryName: String
    let repositoryRemote: String?
    let baseSHA: String
    let branchName: String?
    let changedPaths: [String]
    let copiedUntrackedPaths: [String]
    let omittedPaths: [String]
    let patchSHA256: String
    let failingCommand: String?
    let failureOutput: String?
    let tools: [ReproductionCapsuleTool]
}

struct ReproductionCapsule: Identifiable, Sendable, Equatable {
    let manifest: ReproductionCapsuleManifest
    let directoryURL: URL

    var id: UUID { manifest.id }
}

enum ReproductionCapsuleError: LocalizedError, Sendable {
    case noChanges
    case invalidArchive
    case unsupportedVersion
    case checksumMismatch
    case baseCommitMissing
    case destinationExists
    case unsafePath(String)

    var errorDescription: String? {
        switch self {
        case .noChanges: L10n.text("intelligence.capsule.error.no_changes")
        case .invalidArchive: L10n.text("intelligence.capsule.error.invalid")
        case .unsupportedVersion: L10n.text("intelligence.capsule.error.version")
        case .checksumMismatch: L10n.text("intelligence.capsule.error.checksum")
        case .baseCommitMissing: L10n.text("intelligence.capsule.error.base")
        case .destinationExists: L10n.text("intelligence.capsule.error.destination")
        case let .unsafePath(path): L10n.format("intelligence.capsule.error.unsafe_path", path)
        }
    }
}

enum RepositoryActivityConfidence: String, Codable, Sendable, CaseIterable {
    case high
    case medium
    case ambiguous
    case unknown
}

struct RepositoryActivityAgent: Codable, Sendable, Equatable, Identifiable {
    let processID: Int32
    let name: String

    var id: String { "\(processID):\(name)" }
}

struct RepositoryActivityEvent: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let repositoryPath: String
    let occurredAt: Date
    let previousHeadSHA: String?
    let headSHA: String?
    let previousBranch: String?
    let branch: String?
    let changedPaths: [String]
    let deletedPaths: [String]
    let refChanged: Bool
    let candidates: [RepositoryActivityAgent]
    let confidence: RepositoryActivityConfidence

    init(
        id: UUID = UUID(),
        repositoryPath: String,
        occurredAt: Date = Date(),
        previousHeadSHA: String?,
        headSHA: String?,
        previousBranch: String?,
        branch: String?,
        changedPaths: [String],
        deletedPaths: [String],
        refChanged: Bool,
        candidates: [RepositoryActivityAgent],
        confidence: RepositoryActivityConfidence
    ) {
        self.id = id
        self.repositoryPath = repositoryPath
        self.occurredAt = occurredAt
        self.previousHeadSHA = previousHeadSHA
        self.headSHA = headSHA
        self.previousBranch = previousBranch
        self.branch = branch
        self.changedPaths = changedPaths
        self.deletedPaths = deletedPaths
        self.refChanged = refChanged
        self.candidates = candidates
        self.confidence = confidence
    }
}
