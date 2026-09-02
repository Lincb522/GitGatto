import Combine
import Foundation
import Testing
@testable import GitGatto

@Suite("GitHub app catalog")
struct GitHubMarketplaceViewModelTests {
    @Test(
        "Finds an exact low-star app and publishes it before all release probes finish",
        .timeLimit(.minutes(2))
    )
    @MainActor
    func findsExactApplicationProgressively() async throws {
        let fixture = try MarketplaceGitHubFixture()
        let model = GitHubMarketplaceViewModel(
            github: fixture,
            automaticTranslationTarget: nil,
            automaticallyTranslates: false
        )
        model.query = "GitGatto"
        model.search()

        for await applications in model.$applications.values {
            if !applications.isEmpty { break }
        }

        #expect(model.applications.first?.repository.fullName == "Lincb522/GitGatto")
        #expect(model.applications.first?.repository.stars == 1)
        #expect(model.isLoading)

        for await logoURL in model.$selectedLogoURL.values {
            if logoURL?.absoluteString.hasSuffix("/Assets/AppIcon.svg") == true { break }
        }
        #expect(model.selectedDetails?.paragraphs.contains(where: { $0.contains("Native Git client") }) == true)
        #expect(model.selectedDetails?.features == ["Review changes before committing"])
        #expect(model.selectedDetails?.screenshots.first?.absoluteString.hasSuffix("/Assets/Preview.png") == true)
        #expect(model.selectedLogoURL?.absoluteString.hasSuffix("/Assets/AppIcon.svg") == true)
        #expect(await fixture.releaseLoadCount == 0)

        model.loadReleasesIfNeeded()
        while await fixture.releaseLoadCount == 0 {
            await Task.yield()
        }
        #expect(await fixture.releaseLoadCount == 1)

        await fixture.finishDelayedRelease()
        for await isLoading in model.$isLoading.values {
            if !isLoading { break }
        }
        #expect(!model.isLoading)
        let queries = await fixture.recordedQueries
        #expect(queries.contains("GitGatto in:name,description,readme"))
        #expect(!queries.contains(where: { $0.contains("stars:") }))
    }

    @Test("Continues repository search beyond the first result page")
    @MainActor
    func continuesSearchBeyondFirstPage() async throws {
        let fixture = try PaginatedMarketplaceGitHubFixture()
        let model = GitHubMarketplaceViewModel(
            github: fixture,
            automaticTranslationTarget: nil,
            automaticallyTranslates: false
        )
        var resultPublicationCount = 0
        let observation = model.$applications.dropFirst().sink { _ in
            resultPublicationCount += 1
        }
        defer { observation.cancel() }
        model.query = "example/App"
        model.search()

        for await isLoading in model.$isLoading.values {
            if !isLoading { break }
        }
        #expect(model.applications.count == 30)
        #expect(resultPublicationCount <= 10)
        #expect(model.canLoadMore)

        model.loadMore()
        for await applications in model.$applications.values {
            if applications.count == 32 { break }
        }
        #expect(model.applications.count == 32)
        #expect(!model.canLoadMore)
        #expect(await fixture.requestedPages == [1, 2])
    }

