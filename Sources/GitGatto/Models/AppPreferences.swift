import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case portugueseBrazil = "pt-BR"
    case russian = "ru"
    case arabic = "ar"

    var id: String { rawValue }

    var preferredLanguages: [String] {
        switch self {
        case .system: Locale.preferredLanguages
        case .english: ["en"]
        case .simplifiedChinese: ["zh-Hans"]
        case .traditionalChinese: ["zh-Hant"]
        case .japanese: ["ja"]
        case .korean: ["ko"]
        case .french: ["fr"]
        case .german: ["de"]
        case .spanish: ["es"]
        case .portugueseBrazil: ["pt-BR"]
        case .russian: ["ru"]
        case .arabic: ["ar"]
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            .autoupdatingCurrent
        default:
            Locale(identifier: rawValue)
        }
    }

    var translationTarget: CodexTranslationTarget {
        switch self {
        case .system:
            Self.translationTarget(for: Locale.preferredLanguages.first ?? "en")
        case .english:
            .english
        case .simplifiedChinese:
            .simplifiedChinese
        case .traditionalChinese:
            .traditionalChinese
        case .japanese:
            .japanese
        case .korean:
            .korean
        case .french:
            .french
        case .german:
            .german
        case .spanish:
            .spanish
        case .portugueseBrazil:
            .portuguese
        case .russian:
            .russian
        case .arabic:
            .arabic
        }
    }

    var usesRightToLeftLayout: Bool {
        let identifier = self == .system
            ? (Locale.preferredLanguages.first ?? "en")
            : rawValue
        let language = identifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first?
            .lowercased()
        return language.map { ["ar", "fa", "he", "ur"].contains($0) } ?? false
    }

    private static func translationTarget(for identifier: String) -> CodexTranslationTarget {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized.hasPrefix("zh-hant")
            || normalized.hasPrefix("zh-tw")
            || normalized.hasPrefix("zh-hk")
            || normalized.hasPrefix("zh-mo") {
            return .traditionalChinese
        }
        if normalized.hasPrefix("zh") { return .simplifiedChinese }
        if normalized.hasPrefix("ja") { return .japanese }
        if normalized.hasPrefix("ko") { return .korean }
        if normalized.hasPrefix("fr") { return .french }
        if normalized.hasPrefix("de") { return .german }
        if normalized.hasPrefix("es") { return .spanish }
        if normalized.hasPrefix("pt") { return .portuguese }
        if normalized.hasPrefix("ru") { return .russian }
        if normalized.hasPrefix("ar") { return .arabic }
        return .english
    }
}

enum CommitDraftDetail: String, CaseIterable, Identifiable, Codable, Sendable {
    case concise
    case complete

    var id: String { rawValue }
}

enum WindowCloseBehavior: String, CaseIterable, Identifiable, Codable, Sendable {
    case ask
    case minimize
    case quit

    var id: String { rawValue }
}

enum AppVisualTheme: String, CaseIterable, Identifiable, Sendable {
    case standard = "default"
    case softGlass
    case console
    case emerald
    case folio

    var id: String { rawValue }

    static func resolved(_ storedValue: String?) -> AppVisualTheme {
        storedValue.flatMap(AppVisualTheme.init(rawValue:)) ?? AppStyleDefaults.defaultTheme
    }
}

enum AppAccentChoice: String, CaseIterable, Identifiable, Sendable {
    case coral
    case amber
    case blue
    case teal
    case green
    case violet
    case pink
    case custom

    var id: String { rawValue }
}

enum AppStyleDefaults {
    static let defaultTheme = AppVisualTheme.softGlass
    static let themeKey = "visualTheme"
    static let accentKey = "accentColor"
    static let customAccentKey = "customAccentHex"

    static var theme: AppVisualTheme {
        AppVisualTheme.resolved(UserDefaults.standard.string(forKey: themeKey))
    }

    static var accent: AppAccentChoice {
        AppAccentChoice(
            rawValue: UserDefaults.standard.string(forKey: accentKey) ?? ""
        ) ?? .coral
    }

    static var customAccentHex: String {
        UserDefaults.standard.string(forKey: customAccentKey) ?? "#4F7DFF"
    }
}

struct AppPreferences: Codable, Sendable, Equatable {
    var language: AppLanguage = .system
    var defaultWorkspace: WorkspaceSection = .github
    var liveRefreshEnabled = true
    var liveRefreshInterval = 1.0
    var remoteRefreshEnabled = true
    var remoteRefreshInterval = 30.0
    var commitDraftDetail: CommitDraftDetail = .concise
    var reopenLastRepository = true
    var launchAnimationEnabled = true
    var windowCloseBehavior: WindowCloseBehavior = .ask
    var confirmDiscardChanges = true
    var defaultTranslationTarget: CodexTranslationTarget = .simplifiedChinese

    private enum CodingKeys: String, CodingKey {
        case language
        case defaultWorkspace
        case liveRefreshEnabled
        case liveRefreshInterval
        case remoteRefreshEnabled
        case remoteRefreshInterval
        case commitDraftDetail
        case reopenLastRepository
        case launchAnimationEnabled
        case windowCloseBehavior
        case confirmDiscardChanges
        case defaultTranslationTarget
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        defaultWorkspace = try container.decodeIfPresent(WorkspaceSection.self, forKey: .defaultWorkspace) ?? .github
        liveRefreshEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveRefreshEnabled) ?? true
        liveRefreshInterval = try container.decodeIfPresent(Double.self, forKey: .liveRefreshInterval) ?? 1
        remoteRefreshEnabled = try container.decodeIfPresent(Bool.self, forKey: .remoteRefreshEnabled) ?? true
        remoteRefreshInterval = try container.decodeIfPresent(Double.self, forKey: .remoteRefreshInterval) ?? 30
        commitDraftDetail = try container.decodeIfPresent(CommitDraftDetail.self, forKey: .commitDraftDetail) ?? .concise
        reopenLastRepository = try container.decodeIfPresent(Bool.self, forKey: .reopenLastRepository) ?? true
        launchAnimationEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchAnimationEnabled) ?? true
        windowCloseBehavior = try container.decodeIfPresent(
            WindowCloseBehavior.self,
            forKey: .windowCloseBehavior
        ) ?? .ask
        confirmDiscardChanges = try container.decodeIfPresent(Bool.self, forKey: .confirmDiscardChanges) ?? true
        defaultTranslationTarget = try container.decodeIfPresent(CodexTranslationTarget.self, forKey: .defaultTranslationTarget) ?? .simplifiedChinese
    }
}

enum AppPreferencesStore {
    private static let key = "app.preferences"

    static func load() -> AppPreferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let preferences = try? JSONDecoder().decode(AppPreferences.self, from: data) else {
            return AppPreferences()
        }
        return preferences
    }

    static func save(_ preferences: AppPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func saveLanguage(_ language: AppLanguage) {
        var preferences = load()
        preferences.language = language
        save(preferences)
    }
}
