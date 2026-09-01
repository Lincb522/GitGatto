import Foundation

struct DevelopmentToolProbeResult: Sendable, Equatable {
    let isInstalled: Bool
    let version: String?
    let executableURL: URL?
}

protocol DevelopmentToolProbing: Sendable {
    func probe(_ tool: DevelopmentTool) async -> DevelopmentToolProbeResult
}

actor DevelopmentToolProbe: DevelopmentToolProbing {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func probe(_ tool: DevelopmentTool) async -> DevelopmentToolProbeResult {
        if tool.id == "xcode-command-line-tools" {
            return await probeCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcode-select"),
                arguments: ["--print-path"]
            )
        }
        guard let executableURL = locate(
            tool.executableCandidates,
            homebrewFormula: tool.homebrewFormula
        ) else {
            return DevelopmentToolProbeResult(isInstalled: false, version: nil, executableURL: nil)
        }
        return await probeCommand(executableURL: executableURL, arguments: tool.versionArguments)
    }

    private func locate(_ commands: [String], homebrewFormula: String?) -> URL? {
        let home = fileManager.homeDirectoryForCurrentUser
        var directories = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".cargo/bin").path,
            home.appendingPathComponent(".npm-global/bin").path,
            home.appendingPathComponent("Library/Python/3.14/bin").path,
            home.appendingPathComponent("Library/Python/3.13/bin").path
        ]
        if let homebrewFormula {
            let formula = homebrewFormula.split(separator: "/").last.map(String.init) ?? homebrewFormula
            directories.append(contentsOf: [
                "/opt/homebrew/opt/\(formula)/bin",
                "/opt/homebrew/opt/\(formula)/sbin",
                "/usr/local/opt/\(formula)/bin",
                "/usr/local/opt/\(formula)/sbin"
            ])
        }
        if let environmentPath = ProcessInfo.processInfo.environment["PATH"] {
            directories.append(contentsOf: environmentPath.split(separator: ":").map(String.init))
        }
        var visited = Set<String>()
        for directory in directories where visited.insert(directory).inserted {
            for command in commands {
                let url = URL(fileURLWithPath: directory).appendingPathComponent(command)
                if fileManager.isExecutableFile(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
    }

    private func probeCommand(executableURL: URL, arguments: [String]) async -> DevelopmentToolProbeResult {
        await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = error
            do {
                try process.run()
                process.waitUntilExit()
                let stdout = output.fileHandleForReading.readDataToEndOfFile()
                let stderr = error.fileHandleForReading.readDataToEndOfFile()
                guard process.terminationStatus == 0 else {
                    return DevelopmentToolProbeResult(
                        isInstalled: false,
                        version: nil,
                        executableURL: executableURL
                    )
                }
                let text = String(decoding: stdout.isEmpty ? stderr : stdout, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let firstLine = text.split(whereSeparator: \Character.isNewline).first.map(String.init)
                return DevelopmentToolProbeResult(
                    isInstalled: true,
                    version: firstLine,
                    executableURL: executableURL
                )
            } catch {
                return DevelopmentToolProbeResult(
                    isInstalled: false,
                    version: nil,
                    executableURL: executableURL
                )
            }
        }.value
    }
}
