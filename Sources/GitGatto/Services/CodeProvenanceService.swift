import Foundation

protocol CodeProvenanceServing: Sendable {
    func trace(filePath: String, line: Int, in repositoryURL: URL) async throws -> CodeProvenanceReport
}

actor CodeProvenanceService: CodeProvenanceServing {
    private let gitRunner: GitCommandRunner
    private let processRunner: ExternalProcessRunner

    init(
        gitRunner: GitCommandRunner = GitCommandRunner(),
        processRunner: ExternalProcessRunner = ExternalProcessRunner()
    ) {
        self.gitRunner = gitRunner
        self.processRunner = processRunner
    }

    func trace(
        filePath: String,
        line: Int,
        in repositoryURL: URL
    ) async throws -> CodeProvenanceReport {
        let repository = repositoryURL.standardizedFileURL
        let path = try Self.safeRelativePath(filePath)
        guard line > 0 else { throw CodeProvenanceError.invalidLine }
        let fileURL = repository.appendingPathComponent(path).standardizedFileURL
        guard fileURL.path.hasPrefix(repository.path + "/"),
              FileManager.default.fileExists(atPath: fileURL.path)
        else { throw CodeProvenanceError.invalidPath }

        let blameResult = try await gitRunner.run(
            at: repository,
            arguments: ["blame", "--line-porcelain", "-L", "\(line),\(line)", "--", path]
        )
        let blame = blameResult.text
        guard let first = blame.split(separator: "\n").first,
              let hash = first.split(separator: " ").first.map(String.init),
              hash.count >= 7
        else { throw CodeProvenanceError.malformedGitOutput }
        guard Set(hash) != Set("0") else { throw CodeProvenanceError.lineNotCommitted }
        let sourceText = blame.split(separator: "\n", omittingEmptySubsequences: false)
            .first(where: { $0.hasPrefix("\t") })
            .map { String($0.dropFirst()) }
        let commit = try await commit(hash: hash, in: repository)

        guard let remote = try await remoteIdentity(in: repository) else {
            return CodeProvenanceReport(
                repositoryPath: repository.path,
                filePath: path,
                line: line,
                sourceText: sourceText,
                commit: commit,
                pullRequest: nil,
                issues: [],
                reviews: [],
                checks: [],
                remoteUnavailableReason: L10n.text("intelligence.provenance.remote.none")
            )
        }
        guard let gh = CommandExecutableLocator.find("gh") else {
            return CodeProvenanceReport(
                repositoryPath: repository.path,
                filePath: path,
                line: line,
                sourceText: sourceText,
                commit: commit,
                pullRequest: nil,
                issues: [],
                reviews: [],
                checks: [],
                remoteUnavailableReason: L10n.text("intelligence.provenance.remote.gh_missing")
            )
        }

        do {
            let pulls: [PullPayload] = try await api(
                ["repos/\(remote.fullName)/commits/\(hash)/pulls"],
                host: remote.host,
                executable: gh
            )
            let pullPayload = pulls.first(where: { $0.mergedAt != nil }) ?? pulls.first
            let pullRequest = pullPayload?.model
            async let reviews = loadReviews(
                pullNumber: pullPayload?.number,
                remote: remote,
                executable: gh
            )
            async let checks = loadChecks(hash: hash, remote: remote, executable: gh)
            let issueNumbers = Self.issueNumbers(
                in: [commit.subject, commit.body, pullPayload?.body ?? ""].joined(separator: "\n"),
                excluding: pullPayload?.number
            )
            async let issues = loadIssues(numbers: issueNumbers, remote: remote, executable: gh)
            return try await CodeProvenanceReport(
                repositoryPath: repository.path,
                filePath: path,
                line: line,
                sourceText: sourceText,
                commit: commit,
                pullRequest: pullRequest,
                issues: issues,
                reviews: reviews,
                checks: checks,
                remoteUnavailableReason: nil
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return CodeProvenanceReport(
                repositoryPath: repository.path,
                filePath: path,
                line: line,
                sourceText: sourceText,
                commit: commit,
                pullRequest: nil,
                issues: [],
                reviews: [],
                checks: [],
                remoteUnavailableReason: error.localizedDescription
            )
        }
    }

    private func commit(hash: String, in repositoryURL: URL) async throws -> CodeProvenanceCommit {
        let metadata = try await gitRunner.run(
            at: repositoryURL,
            arguments: ["show", "-s", "--format=%H%x00%h%x00%an%x00%aI%x00%s%x00%b", hash]
        ).output.split(separator: 0, omittingEmptySubsequences: false).map {
            String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .newlines)
        }
        guard metadata.count >= 6 else { throw CodeProvenanceError.malformedGitOutput }
        let pathsData = try await gitRunner.run(
            at: repositoryURL,
            arguments: ["diff-tree", "--root", "--no-commit-id", "--name-only", "-r", "-z", hash]
        ).output
        let paths = pathsData.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        return CodeProvenanceCommit(
            hash: metadata[0],
            shortHash: metadata[1],
            author: metadata[2],
            authoredAt: ISO8601DateFormatter().date(from: metadata[3]),
            subject: metadata[4],
            body: metadata[5].trimmingCharacters(in: .whitespacesAndNewlines),
            changedPaths: paths
        )
    }

    private func remoteIdentity(in repositoryURL: URL) async throws -> RemoteIdentity? {
        let result = try await gitRunner.run(
            at: repositoryURL,
            arguments: ["config", "--get", "remote.origin.url"],
            acceptedExitCodes: [0, 1]
        )
        guard result.exitCode == 0 else { return nil }
        return Self.parseRemote(result.text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func loadReviews(
        pullNumber: Int?,
        remote: RemoteIdentity,
        executable: URL
    ) async throws -> [CodeProvenanceReview] {
        guard let pullNumber else { return [] }
        let payloads: [ReviewPayload] = try await api(
            ["repos/\(remote.fullName)/pulls/\(pullNumber)/reviews"],
            host: remote.host,
            executable: executable
        )
        return payloads.map(\.model).sorted {
            ($0.submittedAt ?? .distantPast) < ($1.submittedAt ?? .distantPast)
        }
    }

    private func loadChecks(
        hash: String,
        remote: RemoteIdentity,
        executable: URL
    ) async throws -> [CodeProvenanceCheck] {
        let payload: ChecksPayload = try await api(
            ["repos/\(remote.fullName)/commits/\(hash)/check-runs"],
            host: remote.host,
            executable: executable
        )
        return payload.checkRuns.map(\.model)
    }

    private func loadIssues(
        numbers: [Int],
        remote: RemoteIdentity,
        executable: URL
    ) async throws -> [CodeProvenanceIssue] {
        try await withThrowingTaskGroup(of: CodeProvenanceIssue?.self) { group in
            for number in numbers.prefix(8) {
                group.addTask { [processRunner] in
                    do {
                        let arguments = Self.apiArguments(
                            path: "repos/\(remote.fullName)/issues/\(number)",
                            host: remote.host
                        )
                        let result = try await processRunner.run(
                            executable: executable,
                            arguments: arguments,
                            timeout: .seconds(20)
                        )
                        let payload = try JSONDecoder.github.decode(IssuePayload.self, from: result.standardOutput)
                        return payload.pullRequest == nil ? payload.model : nil
                    } catch {
                        return nil
                    }
                }
            }
            var issues: [CodeProvenanceIssue] = []
            for try await issue in group {
                if let issue { issues.append(issue) }
            }
            return issues.sorted { $0.number < $1.number }
        }
    }

    private func api<T: Decodable>(
        _ pathComponents: [String],
        host: String,
        executable: URL
    ) async throws -> T {
        guard let path = pathComponents.first else { throw CodeProvenanceError.malformedGitOutput }
        let result = try await processRunner.run(
            executable: executable,
            arguments: Self.apiArguments(path: path, host: host),
            timeout: .seconds(25)
        )
        return try JSONDecoder.github.decode(T.self, from: result.standardOutput)
    }

    static func safeRelativePath(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.split(separator: "/").contains("..")
        else { throw CodeProvenanceError.invalidPath }
        return trimmed
    }

    static func parseRemote(_ value: String) -> RemoteIdentity? {
        guard !value.isEmpty else { return nil }
        if let url = URL(string: value), let host = url.host {
            let path = repositoryPath(
                url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            )
            guard path.split(separator: "/").count >= 2 else { return nil }
            return RemoteIdentity(host: host, fullName: path)
        }
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let hostPart = value[..<colon]
        let path = repositoryPath(String(value[value.index(after: colon)...]))
        let host = hostPart.split(separator: "@").last.map(String.init) ?? "github.com"
        guard path.split(separator: "/").count >= 2 else { return nil }
        return RemoteIdentity(host: host, fullName: path)
    }

    private static func repositoryPath(_ value: String) -> String {
        value.hasSuffix(".git") ? String(value.dropLast(4)) : value
    }

    static func issueNumbers(in text: String, excluding excluded: Int?) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?)?\s*#(\d+)"#) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<Int>()
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: text),
                  let number = Int(text[swiftRange]),
                  number != excluded,
                  seen.insert(number).inserted
            else { return nil }
            return number
        }
    }

    private static func apiArguments(path: String, host: String) -> [String] {
        var arguments = ["api"]
        if host != "github.com" {
            arguments.append(contentsOf: ["--hostname", host])
        }
        arguments.append(contentsOf: [
            "-H", "Accept: application/vnd.github+json",
            "-H", "X-GitHub-Api-Version: 2022-11-28",
            path,
        ])
        return arguments
    }

    struct RemoteIdentity: Sendable, Equatable {
        let host: String
        let fullName: String
    }
}

