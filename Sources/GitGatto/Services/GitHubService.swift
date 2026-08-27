import Foundation

protocol GitHubServing: Sendable {
    func probe() async -> GitHubAvailability
    func beginLogin() async throws
    func currentAccount() async throws -> GitHubAccount
    func accountRepositories() async throws -> [GitHubRepository]
    func searchRepositories(query: String) async throws -> [GitHubRepository]
    func searchDevelopers(query: String) async throws -> [GitHubDeveloperSummary]
    func developerProfile(login: String) async throws -> GitHubDeveloperProfile
    func repositories(forDeveloper login: String) async throws -> [GitHubRepository]
    func dailyRecommendations() async throws -> [GitHubRepository]
    func readme(for repository: GitHubRepository) async throws -> GitHubReadmeDocument?
    func markdown(at path: String, in repository: GitHubRepository) async throws -> GitHubReadmeDocument
    func contents(at path: String, in repository: GitHubRepository) async throws -> [GitHubContentItem]
    func file(_ item: GitHubContentItem, in repository: GitHubRepository) async throws -> GitHubFileDocument
    func pullRequests(for repository: GitHubRepository) async throws -> [GitHubPullRequest]
    func pullRequestContext(
        for pullRequest: GitHubPullRequest,
        in repository: GitHubRepository
    ) async throws -> GitHubPullRequestContext
    func clone(_ repository: GitHubRepository, into parentDirectory: URL) async throws -> URL
    func forkAndClone(_ repository: GitHubRepository, into parentDirectory: URL) async throws -> URL
    func postComment(_ body: String, to pullRequest: GitHubPullRequest, in repository: GitHubRepository) async throws
    func cancel() async
}

enum GitHubServiceError: LocalizedError, Sendable {
    case executableNotFound
    case launchFailed
    case commandFailed(String)
    case destinationExists
    case invalidResponse
    case resourceNotFound

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "The GitHub CLI was not found."
        case .launchFailed:
            "The GitHub CLI could not be started."
        case let .commandFailed(message):
            message
        case .destinationExists:
            "A folder with this repository name already exists at the selected location."
        case .invalidResponse:
            "GitHub returned an invalid response."
        case .resourceNotFound:
            "The GitHub resource was not found."
        }
    }
}

