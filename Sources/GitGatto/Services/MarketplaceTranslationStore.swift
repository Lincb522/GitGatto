import Foundation

struct MarketplaceTranslationDocument: Codable, Equatable, Sendable {
    let repositoryDescription: String?
    let releaseNotes: String?
    let detailParagraphs: [String]?
    let detailFeatures: [String]?

    init(
        repositoryDescription: String?,
        releaseNotes: String?,
        detailParagraphs: [String]? = nil,
        detailFeatures: [String]? = nil
    ) {
        self.repositoryDescription = repositoryDescription
        self.releaseNotes = releaseNotes
        self.detailParagraphs = detailParagraphs
        self.detailFeatures = detailFeatures
    }
}

protocol MarketplaceTranslationStoring: Sendable {
    func load(
        repositoryName: String,
        releaseID: Int64,
        sourceDescription: String?,
        sourceReleaseNotes: String?,
        sourceDetails: String?,
        target: CodexTranslationTarget
    ) async throws -> MarketplaceTranslationDocument?

    func save(
        _ document: MarketplaceTranslationDocument,
        repositoryName: String,
        releaseID: Int64,
        sourceDescription: String?,
        sourceReleaseNotes: String?,
        sourceDetails: String?,
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
        sourceDetails: String?,
        target: CodexTranslationTarget
    ) async throws -> MarketplaceTranslationDocument? {
        let url = fileURL(
            repositoryName: repositoryName,
            releaseID: releaseID,
            sourceDescription: sourceDescription,
            sourceReleaseNotes: sourceReleaseNotes,
            sourceDetails: sourceDetails,
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
        sourceDetails: String?,
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
                sourceDetails: sourceDetails,
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
        sourceDetails: String?,
        target: CodexTranslationTarget
    ) -> URL {
        var source = [
            repositoryName,
            String(releaseID),
            target.rawValue,
            sourceDescription ?? "",
            sourceReleaseNotes ?? "",
        ]
        if let sourceDetails {
            source.append(sourceDetails)
        }
        let key = StableHash.hex(source.joined(separator: "\u{0}"))
        return directoryURL.appendingPathComponent("\(key).json")
    }
}
