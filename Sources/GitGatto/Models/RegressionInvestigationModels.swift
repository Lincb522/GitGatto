import Foundation

enum RegressionInvestigationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case manual

    var id: String { rawValue }
}

enum RegressionInvestigationStatus: String, Codable, Sendable {
    case preparing
    case running
    case awaitingManualVerdict
    case paused
    case culpritFound
    case agentFixing
    case fixReady
    case verifyingFix
    case fixVerified
    case publishing
    case completed
    case inconclusive
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .inconclusive, .failed, .cancelled:
            true
        default:
            false
        }
    }

    var canResume: Bool {
        self == .paused
    }
}

enum RegressionVerdict: String, Codable, CaseIterable, Identifiable, Sendable {
    case good
    case bad
    case skipped

    var id: String { rawValue }

    var gitArgument: String {
        switch self {
        case .good: "good"
        case .bad: "bad"
        case .skipped: "skip"
        }
    }
}

struct RegressionCommitEvidence: Codable, Sendable, Equatable, Identifiable {
    let sha: String
    let shortSHA: String
    let subject: String
    let author: String
    let authoredAt: Date?

    var id: String { sha }
}

struct RegressionProbe: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let commit: RegressionCommitEvidence
    let verdict: RegressionVerdict
    let exitCode: Int32?
    let duration: TimeInterval
    let output: String
    let completedAt: Date

    init(
        id: UUID = UUID(),
        commit: RegressionCommitEvidence,
        verdict: RegressionVerdict,
        exitCode: Int32?,
        duration: TimeInterval,
        output: String,
        completedAt: Date = Date()
    ) {
        self.id = id
        self.commit = commit
        self.verdict = verdict
        self.exitCode = exitCode
        self.duration = duration
        self.output = output
        self.completedAt = completedAt
    }
}

struct RegressionFixVerification: Codable, Sendable, Equatable {
    let passed: Bool
    let exitCode: Int32?
    let duration: TimeInterval
    let output: String
    let completedAt: Date
}

struct RegressionInvestigation: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let repositoryPath: String
    let repositoryName: String
    let sourceBranch: String?
    let sourceHeadSHA: String
    let goodRevision: String
    let badRevision: String
    let goodSHA: String
    let badSHA: String
    let verificationCommand: String
    let mode: RegressionInvestigationMode
    let createdAt: Date
    var updatedAt: Date
    var status: RegressionInvestigationStatus
    var workspacePath: String?
    var currentCommit: RegressionCommitEvidence?
    var candidateCount: Int
    var probes: [RegressionProbe]
    var culprit: RegressionCommitEvidence?
    var culpritSummary: String?
    var bisectLog: String?
    var agentSummary: String?
    var fixBranch: String?
    var fixVerification: RegressionFixVerification?
    var fixCommitSHA: String?
    var pullRequestURL: URL?
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        repositoryPath: String,
        repositoryName: String,
        sourceBranch: String?,
        sourceHeadSHA: String,
        goodRevision: String,
        badRevision: String,
        goodSHA: String,
        badSHA: String,
        verificationCommand: String,
        mode: RegressionInvestigationMode,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        status: RegressionInvestigationStatus = .preparing,
        workspacePath: String? = nil,
        currentCommit: RegressionCommitEvidence? = nil,
        candidateCount: Int = 0,
        probes: [RegressionProbe] = [],
        culprit: RegressionCommitEvidence? = nil,
        culpritSummary: String? = nil,
        bisectLog: String? = nil,
        agentSummary: String? = nil,
        fixBranch: String? = nil,
        fixVerification: RegressionFixVerification? = nil,
        fixCommitSHA: String? = nil,
        pullRequestURL: URL? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.repositoryPath = repositoryPath
        self.repositoryName = repositoryName
        self.sourceBranch = sourceBranch
        self.sourceHeadSHA = sourceHeadSHA
        self.goodRevision = goodRevision
        self.badRevision = badRevision
        self.goodSHA = goodSHA
        self.badSHA = badSHA
        self.verificationCommand = verificationCommand
        self.mode = mode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.workspacePath = workspacePath
        self.currentCommit = currentCommit
        self.candidateCount = candidateCount
        self.probes = probes
        self.culprit = culprit
        self.culpritSummary = culpritSummary
        self.bisectLog = bisectLog
        self.agentSummary = agentSummary
        self.fixBranch = fixBranch
        self.fixVerification = fixVerification
        self.fixCommitSHA = fixCommitSHA
        self.pullRequestURL = pullRequestURL
        self.errorMessage = errorMessage
    }

    var repositoryURL: URL {
        URL(fileURLWithPath: repositoryPath, isDirectory: true)
    }

    var workspaceURL: URL? {
        workspacePath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var completedProbeCount: Int { probes.count }

    var estimatedProgress: Double {
        guard candidateCount > 0 else { return 0 }
        if culprit != nil { return 1 }
        let estimatedSteps = max(1, Int(ceil(log2(Double(candidateCount)))))
        return min(0.96, Double(probes.count) / Double(estimatedSteps))
    }
}