actor GitHubService: GitHubServing {
    private var currentInvocation: GitHubCommandInvocation?

    func probe() async -> GitHubAvailability {
        guard let executableURL = GitHubExecutableLocator.find() else {
            return .unavailable
        }

        do {
            let versionOutput = try await GitHubCommandInvocation(
                executableURL: executableURL,
                arguments: ["--version"],
                currentDirectoryURL: nil
            ).run()
            guard versionOutput.exitCode == 0 else { return .unavailable }

            let authOutput = try await GitHubCommandInvocation(
                executableURL: executableURL,
                arguments: ["auth", "status", "--hostname", "github.com"],
                currentDirectoryURL: nil
            ).run()
            guard authOutput.exitCode == 0 else { return .unavailable }

            let firstLine = String(decoding: versionOutput.standardOutput, as: UTF8.self)
                .split(whereSeparator: \Character.isNewline)
                .first
                .map(String.init)
            return GitHubAvailability(state: .available, version: firstLine)
        } catch {
            return .unavailable
        }
    }

    func beginLogin() async throws {
        guard let executableURL = GitHubExecutableLocator.find() else {
            throw GitHubServiceError.executableNotFound
        }
        try await GitHubLoginLauncher.launch(executableURL: executableURL)
    }

    func currentAccount() async throws -> GitHubAccount {
        let response = try await api(["user"])
        return try GitHubAPIParser.account(from: response)
    }

    func accountRepositories() async throws -> [GitHubRepository] {
        let response = try await api([
            "--paginate", "--slurp",
            "-X", "GET",
            "user/repos",
            "-f", "affiliation=owner,collaborator,organization_member",
            "-f", "visibility=all",
            "-f", "sort=updated",
            "-f", "per_page=100"
        ])
        return try GitHubAPIParser.accountRepositories(from: response)
    }

    func searchRepositories(query: String) async throws -> [GitHubRepository] {
        let response = try await api([
            "-X", "GET",
            "search/repositories",
            "-f", "q=\(query) archived:false",
            "-f", "sort=stars",
            "-f", "order=desc",
            "-f", "per_page=30"
        ])
        return try GitHubAPIParser.repositories(from: response)
    }

    func searchDevelopers(query: String) async throws -> [GitHubDeveloperSummary] {
        let response = try await api([
            "-X", "GET",
            "search/users",
            "-f", "q=\(query)",
            "-f", "per_page=40"
        ])
        let developers = try GitHubAPIParser.developers(from: response)
        return GitHubFuzzySearch.sorted(developers, query: query)
    }

    func developerProfile(login: String) async throws -> GitHubDeveloperProfile {
        let response = try await api(["users/\(login)"])
        return try GitHubAPIParser.developerProfile(from: response)
    }

    func repositories(forDeveloper login: String) async throws -> [GitHubRepository] {
        let response = try await api([
            "-X", "GET",
            "users/\(login)/repos",
            "-f", "type=owner",
            "-f", "sort=updated",
            "-f", "per_page=30"
        ])
        return try GitHubAPIParser.repositoryList(from: response)
    }

    func dailyRecommendations() async throws -> [GitHubRepository] {
        let calendar = Calendar(identifier: .gregorian)
        let startDate = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        let query = "created:>=\(formatter.string(from: startDate)) stars:>=25 is:public archived:false"

        let response = try await api([
            "-X", "GET",
            "search/repositories",
            "-f", "q=\(query)",
            "-f", "sort=stars",
            "-f", "order=desc",
            "-f", "per_page=20"
        ])
        return try GitHubAPIParser.repositories(from: response)
    }

    func readme(for repository: GitHubRepository) async throws -> GitHubReadmeDocument? {
        do {
            let endpoint = "repos/\(repository.fullName)/readme"
            return try await renderedMarkdown(endpoint: endpoint, repository: repository)
        } catch GitHubServiceError.resourceNotFound {
            return nil
        }
    }

    func markdown(at path: String, in repository: GitHubRepository) async throws -> GitHubReadmeDocument {
        let endpoint = GitHubPathEncoder.contentsEndpoint(repository: repository.fullName, path: path)
        return try await renderedMarkdown(endpoint: endpoint, repository: repository)
    }

    func contents(at path: String, in repository: GitHubRepository) async throws -> [GitHubContentItem] {
        let endpoint = GitHubPathEncoder.contentsEndpoint(repository: repository.fullName, path: path)
        let response = try await api([
            "-X", "GET",
            endpoint,
            "-f", "ref=\(repository.defaultBranch)"
        ])
        return try GitHubAPIParser.contents(from: response)
    }

    func file(_ item: GitHubContentItem, in repository: GitHubRepository) async throws -> GitHubFileDocument {
        guard item.kind != .directory else {
            throw GitHubServiceError.invalidResponse
        }
        guard item.size <= 1_500_000 else {
            return GitHubFileDocument(
                name: item.name,
                path: item.path,
                text: nil,
                size: item.size,
                webURL: item.webURL
            )
        }

        let endpoint = GitHubPathEncoder.contentsEndpoint(repository: repository.fullName, path: item.path)
        let response = try await api([
            "-H", "Accept: application/vnd.github.raw+json",
            "-X", "GET",
            endpoint,
            "-f", "ref=\(repository.defaultBranch)"
        ])
        let isBinary = response.prefix(8_192).contains(0)
        let text = isBinary ? nil : String(data: response, encoding: .utf8)
        return GitHubFileDocument(
            name: item.name,
            path: item.path,
            text: text,
            size: item.size,
            webURL: item.webURL
        )
    }

    private func embeddingPrivateReadmeAssets(
        in html: String,
        readmePath: String,
        repository: GitHubRepository
    ) async throws -> String {
        let references = Array(GitHubReadmeHTML.relativeAssetReferences(in: html).prefix(16))
        guard !references.isEmpty else { return html }

        var replacements: [String: String] = [:]
        var totalSize = 0
        for reference in references {
            guard let path = GitHubReadmeHTML.repositoryPath(for: reference, readmePath: readmePath),
                  let mimeType = Self.imageMIMEType(for: path) else { continue }
            do {
                let endpoint = GitHubPathEncoder.contentsEndpoint(repository: repository.fullName, path: path)
                let metadataResponse = try await api([
                    "-X", "GET",
                    endpoint,
                    "-f", "ref=\(repository.defaultBranch)"
                ])
                let item = try GitHubAPIParser.contentItem(from: metadataResponse)
                guard item.kind == .file,
                      item.size <= 4_000_000,
                      totalSize + item.size <= 12_000_000 else { continue }

                let data = try await api([
                    "-H", "Accept: application/vnd.github.raw+json",
                    "-X", "GET",
                    endpoint,
                    "-f", "ref=\(repository.defaultBranch)"
                ])
                guard data.count <= 4_000_000,
                      totalSize + data.count <= 12_000_000 else { continue }
                totalSize += data.count
                replacements[reference] = "data:\(mimeType);base64,\(data.base64EncodedString())"
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return GitHubReadmeHTML.replacingAssetReferences(in: html, replacements: replacements)
    }

    private func renderedMarkdown(
        endpoint: String,
        repository: GitHubRepository
    ) async throws -> GitHubReadmeDocument {
        let metadataResponse = try await api([
            "-X", "GET",
            endpoint,
            "-f", "ref=\(repository.defaultBranch)"
        ])
        let metadata = try GitHubAPIParser.readmeMetadata(from: metadataResponse)
        let response = try await api([
            "-H", "Accept: application/vnd.github.html+json",
            "-X", "GET",
            endpoint,
            "-f", "ref=\(repository.defaultBranch)"
        ])
        var html = String(decoding: response, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !html.isEmpty else { throw GitHubServiceError.invalidResponse }
        if repository.isPrivate {
            html = try await embeddingPrivateReadmeAssets(
                in: html,
                readmePath: metadata.path,
                repository: repository
            )
        }
        return metadata.document(html: html)
    }

    private static func imageMIMEType(for path: String) -> String? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "svg": "image/svg+xml"
        case "webp": "image/webp"
        case "bmp": "image/bmp"
        case "ico": "image/x-icon"
        case "avif": "image/avif"
        default: nil
        }
    }

    func pullRequests(for repository: GitHubRepository) async throws -> [GitHubPullRequest] {
        let response = try await api([
            "-X", "GET",
            "repos/\(repository.fullName)/pulls",
            "-f", "state=open",
            "-f", "sort=updated",
            "-f", "direction=desc",
            "-f", "per_page=30"
        ])
        return try GitHubAPIParser.pullRequests(from: response)
    }

    func pullRequestContext(
        for pullRequest: GitHubPullRequest,
        in repository: GitHubRepository
    ) async throws -> GitHubPullRequestContext {
        let response = try await api([
            "-H", "Accept: application/vnd.github.v3.diff",
            "repos/\(repository.fullName)/pulls/\(pullRequest.number)"
        ])
        let diff = String(decoding: response, as: UTF8.self)
        return GitHubPullRequestContext(
            repositoryName: repository.fullName,
            pullRequest: pullRequest,
            diff: String(diff.prefix(80_000))
        )
    }

    func clone(_ repository: GitHubRepository, into parentDirectory: URL) async throws -> URL {
        let destination = parentDirectory.appendingPathComponent(repository.name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw GitHubServiceError.destinationExists
        }
        _ = try await execute(
            arguments: ["repo", "clone", repository.fullName, destination.path],
            currentDirectoryURL: parentDirectory
        )
        return destination
    }

    func forkAndClone(_ repository: GitHubRepository, into parentDirectory: URL) async throws -> URL {
        let destination = parentDirectory.appendingPathComponent(repository.name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw GitHubServiceError.destinationExists
        }
        _ = try await execute(
            arguments: ["repo", "fork", repository.fullName, "--clone"],
            currentDirectoryURL: parentDirectory
        )
        return destination
    }

    func postComment(
        _ body: String,
        to pullRequest: GitHubPullRequest,
        in repository: GitHubRepository
    ) async throws {
        _ = try await api([
            "-X", "POST",
            "repos/\(repository.fullName)/issues/\(pullRequest.number)/comments",
            "-f", "body=\(body)"
        ])
    }

    func cancel() {
        currentInvocation?.cancel()
    }

    private func api(_ arguments: [String]) async throws -> Data {
        try await execute(arguments: ["api"] + arguments, currentDirectoryURL: nil).standardOutput
    }

    private func execute(arguments: [String], currentDirectoryURL: URL?) async throws -> GitHubCommandOutput {
        guard let executableURL = GitHubExecutableLocator.find() else {
            throw GitHubServiceError.executableNotFound
        }
        let invocation = GitHubCommandInvocation(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL
        )
        currentInvocation = invocation
        defer {
            if currentInvocation === invocation {
                currentInvocation = nil
            }
        }

        let output = try await withTaskCancellationHandler {
            try await invocation.run()
        } onCancel: {
            invocation.cancel()
        }
        guard output.exitCode == 0 else {
            let message = String(decoding: output.standardError, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if message.contains("HTTP 404") {
                throw GitHubServiceError.resourceNotFound
            }
            throw GitHubServiceError.commandFailed(
                message.isEmpty ? "GitHub CLI exited with status \(output.exitCode)." : String(message.prefix(2_000))
            )
        }
        return output
    }

}

enum GitHubAPIParser {
    static func account(from data: Data) throws -> GitHubAccount {
        try decode(AccountPayload.self, from: data).model
    }

    static func repositories(from data: Data) throws -> [GitHubRepository] {
        try decode(SearchResponse.self, from: data).items.map(\.model)
    }

    static func developers(from data: Data) throws -> [GitHubDeveloperSummary] {
        try decode(DeveloperSearchResponse.self, from: data).items.map(\.model)
    }

    static func developerProfile(from data: Data) throws -> GitHubDeveloperProfile {
        try decode(DeveloperProfilePayload.self, from: data).model
    }

    static func repositoryList(from data: Data) throws -> [GitHubRepository] {
        try decode([RepositoryPayload].self, from: data).map(\.model)
    }

    static func accountRepositories(from data: Data) throws -> [GitHubRepository] {
        if let pages = try? decode([[RepositoryPayload]].self, from: data) {
            return pages.flatMap { $0 }.map(\.model)
        }
        return try decode([RepositoryPayload].self, from: data).map(\.model)
    }

    static func pullRequests(from data: Data) throws -> [GitHubPullRequest] {
        try decode([PullRequestPayload].self, from: data).map(\.model)
    }

    static func readmeMetadata(from data: Data) throws -> GitHubReadmeMetadata {
        try decode(ReadmeMetadataPayload.self, from: data).model
    }

    static func contents(from data: Data) throws -> [GitHubContentItem] {
        try decode([ContentItemPayload].self, from: data)
            .map(\.model)
            .sorted {
                if $0.kind == .directory, $1.kind != .directory { return true }
                if $0.kind != .directory, $1.kind == .directory { return false }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    static func contentItem(from data: Data) throws -> GitHubContentItem {
        try decode(ContentItemPayload.self, from: data).model
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw GitHubServiceError.invalidResponse
        }
    }
}

enum GitHubFuzzySearch {
    static func sorted(
        _ developers: [GitHubDeveloperSummary],
        query: String
    ) -> [GitHubDeveloperSummary] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return developers }
        return developers.sorted { lhs, rhs in
            let left = score(candidate: lhs.login, query: needle)
            let right = score(candidate: rhs.login, query: needle)
            if left != right { return left < right }
            return lhs.login.localizedCaseInsensitiveCompare(rhs.login) == .orderedAscending
        }
    }

    static func score(candidate: String, query: String) -> Int {
        let value = normalize(candidate)
        let needle = normalize(query)
        if value == needle { return 0 }
        if value.hasPrefix(needle) { return 1 }
        if value.contains(needle) { return 2 }
        return 3 + editDistance(value, needle)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                current.append(Swift.min(Swift.min(insertion, deletion), substitution))
            }
            previous = current
        }
        return previous[right.count]
    }
}

