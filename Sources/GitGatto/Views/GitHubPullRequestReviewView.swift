import SwiftUI

struct GitHubPullRequestReviewView: View {
    @ObservedObject var model: WorkspaceViewModel
    let pullRequest: GitHubPullRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue
    @State private var inAppBrowserPage: InAppBrowserPage?

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            header(palette)
            Rectangle().fill(palette.divider).frame(height: 1)
            tabBar(palette)
            Rectangle().fill(palette.divider).frame(height: 1)

            if model.isLoadingPullRequestReview, model.pullRequestReviewCenter == nil {
                reviewLoading()
            } else if let center = model.pullRequestReviewCenter {
                tabContent(center, palette: palette)
            } else if let error = model.pullRequestReviewError {
                errorView(error, palette: palette)
            }
        }
        .background(theme == .softGlass ? Color.clear : palette.background)
        .sheet(item: $inAppBrowserPage) { page in
            InAppBrowserSheet(url: page.url, persistent: page.persistent)
                .frame(minWidth: 820, minHeight: 640)
        }
    }

    private func header(_ palette: AppPalette) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: theme == .console ? 4 : 9, style: .continuous)
                    .fill(pullRequest.isDraft ? palette.warningSoft : palette.successSoft)
                Image(gattoSymbol: "git.pull.request")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(pullRequest.isDraft ? palette.warning : palette.success)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(pullRequest.title)
                        .font(font(size: 16, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text("#\(pullRequest.number)")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                }
                HStack(spacing: 6) {
                    Text(pullRequest.author)
                    Text("·")
                    Text(pullRequest.headBranch)
                    Image(gattoSymbol: "arrow.right")
                    Text(pullRequest.baseBranch)
                }
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.mutedInk)
            }

            Spacer(minLength: 12)

            if model.isLoadingPullRequestReview {
                ProgressView().controlSize(.small)
            }
            ToolbarIconButton(
                systemName: "arrow.clockwise",
                helpKey: "action.refresh",
                isActive: model.isLoadingPullRequestReview,
                isDisabled: model.isLoadingPullRequestReview
            ) {
                model.refreshPullRequestReview()
            }
            Button {
                inAppBrowserPage = InAppBrowserPage(url: pullRequest.webURL, persistent: true)
            } label: {
                GattoLabel(L10n.text("github.review.open_github"), systemImage: "arrow.up.right")
            }
            .buttonStyle(SecondaryButtonStyle())
            Button {
                model.closePullRequestReview()
                dismiss()
            } label: {
                Image(gattoSymbol: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.mutedInk)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("action.close"))
        }
        .padding(.horizontal, 18)
        .frame(height: 68)
        .background(theme == .softGlass ? palette.surface.opacity(0.18) : palette.surface)
    }

    private func tabBar(_ palette: AppPalette) -> some View {
        HStack(spacing: 4) {
            ForEach(GitHubPullRequestReviewTab.allCases) { tab in
                let count = tabCount(tab)
                Button {
                    model.pullRequestReviewTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(gattoSymbol: tab.icon)
                        Text(L10n.text("github.review.tab.\(tab.rawValue)"))
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(palette.subtleInk)
                        }
                    }
                    .font(font(size: 11.5, weight: .semibold))
                    .foregroundStyle(model.pullRequestReviewTab == tab ? palette.primary : palette.mutedInk)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(model.pullRequestReviewTab == tab ? palette.primarySoft : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: theme == .console ? 4 : 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.pullRequestReviewTab == tab ? .isSelected : [])
            }
            Spacer()
            if let error = model.pullRequestReviewError {
                GattoLabel(error, systemImage: "exclamationmark.triangle.fill")
                    .font(font(size: 10, weight: .medium))
                    .foregroundStyle(palette.danger)
                    .lineLimit(1)
                    .help(error)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(theme == .softGlass ? palette.surface.opacity(0.12) : palette.surface)
    }

    @ViewBuilder
    private func tabContent(_ center: GitHubPullRequestReviewCenter, palette: AppPalette) -> some View {
        switch model.pullRequestReviewTab {
        case .conversation:
            conversation(center, palette: palette)
        case .commits:
            commits(center.commits, palette: palette)
        case .files:
            files(center.files, palette: palette)
        case .checks:
            checks(center.checks, palette: palette)
        }
    }

    private func conversation(_ center: GitHubPullRequestReviewCenter, palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let body = pullRequest.body, !body.isEmpty {
                        ConversationEntry(
                            author: pullRequest.author,
                            metadata: L10n.text("github.review.opened_pull_request"),
                            content: body,
                            systemImage: "git.pull.request",
                            tint: palette.success,
                            theme: theme
                        )
                    }
                    ForEach(center.comments) { comment in
                        ConversationEntry(
                            author: comment.author,
                            metadata: comment.createdAt.formatted(date: .abbreviated, time: .shortened),
                            content: comment.body,
                            systemImage: comment.kind == .review ? "text.bubble" : "bubble.left",
                            tint: palette.accent,
                            path: comment.path,
                            line: comment.line,
                            theme: theme
                        )
                    }
                    ForEach(center.reviews) { review in
                        ConversationEntry(
                            author: review.author,
                            metadata: L10n.text("github.review.state.\(review.state.lowercased())"),
                            content: review.body ?? "",
                            systemImage: review.state.lowercased() == "approved" ? "checkmark.circle.fill" : "eye",
                            tint: review.state.lowercased() == "approved" ? palette.success : palette.warning,
                            theme: theme
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }

            Rectangle().fill(palette.divider).frame(height: 1)
            reviewComposer(palette)
        }
    }

    private func reviewComposer(_ palette: AppPalette) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Text(L10n.text("github.review.submit.title"))
                    .font(font(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.mutedInk)
                Picker("", selection: $model.pullRequestReviewEvent) {
                    ForEach(GitHubPullRequestReviewEvent.allCases) { event in
                        Text(L10n.text("github.review.event.\(event.key)"))
                            .tag(event)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 330)
                Spacer()
                if model.isDraftingPullRequestReply {
                    ProgressView().controlSize(.small)
                }
            }

            TextEditor(text: $model.pullRequestReviewDraft)
                .font(font(size: 12, weight: .regular))
                .foregroundStyle(palette.ink)
                .scrollContentBackground(.hidden)
                .padding(7)
                .frame(minHeight: 72, maxHeight: 96)
                .background(palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous)
                        .stroke(palette.divider, lineWidth: 1)
                }
                .disabled(model.activeGitHubOperation != nil || model.isDraftingPullRequestReply)

            HStack(spacing: 8) {
                if model.isDraftingPullRequestReply {
                    Button(L10n.text("github.action.stop_ai")) { model.cancelPullRequestDraft() }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button {
                        model.draftPullRequestReview()
                    } label: {
                        GattoLabel(L10n.text("github.review.action.agent_draft"), systemImage: "sparkles")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!model.canDraftPullRequestReply)
                }
                Spacer()
                Button(L10n.text("github.review.action.submit")) {
                    model.submitPullRequestReview()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(
                    model.activeGitHubOperation != nil
                        || model.isDraftingPullRequestReply
                        || (model.pullRequestReviewEvent == .requestChanges
                            && model.pullRequestReviewDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                )
            }
        }
        .padding(14)
        .background(theme == .softGlass ? palette.surface.opacity(0.14) : palette.surface)
    }

    private func commits(_ commits: [GitHubPullRequestCommit], palette: AppPalette) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(commits) { commit in
                    HStack(spacing: 12) {
                        Image(gattoSymbol: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(commit.message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? commit.message)
                                .font(font(size: 12.5, weight: .medium))
                                .foregroundStyle(palette.ink)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Text(commit.author)
                                if let date = commit.date {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                }
                            }
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.subtleInk)
                        }
                        Spacer()
                        Text(commit.shortSHA)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.mutedInk)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 20)
                    .frame(minHeight: 58)
                    Rectangle().fill(palette.divider).frame(height: 1).padding(.leading, 56)
                }
            }
        }
    }

    private func files(_ files: [GitHubPullRequestFile], palette: AppPalette) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text(L10n.text("github.review.files.changed"))
                        .font(font(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.mutedInk)
                    Spacer()
                    Text("\(files.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                }
                .padding(.horizontal, 12)
                .frame(height: 42)
                Rectangle().fill(palette.divider).frame(height: 1)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(files) { file in
                            PullRequestFileRow(
                                file: file,
                                selected: model.selectedPullRequestFile?.id == file.id,
                                viewed: model.viewedPullRequestFilePaths.contains(file.path),
                                theme: theme
                            ) {
                                model.selectedPullRequestFile = file
                                model.pullRequestCommentLine = ""
                            }
                        }
                    }
                    .padding(7)
                }
            }
            .frame(width: 300)
            .background(theme == .softGlass ? palette.sidebar.opacity(0.14) : palette.sidebar)

            Rectangle().fill(palette.divider).frame(width: 1)

            if let file = model.selectedPullRequestFile ?? files.first {
                PullRequestFileInspector(model: model, file: file, theme: theme)
            } else {
                empty(L10n.text("github.review.files.empty"), icon: "doc.text", palette: palette)
            }
        }
    }

    private func checks(_ checks: [GitHubPullRequestCheck], palette: AppPalette) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(checks) { check in
                    HStack(spacing: 12) {
                        CheckStateGlyph(status: check.status, conclusion: check.conclusion)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(check.name)
                                .font(font(size: 12.5, weight: .medium))
                                .foregroundStyle(palette.ink)
                            Text(L10n.text("github.actions.status.\((check.conclusion ?? check.status).lowercased())"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(palette.subtleInk)
                        }
                        Spacer()
                        if let startedAt = check.startedAt {
                            Text(startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 10.5))
                                .foregroundStyle(palette.subtleInk)
                        }
                        if let url = check.detailsURL {
                            Button {
                                inAppBrowserPage = InAppBrowserPage(url: url, persistent: true)
                            } label: {
                                Image(gattoSymbol: "arrow.up.right")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(palette.primary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(minHeight: 58)
                    Rectangle().fill(palette.divider).frame(height: 1).padding(.leading, 54)
                }
            }
        }
        .overlay {
            if checks.isEmpty {
                empty(L10n.text("github.review.checks.empty"), icon: "checkmark.shield", palette: palette)
            }
        }
    }

    private func reviewLoading() -> some View {
        GattoLoadingState(text: L10n.text("github.review.loading"))
    }

    private func errorView(_ message: String, palette: AppPalette) -> some View {
        VStack(spacing: 12) {
            Image(gattoSymbol: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(palette.danger)
            Text(message)
                .font(font(size: 12, weight: .medium))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Button(L10n.text("github.action.retry")) { model.refreshPullRequestReview() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func empty(_ text: String, icon: String, palette: AppPalette) -> some View {
        VStack(spacing: 9) {
            Image(gattoSymbol: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            Text(text)
                .font(font(size: 12, weight: .medium))
                .foregroundStyle(palette.mutedInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tabCount(_ tab: GitHubPullRequestReviewTab) -> Int {
        guard let center = model.pullRequestReviewCenter else { return 0 }
        switch tab {
        case .conversation: return center.comments.count + center.reviews.count
        case .commits: return center.commits.count
        case .files: return center.files.count
        case .checks: return center.checks.count
        }
    }

    private func font(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: theme == .console ? .monospaced : .default)
    }
}

private struct ConversationEntry: View {
    let author: String
    let metadata: String
    let content: String
    let systemImage: String
    let tint: Color
    var path: String?
    var line: Int?
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.14))
                Image(gattoSymbol: systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(author)
                        .font(.system(size: 11.5, weight: .semibold, design: theme == .console ? .monospaced : .default))
                        .foregroundStyle(palette.ink)
                    Text(metadata)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.subtleInk)
                    if let path {
                        Text(line.map { "\(path):\($0)" } ?? path)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.accent)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                if !content.isEmpty {
                    Text(attributed(content))
                        .font(.system(size: 12.5, design: theme == .console ? .monospaced : .default))
                        .foregroundStyle(palette.ink)
                        .textSelection(.enabled)
                }
            }
            .padding(.bottom, 15)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.divider).frame(height: 1)
            }
        }
        .padding(.top, 12)
    }

    private func attributed(_ text: String) -> AttributedString {
        let cleaned = CodexResponseFormatter.clean(text)
        return (try? AttributedString(markdown: cleaned)) ?? AttributedString(cleaned)
    }
}

