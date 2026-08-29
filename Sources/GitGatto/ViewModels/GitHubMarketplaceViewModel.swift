import Combine
import Foundation

@MainActor
final class GitHubMarketplaceViewModel: ObservableObject {
    @Published var query = ""
    @Published var platform: MarketplacePlatform = .macOS
    @Published private(set) var applications: [MarketplaceApplication] = []
    @Published var selectedApplication: MarketplaceApplication?
    @Published private(set) var releases: [GitHubRelease] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isUsingAgent = false
    @Published private(set) var error: String?
    @Published private(set) var agentInstallResult: String?
    @Published private(set) var isAgentInstalling = false

    private let github: any GitHubServing
    private let searchAI: any CodexServing
    private let installerAI: any CodexServing
    private var searchTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?
    private var hasLoaded = false

    init(
        github: any GitHubServing = GitHubService(),
        searchAI: any CodexServing = CodexService(lane: .search),
        installerAI: any CodexServing = CodexService(lane: .installer)
    ) {
        self.github = github
        self.searchAI = searchAI
        self.installerAI = installerAI
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
#if DEBUG
        if ProcessInfo.processInfo.environment["GITGATTO_MARKETPLACE_PREVIEW"] == "1" {
            loadPreviewFixture()
            return
        }
#endif
        search(defaultQuery: true)
    }

    func search(defaultQuery: Bool = false) {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = defaultQuery && input.isEmpty ? defaultSearchQuery : input
        guard !request.isEmpty else { return }
        searchTask?.cancel()
        detailTask?.cancel()
        isLoading = true
        error = nil
        agentInstallResult = nil
        applications = []
        selectedApplication = nil
        releases = []

        let github = self.github
        let platform = self.platform
        searchTask = Task {
            defer {
                isLoading = false
                isUsingAgent = false
            }
            do {
                let shouldUseAgent = !defaultQuery && GitHubSearchQueryResolver.requiresAgent(request)
                isUsingAgent = shouldUseAgent
                let resolved: String
                if shouldUseAgent {
                    resolved = try await searchAI.resolveGitHubSearchQuery(request, scope: .projects)
                } else if defaultQuery {
                    resolved = request
                } else {
                    resolved = GitHubSearchQueryResolver.directQuery(request, scope: .projects)
                }
                let repositories = try await github.searchRepositories(
                    query: "\(resolved) archived:false stars:>=5"
                )
                let candidates = Array(GitHubFuzzySearch.sorted(repositories, query: request).prefix(18))
                let found = await withTaskGroup(of: MarketplaceApplication?.self) { group in
                    for repository in candidates {
                        group.addTask {
                            guard let releases = try? await github.releases(for: repository),
                                  let latest = releases.first(where: { !$0.assets.isEmpty }) else { return nil }
                            let assets = latest.assets.filter { platform.supports($0) }
                            guard platform == .all ? !latest.assets.isEmpty : !assets.isEmpty else { return nil }
                            return MarketplaceApplication(
                                repository: repository,
                                latestRelease: latest,
                                matchingAssets: platform == .all ? latest.assets : assets
                            )
                        }
                    }
                    var values: [MarketplaceApplication] = []
                    for await value in group {
                        if let value { values.append(value) }
                    }
                    return values.sorted {
                        if $0.repository.stars != $1.repository.stars {
                            return $0.repository.stars > $1.repository.stars
                        }
                        return $0.repository.fullName < $1.repository.fullName
                    }
                }
                guard !Task.isCancelled else { return }
                applications = found
                select(found.first)
            } catch is CancellationError {
                return
            } catch {
                self.error = L10n.format("marketplace.error.search", error.localizedDescription)
            }
        }
    }