struct GitHubReadmeMetadata: Sendable, Equatable {
    let path: String
    let htmlURL: URL
    let downloadURL: URL?

    func document(html: String) -> GitHubReadmeDocument {
        let directoryDepth = max(0, path.split(separator: "/").count - 1)
        let linkBaseURL = Self.directoryURL(htmlURL.deletingLastPathComponent())
        let linkRootURL = Self.ancestor(of: linkBaseURL, levels: directoryDepth)
        let assetFileURL = downloadURL ?? htmlURL
        let assetBaseURL = Self.directoryURL(assetFileURL.deletingLastPathComponent())
        let assetRootURL = Self.ancestor(of: assetBaseURL, levels: directoryDepth)
        return GitHubReadmeDocument(
            path: path,
            html: html,
            linkBaseURL: linkBaseURL,
            linkRootURL: linkRootURL,
            assetBaseURL: assetBaseURL,
            assetRootURL: assetRootURL
        )
    }

    private static func ancestor(of url: URL, levels: Int) -> URL {
        var result = url
        for _ in 0..<levels {
            result = result.deletingLastPathComponent()
        }
        return directoryURL(result)
    }

    private static func directoryURL(_ url: URL) -> URL {
        guard !url.absoluteString.hasSuffix("/") else { return url }
        return URL(string: url.absoluteString + "/") ?? url
    }
}

