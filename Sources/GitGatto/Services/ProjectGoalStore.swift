import Foundation

protocol ProjectGoalStoring: Sendable {
    func load() async throws -> [ProjectGoal]
    func save(_ goals: [ProjectGoal]) async throws
}

actor ProjectGoalStore: ProjectGoalStoring {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = support
                .appendingPathComponent("GitGatto", isDirectory: true)
                .appendingPathComponent("Goals", isDirectory: true)
                .appendingPathComponent("goals.json")
        }
    }

    func load() async throws -> [ProjectGoal] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode([ProjectGoal].self, from: data)
    }

    func save(_ goals: [ProjectGoal]) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(goals)
        try data.write(to: fileURL, options: .atomic)
    }
}
