import Foundation

enum RegressionInvestigationError: LocalizedError, Sendable, Equatable {
    case emptyVerificationCommand
    case invalidRevision(String)
    case identicalBoundary
    case goodRevisionIsNotAncestor
    case workspaceMissing
    case currentCommitMissing
    case manualVerdictUnavailable
    case culpritMissing
    case fixNotVerified
    case noFixChanges
    case sourceBranchMissing
    case commandFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .emptyVerificationCommand:
            L10n.text("regression.error.empty_command")
        case let .invalidRevision(revision):
            L10n.format("regression.error.invalid_revision", revision)
        case .identicalBoundary:
            L10n.text("regression.error.identical_boundary")
        case .goodRevisionIsNotAncestor:
            L10n.text("regression.error.not_ancestor")
        case .workspaceMissing:
            L10n.text("regression.error.workspace_missing")
        case .currentCommitMissing:
            L10n.text("regression.error.current_commit_missing")
        case .manualVerdictUnavailable:
            L10n.text("regression.error.manual_verdict_unavailable")
        case .culpritMissing:
            L10n.text("regression.error.culprit_missing")
        case .fixNotVerified:
            L10n.text("regression.error.fix_not_verified")
        case .noFixChanges:
            L10n.text("regression.error.no_fix_changes")
        case .sourceBranchMissing:
            L10n.text("regression.error.source_branch_missing")
        case let .commandFailed(code, output):
            output.isEmpty
                ? L10n.format("regression.error.command_failed_code", code)
                : output
        }
    }
}

struct RegressionCommandResult: Sendable, Equatable {
    let standardOutput: String
    let standardError: String
    let exitCode: Int32

    var combinedOutput: String {
        [standardOutput, standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

struct RegressionCommandRunner: Sendable {
    private let additionalSearchPaths: [String]

    init(additionalSearchPaths: [String] = []) {
        self.additionalSearchPaths = additionalSearchPaths
    }

    func runShell(command: String, at directory: URL) async throws -> RegressionCommandResult {
        try await run(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", command],
            at: directory
        )
    }

    func run(
        executable: URL,
        arguments: [String],
        at directory: URL
    ) async throws -> RegressionCommandResult {
        let processBox = RegressionProcessBox()
        let task = Task.detached(priority: .userInitiated) {
            try Self.runBlocking(
                executable: executable,
                arguments: arguments,
                at: directory,
                additionalSearchPaths: additionalSearchPaths,
                processBox: processBox
            )
        }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            task.cancel()
            processBox.cancel()
        }
    }

    private static func runBlocking(
        executable: URL,
        arguments: [String],
        at directory: URL,
        additionalSearchPaths: [String],
        processBox: RegressionProcessBox
    ) throws -> RegressionCommandResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = standardOutput
        process.standardError = standardError

        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["GIT_PAGER"] = "cat"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["PATH"] = GitCommandRunner.commandPath(
            inheritedPath: environment["PATH"],
            additionalSearchPaths: additionalSearchPaths + [
                "/usr/local/bin",
                "/opt/homebrew/bin",
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".local/bin", isDirectory: true)
                    .path
            ]
        )
        process.environment = environment

        guard !processBox.install(process) else { throw CancellationError() }
        defer { processBox.clear() }
        try process.run()
        if processBox.isCancelled { process.terminate() }

        let outputBox = RegressionDataBox()
        let errorBox = RegressionDataBox()
        let reads = DispatchGroup()
        reads.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputBox.set(standardOutput.fileHandleForReading.readDataToEndOfFile())
            reads.leave()
        }
        reads.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorBox.set(standardError.fileHandleForReading.readDataToEndOfFile())
            reads.leave()
        }
        process.waitUntilExit()
        reads.wait()

        if processBox.isCancelled || Task.isCancelled { throw CancellationError() }
        return RegressionCommandResult(
            standardOutput: String(decoding: outputBox.value, as: UTF8.self),
            standardError: String(decoding: errorBox.value, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }
}

