import Foundation
import Testing
@testable import GitGatto

@Suite("Global error handling")
struct GlobalErrorHandlerTests {
    @Test("Keeps complete stdout and stderr from a failed Git process")
    func preservesBothGitOutputStreams() async {
        let runner = GitCommandRunner()
        let arguments = [
            "-c",
            "alias.emit=!f() { echo stdout-line; echo stderr-line >&2; exit 7; }; f",
            "emit"
        ]

        do {
            _ = try await runner.run(
                at: FileManager.default.temporaryDirectory,
                arguments: arguments
            )
            Issue.record("Expected Git to exit with status 7")
        } catch let error as GitCommandError {
            #expect(error.exitCode == 7)
            #expect(error.message == "stdout-line\nstderr-line")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Preserves complete Git output and exposes a stable commit error code")
    func reportsCommitFailure() {
        let error = GitCommandError(
            arguments: ["commit", "-m", "private commit message"],
            exitCode: 128,
            message: "first diagnostic line\nsecond diagnostic line\nthird diagnostic line"
        )
        let repository = URL(fileURLWithPath: "/tmp/example", isDirectory: true)

        let report = GlobalErrorHandler.report(
            for: error,
            context: .git(.commit),
            repositoryURL: repository,
            occurredAt: Date(timeIntervalSince1970: 0)
        )

        #expect(report.code == "GG-GIT-COMMIT-128")
        #expect(report.exitCode == 128)
        #expect(report.command == "git commit")
        #expect(report.repositoryPath == "/tmp/example")
        #expect(report.message == "first diagnostic line\nsecond diagnostic line\nthird diagnostic line")
        #expect(report.explanation == L10n.text("error.explanation.git_fatal"))
        #expect(!report.diagnosticText.contains("private commit message"))
        #expect(report.diagnosticText.contains(report.explanation))
    }

    @Test("Redacts credentials without shortening the surrounding error")
    func redactsCredentials() {
        let error = GitCommandError(
            arguments: ["push"],
            exitCode: 128,
            message: "fatal: unable to access https://ghp_exampleSecret@github.com/example/repository.git\nremote rejected the update"
        )

        let report = GlobalErrorHandler.report(for: error, context: .git(.push))

        #expect(!report.message.contains("ghp_exampleSecret"))
        #expect(report.message.contains("https://***@github.com/example/repository.git"))
        #expect(report.message.contains("remote rejected the update"))
    }

    @Test("Keeps the Git exit code when push fails after a commit")
    func reportsPushAfterCommitFailure() {
        let error = GitRepositoryServiceError.pushFailedAfterCommit(
            GitFailureDetails(arguments: ["push"], exitCode: 1, message: "remote rejected")
        )

        let report = GlobalErrorHandler.report(for: error, context: .git(.commitAndPush))

        #expect(report.code == "GG-GIT-COMMIT-PUSH-1")
        #expect(report.exitCode == 1)
        #expect(report.command == "git push")
        #expect(report.message == "remote rejected")
    }

    @Test("Reports NSError domain and numeric code")
    func reportsSystemFailure() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: [NSLocalizedDescriptionKey: "Permission denied"]
        )

        let report = GlobalErrorHandler.report(for: error, context: .repositoryOpen)

        #expect(report.code == "GG-REPOSITORY-OPEN-257")
        #expect(report.domain == NSCocoaErrorDomain)
        #expect(report.systemCode == NSFileReadNoPermissionError)
        #expect(report.message == "Permission denied")
        #expect(report.explanation == L10n.text("error.explanation.file_permission"))
    }

    @Test("Reports the extended Agent timeout with actionable recovery")
    func reportsAgentTimeout() {
        let report = GlobalErrorHandler.report(
            for: CodexServiceError.timedOut,
            context: .agent,
            repositoryURL: URL(fileURLWithPath: "/tmp/example", isDirectory: true)
        )

        #expect(report.code == "GG-AGENT-RUN-6")
        #expect(report.message == "The AI CLI did not finish within the time limit.")
        #expect(report.explanation == L10n.text("error.explanation.agent_timeout"))
        #expect(report.recoverySuggestion == L10n.text("error.recovery.agent_timeout"))
    }

    @Test("Explains common Git failures without replacing the original output")
    func explainsGitFailure() {
        let original = "error: failed to push some refs to 'origin'\nhint: Updates were rejected because the remote contains work that you do not have locally."
        let report = GlobalErrorHandler.report(
            for: GitCommandError(arguments: ["push"], exitCode: 1, message: original),
            context: .git(.push)
        )

        #expect(report.message == original)
        #expect(report.explanation == L10n.text("error.explanation.git_non_fast_forward"))
        #expect(report.recoverySuggestion == L10n.text("error.recovery.git_non_fast_forward"))
    }

    @Test("Provides catalog entries for every Agent service error")
    func explainsEveryAgentServiceError() {
        let errors: [CodexServiceError] = [
            .executableNotFound,
            .launchFailed,
            .executionFailed(9),
            .missingResponse,
            .inputTooLarge,
            .invalidTranslation,
            .timedOut,
            .installerSandboxUnavailable
        ]

        for error in errors {
            let report = GlobalErrorHandler.report(for: error, context: .agent)
            #expect(!report.explanation.isEmpty)
            #expect(!report.recoverySuggestion.isEmpty)
            #expect(report.message == error.localizedDescription)
        }
    }
}
