import Foundation

protocol GitHubServing: Sendable {
    func probe() async -> GitHubAvailability
    func beginLogin() async throws
    func currentAccount() async throws -> GitHubAccount
    func accountRepositories() async throws -> [GitHubRepository]
    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepository]
    func searchDevelopers(query: String, page: Int) async throws -> [GitHubDeveloperSummary]
    func developerProfile(login: String) async throws -> GitHubDeveloperProfile
    func repositories(forDeveloper login: String, page: Int) async throws -> [GitHubRepository]
    func dailyRecommendations() async throws -> [GitHubRepository]
    func readme(for repository: GitHubRepository) async throws -> GitHubReadmeDocument?
    func markdown(at path: String, in repository: GitHubRepository) async throws -> GitHubReadmeDocument
    func renderLocalMarkdown(
        at fileURL: URL,
        relativePath: String,
        in repository: GitHubRepository
    ) async throws -> GitHubReadmeDocument
    func contents(at path: String, in repository: GitHubRepository) async throws -> [GitHubContentItem]
    func file(_ item: GitHubContentItem, in repository: GitHubRepository) async throws -> GitHubFileDocument
    func releases(for repository: GitHubRepository) async throws -> [GitHubRelease]
    func releaseAssetData(_ asset: GitHubReleaseAsset, in repository: GitHubRepository) async throws -> Data
    func downloadReleaseAsset(
        _ asset: GitHubReleaseAsset,
        tag: String,
        in repository: GitHubRepository,
        to directory: URL
    ) async throws -> URL
    func isStarred(_ repository: GitHubRepository) async throws -> Bool
    func setStarred(_ starred: Bool, repository: GitHubRepository) async throws
    func pullRequests(for repository: GitHubRepository) async throws -> [GitHubPullRequest]
    func inbox() async throws -> [GitHubInboxItem]
    func issues(
        for repository: GitHubRepository,
        state: GitHubIssueState,
        page: Int
    ) async throws -> [GitHubIssue]
    func issueComments(
        for issue: GitHubIssue,
        in repository: GitHubRepository
    ) async throws -> [GitHubIssueComment]
    func createIssue(
        _ draft: GitHubIssueDraft,
        in repository: GitHubRepository
    ) async throws -> GitHubIssue
    func updateIssue(
        _ issue: GitHubIssue,
        draft: GitHubIssueDraft,
        state: GitHubIssueState,
        in repository: GitHubRepository
    ) async throws -> GitHubIssue
    func addIssueComment(
        _ body: String,
        to issue: GitHubIssue,
        in repository: GitHubRepository
    ) async throws -> GitHubIssueComment
    func pullRequestContext(
        for pullRequest: GitHubPullRequest,
        in repository: GitHubRepository
    ) async throws -> GitHubPullRequestContext
    func pullRequestReviewCenter(
        for pullRequest: GitHubPullRequest,
        in repository: GitHubRepository
    ) async throws -> GitHubPullRequestReviewCenter
    func submitPullRequestReview(
        body: String,
        event: GitHubPullRequestReviewEvent,
        to pullRequest: GitHubPullRequest,
        in repository: GitHubRepository
    ) async throws
    func postPullRequestReviewComment(
        body: String,
        path: String,
        line: Int,
        startLine: Int?,
        to pullRequest: GitHubPullRequest,
        in repository: GitHubRepository
    ) async throws
    func markPullRequestFile(
        _ path: String,
        viewed: Bool,
        in pullRequest: GitHubPullRequest
    ) async throws
    func deliveryPullRequest(
        headBranch: String,
        targetSHA: String,
        in repository: GitHubRepository
    ) async throws -> (pullRequest: GitHubDeliveryPullRequest?, defaultBranch: String)
    func createDeliveryPullRequest(
        title: String,
        body: String,
        headBranch: String,
        baseBranch: String,
        in repository: GitHubRepository
    ) async throws
    func mergeDeliveryPullRequest(
        number: Int,
        in repository: GitHubRepository
    ) async throws
    func actionWorkflows(for repository: GitHubRepository) async throws -> [GitHubActionsWorkflow]
    func actionRuns(for repository: GitHubRepository) async throws -> [GitHubActionsRun]
    func actionRunDetail(
        _ run: GitHubActionsRun,
        in repository: GitHubRepository,
        includeLog: Bool
    ) async throws -> GitHubActionsRunDetail
    func rerunActionRun(
        _ run: GitHubActionsRun,
        failedOnly: Bool,
        in repository: GitHubRepository
    ) async throws
    func cancelActionRun(_ run: GitHubActionsRun, in repository: GitHubRepository) async throws
    func downloadActionArtifact(
        _ artifact: GitHubActionsArtifact,
        for run: GitHubActionsRun,
        to destination: URL,
        in repository: GitHubRepository
    ) async throws
    func cloneReadmeWorkspace(_ repository: GitHubRepository, into parentDirectory: URL) async throws -> URL
    func clone(_ repository: GitHubRepository, into parentDirectory: URL) async throws -> URL
    func forkAndClone(_ repository: GitHubRepository, into parentDirectory: URL) async throws -> URL
    func postComment(_ body: String, to pullRequest: GitHubPullRequest, in repository: GitHubRepository) async throws
    func cancel() async
}

protocol MarketplaceGitHubServing: Sendable {
    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepository]
    func searchRepositories(
        query: String,
        page: Int,
        sort: GitHubRepositorySearchSort
    ) async throws -> [GitHubRepository]
    func repository(named fullName: String) async throws -> GitHubRepository
    func starredRepositories(page: Int) async throws -> [GitHubRepository]
    func isStarred(_ repository: GitHubRepository) async throws -> Bool
    func setStarred(_ starred: Bool, repository: GitHubRepository) async throws
    func marketplaceRelease(for repository: GitHubRepository) async throws -> GitHubRelease?
    func releases(for repository: GitHubRepository) async throws -> [GitHubRelease]
    func readme(for repository: GitHubRepository) async throws -> GitHubReadmeDocument?
}