actor RegressionInvestigationRuntime {
    typealias UpdateHandler = @Sendable (RegressionInvestigation) async -> Void

    private let gitRunner: GitCommandRunner
    private let commandRunner: RegressionCommandRunner
    private let fileManager: FileManager
    private let workspaceRoot: URL

    init(
        gitRunner: GitCommandRunner = GitCommandRunner(),
        commandRunner: RegressionCommandRunner = RegressionCommandRunner(),
        workspaceRoot: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.gitRunner = gitRunner
        self.commandRunner = commandRunner
        self.fileManager = fileManager
        if let workspaceRoot {
            self.workspaceRoot = workspaceRoot
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.workspaceRoot = support
                .appendingPathComponent("GitGatto", isDirectory: true)
                .appendingPathComponent("RegressionInvestigations", isDirectory: true)
                .appendingPathComponent("Worktrees", isDirectory: true)
        }
    }

    func prepare(
        repositoryURL: URL,
        goodRevision: String,
        badRevision: String,
        verificationCommand: String,
        mode: RegressionInvestigationMode
    ) async throws -> RegressionInvestigation {
        let command = verificationCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .automatic, command.isEmpty {
            throw RegressionInvestigationError.emptyVerificationCommand
        }
        let goodInput = goodRevision.trimmingCharacters(in: .whitespacesAndNewlines)
        let badInput = badRevision.trimmingCharacters(in: .whitespacesAndNewlines)
        let goodSHA = try await resolveCommit(goodInput, in: repositoryURL)
        let badSHA = try await resolveCommit(badInput, in: repositoryURL)
        guard goodSHA != badSHA else { throw RegressionInvestigationError.identicalBoundary }

        let ancestry = try await gitRunner.run(
            at: repositoryURL,
            arguments: ["merge-base", "--is-ancestor", goodSHA, badSHA],
            acceptedExitCodes: [0, 1]
        )
        guard ancestry.exitCode == 0 else {
            throw RegressionInvestigationError.goodRevisionIsNotAncestor
        }

        let head = try await gitText(["rev-parse", "HEAD"], at: repositoryURL)
        let branch = await sourceBranch(in: repositoryURL)
        let id = UUID()
        let worktreeURL = workspaceRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        var addedWorktree = false
        do {
            _ = try await gitRunner.run(
                at: repositoryURL,
                arguments: ["worktree", "add", "--detach", "--", worktreeURL.path, badSHA]
            )
            addedWorktree = true
            let start = try await gitRunner.run(
                at: worktreeURL,
                arguments: ["bisect", "start", badSHA, goodSHA, "--"],
                acceptedExitCodes: [0, 1, 2]
            )
            let startOutput = Self.combined(start)
            let candidateCount = Int(
                try await gitText(["rev-list", "--count", "\(goodSHA)..\(badSHA)"], at: repositoryURL)
            ) ?? 0
            var investigation = RegressionInvestigation(
                id: id,
                repositoryPath: repositoryURL.standardizedFileURL.path,
                repositoryName: repositoryURL.lastPathComponent,
                sourceBranch: branch,
                sourceHeadSHA: head,
                goodRevision: goodInput,
                badRevision: badInput,
                goodSHA: goodSHA,
                badSHA: badSHA,
                verificationCommand: command,
                mode: mode,
                status: mode == .automatic ? .running : .awaitingManualVerdict,
                workspacePath: worktreeURL.path,
                candidateCount: candidateCount
            )

            if let culpritSHA = Self.firstBadCommitSHA(in: startOutput) {
                investigation = try await finishWithCulprit(culpritSHA, investigation: investigation)
            } else {
                investigation.currentCommit = try await commitEvidence(at: "HEAD", in: worktreeURL)
                investigation.updatedAt = Date()
            }
            return investigation
        } catch {
            if addedWorktree {
                _ = try? await gitRunner.run(
                    at: repositoryURL,
                    arguments: ["worktree", "remove", "--force", "--", worktreeURL.path],
                    acceptedExitCodes: [0, 1, 128]
                )
            }
            try? fileManager.removeItem(at: worktreeURL)
            throw error
        }
    }

    func runAutomatic(
        _ source: RegressionInvestigation,
        onUpdate: UpdateHandler
    ) async throws -> RegressionInvestigation {
        var investigation = source
        guard investigation.mode == .automatic else {
            throw RegressionInvestigationError.manualVerdictUnavailable
        }
        guard let workspace = investigation.workspaceURL,
              fileManager.fileExists(atPath: workspace.path) else {
            throw RegressionInvestigationError.workspaceMissing
        }
        investigation.status = .running
        investigation.errorMessage = nil
        investigation.updatedAt = Date()
        await onUpdate(investigation)

        while investigation.status == .running {
            try Task.checkCancellation()
            let commit = try await commitEvidence(at: "HEAD", in: workspace)
            investigation.currentCommit = commit
            investigation.updatedAt = Date()
            await onUpdate(investigation)

            let startedAt = Date()
            let result = try await commandRunner.runShell(
                command: investigation.verificationCommand,
                at: workspace
            )
            try Task.checkCancellation()
            let verdict: RegressionVerdict
            switch result.exitCode {
            case 0:
                verdict = .good
            case 125:
                verdict = .skipped
            case 1...124:
                verdict = .bad
            default:
                throw RegressionInvestigationError.commandFailed(
                    result.exitCode,
                    Self.bounded(result.combinedOutput)
                )
            }
            let probe = RegressionProbe(
                commit: commit,
                verdict: verdict,
                exitCode: result.exitCode,
                duration: Date().timeIntervalSince(startedAt),
                output: Self.evidenceOutput(result.combinedOutput)
            )
            investigation = try await advance(investigation, with: probe, at: workspace)
            await onUpdate(investigation)
        }
        return investigation
    }

    func recordManual(
        _ verdict: RegressionVerdict,
        in source: RegressionInvestigation
    ) async throws -> RegressionInvestigation {
        guard source.mode == .manual,
              source.status == .awaitingManualVerdict else {
            throw RegressionInvestigationError.manualVerdictUnavailable
        }
        guard let workspace = source.workspaceURL,
              fileManager.fileExists(atPath: workspace.path) else {
            throw RegressionInvestigationError.workspaceMissing
        }
        let commit = try await commitEvidence(at: "HEAD", in: workspace)
        let probe = RegressionProbe(
            commit: commit,
            verdict: verdict,
            exitCode: nil,
            duration: 0,
            output: ""
        )
        return try await advance(source, with: probe, at: workspace)
    }

    func pause(_ source: RegressionInvestigation) -> RegressionInvestigation {
        var investigation = source
        guard investigation.status == .running else { return investigation }
        investigation.status = .paused
        investigation.updatedAt = Date()
        return investigation
    }

    func resume(_ source: RegressionInvestigation) throws -> RegressionInvestigation {
        guard let workspace = source.workspaceURL,
              fileManager.fileExists(atPath: workspace.path) else {
            throw RegressionInvestigationError.workspaceMissing
        }
        var investigation = source
        investigation.status = source.mode == .automatic ? .running : .awaitingManualVerdict
        investigation.errorMessage = nil
        investigation.updatedAt = Date()
        return investigation
    }

    func markFailed(
        _ source: RegressionInvestigation,
        message: String
    ) -> RegressionInvestigation {
        var investigation = source
        investigation.status = .failed
        investigation.errorMessage = message
        investigation.updatedAt = Date()
        return investigation
    }

    func prepareFix(_ source: RegressionInvestigation) async throws -> RegressionInvestigation {
        guard source.culprit != nil else { throw RegressionInvestigationError.culpritMissing }
        guard let workspace = source.workspaceURL,
              fileManager.fileExists(atPath: workspace.path) else {
            throw RegressionInvestigationError.workspaceMissing
        }
        _ = try await gitRunner.run(
            at: workspace,
            arguments: ["bisect", "reset"],
            acceptedExitCodes: [0, 1, 128]
        )
        _ = try await gitRunner.run(at: workspace, arguments: ["switch", "--detach", source.badSHA])
        let branchSuffix = source.culprit?.shortSHA ?? String(source.id.uuidString.prefix(7))
        let branch = "gitgatto/regression-\(branchSuffix)"
        _ = try await gitRunner.run(at: workspace, arguments: ["switch", "-c", branch])
        var investigation = source
        investigation.status = .agentFixing
        investigation.fixBranch = branch
        investigation.fixVerification = nil
        investigation.errorMessage = nil
        investigation.updatedAt = Date()
        return investigation
    }

    func markAgentFixCompleted(
        _ source: RegressionInvestigation,
        summary: String
    ) -> RegressionInvestigation {
        var investigation = source
        investigation.status = .fixReady
        investigation.agentSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        investigation.updatedAt = Date()
        return investigation
    }

    func verifyFix(_ source: RegressionInvestigation) async throws -> RegressionInvestigation {
        guard !source.verificationCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RegressionInvestigationError.emptyVerificationCommand
        }
        guard let workspace = source.workspaceURL,
              fileManager.fileExists(atPath: workspace.path) else {
            throw RegressionInvestigationError.workspaceMissing
        }
        var investigation = source
        investigation.status = .verifyingFix
        investigation.updatedAt = Date()
        let startedAt = Date()
        let result = try await commandRunner.runShell(
            command: source.verificationCommand,
            at: workspace
        )
        investigation.fixVerification = RegressionFixVerification(
            passed: result.exitCode == 0,
            exitCode: result.exitCode,
            duration: Date().timeIntervalSince(startedAt),
            output: Self.evidenceOutput(result.combinedOutput),
            completedAt: Date()
        )
        investigation.status = result.exitCode == 0 ? .fixVerified : .fixReady
        investigation.errorMessage = result.exitCode == 0
            ? nil
            : L10n.format("regression.error.verification_exit", result.exitCode)
        investigation.updatedAt = Date()
        return investigation
    }

    func recordManualFixVerification(
        _ source: RegressionInvestigation,
        passed: Bool
    ) -> RegressionInvestigation {
        var investigation = source
        investigation.fixVerification = RegressionFixVerification(
            passed: passed,
            exitCode: nil,
            duration: 0,
            output: "",
            completedAt: Date()
        )
        investigation.status = passed ? .fixVerified : .fixReady
        investigation.errorMessage = passed ? nil : L10n.text("regression.verification.failed")
        investigation.updatedAt = Date()
        return investigation
    }

    func publishFix(
        _ source: RegressionInvestigation,
        title: String,
        body: String
    ) async throws -> RegressionInvestigation {
        guard source.fixVerification?.passed == true else {
            throw RegressionInvestigationError.fixNotVerified
        }
        guard let branch = source.fixBranch,
              let workspace = source.workspaceURL,
              fileManager.fileExists(atPath: workspace.path) else {
            throw RegressionInvestigationError.workspaceMissing
        }
        guard let baseBranch = source.sourceBranch, !baseBranch.isEmpty else {
            throw RegressionInvestigationError.sourceBranchMissing
        }

        var investigation = source
        investigation.status = .publishing
        investigation.errorMessage = nil
        investigation.updatedAt = Date()

        let status = try await gitText(["status", "--porcelain=v1"], at: workspace)
        if !status.isEmpty {
            _ = try await gitRunner.run(at: workspace, arguments: ["add", "-A"])
            let staged = try await gitRunner.run(
                at: workspace,
                arguments: ["diff", "--cached", "--quiet"],
                acceptedExitCodes: [0, 1]
            )
            guard staged.exitCode == 1 else { throw RegressionInvestigationError.noFixChanges }
            let message = title.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await gitRunner.run(
                at: workspace,
                arguments: ["commit", "-m", message.isEmpty ? "fix: resolve regression" : message]
            )
        } else {
            let head = try await gitText(["rev-parse", "HEAD"], at: workspace)
            guard head != source.badSHA else { throw RegressionInvestigationError.noFixChanges }
        }

        let commitSHA = try await gitText(["rev-parse", "HEAD"], at: workspace)
        _ = try await gitRunner.run(
            at: workspace,
            arguments: ["push", "--set-upstream", "origin", branch]
        )

        let prTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let prBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let pr = try await commandRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "gh", "pr", "create",
                "--head", branch,
                "--base", baseBranch,
                "--title", prTitle.isEmpty ? "Fix regression \(source.culprit?.shortSHA ?? "")" : prTitle,
                "--body", prBody
            ],
            at: workspace
        )
        guard pr.exitCode == 0 else {
            throw RegressionInvestigationError.commandFailed(pr.exitCode, pr.combinedOutput)
        }
        let url = pr.combinedOutput
            .split(whereSeparator: \Character.isWhitespace)
            .lazy
            .compactMap { URL(string: String($0)) }
            .first { $0.scheme == "https" }
        guard let url else {
            throw RegressionInvestigationError.commandFailed(-1, pr.combinedOutput)
        }

        investigation.status = .completed
        investigation.fixCommitSHA = commitSHA
        investigation.pullRequestURL = url
        investigation.updatedAt = Date()
        return investigation
    }

    func cleanup(_ source: RegressionInvestigation) async throws -> RegressionInvestigation {
        var investigation = source
        if let workspace = source.workspaceURL {
            if fileManager.fileExists(atPath: workspace.path) {
                _ = try? await gitRunner.run(
                    at: workspace,
                    arguments: ["bisect", "reset"],
                    acceptedExitCodes: [0, 1, 128]
                )
            }
            _ = try await gitRunner.run(
                at: source.repositoryURL,
                arguments: ["worktree", "remove", "--force", "--", workspace.path],
                acceptedExitCodes: [0, 1, 128]
            )
            _ = try await gitRunner.run(
                at: source.repositoryURL,
                arguments: ["worktree", "prune"],
                acceptedExitCodes: [0, 1]
            )
        }
        investigation.workspacePath = nil
        if !investigation.status.isTerminal {
            investigation.status = .cancelled
        }
        investigation.updatedAt = Date()
        return investigation
    }

    static func firstBadCommitSHA(in output: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?m)^([0-9a-fA-F]{40}) is the first bad commit"#
        ) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              let shaRange = Range(match.range(at: 1), in: output) else { return nil }
        return String(output[shaRange]).lowercased()
    }

    static func agentPrompt(for investigation: RegressionInvestigation) -> String {
        let culprit = investigation.culprit
        let recentEvidence = investigation.probes.suffix(6).map { probe in
            "- \(probe.commit.shortSHA) \(probe.verdict.rawValue): \(probe.commit.subject)"
        }.joined(separator: "\n")
        return """
        Fix the verified Git regression in this isolated worktree. Make the smallest source change that restores the failing behavior. Do not commit, push, or create a pull request.

        Verification command:
        \(investigation.verificationCommand)

        First bad commit:
        \(culprit?.sha ?? "unknown") \(culprit?.subject ?? "")

        Bisect evidence:
        \(recentEvidence)

        Inspect the culprit diff and current code, implement the fix, and run focused checks. Preserve unrelated changes.
        """
    }

    private func advance(
        _ source: RegressionInvestigation,
        with probe: RegressionProbe,
        at workspace: URL
    ) async throws -> RegressionInvestigation {
        var investigation = source
        investigation.probes.append(probe)
        let result = try await gitRunner.run(
            at: workspace,
            arguments: ["bisect", probe.verdict.gitArgument],
            acceptedExitCodes: [0, 1, 2, 128]
        )
        let output = Self.combined(result)
        if let culpritSHA = Self.firstBadCommitSHA(in: output) {
            investigation = try await finishWithCulprit(culpritSHA, investigation: investigation)
        } else if output.localizedCaseInsensitiveContains("only 'skip'ped commits left")
                    || output.localizedCaseInsensitiveContains("first bad commit could be any of") {
            investigation.status = .inconclusive
            investigation.bisectLog = try? await gitText(["bisect", "log"], at: workspace)
            investigation.currentCommit = nil
        } else if result.exitCode != 0 {
            throw RegressionInvestigationError.commandFailed(result.exitCode, output)
        } else {
            investigation.status = investigation.mode == .automatic ? .running : .awaitingManualVerdict
            investigation.currentCommit = try await commitEvidence(at: "HEAD", in: workspace)
        }
        investigation.updatedAt = Date()
        return investigation
    }

    private func finishWithCulprit(
        _ sha: String,
        investigation source: RegressionInvestigation
    ) async throws -> RegressionInvestigation {
        guard let workspace = source.workspaceURL else {
            throw RegressionInvestigationError.workspaceMissing
        }
        var investigation = source
        let culprit = try await commitEvidence(at: sha, in: workspace)
        let summary = try await gitText(
            ["show", "--stat", "--format=%H%n%an%n%aI%n%s", sha],
            at: workspace
        )
        investigation.status = .culpritFound
        investigation.culprit = culprit
        investigation.currentCommit = culprit
        investigation.culpritSummary = Self.bounded(summary)
        investigation.bisectLog = try? await gitText(["bisect", "log"], at: workspace)
        investigation.errorMessage = nil
        investigation.updatedAt = Date()
        return investigation
    }

    private func resolveCommit(_ revision: String, in repository: URL) async throws -> String {
        guard !revision.isEmpty else { throw RegressionInvestigationError.invalidRevision(revision) }
        do {
            return try await gitText(
                ["rev-parse", "--verify", "--end-of-options", "\(revision)^{commit}"],
                at: repository
            )
        } catch {
            throw RegressionInvestigationError.invalidRevision(revision)
        }
    }

    private func sourceBranch(in repository: URL) async -> String? {
        if let branch = try? await gitText(
            ["symbolic-ref", "--quiet", "--short", "HEAD"],
            at: repository,
            acceptedExitCodes: [0, 1]
        ), !branch.isEmpty {
            return branch
        }
        if let remoteHead = try? await gitText(
            ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"],
            at: repository,
            acceptedExitCodes: [0, 1]
        ), !remoteHead.isEmpty {
            return remoteHead.replacingOccurrences(of: "origin/", with: "")
        }
        for candidate in ["main", "master"] {
            if let result = try? await gitRunner.run(
                at: repository,
                arguments: ["show-ref", "--verify", "--quiet", "refs/heads/\(candidate)"],
                acceptedExitCodes: [0, 1]
            ), result.exitCode == 0 {
                return candidate
            }
        }
        return nil
    }

    private func commitEvidence(at revision: String, in repository: URL) async throws -> RegressionCommitEvidence {
        let output = try await gitText(
            ["show", "-s", "--format=%H%x1f%h%x1f%an%x1f%aI%x1f%s", revision],
            at: repository
        )
        let fields = output.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 5 else {
            throw RegressionInvestigationError.invalidRevision(revision)
        }
        return RegressionCommitEvidence(
            sha: fields[0],
            shortSHA: fields[1],
            subject: fields[4],
            author: fields[2],
            authoredAt: ISO8601DateFormatter().date(from: fields[3])
        )
    }

    private func gitText(
        _ arguments: [String],
        at repository: URL,
        acceptedExitCodes: Set<Int32> = [0]
    ) async throws -> String {
        let result = try await gitRunner.run(
            at: repository,
            arguments: arguments,
            acceptedExitCodes: acceptedExitCodes
        )
        return Self.combined(result).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func combined(_ result: GitCommandResult) -> String {
        let output = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let error = String(decoding: result.errorOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return [output, error].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func bounded(_ value: String, limit: Int = 64 * 1_024) -> String {
        guard value.utf8.count > limit else { return value }
        let suffix = value.utf8.suffix(limit)
        return "…\n" + String(decoding: suffix, as: UTF8.self)
    }

    static func evidenceOutput(_ value: String) -> String {
        var result = value
        let replacements: [(String, String)] = [
            (#"(?i)(https?://)[^/@\s]+@"#, "$1***@"),
            (#"(?i)\b(?:gh[pousr]|github_pat)_[A-Za-z0-9_]+\b"#, "***"),
            (#"(?i)(authorization:\s*(?:bearer|token)\s+)[^\s]+"#, "$1***")
        ]
        for (pattern, replacement) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: replacement
            )
        }
        return bounded(result)
    }
}

private final class RegressionProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func install(_ process: Process) -> Bool {
        lock.withLock {
            self.process = process
            return cancelled
        }
    }

    func cancel() {
        let process = lock.withLock {
            cancelled = true
            return self.process
        }
        if process?.isRunning == true { process?.terminate() }
    }

    func clear() {
        lock.withLock { process = nil }
    }
}

private final class RegressionDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var value: Data { lock.withLock { data } }

    func set(_ value: Data) {
        lock.withLock { data = value }
    }
}
