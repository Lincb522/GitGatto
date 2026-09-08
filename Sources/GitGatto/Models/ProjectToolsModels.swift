import Foundation

enum ProjectTool: String, CaseIterable, Identifiable {
    case search, scenes, commands, ignore, identities
    var id: String { rawValue }
    var title: String { L10n.text("tools.\(rawValue)") }
    var symbol: String {
        switch self {
        case .search: "magnifyingglass"
        case .scenes: "square.stack.3d.up"
        case .commands: "terminal"
        case .ignore: "eye.slash"
        case .identities: "person.crop.circle"
        }
    }
}

struct ProjectToolsError: LocalizedError, Sendable {
    let key: String
    var errorDescription: String? { L10n.text("tools.error.\(key)") }
}

struct ProjectCodeQuery: Sendable {
    enum Scope: String, CaseIterable { case working, revision, history }
    var text = ""
    var scope = Scope.working
    var revision = "HEAD"
    var directory = ""
    var fileExtension = ""
    var language = ""
    static let languageExtensions: [String: [String]] = [
        "Swift": ["swift"], "Objective-C": ["m", "mm", "h"], "C": ["c", "h"], "C++": ["cpp", "cc", "cxx", "hpp", "hxx", "h"],
        "C#": ["cs"], "JavaScript": ["js", "jsx", "mjs", "cjs"], "TypeScript": ["ts", "tsx", "mts", "cts"],
        "Python": ["py", "pyi"], "Go": ["go"], "Rust": ["rs"], "Java": ["java"], "Kotlin": ["kt", "kts"],
        "Ruby": ["rb", "rake"], "PHP": ["php"], "Shell": ["sh", "bash", "zsh"], "Dart": ["dart"], "Scala": ["scala", "sc"],
        "Lua": ["lua"], "HTML": ["html", "htm"], "CSS": ["css", "scss", "sass", "less"],
        "JSON": ["json", "jsonc"], "YAML": ["yml", "yaml"], "SQL": ["sql"], "Markdown": ["md", "markdown"]
    ]
    var filenamesOnly = false
}

struct ProjectCodeMatch: Identifiable, Sendable {
    let repository: URL
    let path: String
    let line: Int?
    let text: String
    let revision: String?
    var id: String { [repository.path, revision ?? "", path, String(line ?? 0), text].joined(separator: "\u{1f}") }
}

struct ProjectSearchResult: Sendable {
    var matches: [ProjectCodeMatch] = []
    var failures: [String] = []
    var limited = false
}

struct WorkScene: Codable, Identifiable, Sendable, Equatable {
    enum Phase: String, Codable { case saving, saved, restoring, restored, handled }
    var id = UUID()
    var name: String
    var repositoryPath: String
    var branch: String
    var head: String
    var stash: String?
    var phase = Phase.saving
    var createdAt = Date()
    var selectedPath: String?
    var draft: String
    var agentDraft: String
    var goalID: UUID?
    var relatedURL: String
    var section: String
    var ref: String { "refs/gitgatto/scenes/\(id.uuidString.lowercased())" }
    var marker: String { "GitGatto-scene-\(id.uuidString)" }
}

struct ProjectCommand: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var title: String
    var executable: String
    var arguments: [String]
    var repositoryPath: String
    var timeoutSeconds: Int = 3600
    var localURL: String = ""
    var displayCommand: String { ([executable] + arguments).map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ") }
}

struct RepositoryIdentityProfile: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var title: String
    var name: String
    var email: String
    var signCommits = false
    var signingFormat = "openpgp"
    var signingKey = ""
}

struct RepositoryIdentityBinding: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var profileID: UUID
    var path: String
    var directory: Bool
    var configKey: String
    var includePath: String
}

struct ProjectToolsState: Codable, Sendable {
    var scenes: [WorkScene] = []
    var commands: [ProjectCommand] = []
    var profiles: [RepositoryIdentityProfile] = []
    var bindings: [RepositoryIdentityBinding] = []
}

actor ProjectToolsStore {
    let root: URL
    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GitGatto/ProjectTools", isDirectory: true)) { self.root = root }
    func load() throws -> ProjectToolsState {
        let file = root.appendingPathComponent("state.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return ProjectToolsState() }
        return try JSONDecoder().decode(ProjectToolsState.self, from: Data(contentsOf: file))
    }
    @discardableResult func update(_ transform: @Sendable (inout ProjectToolsState) throws -> Void) throws -> ProjectToolsState {
        var state = try load()
        try transform(&state)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: root.appendingPathComponent("state.json"), options: .atomic)
        return state
    }
}

enum ProjectToolsPolicy {
    static func relativePath(_ path: String) throws -> String {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.contains("\0") else {
            throw ProjectToolsError(key: "path")
        }
        return path
    }
    static func allowsContent(_ path: String) -> Bool {
        let parts = path.lowercased().split(separator: "/").map(String.init)
        return !parts.contains { $0 == ".git" || $0 == ".env" || $0.hasPrefix(".env.") || $0 == "credentials" || $0 == "auth.json" || $0.hasSuffix(".pem") || $0.hasSuffix(".key") || $0.hasPrefix("id_rsa") || $0.hasPrefix("id_ed25519") }
    }
    static func git(_ repository: URL, _ arguments: [String], input: Data? = nil, codes: Set<Int32> = [0], environment: [String: String] = [:]) async throws -> ExternalProcessResult {
        try await ExternalProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/git"), arguments: ["-C", repository.path] + arguments,
            currentDirectoryURL: repository, environment: environment, input: input, acceptedExitCodes: codes, timeout: .seconds(60))
    }
    static func text(_ repository: URL, _ arguments: [String]) async throws -> String {
        try await git(repository, arguments).outputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
