import Foundation
import Testing
@testable import GitGatto

@Suite("Marketplace translation cache")
struct MarketplaceTranslationStoreTests {
    @Test("Persists translations for an unchanged release")
    func persistsTranslation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoMarketplaceTranslationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MarketplaceTranslationStore(directoryURL: directory)
        let document = MarketplaceTranslationDocument(
            repositoryDescription: "Translated description",
            releaseNotes: "Translated notes",
            detailParagraphs: ["Translated detail"],
            detailFeatures: ["Translated feature"]
        )

        try await store.save(
            document,
            repositoryName: "owner/repository",
            releaseID: 42,
            sourceDescription: "Source description",
            sourceReleaseNotes: "Source notes",
            sourceDetails: "Source detail\u{1F}Source feature",
            target: .english
        )

        let loaded = try await store.load(
            repositoryName: "owner/repository",
            releaseID: 42,
            sourceDescription: "Source description",
            sourceReleaseNotes: "Source notes",
            sourceDetails: "Source detail\u{1F}Source feature",
            target: .english
        )
        #expect(loaded == document)
    }

    @Test("Does not reuse a translation after release notes change")
    func invalidatesChangedSource() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoMarketplaceTranslationInvalidationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MarketplaceTranslationStore(directoryURL: directory)
        let document = MarketplaceTranslationDocument(
            repositoryDescription: nil,
            releaseNotes: "Translated notes"
        )
        try await store.save(
            document,
            repositoryName: "owner/repository",
            releaseID: 42,
            sourceDescription: nil,
            sourceReleaseNotes: "Version one",
            sourceDetails: nil,
            target: .simplifiedChinese
        )

        let loaded = try await store.load(
            repositoryName: "owner/repository",
            releaseID: 42,
            sourceDescription: nil,
            sourceReleaseNotes: "Version two",
            sourceDetails: nil,
            target: .simplifiedChinese
        )
        #expect(loaded == nil)
    }

    @Test("Does not reuse a translation after detailed introduction changes")
    func invalidatesChangedDetails() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoMarketplaceDetailTranslationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MarketplaceTranslationStore(directoryURL: directory)
        let document = MarketplaceTranslationDocument(
            repositoryDescription: "Translated description",
            releaseNotes: nil,
            detailParagraphs: ["Translated detail"]
        )
        try await store.save(
            document,
            repositoryName: "owner/repository",
            releaseID: 42,
            sourceDescription: "Description",
            sourceReleaseNotes: nil,
            sourceDetails: "Detail one",
            target: .simplifiedChinese
        )

        let loaded = try await store.load(
            repositoryName: "owner/repository",
            releaseID: 42,
            sourceDescription: "Description",
            sourceReleaseNotes: nil,
            sourceDetails: "Detail two",
            target: .simplifiedChinese
        )
        #expect(loaded == nil)
    }
}
