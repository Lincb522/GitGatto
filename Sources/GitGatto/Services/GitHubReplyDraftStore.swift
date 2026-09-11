import Foundation

@MainActor
final class GitHubReplyDraftStore {
    static let shared = GitHubReplyDraftStore()
    enum Kind: String { case issue, reply, review }
    struct Key: Equatable {
        let repository: String
        let number: Int
        let kind: Kind
        var storageKey: String { "\(repository.lowercased())#\(number)/\(kind.rawValue)" }
    }

    private let defaults: UserDefaults
    private let storageKey = "github.replyDrafts"
    private var drafts: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        drafts = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }

    func text(for key: Key?) -> String {
        key.flatMap { drafts[$0.storageKey] } ?? ""
    }

    func save(_ text: String, for key: Key?) {
        guard let key else { return }
        if text.isEmpty { drafts.removeValue(forKey: key.storageKey) }
        else { drafts[key.storageKey] = text }
        defaults.set(drafts, forKey: storageKey)
    }

    // A completed request must not discard edits made while it was in flight.
    func remove(_ key: Key?, matching submitted: String) {
        guard let key, text(for: key) == submitted else { return }
        save("", for: key)
    }
}
