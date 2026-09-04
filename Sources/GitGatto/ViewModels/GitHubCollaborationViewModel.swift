import Combine
import Foundation

@MainActor
final class GitHubCollaborationViewModel: ObservableObject {
    @Published private(set) var inboxItems: [GitHubInboxItem] = []
    @Published var inboxCategory: GitHubInboxCategory?
    @Published var inboxQuery = ""
    @Published private(set) var isLoadingInbox = false
    @Published private(set) var inboxError: String?

    @Published private(set) var repositories: [GitHubRepository] = []
    @Published var selectedRepository: GitHubRepository?
    @Published var issueState: GitHubIssueState = .open
    @Published var issueQuery = ""
    @Published private(set) var issues: [GitHubIssue] = []
    @Published var selectedIssue: GitHubIssue?
    @Published private(set) var issueComments: [GitHubIssueComment] = []
    @Published private(set) var isLoadingIssues = false
    @Published private(set) var isLoadingMoreIssues = false
    @Published private(set) var canLoadMoreIssues = false
    @Published private(set) var isLoadingIssueComments = false
    @Published private(set) var isSavingIssue = false
    @Published private(set) var issueError: String?
    @Published var issueReplyDraft = ""
    @Published private(set) var isDraftingIssueReply = false
    @Published private(set) var issueReplyError: String?
    @Published private(set) var issueReplyCompletionID: UUID?

    private let service: any GitHubServing
    private let replyService: any CodexServing
    private var inboxTask: Task<Void, Never>?
    private var issuesTask: Task<Void, Never>?
    private var commentsTask: Task<Void, Never>?
    private var mutationTask: Task<Void, Never>?
    private var issueReplyTask: Task<Void, Never>?
    private var issuePage = 0
    private var didLoadInbox = false
    private var inboxRequestID: UUID?
    private var issuesRequestID: UUID?
    private var commentsRequestID: UUID?

    init(
        service: any GitHubServing = GitHubService(),
        replyService: any CodexServing = CodexService(lane: .project)
    ) {
        self.service = service
        self.replyService = replyService
    }

    var filteredInboxItems: [GitHubInboxItem] {
        let needle = inboxQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return inboxItems.filter { item in
            let matchesCategory = inboxCategory.map(item.categories.contains) ?? true
            let matchesQuery = needle.isEmpty
                || item.title.localizedCaseInsensitiveContains(needle)
                || item.repositoryName.localizedCaseInsensitiveContains(needle)
                || item.author?.localizedCaseInsensitiveContains(needle) == true
            return matchesCategory && matchesQuery
        }
    }

