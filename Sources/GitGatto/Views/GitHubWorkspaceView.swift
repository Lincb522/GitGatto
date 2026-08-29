import AppKit
import SwiftUI

struct GitHubWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    @ObservedObject var downloads: AppDownloadManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue
    @State private var inAppBrowserPage: InAppBrowserPage?
    @State private var isRepositoryHeaderCollapsed = false
    @State private var githubFileQuery = ""

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            searchHeader(palette)
            Rectangle().fill(palette.divider).frame(height: 1)

            if model.githubAvailability.state == .unavailable {
                unavailableState(palette)
            } else {
                GeometryReader { proxy in
                    if AppVisualTheme.resolved(themeRaw) == .standard {
                        HStack(spacing: 0) {
                            listPane(palette)
                                .frame(width: proxy.size.width < 900 ? 270 : 330)
                            Rectangle().fill(palette.divider).frame(width: 1)
                            detailPane(palette)
                        }
                    } else if AppVisualTheme.resolved(themeRaw) == .softGlass {
                        HStack(spacing: 10) {
                            listPane(palette)
                                .frame(width: proxy.size.width < 900 ? 270 : 330)
                                .appGlassPanel(cornerRadius: 14, elevated: false)
                            detailPane(palette)
                                .appGlassPanel(cornerRadius: 14, elevated: false)
                        }
                        .padding(10)
                    } else {
                        HStack(spacing: 8) {
                            listPane(palette)
                                .frame(width: proxy.size.width < 900 ? 280 : 340)
                                .appConsolePanel()
                            detailPane(palette)
                                .appConsolePanel()
                        }
                        .padding(8)
                    }
                }
            }
        }
        .background(AppVisualTheme.resolved(themeRaw) == .softGlass ? Color.clear : palette.background)
        .sheet(item: $model.selectedGitHubPullRequest) { pullRequest in
            GitHubPullRequestReviewView(model: model, pullRequest: pullRequest)
                .frame(minWidth: 900, minHeight: 680)
        }
        .sheet(item: $inAppBrowserPage) { page in
            InAppBrowserSheet(url: page.url, persistent: page.persistent)
                .frame(minWidth: 820, minHeight: 640)
        }
    }

    @ViewBuilder
    private func listPane(_ palette: AppPalette) -> some View {
        if model.githubSearchScope == .developers {
            developerList(palette)
        } else {
            repositoryList(palette)
        }
    }

    @ViewBuilder
    private func detailPane(_ palette: AppPalette) -> some View {
        if model.githubSearchScope == .developers {
            developerDetail(palette)
        } else {
            repositoryDetail(palette)
        }
    }

    private func searchHeader(_ palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            Text(L10n.text("github.title"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.ink)
            GitHubAvailabilityBadge(availability: model.githubAvailability)

            if let account = model.githubAccount {
                Button {
                    inAppBrowserPage = InAppBrowserPage(url: account.webURL, persistent: true)
                } label: {
                    HStack(spacing: 7) {
                        Image(gattoSymbol: "person.crop.circle.fill")
                        Text(account.login)
                            .lineLimit(1)
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.mutedInk)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(palette.raisedSurface)
                    .clipShape(Capsule())
                    .overlay { Capsule().stroke(palette.divider, lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 12)

            Picker("", selection: searchScopeBinding) {
                ForEach(GitHubSearchScope.allCases) { scope in
                    Text(L10n.text("github.search.scope.\(scope.rawValue)"))
                        .tag(scope)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 152)

            HStack(spacing: 7) {
                Image(gattoSymbol: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
                TextField(searchPlaceholder, text: $model.githubQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.ink)
                    .onSubmit { model.searchGitHub() }
                if !model.githubQuery.isEmpty {
                    Button {
                        model.githubQuery = ""
                        model.searchGitHub()
                    } label: {
                        Image(gattoSymbol: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.subtleInk)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 220, idealWidth: 300, maxWidth: 340)
            .frame(height: 32)
            .background(palette.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.divider, lineWidth: 1)
            }

            Button {
                model.searchGitHub()
            } label: {
                Image(gattoSymbol: "arrow.right")
                    .font(.system(size: 11.5, weight: .bold))
                    .frame(width: 16, height: 16)
            }
                .buttonStyle(PrimaryButtonStyle())
                .help(L10n.text("github.action.search"))
                .disabled(model.isLoadingGitHub || model.githubAvailability.state != .available)
                .opacity(model.isLoadingGitHub ? 0.55 : 1)
        }
        .padding(.horizontal, 20)
        .frame(height: 62)
        .background(palette.surface)
    }

    private var searchScopeBinding: Binding<GitHubSearchScope> {
        Binding(
            get: { model.githubSearchScope },
            set: { model.selectGitHubSearchScope($0) }
        )
    }

    private var searchPlaceholder: String {
        L10n.text(
            model.githubSearchScope == .developers
                ? "github.search.developers.placeholder"
                : "github.search.placeholder"
        )
    }

    private func developerList(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(L10n.text("github.developers.results"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.mutedInk)
                if !model.githubDeveloperResults.isEmpty {
                    Text("\(model.githubDeveloperResults.count)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.subtleInk)
                }
                Spacer()
                if model.isResolvingGitHubSearch {
                    Image(gattoSymbol: "sparkles")
                        .foregroundStyle(palette.primary)
                } else if model.isLoadingGitHub {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            Rectangle().fill(palette.divider).frame(height: 1)

            if model.githubDeveloperResults.isEmpty && model.isLoadingGitHub {
                GattoLoadingState(text: L10n.text("loading.generic"))
            } else if model.githubDeveloperResults.isEmpty {
                VStack(spacing: 8) {
                    Image(gattoSymbol: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 20))
                        .foregroundStyle(palette.subtleInk)
                    Text(
                        L10n.text(
                            model.hasGitHubSearched
                                ? "github.search.developers.empty"
                                : "github.search.developers.start"
                        )
                    )
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.mutedInk)
                    .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(model.githubDeveloperResults) { developer in
                            GitHubDeveloperRow(
                                developer: developer,
                                isSelected: model.selectedGitHubDeveloper?.id == developer.id
                            ) {
                                model.selectGitHubDeveloper(developer)
                            }
                        }
                        if model.canLoadMoreGitHubSearch {
                            loadMoreButton(isLoading: model.isLoadingMoreGitHubSearch) {
                                model.loadMoreGitHubSearch()
                            }
                            .padding(.vertical, 7)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(palette.sidebar)
    }

    @ViewBuilder
    private func developerDetail(_ palette: AppPalette) -> some View {
        if model.isLoadingGitHubDeveloper, model.githubDeveloperProfile == nil {
            GattoLoadingState(text: L10n.text("github.developer.loading"))
        } else if let profile = model.githubDeveloperProfile {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 18) {
                        AsyncImage(url: profile.avatarURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(gattoSymbol: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(palette.subtleInk)
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        VStack(alignment: .leading, spacing: 5) {
                            Text(profile.name ?? profile.login)
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(palette.ink)
                            Text("@\(profile.login)")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.mutedInk)
                            if let bio = profile.bio, !bio.isEmpty {
                                Text(bio)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(palette.ink)
                                    .padding(.top, 3)
                            }
                        }
                        Spacer()
                        Button(L10n.text("github.developer.open_profile")) {
                            inAppBrowserPage = InAppBrowserPage(url: profile.webURL, persistent: true)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    HStack(spacing: 20) {
                        GattoLabel(L10n.format("github.developer.followers", profile.followers), systemImage: "person.2")
                        GattoLabel(L10n.format("github.developer.repositories", profile.publicRepositories), systemImage: "shippingbox")
                        if let location = profile.location, !location.isEmpty {
                            GattoLabel(location, systemImage: "location")
                        }
                        if let company = profile.company, !company.isEmpty {
                            GattoLabel(company, systemImage: "building.2")
                        }
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
                    .padding(.top, 18)

                    Rectangle().fill(palette.divider).frame(height: 1).padding(.vertical, 22)

                    HStack {
                        Text(L10n.text("github.developer.public_projects"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.ink)
                        Spacer()
                        Text("\(model.githubDeveloperRepositories.count)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.subtleInk)
                    }

                    LazyVStack(spacing: 4) {
                        ForEach(model.githubDeveloperRepositories) { repository in
                            GitHubRepositoryRow(repository: repository, isSelected: false) {
                                model.openDeveloperRepository(repository)
                            }
                        }
                        if model.canLoadMoreGitHubDeveloperRepositories {
                            loadMoreButton(isLoading: model.isLoadingMoreGitHubDeveloperRepositories) {
                                model.loadMoreGitHubDeveloperRepositories()
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.top, 10)

                    if let error = model.githubDeveloperError {
                        projectError(error, palette: palette)
                            .padding(.top, 12)
                    }
                }
                .padding(24)
            }
            .background(palette.background)
        } else if let error = model.githubDeveloperError {
            projectError(error, palette: palette)
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ProjectEmptyState(systemImage: "person.crop.circle", titleKey: "github.developer.empty")
        }
    }

    private func repositoryList(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(L10n.text(model.githubCollectionTitleKey))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.mutedInk)
                    if !model.displayedGitHubRepositories.isEmpty {
                        Text("\(model.displayedGitHubRepositories.count)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.subtleInk)
                    }
                    Spacer()
                    if model.isResolvingGitHubSearch {
                        Image(gattoSymbol: "sparkles")
                            .foregroundStyle(palette.primary)
                    } else if model.isLoadingGitHub {
                        ProgressView().controlSize(.small)
                    }
                }

                if !model.hasGitHubSearched {
                    HStack(spacing: 4) {
                        collectionButton(
                            titleKey: "github.collection.account",
                            selected: model.githubCollection == .account
                        ) { model.showGitHubAccountRepositories() }
                        collectionButton(
                            titleKey: "github.collection.recommendations",
                            selected: model.githubCollection == .recommendations
                        ) { model.showGitHubRecommendations() }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: model.hasGitHubSearched ? 43 : 72)

            Rectangle().fill(palette.divider).frame(height: 1)

            if model.displayedGitHubRepositories.isEmpty && model.isLoadingGitHub {
                GattoLoadingState(text: L10n.text("loading.generic"))
            } else if model.displayedGitHubRepositories.isEmpty {
                VStack(spacing: 8) {
                    Image(gattoSymbol: "magnifyingglass")
                        .font(.system(size: 18))
                        .foregroundStyle(palette.subtleInk)
                    Text(L10n.text("github.search.empty"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.mutedInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(model.displayedGitHubRepositories) { repository in
                            GitHubRepositoryRow(
                                repository: repository,
                                isSelected: model.selectedGitHubRepository?.id == repository.id
                            ) {
                                model.selectGitHubRepository(repository)
                            }
                        }
                        if model.hasGitHubSearched, model.canLoadMoreGitHubSearch {
                            loadMoreButton(isLoading: model.isLoadingMoreGitHubSearch) {
                                model.loadMoreGitHubSearch()
                            }
                            .padding(.vertical, 7)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(palette.sidebar)
    }

    private func collectionButton(
        titleKey: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let palette = AppPalette(colorScheme)
        return Button(action: action) {
            Text(L10n.text(titleKey))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(selected ? palette.primary : palette.subtleInk)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(selected ? palette.primarySoft : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func loadMoreButton(isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(gattoSymbol: "chevron.down.circle")
                }
                Text(L10n.text(isLoading ? "github.search.loading_more" : "github.search.load_more"))
            }
            .font(.system(size: 11.5, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 34)
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(isLoading)
    }

    @ViewBuilder
    private func repositoryDetail(_ palette: AppPalette) -> some View {
        if let repository = model.selectedGitHubRepository {
            VStack(spacing: 0) {
                repositoryHeader(repository, palette: palette)
                Rectangle().fill(palette.divider).frame(height: 1)
                projectTabBar(palette)
                Rectangle().fill(palette.divider).frame(height: 1)
                projectTabContent(repository, palette: palette)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background)
            .onChange(of: repository.id) { _, _ in
                setRepositoryHeaderCollapsed(false)
            }
            .onChange(of: model.githubError != nil) { _, hasError in
                if hasError {
                    setRepositoryHeaderCollapsed(false)
                }
            }
        } else {
            VStack(spacing: 9) {
                Image(gattoSymbol: "shippingbox")
                    .font(.system(size: 22))
                    .foregroundStyle(palette.subtleInk)
                Text(L10n.text("github.repository.empty"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.mutedInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func repositoryHeader(_ repository: GitHubRepository, palette: AppPalette) -> some View {
        if isRepositoryHeaderCollapsed {
            compactRepositoryHeader(repository, palette: palette)
                .transition(.opacity)
        } else {
            expandedRepositoryHeader(repository, palette: palette)
                .transition(.opacity)
        }
    }

    private func expandedRepositoryHeader(_ repository: GitHubRepository, palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                setRepositoryHeaderCollapsed(true)
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    GitHubLanguageIcon(
                        language: repository.language,
                        isPrivate: repository.isPrivate,
                        size: 44
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(repository.fullName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .textSelection(.enabled)
                        Text(repository.description ?? L10n.text("github.repository.no_description"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.mutedInk)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Image(gattoSymbol: "chevron.compact.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.subtleInk)
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.plain)
            .help(L10n.text("github.repository.header.collapse"))

            HStack(spacing: 14) {
                GattoLabel(GitHubNumberFormatter.string(repository.stars), systemImage: "star")
                GattoLabel(GitHubNumberFormatter.string(repository.forks), systemImage: "arrow.triangle.branch")
                GattoLabel(GitHubNumberFormatter.string(repository.openIssues), systemImage: "record.circle")
                if let language = repository.language {
                    GitHubLanguageLabel(language: language)
                }
                GattoLabel(repository.defaultBranch, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(palette.subtleInk)

            HStack(spacing: 8) {
                Button {
                    model.toggleSelectedGitHubRepositoryStar()
                } label: {
                    GattoLabel(
                        L10n.text(model.isSelectedGitHubRepositoryStarred ? "github.action.unstar" : "github.action.star"),
                        systemImage: model.isSelectedGitHubRepositoryStarred ? "star.fill" : "star"
                    )
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.isUpdatingGitHubStar)

                Button(L10n.text("github.action.clone")) {
                    model.chooseGitHubCloneDestination(fork: false)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(L10n.text("github.action.fork_clone")) {
                    model.chooseGitHubCloneDestination(fork: true)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    openProjectWeb(repository.webURL)
                } label: {
                    GattoLabel(L10n.text("github.action.open_web"), systemImage: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.primary)
            }
            .disabled(model.activeGitHubOperation != nil)

            if let activity = model.githubActivity, model.activeGitHubOperation != nil {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(activity)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.mutedInk)
                    Spacer()
                    Button(L10n.text("github.action.cancel")) { model.cancelGitHubOperation() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.danger)
                }
            }

            if let error = model.githubError {
                projectError(error, palette: palette)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(palette.background)
    }

    private func compactRepositoryHeader(_ repository: GitHubRepository, palette: AppPalette) -> some View {
        HStack(spacing: 8) {
            Button {
                setRepositoryHeaderCollapsed(false)
            } label: {
                HStack(spacing: 10) {
                    GitHubLanguageIcon(
                        language: repository.language,
                        isPrivate: repository.isPrivate,
                        size: 28
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(repository.fullName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)

                        HStack(spacing: 10) {
                            if let language = repository.language {
                                GitHubLanguageLabel(language: language)
                            }
                            GattoLabel(
                                repository.defaultBranch,
                                systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                            )
                        }
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(palette.subtleInk)
                    }

                    Spacer(minLength: 8)
                    Image(gattoSymbol: "chevron.compact.down")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.subtleInk)
                        .frame(width: 24, height: 24)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.text("github.repository.header.expand"))

            Rectangle()
                .fill(palette.divider)
                .frame(width: 1, height: 24)

            if model.activeGitHubOperation != nil {
                ProgressView()
                    .controlSize(.small)
                Text(model.githubActivity ?? L10n.text("github.status.checking"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.mutedInk)
                    .lineLimit(1)
                    .frame(maxWidth: 150)
                ToolbarIconButton(
                    systemName: "xmark",
                    helpKey: "github.action.cancel"
                ) {
                    model.cancelGitHubOperation()
                }
            } else {
                ToolbarIconButton(
                    systemName: model.isSelectedGitHubRepositoryStarred ? "star.fill" : "star",
                    helpKey: model.isSelectedGitHubRepositoryStarred ? "github.action.unstar" : "github.action.star"
                ) {
                    model.toggleSelectedGitHubRepositoryStar()
                }
                ToolbarIconButton(
                    systemName: "tray.and.arrow.down",
                    helpKey: "github.action.clone"
                ) {
                    model.chooseGitHubCloneDestination(fork: false)
                }
                ToolbarIconButton(
                    systemName: "arrow.triangle.branch",
                    helpKey: "github.action.fork_clone"
                ) {
                    model.chooseGitHubCloneDestination(fork: true)
                }
                ToolbarIconButton(
                    systemName: "arrow.up.right",
                    helpKey: "github.action.open_web"
                ) {
                    openProjectWeb(repository.webURL)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(palette.surface)
    }

    private func setRepositoryHeaderCollapsed(_ collapsed: Bool) {
        guard isRepositoryHeaderCollapsed != collapsed else { return }
        if reduceMotion {
            isRepositoryHeaderCollapsed = collapsed
        } else {
            withAnimation(.easeInOut(duration: 0.18)) {
                isRepositoryHeaderCollapsed = collapsed
            }
        }
    }

    private func projectTabBar(_ palette: AppPalette) -> some View {
        HStack(spacing: 4) {
            projectTab(.overview, image: "doc.richtext", palette: palette)
            projectTab(.code, image: "code.source", palette: palette)
            projectTab(.releases, image: "shippingbox", palette: palette, count: model.githubReleases.count)
            projectTab(.pullRequests, image: "git.pull.request", palette: palette, count: model.githubPullRequests.count)
            projectTab(.actions, image: "play.circle", palette: palette, count: model.githubActionRuns.count)
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(palette.surface)
    }

    private func projectTab(
        _ tab: GitHubProjectDetailTab,
        image: String,
        palette: AppPalette,
        count: Int? = nil
    ) -> some View {
        let selected = model.githubProjectDetailTab == tab
        return Button {
            model.selectGitHubProjectDetailTab(tab)
        } label: {
            HStack(spacing: 6) {
                Image(gattoSymbol: image)
                Text(L10n.text("github.project.tab.\(tab.rawValue)"))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(palette.subtleInk)
                }
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(selected ? palette.primary : palette.mutedInk)
            .padding(.horizontal, 10)
            .frame(height: 29)
            .background(selected ? palette.primarySoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func projectTabContent(_ repository: GitHubRepository, palette: AppPalette) -> some View {
        switch model.githubProjectDetailTab {
        case .overview:
            readmeView(palette)
        case .code:
            codeBrowser(repository, palette: palette)
        case .releases:
            RepositoryReleasesView(model: model, downloads: downloads, openURL: openProjectWeb)
        case .pullRequests:
            pullRequestsView(palette)
        case .actions:
            GitHubActionsCenterView(model: model)
        }
    }

    @ViewBuilder
    private func readmeView(_ palette: AppPalette) -> some View {
        if model.isLoadingGitHubReadme {
            GattoLoadingState(text: L10n.text("github.readme.loading"))
        } else if let document = model.displayedGitHubReadme {
            VStack(spacing: 0) {
                readmeToolbar(document, palette: palette)

                if let error = model.githubReadmeError {
                    projectError(error, palette: palette)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }

                if let error = model.githubReadmeTranslationError {
                    projectError(error, palette: palette)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }

                Rectangle().fill(palette.divider).frame(height: 1)

                GitHubReadmeView(
                    document: document,
                    colorScheme: colorScheme,
                    onScrollAwayFromTop: {
                        setRepositoryHeaderCollapsed(true)
                    },
                    onOpenLink: { url in
                        if !model.openGitHubReadmeLink(url) {
                            inAppBrowserPage = InAppBrowserPage(url: url)
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if let error = model.githubReadmeError {
            projectError(error, palette: palette)
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ProjectEmptyState(
                systemImage: "doc.richtext",
                titleKey: "github.readme.empty"
            )
        }
    }

    private func readmeToolbar(_ document: GitHubReadmeDocument, palette: AppPalette) -> some View {
        HStack(spacing: 9) {
            Button {
                model.navigateBackInGitHubReadme()
            } label: {
                Image(gattoSymbol: "chevron.left")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(!model.canNavigateBackInGitHubReadme)
            .opacity(model.canNavigateBackInGitHubReadme ? 1 : 0.35)
            .help(L10n.text("github.readme.back"))

            Text(document.path)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.mutedInk)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 10)

            if model.isTranslatingGitHubReadme {
                ProgressView()
                    .controlSize(.small)
                Text(githubReadmeTranslationStatus)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.mutedInk)
                Button(L10n.text("github.action.cancel")) {
                    model.cancelGitHubReadmeTranslation()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.danger)
            } else {
                if !model.availableGitHubReadmeTranslationTargets.isEmpty {
                    HStack(spacing: 2) {
                        translationVersionButton(
                            title: L10n.text("github.readme.original"),
                            selected: model.githubReadmeTranslationTarget == nil,
                            palette: palette
                        ) {
                            model.showOriginalGitHubReadme()
                        }
                        ForEach(model.availableGitHubReadmeTranslationTargets) { target in
                            translationVersionButton(
                                title: L10n.text("codex.translate.short.\(target.rawValue)"),
                                selected: model.githubReadmeTranslationTarget == target,
                                palette: palette
                            ) {
                                model.showGitHubReadmeTranslation(target)
                            }
                        }
                    }
                    .padding(2)
                    .background(palette.raisedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                Menu {
                    Button(L10n.text("codex.translate.simplifiedChinese")) {
                        model.translateGitHubReadme(to: .simplifiedChinese)
                    }
                    Button(L10n.text("codex.translate.english")) {
                        model.translateGitHubReadme(to: .english)
                    }
                } label: {
                    GattoLabel(L10n.text("codex.action.translate"), systemImage: "ai.translation")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!model.canTranslateGitHubReadme)

                if model.selectedGitHubLocalRepositoryURL != nil {
                    Menu {
                        ForEach(ReadmeAgentStyle.allCases) { style in
                            Button(L10n.text("github.readme.style.\(style.rawValue)")) {
                                model.beautifySelectedReadme(style: style)
                            }
                        }
                    } label: {
                        GattoLabel(L10n.text("github.readme.agent"), systemImage: "sparkles")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(!model.canBeautifySelectedReadme)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(palette.surface)
    }

    private var githubReadmeTranslationStatus: String {
        guard let progress = model.githubReadmeTranslationProgress else {
            return L10n.text("github.readme.translating")
        }
        return L10n.format(
            "github.readme.translating_progress",
            progress.current,
            progress.total
        )
    }

    private func translationVersionButton(
        title: String,
        selected: Bool,
        palette: AppPalette,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(selected ? palette.primary : palette.mutedInk)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(selected ? palette.primarySoft : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func codeBrowser(_ repository: GitHubRepository, palette: AppPalette) -> some View {
        HSplitView {
            VStack(spacing: 0) {
                directoryHeader(repository, palette: palette)
                Rectangle().fill(palette.divider).frame(height: 1)

                if model.isLoadingGitHubContents {
                    GattoLoadingState(text: L10n.text("loading.generic"))
                } else if let error = model.githubContentsError, model.selectedGitHubContent == nil {
                    projectError(error, palette: palette)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else if model.githubContents.isEmpty {
                    ProjectEmptyState(
                        systemImage: "folder",
                        titleKey: "github.code.empty_directory"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredGitHubContents) { item in
                                GitHubContentRow(
                                    item: item,
                                    selected: model.selectedGitHubContent?.id == item.id,
                                    openWeb: { url in openProjectWeb(url) },
                                    download: { item in downloadRepositoryFile(item, repository: repository) }
                                ) {
                                    model.openGitHubContent(item)
                                }
                            }
                        }
                        .padding(7)
                    }
                }
            }
            .frame(minWidth: 210, idealWidth: 260, maxWidth: 390)
            .background(palette.sidebar)

            GitHubCodeFileView(model: model, openInApp: openProjectWeb)
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func directoryHeader(_ repository: GitHubRepository, palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                if !model.githubDirectoryPath.isEmpty {
                    Button {
                        let parent = model.githubDirectoryPath
                            .split(separator: "/")
                            .dropLast()
                            .joined(separator: "/")
                        model.openGitHubDirectory(parent)
                    } label: {
                        Image(gattoSymbol: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.mutedInk)
                }
                Text(repository.defaultBranch)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                let parts = model.githubDirectoryPath.split(separator: "/").map(String.init)
                HStack(spacing: 4) {
                    Button(repository.name) { model.openGitHubDirectory("") }
                        .buttonStyle(.plain)
                    ForEach(parts.indices, id: \.self) { index in
                        Text("/").foregroundStyle(palette.subtleInk)
                        let path = parts.prefix(index + 1).joined(separator: "/")
                        Button(parts[index]) { model.openGitHubDirectory(path) }
                            .buttonStyle(.plain)
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.mutedInk)
            }

            HStack(spacing: 7) {
                Image(gattoSymbol: "magnifyingglass")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.subtleInk)
                TextField(L10n.text("github.code.filter"), text: $githubFileQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5))
                if !githubFileQuery.isEmpty {
                    Button { githubFileQuery = "" } label: {
                        Image(gattoSymbol: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 27)
            .background(palette.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(height: 86)
    }

    private var filteredGitHubContents: [GitHubContentItem] {
        let query = githubFileQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.githubContents }
        return model.githubContents.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.path.localizedCaseInsensitiveContains(query)
        }
    }

    private func downloadRepositoryFile(_ item: GitHubContentItem, repository: GitHubRepository) {
        guard let url = item.downloadURL else { return }
        downloads.start(
            url: url,
            fileName: item.name,
            expectedBytes: Int64(item.size),
            repositoryName: repository.fullName
        )
    }

    private func pullRequestsView(_ palette: AppPalette) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if model.isLoadingPullRequests {
                    GattoLoadingState(text: L10n.text("github.pull_requests.loading"))
                        .frame(minHeight: 240)
                } else if let error = model.githubPullRequestsError {
                    projectError(error, palette: palette)
                } else if model.githubPullRequests.isEmpty {
                    Text(L10n.text("github.pull_requests.empty"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.mutedInk)
                        .padding(.vertical, 22)
                } else {
                    ForEach(model.githubPullRequests) { pullRequest in
                        GitHubPullRequestRow(pullRequest: pullRequest) {
                            model.openPullRequestReview(pullRequest)
                        }
                    }
                }
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func projectError(_ message: String, palette: AppPalette) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(gattoSymbol: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.danger)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.ink)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(palette.dangerSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func openProjectWeb(_ url: URL) {
        inAppBrowserPage = InAppBrowserPage(url: url, persistent: true)
    }

    private func unavailableState(_ palette: AppPalette) -> some View {
        VStack(spacing: 14) {
            Image(gattoSymbol: "terminal")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            Text(L10n.text("github.unavailable.title"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text(L10n.text("github.unavailable.body"))
                .font(.system(size: 12.5))
                .foregroundStyle(palette.mutedInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 450)
            HStack(spacing: 8) {
                Button(L10n.text("github.action.login")) { model.beginGitHubLogin() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isLaunchingGitHubLogin)
                Button(L10n.text("github.action.retry")) { model.retryGitHubProbe() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            if let activity = model.githubActivity {
                Text(activity)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.mutedInk)
            }
            if let error = model.githubError {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.danger)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProjectEmptyState: View {
    let systemImage: String
    let titleKey: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 9) {
            Image(gattoSymbol: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            Text(L10n.text(titleKey))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(palette.mutedInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GitHubContentRow: View {
    let item: GitHubContentItem
    let selected: Bool
    let openWeb: (URL) -> Void
    let download: (GitHubContentItem) -> Void
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 8) {
                Image(gattoSymbol: iconName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(item.kind == .directory ? palette.accent : palette.subtleInk)
                    .frame(width: 16)
                Text(item.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if item.kind == .file, item.size > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                        .font(.system(size: 9.5))
                        .foregroundStyle(palette.subtleInk)
                }
                if item.kind == .directory {
                    Image(gattoSymbol: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(palette.subtleInk)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? palette.primarySoft : (isHovering ? palette.raisedSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(L10n.text("action.copy_path")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.path, forType: .string)
            }
            if let url = item.webURL {
                Button(L10n.text("github.code.open_github")) { openWeb(url) }
            }
            if item.downloadURL != nil, item.kind != .directory {
                Button(L10n.text("github.releases.download")) { download(item) }
            }
        }
    }

    private var iconName: String {
        switch item.kind {
        case .directory: return "folder.fill"
        case .file:
            if let mediaKind = RepositoryMediaKind(fileName: item.name) {
                return mediaKind == .video ? "play.circle" : "photo"
            }
            switch (item.name as NSString).pathExtension.lowercased() {
            case "zip", "gz", "xz", "dmg", "pkg": return "archivebox"
            default: return "doc.text"
            }
        case .symlink: return "link"
        case .submodule: return "shippingbox"
        }
    }
}

private struct GitHubCodeFileView: View {
    @ObservedObject var model: WorkspaceViewModel
    let openInApp: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            if let item = model.selectedGitHubContent {
                fileHeader(item, palette: palette)
                Rectangle().fill(palette.divider).frame(height: 1)
            }

            if model.isLoadingGitHubFile {
                GattoLoadingState(text: L10n.text("github.code.loading"))
            } else if let error = model.githubContentsError, model.selectedGitHubContent != nil {
                errorView(error, palette: palette)
            } else if let document = model.githubFileDocument {
                fileBody(document, palette: palette)
            } else {
                ProjectEmptyState(
                    systemImage: "doc.text",
                    titleKey: "github.code.select_file"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
    }

    private func fileHeader(_ item: GitHubContentItem, palette: AppPalette) -> some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous)
                    .fill(palette.primarySoft)
                Image(gattoSymbol: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.primary)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12.5, weight: .semibold, design: theme == .console ? .monospaced : .default))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text(item.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if item.size > 0 {
                        Circle().fill(palette.subtleInk).frame(width: 2.5, height: 2.5)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                    }
                }
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(palette.subtleInk)
            }
            Spacer(minLength: 8)
            if let url = item.webURL {
                Button {
                    openInApp(url)
                } label: {
                    GattoLabel(L10n.text("github.code.open_github"), systemImage: "arrow.up.right")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Button { model.closeGitHubFile() } label: {
                Image(gattoSymbol: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(palette.subtleInk)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background(theme == .softGlass ? palette.surface.opacity(0.15) : palette.surface)
    }

    @ViewBuilder
    private func fileBody(_ document: GitHubFileDocument, palette: AppPalette) -> some View {
        switch GitHubFilePresentationKind(fileName: document.name) {
        case .media:
            if let url = document.localPreviewURL ?? document.downloadURL {
                RepositoryMediaPreview(
                    url: url,
                    fileName: document.name,
                    svgSource: document.text
                )
            } else {
                binaryFallback(document, palette: palette)
            }
        case .text:
            if let text = document.text {
                CodeDocumentView(content: text, fileName: document.name)
            } else {
                binaryFallback(document, palette: palette)
            }
        case .binary:
            binaryFallback(document, palette: palette)
        }
    }

    private func binaryFallback(_ document: GitHubFileDocument, palette: AppPalette) -> some View {
        VStack(spacing: 12) {
            ProjectEmptyState(
                systemImage: "doc.badge.ellipsis",
                titleKey: "github.code.binary"
            )
            if let url = document.webURL {
                Button(L10n.text("github.code.open_github")) {
                    openInApp(url)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.primary)
            }
        }
    }

    private enum GitHubFilePresentationKind {
        case media
        case text
        case binary

        init(fileName: String) {
            if RepositoryMediaKind(fileName: fileName) != nil {
                self = .media
                return
            }
            switch (fileName as NSString).pathExtension.lowercased() {
            case "dmg", "pkg", "zip", "gz", "xz", "7z", "pdf", "woff", "woff2", "ttf": self = .binary
            default: self = .text
            }
        }
    }

    private func errorView(_ error: String, palette: AppPalette) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(gattoSymbol: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.danger)
            Text(error)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.ink)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(palette.dangerSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct GitHubAvailabilityBadge: View {
    let availability: GitHubAvailability
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 5) {
            Circle()
                .fill(availability.state == .available ? palette.success : palette.subtleInk)
                .frame(width: 6, height: 6)
            Text(label)
                .lineLimit(1)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(palette.mutedInk)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(palette.raisedSurface)
        .clipShape(Capsule())
        .overlay { Capsule().stroke(palette.divider, lineWidth: 1) }
    }

    private var label: String {
        switch availability.state {
        case .checking: L10n.text("github.status.checking")
        case .available: L10n.text("github.status.available")
        case .unavailable: L10n.text("github.status.unavailable")
        }
    }
}

private struct GitHubRepositoryRow: View {
    let repository: GitHubRepository
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                GitHubLanguageIcon(
                    language: repository.language,
                    isPrivate: repository.isPrivate,
                    size: 32
                )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(repository.fullName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Spacer()
                        GattoLabel(GitHubNumberFormatter.string(repository.stars), systemImage: "star")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(palette.subtleInk)
                    }
                    if let description = repository.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.mutedInk)
                            .lineLimit(2)
                    }
                    if let language = repository.language {
                        GitHubLanguageLabel(language: language, fontSize: 9.5)
                            .foregroundStyle(palette.subtleInk)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? palette.primarySoft : (isHovering ? palette.raisedSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct GitHubDeveloperRow: View {
    let developer: GitHubDeveloperSummary
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 10) {
                AsyncImage(url: developer.avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(gattoSymbol: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(palette.subtleInk)
                }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(developer.login)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(developer.accountType)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.subtleInk)
                }

                Spacer()
                Image(gattoSymbol: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.subtleInk)
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(isSelected ? palette.primarySoft : (isHovering ? palette.raisedSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct GitHubPullRequestRow: View {
    let pullRequest: GitHubPullRequest
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(gattoSymbol: "git.pull.request")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.success)
                    .frame(width: 24, height: 24)
                    .background(palette.successSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("#\(pullRequest.number)")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.subtleInk)
                        Text(pullRequest.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        if pullRequest.isDraft {
                            Text(L10n.text("github.pull_request.draft"))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(palette.warning)
                        }
                    }
                    Text("\(pullRequest.author) · \(pullRequest.headBranch) → \(pullRequest.baseBranch)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.subtleInk)
                        .lineLimit(1)
                }
                Spacer()
                Image(gattoSymbol: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.subtleInk)
            }
            .padding(10)
            .background(isHovering ? palette.raisedSurface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

enum GitHubNumberFormatter {
    static func string(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}
