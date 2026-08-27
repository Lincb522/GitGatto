import Foundation

enum AppErrorContext: Sendable, Equatable {
    case repositoryOpen
    case repositoryRefresh
    case diffLoad
    case git(OperationKind)
    case agent

    fileprivate var codeComponent: String {
        switch self {
        case .repositoryOpen: "REPOSITORY-OPEN"
        case .repositoryRefresh: "REPOSITORY-REFRESH"
        case .diffLoad: "DIFF-LOAD"
        case let .git(operation): "GIT-\(operation.errorCodeComponent)"
        case .agent: "AGENT-RUN"
        }
    }

    fileprivate var operationName: String {
        switch self {
        case .repositoryOpen: L10n.text("error.operation.repository_open")
        case .repositoryRefresh: L10n.text("error.operation.repository_refresh")
        case .diffLoad: L10n.text("error.operation.diff_load")
        case let .git(operation): L10n.text(operation.errorOperationKey)
        case .agent: L10n.text("error.operation.agent")
        }
    }

    fileprivate var recoverySuggestion: String {
        switch self {
        case .repositoryOpen, .repositoryRefresh, .diffLoad:
            L10n.text("error.recovery.repository")
        case .git(.commit):
            L10n.text("error.recovery.commit")
        case .git(.commitAndPush), .git(.push):
            L10n.text("error.recovery.push")
        case .git(.pull):
            L10n.text("error.recovery.pull")
        case .git:
            L10n.text("error.recovery.git")
        case .agent:
            L10n.text("error.recovery.agent")
        }
    }
}

struct AppErrorReport: Identifiable, Sendable, Equatable {
    let id: UUID
    let code: String
    let title: String
    let message: String
    let recoverySuggestion: String
    let operation: String
    let repositoryPath: String?
    let command: String?
    let exitCode: Int32?
    let domain: String
    let systemCode: Int?
    let occurredAt: Date

    init(
        id: UUID = UUID(),
        code: String,
        title: String,
        message: String,
        recoverySuggestion: String,
        operation: String,
        repositoryPath: String?,
        command: String?,
        exitCode: Int32?,
        domain: String,
        systemCode: Int?,
        occurredAt: Date = Date()
    ) {
        self.id = id
        self.code = code
        self.title = title
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.operation = operation
        self.repositoryPath = repositoryPath
        self.command = command
        self.exitCode = exitCode
        self.domain = domain
        self.systemCode = systemCode
        self.occurredAt = occurredAt
    }

    var diagnosticText: String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "\(L10n.text("error.detail.code")): \(code)",
            "\(L10n.text("error.detail.operation")): \(operation)",
            "\(L10n.text("error.detail.domain")): \(domain)"
        ]
        if let exitCode {
            lines.append("\(L10n.text("error.detail.exit_code")): \(exitCode)")
        }
        if let systemCode {
            lines.append("\(L10n.text("error.detail.system_code")): \(systemCode)")
        }
        if let command {
            lines.append("\(L10n.text("error.detail.command")): \(command)")
        }
        if let repositoryPath {
            lines.append("\(L10n.text("error.detail.repository")): \(repositoryPath)")
        }
        lines.append("\(L10n.text("error.detail.time")): \(formatter.string(from: occurredAt))")
        lines.append("")
        lines.append(message)
        lines.append("")
        lines.append(recoverySuggestion)
        return lines.joined(separator: "\n")
    }
}

enum GlobalErrorHandler {
    static func report(
        for error: any Error,
        context: AppErrorContext,
        repositoryURL: URL? = nil,
        occurredAt: Date = Date()
    ) -> AppErrorReport {
        let operation = context.operationName
        let title = L10n.format("error.dialog.operation_title", operation)
        let repositoryPath = repositoryURL?.standardizedFileURL.path

        if let gitError = error as? GitCommandError {
            return gitReport(
                details: gitError.failureDetails,
                context: context,
                title: title,
                operation: operation,
                repositoryPath: repositoryPath,
                occurredAt: occurredAt
            )
        }

        if let repositoryError = error as? GitRepositoryServiceError {
            return gitReport(
                details: repositoryError.failureDetails,
                context: context,
                title: title,
                operation: operation,
                repositoryPath: repositoryPath,
                occurredAt: occurredAt
            )
        }

        let nsError = error as NSError
        return AppErrorReport(
            code: "GG-\(context.codeComponent)-\(numericCode(nsError.code))",
            title: title,
            message: redact(nsError.localizedDescription),
            recoverySuggestion: context.recoverySuggestion,
            operation: operation,
            repositoryPath: repositoryPath,
            command: nil,
            exitCode: nil,
            domain: nsError.domain,
            systemCode: nsError.code,
            occurredAt: occurredAt
        )
    }

    private static func gitReport(
        details: GitFailureDetails,
        context: AppErrorContext,
        title: String,
        operation: String,
        repositoryPath: String?,
        occurredAt: Date
    ) -> AppErrorReport {
        let suffix = details.exitCode.map(String.init) ?? "UNKNOWN"
        return AppErrorReport(
            code: "GG-\(context.codeComponent)-\(suffix)",
            title: title,
            message: redact(details.message),
            recoverySuggestion: context.recoverySuggestion,
            operation: operation,
            repositoryPath: repositoryPath,
            command: details.safeCommand,
            exitCode: details.exitCode,
            domain: "git",
            systemCode: nil,
            occurredAt: occurredAt
        )
    }

    private static func numericCode(_ code: Int) -> String {
        code < 0 ? "N\(abs(code))" : String(code)
    }

    private static func redact(_ value: String) -> String {
        var result = value
        let patterns = [
            #"(?i)(https?://)[^/@\s]+@"#,
            #"(?i)\b(?:gh[pousr]|github_pat)_[A-Za-z0-9_]+\b"#,
            #"(?i)(authorization:\s*(?:bearer|token)\s+)[^\s]+"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            let replacement = pattern.contains("https?") ? "$1***@" : (pattern.contains("authorization") ? "$1***" : "***")
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        return result
    }
}

private extension OperationKind {
    var errorCodeComponent: String {
        switch self {
        case .stage: "STAGE"
        case .unstage: "UNSTAGE"
        case .discard: "DISCARD"
        case .ignore: "IGNORE"
        case .commit: "COMMIT"
        case .commitAndPush: "COMMIT-PUSH"
        case .switchBranch: "SWITCH-BRANCH"
        case .pull: "PULL"
        case .push: "PUSH"
        }
    }

    var errorOperationKey: String {
        switch self {
        case .stage: "error.operation.stage"
        case .unstage: "error.operation.unstage"
        case .discard: "error.operation.discard"
        case .ignore: "error.operation.ignore"
        case .commit: "error.operation.commit"
        case .commitAndPush: "error.operation.commit_push"
        case .switchBranch: "error.operation.switch_branch"
        case .pull: "error.operation.pull"
        case .push: "error.operation.push"
        }
    }
}
