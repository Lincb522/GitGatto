import Foundation

enum AppErrorContext: Sendable, Equatable {
    case repositoryOpen
    case repositoryRefresh
    case diffLoad
    case fileHistory
    case diagnostics
    case git(OperationKind)
    case agent
    case worktree
    case github

    fileprivate var codeComponent: String {
        switch self {
        case .repositoryOpen: "REPOSITORY-OPEN"
        case .repositoryRefresh: "REPOSITORY-REFRESH"
        case .diffLoad: "DIFF-LOAD"
        case .fileHistory: "FILE-HISTORY"
        case .diagnostics: "DIAGNOSTICS"
        case let .git(operation): "GIT-\(operation.errorCodeComponent)"
        case .agent: "AGENT-RUN"
        case .worktree: "WORKTREE"
        case .github: "GITHUB"
        }
    }

    fileprivate var operationName: String {
        switch self {
        case .repositoryOpen: L10n.text("error.operation.repository_open")
        case .repositoryRefresh: L10n.text("error.operation.repository_refresh")
        case .diffLoad: L10n.text("error.operation.diff_load")
        case .fileHistory: L10n.text("error.operation.file_history")
        case .diagnostics: L10n.text("error.operation.diagnostics")
        case let .git(operation): L10n.text(operation.errorOperationKey)
        case .agent: L10n.text("error.operation.agent")
        case .worktree: L10n.text("error.operation.worktree")
        case .github: L10n.text("error.operation.github")
        }
    }

    fileprivate var recoverySuggestion: String {
        switch self {
        case .repositoryOpen, .repositoryRefresh, .diffLoad, .fileHistory:
            L10n.text("error.recovery.repository")
        case .diagnostics:
            L10n.text("error.recovery.diagnostics")
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
        case .worktree:
            L10n.text("error.recovery.worktree")
        case .github:
            L10n.text("error.recovery.github")
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
            recoverySuggestion: recoverySuggestion(for: error, context: context),
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

    private static func recoverySuggestion(
        for error: any Error,
        context: AppErrorContext
    ) -> String {
        guard case .agent = context,
              let serviceError = error as? CodexServiceError else {
            return context.recoverySuggestion
        }
        if case .timedOut = serviceError {
            return L10n.text("error.recovery.agent_timeout")
        }
        return context.recoverySuggestion
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
        case .merge: "MERGE"
        case .rebase: "REBASE"
        case .resolveConflict: "RESOLVE-CONFLICT"
        case .continueConflictOperation: "CONTINUE-OPERATION"
        case .skipConflictOperation: "SKIP-OPERATION"
        case .abortConflictOperation: "ABORT-OPERATION"
        case .stashSave: "STASH-SAVE"
        case .stashApply: "STASH-APPLY"
        case .stashPop: "STASH-POP"
        case .stashDrop: "STASH-DROP"
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
        case .merge: "error.operation.merge"
        case .rebase: "error.operation.rebase"
        case .resolveConflict: "error.operation.resolve_conflict"
        case .continueConflictOperation: "error.operation.continue_conflict"
        case .skipConflictOperation: "error.operation.skip_conflict"
        case .abortConflictOperation: "error.operation.abort_conflict"
        case .stashSave: "error.operation.stash_save"
        case .stashApply: "error.operation.stash_apply"
        case .stashPop: "error.operation.stash_pop"
        case .stashDrop: "error.operation.stash_drop"
        }
    }
}
