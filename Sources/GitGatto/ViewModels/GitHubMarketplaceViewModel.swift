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
    @Published private(set) var selectedDetails: MarketplaceApplicationDetails?
    @Published private(set) var selectedLogoURL: URL?
    @Published private(set) var isLoadingDetails = false
    @Published private(set) var isLoadingReleases = false
    @Published private(set) var detailError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = false
    @Published private(set) var searchPage = 0
    @Published private(set) var isUsingAgent = false
    @Published private(set) var isTranslating = false
    @Published private(set) var activeTranslationTarget: CodexTranslationTarget?
    @Published private(set) var translations: [CodexTranslationTarget: MarketplaceTranslationDocument] = [:]
    @Published private(set) var translationError: String?
    @Published private(set) var error: String?
    @Published private(set) var agentInstallResult: String?
    @Published private(set) var isAgentInstalling = false

    private let github: any MarketplaceGitHubServing
    private let searchAI: any CodexServing
    private let installerAI: any CodexServing
    private let translationAI: any CodexServing
    private let translationStore: any MarketplaceTranslationStoring
    private var searchTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var detailsTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var translationCacheTask: Task<Void, Never>?
    private var activeSearchID: UUID?
    private var hasLoaded = false
    private var searchInput = ""
    private var resolvedSearchQueries: [String] = []
    private var loadedReleaseApplicationID: String?

    init(
        github: any MarketplaceGitHubServing = GitHubService(),
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
        detailsTask?.cancel()
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
        selectedDetails = nil
        selectedLogoURL = nil
        isLoadingDetails = false
        isLoadingReleases = false
        detailError = nil
        searchPage = 0
        searchInput = ""
        resolvedSearchQueries = []

        let github = self.github
        let platform = self.platform
        let searchID = UUID()
        activeSearchID = searchID
        searchTask = Task {
            defer {
                if activeSearchID == searchID {
                    isLoading = false
                    isUsingAgent = false
                    searchTask = nil
                    activeSearchID = nil
                }
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
                let queries = shouldUseAgent || defaultQuery
                    ? [resolved]
                    : GitHubSearchQueryResolver.marketplaceQueries(for: request)
                let batch = try await Self.searchRepositories(
                    queries: queries,
                    page: 1,
                    github: github
                )
                let candidates = GitHubFuzzySearch.sorted(batch.repositories, query: request)
                guard !Task.isCancelled, activeSearchID == searchID else { return }
                searchInput = request
                resolvedSearchQueries = queries
                searchPage = 1
                canLoadMore = batch.hasMore
                await loadMarketplaceApplications(
                    from: candidates,
                    platform: platform,
                    replacingCurrentResults: true
                )
            } catch is CancellationError {
                return
            } catch {
                guard activeSearchID == searchID else { return }
                self.error = L10n.format("marketplace.error.search", error.localizedDescription)
            }
        }
    }

    func loadMore() {
        guard canLoadMore,
              !isLoading,
              !isLoadingMore,
              !resolvedSearchQueries.isEmpty else { return }
        let nextPage = searchPage + 1
        let request = searchInput
        let queries = resolvedSearchQueries
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
                let batch = try await Self.searchRepositories(
                    queries: queries,
                    page: nextPage,
                    github: github
                )
                let candidates = GitHubFuzzySearch.sorted(batch.repositories, query: request)
                guard !Task.isCancelled, self.platform == platform else { return }
                searchPage = nextPage
                canLoadMore = batch.hasMore
                await loadMarketplaceApplications(
                    from: candidates,
                    platform: platform,
                    replacingCurrentResults: false
                )
            } catch is CancellationError {
                return
            } catch {
                self.error = L10n.format("marketplace.error.search", error.localizedDescription)
            }
        }
    }

    func select(_ application: MarketplaceApplication?) {
        detailTask?.cancel()
        detailsTask?.cancel()
        translationTask?.cancel()
        translationCacheTask?.cancel()
        isTranslating = false
        selectedApplication = application
        releases = application.map { [$0.latestRelease] } ?? []
        selectedReleaseID = application?.latestRelease.id
        translations = [:]
        activeTranslationTarget = nil
        translationError = nil
        selectedDetails = application.map {
            MarketplaceApplicationDetails.fallback(description: $0.repository.description)
        }
        selectedLogoURL = application?.ownerAvatarURL
        isLoadingDetails = application != nil
        isLoadingReleases = false
        loadedReleaseApplicationID = nil
        detailError = nil
        guard let application else { return }
        restoreTranslations(for: application, release: application.latestRelease)
        let github = self.github
        detailsTask = Task {
            defer {
                if selectedApplication?.id == application.id {
                    isLoadingDetails = false
                    detailsTask = nil
                }
            }
            do {
                let document = try await github.readme(for: application.repository)
                guard !Task.isCancelled, selectedApplication?.id == application.id else { return }
                let details = document.map {
                    MarketplaceApplicationDetailsExtractor.extract(
                        from: $0,
                        repositoryDescription: application.repository.description
                    )
                } ?? MarketplaceApplicationDetails.fallback(
                    description: application.repository.description
                )
                selectedDetails = details
                selectedLogoURL = details.logoURL ?? application.ownerAvatarURL
            } catch is CancellationError {
                return
            } catch {
                guard selectedApplication?.id == application.id else { return }
                selectedDetails = MarketplaceApplicationDetails.fallback(
                    description: application.repository.description
                )
                selectedLogoURL = application.ownerAvatarURL
            }
        }
    }

    func loadReleasesIfNeeded() {
        guard let application = selectedApplication,
              loadedReleaseApplicationID != application.id,
              !isLoadingReleases else { return }
        detailTask?.cancel()
        isLoadingReleases = true
        detailError = nil
        let github = self.github
        detailTask = Task {
            defer {
                if selectedApplication?.id == application.id {
                    isLoadingReleases = false
                    detailTask = nil
                }
            }
            do {
                let loaded = try await github.releases(for: application.repository)
                guard !Task.isCancelled, selectedApplication?.id == application.id else { return }
                releases = loaded
                loadedReleaseApplicationID = application.id
                if let release = loaded.first(where: { $0.id == selectedReleaseID }) ?? loaded.first {
                    selectedReleaseID = release.id
                    restoreTranslations(for: application, release: release)
                }
            } catch is CancellationError {
                return
            } catch {
                guard selectedApplication?.id == application.id else { return }
                detailError = L10n.format("marketplace.error.releases", error.localizedDescription)
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

    private struct RepositorySearchBatch: Sendable {
        let repositories: [GitHubRepository]
        let hasMore: Bool
    }

    private struct RepositoryQueryResult: Sendable {
        let index: Int
        let repositories: [GitHubRepository]?
        let errorDescription: String?
    }

    private static func searchRepositories(
        queries: [String],
        page: Int,
        github: any MarketplaceGitHubServing
    ) async throws -> RepositorySearchBatch {
        let results = await withTaskGroup(of: RepositoryQueryResult.self) { group in
            for (index, query) in queries.enumerated() {
                group.addTask {
                    do {
                        return RepositoryQueryResult(
                            index: index,
                            repositories: try await github.searchRepositories(query: query, page: page),
                            errorDescription: nil
                        )
                    } catch {
                        return RepositoryQueryResult(
                            index: index,
                            repositories: nil,
                            errorDescription: error.localizedDescription
                        )
                    }
                }
            }
            var values: [RepositoryQueryResult] = []
            for await value in group { values.append(value) }
            return values.sorted { $0.index < $1.index }
        }
        let successful = results.compactMap(\.repositories)
        guard !successful.isEmpty else {
            throw GitHubServiceError.commandFailed(
                results.compactMap(\.errorDescription).first
                    ?? L10n.text("marketplace.error.search.empty_response")
            )
        }
        var known = Set<String>()
        let repositories = successful
            .flatMap { $0 }
            .filter { known.insert($0.id).inserted }
        return RepositorySearchBatch(
            repositories: repositories,
            hasMore: successful.contains(where: { $0.count == 30 })
        )
    }

    private func loadMarketplaceApplications(
        from repositories: [GitHubRepository],
        platform: MarketplacePlatform,
        replacingCurrentResults: Bool
    ) async {
        let github = self.github
        let existing = replacingCurrentResults ? [] : applications
        let existingIDs = Set(existing.map(\.id))
        await withTaskGroup(of: (Int, MarketplaceApplication?).self) { group in
            var iterator = repositories.makeIterator()
            var nextIndex = 0
            for _ in 0..<min(6, repositories.count) {
                guard let repository = iterator.next() else { break }
                let index = nextIndex
                nextIndex += 1
                group.addTask {
                    (
                        index,
                        await Self.marketplaceApplication(from: repository, platform: platform, github: github)
                    )
                }
            }
            var pageValues: [Int: MarketplaceApplication] = [:]
            var completedCount = 0
            let publishResults = {
                var known = existingIDs
                let orderedPage = pageValues
                    .sorted { $0.key < $1.key }
                    .map(\.value)
                    .filter { known.insert($0.id).inserted }
                let updated = existing + orderedPage
                guard self.applications != updated else { return }
                self.applications = updated
                if self.selectedApplication == nil, let first = updated.first {
                    self.select(first)
                }
            }
            while let (index, value) = await group.next() {
                guard !Task.isCancelled, self.platform == platform else {
                    group.cancelAll()
                    return
                }
                completedCount += 1
                if let value { pageValues[index] = value }
                if completedCount == 1 || completedCount.isMultiple(of: 4) {
                    publishResults()
                }
                if let repository = iterator.next() {
                    let index = nextIndex
                    nextIndex += 1
                    group.addTask {
                        (
                            index,
                            await Self.marketplaceApplication(from: repository, platform: platform, github: github)
                        )
                    }
                }
            }
            publishResults()
        }
    }

    private static func marketplaceApplication(
        from repository: GitHubRepository,
        platform: MarketplacePlatform,
        github: any MarketplaceGitHubServing
    ) async -> MarketplaceApplication? {
        guard let latest = try? await github.marketplaceRelease(for: repository) else { return nil }
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
        guard let repositoryURL = URL(string: "https://github.com/Lincb522/GitGatto"),
              let appIconURL = URL(string: "https://raw.githubusercontent.com/Lincb522/GitGatto/main/Assets/GitGatto-AppIcon.svg"),
              let diskImageURL = URL(string: "https://github.com/Lincb522/GitGatto/releases/download/v0.18.4/GitGatto-0.18.4.dmg"),
              let releaseURL = URL(string: "https://github.com/Lincb522/GitGatto/releases/tag/v0.18.4") else { return }
        let repository = GitHubRepository(
            fullName: "Lincb522/GitGatto",
            name: "GitGatto",
            owner: "Lincb522",
            description: L10n.text("about.product"),
            webURL: repositoryURL,
            stars: 1,
            forks: 0,
            openIssues: 0,
            language: "Swift",
            updatedAt: Date(),
            isPrivate: false,
            defaultBranch: "main"
        )
        let assets = [
            GitHubReleaseAsset(
                id: 1,
                name: "GitGatto-0.18.4.dmg",
                size: 28_420_096,
                downloadCount: 1_842,
                contentType: "application/x-apple-diskimage",
                downloadURL: diskImageURL,
                createdAt: Date().addingTimeInterval(-86_400)
            )
        ]
        let release = GitHubRelease(
            id: 18_004,
            tagName: "v0.18.4",
            name: "GitGatto 0.18.4",
            body: "## 本次更新\n\n- 全量语言图标资源已更新。\n- 提升小尺寸图标的清晰度。",
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
        selectedLogoURL = appIconURL
        selectedDetails = MarketplaceApplicationDetails(
            summary: repository.description,
            paragraphs: [
                "GitGatto 将本地工作区、提交历史、仓库文件与 GitHub 协作集中在同一个原生客户端中。"
            ],
            features: [
                "查看工作区改动、提交历史、分支与仓库文件",
                "在当前仓库使用 Agent 起草提交、处理错误并执行 Git 操作",
                "搜索 GitHub 项目与应用发行版，直接下载并管理安装包"
            ],
            screenshots: [],
            logoURL: appIconURL
        )
        isLoadingDetails = false
    }
#endif
}
