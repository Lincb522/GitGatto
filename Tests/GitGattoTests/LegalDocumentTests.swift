import Foundation
import Testing
@testable import GitGatto

@Suite("Legal documents")
struct LegalDocumentTests {
    @Test("Loads every bundled agreement in both supported languages")
    func loadsLocalizedDocuments() throws {
        for language in ["en", "zh-Hans"] {
            for document in LegalDocumentKind.allCases {
                let url = try #require(
                    L10n.legalDocumentURL(
                        named: document.fileName,
                        preferredLanguages: [language]
                    )
                )
                let contents = try String(contentsOf: url, encoding: .utf8)

                #expect(contents.hasPrefix("# "))
                #expect(contents.count > 200)
            }
        }
    }

    @Test("Every agreement label is localized")
    func localizesNavigationLabels() {
        for language in ["en", "zh-Hans"] {
            let bundle = L10n.bundle(preferredLanguages: [language])
            for document in LegalDocumentKind.allCases {
                let title = bundle.localizedString(forKey: document.titleKey, value: document.titleKey, table: nil)
                let summary = bundle.localizedString(forKey: document.summaryKey, value: document.summaryKey, table: nil)

                #expect(title != document.titleKey)
                #expect(summary != document.summaryKey)
            }
        }
    }
}
