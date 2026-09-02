import Foundation
import Testing
@testable import GitGatto

@Suite("Application localization", .serialized)
struct LocalizationRuntimeTests {
    @Test("Includes every shipped interface language")
    func includesShippedLanguages() {
        #expect(Set(AppLanguage.allCases) == [
            .system,
            .english,
            .simplifiedChinese,
            .traditionalChinese,
            .japanese,
            .korean,
            .french,
            .german,
            .spanish,
            .portugueseBrazil,
            .russian,
            .arabic
        ])
    }

    @Test("Switches localized strings in the running process")
    func switchesWithoutRestarting() {
        let original = AppPreferencesStore.load().language
        defer { L10n.activate(original) }

        L10n.activate(.english)
        #expect(L10n.text("settings.save") == "Save & Check")

        L10n.activate(.simplifiedChinese)
        #expect(L10n.text("settings.save") == "保存并检测")

        L10n.activate(.english)
        #expect(L10n.text("settings.save") == "Save & Check")
    }

    @Test("Maps the interface language to automatic document translation")
    func mapsAutomaticTranslationTargets() {
        #expect(AppLanguage.english.translationTarget == .english)
        #expect(AppLanguage.traditionalChinese.translationTarget == .traditionalChinese)
        #expect(AppLanguage.japanese.translationTarget == .japanese)
        #expect(AppLanguage.korean.translationTarget == .korean)
        #expect(AppLanguage.french.translationTarget == .french)
        #expect(AppLanguage.german.translationTarget == .german)
        #expect(AppLanguage.spanish.translationTarget == .spanish)
        #expect(AppLanguage.portugueseBrazil.translationTarget == .portuguese)
        #expect(AppLanguage.russian.translationTarget == .russian)
        #expect(AppLanguage.arabic.translationTarget == .arabic)
    }

    @Test("Packages a complete table for each interface language")
    func packagesEveryLocalization() {
        let english = L10n.bundle(preferredLanguages: ["en"])
        let referenceKeys = localizationKeys(in: english)

        for language in AppLanguage.allCases where language != .system {
            let bundle = L10n.bundle(preferredLanguages: language.preferredLanguages)
            #expect(localizationKeys(in: bundle) == referenceKeys)
            #expect(bundle.localizedString(forKey: "settings.save", value: nil, table: nil) != "settings.save")
        }
    }

    @Test("Uses right-to-left layout for Arabic")
    func usesArabicLayoutDirection() {
        #expect(AppLanguage.arabic.usesRightToLeftLayout)
        #expect(!AppLanguage.english.usesRightToLeftLayout)
    }

    private func localizationKeys(in bundle: Bundle) -> Set<String> {
        guard let url = bundle.url(forResource: "Localizable", withExtension: "strings"),
              let dictionary = NSDictionary(contentsOf: url) as? [String: String] else {
            return []
        }
        return Set(dictionary.keys)
    }
}
