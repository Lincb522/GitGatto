import Foundation

enum GitRepositoryServiceError: LocalizedError, Sendable {
    case pushFailedAfterCommit(GitFailureDetails)

    var failureDetails: GitFailureDetails {
        switch self {
        case let .pushFailedAfterCommit(details): details
        }
    }

    var errorDescription: String? {
        switch self {
        case let .pushFailedAfterCommit(details):
            "The commit was created, but the push failed: \(details.message)"
        }
    }
}

protocol GitRepositoryServing: Sendable {
    func loadRepository(at selectedURL: URL) async throws -> RepositorySnapshot
    func loadLiveState(at repositoryURL: URL) async throws -> RepositoryLiveState
    func fetchRemoteTracking(in repositoryURL: URL) async throws
    func diff(for change: WorkingTreeChange, in repositoryURL: URL) async throws -> DiffDocument
    func diff(for commit: CommitRecord, in repositoryURL: URL) async throws -> DiffDocument
    func stagedDiff(in repositoryURL: URL) async throws -> String
    func stage(paths: [String], in repositoryURL: URL) async throws
    func unstage(paths: [String], in repositoryURL: URL) async throws
    func switchBranch(to branchName: String, in repositoryURL: URL) async throws
    func discard(_ change: WorkingTreeChange, in repositoryURL: URL) async throws
    func ignore(path: String, scope: GitIgnoreScope, in repositoryURL: URL) async throws
    func commit(message: String, in repositoryURL: URL) async throws
    func commitAndPush(message: String, in repositoryURL: URL) async throws
    func pull(in repositoryURL: URL) async throws
    func push(in repositoryURL: URL) async throws
}

