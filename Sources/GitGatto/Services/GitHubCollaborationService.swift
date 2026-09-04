import Foundation

extension GitHubService {
    func inbox() async throws -> [GitHubInboxItem] {
        var loadedItems: [GitHubInboxItem] = []
        var firstError: Error?

        do {
            let data = try await api([
                "graphql",
                "-f", "query=\(Self.inboxQuery)",
                "-f", "searchQuery=is:pr is:open involves:@me sort:updated-desc"
            ])
            loadedItems.append(contentsOf: try GitHubCollaborationParser.inboxPullRequests(from: data))
        } catch {
            firstError = error
        }

        do {
            let data = try await api([
                "-X", "GET",
                "notifications?all=false&participating=true&per_page=100"
            ])
            loadedItems.append(contentsOf: try GitHubCollaborationParser.notifications(from: data))
        } catch {
            if firstError == nil { firstError = error }
        }

        if loadedItems.isEmpty, let firstError {
            throw firstError
        }
        var merged: [String: GitHubInboxItem] = [:]
        for item in loadedItems {
            if let existing = merged[item.id] {
                let preferred = existing.subjectKind == .other ? item : existing
                merged[item.id] = preferred.merging(categories: existing.categories.union(item.categories))
            } else {
                merged[item.id] = item
            }
        }
        return merged.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func issues(
        for repository: GitHubRepository,
        state: GitHubIssueState,
        page: Int
    ) async throws -> [GitHubIssue] {
        let response = try await api([
            "-X", "GET",
            "repos/\(repository.fullName)/issues",
            "-f", "state=\(state.rawValue)",
            "-f", "sort=updated",
            "-f", "direction=desc",
            "-f", "per_page=50",
            "-f", "page=\(max(1, page))"
        ])
        return try GitHubCollaborationParser.issues(from: response)
    }

    func issueComments(
        for issue: GitHubIssue,
        in repository: GitHubRepository
    ) async throws -> [GitHubIssueComment] {
        let response = try await api([
            "--paginate", "--slurp", "-X", "GET",
            "repos/\(repository.fullName)/issues/\(issue.number)/comments",
            "-f", "per_page=100"
        ])
        return try GitHubCollaborationParser.issueComments(from: response)
    }

    func createIssue(
        _ draft: GitHubIssueDraft,
        in repository: GitHubRepository
    ) async throws -> GitHubIssue {
        var arguments = [
            "-X", "POST",
            "repos/\(repository.fullName)/issues",
            "-f", "title=\(draft.title)",
            "-f", "body=\(draft.body)"
        ]
        append(values: draft.labels, field: "labels", to: &arguments, includesEmpty: false)
        append(values: draft.assignees, field: "assignees", to: &arguments, includesEmpty: false)
        if let milestone = draft.milestoneNumber {
            arguments.append(contentsOf: ["-F", "milestone=\(milestone)"])
        }
        return try GitHubCollaborationParser.issue(from: await api(arguments))
    }

    func updateIssue(
        _ issue: GitHubIssue,
        draft: GitHubIssueDraft,
        state: GitHubIssueState,
        in repository: GitHubRepository
    ) async throws -> GitHubIssue {
        var arguments = [
            "-X", "PATCH",
            "repos/\(repository.fullName)/issues/\(issue.number)",
            "-f", "title=\(draft.title)",
            "-f", "body=\(draft.body)",
            "-f", "state=\(state == .all ? issue.state.rawValue : state.rawValue)"
        ]
        append(values: draft.labels, field: "labels", to: &arguments, includesEmpty: true)
        append(values: draft.assignees, field: "assignees", to: &arguments, includesEmpty: true)
        arguments.append(contentsOf: [
            "-F", draft.milestoneNumber.map { "milestone=\($0)" } ?? "milestone=null"
        ])
        return try GitHubCollaborationParser.issue(from: await api(arguments))
    }

    func addIssueComment(
        _ body: String,
        to issue: GitHubIssue,
        in repository: GitHubRepository
    ) async throws -> GitHubIssueComment {
        let response = try await api([
            "-X", "POST",
            "repos/\(repository.fullName)/issues/\(issue.number)/comments",
            "-f", "body=\(body)"
        ])
        return try GitHubCollaborationParser.issueComment(from: response)
    }

    private func append(
        values: [String],
        field: String,
        to arguments: inout [String],
        includesEmpty: Bool
    ) {
        if values.isEmpty, includesEmpty {
            arguments.append(contentsOf: ["-f", "\(field)[]"])
        } else {
            for value in values where !value.isEmpty {
                arguments.append(contentsOf: ["-f", "\(field)[]=\(value)"])
            }
        }
    }

    private static let inboxQuery = """
    query($searchQuery:String!) {
      viewer { login }
      search(query:$searchQuery,type:ISSUE,first:50) {
        nodes {
          ... on PullRequest {
            id number title url updatedAt isDraft mergeable reviewDecision
            author { login }
            repository { nameWithOwner }
            reviewRequests(first:20) {
              nodes { requestedReviewer { ... on User { login } } }
            }
            commits(last:1) {
              nodes { commit { statusCheckRollup { state } } }
            }
          }
        }
      }
    }
    """
}

enum GitHubCollaborationParser {
    static func inboxPullRequests(from data: Data) throws -> [GitHubInboxItem] {
        let payload = try decode(InboxGraphQLPayload.self, from: data)
        let viewer = payload.data.viewer.login
        return payload.data.search.nodes.compactMap { node in
            guard let number = node.number,
                  let title = node.title,
                  let webURL = node.url,
                  let updatedAt = node.updatedAt,
                  let repositoryName = node.repository?.nameWithOwner else { return nil }
            var categories = Set<GitHubInboxCategory>()
            if node.author?.login.caseInsensitiveCompare(viewer) == .orderedSame {
                categories.insert(.authored)
            }
            if node.reviewRequests?.nodes.contains(where: {
                $0.requestedReviewer?.login?.caseInsensitiveCompare(viewer) == .orderedSame
            }) == true {
                categories.insert(.reviewRequested)
            }
            if node.reviewDecision == "CHANGES_REQUESTED" { categories.insert(.changesRequested) }
            if node.mergeable == "CONFLICTING" { categories.insert(.conflicted) }
            if node.mergeable == "MERGEABLE", node.reviewDecision == "APPROVED" {
                categories.insert(.mergeable)
            }
            let checkState = node.commits?.nodes.last?.commit.statusCheckRollup?.state
            if checkState == "FAILURE" || checkState == "ERROR" {
                categories.insert(.actionsFailed)
            }
            if categories.isEmpty { categories.insert(.mentioned) }
            return GitHubInboxItem(
                id: "pullRequest:\(repositoryName):\(number)",
                repositoryName: repositoryName,
                number: number,
                title: title,
                author: node.author?.login,
                webURL: webURL,
                updatedAt: updatedAt,
                subjectKind: .pullRequest,
                categories: categories,
                isDraft: node.isDraft ?? false
            )
        }
    }