private struct PullPayload: Decodable {
    let number: Int
    let title: String
    let body: String?
    let state: String
    let user: UserPayload
    let htmlURL: URL?
    let mergedAt: Date?

    enum CodingKeys: String, CodingKey {
        case number, title, body, state, user
        case htmlURL = "html_url"
        case mergedAt = "merged_at"
    }

    var model: CodeProvenancePullRequest {
        CodeProvenancePullRequest(
            number: number,
            title: title,
            body: body ?? "",
            state: state,
            author: user.login,
            url: htmlURL,
            mergedAt: mergedAt
        )
    }
}

private struct UserPayload: Decodable {
    let login: String
}

private struct ReviewPayload: Decodable {
    let id: Int64
    let user: UserPayload
    let body: String?
    let state: String
    let submittedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, user, body, state
        case submittedAt = "submitted_at"
    }

    var model: CodeProvenanceReview {
        CodeProvenanceReview(
            id: id,
            author: user.login,
            state: state,
            body: body ?? "",
            submittedAt: submittedAt
        )
    }
}

private struct ChecksPayload: Decodable {
    let checkRuns: [CheckPayload]

    enum CodingKeys: String, CodingKey {
        case checkRuns = "check_runs"
    }
}

private struct CheckPayload: Decodable {
    let id: Int64
    let name: String
    let status: String
    let conclusion: String?
    let detailsURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion
        case detailsURL = "details_url"
    }

    var model: CodeProvenanceCheck {
        CodeProvenanceCheck(
            id: id,
            name: name,
            status: status,
            conclusion: conclusion,
            url: detailsURL
        )
    }
}

private struct IssuePayload: Decodable {
    let number: Int
    let title: String
    let state: String
    let htmlURL: URL?
    let pullRequest: PullRequestMarker?

    enum CodingKeys: String, CodingKey {
        case number, title, state
        case htmlURL = "html_url"
        case pullRequest = "pull_request"
    }

    var model: CodeProvenanceIssue {
        CodeProvenanceIssue(number: number, title: title, state: state, url: htmlURL)
    }
}

private struct PullRequestMarker: Decodable {}

private extension JSONDecoder {
    static var github: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
