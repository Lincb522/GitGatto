import Foundation
import Testing
@testable import GitGatto

@Suite("Persistent workspace stores")
struct PersistenceStoreTests {
    @Test("Loads current preferences from an older payload without automatic discovery")
    func loadsPreferencesFromOlderPayload() throws {
        let data = try #require("""
        {
          "language": "en",
          "defaultWorkspace": "changes",
          "autoDiscoverRepositories": true,
          "liveRefreshEnabled": false,
          "liveRefreshInterval": 2,
          "remoteRefreshEnabled": true,
          "remoteRefreshInterval": 60,
          "commitDraftDetail": "complete"
        }
        """.data(using: .utf8))

        let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)

        #expect(preferences.language == .english)
        #expect(preferences.defaultWorkspace == .changes)
        #expect(!preferences.liveRefreshEnabled)
        #expect(preferences.commitDraftDetail == .complete)
        #expect(preferences.reopenLastRepository)
        #expect(preferences.confirmDiscardChanges)
        #expect(preferences.defaultTranslationTarget == .simplifiedChinese)

        let encoded = try #require(String(data: JSONEncoder().encode(preferences), encoding: .utf8))
        #expect(!encoded.contains("autoDiscoverRepositories"))
    }

    @Test("Restores Codex conversation text and operation records per repository")
    func restoresCodexConversation() async throws {
        let root = temporaryDirectory("CodexConversation")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CodexConversationStore(directoryURL: root.appendingPathComponent("store"))
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        let messages = [
            CodexMessage(role: .user, text: "Review the staged changes"),
            CodexMessage(
                role: .assistant,
                text: "No blocking findings.",
                operation: CodexOperationRecord(
                    mode: .analyze,
                    commandCount: 2,
                    fileChangeCount: 0,
                    completedAt: Date(timeIntervalSince1970: 1_788_000_000),
                    events: [
                        CodexOperationEvent(kind: .command, summary: "git diff --cached")
                    ]
                )
            )
        ]

        try await store.save(messages, for: repository)
        let restored = try await store.load(for: repository)
        let unrelated = try await store.load(for: root.appendingPathComponent("other"))

        #expect(restored == messages)
        #expect(restored.last?.operation?.commandCount == 2)
        #expect(restored.last?.operation?.events.first?.summary == "git diff --cached")
        #expect(unrelated.isEmpty)
    }

    @Test("Reuses a README translation only for the unchanged source document")
    func restoresMatchingReadmeTranslation() async throws {
        let root = temporaryDirectory("ReadmeTranslation")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GitHubReadmeTranslationStore(directoryURL: root.appendingPathComponent("store"))
        let source = try readme(html: "<h1>Project</h1>")
        let translated = source.replacingHTML(with: "<h1>项目</h1>")

        try await store.save(
            translated,
            repositoryName: "octocat/Hello-World",
            source: source,
            target: .simplifiedChinese
        )

        let restored = try await store.load(
            repositoryName: "octocat/Hello-World",
            source: source,
            target: .simplifiedChinese
        )
        let stale = try await store.load(
            repositoryName: "octocat/Hello-World",
            source: try readme(html: "<h1>Changed</h1>"),
            target: .simplifiedChinese
        )

        #expect(restored?.html == "<h1>项目</h1>")
        #expect(stale == nil)
    }

    private func temporaryDirectory(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGatto\(name)Tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func readme(html: String) throws -> GitHubReadmeDocument {
        let linkURL = try #require(URL(string: "https://github.com/octocat/Hello-World/blob/main/"))
        let assetURL = try #require(URL(string: "https://raw.githubusercontent.com/octocat/Hello-World/main/"))
        return GitHubReadmeDocument(
            path: "README.md",
            html: html,
            linkBaseURL: linkURL,
            linkRootURL: linkURL,
            assetBaseURL: assetURL,
            assetRootURL: assetURL
        )
    }
}
