import Foundation

protocol GitCommitSearchServing: Sendable {
    func search(_ query: CommitSearchQuery, in repositoryURL: URL) async throws -> [CommitRecord]
}

struct GitCommitSearchService: GitCommitSearchServing {
    private let runner: GitCommandRunner

    init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    func search(_ query: CommitSearchQuery, in repositoryURL: URL) async throws -> [CommitRecord] {
        var arguments = [
            "log", "-n", "500", "--date=iso-strict", "--regexp-ignore-case",
            "--pretty=format:%H%x1f%h%x1f%an%x1f%ad%x1f%s%x1e"
        ]

        let requestedRevision = query.hash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? query.revision
            : query.hash
        let revision = try await validatedRevision(requestedRevision, in: repositoryURL)
        arguments.append(revision)
        appendValue(query.message, flag: "--grep", to: &arguments)
        appendValue(query.author, flag: "--author", to: &arguments)
        appendValue(query.changedText, flag: "-S", joined: true, to: &arguments)
        if let since = query.since {
            arguments.append("--since=\(since.formatted(Self.gitDateFormat))")
        }
        if let until = query.until {
            arguments.append("--until=\(until.formatted(Self.gitDateFormat))")
        }
        if query.mergesOnly {
            arguments.append("--merges")
        }

        let path = try validatedPath(query.path)
        let fileExtension = try validatedExtension(query.fileExtension)
        if path != nil || fileExtension != nil {
            arguments.append("--")
            if let path, let fileExtension {
                if path.hasSuffix(".\(fileExtension)") {
                    arguments.append(path)
                } else {
                    arguments.append(":(glob)\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/**/*.\(fileExtension)")
                }
            } else if let path {
                arguments.append(path)
            } else if let fileExtension {
                arguments.append(":(glob)**/*.\(fileExtension)")
            }
        }

        let result = try await runner.run(
            at: repositoryURL,
            arguments: arguments,
            acceptedExitCodes: [0, 128]
        )
        guard result.exitCode == 0 else { return [] }
        return GitParsers.commits(from: result.text)
    }

    private func validatedRevision(_ value: String, in repositoryURL: URL) async throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "--all" { return "--all" }
        guard !trimmed.hasPrefix("-") else { throw GitCommitSearchError.invalidRevision }
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "--verify", "\(trimmed)^{commit}"],
            acceptedExitCodes: [0, 128]
        )
        guard result.exitCode == 0 else { throw GitCommitSearchError.invalidRevision }
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validatedPath(_ value: String) throws -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let components = NSString(string: trimmed).standardizingPath.split(separator: "/")
        guard !trimmed.hasPrefix("-"), !trimmed.hasPrefix("/"), !components.contains("..") else {
            throw GitCommitSearchError.invalidPath
        }
        return trimmed
    }

    private func validatedExtension(_ value: String) throws -> String? {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "#" || $0 == "-" }) else {
            throw GitCommitSearchError.invalidFileExtension
        }
        return trimmed
    }

    private func appendValue(
        _ value: String,
        flag: String,
        joined: Bool = false,
        to arguments: inout [String]
    ) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if joined {
            arguments.append("\(flag)\(trimmed)")
        } else {
            arguments.append(contentsOf: [flag, trimmed])
        }
    }

    private static let gitDateFormat = Date.ISO8601FormatStyle()
        .year().month().day().dateSeparator(.dash)
        .time(includingFractionalSeconds: false)
        .timeSeparator(.colon)
}

enum GitCommitSearchError: LocalizedError, Sendable, Equatable {
    case invalidRevision
    case invalidPath
    case invalidFileExtension

    var errorDescription: String? {
        switch self {
        case .invalidRevision: L10n.text("commit_search.error.revision")
        case .invalidPath: L10n.text("commit_search.error.path")
        case .invalidFileExtension: L10n.text("commit_search.error.file_extension")
        }
    }
}
