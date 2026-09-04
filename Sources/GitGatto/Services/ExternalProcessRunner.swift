import Foundation

struct ExternalProcessResult: Sendable {
    let standardOutput: Data
    let standardError: Data
    let exitCode: Int32

    var outputText: String {
        String(decoding: standardOutput, as: UTF8.self)
    }

    var errorText: String {
        String(decoding: standardError, as: UTF8.self)
    }
}

struct ExternalProcessError: LocalizedError, Sendable {
    let executable: String
    let arguments: [String]
    let exitCode: Int32
    let output: String

    var errorDescription: String? {
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty
            ? "\(URL(fileURLWithPath: executable).lastPathComponent) exited with status \(exitCode)."
            : detail
    }
}

struct ExternalProcessTimeoutError: LocalizedError, Sendable {
    let executable: String

    var errorDescription: String? {
        L10n.format("process.error.timeout", URL(fileURLWithPath: executable).lastPathComponent)
    }
}

struct ExternalProcessRunner: Sendable {
    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String] = [:],
        input: Data? = nil,
        acceptedExitCodes: Set<Int32> = [0],
        timeout: Duration = .seconds(30)
    ) async throws -> ExternalProcessResult {
        let invocation = ExternalProcessInvocation(
            executable: executable,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            environment: environment,
            input: input
        )
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: ExternalProcessResult.self) { group in
                group.addTask { try await invocation.run() }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    invocation.cancel()
                    throw ExternalProcessTimeoutError(executable: executable.path)
                }
                guard let result = try await group.next() else { throw CancellationError() }
                group.cancelAll()
                guard acceptedExitCodes.contains(result.exitCode) else {
                    let output = [result.outputText, result.errorText]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                    throw ExternalProcessError(
                        executable: executable.path,
                        arguments: arguments,
                        exitCode: result.exitCode,
                        output: output
                    )
                }
                return result
            }
        } onCancel: {
            invocation.cancel()
        }
    }
}

private final class ExternalProcessInvocation: @unchecked Sendable {
    private let executable: URL
    private let arguments: [String]
    private let currentDirectoryURL: URL?
    private let environmentOverrides: [String: String]
    private let input: Data?
    private let process = Process()
    private let lock = NSLock()
    private var started = false
    private var cancelled = false

    init(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String],
        input: Data?
    ) {
        self.executable = executable
        self.arguments = arguments
        self.currentDirectoryURL = currentDirectoryURL
        environmentOverrides = environment
        self.input = input
    }

    func run() async throws -> ExternalProcessResult {
        try await Task.detached(priority: .userInitiated) { [self] in
            try runBlocking()
        }.value
    }

    func cancel() {
        let shouldTerminate = lock.withLock {
            cancelled = true
            return started && process.isRunning
        }
        if shouldTerminate { process.terminate() }
    }

    private func runBlocking() throws -> ExternalProcessResult {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = input == nil ? nil : Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["NO_COLOR"] = "1"
        environment["GIT_PAGER"] = "cat"
        environment["GH_PAGER"] = "cat"
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment.merge(environmentOverrides) { _, replacement in replacement }
        process.environment = environment

        if lock.withLock({ cancelled }) { throw CancellationError() }
        try process.run()
        lock.withLock { started = true }
        if lock.withLock({ cancelled }) { process.terminate() }

        if let input, let inputPipe {
            inputPipe.fileHandleForWriting.write(input)
            try? inputPipe.fileHandleForWriting.close()
        }
        let captured = ProcessPipeCollector.waitForExit(
            process,
            standardOutput: outputPipe,
            standardError: errorPipe
        )
        if lock.withLock({ cancelled }) || Task.isCancelled { throw CancellationError() }
        return ExternalProcessResult(
            standardOutput: captured.standardOutput,
            standardError: captured.standardError,
            exitCode: process.terminationStatus
        )
    }
}

enum CommandExecutableLocator {
    static func find(_ name: String) -> URL? {
        let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/\(name)").path,
        ] + environmentPath.split(separator: ":").map { "\($0)/\(name)" }
        return candidates.lazy
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