extension MarketplaceGitHubServing {
    func searchRepositories(
        query: String,
        page: Int,
        sort: GitHubRepositorySearchSort
    ) async throws -> [GitHubRepository] {
        try await searchRepositories(query: query, page: page)
    }

    func repository(named fullName: String) async throws -> GitHubRepository {
        let components = fullName.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2 else { throw GitHubServiceError.resourceNotFound }
        let candidates = try await searchRepositories(
            query: "\(components[1]) user:\(components[0]) in:name",
            page: 1
        )
        guard let repository = candidates.first(where: {
            $0.fullName.caseInsensitiveCompare(fullName) == .orderedSame
        }) else {
            throw GitHubServiceError.resourceNotFound
        }
        return repository
    }

    func starredRepositories(page: Int) async throws -> [GitHubRepository] { [] }

    func isStarred(_ repository: GitHubRepository) async throws -> Bool { false }

    func setStarred(_ starred: Bool, repository: GitHubRepository) async throws {
        throw GitHubServiceError.invalidResponse
    }
}

extension GitHubServing {
    func searchRepositories(query: String) async throws -> [GitHubRepository] {
        try await searchRepositories(query: query, page: 1)
    }

    func searchDevelopers(query: String) async throws -> [GitHubDeveloperSummary] {
        try await searchDevelopers(query: query, page: 1)
    }

    func repositories(forDeveloper login: String) async throws -> [GitHubRepository] {
        try await repositories(forDeveloper: login, page: 1)
    }

    func releases(for repository: GitHubRepository) async throws -> [GitHubRelease] {
        throw GitHubServiceError.invalidResponse
    }

    func inbox() async throws -> [GitHubInboxItem] {
        throw GitHubServiceError.invalidResponse
    }

    func issues(
        for repository: GitHubRepository,
        state: GitHubIssueState,
        page: Int
    ) async throws -> [GitHubIssue] {
        throw GitHubServiceError.invalidResponse
    }

    func issueComments(
        for issue: GitHubIssue,
        in repository: GitHubRepository
    ) async throws -> [GitHubIssueComment] {
        throw GitHubServiceError.invalidResponse
    }

    func createIssue(
        _ draft: GitHubIssueDraft,
        in repository: GitHubRepository
    ) async throws -> GitHubIssue {
        throw GitHubServiceError.invalidResponse
    }

    func updateIssue(
        _ issue: GitHubIssue,
        draft: GitHubIssueDraft,
        state: GitHubIssueState,
        in repository: GitHubRepository
    ) async throws -> GitHubIssue {
        throw GitHubServiceError.invalidResponse
    }

    func addIssueComment(
        _ body: String,
        to issue: GitHubIssue,
        in repository: GitHubRepository
    ) async throws -> GitHubIssueComment {
        throw GitHubServiceError.invalidResponse
    }

    func releaseAssetData(_ asset: GitHubReleaseAsset, in repository: GitHubRepository) async throws -> Data {
        throw GitHubServiceError.invalidResponse
    }

    func downloadReleaseAsset(
        _ asset: GitHubReleaseAsset,
        tag: String,
        in repository: GitHubRepository,
        to directory: URL
    ) async throws -> URL {
        throw GitHubServiceError.invalidResponse
    }

    func isStarred(_ repository: GitHubRepository) async throws -> Bool {
        false
    }

    func setStarred(_ starred: Bool, repository: GitHubRepository) async throws {
        throw GitHubServiceError.invalidResponse
    }

    func renderLocalMarkdown(
        at fileURL: URL,
        relativePath: String,
        in repository: GitHubRepository
    ) async throws -> GitHubReadmeDocument {
        throw GitHubServiceError.invalidResponse
    }

    func pullRequestReviewCenter(
        for pullRequest: GitHubPullRequest,
        in repository: GitHubRepository
    ) async throws -> GitHubPullRequestReviewCenter {
        throw GitHubServiceError.invalidResponse
    }

    func submitPullRequestReview(
        body: String,
        event: GitHubPullRequestReviewEvent,
        to pullRequest: GitHubPullRequest,
        in repository: GitHubRepository
    ) async throws {
        throw GitHubServiceError.invalidResponse
    }

    func postPullRequestReviewComment(
        body: String,
        path: String,
        line: Int,
        startLine: Int?,
        to pullRequest: GitHubPullRequest,
        in repository: GitHubRepository
    ) async throws {
        throw GitHubServiceError.invalidResponse
    }

    func markPullRequestFile(
        _ path: String,
        viewed: Bool,
        in pullRequest: GitHubPullRequest
    ) async throws {
        throw GitHubServiceError.invalidResponse
    }

    func deliveryPullRequest(
        headBranch: String,
        targetSHA: String,
        in repository: GitHubRepository
    ) async throws -> (pullRequest: GitHubDeliveryPullRequest?, defaultBranch: String) {
        throw GitHubServiceError.invalidResponse
    }

    func createDeliveryPullRequest(
        title: String,
        body: String,
        headBranch: String,
        baseBranch: String,
        in repository: GitHubRepository
    ) async throws {
        throw GitHubServiceError.invalidResponse
    }

    func mergeDeliveryPullRequest(
        number: Int,
        in repository: GitHubRepository
    ) async throws {
        throw GitHubServiceError.invalidResponse
    }

    func actionWorkflows(for repository: GitHubRepository) async throws -> [GitHubActionsWorkflow] {
        throw GitHubServiceError.invalidResponse
    }

    func actionRuns(for repository: GitHubRepository) async throws -> [GitHubActionsRun] {
        throw GitHubServiceError.invalidResponse
    }

    func actionRunDetail(
        _ run: GitHubActionsRun,
        in repository: GitHubRepository,
        includeLog: Bool
    ) async throws -> GitHubActionsRunDetail {
        throw GitHubServiceError.invalidResponse
    }

    func rerunActionRun(
        _ run: GitHubActionsRun,
        failedOnly: Bool,
        in repository: GitHubRepository
    ) async throws {
        throw GitHubServiceError.invalidResponse
    }

    func cancelActionRun(_ run: GitHubActionsRun, in repository: GitHubRepository) async throws {
        throw GitHubServiceError.invalidResponse
    }

