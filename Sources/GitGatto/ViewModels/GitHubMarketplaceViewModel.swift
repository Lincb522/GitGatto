import Combine
import Foundation

@MainActor
final class GitHubMarketplaceViewModel: ObservableObject {
    @Published var query = ""
    @Published var platform: MarketplacePlatform = .macOS
    @Published private(set) var applications: [MarketplaceApplication] = []
    @Published var selectedApplication: MarketplaceApplication?
    @Published private(set) var releases: [GitHubRelease] = []
    @Published var selectedReleaseID: Int64?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = false
    @Published private(set) var isUsingAgent = false
    @Published private(set) var isTranslating = false
    @Published private(set) var activeTranslationTarget: CodexTranslationTarget?
    @Published private(set) var translations: [CodexTranslationTarget: MarketplaceTranslationDocument] = [:]
    @Published private(set) var translationError: String?
    @Published private(set) var error: String?
    @Published private(set) var agentInstallResult: String?
    @Published private(set) var isAgentInstalling = false

    private let github: any GitHubServing
    private let searchAI: any CodexServing
    private let installerAI: any CodexServing
    private let translationAI: any CodexServing
    private let translationStore: any MarketplaceTranslationStoring
    private var searchTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var translationCacheTask: Task<Void, Never>?
    private var hasLoaded = false
    private var searchPage = 0
    private var searchInput = ""
    private var resolvedSearchQuery = ""

    init(
        github: any GitHubServing = GitHubService(),
        searchAI: any CodexServing = CodexService(lane: .search),
        installerAI: any CodexServing = CodexService(lane: .installer),
        translationAI: any CodexServing = CodexService(lane: .translation),
        translationStore: any MarketplaceTranslationStoring = MarketplaceTranslationStore()
    ) {
        self.github = github
        self.searchAI = searchAI
        self.installerAI = installerAI
        self.translationAI = translationAI
        self.translationStore = translationStore
    }