actor GitRepositoryService: GitRepositoryServing {
    private let runner: GitCommandRunner

    init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    func loadRepository(at selectedURL: URL) async throws -> RepositorySnapshot {
        let rootResult = try await runner.run(at: selectedURL, arguments: ["rev-parse", "--show-toplevel"])
        let rootPath = rootResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)

        let branchResult = try await runner.run(at: rootURL, arguments: ["branch", "--show-current"])
        var branchName = branchResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if branchName.isEmpty {
            let head = try await runner.run(at: rootURL, arguments: ["rev-parse", "--short", "HEAD"])
            branchName = head.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let statusResult = try await runner.run(
            at: rootURL,
            arguments: ["status", "--porcelain=v1", "-z", "--untracked-files=all"]
        )

        let commitResult = try await runner.run(
            at: rootURL,
            arguments: ["log", "-n", "100", "--date=iso-strict", "--pretty=format:%H%x1f%h%x1f%an%x1f%ad%x1f%s%x1e"],
            acceptedExitCodes: [0, 128]
        )

        let branchListResult = try await runner.run(
            at: rootURL,
            arguments: ["for-each-ref", "--format=%(refname:short)%00%(objectname:short)%00%(upstream:short)%00", "refs/heads"]
        )

        let upstreamResult = try await runner.run(
            at: rootURL,
            arguments: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            acceptedExitCodes: [0, 128]
        )
        let upstreamName = upstreamResult.exitCode == 0
            ? upstreamResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        var ahead = 0
        var behind = 0
        if upstreamName != nil {
            let counts = try await runner.run(
                at: rootURL,
                arguments: ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
                acceptedExitCodes: [0, 128]
            )
            if counts.exitCode == 0 {
                let values = counts.text.split(whereSeparator: \Character.isWhitespace).compactMap { Int($0) }
                if values.count == 2 {
                    behind = values[0]
                    ahead = values[1]
                }
            }
        }

        return RepositorySnapshot(
            rootURL: rootURL,
            branchName: branchName,
            upstreamName: upstreamName,
            aheadCount: ahead,
            behindCount: behind,
            changes: GitParsers.status(from: statusResult.output),
            commits: GitParsers.commits(from: commitResult.text),
            branches: GitParsers.branches(from: branchListResult.output, currentBranch: branchName)
        )
    }

    func loadLiveState(at repositoryURL: URL) async throws -> RepositoryLiveState {
        let branchResult = try await runner.run(at: repositoryURL, arguments: ["branch", "--show-current"])
        var branchName = branchResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if branchName.isEmpty {
            let head = try await runner.run(at: repositoryURL, arguments: ["rev-parse", "--short", "HEAD"])
            branchName = head.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let statusResult = try await runner.run(
            at: repositoryURL,
            arguments: ["status", "--porcelain=v1", "-z", "--untracked-files=all"]
        )
        let upstreamResult = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            acceptedExitCodes: [0, 128]
        )
        let upstreamName = upstreamResult.exitCode == 0
            ? upstreamResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        var ahead = 0
        var behind = 0
        if upstreamName != nil {
            let counts = try await runner.run(
                at: repositoryURL,
                arguments: ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
                acceptedExitCodes: [0, 128]
            )
            if counts.exitCode == 0 {
                let values = counts.text.split(whereSeparator: \Character.isWhitespace).compactMap { Int($0) }
                if values.count == 2 {
                    behind = values[0]
                    ahead = values[1]
                }
            }
        }

        return RepositoryLiveState(
            branchName: branchName,
            upstreamName: upstreamName,
            aheadCount: ahead,
            behindCount: behind,
            changes: GitParsers.status(from: statusResult.output)
        )
    }

    func fetchRemoteTracking(in repositoryURL: URL) async throws {
        let upstream = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            acceptedExitCodes: [0, 128]
        )
        guard upstream.exitCode == 0 else { return }
        let upstreamName = upstream.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let remote = upstreamName.split(separator: "/", maxSplits: 1).first, !remote.isEmpty else { return }
        _ = try await runner.run(
            at: repositoryURL,
            arguments: ["fetch", "--quiet", "--no-tags", String(remote)]
        )
    }

    func diff(for change: WorkingTreeChange, in repositoryURL: URL) async throws -> DiffDocument {
        let result: GitCommandResult
        if change.isStaged {
            result = try await runner.run(
                at: repositoryURL,
                arguments: ["diff", "--cached", "--no-color", "--unified=4", "--", change.path]
            )
        } else if change.workTreeStatus == .untracked {
            result = try await runner.run(
                at: repositoryURL,
                arguments: ["diff", "--no-index", "--no-color", "--unified=4", "/dev/null", change.path],
                acceptedExitCodes: [0, 1]
            )
        } else {
            result = try await runner.run(
                at: repositoryURL,
                arguments: ["diff", "--no-color", "--unified=4", "--", change.path]
            )
        }
        return GitParsers.diff(from: result.text, path: change.path)
    }

    func diff(for commit: CommitRecord, in repositoryURL: URL) async throws -> DiffDocument {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["show", "--format=", "--no-color", "--unified=4", commit.hash]
        )
        return GitParsers.diff(from: result.text, path: commit.shortHash)
    }

    func stagedDiff(in repositoryURL: URL) async throws -> String {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["diff", "--cached", "--no-color", "--no-ext-diff", "--unified=4"]
        )
        return result.text
    }

    func stage(paths: [String], in repositoryURL: URL) async throws {
        guard !paths.isEmpty else { return }
        let currentChanges = try await changes(at: paths, in: repositoryURL)
        let unstagedPaths = Set(
            currentChanges
                .filter { $0.workTreeStatus != .unmodified }
                .map(\.path)
        )
        let pathsToStage = paths.filter { unstagedPaths.contains($0) }
        guard !pathsToStage.isEmpty else { return }
        _ = try await runner.run(at: repositoryURL, arguments: ["add", "--"] + pathsToStage)
    }

    func unstage(paths: [String], in repositoryURL: URL) async throws {
        guard !paths.isEmpty else { return }
        let currentChanges = try await changes(at: paths, in: repositoryURL)
        let stagedPaths = Set(currentChanges.filter(\.isStaged).map(\.path))
        let pathsToUnstage = paths.filter { stagedPaths.contains($0) }
        guard !pathsToUnstage.isEmpty else { return }
        _ = try await runner.run(at: repositoryURL, arguments: ["reset", "--"] + pathsToUnstage)
    }

    func switchBranch(to branchName: String, in repositoryURL: URL) async throws {
        _ = try await runner.run(
            at: repositoryURL,
            arguments: ["switch", "--no-guess", branchName]
        )
    }

    func discard(_ change: WorkingTreeChange, in repositoryURL: URL) async throws {
        let paths = [change.path, change.originalPath].compactMap { $0 }
        var pathsInHead: [String] = []
        var pathsOutsideHead: [String] = []

        for path in paths {
            let result = try await runner.run(
                at: repositoryURL,
                arguments: ["cat-file", "-e", "HEAD:\(path)"],
                acceptedExitCodes: [0, 128]
            )
            if result.exitCode == 0 {
                pathsInHead.append(path)
            } else {
                pathsOutsideHead.append(path)
            }
        }

        if !pathsInHead.isEmpty {
            _ = try await runner.run(
                at: repositoryURL,
                arguments: ["restore", "--source=HEAD", "--staged", "--worktree", "--"] + pathsInHead
            )
        }

        if !pathsOutsideHead.isEmpty {
            _ = try await runner.run(
                at: repositoryURL,
                arguments: ["rm", "--cached", "--ignore-unmatch", "--"] + pathsOutsideHead,
                acceptedExitCodes: [0, 128]
            )
            for path in pathsOutsideHead {
                let fileURL = repositoryURL.appendingPathComponent(path)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    _ = try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                }
            }
        }
    }

    func ignore(path: String, scope: GitIgnoreScope, in repositoryURL: URL) async throws {
        let pattern: String
        switch scope {
        case .file:
            pattern = "/\(Self.escapeGitIgnore(path))"
        case let .folder(folderPath):
            guard !folderPath.isEmpty else { return }
            pattern = "/\(Self.escapeGitIgnore(folderPath))/"
        case .fileExtension:
            let fileExtension = (path as NSString).pathExtension
            guard !fileExtension.isEmpty else { return }
            pattern = "*.\(Self.escapeGitIgnore(fileExtension))"
        }

        let ignoreURL = repositoryURL.appendingPathComponent(".gitignore")
        var data = (try? Data(contentsOf: ignoreURL)) ?? Data()
        let existing = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard !existing.contains(pattern) else { return }

        if let last = data.last, last != 0x0A {
            data.append(0x0A)
        }
        data.append(contentsOf: pattern.utf8)
        data.append(0x0A)
        try data.write(to: ignoreURL, options: .atomic)
    }

    func commit(message: String, in repositoryURL: URL) async throws {
        _ = try await runner.run(at: repositoryURL, arguments: ["commit", "-m", message])
    }

    func commitAndPush(message: String, in repositoryURL: URL) async throws {
        try await commit(message: message, in: repositoryURL)
        do {
            try await push(in: repositoryURL)
        } catch let error as GitCommandError {
            throw GitRepositoryServiceError.pushFailedAfterCommit(error.failureDetails)
        } catch {
            throw GitRepositoryServiceError.pushFailedAfterCommit(
                GitFailureDetails(
                    arguments: ["push"],
                    exitCode: nil,
                    message: error.localizedDescription
                )
            )
        }
    }

    func pull(in repositoryURL: URL) async throws {
        _ = try await runner.run(at: repositoryURL, arguments: ["pull", "--ff-only"])
    }

    func push(in repositoryURL: URL) async throws {
        let upstream = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            acceptedExitCodes: [0, 128]
        )
        if upstream.exitCode == 0 {
            _ = try await runner.run(at: repositoryURL, arguments: ["push"])
            return
        }

        let branchResult = try await runner.run(at: repositoryURL, arguments: ["branch", "--show-current"])
        let branch = branchResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteResult = try await runner.run(at: repositoryURL, arguments: ["remote"])
        let remotes = remoteResult.text.split(whereSeparator: \Character.isNewline).map(String.init)
        guard !branch.isEmpty, let remote = remotes.contains("origin") ? "origin" : remotes.first else {
            _ = try await runner.run(at: repositoryURL, arguments: ["push"])
            return
        }
        _ = try await runner.run(
            at: repositoryURL,
            arguments: ["push", "--set-upstream", remote, branch]
        )
    }

    private func changes(at paths: [String], in repositoryURL: URL) async throws -> [WorkingTreeChange] {
        let status = try await runner.run(
            at: repositoryURL,
            arguments: ["status", "--porcelain=v1", "-z", "--untracked-files=all", "--"] + paths
        )
        return GitParsers.status(from: status.output)
    }

    private static func escapeGitIgnore(_ value: String) -> String {
        let specialCharacters: Set<Character> = ["\\", " ", "*", "?", "[", "]", "#", "!"]
        return value.reduce(into: "") { result, character in
            if specialCharacters.contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
    }
}
