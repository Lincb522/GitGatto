import Foundation
@testable import GitGatto
import Testing

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
        #expect(preferences.launchAnimationEnabled)
        #expect(preferences.windowCloseBehavior == .ask)
        #expect(preferences.confirmDiscardChanges)
        #expect(preferences.defaultTranslationTarget == .simplifiedChinese)
        #expect(preferences.repositoryBackupEnabled)
        #expect(preferences.repositoryBackupIntervalMinutes == 10)
        #expect(preferences.majorBackupFileThreshold == 20)
        #expect(preferences.majorBackupLineThreshold == 500)
        #expect(preferences.repositoryBackupRetentionCount == 3)
        #expect(preferences.repositoryBackupMaximumFileSizeMB == 50)
        #expect(preferences.repositoryBackupDirectoryPath == nil)
        #expect(preferences.agentEditProtectionEnabled)
        #expect(preferences.externalRepositoryProtectionEnabled)
        #expect(preferences.agentConversationHistoryLimit == 24)
        #expect(preferences.defaultAgentRunMode == .analyze)
        #expect(preferences.monitoringEngineEnabled)
        #expect(preferences.statusBarMonitoringEnabled)
        #expect(preferences.githubActionsMonitoringEnabled)
        #expect(preferences.projectGoalMonitoringEnabled)

        let encoded = try #require(String(data: JSONEncoder().encode(preferences), encoding: .utf8))
        #expect(!encoded.contains("autoDiscoverRepositories"))
    }

    @Test("Persists monitoring engine and menu bar preferences")
    func persistsMonitoringPreferences() throws {
        var preferences = AppPreferences()
        preferences.monitoringEngineEnabled = false
        preferences.statusBarMonitoringEnabled = false
        preferences.githubActionsMonitoringEnabled = false
        preferences.projectGoalMonitoringEnabled = false

        let data = try JSONEncoder().encode(preferences)
        let restored = try JSONDecoder().decode(AppPreferences.self, from: data)

        #expect(!restored.monitoringEngineEnabled)
        #expect(!restored.statusBarMonitoringEnabled)
        #expect(!restored.githubActionsMonitoringEnabled)
        #expect(!restored.projectGoalMonitoringEnabled)
    }

    @Test("Persists the selected main-window close behavior")
    func persistsWindowCloseBehavior() throws {
        var preferences = AppPreferences()
        preferences.windowCloseBehavior = .quit

        let data = try JSONEncoder().encode(preferences)
        let restored = try JSONDecoder().decode(AppPreferences.self, from: data)

        #expect(restored.windowCloseBehavior == .quit)
    }

    @Test("Persists backup storage and Agent context settings")
    func persistsRecoveryAndAgentSettings() throws {
        var preferences = AppPreferences()
        preferences.repositoryBackupDirectoryPath = "/Volumes/Backups/GitGatto Recovery"
        preferences.repositoryBackupRetentionCount = 99
        preferences.agentEditProtectionEnabled = false
        preferences.externalRepositoryProtectionEnabled = false
        preferences.agentConversationHistoryLimit = 40
        preferences.defaultAgentRunMode = .edit

        let data = try JSONEncoder().encode(preferences)
        let restored = try JSONDecoder().decode(AppPreferences.self, from: data)

        #expect(restored.repositoryBackupDirectoryURL?.path == "/Volumes/Backups/GitGatto Recovery")
        #expect(restored.repositoryBackupRetentionCount == 3)
        #expect(!restored.agentEditProtectionEnabled)
        #expect(!restored.externalRepositoryProtectionEnabled)
        #expect(restored.agentConversationHistoryLimit == 40)
        #expect(restored.defaultAgentRunMode == .edit)
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
                        CodexOperationEvent(kind: .command, summary: "git diff --cached"),
                    ]
                )
            ),
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
            source: readme(html: "<h1>Changed</h1>"),
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
