import Darwin
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
    case regression
    case github
    case goal

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
        case .regression: "REGRESSION"
        case .github: "GITHUB"
        case .goal: "PROJECT-GOAL"
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
        case .regression: L10n.text("error.operation.regression")
        case .github: L10n.text("error.operation.github")
        case .goal: L10n.text("error.operation.goal")
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
        case .regression:
            L10n.text("error.recovery.regression")
        case .github:
            L10n.text("error.recovery.github")
        case .goal:
            L10n.text("error.recovery.goal")
        }
    }
}

struct AppErrorReport: Identifiable, Sendable, Equatable {
    let id: UUID
    let code: String
    let title: String
    let message: String
    let explanation: String
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
        explanation: String,
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
        self.explanation = explanation
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
        lines.append("\(L10n.text("error.section.explanation")): \(explanation)")
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
        let message = redact(nsError.localizedDescription)
        let diagnosis = AppErrorCatalog.diagnosis(
            for: error,
            message: message,
            context: context
        )
        return AppErrorReport(
            code: "GG-\(context.codeComponent)-\(numericCode(nsError.code))",
            title: title,
            message: message,
            explanation: diagnosis.explanation,
            recoverySuggestion: diagnosis.recoverySuggestion,
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
        let message = redact(details.message)
        let diagnosis = AppErrorCatalog.diagnosis(
            for: nil,
            message: message,
            context: context,
            exitCode: details.exitCode
        )
        return AppErrorReport(
            code: "GG-\(context.codeComponent)-\(suffix)",
            title: title,
            message: message,
            explanation: diagnosis.explanation,
            recoverySuggestion: diagnosis.recoverySuggestion,
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

private struct AppErrorDiagnosis {
    let explanation: String
    let recoverySuggestion: String
}

private enum AppErrorCatalog {
    static func diagnosis(
        for error: (any Error)?,
        message: String,
        context: AppErrorContext,
        exitCode: Int32? = nil
    ) -> AppErrorDiagnosis {
        if let diagnosis = typedDiagnosis(for: error) {
            return diagnosis
        }
        if let diagnosis = gitDiagnosis(message: message) {
            return diagnosis
        }
        if let error, let diagnosis = systemDiagnosis(for: error as NSError) {
            return diagnosis
        }

        let explanationKey: String = switch context {
        case .repositoryOpen: "error.explanation.repository_open"
        case .repositoryRefresh: "error.explanation.repository_refresh"
        case .diffLoad: "error.explanation.diff_load"
        case .fileHistory: "error.explanation.file_history"
        case .diagnostics: "error.explanation.diagnostics"
        case .agent: "error.explanation.agent_unknown"
        case .worktree: "error.explanation.worktree_unknown"
        case .regression: "error.explanation.regression_unknown"
        case .github: "error.explanation.github_unknown"
        case .goal: "error.explanation.goal_unknown"
        case .git: exitCode == 128 ? "error.explanation.git_fatal" : "error.explanation.git_unknown"
        }
        return AppErrorDiagnosis(
            explanation: L10n.text(explanationKey),
            recoverySuggestion: context.recoverySuggestion
        )
    }

    private static func typedDiagnosis(for error: (any Error)?) -> AppErrorDiagnosis? {
        switch error {
        case let error as CodexServiceError:
            return switch error {
            case .executableNotFound:
                localized("error.explanation.agent_executable", "error.recovery.agent_executable")
            case .launchFailed:
                localized("error.explanation.agent_launch", "error.recovery.agent_launch")
            case .executionFailed:
                localized("error.explanation.agent_exit", "error.recovery.agent_exit")
            case .missingResponse:
                localized("error.explanation.agent_empty", "error.recovery.agent_empty")
            case .inputTooLarge:
                localized("error.explanation.agent_input_large", "error.recovery.agent_input_large")
            case .invalidTranslation:
                localized("error.explanation.agent_translation", "error.recovery.agent_translation")
            case .installerSandboxUnavailable:
                localized("error.explanation.agent_installer_sandbox", "error.recovery.agent_installer_sandbox")
            case .timedOut:
                localized("error.explanation.agent_timeout", "error.recovery.agent_timeout")
            }
        case let error as GitHubServiceError:
            return switch error {
            case .executableNotFound:
                localized("error.explanation.github_cli_missing", "error.recovery.github_cli_missing")
            case .launchFailed:
                localized("error.explanation.github_launch", "error.recovery.github_launch")
            case .commandFailed:
                nil
            case .destinationExists:
                localized("error.explanation.destination_exists", "error.recovery.destination_exists")
            case .invalidResponse:
                localized("error.explanation.github_response", "error.recovery.github_response")
            case .resourceNotFound:
                localized("error.explanation.github_not_found", "error.recovery.github_not_found")
            }
        case let error as GitHubReleaseServiceError:
            return switch error {
            case .invalidResponse:
                localized("error.explanation.github_response", "error.recovery.github_response")
            case .httpStatus:
                localized("error.explanation.http_status", "error.recovery.http_status")
            }
        case let error as GitWorktreeServiceError:
            return switch error {
            case .invalidBranch:
                localized("error.explanation.worktree_branch", "error.recovery.worktree_branch")
            case .destinationExists:
                localized("error.explanation.destination_exists", "error.recovery.destination_exists")
            case .cannotRemoveMainWorktree:
                localized("error.explanation.worktree_main", "error.recovery.worktree_main")
            case .worktreeNotRegistered:
                localized("error.explanation.worktree_unregistered", "error.recovery.worktree_unregistered")
            }
        case let error as MacApplicationInstallerError:
            return switch error {
            case .unsupportedFormat:
                localized("error.explanation.installer_format", "error.recovery.installer_format")
            case .noApplicationFound:
                localized("error.explanation.installer_no_app", "error.recovery.installer_no_app")
            case .destinationExists:
                localized("error.explanation.destination_exists", "error.recovery.destination_exists")
            case .commandFailed:
                nil
            }
        case is CommitDraftPreparationError:
            return localized("error.explanation.unresolved_conflicts", "error.recovery.unresolved_conflicts")
        default:
            return nil
        }
    }

    private static func gitDiagnosis(message: String) -> AppErrorDiagnosis? {
        let value = message.lowercased()
        let rules: [(needles: [String], explanation: String, recovery: String)] = [
            (["not a git repository"], "error.explanation.git_not_repository", "error.recovery.git_not_repository"),
            (["another git process seems to be running", "index.lock': file exists", "index.lock\" already exists"], "error.explanation.git_index_lock", "error.recovery.git_index_lock"),
            (["pathspec", "did not match any file"], "error.explanation.git_pathspec", "error.recovery.git_pathspec"),
            (["permission denied (publickey)"], "error.explanation.git_ssh_auth", "error.recovery.git_ssh_auth"),
            (["host key verification failed"], "error.explanation.git_host_key", "error.recovery.git_host_key"),
            (["authentication failed", "could not read username", "terminal prompts disabled", "invalid username or password"], "error.explanation.git_auth", "error.recovery.git_auth"),
            (["repository not found", "does not appear to be a git repository"], "error.explanation.git_remote_missing", "error.recovery.git_remote_missing"),
            (["could not resolve host", "name or service not known"], "error.explanation.network_dns", "error.recovery.network_dns"),
            (["failed to connect", "connection timed out", "connection reset", "network is unreachable"], "error.explanation.network_connection", "error.recovery.network_connection"),
            (["ssl certificate problem", "certificate verify failed"], "error.explanation.network_certificate", "error.recovery.network_certificate"),
            (["non-fast-forward", "fetch first", "failed to push some refs"], "error.explanation.git_non_fast_forward", "error.recovery.git_non_fast_forward"),
            (["has no upstream branch", "no tracking information for the current branch"], "error.explanation.git_no_upstream", "error.recovery.git_no_upstream"),
            (["need to specify how to reconcile divergent branches", "divergent branches"], "error.explanation.git_diverged", "error.recovery.git_diverged"),
            (["would be overwritten by merge", "would be overwritten by checkout"], "error.explanation.git_local_overwrite", "error.recovery.git_local_overwrite"),
            (["unmerged files", "resolve your current index first", "fix conflicts and then commit"], "error.explanation.unresolved_conflicts", "error.recovery.unresolved_conflicts"),
            (["gpg failed to sign", "failed to sign the data"], "error.explanation.git_signing", "error.recovery.git_signing"),
            (["hook", "exited with code"], "error.explanation.git_hook", "error.recovery.git_hook"),
            (["git-lfs: command not found", "git-lfs was not found", "git: 'lfs' is not a git command"], "error.explanation.git_lfs", "error.recovery.git_lfs"),
            (["src refspec", "does not match any"], "error.explanation.git_refspec", "error.recovery.git_refspec"),
            (["no space left on device", "disk quota exceeded"], "error.explanation.storage_full", "error.recovery.storage_full"),
            (["cannot lock ref", "unable to create", "could not lock"], "error.explanation.git_lock_ref", "error.recovery.git_lock_ref"),
            (["nothing to commit", "no changes added to commit"], "error.explanation.git_nothing_to_commit", "error.recovery.git_nothing_to_commit"),
            (["refusing to merge unrelated histories"], "error.explanation.git_unrelated", "error.recovery.git_unrelated"),
            (["remote origin already exists"], "error.explanation.git_remote_exists", "error.recovery.git_remote_exists"),
            (["unknown revision", "bad revision", "ambiguous argument"], "error.explanation.git_revision", "error.recovery.git_revision")
        ]

        for rule in rules where rule.needles.contains(where: value.contains) {
            return localized(rule.explanation, rule.recovery)
        }
        return nil
    }

    private static func systemDiagnosis(for error: NSError) -> AppErrorDiagnosis? {
        if error.domain == NSURLErrorDomain {
            return switch error.code {
            case NSURLErrorTimedOut:
                localized("error.explanation.network_timeout", "error.recovery.network_connection")
            case NSURLErrorNotConnectedToInternet:
                localized("error.explanation.network_offline", "error.recovery.network_connection")
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                localized("error.explanation.network_dns", "error.recovery.network_dns")
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot:
                localized("error.explanation.network_certificate", "error.recovery.network_certificate")
            case NSURLErrorBadServerResponse:
                localized("error.explanation.http_status", "error.recovery.http_status")
            default:
                localized("error.explanation.network_connection", "error.recovery.network_connection")
            }
        }

        if error.domain == NSCocoaErrorDomain {
            return switch error.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                localized("error.explanation.file_permission", "error.recovery.file_permission")
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                localized("error.explanation.file_missing", "error.recovery.file_missing")
            case NSFileWriteOutOfSpaceError:
                localized("error.explanation.storage_full", "error.recovery.storage_full")
            case NSFileWriteFileExistsError:
                localized("error.explanation.destination_exists", "error.recovery.destination_exists")
            default:
                nil
            }
        }

        if error.domain == NSPOSIXErrorDomain {
            return switch Int32(error.code) {
            case EACCES, EPERM:
                localized("error.explanation.file_permission", "error.recovery.file_permission")
            case ENOENT:
                localized("error.explanation.file_missing", "error.recovery.file_missing")
            case ENOSPC, EDQUOT:
                localized("error.explanation.storage_full", "error.recovery.storage_full")
            case EEXIST:
                localized("error.explanation.destination_exists", "error.recovery.destination_exists")
            default:
                nil
            }
        }
        return nil
    }

    private static func localized(_ explanationKey: String, _ recoveryKey: String) -> AppErrorDiagnosis {
        AppErrorDiagnosis(
            explanation: L10n.text(explanationKey),
            recoverySuggestion: L10n.text(recoveryKey)
        )
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