    func downloadActionArtifact(
        _ artifact: GitHubActionsArtifact,
        for run: GitHubActionsRun,
        to destination: URL,
        in repository: GitHubRepository
    ) async throws {
        throw GitHubServiceError.invalidResponse
    }
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

actor GitHubService: GitHubServing, MarketplaceGitHubServing {
    private var currentInvocations: [UUID: GitHubCommandInvocation] = [:]
    private var marketplaceReleaseCache: [String: MarketplaceReleaseCacheEntry] = [:]

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

    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepository] {
        try await searchRepositories(query: query, page: page, sort: .stars)
    }

    func searchRepositories(
        query: String,
        page: Int,
        sort: GitHubRepositorySearchSort
    ) async throws -> [GitHubRepository] {
        let response = try await api([
            "-X", "GET",
            "search/repositories",
            "-f", "q=\(query) archived:false",
            "-f", "sort=\(sort.rawValue)",
            "-f", "order=desc",
            "-f", "per_page=30",
            "-f", "page=\(max(1, page))"
        ])
        return try GitHubAPIParser.repositories(from: response)
    }

    func repository(named fullName: String) async throws -> GitHubRepository {
        let response = try await api(["-X", "GET", "repos/\(fullName)"])
        return try GitHubAPIParser.repository(from: response)
    }

    func starredRepositories(page: Int) async throws -> [GitHubRepository] {
        let response = try await api([
            "-X", "GET",
            "user/starred",
            "-f", "sort=updated",
            "-f", "direction=desc",
            "-f", "per_page=30",
            "-f", "page=\(max(1, page))"
        ])
        return try GitHubAPIParser.repositoryList(from: response)
    }

    func searchDevelopers(query: String, page: Int) async throws -> [GitHubDeveloperSummary] {
        let response = try await api([
            "-X", "GET",
            "search/users",
            "-f", "q=\(query)",
            "-f", "per_page=30",
            "-f", "page=\(max(1, page))"
        ])
        let developers = try GitHubAPIParser.developers(from: response)
        return GitHubFuzzySearch.sorted(developers, query: query)
    }

    func developerProfile(login: String) async throws -> GitHubDeveloperProfile {
        let response = try await api(["users/\(login)"])
        return try GitHubAPIParser.developerProfile(from: response)
    }