    func select(_ application: MarketplaceApplication?) {
        detailTask?.cancel()
        selectedApplication = application
        releases = application.map { [$0.latestRelease] } ?? []
        guard let application else { return }
        let github = self.github
        detailTask = Task {
            do {
                let loaded = try await github.releases(for: application.repository)
                guard !Task.isCancelled, selectedApplication?.id == application.id else { return }
                releases = loaded
            } catch is CancellationError {
                return
            } catch {
                guard selectedApplication?.id == application.id else { return }
                self.error = L10n.format("marketplace.error.releases", error.localizedDescription)
            }
        }
    }

    func changePlatform(_ newValue: MarketplacePlatform) {
        guard platform != newValue else { return }
        platform = newValue
        search(defaultQuery: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func installWithAgent(_ record: AppDownloadRecord) {
        guard let url = record.destinationURL, !isAgentInstalling else { return }
        installTask?.cancel()
        isAgentInstalling = true
        agentInstallResult = nil
        error = nil
        installTask = Task {
            defer { isAgentInstalling = false }
            do {
                let result = try await installerAI.installDownloadedArtifact(
                    at: url,
                    displayName: record.repositoryName
                )
                guard !Task.isCancelled else { return }
                agentInstallResult = result.response
            } catch is CancellationError {
                return
            } catch {
                self.error = L10n.format("marketplace.error.agent_install", error.localizedDescription)
            }
        }
    }

    private var defaultSearchQuery: String {
        switch platform {
        case .all: "topic:desktop-app"
        case .macOS: "topic:macos-app"
        case .windows: "topic:windows-app"
        case .linux: "topic:linux-app"
        case .iOS: "topic:ios-app"
        case .android: "topic:android-app"
        }
    }

#if DEBUG
    private func loadPreviewFixture() {
        guard let repositoryURL = URL(string: "https://github.com/ZIJIU522/GitGatto"),
              let diskImageURL = URL(string: "https://github.com/ZIJIU522/GitGatto/releases/download/v0.16.2/GitGatto-0.16.2-universal.dmg"),
              let archiveURL = URL(string: "https://github.com/ZIJIU522/GitGatto/releases/download/v0.16.2/GitGatto-0.16.2-macos.zip"),
              let releaseURL = URL(string: "https://github.com/ZIJIU522/GitGatto/releases/tag/v0.16.2") else { return }
        let repository = GitHubRepository(
            fullName: "ZIJIU522/GitGatto",
            name: "GitGatto",
            owner: "ZIJIU522",
            description: "原生构建、由 Agent 驱动的 Git 管理工具。",
            webURL: repositoryURL,
            stars: 268,
            forks: 24,
            openIssues: 8,
            language: "Swift",
            updatedAt: Date(),
            isPrivate: false,
            defaultBranch: "main"
        )
        let assets = [
            GitHubReleaseAsset(
                id: 1,
                name: "GitGatto-0.16.2-universal.dmg",
                size: 28_420_096,
                downloadCount: 1_842,
                contentType: "application/x-apple-diskimage",
                downloadURL: diskImageURL,
                createdAt: Date().addingTimeInterval(-86_400)
            ),
            GitHubReleaseAsset(
                id: 2,
                name: "GitGatto-0.16.2-macos.zip",
                size: 27_160_576,
                downloadCount: 936,
                contentType: "application/zip",
                downloadURL: archiveURL,
                createdAt: Date().addingTimeInterval(-86_400)
            )
        ]
        let release = GitHubRelease(
            id: 16_002,
            tagName: "v0.16.2",
            name: "GitGatto 0.16.2",
            body: "## 本次更新\n\n- 项目代码目录支持图片、视频与 SVG 预览。\n- 新增发行版下载与下载管理。\n- 新增应用仓库与平台筛选。\n- Agent 支持自然语言检索与 README 美化。",
            publishedAt: Date().addingTimeInterval(-86_400),
            webURL: releaseURL,
            isPrerelease: false,
            assets: assets
        )
        let application = MarketplaceApplication(
            repository: repository,
            latestRelease: release,
            matchingAssets: assets
        )
        applications = [application]
        selectedApplication = application
        releases = [release]
    }
#endif
}
