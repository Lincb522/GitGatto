import Darwin
import Foundation

enum DevelopmentToolHomebrewOperation: String, Sendable {
    case install
    case upgrade
}

enum DevelopmentToolHomebrewError: LocalizedError, Sendable, Equatable {
    case unavailable
    case invalidFormula
    case launchFailed
    case commandFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unavailable:
            L10n.text("developer_tools.update.homebrew_missing")
        case .invalidFormula:
            L10n.text("developer_tools.package.error.invalid_formula")
        case .launchFailed:
            L10n.text("developer_tools.package.error.launch")
        case let .commandFailed(message):
            L10n.format("developer_tools.package.error.command", message)
        case .timedOut:
            L10n.text("developer_tools.package.error.timeout")
        }
    }

    var commandOutput: String? {
        guard case let .commandFailed(output) = self else { return nil }
        return output
    }
}

protocol DevelopmentToolHomebrewManaging: Sendable {
    func run(_ operation: DevelopmentToolHomebrewOperation, formula: String) async throws -> String
    func cancel() async
}

actor DevelopmentToolHomebrewService: DevelopmentToolHomebrewManaging {
    private static let executionGate = DevelopmentToolHomebrewExecutionGate()

    private let fileManager: FileManager
    private let configuredHomebrewURL: URL?
    private let timeout: Duration
    private var currentCommand: DevelopmentToolHomebrewCommand?
    private var currentOperationID: UUID?

    init(
        fileManager: FileManager = .default,
        homebrewURL: URL? = nil,
        timeout: Duration = .seconds(1_800)
    ) {
        self.fileManager = fileManager
        self.configuredHomebrewURL = homebrewURL
        self.timeout = timeout
    }

    func run(_ operation: DevelopmentToolHomebrewOperation, formula: String) async throws -> String {
        guard Self.isValidFormula(formula) else {
            throw DevelopmentToolHomebrewError.invalidFormula
        }
        guard let homebrewURL = locateHomebrew() else {
            throw DevelopmentToolHomebrewError.unavailable
        }

        let operationID = UUID()
        currentOperationID = operationID
        do {
            try await Self.executionGate.acquire(operationID)
            try Task.checkCancellation()
        } catch {
            if currentOperationID == operationID {
                currentOperationID = nil
            }
            throw error
        }

        let command = DevelopmentToolHomebrewCommand(
            executableURL: homebrewURL,
            arguments: [operation.rawValue, "--formula", formula]
        )
        currentCommand = command

        let output: DevelopmentToolHomebrewCommand.Output
        do {
            output = try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: DevelopmentToolHomebrewCommand.Output.self) { group in
                    group.addTask { try await command.run() }
                    group.addTask { [timeout] in
                        try await command.waitUntilStarted()
                        try await Task.sleep(for: timeout)
                        command.cancel()
                        throw DevelopmentToolHomebrewError.timedOut
                    }
                    guard let first = try await group.next() else {
                        throw DevelopmentToolHomebrewError.launchFailed
                    }
                    group.cancelAll()
                    return first
                }
            } onCancel: {
                command.cancel()
            }
        } catch {
            if currentCommand === command {
                currentCommand = nil
            }
            if currentOperationID == operationID {
                currentOperationID = nil
            }
            await Self.executionGate.release(operationID)
            throw error
        }

        if currentCommand === command {
            currentCommand = nil
        }
        if currentOperationID == operationID {
            currentOperationID = nil
        }
        await Self.executionGate.release(operationID)

        let standardOutput = String(decoding: output.standardOutput, as: UTF8.self)
        let standardError = String(decoding: output.standardError, as: UTF8.self)
        let combined = [standardOutput, standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard output.exitCode == 0 else {
            throw DevelopmentToolHomebrewError.commandFailed(combined)
        }
        return combined
    }

    func cancel() async {
        currentCommand?.cancel()
        if let currentOperationID {
            await Self.executionGate.cancelWaiting(currentOperationID)
        }
    }

    private func locateHomebrew() -> URL? {
        if let configuredHomebrewURL {
            return fileManager.isExecutableFile(atPath: configuredHomebrewURL.path)
                ? configuredHomebrewURL
                : nil
        }
        return [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
            "/home/linuxbrew/.linuxbrew/bin/brew"
        ]
        .map(URL.init(fileURLWithPath:))
        .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private static func isValidFormula(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9+_.@-]*(?:/[A-Za-z0-9][A-Za-z0-9+_.@-]*){0,2}$"#,
            options: .regularExpression
        ) != nil
    }
}

private actor DevelopmentToolHomebrewExecutionGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var activeOperationID: UUID?
    private var waiters: [Waiter] = []

    func acquire(_ operationID: UUID) async throws {
        if activeOperationID == nil {
            activeOperationID = operationID
            return
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters.append(Waiter(id: operationID, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiting(operationID) }
        }
    }

    func release(_ operationID: UUID) {
        guard activeOperationID == operationID else { return }
        guard !waiters.isEmpty else {
            activeOperationID = nil
            return
        }
        let next = waiters.removeFirst()
        activeOperationID = next.id
        next.continuation.resume()
    }

    func cancelWaiting(_ operationID: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == operationID }) else {
            return
        }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}

private final class DevelopmentToolHomebrewCommand: @unchecked Sendable {
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
        try await Task.detached(priority: .userInitiated) { [self] in
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

    func waitUntilStarted() async throws {
        while true {
            try Task.checkCancellation()
            let state = lock.withLock { (hasStarted, isCancelled) }
            if state.0 { return }
            if state.1 { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func runBlocking() throws -> Output {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        environment["NONINTERACTIVE"] = "1"
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
            throw DevelopmentToolHomebrewError.launchFailed
        }

        let outputBox = HomebrewCommandDataBox()
        let errorBox = HomebrewCommandDataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputBox.set(outputPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorBox.set(errorPipe.fileHandleForReading.readDataToEndOfFile())
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

private final class HomebrewCommandDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var value: Data { lock.withLock { data } }

    func set(_ value: Data) {
        lock.withLock { data = value }
    }
}
