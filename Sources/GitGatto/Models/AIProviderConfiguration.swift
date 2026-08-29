import Foundation

enum AIExecutionLane: String, Sendable {
    case project
    case translation
    case search
    case installer
}

enum AIProviderPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case codex
    case claude
    case gemini
    case opencode
    case custom

    var id: String { rawValue }

    var localizationKey: String { "ai.provider.\(rawValue)" }

    var defaultName: String {
        switch self {
        case .codex: "Codex CLI"
        case .claude: "Claude Code"
        case .gemini: "Gemini CLI"
        case .opencode: "OpenCode"
        case .custom: "Custom CLI"
        }
    }

    var defaultExecutable: String {
        switch self {
        case .codex: "codex"
        case .claude: "claude"
        case .gemini: "gemini"
        case .opencode: "opencode"
        case .custom: ""
        }
    }
}

enum AIOutputFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case plainText
    case codexJSONL

    var id: String { rawValue }
}

struct AIProviderConfiguration: Codable, Sendable, Equatable {
    var preset: AIProviderPreset
    var displayName: String
    var executable: String
    var versionArguments: String
    var analyzeArguments: String
    var editArguments: String
    var translationArguments: String
    var outputFormat: AIOutputFormat

    static func preset(_ preset: AIProviderPreset) -> AIProviderConfiguration {
        switch preset {
        case .codex:
            AIProviderConfiguration(
                preset: preset,
                displayName: preset.defaultName,
                executable: preset.defaultExecutable,
                versionArguments: "--version",
                analyzeArguments: "",
                editArguments: "",
                translationArguments: "",
                outputFormat: .codexJSONL
            )
        case .claude:
            AIProviderConfiguration(
                preset: preset,
                displayName: preset.defaultName,
                executable: preset.defaultExecutable,
                versionArguments: "--version",
                analyzeArguments: "-p\n--output-format\ntext\n--permission-mode\nplan\n--no-session-persistence\n{prompt}",
                editArguments: "-p\n--output-format\ntext\n--permission-mode\nacceptEdits\n--no-session-persistence\n{prompt}",
                translationArguments: "-p\n--output-format\ntext\n--permission-mode\nplan\n--tools\n{empty}\n--no-session-persistence\n{prompt}",
                outputFormat: .plainText
            )
        case .gemini:
            AIProviderConfiguration(
                preset: preset,
                displayName: preset.defaultName,
                executable: preset.defaultExecutable,
                versionArguments: "--version",
                analyzeArguments: "--output-format\ntext\n--approval-mode\nplan\n--prompt\n{prompt}",
                editArguments: "--output-format\ntext\n--approval-mode\nauto_edit\n--prompt\n{prompt}",
                translationArguments: "--output-format\ntext\n--approval-mode\nplan\n--prompt\n{prompt}",
                outputFormat: .plainText
            )
        case .opencode:
            AIProviderConfiguration(
                preset: preset,
                displayName: preset.defaultName,
                executable: preset.defaultExecutable,
                versionArguments: "--version",
                analyzeArguments: "run\n{prompt}",
                editArguments: "run\n{prompt}",
                translationArguments: "run\n{prompt}",
                outputFormat: .plainText
            )
        case .custom:
            AIProviderConfiguration(
                preset: preset,
                displayName: preset.defaultName,
                executable: "",
                versionArguments: "--version",
                analyzeArguments: "{prompt}",
                editArguments: "{prompt}",
                translationArguments: "{prompt}",
                outputFormat: .plainText
            )
        }
    }

    var resolvedName: String {
        let value = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? preset.defaultName : value
    }

    var localizedName: String {
        let value = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, value != preset.defaultName { return value }
        return L10n.text(preset.localizationKey)
    }

    func arguments(for lane: AIExecutionLane, mode: CodexRunMode = .analyze) -> [String] {
        let source: String
        switch lane {
        case .project, .search, .installer:
            source = mode == .analyze ? analyzeArguments : editArguments
        case .translation:
            source = translationArguments
        }
        return Self.argumentLines(source)
    }

    var parsedVersionArguments: [String] {
        Self.argumentLines(versionArguments)
    }

    private static func argumentLines(_ value: String) -> [String] {
        value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line in
                if line == "{empty}" { return "" }
                return line.isEmpty ? nil : String(line)
            }
    }
}

enum AIProviderSettings {
    private static let projectKey = "ai.project.configuration"
    private static let translationKey = "ai.translation.configuration"

    static func load(_ lane: AIExecutionLane) -> AIProviderConfiguration {
        let key = lane == .translation ? translationKey : projectKey
        guard let data = UserDefaults.standard.data(forKey: key),
              let configuration = try? JSONDecoder().decode(AIProviderConfiguration.self, from: data) else {
            return .preset(.codex)
        }
        return configuration
    }

    static func save(_ configuration: AIProviderConfiguration, lane: AIExecutionLane) {
        let key = lane == .translation ? translationKey : projectKey
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
