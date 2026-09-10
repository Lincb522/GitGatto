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
    case dsh
    case cursor
    case copilot
    case qwen
    case custom
    case openAICompatible
    case deepseek

    var id: String { rawValue }

    var localizationKey: String { "ai.provider.\(rawValue)" }

    var defaultName: String {
        switch self {
        case .codex: "Codex CLI"
        case .claude: "Claude Code"
        case .gemini: "Gemini CLI"
        case .opencode: "OpenCode"
        case .dsh: "DeepSeek Harness"
        case .cursor: "Cursor Agent"
        case .copilot: "GitHub Copilot CLI"
        case .qwen: "Qwen Code"
        case .custom: "Custom CLI"
        case .openAICompatible: "OpenAI-compatible API"
        case .deepseek: "DeepSeek API"
        }
    }

    var defaultExecutable: String {
        switch self {
        case .codex: "codex"
        case .claude: "claude"
        case .gemini: "gemini"
        case .opencode: "opencode"
        case .dsh: "dsh"
        case .cursor: "agent"
        case .copilot: "copilot"
        case .qwen: "qwen"
        case .custom, .openAICompatible, .deepseek: ""
        }
    }

    var usesAPI: Bool { self == .openAICompatible || self == .deepseek }

    var requiresProjectSandbox: Bool { [.dsh, .cursor, .copilot, .qwen].contains(self) }

    var stateDirectory: URL? {
        let name: String
        switch self {
        case .dsh: name = ProcessInfo.processInfo.environment["DSH_HOME"] ?? "~/.dsh"
        case .cursor: name = "~/.cursor"
        case .copilot: name = ProcessInfo.processInfo.environment["COPILOT_HOME"] ?? "~/.copilot"
        case .qwen: name = "~/.qwen"
        default: return nil
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return URL(fileURLWithPath: NSString(string: name).expandingTildeInPath, isDirectory: true)
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
    var api: AIAPIConfiguration?

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
        case .dsh, .cursor, .copilot, .qwen:
            cliPreset(preset)
        case .openAICompatible, .deepseek:
            AIProviderConfiguration(
                preset: preset, displayName: preset.defaultName, executable: "",
                versionArguments: "", analyzeArguments: "", editArguments: "",
                translationArguments: "", outputFormat: .plainText,
                api: AIAPIConfiguration(
                    baseURL: preset == .deepseek ? "https://api.deepseek.com" : "",
                    model: preset == .deepseek ? "deepseek-v4-flash" : ""
                )
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

    private static func cliPreset(_ preset: AIProviderPreset) -> AIProviderConfiguration {
        let analyze: String
        let edit: String
        switch preset {
        case .dsh:
            analyze = "--profile\nheadless\n{prompt}"
            edit = analyze
        case .cursor:
            analyze = "--print\n--output-format\ntext\n--mode\nask\n{prompt}"
            edit = "--print\n--output-format\ntext\n--sandbox\nenabled\n{prompt}"
        case .copilot:
            let common = "--silent\n--no-ask-user\n--disable-builtin-mcps\n--no-auto-update\n"
            analyze = common + "--plan\n--allow-tool\nread\n-p\n{prompt}"
            edit = common + "--allow-tool\nread\n--allow-tool\nwrite\n--allow-tool\nshell\n-p\n{prompt}"
        case .qwen:
            analyze = "--output-format\ntext\n--approval-mode\nplan\n--prompt\n{prompt}"
            edit = "--output-format\ntext\n--approval-mode\nauto-edit\n--prompt\n{prompt}"
        default:
            preconditionFailure("Not an additional CLI preset")
        }
        return AIProviderConfiguration(
            preset: preset, displayName: preset.defaultName, executable: preset.defaultExecutable,
            versionArguments: "--version", analyzeArguments: analyze, editArguments: edit,
            translationArguments: analyze, outputFormat: .plainText
        )
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
