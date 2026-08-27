import Foundation
import Testing
@testable import GitGatto

@Suite("GitHub API parser")
struct GitHubAPIParserTests {
    @Test("Decodes the authenticated account without credential material")
    func decodesAccount() throws {
        let payload = """
        {
          "login": "octocat",
          "name": "The Octocat",
          "html_url": "https://github.com/octocat"
        }
        """

        let account = try GitHubAPIParser.account(from: Data(payload.utf8))

        #expect(account.login == "octocat")
        #expect(account.name == "The Octocat")
    }

    @Test("Flattens paginated repositories available to the account")
    func decodesAccountRepositories() throws {
        let repository = """
        {
          "full_name": "octocat/Hello-World",
          "name": "Hello-World",
          "owner": {"login": "octocat"},
          "description": null,
          "html_url": "https://github.com/octocat/Hello-World",
          "stargazers_count": 1,
          "forks_count": 2,
          "open_issues_count": 3,
          "language": null,
          "updated_at": "2026-08-25T12:30:00Z",
          "private": true,
          "default_branch": "main"
        }
        """
        let payload = "[[\(repository)], [\(repository)]]"

        let repositories = try GitHubAPIParser.accountRepositories(from: Data(payload.utf8))

        #expect(repositories.count == 2)
        #expect(repositories.allSatisfy { $0.isPrivate })
    }

    @Test("Decodes real repository search fields")
    func decodesRepositorySearch() throws {
        let payload = """
        {
          "items": [{
            "full_name": "octocat/Hello-World",
            "name": "Hello-World",
            "owner": {"login": "octocat"},
            "description": "Example repository",
            "html_url": "https://github.com/octocat/Hello-World",
            "stargazers_count": 1234,
            "forks_count": 456,
            "open_issues_count": 7,
            "language": "Swift",
            "updated_at": "2026-08-25T12:30:00Z",
            "private": false,
            "default_branch": "main"
          }]
        }
        """

        let repositories = try GitHubAPIParser.repositories(from: Data(payload.utf8))

        #expect(repositories.first?.fullName == "octocat/Hello-World")
        #expect(repositories.first?.stars == 1234)
        #expect(repositories.first?.defaultBranch == "main")
    }

    @Test("Decodes developer search and profile fields")
    func decodesDevelopers() throws {
        let searchPayload = """
        {
          "items": [{
            "login": "the-octocat",
            "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4",
            "html_url": "https://github.com/the-octocat",
            "type": "User"
          }]
        }
        """
        let profilePayload = """
        {
          "login": "the-octocat",
          "name": "The Octocat",
          "bio": "GitHub mascot",
          "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4",
          "html_url": "https://github.com/the-octocat",
          "type": "User",
          "company": "@github",
          "location": "San Francisco",
          "followers": 120,
          "public_repos": 8
        }
        """

        let developers = try GitHubAPIParser.developers(from: Data(searchPayload.utf8))
        let profile = try GitHubAPIParser.developerProfile(from: Data(profilePayload.utf8))

        #expect(developers.first?.login == "the-octocat")
        #expect(profile.name == "The Octocat")
        #expect(profile.followers == 120)
        #expect(profile.publicRepositories == 8)
    }

    @Test("Ranks fuzzy username matches before distant results")
    func ranksFuzzyDevelopers() throws {
        let url = try #require(URL(string: "https://github.com/example"))
        let avatar = try #require(URL(string: "https://avatars.githubusercontent.com/u/1"))
        let developers = ["other-user", "octocat", "the-octocat"].map {
            GitHubDeveloperSummary(login: $0, avatarURL: avatar, webURL: url, accountType: "User")
        }

        let sorted = GitHubFuzzySearch.sorted(developers, query: "octcat")

        #expect(sorted.first?.login == "octocat")
    }

    @Test("Decodes pull request fields used by the reply workflow")
    func decodesPullRequests() throws {
        let payload = """
        [{
          "number": 42,
          "title": "Improve repository loading",
          "user": {"login": "contributor"},
          "body": "Adds cancellation support.",
          "html_url": "https://github.com/octocat/Hello-World/pull/42",
          "draft": false,
          "head": {"ref": "loading-fix"},
          "base": {"ref": "main"},
          "updated_at": "2026-08-25T12:30:00Z"
        }]
        """

        let pullRequests = try GitHubAPIParser.pullRequests(from: Data(payload.utf8))

        #expect(pullRequests.first?.number == 42)
        #expect(pullRequests.first?.headBranch == "loading-fix")
        #expect(pullRequests.first?.baseBranch == "main")
    }

