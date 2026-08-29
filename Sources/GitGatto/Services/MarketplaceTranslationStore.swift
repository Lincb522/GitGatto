import Foundation

struct MarketplaceTranslationDocument: Codable, Equatable, Sendable {
    let repositoryDescription: String?
    let releaseNotes: String?
}

protocol MarketplaceTranslationStoring: Sendable {
    func load(
        repositoryName: String,
        releaseID: Int64,
        sourceDescription: String?,
        sourceReleaseNotes: String?,
        target: CodexTranslationTarget
    ) async throws -> MarketplaceTranslationDocument?

    func save(
        _ document: MarketplaceTranslationDocument,
        repositoryName: String,
        releaseID: Int64,
        sourceDescription: String?,
        sourceReleaseNotes: String?,
        target: CodexTranslationTarget
    ) async throws
}

actor MarketplaceTranslationStore: MarketplaceTranslationStoring {
    private let directoryURL: URL

    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("GitGatto", isDirectory: true)
            .appendingPathComponent("Marketplace Translations", isDirectory: true)
    }

    func load(
        repositoryName: String,
        releaseID: Int64,
        sourceDescription: String?,
        sourceReleaseNotes: String?,
        target: CodexTranslationTarget
    ) async throws -> MarketplaceTranslationDocument? {
        let url = fileURL(
            repositoryName: repositoryName,
            releaseID: releaseID,
            sourceDescription: sourceDescription,
            sourceReleaseNotes: sourceReleaseNotes,
            target: target
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(
            MarketplaceTranslationDocument.self,
            from: Data(contentsOf: url)
        )
    }

    func save(
        _ document: MarketplaceTranslationDocument,
        repositoryName: String,
        releaseID: Int64,
        sourceDescription: String?,
        sourceReleaseNotes: String?,
        target: CodexTranslationTarget
    ) async throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(document)
        try data.write(
            to: fileURL(
                repositoryName: repositoryName,
                releaseID: releaseID,
                sourceDescription: sourceDescription,
                sourceReleaseNotes: sourceReleaseNotes,
                target: target
            ),
            options: .atomic
        )
    }

    private func fileURL(
        repositoryName: String,
        releaseID: Int64,
        sourceDescription: String?,
        sourceReleaseNotes: String?,
        target: CodexTranslationTarget
    ) -> URL {
        let key = StableHash.hex(
            "\(repositoryName)\u{0}\(releaseID)\u{0}\(target.rawValue)\u{0}\(sourceDescription ?? "")\u{0}\(sourceReleaseNotes ?? "")"
        )
        return directoryURL.appendingPathComponent("\(key).json")
    }
}
