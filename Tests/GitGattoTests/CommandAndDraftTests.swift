import Foundation
import Testing
@testable import GitGatto

@Suite("Persistent navigation and collaboration drafts")
@MainActor
struct CommandAndDraftTests {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let name = "GitGatto.tests.commands.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func commandOrderingSurvivesReopeningAndFiltersUnavailableActions() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = CommandUsageStore(defaults: defaults)
        store.record("history")
        store.record("changes")
        store.record("history")
        store.togglePin("settings")
        store.togglePin("missing")
        let reopened = CommandUsageStore(defaults: defaults)
        #expect(reopened.orderedIDs(["changes", "settings", "history", "new"]) == ["settings", "history", "changes", "new"])
        reopened.togglePin("settings")
        #expect(reopened.orderedIDs(["changes", "settings", "history"]) == ["history", "changes", "settings"])
        for index in 0..<30 { reopened.record(String(index)) }
        #expect(reopened.recent.count == 20)
    }

    @Test func localizedAliasesSupportTokenAndAccentSearch() {
        #expect(CommandSearchIndex.matches("恢复 文件", text: ["找回文件 恢复误删"]))
        #expect(CommandSearchIndex.matches("RESTAURER DEPOT", text: ["Restaurer le dépôt"]))
        #expect(!CommandSearchIndex.matches("恢复 分支", text: ["找回文件 恢复误删"]))
    }

    @Test func draftsAreScopedAndDoNotLoseNewEditsAfterSending() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = GitHubReplyDraftStore(defaults: defaults)
        let reply = GitHubReplyDraftStore.Key(repository: "owner/repo", number: 1, kind: .reply)
        let review = GitHubReplyDraftStore.Key(repository: "owner/repo", number: 1, kind: .review)
        let other = GitHubReplyDraftStore.Key(repository: "owner/other", number: 1, kind: .reply)
        store.save("Reply", for: reply)
        store.save("Review", for: review)
        store.save("Other", for: other)
        let reopened = GitHubReplyDraftStore(defaults: defaults)
        #expect(reopened.text(for: reply) == "Reply")
        #expect(reopened.text(for: review) == "Review")
        reopened.save("New reply", for: reply)
        reopened.remove(reply, matching: "Reply")
        #expect(reopened.text(for: reply) == "New reply")
        reopened.remove(reply, matching: "New reply")
        #expect(reopened.text(for: reply).isEmpty)
        #expect(reopened.text(for: other) == "Other")
        #expect(reopened.text(for: review) == "Review")
        reopened.save("Unbound", for: nil)
        #expect(reopened.text(for: nil).isEmpty)
    }
    @Test func sendingIssueDraftKeepsEditsAndRestoresAfterSwitching() async throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = GitHubReplyDraftStore(defaults: defaults)
        let service = try GitHubAgentReplyGitHubFixture()
        let model = GitHubCollaborationViewModel(service: service, draftStore: store)
        model.selectedRepository = service.repository
        model.selectIssue(service.issue)
        model.issueReplyDraft = "Send this"
        await service.holdPublication()
        let task = Task { await model.publishIssueReply() }
        let deadline = ContinuousClock.now + .seconds(8)
        while await service.publishedBodies.isEmpty, ContinuousClock.now < deadline { await Task.yield() }
        #expect(await service.publishedBodies == ["Send this"])
        model.issueReplyDraft = "Next edit"
        model.selectIssue(nil)
        await service.finishPublication()
        #expect(await task.value)
        #expect(model.issueReplyDraft.isEmpty)
        model.selectIssue(service.issue)
        #expect(model.issueReplyDraft == "Next edit")
        let reopened = GitHubCollaborationViewModel(service: service, draftStore: GitHubReplyDraftStore(defaults: defaults))
        reopened.selectedRepository = service.repository
        reopened.selectIssue(service.issue)
        #expect(reopened.issueReplyDraft == "Next edit")
    }

    @Test func pullRequestAndReviewDraftsRestoreThroughSelection() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let previous = UserDefaults.standard.object(forKey: "app.preferences")
        var preferences = AppPreferences(); preferences.monitoringEngineEnabled = false
        AppPreferencesStore.save(preferences)
        defer { UserDefaults.standard.set(previous, forKey: "app.preferences") }
        let service = try GitHubAgentReplyGitHubFixture()
        let store = GitHubReplyDraftStore(defaults: defaults)
        let model = WorkspaceViewModel(replyDraftStore: store, githubService: service)
        model.selectedGitHubRepository = service.repository
        let first = GitHubPullRequest(number: 1, title: "First", author: "Fixture", body: nil,
            webURL: service.repository.webURL, isDraft: false, headBranch: "feature", headSHA: "abc", baseBranch: "main", nodeID: "1", updatedAt: Date())
        let second = GitHubPullRequest(number: 2, title: "Second", author: "Fixture", body: nil,
            webURL: service.repository.webURL, isDraft: false, headBranch: "other", headSHA: "def", baseBranch: "main", nodeID: "2", updatedAt: Date())
        model.selectedGitHubPullRequest = first
        model.pullRequestReplyDraft = "First reply"
        model.pullRequestReviewDraft = "First review"
        model.selectedGitHubPullRequest = second
        #expect(model.pullRequestReplyDraft.isEmpty)
        #expect(model.pullRequestReviewDraft.isEmpty)
        model.pullRequestReplyDraft = "Second reply"
        model.selectedGitHubPullRequest = first
        #expect(model.pullRequestReplyDraft == "First reply")
        #expect(model.pullRequestReviewDraft == "First review")
        model.selectedGitHubRepository = nil
        model.selectedGitHubPullRequest = nil
        #expect(store.text(for: .init(repository: service.repository.fullName, number: 1, kind: .review)) == "First review")
    }

}
