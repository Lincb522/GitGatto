import Darwin
import Foundation

enum DevelopmentToolEnvironmentConfiguration: Sendable, Equatable {
    case unchanged
    case updated(profileURL: URL)
}

protocol DevelopmentToolEnvironmentConfiguring: Sendable {
    func configure(executableURL: URL) async throws -> DevelopmentToolEnvironmentConfiguration
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