enum GitHubPathEncoder {
    static func contentsEndpoint(repository: String, path: String) -> String {
        let base = "repos/\(repository)/contents"
        guard !path.isEmpty else { return base }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
            .joined(separator: "/")
        return "\(base)/\(encoded)"
    }
}

private struct AccountPayload: Decodable {
    let login: String
    let name: String?
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case login, name
        case htmlURL = "html_url"
    }

    var model: GitHubAccount {
        GitHubAccount(login: login, name: name, webURL: htmlURL)
    }
}

private struct SearchResponse: Decodable {
    let items: [RepositoryPayload]
}

private struct DeveloperSearchResponse: Decodable {
    let items: [DeveloperSummaryPayload]
}

private struct DeveloperSummaryPayload: Decodable {
    let login: String
    let avatarURL: URL
    let htmlURL: URL
    let type: String

    enum CodingKeys: String, CodingKey {
        case login, type
        case avatarURL = "avatar_url"
        case htmlURL = "html_url"
    }

    var model: GitHubDeveloperSummary {
        GitHubDeveloperSummary(
            login: login,
            avatarURL: avatarURL,
            webURL: htmlURL,
            accountType: type
        )
    }
}

private struct DeveloperProfilePayload: Decodable {
    let login: String
    let name: String?
    let bio: String?
    let avatarURL: URL
    let htmlURL: URL
    let type: String
    let company: String?
    let location: String?
    let followers: Int
    let publicRepos: Int