    @Test("Keeps every supplied screenshot without promoting one to the app logo")
    func keepsEveryScreenshot() throws {
        let linkRoot = try #require(URL(string: "https://github.com/example/App/blob/main/"))
        let assetRoot = try #require(URL(string: "https://raw.githubusercontent.com/example/App/main/"))
        let images = (1...8)
            .map { #"<img src="Screenshots/\#($0).png" alt="Screenshot \#($0)">"# }
            .joined()
        let document = GitHubReadmeDocument(
            path: "README.md",
            html: "<h2>Screenshots</h2>\(images)",
            linkBaseURL: linkRoot,
            linkRootURL: linkRoot,
            assetBaseURL: assetRoot,
            assetRootURL: assetRoot
        )

        let details = MarketplaceApplicationDetailsExtractor.extract(
            from: document,
            repositoryDescription: "Example app"
        )

        #expect(details.screenshots.count == 8)
        #expect(details.screenshots.first?.absoluteString.hasSuffix("/Screenshots/1.png") == true)
        #expect(details.screenshots.last?.absoluteString.hasSuffix("/Screenshots/8.png") == true)
        #expect(details.logoURL == nil)
    }

    @Test("Preserves detailed introduction structure through translation")
    func preservesTranslatedIntroductionStructure() throws {
        let details = MarketplaceApplicationDetails(
            summary: "Native Git client",
            paragraphs: ["Review repositories & releases.", "Manage work without leaving the app."],
            features: ["Inspect changes", "Download releases"],
            screenshots: [],
            logoURL: nil
        )
        let sourceHTML = try #require(
            MarketplaceApplicationDetailsExtractor.translationHTML(
                repositoryDescription: details.summary,
                details: details
            )
        )
        let translatedHTML = sourceHTML
            .replacingOccurrences(of: "Native Git client", with: "原生 Git 客户端")
            .replacingOccurrences(of: "Review repositories &amp; releases.", with: "查看仓库与发行版。")
            .replacingOccurrences(of: "Manage work without leaving the app.", with: "无需离开应用即可管理工作。")
            .replacingOccurrences(of: "Inspect changes", with: "检查改动")
            .replacingOccurrences(of: "Download releases", with: "下载发行版")
        let translated = try #require(
            MarketplaceApplicationDetailsExtractor.translatedText(from: translatedHTML)
        )

        #expect(translated.repositoryDescription == "原生 Git 客户端")
        #expect(translated.paragraphs == ["查看仓库与发行版。", "无需离开应用即可管理工作。"])
        #expect(translated.features == ["检查改动", "下载发行版"])
    }

    @Test("Detects the source language and translates the complete application automatically")
    @MainActor
    func translatesCompleteApplicationDetails() async throws {
        let fixture = try MarketplaceGitHubFixture()
        let translator = MarketplaceTranslationAIFixture()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoMarketplaceTranslationFlow-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = GitHubMarketplaceViewModel(
            github: fixture,
            translationAI: translator,
            translationStore: MarketplaceTranslationStore(directoryURL: directory),
            automaticTranslationTarget: .simplifiedChinese
        )
        model.query = "GitGatto"
        model.search()

        for await details in model.$selectedDetails.values {
            if details?.paragraphs.isEmpty == false { break }
        }
        await fixture.finishDelayedRelease()
        for await isLoading in model.$isLoading.values {
            if !isLoading { break }
        }
        for await target in model.$activeTranslationTarget.values {
            if target == .simplifiedChinese { break }
        }

        let application = try #require(model.selectedApplication)
        let release = try #require(model.selectedRelease)
        let details = model.displayedDetails(for: application)
        #expect(model.displayedDescription(for: application) == "原生 Git 客户端")
        #expect(details.paragraphs == ["用于仓库管理、审查与协作的原生 Git 客户端。"])
        #expect(details.features == ["提交前检查改动"])
        #expect(model.displayedReleaseNotes(for: release) == "已翻译：Release notes")
    }

    @Test("Loads each discovery feed with its own GitHub ordering")
    @MainActor
    func loadsDiscoveryFeedsWithExpectedOrdering() async throws {
        let fixture = try MarketplaceCollectionsGitHubFixture()
        let model = GitHubMarketplaceViewModel(
            github: fixture,
            automaticTranslationTarget: nil,
            automaticallyTranslates: false
        )

        model.loadIfNeeded()
        for await isLoading in model.$isLoading.values where !isLoading { break }

        var requests = await fixture.searchRequests
        #expect(requests.last?.sort == .updated)
        #expect(requests.last?.query.contains("pushed:>=") == true)

        model.changeFeed(.popular)
        for await isLoading in model.$isLoading.values where !isLoading { break }

        requests = await fixture.searchRequests
        #expect(requests.last?.sort == .stars)
        #expect(requests.last?.query.contains("stars:>=100") == true)
    }

    @Test("Lists GitHub Stars and removes an app after unstar")
    @MainActor
    func managesFavoriteApplications() async throws {
        let fixture = try MarketplaceCollectionsGitHubFixture()
        let model = GitHubMarketplaceViewModel(
            github: fixture,
            automaticTranslationTarget: nil,
            automaticallyTranslates: false
        )

        model.changeCollection(.favorites)
        for await isLoading in model.$isLoading.values where !isLoading { break }
        for await isStarred in model.$isStarred.values where isStarred { break }

        #expect(model.applications.map(\.repository.fullName) == ["example/Alpha"])
        model.toggleStar()
        for await applications in model.$applications.values where applications.isEmpty { break }

        #expect(await fixture.starChanges == [false])
        #expect(model.selectedApplication == nil)
    }

    @Test("Restores installed and recently viewed application collections")
    @MainActor
    func restoresLocalApplicationCollections() async throws {
        let fixture = try MarketplaceCollectionsGitHubFixture()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoMarketplaceHistory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = MarketplaceHistoryStore(directoryURL: directory)
        await history.record("example/Alpha")
        await history.record("example/Beta")
        let model = GitHubMarketplaceViewModel(
            github: fixture,
            historyStore: history,
            automaticTranslationTarget: nil,
            automaticallyTranslates: false
        )

        model.changeCollection(.recent)
        for await isLoading in model.$isLoading.values where !isLoading { break }
        #expect(model.applications.map(\.repository.fullName) == ["example/Beta", "example/Alpha"])

        model.changeCollection(.installed, installedRepositoryNames: ["example/Alpha"])
        for await isLoading in model.$isLoading.values where !isLoading { break }
        #expect(model.applications.map(\.repository.fullName) == ["example/Alpha"])
    }

}

