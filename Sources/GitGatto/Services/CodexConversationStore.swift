import Foundation

protocol CodexConversationStoring: Sendable {
    func load(for repositoryURL: URL) async throws -> [CodexMessage]
    func save(_ messages: [CodexMessage], for repositoryURL: URL) async throws
}

actor CodexConversationStore: CodexConversationStoring {
    private let directoryURL: URL

    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("GitGatto", isDirectory: true)
            .appendingPathComponent("Codex Conversations", isDirectory: true)
    }

    func load(for repositoryURL: URL) async throws -> [CodexMessage] {
        let fileURL = fileURL(for: repositoryURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([CodexMessage].self, from: Data(contentsOf: fileURL))
    }

    func save(_ messages: [CodexMessage], for repositoryURL: URL) async throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(messages)
        try data.write(to: fileURL(for: repositoryURL), options: .atomic)
    }

    private func fileURL(for repositoryURL: URL) -> URL {
        let key = StableHash.hex(repositoryURL.standardizedFileURL.path)
        return directoryURL.appendingPathComponent("\(key).json")
    }
}
