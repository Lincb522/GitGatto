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
        let model = GitHubMarketplaceViewModel(github: fixture)
        model.query = "GitGatto"
        model.search()

        for await applications in model.$applications.values {
            if !applications.isEmpty { break }
        }

        #expect(model.applications.first?.repository.fullName == "Lincb522/GitGatto")
        #expect(model.applications.first?.repository.stars == 1)
        #expect(model.isLoading)

        for await readme in model.$selectedReadme.values {
            if readme != nil { break }
        }
        #expect(model.selectedReadme?.html.contains("Native Git client") == true)
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
            html: #"<p><img src="Assets/AppIcon.svg"></p><h1>Native Git client</h1>"#,
            linkBaseURL: linkRoot,
            linkRootURL: linkRoot,
            assetBaseURL: assetRoot,
            assetRootURL: assetRoot
        )
    }
}
