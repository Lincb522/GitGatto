import Foundation

protocol RegressionInvestigationStoring: Sendable {
    func load() async throws -> [RegressionInvestigation]
    func save(_ investigations: [RegressionInvestigation]) async throws
}

actor RegressionInvestigationStore: RegressionInvestigationStoring {
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
                .appendingPathComponent("RegressionInvestigations", isDirectory: true)
                .appendingPathComponent("investigations.json")
        }
    }

    func load() async throws -> [RegressionInvestigation] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode([RegressionInvestigation].self, from: data)
    }

    func save(_ investigations: [RegressionInvestigation]) async throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(investigations).write(to: fileURL, options: .atomic)
    }
}
