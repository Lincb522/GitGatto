import Foundation

protocol GitWorktreeServing: Sendable {
    func worktrees(in repositoryURL: URL) async throws -> [GitWorktreeRecord]
    func createWorktree(
        branch: String,
        startPoint: String,
        destination: URL,
        in repositoryURL: URL
    ) async throws
    func removeWorktree(_ worktree: GitWorktreeRecord, force: Bool, in repositoryURL: URL) async throws
}

enum GitWorktreeServiceError: LocalizedError, Sendable {
    case invalidBranch
    case destinationExists
    case cannotRemoveMainWorktree
    case worktreeNotRegistered

    var errorDescription: String? {
        switch self {
        case .invalidBranch:
            L10n.text("worktree.error.invalid_branch")
        case .destinationExists:
            L10n.text("worktree.error.destination_exists")
        case .cannotRemoveMainWorktree:
            L10n.text("worktree.error.main_remove")
        case .worktreeNotRegistered:
            L10n.text("worktree.error.not_registered")
        }
    }
}

actor GitWorktreeService: GitWorktreeServing {
    private let runner: GitCommandRunner

    init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    func worktrees(in repositoryURL: URL) async throws -> [GitWorktreeRecord] {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["worktree", "list", "--porcelain", "-z"]
        )
        let entries = Self.parsePorcelain(result.output)
        let runner = self.runner
        return try await withThrowingTaskGroup(of: (Int, GitWorktreeRecord).self) { group in
            for (index, entry) in entries.enumerated() {
                group.addTask {
                    let path = URL(fileURLWithPath: entry.path, isDirectory: true).standardizedFileURL
                    let statusResult = try await runner.run(
                        at: path,
                        arguments: ["status", "--porcelain=v1", "-z", "--branch", "--untracked-files=all"]
                    )
                    guard let status = GitParsers.statusSnapshot(from: statusResult.output) else {
                        throw GitCommandError(
                            arguments: ["status", "--porcelain=v1", "-z", "--branch", "--untracked-files=all"],
                            exitCode: statusResult.exitCode,
                            message: "Git did not return worktree status metadata."
                        )
                    }
                    return (
                        index,
                        GitWorktreeRecord(
                            path: path,
                            headHash: entry.headHash,
                            branch: entry.branch,
                            isMain: index == 0,
                            isLocked: entry.isLocked,
                            isPrunable: entry.isPrunable,
                            changesCount: status.changes.count,
                            aheadCount: status.aheadCount,
                            behindCount: status.behindCount
                        )
                    )
                }
            }
            var records: [(Int, GitWorktreeRecord)] = []
            for try await record in group {
                records.append(record)
            }
            return records.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    func createWorktree(
        branch: String,
        startPoint: String,
        destination: URL,
        in repositoryURL: URL
    ) async throws {
        let branch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let startPoint = startPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { throw GitWorktreeServiceError.invalidBranch }
        let validation = try await runner.run(
            at: repositoryURL,
            arguments: ["check-ref-format", "--branch", branch],
            acceptedExitCodes: [0, 1, 128]
        )
        guard validation.exitCode == 0 else { throw GitWorktreeServiceError.invalidBranch }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw GitWorktreeServiceError.destinationExists
        }

        let branchExists = try await runner.run(
            at: repositoryURL,
            arguments: ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"],
            acceptedExitCodes: [0, 1]
        ).exitCode == 0

        let arguments: [String]
        if branchExists {
            arguments = ["worktree", "add", "--", destination.path, branch]
        } else {
            arguments = [
                "worktree", "add", "-b", branch, "--", destination.path,
                startPoint.isEmpty ? "HEAD" : startPoint
            ]
        }
        _ = try await runner.run(at: repositoryURL, arguments: arguments)
    }

    func removeWorktree(
        _ worktree: GitWorktreeRecord,
        force: Bool,
        in repositoryURL: URL
    ) async throws {
        guard !worktree.isMain else { throw GitWorktreeServiceError.cannotRemoveMainWorktree }
        let list = try await runner.run(
            at: repositoryURL,
            arguments: ["worktree", "list", "--porcelain", "-z"]
        )
        let registered = Self.parsePorcelain(list.output).contains {
            URL(fileURLWithPath: $0.path, isDirectory: true).standardizedFileURL
                == worktree.path.standardizedFileURL
        }
        guard registered else { throw GitWorktreeServiceError.worktreeNotRegistered }
        var arguments = ["worktree", "remove"]
        if force { arguments.append("--force") }
        arguments.append(contentsOf: ["--", worktree.path.path])
        _ = try await runner.run(at: repositoryURL, arguments: arguments)
    }

    static func parsePorcelain(_ data: Data) -> [PorcelainEntry] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        var entries: [PorcelainEntry] = []
        var current: PorcelainEntry?

        for field in fields {
            if field.isEmpty {
                if let current, !current.path.isEmpty {
                    entries.append(current)
                }
                current = nil
                continue
            }
            if field.hasPrefix("worktree ") {
                if let current, !current.path.isEmpty { entries.append(current) }
                current = PorcelainEntry(path: String(field.dropFirst(9)))
            } else if field.hasPrefix("HEAD ") {
                current?.headHash = String(field.dropFirst(5))
            } else if field.hasPrefix("branch refs/heads/") {
                current?.branch = String(field.dropFirst(18))
            } else if field == "locked" || field.hasPrefix("locked ") {
                current?.isLocked = true
            } else if field == "prunable" || field.hasPrefix("prunable ") {
                current?.isPrunable = true
            }
        }
        if let current, !current.path.isEmpty { entries.append(current) }
        return entries
    }

    struct PorcelainEntry: Sendable, Equatable {
        var path: String
        var headHash = ""
        var branch: String?
        var isLocked = false
        var isPrunable = false
    }
}

protocol GitWorktreeAgentCoordinating: Sendable {
    func run(
        worktreeID: String,
        prompt: String,
        repositoryURL: URL,
        mode: CodexRunMode
    ) async throws -> CodexRunResult
    func cancel(worktreeID: String) async
}

actor GitWorktreeAgentCoordinator: GitWorktreeAgentCoordinating {
    private var services: [String: CodexService] = [:]

    func run(
        worktreeID: String,
        prompt: String,
        repositoryURL: URL,
        mode: CodexRunMode
    ) async throws -> CodexRunResult {
        let service = CodexService()
        services[worktreeID] = service
        defer { services[worktreeID] = nil }
        return try await service.run(prompt: prompt, context: [], in: repositoryURL, mode: mode)
    }

    func cancel(worktreeID: String) async {
        guard let service = services[worktreeID] else { return }
        await service.cancel()
        services[worktreeID] = nil
    }
}
