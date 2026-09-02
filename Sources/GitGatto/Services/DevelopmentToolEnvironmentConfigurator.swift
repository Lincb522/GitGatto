import Darwin
import Foundation

enum DevelopmentToolEnvironmentConfiguration: Sendable, Equatable {
    case unchanged
    case updated(profileURL: URL)
}

protocol DevelopmentToolEnvironmentConfiguring: Sendable {
    func configure(executableURL: URL) async throws -> DevelopmentToolEnvironmentConfiguration
}

protocol DevelopmentToolSystemAuthorizing: Sendable {
    func request(for tool: DevelopmentTool) async -> DevelopmentToolSystemAuthorizationRequest?
    func authorize(_ request: DevelopmentToolSystemAuthorizationRequest) async throws
}

enum DevelopmentToolSystemAuthorizationError: LocalizedError, Sendable, Equatable {
    case cancelled
    case invalidRequest
    case failed

    var errorDescription: String? {
        switch self {
        case .cancelled:
            L10n.text("developer_tools.authorization.cancelled")
        case .invalidRequest:
            L10n.text("developer_tools.authorization.invalid")
        case .failed:
            L10n.text("developer_tools.authorization.failed")
        }
    }
}

actor DevelopmentToolSystemAuthorizer: DevelopmentToolSystemAuthorizing {
    private let fileManager: FileManager
    private let homebrewURLs: [URL]
    private let runAuthorization: @Sendable (String, String) async throws -> Void

    init(
        fileManager: FileManager = .default,
        homebrewURLs: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            URL(fileURLWithPath: "/usr/local/bin/brew")
        ],
        runAuthorization: (@Sendable (String, String) async throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.homebrewURLs = homebrewURLs
        self.runAuthorization = runAuthorization ?? Self.runAuthorizationCommand
    }

    func request(for tool: DevelopmentTool) async -> DevelopmentToolSystemAuthorizationRequest? {
        guard tool.homebrewFormula != nil,
              let brewURL = homebrewURLs.first(where: {
                  fileManager.isExecutableFile(atPath: $0.path)
              }),
              let prefix = Self.homebrewPrefix(for: brewURL) else {
            return nil
        }

        let knownDirectories = Self.managedDirectoryNames.map {
            prefix.appendingPathComponent($0, isDirectory: true).standardizedFileURL
        }
        let repairDirectories = knownDirectories.filter {
            fileManager.fileExists(atPath: $0.path)
                && !fileManager.isWritableFile(atPath: $0.path)
        }

        guard !repairDirectories.isEmpty else { return nil }
        return DevelopmentToolSystemAuthorizationRequest(
            toolName: tool.name,
            homebrewPrefix: prefix,
            repairDirectories: repairDirectories.sorted { $0.path < $1.path }
        )
    }

    func authorize(_ request: DevelopmentToolSystemAuthorizationRequest) async throws {
        guard Self.isAllowedPrefix(request.homebrewPrefix),
              !request.repairDirectories.isEmpty,
              request.repairDirectories.allSatisfy({
                  Self.isAllowedRepairDirectory($0, prefix: request.homebrewPrefix)
              }) else {
            throw DevelopmentToolSystemAuthorizationError.invalidRequest
        }

        let userID = getuid()
        let commands = request.repairDirectories.map { directory in
            let path = Self.shellQuote(directory.standardizedFileURL.path)
            let recursive = Self.recursiveRepairDirectoryNames.contains(directory.lastPathComponent)
                ? "-R "
                : ""
            return "/usr/sbin/chown \(recursive)\(userID) \(path) && /bin/chmod \(recursive)u+rwX \(path)"
        }
        let command = commands.joined(separator: " && ")
        let prompt = L10n.format(
            "developer_tools.authorization.system_prompt",
            request.toolName
        )
        try await runAuthorization(command, prompt)
    }

    private static let managedDirectoryNames = [
        "Homebrew",
        "Cellar",
        "Caskroom",
        "Frameworks",
        "bin",
        "etc",
        "include",
        "lib",
        "opt",
        "sbin",
        "share",
        "var"
    ]
    private static let recursiveRepairDirectoryNames: Set<String> = [
        "Homebrew",
        "Cellar",
        "Caskroom"
    ]

    private static func homebrewPrefix(for brewURL: URL) -> URL? {
        let path = brewURL.standardizedFileURL.path
        if path == "/opt/homebrew/bin/brew" {
            return URL(fileURLWithPath: "/opt/homebrew", isDirectory: true)
        }
        if path == "/usr/local/bin/brew" {
            return URL(fileURLWithPath: "/usr/local", isDirectory: true)
        }
        return nil
    }

    private static func isAllowedPrefix(_ prefix: URL) -> Bool {
        let path = prefix.standardizedFileURL.path
        return path == "/opt/homebrew" || path == "/usr/local"
    }

    private static func isAllowedRepairDirectory(_ directory: URL, prefix: URL) -> Bool {
        guard isAllowedPrefix(prefix) else { return false }
        let path = directory.standardizedFileURL.path
        return managedDirectoryNames.contains { name in
            path == prefix.appendingPathComponent(name, isDirectory: true).standardizedFileURL.path
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runAuthorizationCommand(_ command: String, prompt: String) async throws {
        let process = Process()
        let output = Pipe()
        let escapedCommand = appleScriptString(command)
        let escapedPrompt = appleScriptString(prompt)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \"\(escapedCommand)\" with administrator privileges with prompt \"\(escapedPrompt)\""
        ]
        process.standardOutput = output
        process.standardError = output

        let task = Task.detached(priority: .userInitiated) {
            do {
                try process.run()
            } catch {
                throw DevelopmentToolSystemAuthorizationError.failed
            }
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self)
            guard process.terminationStatus == 0 else {
                if message.contains("(-128)") || message.localizedCaseInsensitiveContains("user canceled") {
                    throw DevelopmentToolSystemAuthorizationError.cancelled
                }
                throw DevelopmentToolSystemAuthorizationError.failed
            }
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

actor DevelopmentToolEnvironmentConfigurator: DevelopmentToolEnvironmentConfiguring {
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let shellPath: String
    private let updatesProcessEnvironment: Bool
    private var environmentPath: String

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        shellPath: String? = nil,
        environmentPath: String? = nil,
        updatesProcessEnvironment: Bool = true
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        self.shellPath = shellPath
            ?? ProcessInfo.processInfo.environment["SHELL"]
            ?? Self.defaultShellPath()
        self.environmentPath = environmentPath ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        self.updatesProcessEnvironment = updatesProcessEnvironment
    }

    func configure(executableURL: URL) async throws -> DevelopmentToolEnvironmentConfiguration {
        let directory = executableURL.deletingLastPathComponent().standardizedFileURL
        guard !pathComponents.contains(directory.path) else {
            return .unchanged
        }

        let destination = shellConfigurationDestination()
        let expression = pathExpression(for: directory)
        let marker = "# GitGatto PATH: \(expression)"
        let existing = (try? String(contentsOf: destination.url, encoding: .utf8)) ?? ""
        guard !existing.contains(marker) else {
            updateProcessPath(with: directory.path)
            return .unchanged
        }

        try fileManager.createDirectory(
            at: destination.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: destination.url.path) {
            guard fileManager.createFile(atPath: destination.url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }

        let block = destination.block(expression, marker)
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let handle = try FileHandle(forWritingTo: destination.url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((separator + block).utf8))
        updateProcessPath(with: directory.path)
        return .updated(profileURL: destination.url)
    }

    private var pathComponents: Set<String> {
        Set(environmentPath.split(separator: ":").map(String.init))
    }

    private func updateProcessPath(with directory: String) {
        guard !pathComponents.contains(directory) else { return }
        environmentPath = environmentPath.isEmpty ? directory : "\(directory):\(environmentPath)"
        if updatesProcessEnvironment {
            setenv("PATH", environmentPath, 1)
        }
    }

    private func pathExpression(for directory: URL) -> String {
        let homePath = homeDirectory.standardizedFileURL.path
        let path = directory.path
        if path == homePath {
            return "$HOME"
        }
        if path.hasPrefix(homePath + "/") {
            return "$HOME/" + String(path.dropFirst(homePath.count + 1))
        }
        return path
    }

    private static func defaultShellPath() -> String {
        guard let record = getpwuid(getuid()) else { return "/bin/zsh" }
        return String(cString: record.pointee.pw_shell)
    }

    private func shellConfigurationDestination() -> ShellConfigurationDestination {
        switch URL(fileURLWithPath: shellPath).lastPathComponent.lowercased() {
        case "fish":
            return ShellConfigurationDestination(
                url: homeDirectory.appendingPathComponent(".config/fish/conf.d/gitgatto-path.fish"),
                block: { expression, marker in
                    """
                    \(marker)
                    if not contains -- "\(expression)" $PATH
                        fish_add_path --prepend "\(expression)"
                    end

                    """
                }
            )
        case "bash":
            return posixDestination(named: ".bash_profile")
        case "zsh":
            return posixDestination(named: ".zprofile")
        default:
            return posixDestination(named: ".profile")
        }
    }

    private func posixDestination(named name: String) -> ShellConfigurationDestination {
        ShellConfigurationDestination(
            url: homeDirectory.appendingPathComponent(name),
            block: { expression, marker in
                """
                \(marker)
                case ":$PATH:" in
                  *":\(expression):"*) ;;
                  *) export PATH="\(expression):$PATH" ;;
                esac

                """
            }
        )
    }
}

private struct ShellConfigurationDestination: Sendable {
    let url: URL
    let block: @Sendable (_ expression: String, _ marker: String) -> String
}