private actor MarketplaceTranslationAIFixture: CodexServing {
    func probe() async -> CodexAvailability {
        .unavailable
    }

    func run(
        prompt: String,
        context: [CodexMessage],
        in repositoryURL: URL,
        mode: CodexRunMode
    ) async throws -> CodexRunResult {
        throw CodexServiceError.executionFailed(-1)
    }

    func runWithProvidedContext(
        prompt: String,
        context: [CodexMessage]
    ) async throws -> CodexRunResult {
        throw CodexServiceError.executionFailed(-1)
    }

    func draftPullRequestReply(context: GitHubPullRequestContext) async throws -> String {
        throw CodexServiceError.executionFailed(-1)
    }

    func translate(_ text: String, target: CodexTranslationTarget) async throws -> String {
        "已翻译：\(text)"
    }

    func translateHTML(
        _ html: String,
        target: CodexTranslationTarget,
        progress: @escaping @Sendable (_ currentBatch: Int, _ totalBatches: Int) async -> Void
    ) async throws -> String {
        await progress(1, 1)
        return html
            .replacingOccurrences(of: "Native Git client", with: "原生 Git 客户端")
            .replacingOccurrences(
                of: "原生 Git 客户端 for repository management, review, and collaboration.",
                with: "用于仓库管理、审查与协作的原生 Git 客户端。"
            )
            .replacingOccurrences(of: "Review changes before committing", with: "提交前检查改动")
    }

    func cancel() async {}
}