private struct PullRequestFileRow: View {
    let file: GitHubPullRequestFile
    let selected: Bool
    let viewed: Bool
    let theme: AppVisualTheme
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(gattoSymbol: viewed ? "checkmark.circle.fill" : "doc.text")
                        .foregroundStyle(viewed ? palette.success : palette.subtleInk)
                        .frame(width: 16)
                    Text(file.path)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 9) {
                    Text(file.status)
                    Text("+\(file.additions)").foregroundStyle(palette.success)
                    Text("−\(file.deletions)").foregroundStyle(palette.danger)
                }
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.subtleInk)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? palette.primarySoft : (hovering ? palette.raisedSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: theme == .console ? 4 : 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PullRequestFileInspector: View {
    @ObservedObject var model: WorkspaceViewModel
    let file: GitHubPullRequestFile
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var colorScheme

    private var document: DiffDocument {
        GitParsers.diff(from: file.patch ?? "", path: file.path)
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous)
                        .fill(palette.primarySoft)
                    Image(gattoSymbol: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.primary)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.path)
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(L10n.format("github.review.file.summary", file.additions, file.deletions, file.changes))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                }
                Spacer()
                let viewed = model.viewedPullRequestFilePaths.contains(file.path)
                Button {
                    model.setPullRequestFileViewed(file, viewed: !viewed)
                } label: {
                    GattoLabel(
                        L10n.text(viewed ? "github.review.action.unmark_viewed" : "github.review.action.mark_viewed"),
                        systemImage: viewed ? "eye.slash" : "checkmark"
                    )
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.activeGitHubOperation != nil)
            }
            .padding(.horizontal, 13)
            .frame(height: 62)
            .background(theme == .softGlass ? palette.surface.opacity(0.14) : palette.surface)

            Rectangle().fill(palette.divider).frame(height: 1)

            if file.patch == nil {
                VStack(spacing: 9) {
                    Image(gattoSymbol: "doc.badge.ellipsis")
                        .font(.system(size: 21))
                        .foregroundStyle(palette.subtleInk)
                    Text(L10n.text("github.review.patch.unavailable"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.mutedInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiffCodeView(document: document) { line in
                    if let number = line.newLineNumber {
                        model.pullRequestCommentLine = String(number)
                    }
                }
            }

            Rectangle().fill(palette.divider).frame(height: 1)
            HStack(spacing: 8) {
                TextField(L10n.text("github.review.line.placeholder"), text: $model.pullRequestCommentLine)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 9)
                    .frame(width: 88, height: 30)
                    .background(palette.raisedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: theme == .console ? 4 : 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: theme == .console ? 4 : 7, style: .continuous)
                            .stroke(palette.divider, lineWidth: 1)
                    }
                TextField(L10n.text("github.review.comment.placeholder"), text: $model.pullRequestLineCommentDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(palette.raisedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: theme == .console ? 4 : 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: theme == .console ? 4 : 7, style: .continuous)
                            .stroke(palette.divider, lineWidth: 1)
                    }
                Button(L10n.text("github.review.action.comment")) {
                    model.publishPullRequestLineComment()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(
                    Int(model.pullRequestCommentLine) == nil
                        || model.pullRequestLineCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.activeGitHubOperation != nil
                )
            }
            .padding(11)
            .background(theme == .softGlass ? palette.surface.opacity(0.14) : palette.surface)
        }
        .onAppear {
            if model.selectedPullRequestFile?.id != file.id {
                model.selectedPullRequestFile = file
            }
        }
    }
}