    var availableTranslationTargets: [CodexTranslationTarget] {
        CodexTranslationTarget.allCases.filter { translations[$0] != nil }
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
        loadMoreTask?.cancel()
        detailTask?.cancel()
        translationTask?.cancel()
        translationCacheTask?.cancel()
        isLoading = true
        isLoadingMore = false
        canLoadMore = false
        isTranslating = false
        error = nil
        translationError = nil
        translations = [:]
        activeTranslationTarget = nil
        agentInstallResult = nil
        applications = []
        selectedApplication = nil
        releases = []
        selectedReleaseID = nil
        searchPage = 0
        searchInput = ""
        resolvedSearchQuery = ""

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
                let qualifiedQuery = "\(resolved) archived:false stars:>=5"
                let repositories = try await github.searchRepositories(query: qualifiedQuery, page: 1)
                let candidates = GitHubFuzzySearch.sorted(repositories, query: request)
                let found = await Self.marketplaceApplications(
                    from: candidates,
                    platform: platform,
                    github: github
                )
                guard !Task.isCancelled else { return }
                searchInput = request
                resolvedSearchQuery = qualifiedQuery
                searchPage = 1
                canLoadMore = repositories.count == 30
                applications = found
                select(found.first)
            } catch is CancellationError {
                return
            } catch {
                self.error = L10n.format("marketplace.error.search", error.localizedDescription)
            }
        }
    }

    func loadMore() {
        guard canLoadMore,
              !isLoading,
              !isLoadingMore,
              !resolvedSearchQuery.isEmpty else { return }
        let nextPage = searchPage + 1
        let request = searchInput
        let resolved = resolvedSearchQuery
        let platform = platform
        let github = github
        loadMoreTask?.cancel()
        loadMoreTask = Task {
            isLoadingMore = true
            defer {
                isLoadingMore = false
                loadMoreTask = nil
            }
            do {
                let repositories = try await github.searchRepositories(query: resolved, page: nextPage)
                let candidates = GitHubFuzzySearch.sorted(repositories, query: request)
                let found = await Self.marketplaceApplications(
                    from: candidates,
                    platform: platform,
                    github: github
                )
                guard !Task.isCancelled, self.platform == platform else { return }
                var known = Set(applications.map(\.id))
                applications.append(contentsOf: found.filter { known.insert($0.id).inserted })
                searchPage = nextPage
                canLoadMore = repositories.count == 30
            } catch is CancellationError {
                return
            } catch {
                self.error = L10n.format("marketplace.error.search", error.localizedDescription)
            }
        }
    }

    func select(_ application: MarketplaceApplication?) {
        detailTask?.cancel()
        translationTask?.cancel()
        translationCacheTask?.cancel()
        isTranslating = false
        selectedApplication = application
        releases = application.map { [$0.latestRelease] } ?? []
        selectedReleaseID = application?.latestRelease.id
        translations = [:]
        activeTranslationTarget = nil
        translationError = nil
        guard let application else { return }
        restoreTranslations(for: application, release: application.latestRelease)
        let github = self.github
        detailTask = Task {
            do {
                let loaded = try await github.releases(for: application.repository)
                guard !Task.isCancelled, selectedApplication?.id == application.id else { return }
                releases = loaded
                if let release = loaded.first(where: { $0.id == selectedReleaseID }) ?? loaded.first {
                    selectedReleaseID = release.id
                    restoreTranslations(for: application, release: release)
                }
            } catch is CancellationError {
                return
            } catch {
                guard selectedApplication?.id == application.id else { return }
                self.error = L10n.format("marketplace.error.releases", error.localizedDescription)
            }
        }
    }

    func selectRelease(_ releaseID: Int64) {
        guard selectedReleaseID != releaseID,
              let application = selectedApplication,
              let release = releases.first(where: { $0.id == releaseID }) else { return }
        translationTask?.cancel()
        translationCacheTask?.cancel()
        isTranslating = false
        selectedReleaseID = releaseID
        translations = [:]
        activeTranslationTarget = nil
        translationError = nil
        restoreTranslations(for: application, release: release)
    }

    func translateSelected(to target: CodexTranslationTarget) {
        if translations[target] != nil {
            activeTranslationTarget = target
            translationError = nil
            return
        }
        guard !isTranslating,
              let application = selectedApplication,
              let release = selectedRelease else { return }
        let sourceDescription = application.repository.description
        let sourceNotes = release.body
        guard sourceDescription?.isEmpty == false || !sourceNotes.isEmpty else { return }

        translationTask?.cancel()
        isTranslating = true
        translationError = nil
        translationTask = Task {
            defer {
                if selectedApplication?.id == application.id, selectedReleaseID == release.id {
                    isTranslating = false
                    translationTask = nil
                }
            }
            do {
                let translatedDescription: String?
                if let sourceDescription, !sourceDescription.isEmpty {
                    translatedDescription = try await translationAI.translate(sourceDescription, target: target)
                } else {
                    translatedDescription = nil
                }
                let translatedNotes = sourceNotes.isEmpty
                    ? nil
                    : try await translationAI.translateMarkdown(sourceNotes, target: target)
                guard !Task.isCancelled,
                      selectedApplication?.id == application.id,
                      selectedReleaseID == release.id else { return }
                let document = MarketplaceTranslationDocument(
                    repositoryDescription: translatedDescription,
                    releaseNotes: translatedNotes
                )
                translations[target] = document
                activeTranslationTarget = target
                try await translationStore.save(
                    document,
                    repositoryName: application.repository.fullName,
                    releaseID: release.id,
                    sourceDescription: sourceDescription,
                    sourceReleaseNotes: sourceNotes,
                    target: target
                )
            } catch is CancellationError {
                return
            } catch {
                guard selectedApplication?.id == application.id, selectedReleaseID == release.id else { return }
                translationError = L10n.format("marketplace.error.translation", error.localizedDescription)
            }
        }
    }

    func showOriginal() {
        activeTranslationTarget = nil
        translationError = nil
    }

    func showTranslation(_ target: CodexTranslationTarget) {
        guard translations[target] != nil else { return }
        activeTranslationTarget = target
        translationError = nil
    }

    func displayedDescription(for application: MarketplaceApplication) -> String? {
        guard let activeTranslationTarget else { return application.repository.description }
        return translations[activeTranslationTarget]?.repositoryDescription
            ?? application.repository.description
    }

    func displayedReleaseNotes(for release: GitHubRelease) -> String {
        guard let activeTranslationTarget else { return release.body }
        return translations[activeTranslationTarget]?.releaseNotes ?? release.body
    }

    var selectedRelease: GitHubRelease? {
        if let selectedReleaseID,
           let release = releases.first(where: { $0.id == selectedReleaseID }) {
            return release
        }
        return releases.first ?? selectedApplication?.latestRelease
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

    private func restoreTranslations(
        for application: MarketplaceApplication,
        release: GitHubRelease
    ) {
        translationCacheTask?.cancel()
        let store = translationStore
        translationCacheTask = Task {
            var cached: [CodexTranslationTarget: MarketplaceTranslationDocument] = [:]
            for target in CodexTranslationTarget.allCases {
                if let document = try? await store.load(
                    repositoryName: application.repository.fullName,
                    releaseID: release.id,
                    sourceDescription: application.repository.description,
                    sourceReleaseNotes: release.body,
                    target: target
                ) {
                    cached[target] = document
                }
            }
            guard !Task.isCancelled,
                  selectedApplication?.id == application.id,
                  selectedReleaseID == release.id else { return }
            translations = cached
            translationCacheTask = nil
        }
    }

    private static func marketplaceApplications(
        from repositories: [GitHubRepository],
        platform: MarketplacePlatform,
        github: any GitHubServing
    ) async -> [MarketplaceApplication] {
        await withTaskGroup(of: MarketplaceApplication?.self) { group in
            var iterator = repositories.makeIterator()
            for _ in 0..<min(6, repositories.count) {
                guard let repository = iterator.next() else { break }
                group.addTask {
                    await marketplaceApplication(from: repository, platform: platform, github: github)
                }
            }
            var values: [MarketplaceApplication] = []
            while let value = await group.next() {
                if let value { values.append(value) }
                if let repository = iterator.next() {
                    group.addTask {
                        await marketplaceApplication(from: repository, platform: platform, github: github)
                    }
                }
            }
            return values.sorted {
                if $0.repository.stars != $1.repository.stars {
                    return $0.repository.stars > $1.repository.stars
                }
                return $0.repository.fullName < $1.repository.fullName
            }
        }
    }

    private static func marketplaceApplication(
        from repository: GitHubRepository,
        platform: MarketplacePlatform,
        github: any GitHubServing
    ) async -> MarketplaceApplication? {
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
