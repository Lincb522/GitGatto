import Darwin
import Foundation

protocol DevelopmentToolUpdateChecking: Sendable {
    func checkUpdates(for tools: [DevelopmentTool]) async -> [String: DevelopmentToolUpdateResult]
}

actor DevelopmentToolUpdateService: DevelopmentToolUpdateChecking {
    private let fileManager: FileManager
    private let homebrewURL: URL?

    init(fileManager: FileManager = .default, homebrewURL: URL? = nil) {
        self.fileManager = fileManager
        self.homebrewURL = homebrewURL
    }

    func checkUpdates(for tools: [DevelopmentTool]) async -> [String: DevelopmentToolUpdateResult] {
        let installedTools = tools.filter { $0.homebrewFormula != nil }
        var results = Dictionary(uniqueKeysWithValues: tools.map {
            ($0.id, DevelopmentToolUpdateResult.unavailable(
                detail: L10n.text("developer_tools.update.unmanaged")
            ))
        })
        guard !installedTools.isEmpty else { return results }
        guard let brewURL = locateHomebrew() else {
            for tool in installedTools {
                results[tool.id] = .unavailable(detail: L10n.text("developer_tools.update.homebrew_missing"))
            }
            return results
        }

        do {
            let installedOutput = try await run(
                brewURL,
                arguments: ["list", "--formula", "--versions"],
                acceptsNonzeroExit: false
            )
            let installed = Self.parseInstalledFormulae(installedOutput)
            let outdatedOutput = try await run(
                brewURL,
                arguments: ["outdated", "--json=v2"],
                acceptsNonzeroExit: false
            )
            let outdated = try JSONDecoder().decode(HomebrewOutdatedPayload.self, from: outdatedOutput)

            for tool in installedTools {
                guard let formula = tool.homebrewFormula,
                      let installedEntry = installed.first(where: { Self.matches($0.name, formula: formula) }) else {
                    results[tool.id] = .unavailable(detail: L10n.text("developer_tools.update.unmanaged"))
                    continue
                }
                if let update = outdated.formulae.first(where: { Self.matches($0.name, formula: formula) }) {
                    results[tool.id] = DevelopmentToolUpdateResult(
                        availability: .available,
                        installedVersion: update.installedVersions.last ?? installedEntry.versions.last,
                        latestVersion: update.currentVersion,
                        packageName: update.name,
                        isPinned: update.pinned,
                        detail: update.pinned ? L10n.text("developer_tools.update.pinned") : nil
                    )
                } else {
                    results[tool.id] = DevelopmentToolUpdateResult(
                        availability: .current,
                        installedVersion: installedEntry.versions.last,
                        latestVersion: installedEntry.versions.last,
                        packageName: installedEntry.name,
                        isPinned: false,
                        detail: nil
                    )
                }
            }
            return results
        } catch is CancellationError {
            return results
        } catch {
            for tool in installedTools {
                results[tool.id] = DevelopmentToolUpdateResult(
                    availability: .failed,
                    installedVersion: nil,
                    latestVersion: nil,
                    packageName: tool.homebrewFormula,
                    isPinned: false,
                    detail: error.localizedDescription
                )
            }
            return results
        }
    }

    private func locateHomebrew() -> URL? {
        if let homebrewURL {
            return fileManager.isExecutableFile(atPath: homebrewURL.path) ? homebrewURL : nil
        }
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
            "/home/linuxbrew/.linuxbrew/bin/brew"
        ]
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private func run(
        _ executableURL: URL,
        arguments: [String],
        acceptsNonzeroExit: Bool
    ) async throws -> Data {
        let command = DevelopmentToolUpdateCommand(executableURL: executableURL, arguments: arguments)
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: DevelopmentToolUpdateCommand.Output.self) { group in
                group.addTask { try await command.run() }
                group.addTask {
                    try await Task.sleep(for: .seconds(90))
                    command.cancel()
                    throw DevelopmentToolUpdateError.timedOut
                }
                guard let output = try await group.next() else {
                    throw DevelopmentToolUpdateError.invalidResponse
                }
                group.cancelAll()
                guard acceptsNonzeroExit || output.exitCode == 0 else {
                    let message = String(decoding: output.standardError, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    throw DevelopmentToolUpdateError.commandFailed(message)
                }
                return output.standardOutput
            }
        } onCancel: {
            command.cancel()
        }
    }

    private static func parseInstalledFormulae(_ data: Data) -> [InstalledFormula] {
        String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \Character.isNewline)
            .compactMap { line in
                let parts = line.split(whereSeparator: \Character.isWhitespace).map(String.init)
                guard parts.count >= 2 else { return nil }
                return InstalledFormula(name: parts[0], versions: Array(parts.dropFirst()))
            }
    }

    private static func matches(_ packageName: String, formula: String) -> Bool {
        packageName == formula || packageName.hasPrefix("\(formula)@")
    }
}

private struct InstalledFormula: Sendable {
    let name: String
    let versions: [String]
}

private struct HomebrewOutdatedPayload: Decodable {
    let formulae: [HomebrewOutdatedFormula]
}

private struct HomebrewOutdatedFormula: Decodable {
    let name: String
    let installedVersions: [String]
    let currentVersion: String
    let pinned: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case installedVersions = "installed_versions"
        case currentVersion = "current_version"
        case pinned
    }
}

private enum DevelopmentToolUpdateError: LocalizedError {
    case launchFailed
    case commandFailed(String)
    case invalidResponse
    case timedOut

    var errorDescription: String? {
        switch self {
        case .launchFailed:
            L10n.text("developer_tools.update.error.launch")
        case let .commandFailed(message):
            message.isEmpty
                ? L10n.text("developer_tools.update.error.command")
                : L10n.format("developer_tools.update.error.command_detail", message)
        case .invalidResponse:
            L10n.text("developer_tools.update.error.response")
        case .timedOut:
            L10n.text("developer_tools.update.error.timeout")
        }
    }
}

private final class DevelopmentToolUpdateCommand: @unchecked Sendable {
    struct Output: Sendable {
        let standardOutput: Data
        let standardError: Data
        let exitCode: Int32
    }

    private let executableURL: URL
    private let arguments: [String]
    private let process = Process()
    private let lock = NSLock()
    private var hasStarted = false
    private var isCancelled = false

    init(executableURL: URL, arguments: [String]) {
        self.executableURL = executableURL
        self.arguments = arguments
    }

    func run() async throws -> Output {
        try await Task.detached(priority: .utility) { [self] in
            try runBlocking()
        }.value
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let shouldTerminate = hasStarted && process.isRunning
        lock.unlock()
        guard shouldTerminate else { return }
        process.terminate()
        let process = process
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    private func runBlocking() throws -> Output {
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["NO_COLOR"] = "1"
        process.environment = environment

        lock.lock()
        if isCancelled {
            lock.unlock()
            throw CancellationError()
        }
        do {
            try process.run()
            hasStarted = true
            lock.unlock()
        } catch {
            lock.unlock()
            throw DevelopmentToolUpdateError.launchFailed
        }

        let outputBox = UpdateCommandDataBox()
        let errorBox = UpdateCommandDataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outputBox.set(output.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errorBox.set(error.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        process.waitUntilExit()
        group.wait()

        lock.lock()
        let cancelled = isCancelled
        lock.unlock()
        if cancelled { throw CancellationError() }
        return Output(
            standardOutput: outputBox.value,
            standardError: errorBox.value,
            exitCode: process.terminationStatus
        )
    }
}

private final class UpdateCommandDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var value: Data {
        lock.withLock { data }
    }

    func set(_ value: Data) {
        lock.withLock { data = value }
    }
}
