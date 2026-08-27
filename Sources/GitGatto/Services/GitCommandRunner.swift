import Foundation

struct GitCommandResult: Sendable {
    let output: Data
    let errorOutput: Data
    let exitCode: Int32

    var text: String {
        String(decoding: output, as: UTF8.self)
    }
}

struct GitCommandError: LocalizedError, Sendable {
    let arguments: [String]
    let exitCode: Int32
    let message: String

    var errorDescription: String? { message }

    var failureDetails: GitFailureDetails {
        GitFailureDetails(arguments: arguments, exitCode: exitCode, message: message)
    }
}

struct GitFailureDetails: Sendable, Equatable {
    let arguments: [String]
    let exitCode: Int32?
    let message: String

    var safeCommand: String {
        guard let command = arguments.first, !command.hasPrefix("-") else { return "git" }
        return "git \(command)"
    }
}

struct GitCommandRunner: Sendable {
    func run(
        at repositoryURL: URL,
        arguments: [String],
        acceptedExitCodes: Set<Int32> = [0]
    ) async throws -> GitCommandResult {
        try await Task.detached(priority: .userInitiated) {
            try Self.runBlocking(
                at: repositoryURL,
                arguments: arguments,
                acceptedExitCodes: acceptedExitCodes
            )
        }.value
    }

    private static func runBlocking(
        at repositoryURL: URL,
        arguments: [String],
        acceptedExitCodes: Set<Int32>
    ) throws -> GitCommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repositoryURL.path] + arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["GIT_PAGER"] = "cat"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_HTTP_LOW_SPEED_LIMIT"] = "1000"
        environment["GIT_HTTP_LOW_SPEED_TIME"] = "10"
        environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=10"
        environment["PATH"] = commandPath(inheritedPath: environment["PATH"])
        process.environment = environment

        try process.run()

        let outputBox = GitCommandDataBox()
        let errorBox = GitCommandDataBox()
        let readGroup = DispatchGroup()
        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputBox.set(outputPipe.fileHandleForReading.readDataToEndOfFile())
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorBox.set(errorPipe.fileHandleForReading.readDataToEndOfFile())
            readGroup.leave()
        }

        process.waitUntilExit()
        readGroup.wait()

        let result = GitCommandResult(
            output: outputBox.value,
            errorOutput: errorBox.value,
            exitCode: process.terminationStatus
        )

        guard acceptedExitCodes.contains(result.exitCode) else {
            let stdout = String(decoding: result.output, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = String(decoding: result.errorOutput, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let completeOutput = [stdout, stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw GitCommandError(
                arguments: arguments,
                exitCode: result.exitCode,
                message: completeOutput.isEmpty
                    ? "git exited with status \(result.exitCode)"
                    : completeOutput
            )
        }

        return result
    }

    static func commandPath(
        inheritedPath: String?,
        additionalSearchPaths: [String] = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin", isDirectory: true)
                .path
        ]
    ) -> String {
        let inherited = inheritedPath?.split(separator: ":").map(String.init) ?? []
        var seen = Set<String>()
        return (additionalSearchPaths + inherited)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
    }
}

private final class GitCommandDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var value: Data {
        lock.withLock { storage }
    }

    func set(_ value: Data) {
        lock.withLock { storage = value }
    }
}
