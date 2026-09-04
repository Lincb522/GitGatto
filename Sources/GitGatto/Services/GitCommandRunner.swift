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
        environment environmentOverrides: [String: String] = [:],
        acceptedExitCodes: Set<Int32> = [0]
    ) async throws -> GitCommandResult {
        let processBox = GitCommandProcessBox()
        let task = Task.detached(priority: .userInitiated) {
            try Self.runBlocking(
                at: repositoryURL,
                arguments: arguments,
                environmentOverrides: environmentOverrides,
                acceptedExitCodes: acceptedExitCodes,
                processBox: processBox
            )
        }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            task.cancel()
            processBox.cancel()
        }
    }

    private static func runBlocking(
        at repositoryURL: URL,
        arguments: [String],
        environmentOverrides: [String: String],
        acceptedExitCodes: Set<Int32>,
        processBox: GitCommandProcessBox
    ) throws -> GitCommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repositoryURL.path] + arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        guard !processBox.install(process) else { throw CancellationError() }
        defer { processBox.clear() }

        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["GIT_PAGER"] = "cat"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_HTTP_LOW_SPEED_LIMIT"] = "1000"
        environment["GIT_HTTP_LOW_SPEED_TIME"] = "10"
        environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=10"
        environment["PATH"] = commandPath(inheritedPath: environment["PATH"])
        environment.merge(environmentOverrides) { _, override in override }
        process.environment = environment

        try process.run()
        if processBox.isCancelled {
            process.terminate()
        }

        let capturedOutput = ProcessPipeCollector.waitForExit(
            process,
            standardOutput: outputPipe,
            standardError: errorPipe
        )

        if processBox.isCancelled || Task.isCancelled {
            throw CancellationError()
        }

        let result = GitCommandResult(
            output: capturedOutput.standardOutput,
            errorOutput: capturedOutput.standardError,
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

private final class GitCommandProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func install(_ process: Process) -> Bool {
        lock.withLock {
            self.process = process
            return cancelled
        }
    }

    func cancel() {
        let process = lock.withLock {
            cancelled = true
            return self.process
        }
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    func clear() {
        lock.withLock { process = nil }
    }
}

struct ProcessPipeOutput: Sendable {
    let standardOutput: Data
    let standardError: Data
}

enum ProcessPipeCollector {
    static func waitForExit(
        _ process: Process,
        standardOutput outputPipe: Pipe,
        standardError errorPipe: Pipe
    ) -> ProcessPipeOutput {
        let outputReader = ProcessPipeReader(
            handle: outputPipe.fileHandleForReading,
            name: "GitGatto.stdout"
        )
        let errorReader = ProcessPipeReader(
            handle: errorPipe.fileHandleForReading,
            name: "GitGatto.stderr"
        )
        outputReader.start()
        errorReader.start()
        process.waitUntilExit()
        return ProcessPipeOutput(
            standardOutput: outputReader.waitForData(),
            standardError: errorReader.waitForData()
        )
    }
}

private final class ProcessPipeReader: @unchecked Sendable {
    private let handle: FileHandle
    private let name: String
    private let completion = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var storage = Data()

    init(handle: FileHandle, name: String) {
        self.handle = handle
        self.name = name
    }

    func start() {
        let thread = Thread { [self] in
            let data = handle.readDataToEndOfFile()
            lock.withLock { storage = data }
            completion.signal()
        }
        thread.name = name
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func waitForData() -> Data {
        completion.wait()
        return lock.withLock { storage }
    }
}