    enum CodingKeys: String, CodingKey {
        case login, name, bio, type, company, location, followers
        case avatarURL = "avatar_url"
        case htmlURL = "html_url"
        case publicRepos = "public_repos"
    }

    var model: GitHubDeveloperProfile {
        GitHubDeveloperProfile(
            login: login,
            name: name,
            bio: bio,
            avatarURL: avatarURL,
            webURL: htmlURL,
            accountType: type,
            company: company,
            location: location,
            followers: followers,
            publicRepositories: publicRepos
        )
    }
}

private struct ReadmeMetadataPayload: Decodable {
    let path: String
    let htmlURL: URL
    let downloadURL: URL?

    enum CodingKeys: String, CodingKey {
        case path
        case htmlURL = "html_url"
        case downloadURL = "download_url"
    }

    var model: GitHubReadmeMetadata {
        GitHubReadmeMetadata(path: path, htmlURL: htmlURL, downloadURL: downloadURL)
    }
}

private struct RepositoryPayload: Decodable {
    struct Owner: Decodable { let login: String }

    let fullName: String
    let name: String
    let owner: Owner
    let description: String?
    let htmlURL: URL
    let stargazersCount: Int
    let forksCount: Int
    let openIssuesCount: Int
    let language: String?
    let updatedAt: Date
    let isPrivate: Bool
    let defaultBranch: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case name, owner, description, language
        case htmlURL = "html_url"
        case stargazersCount = "stargazers_count"
        case forksCount = "forks_count"
        case openIssuesCount = "open_issues_count"
        case updatedAt = "updated_at"
        case isPrivate = "private"
        case defaultBranch = "default_branch"
    }

    var model: GitHubRepository {
        GitHubRepository(
            fullName: fullName,
            name: name,
            owner: owner.login,
            description: description,
            webURL: htmlURL,
            stars: stargazersCount,
            forks: forksCount,
            openIssues: openIssuesCount,
            language: language,
            updatedAt: updatedAt,
            isPrivate: isPrivate,
            defaultBranch: defaultBranch
        )
    }
}

