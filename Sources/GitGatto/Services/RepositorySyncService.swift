import Foundation

protocol RepositorySyncServing: Sendable {
    func status(for repositoryURL: URL) async -> RepositorySyncStatus
    func perform(_ operation: RepositoryBatchOperation, in repositoryURL: URL) async -> RepositoryBatchResult
}

struct RepositorySyncService: RepositorySyncServing {
    private let runner: GitCommandRunner

    init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    func status(for repositoryURL: URL) async -> RepositorySyncStatus {
        do {
            let branchOutput = try await runner.run(
                at: repositoryURL,
                arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"],
                acceptedExitCodes: [0, 1]
            )
            let headOutput = try await runner.run(
                at: repositoryURL,
                arguments: ["rev-parse", "--short", "HEAD"],
                acceptedExitCodes: [0, 128]
            )
            let upstreamOutput = try await runner.run(
                at: repositoryURL,
                arguments: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
                acceptedExitCodes: [0, 128]
            )
            let changesOutput = try await runner.run(
                at: repositoryURL,
                arguments: ["status", "--porcelain=v1", "--untracked-files=normal"]
            )
            let lastCommitOutput = try await runner.run(
                at: repositoryURL,
                arguments: ["log", "-1", "--format=%ct"],
                acceptedExitCodes: [0, 128]
            )
            let remotesOutput = try await runner.run(
                at: repositoryURL,
                arguments: ["remote"]
            )
            let branchName = branchOutput.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let shortHead = headOutput.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let upstream = upstreamOutput.exitCode == 0
                ? upstreamOutput.text.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            let changes = changesOutput.text.split(whereSeparator: \Character.isNewline).map(String.init)
            let conflicts = changes.filter(Self.isConflictStatus).count
            let divergence = if let upstream, !upstream.isEmpty {
                try await aheadBehind(repositoryURL: repositoryURL, upstream: upstream)
            } else {
                (ahead: 0, behind: 0)
            }
            let timestamp = TimeInterval(lastCommitOutput.text.trimmingCharacters(in: .whitespacesAndNewlines))

            return RepositorySyncStatus(
                repositoryURL: repositoryURL.standardizedFileURL,
                branch: branchName.isEmpty ? "@\(shortHead)" : branchName,
                upstream: upstream?.isEmpty == false ? upstream : nil,
                hasRemote: !remotesOutput.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                aheadCount: divergence.ahead,
                behindCount: divergence.behind,
                changedFileCount: changes.count,
                conflictCount: conflicts,
                lastCommitAt: timestamp.map(Date.init(timeIntervalSince1970:)),
                errorMessage: nil
            )
        } catch is CancellationError {
            return .unavailable(repositoryURL: repositoryURL, message: CancellationError().localizedDescription)
        } catch {
            return .unavailable(repositoryURL: repositoryURL, message: error.localizedDescription)
        }
    }

    func perform(_ operation: RepositoryBatchOperation, in repositoryURL: URL) async -> RepositoryBatchResult {
        do {
            switch operation {
            case .fetch:
                _ = try await runner.run(
                    at: repositoryURL,
                    arguments: ["fetch", "--all", "--prune", "--tags"]
                )
            case .pull:
                let current = await status(for: repositoryURL)
                guard current.supports(.pull) else {
                    throw RepositorySyncError.pullRequiresCleanFastForward
                }
                _ = try await runner.run(at: repositoryURL, arguments: ["pull", "--ff-only"])
            case .push:
                let current = await status(for: repositoryURL)
                guard current.supports(.push) else {
                    throw RepositorySyncError.pushUnavailable
                }
                _ = try await runner.run(at: repositoryURL, arguments: ["push"])
            }
            return RepositoryBatchResult(
                repositoryURL: repositoryURL,
                operation: operation,
                succeeded: true,
                message: nil
            )
        } catch is CancellationError {
            return RepositoryBatchResult(
                repositoryURL: repositoryURL,
                operation: operation,
                succeeded: false,
                message: CancellationError().localizedDescription
            )
        } catch {
            return RepositoryBatchResult(
                repositoryURL: repositoryURL,
                operation: operation,
                succeeded: false,
                message: error.localizedDescription
            )
        }
    }

    private func aheadBehind(repositoryURL: URL, upstream: String) async throws -> (ahead: Int, behind: Int) {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-list", "--left-right", "--count", "HEAD...\(upstream)"]
        )
        let fields = result.text.split(whereSeparator: \Character.isWhitespace)
        guard fields.count == 2,
              let ahead = Int(fields[0]),
              let behind = Int(fields[1]) else {
            throw RepositorySyncError.invalidDivergence
        }
        return (ahead, behind)
    }

    private static func isConflictStatus(_ line: String) -> Bool {
        guard line.count >= 2 else { return false }
        let status = String(line.prefix(2))
        return ["DD", "AU", "UD", "UA", "DU", "AA", "UU"].contains(status)
    }
}

enum RepositorySyncError: LocalizedError, Sendable {
    case invalidDivergence
    case pullRequiresCleanFastForward
    case pushUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidDivergence:
            L10n.text("sync.error.invalid_divergence")
        case .pullRequiresCleanFastForward:
            L10n.text("sync.error.pull_requires_clean")
        case .pushUnavailable:
            L10n.text("sync.error.push_unavailable")
        }
    }
}
