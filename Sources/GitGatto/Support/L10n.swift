import Foundation

enum L10n {
    private static let resourceBundle: Bundle = {
        if let resources = Bundle.main.resourceURL,
           let bundle = Bundle(url: resources.appendingPathComponent("GitGatto_GitGatto.bundle")) {
            return bundle
        }
        return Bundle.module
    }()
    private static let localizedBundle = bundle(
        preferredLanguages: AppPreferencesStore.load().language.preferredLanguages
    )

    static func text(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }

    static func legalDocumentURL(
        named name: String,
        preferredLanguages: [String] = AppPreferencesStore.load().language.preferredLanguages
    ) -> URL? {
        let language = preferredLanguages
            .first { $0.lowercased().hasPrefix("zh") } == nil ? "en" : "zh-Hans"
        return resourceBundle.url(
            forResource: name,
            withExtension: "md",
            subdirectory: nil,
            localization: language
        )
    }

    static func bundle(preferredLanguages: [String]) -> Bundle {
        let available = resourceBundle.localizations
        let match = preferredLanguages.lazy.compactMap { language in
            let preferred = language.replacingOccurrences(of: "_", with: "-").lowercased()
            return available.first { localization in
                let candidate = localization.replacingOccurrences(of: "_", with: "-").lowercased()
                return candidate == preferred
                    || preferred.hasPrefix(candidate + "-")
                    || candidate.hasPrefix(preferred + "-")
            }
        }.first

        guard let match,
              let path = resourceBundle.path(forResource: match, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return resourceBundle
        }
        return bundle
    }
}
