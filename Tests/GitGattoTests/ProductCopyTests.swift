import Testing
@testable import GitGatto

@Suite("Product copy")
struct ProductCopyTests {
    @Test("Uses the official product slogan in both localizations")
    func usesOfficialProductSlogan() {
        let chinese = L10n.bundle(preferredLanguages: ["zh-Hans"])
        let english = L10n.bundle(preferredLanguages: ["en"])

        #expect(
            chinese.localizedString(forKey: "about.product", value: nil, table: nil)
                == "原生构建，由 Agent 驱动的 Git 管理工具。"
        )
        #expect(
            english.localizedString(forKey: "about.product", value: nil, table: nil)
                == "A native-built Git management tool, driven by Agent."
        )
    }
}