private actor MarketplaceGitHubFixture: MarketplaceGitHubServing {
    private let repositories: [GitHubRepository]
    private let release: GitHubRelease
    private(set) var recordedQueries: [String] = []
    private(set) var releaseLoadCount = 0
    private var delayedReleaseContinuation: CheckedContinuation<Void, Never>?
    private var didFinishDelayedRelease = false

    init() throws {
        let repositoryURL = try #require(URL(string: "https://github.com/Lincb522/GitGatto"))
        let otherURL = try #require(URL(string: "https://github.com/example/OtherApp"))
        repositories = [
            GitHubRepository(
                fullName: "Lincb522/GitGatto",
                name: "GitGatto",
                owner: "Lincb522",
                description: "Native Git client",
                webURL: repositoryURL,
                stars: 1,
                forks: 0,
                openIssues: 0,
                language: "Swift",
                updatedAt: Date(),
                isPrivate: false,
                defaultBranch: "main"
            ),
            GitHubRepository(
                fullName: "example/OtherApp",
                name: "OtherApp",
                owner: "example",
                description: nil,
                webURL: otherURL,
                stars: 200,
                forks: 4,
                openIssues: 1,
                language: "Swift",
                updatedAt: Date(),
                isPrivate: false,
                defaultBranch: "main"
            )
        ]
        let assetURL = try #require(
            URL(string: "https://github.com/Lincb522/GitGatto/releases/download/v1/App.dmg")
        )
        release = GitHubRelease(
            id: 1,
            tagName: "v1",
            name: "Version 1",
            body: "Release notes",
            publishedAt: Date(),
            webURL: repositoryURL,
            isPrerelease: false,
            assets: [
                GitHubReleaseAsset(
                    id: 1,
                    name: "App.dmg",
                    size: 1,
                    downloadCount: 0,
                    contentType: "application/x-apple-diskimage",
                    downloadURL: assetURL,
                    createdAt: Date()
                )
            ]
        )
    }

    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepository] {
        recordedQueries.append(query)
        return query.hasPrefix("user:") ? [] : repositories
    }

    func marketplaceRelease(for repository: GitHubRepository) async throws -> GitHubRelease? {
        if repository.name == "OtherApp" {
            if !didFinishDelayedRelease {
                await withCheckedContinuation { continuation in
                    delayedReleaseContinuation = continuation
                }
            }
        }
        return release
    }

    func finishDelayedRelease() {
        didFinishDelayedRelease = true
        delayedReleaseContinuation?.resume()
        delayedReleaseContinuation = nil
    }

    func releases(for repository: GitHubRepository) async throws -> [GitHubRelease] {
        releaseLoadCount += 1
        return [release]
    }

    func readme(for repository: GitHubRepository) async throws -> GitHubReadmeDocument? {
        guard let linkRoot = URL(string: "https://github.com/Lincb522/GitGatto/blob/main/"),
              let assetRoot = URL(string: "https://raw.githubusercontent.com/Lincb522/GitGatto/main/") else {
            return nil
        }
        return GitHubReadmeDocument(
            path: "README.md",
            html: """
            <p><img src="Assets/AppIcon.svg" alt="App icon"></p>
            <h1>GitGatto</h1>
            <p>Native Git client for repository management, review, and collaboration.</p>
            <h2>Features</h2>
            <ul><li>Review changes before committing</li></ul>
            <h2>Screenshots</h2>
            <p><img src="Assets/Preview.png" alt="App screenshot"></p>
            """,
            linkBaseURL: linkRoot,
            linkRootURL: linkRoot,
            assetBaseURL: assetRoot,
            assetRootURL: assetRoot
        )
    }
}

private actor PaginatedMarketplaceGitHubFixture: MarketplaceGitHubServing {
    private let pages: [Int: [GitHubRepository]]
    private let release: GitHubRelease
    private(set) var requestedPages: [Int] = []

    init() throws {
        var pageOne: [GitHubRepository] = []
        var pageTwo: [GitHubRepository] = []
        for index in 0..<32 {
            let repository = GitHubRepository(
                fullName: "example/App\(index)",
                name: "App\(index)",
                owner: "example",
                description: "Application \(index)",
                webURL: try #require(URL(string: "https://github.com/example/App\(index)")),
                stars: 32 - index,
                forks: 0,
                openIssues: 0,
                language: "Swift",
                updatedAt: Date(),
                isPrivate: false,
                defaultBranch: "main"
            )
            if index < 30 {
                pageOne.append(repository)
            } else {
                pageTwo.append(repository)
            }
        }
        pages = [1: pageOne, 2: pageTwo]
        let releaseURL = try #require(URL(string: "https://github.com/example/App/releases/tag/v1"))
        let assetURL = try #require(URL(string: "https://github.com/example/App/releases/download/v1/App.dmg"))
        release = GitHubRelease(
            id: 1,
            tagName: "v1",
            name: "Version 1",
            body: "",
            publishedAt: Date(),
            webURL: releaseURL,
            isPrerelease: false,
            assets: [
                GitHubReleaseAsset(
                    id: 1,
                    name: "App.dmg",
                    size: 1,
                    downloadCount: 0,
                    contentType: "application/x-apple-diskimage",
                    downloadURL: assetURL,
                    createdAt: Date()
                )
            ]
        )
    }

    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepository] {
        requestedPages.append(page)
        return pages[page] ?? []
    }

    func marketplaceRelease(for repository: GitHubRepository) async throws -> GitHubRelease? {
        release
    }

    func releases(for repository: GitHubRepository) async throws -> [GitHubRelease] {
        [release]
    }

    func readme(for repository: GitHubRepository) async throws -> GitHubReadmeDocument? {
        nil
    }
}

