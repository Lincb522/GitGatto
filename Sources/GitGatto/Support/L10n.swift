import Foundation

enum L10n {
    private static let runtime = LocalizationRuntime(
        resourceBundle: AppResourceBundle.current,
        language: AppPreferencesStore.load().language
    )

    static func activate(_ language: AppLanguage) {
        runtime.activate(language)
    }

    static var locale: Locale {
        runtime.locale
    }

    static var preferredLanguages: [String] {
        runtime.preferredLanguages
    }

    static func text(_ key: String) -> String {
        runtime.text(key)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    static func legalDocumentURL(
        named name: String,
        preferredLanguages: [String] = L10n.preferredLanguages
    ) -> URL? {
        localizedDocumentURL(named: name, preferredLanguages: preferredLanguages)
    }

    static func localizedDocumentURL(
        named name: String,
        preferredLanguages: [String] = L10n.preferredLanguages
    ) -> URL? {
        let language = preferredLanguages
            .first { $0.lowercased().hasPrefix("zh") } == nil ? "en" : "zh-Hans"
        return AppResourceBundle.current.url(
            forResource: name,
            withExtension: "md",
            subdirectory: nil,
            localization: language
        )
    }

    static func bundle(preferredLanguages: [String]) -> Bundle {
        resolvedBundle(
            resourceBundle: AppResourceBundle.current,
            preferredLanguages: preferredLanguages
        )
    }

    private static func resolvedBundle(
        resourceBundle: Bundle,
        preferredLanguages: [String]
    ) -> Bundle {
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

    private final class LocalizationRuntime: @unchecked Sendable {
        private let lock = NSLock()
        private let resourceBundle: Bundle
        private let englishBundle: Bundle
        private var language: AppLanguage
        private var localizedBundle: Bundle

        init(resourceBundle: Bundle, language: AppLanguage) {
            self.resourceBundle = resourceBundle
            self.language = language
            localizedBundle = L10n.resolvedBundle(
                resourceBundle: resourceBundle,
                preferredLanguages: language.preferredLanguages
            )
            englishBundle = L10n.resolvedBundle(
                resourceBundle: resourceBundle,
                preferredLanguages: ["en"]
            )
        }

        func activate(_ language: AppLanguage) {
            lock.lock()
            defer { lock.unlock() }
            guard self.language != language else { return }
            self.language = language
            localizedBundle = L10n.resolvedBundle(
                resourceBundle: resourceBundle,
                preferredLanguages: language.preferredLanguages
            )
        }

        var locale: Locale {
            lock.lock()
            defer { lock.unlock() }
            return language.locale
        }

        var preferredLanguages: [String] {
            lock.lock()
            defer { lock.unlock() }
            return language.preferredLanguages
        }

        func text(_ key: String) -> String {
            lock.lock()
            defer { lock.unlock() }
            let localized = localizedBundle.localizedString(forKey: key, value: nil, table: nil)
            if localized != key { return localized }
            return englishBundle.localizedString(forKey: key, value: key, table: nil)
        }
    }
}
