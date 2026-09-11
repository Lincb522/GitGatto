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
        #expect(L10n.text("settings.save") == "Save")

        L10n.activate(.simplifiedChinese)
        #expect(L10n.text("settings.save") == "保存")

        L10n.activate(.english)
        #expect(L10n.text("settings.save") == "Save")
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

    @Test("Translated format strings preserve every argument type")
    func preservesFormatArguments() throws {
        let english = L10n.bundle(preferredLanguages: ["en"])
        let url = try #require(english.url(forResource: "Localizable", withExtension: "strings"))
        let reference = try #require(NSDictionary(contentsOf: url) as? [String: String])
        let regex = try NSRegularExpression(pattern: #"%(?!%)(?:\d+\$)?(?:\d+)?(?:\.\d+)?(?:ll|l)?[@diufsg]"#)
        let position = try NSRegularExpression(pattern: #"^%\d+\$"#)
        func arguments(_ value: String) -> [String] {
            let value = value.replacingOccurrences(of: "%%", with: "")
            return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
                guard let range = Range(match.range, in: value) else { return nil }
                let token = String(value[range])
                return position.stringByReplacingMatches(in: token, range: NSRange(token.startIndex..., in: token), withTemplate: "%")
            }.sorted()
        }
        for language in AppLanguage.allCases where language != .system {
            let bundle = L10n.bundle(preferredLanguages: language.preferredLanguages)
            for (key, value) in reference {
                let translated = bundle.localizedString(forKey: key, value: nil, table: nil)
                #expect(arguments(translated) == arguments(value), "\(language.rawValue): \(key)")
            }
        }
    }

    @Test("Uses right-to-left layout for Arabic")
    func usesArabicLayoutDirection() {
        #expect(AppLanguage.arabic.usesRightToLeftLayout)
        #expect(!AppLanguage.english.usesRightToLeftLayout)
    }

    @Test("Command search prompts and keyboard actions use the selected language")
    func commandPromptsAreLocalized() {
        let english = L10n.bundle(preferredLanguages: ["en"])
        for language in AppLanguage.allCases where language != .system && language != .english {
            let bundle = L10n.bundle(preferredLanguages: language.preferredLanguages)
            for key in ["command_palette.placeholder", "command_palette.empty", "command_palette.hint.run"] {
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                #expect(value != key)
                #expect(value != english.localizedString(forKey: key, value: nil, table: nil), "\(language.rawValue): \(key)")
            }
        }
    }

    private func localizationKeys(in bundle: Bundle) -> Set<String> {
        guard let url = bundle.url(forResource: "Localizable", withExtension: "strings"),
              let dictionary = NSDictionary(contentsOf: url) as? [String: String] else {
            return []
        }
        return Set(dictionary.keys)
    }
}