    static func notifications(from data: Data) throws -> [GitHubInboxItem] {
        try decode([NotificationPayload].self, from: data).compactMap(\.model)
    }

    static func issues(from data: Data) throws -> [GitHubIssue] {
        try decode([IssuePayload].self, from: data).filter { $0.pullRequest == nil }.map(\.model)
    }

    static func issue(from data: Data) throws -> GitHubIssue {
        let payload = try decode(IssuePayload.self, from: data)
        guard payload.pullRequest == nil else { throw GitHubServiceError.invalidResponse }
        return payload.model
    }

    static func issueComments(from data: Data) throws -> [GitHubIssueComment] {
        if let pages = try? decode([[IssueCommentPayload]].self, from: data) {
            return pages.flatMap { $0 }.map(\.model)
        }
        return try decode([IssueCommentPayload].self, from: data).map(\.model)
    }

    static func issueComment(from data: Data) throws -> GitHubIssueComment {
        try decode(IssueCommentPayload.self, from: data).model
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw GitHubServiceError.invalidResponse
        }
    }
}

private struct InboxGraphQLPayload: Decodable {
    struct DataPayload: Decodable {
        struct Viewer: Decodable { let login: String }
        struct Search: Decodable { let nodes: [PullRequestNode] }
        let viewer: Viewer
        let search: Search
    }
    let data: DataPayload
}

private struct PullRequestNode: Decodable {
    struct User: Decodable { let login: String }
    struct Repository: Decodable { let nameWithOwner: String }
    struct ReviewRequests: Decodable {
        struct Reviewer: Decodable { let login: String? }
        struct Node: Decodable { let requestedReviewer: Reviewer? }
        let nodes: [Node]
    }
    struct Commits: Decodable {
        struct Node: Decodable {
            struct Commit: Decodable {
                struct StatusCheckRollup: Decodable { let state: String }
                let statusCheckRollup: StatusCheckRollup?
            }
            let commit: Commit
        }
        let nodes: [Node]
    }
    let number: Int?
    let title: String?
    let url: URL?
    let updatedAt: Date?
    let isDraft: Bool?
    let mergeable: String?
    let reviewDecision: String?
    let author: User?
    let repository: Repository?
    let reviewRequests: ReviewRequests?
    let commits: Commits?
}