    var filteredIssues: [GitHubIssue] {
        let needle = issueQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return issues }
        return issues.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.body?.localizedCaseInsensitiveContains(needle) == true
                || $0.author.localizedCaseInsensitiveContains(needle)
                || String($0.number) == needle
                || $0.labels.contains { $0.name.localizedCaseInsensitiveContains(needle) }
        }
    }

    func configure(repositories: [GitHubRepository]) {
        guard self.repositories != repositories else { return }
        self.repositories = repositories
        if let selectedRepository,
           let updated = repositories.first(where: { $0.id == selectedRepository.id }) {
            self.selectedRepository = updated
        } else {
            selectedRepository = repositories.first
            resetIssues()
        }
    }

    func loadInbox(force: Bool = false) {
        guard force || (!didLoadInbox && !isLoadingInbox) else { return }
        inboxTask?.cancel()
        isLoadingInbox = true
        inboxError = nil
        let requestID = UUID()
        inboxRequestID = requestID
        let service = self.service
        inboxTask = Task {
            defer {
                if inboxRequestID == requestID {
                    isLoadingInbox = false
                    inboxTask = nil
                    inboxRequestID = nil
                }
            }
            do {
                let values = try await service.inbox()
                guard !Task.isCancelled else { return }
                inboxItems = values
                didLoadInbox = true
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                inboxError = error.localizedDescription
            }
        }
    }

    func selectRepository(_ repository: GitHubRepository?) {
        guard selectedRepository?.id != repository?.id else { return }
        selectedRepository = repository
        resetIssues()
        loadIssues()
    }

    func changeIssueState(_ state: GitHubIssueState) {
        guard issueState != state else { return }
        issueState = state
        resetIssues()
        loadIssues()
    }

    func loadIssues(force: Bool = false) {
        guard let repository = selectedRepository,
              force || (!isLoadingIssues && issuePage == 0) else { return }
        issuesTask?.cancel()
        isLoadingIssues = true
        isLoadingMoreIssues = false
        issueError = nil
        let state = issueState
        let requestID = UUID()
        issuesRequestID = requestID
        let service = self.service
        issuesTask = Task {
            defer {
                if issuesRequestID == requestID {
                    isLoadingIssues = false
                    isLoadingMoreIssues = false
                    issuesTask = nil
                    issuesRequestID = nil
                }
            }
            do {
                let values = try await service.issues(for: repository, state: state, page: 1)
                guard !Task.isCancelled,
                      selectedRepository?.id == repository.id,
                      issueState == state else { return }
                issues = values
                issuePage = 1
                canLoadMoreIssues = values.count == 50
                if let selectedIssue,
                   let updated = values.first(where: { $0.id == selectedIssue.id }) {
                    self.selectedIssue = updated
                } else {
                    selectIssue(values.first)
                }
            } catch is CancellationError {
                return
            } catch {
                guard selectedRepository?.id == repository.id else { return }
                issueError = error.localizedDescription
            }
        }
    }

    func loadMoreIssues() {
        guard let repository = selectedRepository,
              canLoadMoreIssues,
              !isLoadingIssues,
              !isLoadingMoreIssues else { return }
        let nextPage = issuePage + 1
        let state = issueState
        isLoadingMoreIssues = true
        issueError = nil
        let requestID = UUID()
        issuesRequestID = requestID
        let service = self.service
        issuesTask = Task {
            defer {
                if issuesRequestID == requestID {
                    isLoadingMoreIssues = false
                    issuesTask = nil
                    issuesRequestID = nil
                }
            }
            do {
                let values = try await service.issues(for: repository, state: state, page: nextPage)
                guard !Task.isCancelled,
                      selectedRepository?.id == repository.id,
                      issueState == state else { return }
                var known = Set(issues.map(\.id))
                issues.append(contentsOf: values.filter { known.insert($0.id).inserted })
                issuePage = nextPage
                canLoadMoreIssues = values.count == 50
            } catch is CancellationError {
                return
            } catch {
                guard selectedRepository?.id == repository.id else { return }
                issueError = error.localizedDescription
            }
        }
    }

    func selectIssue(_ issue: GitHubIssue?) {
        commentsTask?.cancel()
        cancelIssueReplyDraft()
        selectedIssue = issue
        issueComments = []
        issueReplyDraft = ""
        issueReplyError = nil
        issueReplyCompletionID = nil
        isLoadingIssueComments = false
        guard let issue, let repository = selectedRepository else { return }
        isLoadingIssueComments = true
        issueError = nil
        let requestID = UUID()
        commentsRequestID = requestID
        let service = self.service
        commentsTask = Task {
            defer {
                if commentsRequestID == requestID {
                    isLoadingIssueComments = false
                    commentsTask = nil
                    commentsRequestID = nil
                }
            }
            do {
                let values = try await service.issueComments(for: issue, in: repository)
                guard !Task.isCancelled,
                      selectedRepository?.id == repository.id,
                      selectedIssue?.id == issue.id else { return }
                issueComments = values
            } catch is CancellationError {
                return
            } catch {
                guard selectedIssue?.id == issue.id else { return }
                issueError = error.localizedDescription
            }
        }
    }

    func createIssue(_ draft: GitHubIssueDraft) async -> Bool {
        guard let repository = selectedRepository,
              !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isSavingIssue else { return false }
        isSavingIssue = true
        issueError = nil
        do {
            let created = try await service.createIssue(draft, in: repository)
            if issueState == .open || issueState == .all {
                issues.insert(created, at: 0)
            }
            selectIssue(created)
            isSavingIssue = false
            return true
        } catch {
            issueError = error.localizedDescription
            isSavingIssue = false
            return false
        }
    }

    func updateIssue(_ issue: GitHubIssue, draft: GitHubIssueDraft, state: GitHubIssueState) async -> Bool {
        guard let repository = selectedRepository, !isSavingIssue else { return false }
        isSavingIssue = true
        issueError = nil
        do {
            let updated = try await service.updateIssue(issue, draft: draft, state: state, in: repository)
            if let index = issues.firstIndex(where: { $0.id == issue.id }) {
                if issueState == .all || issueState == updated.state {
                    issues[index] = updated
                } else {
                    issues.remove(at: index)
                }
            }
            selectedIssue = updated
            isSavingIssue = false
            return true
        } catch {
            issueError = error.localizedDescription
            isSavingIssue = false
            return false
        }
    }

    func addComment(_ body: String) async -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let repository = selectedRepository,
              let issue = selectedIssue,
              !trimmed.isEmpty,
              !isSavingIssue else { return false }
        isSavingIssue = true
        issueError = nil
        do {
            let comment = try await service.addIssueComment(trimmed, to: issue, in: repository)
            issueComments.append(comment)
            isSavingIssue = false
            return true
        } catch {
            issueError = error.localizedDescription
            isSavingIssue = false
            return false
        }
    }

    var canDraftIssueReply: Bool {
        selectedRepository != nil
            && selectedIssue != nil
            && !isLoadingIssueComments
            && !isSavingIssue
            && !isDraftingIssueReply
    }

    func draftIssueReply() {
        guard let repository = selectedRepository,
              let issue = selectedIssue,
              canDraftIssueReply else { return }
        let context = GitHubIssueReplyContext(
            repositoryName: repository.fullName,
            issue: issue,
            comments: issueComments
        )
        issueReplyTask?.cancel()
        issueReplyError = nil
        issueReplyCompletionID = nil
        isDraftingIssueReply = true
        let replyService = self.replyService
        issueReplyTask = Task {
            defer {
                if selectedRepository?.id == repository.id, selectedIssue?.id == issue.id {
                    isDraftingIssueReply = false
                    issueReplyTask = nil
                }
            }
            do {
                let draft = try await replyService.draftIssueReply(context: context)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !Task.isCancelled,
                      selectedRepository?.id == repository.id,
                      selectedIssue?.id == issue.id else { return }
                guard !draft.isEmpty else { throw CodexServiceError.missingResponse }
                issueReplyDraft = draft
                issueReplyCompletionID = UUID()
            } catch is CancellationError {
                return
            } catch {
                guard selectedIssue?.id == issue.id else { return }
                issueReplyError = L10n.format("github.issues.comment.agent_error", error.localizedDescription)
            }
        }
    }

    func cancelIssueReplyDraft() {
        guard isDraftingIssueReply || issueReplyTask != nil else { return }
        issueReplyTask?.cancel()
        issueReplyTask = nil
        isDraftingIssueReply = false
    }

    func publishIssueReply() async -> Bool {
        let didPublish = await addComment(issueReplyDraft)
        if didPublish {
            issueReplyDraft = ""
            issueReplyError = nil
            issueReplyCompletionID = nil
        }
        return didPublish
    }

    private func resetIssues() {
        issuesRequestID = nil
        commentsRequestID = nil
        issuesTask?.cancel()
        commentsTask?.cancel()
        cancelIssueReplyDraft()
        issuePage = 0
        issues = []
        selectedIssue = nil
        issueComments = []
        canLoadMoreIssues = false
        isLoadingIssues = false
        isLoadingMoreIssues = false
        isLoadingIssueComments = false
        issueError = nil
        issueReplyDraft = ""
        issueReplyError = nil
        issueReplyCompletionID = nil
    }
}
