import Combine
import Foundation

@MainActor
final class GitHubMarketplaceViewModel: ObservableObject {
    @Published var query = ""
    @Published var platform: MarketplacePlatform = .macOS
    @Published var collection: MarketplaceCollection = .discover
    @Published var feed: MarketplaceFeed = .hotReleases
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
    @Published private(set) var translationCompletionID: UUID?
    @Published private(set) var activeTranslationTarget: CodexTranslationTarget?
    @Published private(set) var translations: [CodexTranslationTarget: MarketplaceTranslationDocument] = [:]
    @Published private(set) var translationError: String?
    @Published private(set) var error: String?
    @Published private(set) var hasCompletedInitialLoad = false
    @Published private(set) var isShowingSearchResults = false
    @Published private(set) var isStarred = false
    @Published private(set) var isUpdatingStar = false
    @Published private(set) var starError: String?

    private let github: any MarketplaceGitHubServing
    private let searchAI: any CodexServing
    private let translationAI: any CodexServing
    private let translationStore: any MarketplaceTranslationStoring
    private let historyStore: any MarketplaceHistoryStoring
    private let automaticTranslationTarget: CodexTranslationTarget?
    private let automaticallyTranslates: Bool
    private var searchTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var detailsTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var translationCacheTask: Task<Void, Never>?
    private var starTask: Task<Void, Never>?
    private var activeSearchID: UUID?
    private var hasLoaded = false
    private var searchInput = ""
    private var resolvedSearchQueries: [String] = []
    private var activeSearchSort: GitHubRepositorySearchSort = .stars
    private var installedRepositoryNames: [String] = []
    private var loadedReleaseApplicationID: String?