private actor MarketplaceCollectionsGitHubFixture: MarketplaceGitHubServing {
    struct SearchRequest: Sendable {
        let query: String
        let page: Int
        let sort: GitHubRepositorySearchSort
    }

    private let repositories: [String: GitHubRepository]
    private let release: GitHubRelease
    private(set) var searchRequests: [SearchRequest] = []
    private(set) var starChanges: [Bool] = []

    init() throws {
        let alphaURL = try #require(URL(string: "https://github.com/example/Alpha"))
        let betaURL = try #require(URL(string: "https://github.com/example/Beta"))
        let alpha = GitHubRepository(
            fullName: "example/Alpha",
            name: "Alpha",
            owner: "example",
            description: "Alpha app",
            webURL: alphaURL,
            stars: 120,
            forks: 2,
            openIssues: 0,
            language: "Swift",
            updatedAt: Date(),
            isPrivate: false,
            defaultBranch: "main"
        )
        let beta = GitHubRepository(
            fullName: "example/Beta",
            name: "Beta",
            owner: "example",
            description: "Beta app",
            webURL: betaURL,
            stars: 80,
            forks: 1,
            openIssues: 0,
            language: "Swift",
            updatedAt: Date(),
            isPrivate: false,
            defaultBranch: "main"
        )
        repositories = [alpha.fullName: alpha, beta.fullName: beta]
        let assetURL = try #require(URL(string: "https://github.com/example/Alpha/releases/download/v1/Alpha.dmg"))
        release = GitHubRelease(
            id: 1,
            tagName: "v1",
            name: "Version 1",
            body: "",
            publishedAt: Date(),
            webURL: alphaURL,
            isPrerelease: false,
            assets: [
                GitHubReleaseAsset(
                    id: 1,
                    name: "Alpha.dmg",
                    size: 1,
                    downloadCount: 0,
                    contentType: "application/x-apple-diskimage",
                    downloadURL: assetURL,
                    createdAt: Date()
                )
            ]
        )
    }

    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepository] {
        Array(repositories.values)
    }

    func searchRepositories(
        query: String,
        page: Int,
        sort: GitHubRepositorySearchSort
    ) async throws -> [GitHubRepository] {
        searchRequests.append(SearchRequest(query: query, page: page, sort: sort))
        return Array(repositories.values)
    }

    func repository(named fullName: String) async throws -> GitHubRepository {
        guard let repository = repositories[fullName] else {
            throw GitHubServiceError.resourceNotFound
        }
        return repository
    }

    func starredRepositories(page: Int) async throws -> [GitHubRepository] {
        repositories["example/Alpha"].map { [$0] } ?? []
    }

    func isStarred(_ repository: GitHubRepository) async throws -> Bool {
        repository.fullName == "example/Alpha" && starChanges.last != false
    }

    func setStarred(_ starred: Bool, repository: GitHubRepository) async throws {
        starChanges.append(starred)
    }

    func marketplaceRelease(for repository: GitHubRepository) async throws -> GitHubRelease? {
        release
    }

    func releases(for repository: GitHubRepository) async throws -> [GitHubRelease] {
        [release]
    }

    func readme(for repository: GitHubRepository) async throws -> GitHubReadmeDocument? {
        nil
    }
}
