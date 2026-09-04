import SwiftUI

struct GitHubInboxView: View {
    @ObservedObject var collaborationModel: GitHubCollaborationViewModel
    let openURL: (URL) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedItemID: String?

    private var selectedItem: GitHubInboxItem? {
        collaborationModel.filteredInboxItems.first { $0.id == selectedItemID }
            ?? collaborationModel.filteredInboxItems.first
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            header(palette)
            Rectangle().fill(palette.divider).frame(height: 1)
            filterBar(palette)
            Rectangle().fill(palette.divider).frame(height: 1)

            if collaborationModel.isLoadingInbox, collaborationModel.inboxItems.isEmpty {
                GattoLoadingState(text: L10n.text("github.inbox.loading"))
            } else if let error = collaborationModel.inboxError, collaborationModel.inboxItems.isEmpty {
                collaborationError(error, retry: { collaborationModel.loadInbox(force: true) })
            } else if collaborationModel.filteredInboxItems.isEmpty {
                InspectorEmptyState(
                    image: "tray",
                    titleKey: "github.inbox.empty.title",
                    bodyKey: "github.inbox.empty.body"
                )
            } else {
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        inboxList(palette)
                            .frame(width: min(430, max(290, proxy.size.width * 0.4)))
                        Rectangle().fill(palette.divider).frame(width: 1)
                        inboxDetail(selectedItem, palette: palette)
                    }
                }
            }
        }
        .background(palette.surface)
        .onChange(of: collaborationModel.filteredInboxItems.map(\.id), initial: true) { _, ids in
            if selectedItemID == nil || !ids.contains(selectedItemID ?? "") {
                selectedItemID = ids.first
            }
        }
    }

    private func header(_ palette: AppPalette) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text("github.inbox.title"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text(L10n.format("github.inbox.count", collaborationModel.filteredInboxItems.count))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
            }
            Spacer()
            Button {
                collaborationModel.loadInbox(force: true)
            } label: {
                if collaborationModel.isLoadingInbox {
                    ProgressView().controlSize(.small)
                } else {
                    Image(gattoSymbol: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .help(L10n.text("action.refresh"))
            .disabled(collaborationModel.isLoadingInbox)
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
    }

    private func filterBar(_ palette: AppPalette) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                categoryMenu(palette)
                Spacer(minLength: 10)
                searchField(palette)
            }
            VStack(alignment: .leading, spacing: 8) {
                categoryMenu(palette)
                searchField(palette)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(palette.raisedSurface.opacity(0.58))
    }

    private func categoryMenu(_ palette: AppPalette) -> some View {
        Menu {
            Button(L10n.text("github.inbox.category.all")) { collaborationModel.inboxCategory = nil }
            Divider()
            ForEach(GitHubInboxCategory.allCases) { category in
                Button(L10n.text("github.inbox.category.\(category.rawValue)")) {
                    collaborationModel.inboxCategory = category
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(gattoSymbol: "line.3.horizontal.decrease.circle")
                Text(
                    collaborationModel.inboxCategory.map {
                        L10n.text("github.inbox.category.\($0.rawValue)")
                    } ?? L10n.text("github.inbox.category.all")
                )
                Image(gattoSymbol: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.mutedInk)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func searchField(_ palette: AppPalette) -> some View {
        HStack(spacing: 7) {
            Image(gattoSymbol: "magnifyingglass")
                .foregroundStyle(palette.subtleInk)
            TextField(L10n.text("github.inbox.search"), text: $collaborationModel.inboxQuery)
                .textFieldStyle(.plain)
            if !collaborationModel.inboxQuery.isEmpty {
                Button { collaborationModel.inboxQuery = "" } label: {
                    Image(gattoSymbol: "xmark.circle.fill")
                        .foregroundStyle(palette.subtleInk)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 10)
        .frame(minWidth: 220, idealWidth: 300, maxWidth: 360)
        .frame(height: 31)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(palette.divider) }
    }

    private func inboxList(_ palette: AppPalette) -> some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(collaborationModel.filteredInboxItems) { item in
                    Button { selectedItemID = item.id } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 7) {
                                Image(gattoSymbol: item.subjectKind.symbol)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.primary)
                                    .frame(width: 22)
                                Text(item.repositoryName)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(palette.mutedInk)
                                    .lineLimit(1)
                                Spacer()
                                Text(item.updatedAt.formatted(.relative(presentation: .named)))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(palette.subtleInk)
                            }
                            Text(item.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(palette.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 5) {
                                if let number = item.number {
                                    Text("#\(number)")
                                }
                                ForEach(Array(item.categories.sorted { $0.rawValue < $1.rawValue }.prefix(2))) { category in
                                    Text(L10n.text("github.inbox.category.\(category.rawValue)"))
                                        .padding(.horizontal, 6)
                                        .frame(height: 18)
                                        .background(palette.primarySoft)
                                        .clipShape(Capsule())
                                }
                            }
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(palette.subtleInk)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedItemID == item.id ? palette.primarySoft : palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedItemID == item.id ? palette.primary.opacity(0.4) : palette.divider)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
        .background(palette.sidebar)
    }

    @ViewBuilder
    private func inboxDetail(_ item: GitHubInboxItem?, palette: AppPalette) -> some View {
        if let item {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(gattoSymbol: item.subjectKind.symbol)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(palette.primary)
                            .frame(width: 42, height: 42)
                            .background(palette.primarySoft)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(palette.ink)
                            HStack(spacing: 7) {
                                Text(item.repositoryName)
                                if let number = item.number { Text("#\(number)") }
                                if let author = item.author { Text("@\(author)") }
                            }
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.subtleInk)
                        }
                        Spacer()
                    }
                    HStack(spacing: 7) {
                        ForEach(item.categories.sorted { $0.rawValue < $1.rawValue }) { category in
                            Text(L10n.text("github.inbox.category.\(category.rawValue)"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(palette.primary)
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(palette.primarySoft)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(22)
                Rectangle().fill(palette.divider).frame(height: 1)
                Spacer()
                HStack {
                    Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.subtleInk)
                    Spacer()
                    Button {
                        openURL(item.webURL)
                    } label: {
                        Label(L10n.text("github.inbox.open"), systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(18)
            }
        } else {
            InspectorEmptyState(
                image: "tray",
                titleKey: "github.inbox.empty.title",
                bodyKey: "github.inbox.empty.body"
            )
        }
    }

    private func collaborationError(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(gattoSymbol: "exclamationmark.triangle")
                .font(.system(size: 22))
            Text(message).textSelection(.enabled).multilineTextAlignment(.center)
            Button(L10n.text("action.retry"), action: retry).buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GitHubIssuesView: View {
    @ObservedObject var collaborationModel: GitHubCollaborationViewModel
    let openURL: (URL) -> Void
    let localRepositoryURL: (GitHubRepository) -> URL?
    let createBranch: (GitHubIssue, GitHubRepository, URL) -> Void
    let sendToAgent: (GitHubIssue, GitHubRepository, URL) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var editorContext: IssueEditorContext?

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            header(palette)
            Rectangle().fill(palette.divider).frame(height: 1)
            filterBar(palette)
            Rectangle().fill(palette.divider).frame(height: 1)

            if collaborationModel.selectedRepository == nil {
                InspectorEmptyState(
                    image: "circle.dotted",
                    titleKey: "github.issues.repository.empty.title",
                    bodyKey: "github.issues.repository.empty.body"
                )
            } else if collaborationModel.isLoadingIssues, collaborationModel.issues.isEmpty {
                GattoLoadingState(text: L10n.text("github.issues.loading"))
            } else if let error = collaborationModel.issueError, collaborationModel.issues.isEmpty {
                collaborationError(error)
            } else {
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        issueList(palette)
                            .frame(width: min(430, max(300, proxy.size.width * 0.4)))
                        Rectangle().fill(palette.divider).frame(width: 1)
                        issueDetail(collaborationModel.selectedIssue, palette: palette)
                    }
                }
            }
        }
        .background(palette.surface)
        .sheet(item: $editorContext) { context in
            IssueEditorSheet(
                context: context,
                isSaving: collaborationModel.isSavingIssue,
                save: { draft in
                    if let issue = context.issue {
                        return await collaborationModel.updateIssue(issue, draft: draft, state: issue.state)
                    }
                    return await collaborationModel.createIssue(draft)
                }
            )
            .frame(minWidth: 620, minHeight: 560)
        }
    }

    private func header(_ palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text("github.issues.title"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text(L10n.format("github.issues.count", collaborationModel.filteredIssues.count))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
            }
            Spacer()
            Button {
                collaborationModel.loadIssues(force: true)
            } label: {
                if collaborationModel.isLoadingIssues {
                    ProgressView().controlSize(.small)
                } else {
                    Image(gattoSymbol: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(collaborationModel.selectedRepository == nil || collaborationModel.isLoadingIssues)
            Button {
                editorContext = IssueEditorContext(issue: nil)
            } label: {
                Label(L10n.text("github.issues.new"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(collaborationModel.selectedRepository == nil)
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
    }

    private func filterBar(_ palette: AppPalette) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                repositoryPicker
                statePicker
                Spacer(minLength: 8)
                issueSearch(palette)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { repositoryPicker; statePicker }
                issueSearch(palette)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(palette.raisedSurface.opacity(0.58))
    }

    private var repositoryPicker: some View {
        Picker(
            L10n.text("github.issues.repository"),
            selection: Binding(
                get: { collaborationModel.selectedRepository?.id },
                set: { id in
                    collaborationModel.selectRepository(
                        collaborationModel.repositories.first(where: { $0.id == id })
                    )
                }
            )
        ) {
            ForEach(collaborationModel.repositories) { repository in
                Text(repository.fullName).tag(Optional(repository.id))
            }
        }
        .labelsHidden()
        .frame(minWidth: 190, maxWidth: 300)
    }

    private var statePicker: some View {
        Picker(
            L10n.text("github.issues.state"),
            selection: Binding(
                get: { collaborationModel.issueState },
                set: { collaborationModel.changeIssueState($0) }
            )
        ) {
            ForEach(GitHubIssueState.allCases) { state in
                Text(L10n.text("github.issues.state.\(state.rawValue)")).tag(state)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 168)
    }

    private func issueSearch(_ palette: AppPalette) -> some View {
        HStack(spacing: 7) {
            Image(gattoSymbol: "magnifyingglass").foregroundStyle(palette.subtleInk)
            TextField(L10n.text("github.issues.search"), text: $collaborationModel.issueQuery)
                .textFieldStyle(.plain)
            if !collaborationModel.issueQuery.isEmpty {
                Button { collaborationModel.issueQuery = "" } label: {
                    Image(gattoSymbol: "xmark.circle.fill").foregroundStyle(palette.subtleInk)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 10)
        .frame(minWidth: 220, idealWidth: 300, maxWidth: 360)
        .frame(height: 31)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(palette.divider) }
    }

    private func issueList(_ palette: AppPalette) -> some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(collaborationModel.filteredIssues) { issue in
                    Button { collaborationModel.selectIssue(issue) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 7) {
                                Image(gattoSymbol: issue.state == .open ? "circle.dotted" : "checkmark.circle")
                                    .foregroundStyle(issue.state == .open ? palette.success : palette.subtleInk)
                                Text("#\(issue.number)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.subtleInk)
                                Spacer()
                                Text(issue.updatedAt.formatted(.relative(presentation: .named)))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(palette.subtleInk)
                            }
                            Text(issue.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(palette.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 5) {
                                ForEach(issue.labels.prefix(3)) { label in
                                    IssueLabelChip(label: label)
                                }
                                Spacer()
                                if issue.commentCount > 0 {
                                    Label("\(issue.commentCount)", systemImage: "bubble.left")
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(palette.subtleInk)
                                }
                            }
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(collaborationModel.selectedIssue?.id == issue.id ? palette.primarySoft : palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(collaborationModel.selectedIssue?.id == issue.id ? palette.primary.opacity(0.4) : palette.divider)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if collaborationModel.canLoadMoreIssues {
                    Button {
                        collaborationModel.loadMoreIssues()
                    } label: {
                        if collaborationModel.isLoadingMoreIssues {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L10n.text("action.load_more"))
                        }
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 8)
                }
            }
            .padding(10)
        }
        .background(palette.sidebar)
    }

    @ViewBuilder
    private func issueDetail(_ issue: GitHubIssue?, palette: AppPalette) -> some View {
        if let issue, let repository = collaborationModel.selectedRepository {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(gattoSymbol: issue.state == .open ? "circle.dotted" : "checkmark.circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(issue.state == .open ? palette.success : palette.subtleInk)
                                .frame(width: 40, height: 40)
                                .background((issue.state == .open ? palette.success : palette.subtleInk).opacity(0.09))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(issue.title)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(palette.ink)
                                Text("\(repository.fullName)  #\(issue.number)  @\(issue.author)")
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(palette.subtleInk)
                            }
                            Spacer()
                            Menu {
                                Button(L10n.text("github.issues.edit")) {
                                    editorContext = IssueEditorContext(issue: issue)
                                }
                                Button(L10n.text(issue.state == .open ? "github.issues.close" : "github.issues.reopen")) {
                                    Task {
                                        _ = await collaborationModel.updateIssue(
                                            issue,
                                            draft: issue.draft,
                                            state: issue.state == .open ? .closed : .open
                                        )
                                    }
                                }
                            } label: {
                                Image(gattoSymbol: "ellipsis")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }

                        HStack(spacing: 6) {
                            ForEach(issue.labels) { label in IssueLabelChip(label: label) }
                        }

                        GroupBox {
                            if let body = issue.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                ReleaseNotesMarkdownView(text: body, openURL: openURL)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text(L10n.text("github.issues.body.empty"))
                                    .foregroundStyle(palette.subtleInk)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        HStack(spacing: 8) {
                            Button { openURL(issue.webURL) } label: {
                                Label(L10n.text("github.issues.open"), systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.bordered)

                            if let localURL = localRepositoryURL(repository) {
                                Button { createBranch(issue, repository, localURL) } label: {
                                    Label(L10n.text("github.issues.create_branch"), systemImage: "arrow.triangle.branch")
                                }
                                .buttonStyle(.bordered)
                                Button { sendToAgent(issue, repository, localURL) } label: {
                                    Label(L10n.text("github.issues.send_agent"), systemImage: "sparkles")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        Divider()
                        HStack {
                            Text(L10n.format("github.issues.comments", collaborationModel.issueComments.count))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.ink)
                            Spacer()
                            if collaborationModel.isLoadingIssueComments { ProgressView().controlSize(.small) }
                        }

                        ForEach(collaborationModel.issueComments) { comment in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("@\(comment.author)")
                                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    Spacer()
                                    Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(palette.subtleInk)
                                }
                                ReleaseNotesMarkdownView(text: comment.body, openURL: openURL)
                            }
                            .padding(12)
                            .background(palette.raisedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 11).stroke(palette.divider) }
                        }
                    }
                    .padding(18)
                }

                Rectangle().fill(palette.divider).frame(height: 1)
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        if collaborationModel.issueReplyDraft.isEmpty {
                            Text(L10n.text("github.issues.comment.placeholder"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.subtleInk)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $collaborationModel.issueReplyDraft)
                            .font(.system(size: 11.5))
                            .padding(5)
                            .scrollContentBackground(.hidden)
                            .disabled(collaborationModel.isDraftingIssueReply || collaborationModel.isSavingIssue)
                    }
                    .frame(minHeight: 54, maxHeight: 88)
                    .background(palette.raisedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 9).stroke(palette.divider) }

                    HStack(spacing: 8) {
                        Button {
                            if collaborationModel.isDraftingIssueReply {
                                collaborationModel.cancelIssueReplyDraft()
                            } else {
                                collaborationModel.draftIssueReply()
                            }
                        } label: {
                            ReadmeRewriteMotionLabel(
                                title: L10n.text(collaborationModel.isDraftingIssueReply
                                    ? "github.issues.comment.agent_drafting"
                                    : "github.issues.comment.agent_draft"),
                                isActive: collaborationModel.isDraftingIssueReply,
                                completionID: collaborationModel.issueReplyCompletionID
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!collaborationModel.canDraftIssueReply && !collaborationModel.isDraftingIssueReply)

                        Spacer()

                        Button(L10n.text("github.issues.comment.send")) {
                            Task { _ = await collaborationModel.publishIssueReply() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            collaborationModel.issueReplyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || collaborationModel.isSavingIssue
                                || collaborationModel.isDraftingIssueReply
                        )
                    }

                    if let error = collaborationModel.issueReplyError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.danger)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
            }
        } else if collaborationModel.issues.isEmpty {
            InspectorEmptyState(
                image: "circle.dotted",
                titleKey: "github.issues.empty.title",
                bodyKey: "github.issues.empty.body"
            )
        } else {
            InspectorEmptyState(
                image: "cursorarrow.click",
                titleKey: "github.issues.select.title",
                bodyKey: "github.issues.select.body"
            )
        }
    }

    private func collaborationError(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(gattoSymbol: "exclamationmark.triangle").font(.system(size: 22))
            Text(message).textSelection(.enabled).multilineTextAlignment(.center)
            Button(L10n.text("action.retry")) { collaborationModel.loadIssues(force: true) }
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct IssueEditorContext: Identifiable {
    let id = UUID()
    let issue: GitHubIssue?
}

private struct IssueEditorSheet: View {
    let context: IssueEditorContext
    let isSaving: Bool
    let save: (GitHubIssueDraft) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var title: String
    @State private var descriptionText: String
    @State private var labels: String
    @State private var assignees: String
    @State private var milestone: String

    init(
        context: IssueEditorContext,
        isSaving: Bool,
        save: @escaping (GitHubIssueDraft) async -> Bool
    ) {
        self.context = context
        self.isSaving = isSaving
        self.save = save
        _title = State(initialValue: context.issue?.title ?? "")
        _descriptionText = State(initialValue: context.issue?.body ?? "")
        _labels = State(initialValue: context.issue?.labels.map(\.name).joined(separator: ", ") ?? "")
        _assignees = State(initialValue: context.issue?.assignees.joined(separator: ", ") ?? "")
        _milestone = State(initialValue: context.issue?.milestone.map { String($0.number) } ?? "")
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text(context.issue == nil ? "github.issues.editor.new" : "github.issues.editor.edit"))
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(L10n.text("action.cancel")) { dismiss() }
                    .buttonStyle(.borderless)
                Button {
                    Task {
                        if await save(draft) { dismiss() }
                    }
                } label: {
                    if isSaving { ProgressView().controlSize(.small) }
                    else { Text(L10n.text("action.save")) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
            .padding(18)
            Rectangle().fill(palette.divider).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    editorField(L10n.text("github.issues.editor.title"), text: $title)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.text("github.issues.editor.body"))
                            .font(.system(size: 11, weight: .semibold))
                        TextEditor(text: $descriptionText)
                            .font(.system(size: 12))
                            .frame(minHeight: 220)
                            .padding(7)
                            .scrollContentBackground(.hidden)
                            .background(palette.raisedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 10).stroke(palette.divider) }
                    }
                    editorField(L10n.text("github.issues.editor.labels"), text: $labels)
                    editorField(L10n.text("github.issues.editor.assignees"), text: $assignees)
                    editorField(L10n.text("github.issues.editor.milestone"), text: $milestone)
                }
                .padding(20)
            }
        }
        .background(palette.surface)
    }

    private func editorField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 11, weight: .semibold))
            TextField("", text: text).textFieldStyle(.roundedBorder)
        }
    }

    private var draft: GitHubIssueDraft {
        GitHubIssueDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: descriptionText,
            labels: separated(labels),
            assignees: separated(assignees),
            milestoneNumber: Int(milestone.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }

    private func separated(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct IssueLabelChip: View {
    let label: GitHubIssueLabel

    var body: some View {
        let color = Color(hex: label.colorHex) ?? .secondary
        Text(label.name)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }
}

private extension GitHubIssue {
    var draft: GitHubIssueDraft {
        GitHubIssueDraft(
            title: title,
            body: body ?? "",
            labels: labels.map(\.name),
            assignees: assignees,
            milestoneNumber: milestone?.number
        )
    }
}

private extension GitHubInboxSubjectKind {
    var symbol: String {
        switch self {
        case .pullRequest: "arrow.triangle.pull"
        case .issue: "circle.dotted"
        case .action: "play.circle"
        case .release: "shippingbox"
        case .discussion: "bubble.left.and.bubble.right"
        case .other: "bell"
        }
    }
}
