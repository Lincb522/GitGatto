import Foundation

enum RepositoryBackupReason: String, Codable, CaseIterable, Sendable {
    case scheduled
    case majorChange
    case manual
    case agentCheckpoint
    case externalCheckpoint
}

struct RepositoryBackup: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let repositoryPath: String
    let repositoryName: String
    let branchName: String?
    let headSHA: String?
    let createdAt: Date
    let reason: RepositoryBackupReason
    let changedFileCount: Int
    let changedLineCount: Int
    let storedByteCount: Int64
    let omittedFileCount: Int
    let directoryName: String
}

struct RepositoryBackupPolicy: Sendable, Equatable {
    static let maximumRetentionCount = 3

    let majorFileThreshold: Int
    let majorLineThreshold: Int
    let retentionCount: Int
    let maximumFileSize: Int64

    static let standard = RepositoryBackupPolicy(
        majorFileThreshold: 20,
        majorLineThreshold: 500,
        retentionCount: maximumRetentionCount,
        maximumFileSize: 50 * 1024 * 1024
    )

    static func clampedRetentionCount(_ value: Int) -> Int {
        min(maximumRetentionCount, max(1, value))
    }
}

struct RepositoryBackupManifest: Codable, Sendable, Equatable {
    let backup: RepositoryBackup
    let copiedPaths: [String]
    let deletedPaths: [String]
    let omittedPaths: [String]
    let fingerprint: String
    let indexFingerprint: String?
    let bundleFileName: String?
}

struct RepositoryProtectionAssessment: Sendable, Equatable {
    let backupID: UUID
    let changedFileCount: Int
    let changedLineCount: Int
    let deletedPaths: [String]
    let lostChangedPaths: [String]
    let headChanged: Bool
    let branchChanged: Bool
    let indexChanged: Bool

    var requiresReview: Bool {
        !deletedPaths.isEmpty
            || !lostChangedPaths.isEmpty
            || headChanged
            || branchChanged
            || indexChanged
    }
}

struct AgentProtectionNotice: Sendable, Equatable {
    let backup: RepositoryBackup
    let assessment: RepositoryProtectionAssessment
    let reportedFileChangeCount: Int
    let exceedsConfiguredChangeLimit: Bool

    var requiresReview: Bool {
        assessment.requiresReview || exceedsConfiguredChangeLimit
    }
}

enum RepositoryProtectionIncidentKind: Sendable, Equatable {
    case destructiveChange
    case repositoryUnavailable
}

struct RepositoryProtectionIncident: Identifiable, Sendable, Equatable {
    let id: UUID
    let repositoryPath: String
    let repositoryName: String
    let detectedAt: Date
    let backup: RepositoryBackup
    let kind: RepositoryProtectionIncidentKind
    let assessment: RepositoryProtectionAssessment?
    let failureDescription: String?

    init(
        id: UUID = UUID(),
        repositoryPath: String,
        repositoryName: String,
        detectedAt: Date = Date(),
        backup: RepositoryBackup,
        kind: RepositoryProtectionIncidentKind,
        assessment: RepositoryProtectionAssessment? = nil,
        failureDescription: String? = nil
    ) {
        self.id = id
        self.repositoryPath = repositoryPath
        self.repositoryName = repositoryName
        self.detectedAt = detectedAt
        self.backup = backup
        self.kind = kind
        self.assessment = assessment
        self.failureDescription = failureDescription
    }
}

enum RepositoryBackupError: LocalizedError, Sendable {
    case repositoryUnavailable
    case destinationExists
    case backupMissing
    case invalidBackupPath
    case storageBusy
    case migrationDestinationNotEmpty
    case migrationVerificationFailed
    case agentCheckpointUnavailable

    var errorDescription: String? {
        switch self {
        case .repositoryUnavailable:
            L10n.text("recovery.error.repository_unavailable")
        case .destinationExists:
            L10n.text("recovery.error.destination_exists")
        case .backupMissing:
            L10n.text("recovery.error.backup_missing")
        case .invalidBackupPath:
            L10n.text("recovery.error.invalid_path")
        case .storageBusy:
            L10n.text("recovery.error.storage_busy")
        case .migrationDestinationNotEmpty:
            L10n.text("recovery.error.migration_destination_not_empty")
        case .migrationVerificationFailed:
            L10n.text("recovery.error.migration_verification_failed")
        case .agentCheckpointUnavailable:
            L10n.text("recovery.error.agent_checkpoint_unavailable")
        }
    }
}