    init(
        github: any MarketplaceGitHubServing = GitHubService(),
        searchAI: any CodexServing = CodexService(lane: .search),
        translationAI: any CodexServing = CodexService(lane: .translation),
        translationStore: any MarketplaceTranslationStoring = MarketplaceTranslationStore(),
        historyStore: any MarketplaceHistoryStoring = MarketplaceHistoryStore(),
        automaticTranslationTarget: CodexTranslationTarget? = nil,
        automaticallyTranslates: Bool = true
    ) {
        self.github = github
        self.searchAI = searchAI
        self.translationAI = translationAI
        self.translationStore = translationStore
        self.historyStore = historyStore
        self.automaticTranslationTarget = automaticTranslationTarget
        self.automaticallyTranslates = automaticallyTranslates
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
            hasCompletedInitialLoad = true
            return
        }
#endif
        search(defaultQuery: true)
    }

    func search(defaultQuery: Bool = false) {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if defaultQuery, input.isEmpty, collection != .discover {
            reloadCurrentCollection()
            return
        }
        let request = defaultQuery && input.isEmpty ? defaultSearchQuery : input
        guard !request.isEmpty else { return }
        prepareForNewResults()
        isShowingSearchResults = !defaultQuery

        let github = self.github
        let platform = self.platform
        let sort = defaultQuery ? feed.searchSort : .stars
        let searchID = UUID()
        activeSearchID = searchID
        searchTask = Task {
            defer {
                if defaultQuery {
                    hasCompletedInitialLoad = true
                }
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
                    sort: sort,
                    github: github
                )
                let candidates = defaultQuery
                    ? batch.repositories
                    : GitHubFuzzySearch.sorted(batch.repositories, query: request)
                guard !Task.isCancelled, activeSearchID == searchID else { return }
                searchInput = request
                resolvedSearchQueries = queries
                activeSearchSort = sort
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
        if collection == .favorites, !isShowingSearchResults {
            loadMoreFavorites()
            return
        }
        guard canLoadMore,
              !isLoading,
              !isLoadingMore,
              !resolvedSearchQueries.isEmpty else { return }
        let nextPage = searchPage + 1
        let request = searchInput
        let queries = resolvedSearchQueries
        let sort = activeSearchSort
        let platform = platform
        let github = github
        loadMoreTask?.cancel()
        isLoadingMore = true
        loadMoreTask = Task {
            guard !Task.isCancelled else { return }
            defer {
                if !Task.isCancelled {
                    isLoadingMore = false
                    loadMoreTask = nil
                }
            }
            do {
                let batch = try await Self.searchRepositories(
                    queries: queries,
                    page: nextPage,
                    sort: sort,
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
                guard !Task.isCancelled else { return }
                self.error = L10n.format("marketplace.error.search", error.localizedDescription)
            }
        }
    }

    func select(_ application: MarketplaceApplication?) {
        detailTask?.cancel()
        detailsTask?.cancel()
        translationTask?.cancel()
        translationCacheTask?.cancel()
        starTask?.cancel()
        isTranslating = false
        isStarred = false
        isUpdatingStar = false
        starError = nil
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
        let github = self.github
        let historyStore = self.historyStore
        Task {
            await historyStore.record(application.repository.fullName)
        }
        isUpdatingStar = true
        starTask = Task {
            defer {
                if !Task.isCancelled, selectedApplication?.id == application.id {
                    isUpdatingStar = false
                    starTask = nil
                }
            }
            do {
                let starred = try await github.isStarred(application.repository)
                guard !Task.isCancelled, selectedApplication?.id == application.id else { return }
                isStarred = starred
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, selectedApplication?.id == application.id else { return }
                starError = L10n.format("marketplace.error.favorite", error.localizedDescription)
            }
        }
        detailsTask = Task {
            defer {
                if !Task.isCancelled, selectedApplication?.id == application.id {
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
                restoreTranslations(
                    for: application,
                    release: selectedRelease ?? application.latestRelease,
                    details: details
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, selectedApplication?.id == application.id else { return }
                let details = MarketplaceApplicationDetails.fallback(
                    description: application.repository.description
                )
                selectedDetails = details
                selectedLogoURL = application.ownerAvatarURL
                restoreTranslations(
                    for: application,
                    release: selectedRelease ?? application.latestRelease,
                    details: details
                )
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
                if !Task.isCancelled, selectedApplication?.id == application.id {
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
                    restoreTranslations(
                        for: application,
                        release: release,
                        details: selectedDetails ?? .fallback(description: application.repository.description)
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, selectedApplication?.id == application.id else { return }
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
        restoreTranslations(
            for: application,
            release: release,
            details: selectedDetails ?? .fallback(description: application.repository.description)
        )
    }

    func translateSelected(to target: CodexTranslationTarget) {
        if translations[target] != nil {
            activeTranslationTarget = target
            translationError = nil
            return
        }
        guard !isTranslating,
              !isLoadingDetails,
              let application = selectedApplication,
              let release = selectedRelease,
              let details = selectedDetails else { return }
        let sourceDescription = application.repository.description
        let sourceNotes = release.body
        let sourceDetailHTML = MarketplaceApplicationDetailsExtractor.translationHTML(
            repositoryDescription: sourceDescription,
            details: details
        )
        guard sourceDetailHTML != nil || !sourceNotes.isEmpty else { return }

        translationTask?.cancel()
        translationCacheTask?.cancel()
        translationCacheTask = nil
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
                let translatedDetails: MarketplaceApplicationTranslatedText?
                if let sourceDetailHTML {
                    let translatedHTML = try await translationAI.translateHTML(sourceDetailHTML, target: target)
                    guard let parsed = MarketplaceApplicationDetailsExtractor.translatedText(from: translatedHTML),
                          parsed.paragraphs.count == details.paragraphs.count,
                          parsed.features.count == details.features.count,
                          sourceDescription?.isEmpty != false || parsed.repositoryDescription?.isEmpty == false else {
                        throw CodexServiceError.invalidTranslation
                    }
                    translatedDetails = parsed
                } else {
                    translatedDetails = nil
                }
                let translatedNotes = sourceNotes.isEmpty
                    ? nil
                    : try await translationAI.translateMarkdown(sourceNotes, target: target)
                guard !Task.isCancelled,
                      selectedApplication?.id == application.id,
                      selectedReleaseID == release.id else { return }
                let document = MarketplaceTranslationDocument(
                    repositoryDescription: translatedDetails?.repositoryDescription,
                    releaseNotes: translatedNotes,
                    detailParagraphs: translatedDetails?.paragraphs,
                    detailFeatures: translatedDetails?.features
                )
                translations[target] = document
                activeTranslationTarget = target
                translationCompletionID = UUID()
                try await translationStore.save(
                    document,
                    repositoryName: application.repository.fullName,
                    releaseID: release.id,
                    sourceDescription: sourceDescription,
                    sourceReleaseNotes: sourceNotes,
                    sourceDetails: details.translationSourceText,
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

    func displayedDetails(for application: MarketplaceApplication) -> MarketplaceApplicationDetails {
        let details = selectedDetails ?? .fallback(description: application.repository.description)
        guard let activeTranslationTarget,
              let document = translations[activeTranslationTarget] else { return details }
        return MarketplaceApplicationDetails(
            summary: document.repositoryDescription ?? details.summary,
            paragraphs: document.detailParagraphs ?? details.paragraphs,
            features: document.detailFeatures ?? details.features,
            screenshots: details.screenshots,
            logoURL: details.logoURL
        )
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

    func toggleStar() {
        guard let application = selectedApplication, !isUpdatingStar else { return }
        let target = !isStarred
        let github = self.github
        starTask?.cancel()
        isUpdatingStar = true
        starError = nil
        starTask = Task {
            defer {
                if !Task.isCancelled, selectedApplication?.id == application.id {
                    isUpdatingStar = false
                    starTask = nil
                }
            }
            do {
                try await github.setStarred(target, repository: application.repository)
                guard !Task.isCancelled, selectedApplication?.id == application.id else { return }
                isStarred = target
                if !target, collection == .favorites, !isShowingSearchResults {
                    applications.removeAll { $0.id == application.id }
                    select(applications.first)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, selectedApplication?.id == application.id else { return }
                starError = L10n.format("marketplace.error.favorite", error.localizedDescription)
            }
        }
    }

    func changeFeed(_ newValue: MarketplaceFeed) {
        guard feed != newValue || collection != .discover || isShowingSearchResults else { return }
        feed = newValue
        collection = .discover
        query = ""
        search(defaultQuery: true)
    }

    func changeCollection(
        _ newValue: MarketplaceCollection,
        installedRepositoryNames: [String] = []
    ) {
        let normalizedInstalled = Self.uniqueRepositoryNames(installedRepositoryNames)
        guard collection != newValue
                || (newValue == .installed && normalizedInstalled != self.installedRepositoryNames)
                || isShowingSearchResults else { return }
        collection = newValue
        self.installedRepositoryNames = normalizedInstalled
        query = ""
        isShowingSearchResults = false
        reloadCurrentCollection()
    }

    func changePlatform(_ newValue: MarketplacePlatform) {
        guard platform != newValue else { return }
        platform = newValue
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reloadCurrentCollection()
        } else {
            search()
        }
    }

    func refreshAutomaticTranslation(to target: CodexTranslationTarget) {
        guard let application = selectedApplication,
              let release = selectedRelease,
              let details = selectedDetails else { return }
        restoreTranslations(
            for: application,
            release: release,
            details: details,
            preferredTarget: target
        )
    }

    private func reloadCurrentCollection() {
        switch collection {
        case .discover:
            search(defaultQuery: true)
        case .favorites:
            loadFavorites()
        case .installed:
            loadNamedRepositories(installedRepositoryNames)
        case .recent:
            loadRecentRepositories()
        }
    }

    private func loadFavorites() {
        prepareForNewResults()
        isShowingSearchResults = false
        let github = self.github
        let platform = self.platform
        let searchID = UUID()
        activeSearchID = searchID
        searchTask = Task {
            defer {
                hasCompletedInitialLoad = true
                if activeSearchID == searchID {
                    isLoading = false
                    searchTask = nil
                    activeSearchID = nil
                }
            }
            do {
                let repositories = try await github.starredRepositories(page: 1)
                guard !Task.isCancelled, activeSearchID == searchID else { return }
                searchPage = 1
                canLoadMore = repositories.count == 30
                await loadMarketplaceApplications(
                    from: repositories,
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

    private func loadMoreFavorites() {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        let nextPage = searchPage + 1
        let github = self.github
        let platform = self.platform
        loadMoreTask?.cancel()
        isLoadingMore = true
        loadMoreTask = Task {
            guard !Task.isCancelled else { return }
            defer {
                if !Task.isCancelled {
                    isLoadingMore = false
                    loadMoreTask = nil
                }
            }
            do {
                let repositories = try await github.starredRepositories(page: nextPage)
                guard !Task.isCancelled,
                      collection == .favorites,
                      !isShowingSearchResults,
                      self.platform == platform else { return }
                searchPage = nextPage
                canLoadMore = repositories.count == 30
                await loadMarketplaceApplications(
                    from: repositories,
                    platform: platform,
                    replacingCurrentResults: false
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.error = L10n.format("marketplace.error.search", error.localizedDescription)
            }
        }
    }

    private func loadRecentRepositories() {
        prepareForNewResults()
        isShowingSearchResults = false
        let historyStore = self.historyStore
        let searchID = UUID()
        activeSearchID = searchID
        searchTask = Task {
            let names = await historyStore.repositoryNames()
            await loadNamedRepositories(names, searchID: searchID)
        }
    }

    private func loadNamedRepositories(_ names: [String]) {
        prepareForNewResults()
        isShowingSearchResults = false
        let searchID = UUID()
        activeSearchID = searchID
        searchTask = Task {
            await loadNamedRepositories(names, searchID: searchID)
        }
    }

    private func loadNamedRepositories(_ names: [String], searchID: UUID) async {
        defer {
            hasCompletedInitialLoad = true
            if activeSearchID == searchID {
                isLoading = false
                searchTask = nil
                activeSearchID = nil
            }
        }
        let names = Self.uniqueRepositoryNames(names)
        guard !names.isEmpty, activeSearchID == searchID else { return }
        let github = self.github
        let platform = self.platform
        let results = await withTaskGroup(of: (Int, GitHubRepository?).self) { group in
            for (index, name) in names.enumerated() {
                group.addTask {
                    (index, try? await github.repository(named: name))
                }
            }
            var repositories: [(Int, GitHubRepository)] = []
            for await (index, repository) in group {
                if let repository { repositories.append((index, repository)) }
            }
            return repositories.sorted { $0.0 < $1.0 }.map(\.1)
        }
        guard !Task.isCancelled, activeSearchID == searchID else { return }
        canLoadMore = false
        await loadMarketplaceApplications(
            from: results,
            platform: platform,
            replacingCurrentResults: true
        )
    }

    private func prepareForNewResults() {
        searchTask?.cancel()
        loadMoreTask?.cancel()
        detailTask?.cancel()
        detailsTask?.cancel()
        translationTask?.cancel()
        translationCacheTask?.cancel()
        starTask?.cancel()
        activeSearchID = nil
        isLoading = true
        isLoadingMore = false
        canLoadMore = false
        isUsingAgent = false
        isTranslating = false
        isUpdatingStar = false
        isStarred = false
        error = nil
        detailError = nil
        translationError = nil
        starError = nil
        translations = [:]
        activeTranslationTarget = nil
        applications = []
        selectedApplication = nil
        releases = []
        selectedReleaseID = nil
        selectedDetails = nil
        selectedLogoURL = nil
        isLoadingDetails = false
        isLoadingReleases = false
        searchPage = 0
        searchInput = ""
        resolvedSearchQueries = []
        activeSearchSort = .stars
        loadedReleaseApplicationID = nil
    }

    private static func uniqueRepositoryNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    private func restoreTranslations(
        for application: MarketplaceApplication,
        release: GitHubRelease,
        details: MarketplaceApplicationDetails,
        preferredTarget targetOverride: CodexTranslationTarget? = nil
    ) {
        translationCacheTask?.cancel()
        let preferredTarget = targetOverride
            ?? automaticTranslationTarget
            ?? AppPreferencesStore.load().language.translationTarget
        let automaticTarget = automaticallyTranslates ? AutomaticTranslationPolicy.target(
            for: ([application.repository.description, release.body]
                .compactMap { $0 } + details.paragraphs + details.features)
                .joined(separator: "\n"),
            preferredTarget: preferredTarget
        ) : nil
        let store = translationStore
        translationCacheTask = Task {
            var cached: [CodexTranslationTarget: MarketplaceTranslationDocument] = [:]
            for target in CodexTranslationTarget.allCases {
                if let document = try? await store.load(
                    repositoryName: application.repository.fullName,
                    releaseID: release.id,
                    sourceDescription: application.repository.description,
                    sourceReleaseNotes: release.body,
                    sourceDetails: details.translationSourceText,
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
            guard let automaticTarget else { return }
            if cached[automaticTarget] != nil {
                activeTranslationTarget = automaticTarget
            } else {
                translateSelected(to: automaticTarget)
            }
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
        sort: GitHubRepositorySearchSort,
        github: any MarketplaceGitHubServing
    ) async throws -> RepositorySearchBatch {
        let results = await withTaskGroup(of: RepositoryQueryResult.self) { group in
            for (index, query) in queries.enumerated() {
                group.addTask {
                    do {
                        return RepositoryQueryResult(
                            index: index,
                            repositories: try await github.searchRepositories(
                                query: query,
                                page: page,
                                sort: sort
                            ),
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
                guard !Task.isCancelled, self.platform == platform else { return }
                var known = existingIDs
                let orderedPage = pageValues
                    .sorted { $0.key < $1.key }
                    .map(\.value)
                    .filter { known.insert($0.id).inserted }
                let updated = existing + orderedPage
                guard self.applications != updated else { return }
                self.applications = updated
                if replacingCurrentResults, !updated.isEmpty {
                    self.hasCompletedInitialLoad = true
                }
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
        let platformQuery = switch platform {
        case .all: "topic:desktop-app"
        case .macOS: "topic:macos-app"
        case .windows: "topic:windows-app"
        case .linux: "topic:linux-app"
        case .iOS: "topic:ios-app"
        case .android: "topic:android-app"
        }
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        switch feed {
        case .hotReleases:
            let date = calendar.date(byAdding: .day, value: -45, to: Date()) ?? Date()
            return "\(platformQuery) pushed:>=\(formatter.string(from: date))"
        case .trending:
            let date = calendar.date(byAdding: .day, value: -365, to: Date()) ?? Date()
            return "\(platformQuery) created:>=\(formatter.string(from: date)) stars:>=25"
        case .popular:
            return "\(platformQuery) stars:>=100"
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
        isStarred = true
        let previewScreenshots: [URL]
        if ProcessInfo.processInfo.environment["GITGATTO_MARKETPLACE_CAROUSEL_PREVIEW"] == "1" {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            previewScreenshots = [
                root.appendingPathComponent("docs/media/workspace.png"),
                root.appendingPathComponent("dist/qa/submit-motion-commit.png"),
                root.appendingPathComponent("dist/qa/star-motion-selected.png")
            ].filter { FileManager.default.fileExists(atPath: $0.path) }
        } else {
            previewScreenshots = []
        }
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
            screenshots: previewScreenshots,
            logoURL: appIconURL
        )
        isLoadingDetails = false
    }
#endif
}

private extension MarketplaceFeed {
    var searchSort: GitHubRepositorySearchSort {
        switch self {
        case .hotReleases: .updated
        case .trending, .popular: .stars
        }
    }
}

protocol MarketplaceHistoryStoring: Sendable {
    func repositoryNames() async -> [String]
    func record(_ repositoryName: String) async
}

actor MarketplaceHistoryStore: MarketplaceHistoryStoring {
    private let fileURL: URL
    private let maximumCount: Int

    init(directoryURL: URL? = nil, maximumCount: Int = 40) {
        let directory = directoryURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("GitGatto/Marketplace", isDirectory: true)
        fileURL = directory.appendingPathComponent("recent-repositories.json")
        self.maximumCount = maximumCount
    }

    func repositoryNames() async -> [String] {
        load()
    }

    func record(_ repositoryName: String) async {
        let normalized = repositoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        var names = load().filter {
            $0.caseInsensitiveCompare(normalized) != .orderedSame
        }
        names.insert(normalized, at: 0)
        if names.count > maximumCount {
            names.removeSubrange(maximumCount...)
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(names)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }

    private func load() -> [String] {
        guard let data = try? Data(contentsOf: fileURL),
              let names = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Array(names.prefix(maximumCount))
    }
}