private struct NotificationPayload: Decodable {
    struct Repository: Decodable {
        let fullName: String
        let htmlURL: URL
        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case htmlURL = "html_url"
        }
    }
    struct Subject: Decodable {
        let title: String
        let url: URL?
        let latestCommentURL: URL?
        let type: String
        enum CodingKeys: String, CodingKey {
            case title, url, type
            case latestCommentURL = "latest_comment_url"
        }
    }
    let id: String
    let reason: String
    let updatedAt: Date
    let subject: Subject
    let repository: Repository

    enum CodingKeys: String, CodingKey {
        case id, reason, subject, repository
        case updatedAt = "updated_at"
    }

    var model: GitHubInboxItem? {
        let kind: GitHubInboxSubjectKind
        switch subject.type {
        case "PullRequest": kind = .pullRequest
        case "Issue": kind = .issue
        case "WorkflowRun", "CheckSuite": kind = .action
        case "Release": kind = .release
        case "Discussion": kind = .discussion
        default: kind = .other
        }
        let number = subject.url.flatMap { Int($0.lastPathComponent) }
        let webURL: URL
        switch kind {
        case .pullRequest:
            guard let number else { return nil }
            webURL = repository.htmlURL
                .appendingPathComponent("pull", isDirectory: true)
                .appendingPathComponent(String(number))
        case .issue:
            guard let number else { return nil }
            webURL = repository.htmlURL
                .appendingPathComponent("issues", isDirectory: true)
                .appendingPathComponent(String(number))
        case .action:
            webURL = repository.htmlURL.appendingPathComponent("actions")
        case .release:
            webURL = repository.htmlURL.appendingPathComponent("releases")
        default:
            webURL = repository.htmlURL
        }
        var categories = Set<GitHubInboxCategory>()
        switch reason {
        case "review_requested": categories.insert(.reviewRequested)
        case "author": categories.insert(.authored)
        case "mention", "team_mention", "comment", "subscribed": categories.insert(.mentioned)
        case "ci_activity": categories.insert(.actionsFailed)
        default: break
        }
        if kind == .release { categories.insert(.release) }
        if categories.isEmpty { categories.insert(.mentioned) }
        let stableID = number.map { "\(kind.rawValue):\(repository.fullName):\($0)" }
            ?? "notification:\(id)"
        return GitHubInboxItem(
            id: stableID,
            repositoryName: repository.fullName,
            number: number,
            title: subject.title,
            author: nil,
            webURL: webURL,
            updatedAt: updatedAt,
            subjectKind: kind,
            categories: categories,
            isDraft: false
        )
    }
}

private struct IssuePayload: Decodable {
    struct User: Decodable { let login: String }
    struct Label: Decodable { let name: String; let color: String }
    struct Milestone: Decodable { let number: Int; let title: String }
    struct PullRequestMarker: Decodable {}

    let number: Int
    let title: String
    let body: String?
    let user: User
    let state: String
    let htmlURL: URL
    let labels: [Label]
    let assignees: [User]
    let milestone: Milestone?
    let comments: Int
    let createdAt: Date
    let updatedAt: Date
    let pullRequest: PullRequestMarker?

    enum CodingKeys: String, CodingKey {
        case number, title, body, user, state, labels, assignees, milestone, comments
        case htmlURL = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case pullRequest = "pull_request"
    }

    var model: GitHubIssue {
        GitHubIssue(
            number: number,
            title: title,
            body: body,
            author: user.login,
            state: GitHubIssueState(rawValue: state) ?? .open,
            webURL: htmlURL,
            labels: labels.map { GitHubIssueLabel(name: $0.name, colorHex: $0.color) },
            assignees: assignees.map(\.login),
            milestone: milestone.map { GitHubIssueMilestone(number: $0.number, title: $0.title) },
            commentCount: comments,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct IssueCommentPayload: Decodable {
    struct User: Decodable { let login: String }
    let id: Int64
    let user: User
    let body: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, user, body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var model: GitHubIssueComment {
        GitHubIssueComment(
            id: id,
            author: user.login,
            body: body,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
