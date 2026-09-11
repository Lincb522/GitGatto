import Foundation

struct DevelopmentToolTaskRecord: Codable, Identifiable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case queued, running, interrupted, completed, needsAction, failed, cancelled
    }
    let id: UUID
    let toolID: String
    let operation: DevelopmentToolOperation
    let createdAt: Date
    var updatedAt: Date
    var state: State
    var version: String?
    var executablePath: String?
    var receipt: DevelopmentToolReceipt? = nil

    var needsReview: Bool { [.queued, .running, .interrupted].contains(state) }
}

@MainActor
protocol DevelopmentToolTaskStoring {
    func load() throws -> [DevelopmentToolTaskRecord]
    func save(_ records: [DevelopmentToolTaskRecord]) throws
}

@MainActor
struct DevelopmentToolTaskStore: DevelopmentToolTaskStoring {
    let url: URL

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GitGatto/DevelopmentToolTasks.json")
    }

    func load() throws -> [DevelopmentToolTaskRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 2_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        let records = try JSONDecoder().decode([DevelopmentToolTaskRecord].self, from: Data(contentsOf: url))
        guard records.count <= 1_000, Set(records.map(\.id)).count == records.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return records
    }

    func save(_ records: [DevelopmentToolTaskRecord]) throws {
        let pending = records.filter(\.needsReview)
        let history = records.filter { !$0.needsReview }.suffix(200)
        let data = try JSONEncoder().encode(pending + history)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}


enum DevelopmentToolTaskError: LocalizedError {
    case updateNotVerified
    var errorDescription: String? { L10n.text("developer_tools.upgrade.verification_pending") }
}