    func repositories(forDeveloper login: String, page: Int) async throws -> [GitHubRepository] {
        let response = try await api([
            "-X", "GET",
            "users/\(login)/repos",
            "-f", "type=owner",
            "-f", "sort=updated",
            "-f", "per_page=30",
            "-f", "page=\(max(1, page))"
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

    func renderLocalMarkdown(
        at fileURL: URL,
        relativePath: String,
        in repository: GitHubRepository
    ) async throws -> GitHubReadmeDocument {
        let markdown = try String(contentsOf: fileURL, encoding: .utf8)
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGatto-Markdown-\(UUID().uuidString)")
            .appendingPathExtension("json")
        let payload = LocalMarkdownPayload(
            text: markdown,
            mode: "gfm",
            context: repository.fullName
        )
        try JSONEncoder().encode(payload).write(to: inputURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: inputURL) }

        let response = try await api([
            "--method", "POST",
            "markdown",
            "--input", inputURL.path
        ])
        var html = String(decoding: response, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !html.isEmpty else { throw GitHubServiceError.invalidResponse }
        var repositoryRootURL = fileURL.deletingLastPathComponent()
        for _ in 0..<max(0, relativePath.split(separator: "/").count - 1) {
            repositoryRootURL.deleteLastPathComponent()
        }
        html = try GitHubReadmeHTML.embeddingLocalAssets(
            in: html,
            readmePath: relativePath,
            repositoryRootURL: repositoryRootURL
        )

        let htmlURL = repository.webURL
            .appendingPathComponent("blob", isDirectory: true)
            .appendingPathComponent(repository.defaultBranch, isDirectory: true)
            .appendingPathComponent(relativePath)
        return GitHubReadmeMetadata(
            path: relativePath,
            htmlURL: htmlURL,
            downloadURL: nil
        ).document(html: html)
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
        let previewKind = GitHubPreviewFileKind(fileName: item.name)
        let maximumSize = previewKind.maximumFetchedSize
        guard item.size <= maximumSize else {
            return GitHubFileDocument(
                name: item.name,
                path: item.path,
                text: nil,
                size: item.size,
                webURL: item.webURL,
                downloadURL: item.downloadURL,
                localPreviewURL: nil
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
        let localPreviewURL = try previewKind.cache(
            response,
            repositoryName: repository.fullName,
            path: item.path
        )
        return GitHubFileDocument(
            name: item.name,
            path: item.path,
            text: text,
            size: item.size,
            webURL: item.webURL,
            downloadURL: item.downloadURL,
            localPreviewURL: localPreviewURL
        )
    }

    func releases(for repository: GitHubRepository) async throws -> [GitHubRelease] {
        let response = try await api([
            "--paginate", "--slurp",
            "-X", "GET",
            "repos/\(repository.fullName)/releases",
            "-f", "per_page=50"
        ])
        return try GitHubAPIParser.releases(from: response)
    }

    func releaseAssetData(_ asset: GitHubReleaseAsset, in repository: GitHubRepository) async throws -> Data {
        try await api([
            "-H", "Accept: application/octet-stream",
            "-X", "GET",
            "repos/\(repository.fullName)/releases/assets/\(asset.id)"
        ])
    }

    func downloadReleaseAsset(
        _ asset: GitHubReleaseAsset,
        tag: String,
        in repository: GitHubRepository,
        to directory: URL
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = try await execute(
            arguments: [
                "release", "download", tag,
                "--repo", repository.fullName,
                "--pattern", asset.name,
                "--dir", directory.path,
                "--clobber"
            ],
            currentDirectoryURL: directory
        )
        let downloaded = directory.appendingPathComponent(asset.name)
        guard FileManager.default.fileExists(atPath: downloaded.path) else {
            throw GitHubServiceError.invalidResponse
        }
        return downloaded
    }

    func marketplaceRelease(for repository: GitHubRepository) async throws -> GitHubRelease? {
        let key = repository.fullName.lowercased()
        let now = Date()
        if let cached = marketplaceReleaseCache[key] {
            if cached.expiresAt > now {
                return cached.release
            }
            marketplaceReleaseCache[key] = nil
        }
        let response = try await api([
            "-X", "GET",
            "repos/\(repository.fullName)/releases",
            "-f", "per_page=10",
            "-f", "page=1"
        ])
        let release = try GitHubAPIParser.releases(from: response)
            .first(where: { !$0.assets.isEmpty })
        marketplaceReleaseCache[key] = MarketplaceReleaseCacheEntry(
            release: release,
            expiresAt: now.addingTimeInterval(600)
        )
        if marketplaceReleaseCache.count > 192,
           let oldestKey = marketplaceReleaseCache.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
            marketplaceReleaseCache[oldestKey] = nil
        }
        return release
    }

    func isStarred(_ repository: GitHubRepository) async throws -> Bool {
        do {
            _ = try await api(["-X", "GET", "user/starred/\(repository.fullName)"])
            return true
        } catch GitHubServiceError.resourceNotFound {
            return false
        }
    }

    func setStarred(_ starred: Bool, repository: GitHubRepository) async throws {
        _ = try await api([
            "-X", starred ? "PUT" : "DELETE",
            "user/starred/\(repository.fullName)"
        ])
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
                  let mimeType = GitHubReadmeHTML.imageMIMEType(for: path) else { continue }
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

    func pullRequestReviewCenter(
        for pullRequest: GitHubPullRequest,
        in repository: GitHubRepository
    ) async throws -> GitHubPullRequestReviewCenter {
        let root = "repos/\(repository.fullName)/pulls/\(pullRequest.number)"
        let reviews = try GitHubAPIParser.pullRequestReviews(from: await paginated("\(root)/reviews"))
        let issueComments = try GitHubAPIParser.pullRequestComments(
            from: await paginated("repos/\(repository.fullName)/issues/\(pullRequest.number)/comments"),
            kind: .conversation
        )
        let reviewComments = try GitHubAPIParser.pullRequestComments(
            from: await paginated("\(root)/comments"),
            kind: .review
        )
        let commits = try GitHubAPIParser.pullRequestCommits(from: await paginated("\(root)/commits"))
        let files = try GitHubAPIParser.pullRequestFiles(from: await paginated("\(root)/files"))
        let checksResponse = try await api([
            "--paginate", "--slurp",
            "-H", "Accept: application/vnd.github+json",
            "-X", "GET",
            "repos/\(repository.fullName)/commits/\(pullRequest.headSHA)/check-runs",
            "-f", "per_page=100"
        ])
        let checks = try GitHubAPIParser.pullRequestChecks(from: checksResponse)
        return GitHubPullRequestReviewCenter(
            reviews: reviews,
            comments: (issueComments + reviewComments).sorted { $0.createdAt < $1.createdAt },
            commits: commits,
            files: files,
            checks: checks
        )
    }

    func submitPullRequestReview(
        body: String,
        event: GitHubPullRequestReviewEvent,
        to pullRequest: GitHubPullRequest,
        in repository: GitHubRepository
    ) async throws {
        _ = try await api([
            "-X", "POST",
            "repos/\(repository.fullName)/pulls/\(pullRequest.number)/reviews",
            "-f", "body=\(body)",
            "-f", "event=\(event.rawValue)"
        ])
    }

    func postPullRequestReviewComment(
        body: String,
        path: String,
        line: Int,
        startLine: Int?,
        to pullRequest: GitHubPullRequest,
        in repository: GitHubRepository
    ) async throws {
        var arguments = [
            "-X", "POST",
            "repos/\(repository.fullName)/pulls/\(pullRequest.number)/comments",
            "-f", "body=\(body)",
            "-f", "commit_id=\(pullRequest.headSHA)",
            "-f", "path=\(path)",
            "-F", "line=\(line)",
            "-f", "side=RIGHT"
        ]
        if let startLine, startLine < line {
            arguments.append(contentsOf: ["-F", "start_line=\(startLine)", "-f", "start_side=RIGHT"])
        }
        _ = try await api(arguments)
    }

    func markPullRequestFile(
        _ path: String,
        viewed: Bool,
        in pullRequest: GitHubPullRequest
    ) async throws {
        let field = viewed ? "markFileAsViewed" : "unmarkFileAsViewed"
        let query = "mutation($pullRequestId:ID!,$path:String!){\(field)(input:{pullRequestId:$pullRequestId,path:$path}){clientMutationId}}"
        _ = try await api([
            "graphql",
            "-f", "query=\(query)",
            "-f", "pullRequestId=\(pullRequest.nodeID)",
            "-f", "path=\(path)"
        ])
    }

    func deliveryPullRequest(
        headBranch: String,
        targetSHA: String,
        in repository: GitHubRepository
    ) async throws -> (pullRequest: GitHubDeliveryPullRequest?, defaultBranch: String) {
        let settings = try GitHubAPIParser.deliveryRepositorySettings(
            from: await api(["repos/\(repository.fullName)"])
        )
        let response = try await api([
            "-X", "GET",
            "repos/\(repository.fullName)/pulls",
            "-f", "state=all",
            "-f", "head=\(repository.owner):\(headBranch)",
            "-f", "sort=updated",
            "-f", "direction=desc",
            "-f", "per_page=100"
        ])
        let candidates = try GitHubAPIParser.deliveryPullRequestCandidates(from: response)
        guard let candidate = candidates.first(where: { $0.headSHA == targetSHA })
            ?? candidates.first(where: { $0.headBranch == headBranch && !$0.isClosed })
            ?? candidates.first(where: { $0.headBranch == headBranch }) else {
            return (nil, settings.defaultBranch)
        }
        let detailResponse = try await api(["repos/\(repository.fullName)/pulls/\(candidate.number)"])
        let reviewsResponse = try await paginated("repos/\(repository.fullName)/pulls/\(candidate.number)/reviews")
        let reviewResponse = try await api([
            "graphql",
            "-f", "query=\(Self.deliveryReviewQuery)",
            "-f", "owner=\(repository.owner)",
            "-f", "name=\(repository.name)",
            "-F", "number=\(candidate.number)"
        ])
        let model = try GitHubAPIParser.deliveryPullRequest(
            detail: detailResponse,
            reviews: reviewsResponse,
            reviewSummary: reviewResponse
        )
        return (model, settings.defaultBranch)
    }

    func createDeliveryPullRequest(
        title: String,
        body: String,
        headBranch: String,
        baseBranch: String,
        in repository: GitHubRepository
    ) async throws {
        _ = try await api([
            "-X", "POST",
            "repos/\(repository.fullName)/pulls",
            "-f", "title=\(title)",
            "-f", "body=\(body)",
            "-f", "head=\(headBranch)",
            "-f", "base=\(baseBranch)"
        ])
    }

    func mergeDeliveryPullRequest(
        number: Int,
        in repository: GitHubRepository
    ) async throws {
        let settings = try GitHubAPIParser.deliveryRepositorySettings(
            from: await api(["repos/\(repository.fullName)"])
        )
        let method: String
        if settings.allowsMergeCommit {
            method = "merge"
        } else if settings.allowsSquashMerge {
            method = "squash"
        } else if settings.allowsRebaseMerge {
            method = "rebase"
        } else {
            throw GitHubServiceError.invalidResponse
        }
        let response = try await api([
            "-X", "PUT",
            "repos/\(repository.fullName)/pulls/\(number)/merge",
            "-f", "merge_method=\(method)"
        ])
        let result = try GitHubAPIParser.deliveryMergeResult(from: response)
        guard result.merged else {
            throw GitHubServiceError.commandFailed(result.message)
        }
    }

    private static let deliveryReviewQuery = """
    query($owner:String!,$name:String!,$number:Int!){
      repository(owner:$owner,name:$name){
        pullRequest(number:$number){
          reviewDecision
          reviewThreads(first:100){
            nodes{isResolved}
            pageInfo{hasNextPage}
          }
        }
      }
    }
    """

    func actionWorkflows(for repository: GitHubRepository) async throws -> [GitHubActionsWorkflow] {
        let response = try await api([
            "--paginate", "--slurp", "-X", "GET",
            "repos/\(repository.fullName)/actions/workflows", "-f", "per_page=100"
        ])
        return try GitHubAPIParser.actionWorkflows(from: response)
    }

    func actionRuns(for repository: GitHubRepository) async throws -> [GitHubActionsRun] {
        let response = try await api([
            "--paginate", "--slurp", "-X", "GET",
            "repos/\(repository.fullName)/actions/runs", "-f", "per_page=100"
        ])
        return try GitHubAPIParser.actionRuns(from: response)
    }

    func actionRunDetail(
        _ run: GitHubActionsRun,
        in repository: GitHubRepository,
        includeLog: Bool
    ) async throws -> GitHubActionsRunDetail {
        let jobsResponse = try await api([
            "--paginate", "--slurp", "-X", "GET",
            "repos/\(repository.fullName)/actions/runs/\(run.id)/jobs", "-f", "per_page=100"
        ])
        let artifactsResponse = try await api([
            "--paginate", "--slurp", "-X", "GET",
            "repos/\(repository.fullName)/actions/runs/\(run.id)/artifacts", "-f", "per_page=100"
        ])
        var log: String?
        var logError: String?
        if includeLog {
            do {
                let output = try await execute(
                    arguments: ["run", "view", String(run.id), "--repo", repository.fullName, "--log"],
                    currentDirectoryURL: nil
                )
                log = String(decoding: output.standardOutput, as: UTF8.self)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logError = error.localizedDescription
            }
        }
        return GitHubActionsRunDetail(
            jobs: try GitHubAPIParser.actionJobs(from: jobsResponse),
            artifacts: try GitHubAPIParser.actionArtifacts(from: artifactsResponse),
            log: log,
            logError: logError
        )
    }

    func rerunActionRun(
        _ run: GitHubActionsRun,
        failedOnly: Bool,
        in repository: GitHubRepository
    ) async throws {
        let action = failedOnly ? "rerun-failed-jobs" : "rerun"
        _ = try await api([
            "-X", "POST",
            "repos/\(repository.fullName)/actions/runs/\(run.id)/\(action)"
        ])
    }

    func cancelActionRun(_ run: GitHubActionsRun, in repository: GitHubRepository) async throws {
        _ = try await api([
            "-X", "POST",
            "repos/\(repository.fullName)/actions/runs/\(run.id)/cancel"
        ])
    }

    func downloadActionArtifact(
        _ artifact: GitHubActionsArtifact,
        for run: GitHubActionsRun,
        to destination: URL,
        in repository: GitHubRepository
    ) async throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = try await execute(
            arguments: [
                "run", "download", String(run.id), "--repo", repository.fullName,
                "--name", artifact.name, "--dir", destination.path
            ],
            currentDirectoryURL: destination
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

    func cloneReadmeWorkspace(_ repository: GitHubRepository, into parentDirectory: URL) async throws -> URL {
        let destination = parentDirectory.appendingPathComponent(repository.name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw GitHubServiceError.destinationExists
        }
        _ = try await execute(
            arguments: [
                "repo", "clone", repository.fullName, destination.path,
                "--", "--depth=1"
            ],
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
        let invocations = Array(currentInvocations.values)
        currentInvocations.removeAll()
        for invocation in invocations {
            invocation.cancel()
        }
    }

    func api(_ arguments: [String]) async throws -> Data {
        try await execute(arguments: ["api"] + arguments, currentDirectoryURL: nil).standardOutput
    }

    private func paginated(_ endpoint: String) async throws -> Data {
        try await api([
            "--paginate", "--slurp", "-X", "GET", endpoint, "-f", "per_page=100"
        ])
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
        let invocationID = UUID()
        currentInvocations[invocationID] = invocation
        defer {
            currentInvocations[invocationID] = nil
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

    static func repository(from data: Data) throws -> GitHubRepository {
        try decode(RepositoryPayload.self, from: data).model
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

    fileprivate static func deliveryRepositorySettings(from data: Data) throws -> DeliveryRepositorySettingsPayload {
        try decode(DeliveryRepositorySettingsPayload.self, from: data)
    }

    fileprivate static func deliveryPullRequestCandidates(from data: Data) throws -> [DeliveryPullRequestPayload] {
        try decode([DeliveryPullRequestPayload].self, from: data)
    }

    fileprivate static func deliveryPullRequestDetail(from data: Data) throws -> DeliveryPullRequestPayload {
        try decode(DeliveryPullRequestPayload.self, from: data)
    }

    fileprivate static func deliveryReviewSummary(from data: Data) throws -> DeliveryReviewGraphQLPayload.Summary {
        try decode(DeliveryReviewGraphQLPayload.self, from: data).summary
    }

    fileprivate static func deliveryMergeResult(from data: Data) throws -> DeliveryMergePayload {
        try decode(DeliveryMergePayload.self, from: data)
    }

    static func pullRequestReviews(from data: Data) throws -> [GitHubPullRequestReview] {
        try decodePages(ReviewPayload.self, from: data).map(\.model)
    }

    static func deliveryPullRequest(
        detail detailData: Data,
        reviews reviewData: Data,
        reviewSummary summaryData: Data
    ) throws -> GitHubDeliveryPullRequest {
        let detail = try deliveryPullRequestDetail(from: detailData)
        let reviews = try pullRequestReviews(from: reviewData)
        let latestReviews = Dictionary(grouping: reviews, by: \.author).compactMap { _, values in
            values.max { lhs, rhs in
                (lhs.submittedAt ?? .distantPast) < (rhs.submittedAt ?? .distantPast)
            }
        }
        let reviewSummary = try deliveryReviewSummary(from: summaryData)
        return GitHubDeliveryPullRequest(
            number: detail.number,
            title: detail.title,
            webURL: detail.webURL,
            headBranch: detail.headBranch,
            headSHA: detail.headSHA,
            baseBranch: detail.baseBranch,
            isDraft: detail.isDraft,
            isMerged: detail.isMerged,
            isClosed: detail.isClosed,
            mergeable: detail.mergeable,
            reviewDecision: reviewSummary.reviewDecision,
            approvalCount: latestReviews.filter {
                $0.state.caseInsensitiveCompare("APPROVED") == .orderedSame
            }.count,
            changesRequestedCount: latestReviews.filter {
                $0.state.caseInsensitiveCompare("CHANGES_REQUESTED") == .orderedSame
            }.count,
            requestedReviewerCount: detail.requestedReviewerCount,
            unresolvedThreadCount: reviewSummary.unresolvedThreadCount,
            hasUnscannedReviewThreads: reviewSummary.hasMoreThreads
        )
    }

    static func pullRequestComments(
        from data: Data,
        kind: GitHubPullRequestComment.Kind
    ) throws -> [GitHubPullRequestComment] {
        try decodePages(CommentPayload.self, from: data).map { $0.model(kind: kind) }
    }

    static func pullRequestCommits(from data: Data) throws -> [GitHubPullRequestCommit] {
        try decodePages(PullRequestCommitPayload.self, from: data).map(\.model)
    }

    static func pullRequestFiles(from data: Data) throws -> [GitHubPullRequestFile] {
        try decodePages(PullRequestFilePayload.self, from: data).map(\.model)
    }

    static func pullRequestChecks(from data: Data) throws -> [GitHubPullRequestCheck] {
        if let pages = try? decode([CheckRunsResponse].self, from: data) {
            return pages.flatMap(\.checkRuns).map(\.model)
        }
        return try decode(CheckRunsResponse.self, from: data).checkRuns.map(\.model)
    }

    static func actionWorkflows(from data: Data) throws -> [GitHubActionsWorkflow] {
        if let pages = try? decode([WorkflowsResponse].self, from: data) {
            return pages.flatMap(\.workflows).map(\.model)
        }
        return try decode(WorkflowsResponse.self, from: data).workflows.map(\.model)
    }

    static func actionRuns(from data: Data) throws -> [GitHubActionsRun] {
        if let pages = try? decode([ActionRunsResponse].self, from: data) {
            return pages.flatMap(\.workflowRuns).map(\.model)
        }
        return try decode(ActionRunsResponse.self, from: data).workflowRuns.map(\.model)
    }

    static func actionJobs(from data: Data) throws -> [GitHubActionsJob] {
        if let pages = try? decode([ActionJobsResponse].self, from: data) {
            return pages.flatMap(\.jobs).map(\.model)
        }
        return try decode(ActionJobsResponse.self, from: data).jobs.map(\.model)
    }

    static func actionArtifacts(from data: Data) throws -> [GitHubActionsArtifact] {
        if let pages = try? decode([ActionArtifactsResponse].self, from: data) {
            return pages.flatMap(\.artifacts).map(\.model)
        }
        return try decode(ActionArtifactsResponse.self, from: data).artifacts.map(\.model)
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

    static func releases(from data: Data) throws -> [GitHubRelease] {
        let payloads: [ReleasePayload]
        if let pages = try? decode([[ReleasePayload]].self, from: data) {
            payloads = pages.flatMap { $0 }
        } else {
            payloads = try decode([ReleasePayload].self, from: data)
        }
        return payloads
            .filter { !$0.draft }
            .map(\.model)
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
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

    private static func decodePages<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        if let pages = try? decode([[T]].self, from: data) {
            return pages.flatMap { $0 }
        }
        return try decode([T].self, from: data)
    }
}

enum GitHubFuzzySearch {
    static func sorted(_ repositories: [GitHubRepository], query: String) -> [GitHubRepository] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return repositories }
        return repositories.sorted { lhs, rhs in
            let left = min(score(candidate: lhs.fullName, query: needle), score(candidate: lhs.name, query: needle))
            let right = min(score(candidate: rhs.fullName, query: needle), score(candidate: rhs.name, query: needle))
            if left != right { return left < right }
            if lhs.stars != rhs.stars { return lhs.stars > rhs.stars }
            return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
        }
    }

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

    static func normalize(_ value: String) -> String {
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

private struct LocalMarkdownPayload: Encodable {
    let text: String
    let mode: String
    let context: String
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
    struct Branch: Decodable {
        let ref: String
        let sha: String
    }

    let number: Int
    let title: String
    let user: User
    let body: String?
    let htmlURL: URL
    let draft: Bool
    let nodeID: String
    let head: Branch
    let base: Branch
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case number, title, user, body, draft, head, base
        case htmlURL = "html_url"
        case nodeID = "node_id"
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
            headSHA: head.sha,
            baseBranch: base.ref,
            nodeID: nodeID,
            updatedAt: updatedAt
        )
    }
}

fileprivate struct DeliveryRepositorySettingsPayload: Decodable {
    let defaultBranch: String
    let allowsMergeCommit: Bool
    let allowsSquashMerge: Bool
    let allowsRebaseMerge: Bool

    enum CodingKeys: String, CodingKey {
        case defaultBranch = "default_branch"
        case allowsMergeCommit = "allow_merge_commit"
        case allowsSquashMerge = "allow_squash_merge"
        case allowsRebaseMerge = "allow_rebase_merge"
    }
}

fileprivate struct DeliveryPullRequestPayload: Decodable {
    struct Branch: Decodable {
        let ref: String
        let sha: String
    }

    let number: Int
    let title: String
    let htmlURL: URL
    let state: String
    let draft: Bool
    let mergedAt: Date?
    let mergeable: Bool?
    let head: Branch
    let base: Branch
    let requestedReviewers: [RequestedReviewer]?

    struct RequestedReviewer: Decodable {
        let login: String
    }

    enum CodingKeys: String, CodingKey {
        case number, title, state, draft, mergeable, head, base
        case htmlURL = "html_url"
        case mergedAt = "merged_at"
        case requestedReviewers = "requested_reviewers"
    }

    var webURL: URL { htmlURL }
    var headBranch: String { head.ref }
    var headSHA: String { head.sha }
    var baseBranch: String { base.ref }
    var isDraft: Bool { draft }
    var isMerged: Bool { mergedAt != nil }
    var isClosed: Bool { state.caseInsensitiveCompare("closed") == .orderedSame && !isMerged }
    var requestedReviewerCount: Int { requestedReviewers?.count ?? 0 }
}

fileprivate struct DeliveryReviewGraphQLPayload: Decodable {
    struct DataPayload: Decodable {
        let repository: RepositoryPayload?
    }

    struct RepositoryPayload: Decodable {
        let pullRequest: PullRequestPayload?
    }

    struct PullRequestPayload: Decodable {
        let reviewDecision: String?
        let reviewThreads: ReviewThreadsPayload
    }

    struct ReviewThreadsPayload: Decodable {
        let nodes: [ReviewThreadPayload]
        let pageInfo: PageInfoPayload
    }

    struct ReviewThreadPayload: Decodable {
        let isResolved: Bool
    }

    struct PageInfoPayload: Decodable {
        let hasNextPage: Bool
    }

    struct Summary {
        let reviewDecision: String?
        let unresolvedThreadCount: Int
        let hasMoreThreads: Bool
    }

    let data: DataPayload

    var summary: Summary {
        guard let pullRequest = data.repository?.pullRequest else {
            return Summary(reviewDecision: nil, unresolvedThreadCount: 0, hasMoreThreads: false)
        }
        return Summary(
            reviewDecision: pullRequest.reviewDecision,
            unresolvedThreadCount: pullRequest.reviewThreads.nodes.filter { !$0.isResolved }.count,
            hasMoreThreads: pullRequest.reviewThreads.pageInfo.hasNextPage
        )
    }
}

fileprivate struct DeliveryMergePayload: Decodable {
    let merged: Bool
    let message: String
}

private struct ReviewPayload: Decodable {
    struct User: Decodable { let login: String }
    let id: Int64
    let user: User
    let body: String?
    let state: String
    let submittedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, user, body, state
        case submittedAt = "submitted_at"
    }

    var model: GitHubPullRequestReview {
        GitHubPullRequestReview(id: id, author: user.login, body: body, state: state, submittedAt: submittedAt)
    }
}

private struct CommentPayload: Decodable {
    struct User: Decodable { let login: String }
    let id: Int64
    let user: User
    let body: String
    let createdAt: Date
    let path: String?
    let line: Int?

    enum CodingKeys: String, CodingKey {
        case id, user, body, path, line
        case createdAt = "created_at"
    }

    func model(kind: GitHubPullRequestComment.Kind) -> GitHubPullRequestComment {
        GitHubPullRequestComment(
            id: id,
            author: user.login,
            body: body,
            createdAt: createdAt,
            path: path,
            line: line,
            kind: kind
        )
    }
}

private struct PullRequestCommitPayload: Decodable {
    struct Commit: Decodable {
        struct Author: Decodable {
            let name: String
            let date: Date?
        }
        let message: String
        let author: Author?
    }
    let sha: String
    let commit: Commit

    var model: GitHubPullRequestCommit {
        GitHubPullRequestCommit(
            sha: sha,
            message: commit.message,
            author: commit.author?.name ?? "—",
            date: commit.author?.date
        )
    }
}

private struct PullRequestFilePayload: Decodable {
    let filename: String
    let status: String
    let additions: Int
    let deletions: Int
    let changes: Int
    let patch: String?

    var model: GitHubPullRequestFile {
        GitHubPullRequestFile(
            path: filename,
            status: status,
            additions: additions,
            deletions: deletions,
            changes: changes,
            patch: patch
        )
    }
}

private struct CheckRunsResponse: Decodable {
    let checkRuns: [CheckRunPayload]
    enum CodingKeys: String, CodingKey { case checkRuns = "check_runs" }
}

private struct CheckRunPayload: Decodable {
    let id: Int64
    let name: String
    let status: String
    let conclusion: String?
    let detailsURL: URL?
    let startedAt: Date?
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion
        case detailsURL = "details_url"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }

    var model: GitHubPullRequestCheck {
        GitHubPullRequestCheck(
            id: id,
            name: name,
            status: status,
            conclusion: conclusion,
            detailsURL: detailsURL,
            startedAt: startedAt,
            completedAt: completedAt
        )
    }
}

private struct WorkflowsResponse: Decodable { let workflows: [WorkflowPayload] }
private struct WorkflowPayload: Decodable {
    let id: Int64
    let name: String
    let path: String
    let state: String
    var model: GitHubActionsWorkflow { .init(id: id, name: name, path: path, state: state) }
}

private struct ActionRunsResponse: Decodable {
    let workflowRuns: [ActionRunPayload]
    enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" }
}

private struct ActionRunPayload: Decodable {
    struct Actor: Decodable { let login: String }
    let id: Int64
    let workflowID: Int64
    let name: String?
    let displayTitle: String
    let event: String
    let status: String
    let conclusion: String?
    let headBranch: String?
    let headSHA: String
    let runNumber: Int
    let actor: Actor?
    let createdAt: Date
    let updatedAt: Date
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case id, name, event, status, conclusion, actor
        case workflowID = "workflow_id"
        case displayTitle = "display_title"
        case headBranch = "head_branch"
        case headSHA = "head_sha"
        case runNumber = "run_number"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case htmlURL = "html_url"
    }

    var model: GitHubActionsRun {
        GitHubActionsRun(
            id: id,
            workflowID: workflowID,
            name: name ?? displayTitle,
            displayTitle: displayTitle,
            event: event,
            status: status,
            conclusion: conclusion,
            branch: headBranch,
            headSHA: headSHA,
            runNumber: runNumber,
            actor: actor?.login ?? "—",
            createdAt: createdAt,
            updatedAt: updatedAt,
            webURL: htmlURL
        )
    }
}

private struct ActionJobsResponse: Decodable { let jobs: [ActionJobPayload] }
private struct ActionJobPayload: Decodable {
    let id: Int64
    let name: String
    let status: String
    let conclusion: String?
    let startedAt: Date?
    let completedAt: Date?
    let htmlURL: URL?
    let steps: [ActionStepPayload]?

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion, steps
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case htmlURL = "html_url"
    }

    var model: GitHubActionsJob {
        GitHubActionsJob(
            id: id,
            name: name,
            status: status,
            conclusion: conclusion,
            startedAt: startedAt,
            completedAt: completedAt,
            webURL: htmlURL,
            steps: (steps ?? []).map(\.model)
        )
    }
}

private struct ActionStepPayload: Decodable {
    let number: Int
    let name: String
    let status: String
    let conclusion: String?
    let startedAt: Date?
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case number, name, status, conclusion
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }

    var model: GitHubActionsStep {
        GitHubActionsStep(
            number: number,
            name: name,
            status: status,
            conclusion: conclusion,
            startedAt: startedAt,
            completedAt: completedAt
        )
    }
}

private struct ActionArtifactsResponse: Decodable { let artifacts: [ActionArtifactPayload] }
private struct ActionArtifactPayload: Decodable {
    let id: Int64
    let name: String
    let sizeInBytes: Int
    let expired: Bool
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, expired
        case sizeInBytes = "size_in_bytes"
        case expiresAt = "expires_at"
    }

    var model: GitHubActionsArtifact {
        GitHubActionsArtifact(
            id: id,
            name: name,
            sizeInBytes: sizeInBytes,
            isExpired: expired,
            expiresAt: expiresAt
        )
    }
}

private struct ContentItemPayload: Decodable {
    let type: String
    let name: String
    let path: String
    let size: Int
    let htmlURL: URL?
    let downloadURL: URL?

    enum CodingKeys: String, CodingKey {
        case type, name, path, size
        case htmlURL = "html_url"
        case downloadURL = "download_url"
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
            webURL: htmlURL,
            downloadURL: downloadURL
        )
    }
}

private struct ReleasePayload: Decodable {
    let id: Int64
    let tagName: String
    let name: String?
    let body: String?
    let publishedAt: Date?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [ReleaseAssetPayload]

    enum CodingKeys: String, CodingKey {
        case id, name, body, draft, prerelease, assets
        case tagName = "tag_name"
        case publishedAt = "published_at"
        case htmlURL = "html_url"
    }

    var model: GitHubRelease {
        GitHubRelease(
            id: id,
            tagName: tagName,
            name: name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? tagName,
            body: body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            publishedAt: publishedAt,
            webURL: htmlURL,
            isPrerelease: prerelease,
            assets: assets.map(\.model)
        )
    }
}

private struct ReleaseAssetPayload: Decodable {
    let id: Int64
    let name: String
    let size: Int64
    let downloadCount: Int
    let contentType: String
    let browserDownloadURL: URL
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, size
        case downloadCount = "download_count"
        case contentType = "content_type"
        case browserDownloadURL = "browser_download_url"
        case createdAt = "created_at"
    }

    var model: GitHubReleaseAsset {
        GitHubReleaseAsset(
            id: id,
            name: name,
            size: size,
            downloadCount: downloadCount,
            contentType: contentType,
            downloadURL: browserDownloadURL,
            createdAt: createdAt
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private enum GitHubPreviewFileKind {
    case none
    case image(String)
    case video(String)
    case svg

    init(fileName: String) {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch RepositoryMediaKind(fileName: fileName) {
        case .image: self = .image(ext)
        case .video: self = .video(ext)
        case .svg: self = .svg
        case nil: self = .none
        }
    }

    var maximumFetchedSize: Int {
        switch self {
        case .none: 1_500_000
        case .image, .svg: 25_000_000
        case .video: 250_000_000
        }
    }

    func cache(_ data: Data, repositoryName: String, path: String) throws -> URL? {
        let fileExtension: String
        switch self {
        case .none: return nil
        case let .image(ext), let .video(ext): fileExtension = ext
        case .svg: fileExtension = "svg"
        }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GitGatto/GitHubPreviews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory
            .appendingPathComponent(StableHash.hex("\(repositoryName):\(path)"))
            .appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }
}

private struct GitHubCommandOutput: Sendable {
    let standardOutput: Data
    let standardError: Data
    let exitCode: Int32
}

private struct MarketplaceReleaseCacheEntry: Sendable {
    let release: GitHubRelease?
    let expiresAt: Date
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