    @Test("Decodes and sorts repository contents")
    func decodesRepositoryContents() throws {
        let payload = """
        [
          {
            "type": "file",
            "name": "README.md",
            "path": "README.md",
            "size": 2048,
            "html_url": "https://github.com/octocat/Hello-World/blob/main/README.md"
          },
          {
            "type": "dir",
            "name": "Sources",
            "path": "Sources",
            "size": 0,
            "html_url": "https://github.com/octocat/Hello-World/tree/main/Sources"
          }
        ]
        """

        let contents = try GitHubAPIParser.contents(from: Data(payload.utf8))

        #expect(contents.map(\.name) == ["Sources", "README.md"])
        #expect(contents.first?.kind == .directory)
        #expect(contents.last?.size == 2048)
    }

    @Test("Encodes each repository path segment")
    func encodesContentPath() {
        let endpoint = GitHubPathEncoder.contentsEndpoint(
            repository: "octocat/Hello-World",
            path: "Sources/My File #1.swift"
        )

        #expect(endpoint == "repos/octocat/Hello-World/contents/Sources/My%20File%20%231.swift")
    }

    @Test("Builds README link and image roots from its real repository path")
    func decodesReadmeMetadata() throws {
        let payload = """
        {
          "path": "docs/README.md",
          "html_url": "https://github.com/octocat/Hello-World/blob/main/docs/README.md",
          "download_url": "https://raw.githubusercontent.com/octocat/Hello-World/main/docs/README.md"
        }
        """

        let metadata = try GitHubAPIParser.readmeMetadata(from: Data(payload.utf8))
        let document = metadata.document(html: "<p>README</p>")

        #expect(document.path == "docs/README.md")
        #expect(document.linkBaseURL.absoluteString == "https://github.com/octocat/Hello-World/blob/main/docs/")
        #expect(document.linkRootURL.absoluteString == "https://github.com/octocat/Hello-World/blob/main/")
        #expect(document.assetBaseURL.absoluteString == "https://raw.githubusercontent.com/octocat/Hello-World/main/docs/")
        #expect(document.assetRootURL.absoluteString == "https://raw.githubusercontent.com/octocat/Hello-World/main/")
    }

    @Test("Resolves README images to raw content while preserving external images")
    func resolvesReadmeImages() throws {
        let html = """
        <a href="./guide.md"><img src="./images/logo.png"></a>
        <img src="/shared/banner.svg">
        <img src="https://images.example.com/external.png">
        """
        let normalized = GitHubReadmeHTML.normalized(
            html,
            linkBaseURL: try #require(URL(string: "https://github.com/octocat/Hello-World/blob/main/docs/")),
            linkRootURL: try #require(URL(string: "https://github.com/octocat/Hello-World/blob/main/")),
            assetBaseURL: try #require(URL(string: "https://raw.githubusercontent.com/octocat/Hello-World/main/docs/")),
            assetRootURL: try #require(URL(string: "https://raw.githubusercontent.com/octocat/Hello-World/main/"))
        )

        #expect(normalized.contains("href=\"https://github.com/octocat/Hello-World/blob/main/docs/guide.md\""))
        #expect(normalized.contains("src=\"https://raw.githubusercontent.com/octocat/Hello-World/main/docs/images/logo.png\""))
        #expect(normalized.contains("src=\"https://raw.githubusercontent.com/octocat/Hello-World/main/shared/banner.svg\""))
        #expect(normalized.contains("src=\"https://images.example.com/external.png\""))
        #expect(GitHubReadmeHTML.repositoryPath(for: "../assets/icon%20dark.png", readmePath: "docs/README.md") == "assets/icon dark.png")
    }

    @Test("Routes repository documentation and code links inside the project detail")
    func routesRepositoryLinks() throws {
        let repository = GitHubRepository(
            fullName: "octocat/Hello-World",
            name: "Hello-World",
            owner: "octocat",
            description: nil,
            webURL: try #require(URL(string: "https://github.com/octocat/Hello-World")),
            stars: 1,
            forks: 2,
            openIssues: 3,
            language: "Swift",
            updatedAt: Date(timeIntervalSince1970: 0),
            isPrivate: false,
            defaultBranch: "release/v1"
        )

        let markdown = try #require(URL(string: "https://github.com/octocat/Hello-World/blob/release/v1/docs/Guide.md"))
        let file = try #require(URL(string: "https://github.com/octocat/Hello-World/blob/release/v1/Sources/App.swift"))
        let directory = try #require(URL(string: "https://github.com/octocat/Hello-World/tree/release/v1/Sources"))
        let external = try #require(URL(string: "https://example.com/reference"))

        #expect(GitHubRepositoryLink.destination(for: markdown, repository: repository) == .markdown(path: "docs/Guide.md"))
        #expect(GitHubRepositoryLink.destination(for: file, repository: repository) == .file(path: "Sources/App.swift"))
        #expect(GitHubRepositoryLink.destination(for: directory, repository: repository) == .directory(path: "Sources"))
        #expect(GitHubRepositoryLink.destination(for: external, repository: repository) == .web(external))
    }
}