struct CheckStateGlyph: View {
    let status: String
    let conclusion: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        if ["queued", "in_progress", "waiting", "requested", "pending"].contains(status.lowercased()) {
            ProgressView().controlSize(.small).tint(palette.accent).frame(width: 24)
        } else {
            Image(gattoSymbol: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color(palette))
                .frame(width: 24)
        }
    }

    private var icon: String {
        switch conclusion?.lowercased() {
        case "success", "neutral", "skipped": "checkmark.circle.fill"
        case "cancelled": "minus.circle.fill"
        default: "xmark.circle.fill"
        }
    }

    private func color(_ palette: AppPalette) -> Color {
        switch conclusion?.lowercased() {
        case "success", "neutral", "skipped": palette.success
        case "cancelled": palette.subtleInk
        default: palette.danger
        }
    }
}

private extension GitHubPullRequestReviewTab {
    var icon: String {
        switch self {
        case .conversation: "bubble.left.and.bubble.right"
        case .commits: "point.topleft.down.to.point.bottomright.curvepath"
        case .files: "doc.text.magnifyingglass"
        case .checks: "checkmark.shield"
        }
    }
}

private extension GitHubPullRequestReviewEvent {
    var key: String {
        switch self {
        case .comment: "comment"
        case .approve: "approve"
        case .requestChanges: "request_changes"
        }
    }
}