private struct PullRequestPayload: Decodable {
    struct User: Decodable { let login: String }
    struct Branch: Decodable { let ref: String }

    let number: Int
    let title: String
    let user: User
    let body: String?
    let htmlURL: URL
    let draft: Bool
    let head: Branch
    let base: Branch
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case number, title, user, body, draft, head, base
        case htmlURL = "html_url"
        case updatedAt = "updated_at"
    }

    var model: GitHubPullRequest {
        GitHubPullRequest(
            number: number,
            title: title,
            author: user.login,
            body: body,
            webURL: htmlURL,
            isDraft: draft,
            headBranch: head.ref,
            baseBranch: base.ref,
            updatedAt: updatedAt
        )
    }
}

private struct ContentItemPayload: Decodable {
    let type: String
    let name: String
    let path: String
    let size: Int
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case type, name, path, size
        case htmlURL = "html_url"
    }

    var model: GitHubContentItem {
        let kind: GitHubContentItem.Kind
        switch type {
        case "dir": kind = .directory
        case "symlink": kind = .symlink
        case "submodule": kind = .submodule
        default: kind = .file
        }
        return GitHubContentItem(
            name: name,
            path: path,
            kind: kind,
            size: size,
            webURL: htmlURL
        )
    }
}

private struct GitHubCommandOutput: Sendable {
    let standardOutput: Data
    let standardError: Data
    let exitCode: Int32
}

private final class GitHubCommandInvocation: @unchecked Sendable {
    private let executableURL: URL
    private let arguments: [String]
    private let currentDirectoryURL: URL?
    private let process = Process()
    private let lock = NSLock()
    private var hasStarted = false
    private var isCancelled = false

    init(executableURL: URL, arguments: [String], currentDirectoryURL: URL?) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.currentDirectoryURL = currentDirectoryURL
    }

    func run() async throws -> GitHubCommandOutput {
        try await Task.detached(priority: .userInitiated) { [self] in
            try runBlocking()
        }.value
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let shouldTerminate = hasStarted && process.isRunning
        lock.unlock()
        if shouldTerminate { process.terminate() }
    }

    private func runBlocking() throws -> GitHubCommandOutput {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        var environment = ProcessInfo.processInfo.environment
        environment["GH_PAGER"] = "cat"
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["NO_COLOR"] = "1"
        process.environment = environment

        lock.lock()
        if isCancelled {
            lock.unlock()
            throw CancellationError()
        }
        do {
            try process.run()
            hasStarted = true
            lock.unlock()
        } catch {
            lock.unlock()
            throw GitHubServiceError.launchFailed
        }

        let outputBox = GitHubLockedDataBox()
        let errorBox = GitHubLockedDataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputBox.set(outputPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorBox.set(errorPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        process.waitUntilExit()
        group.wait()

        lock.lock()
        let cancelled = isCancelled
        lock.unlock()
        if cancelled { throw CancellationError() }

        return GitHubCommandOutput(
            standardOutput: outputBox.value,
            standardError: errorBox.value,
            exitCode: process.terminationStatus
        )
    }
}

private final class GitHubLockedDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var value: Data { lock.withLock { storage } }
    func set(_ value: Data) { lock.withLock { storage = value } }
}

private enum GitHubLoginLauncher {
    static func launch(executableURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let escapedPath = executableURL.path.replacingOccurrences(of: "'", with: "'\\''")
            let command = "'\(escapedPath)' auth login --hostname github.com --web --clipboard --git-protocol ssh --skip-ssh-key"
            let escapedCommand = command
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [
                "-e", "tell application \"Terminal\"",
                "-e", "activate",
                "-e", "do script \"\(escapedCommand)\"",
                "-e", "end tell"
            ]
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            do {
                try process.run()
            } catch {
                throw GitHubServiceError.launchFailed
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw GitHubServiceError.launchFailed
            }
        }.value
    }
}

private enum GitHubExecutableLocator {
    static func find() -> URL? {
        var paths = ["/usr/local/bin/gh", "/opt/homebrew/bin/gh"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            paths.append(contentsOf: path.split(separator: ":").map { "\($0)/gh" })
        }
        for path in paths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
