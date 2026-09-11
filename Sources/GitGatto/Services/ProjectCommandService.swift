import Foundation
import AppKit
import Darwin

actor ProjectCommandDiscovery {
    func discover(repository: URL, saved: [ProjectCommand] = []) throws -> [ProjectCommand] {
        var commands: [ProjectCommand] = []
        func append(_ id: String, _ title: String, _ executable: String, _ arguments: [String]) {
            commands.append(ProjectCommand(id: repository.path + ":" + id, title: title, executable: executable, arguments: arguments, repositoryPath: repository.path))
        }
        func read(_ name: String) throws -> Data? {
            let file = repository.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            guard file.resolvingSymlinksInPath().path.hasPrefix(repository.resolvingSymlinksInPath().path + "/"),
                  (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 1_000_000 else { throw ProjectToolsError(key: "path") }
            return try Data(contentsOf: file)
        }
        if let data = try read("package.json"), let package = try JSONSerialization.jsonObject(with: data) as? [String: Any], let scripts = package["scripts"] as? [String: String] {
            let manager: String
            if let declared = package["packageManager"] as? String, ["npm", "pnpm", "yarn", "bun"].contains(String(declared.split(separator: "@").first ?? "")) { manager = String(declared.split(separator: "@")[0]) }
            else if FileManager.default.fileExists(atPath: repository.appendingPathComponent("pnpm-lock.yaml").path) { manager = "pnpm" }
            else if FileManager.default.fileExists(atPath: repository.appendingPathComponent("yarn.lock").path) { manager = "yarn" }
            else { manager = "npm" }
            for name in scripts.keys.sorted() where !name.hasPrefix("-") { append("package:" + name, name, manager, ["run", name]) }
        }
        if let data = try read("Makefile"), let source = String(data: data, encoding: .utf8) {
            let regex = try NSRegularExpression(pattern: #"^([A-Za-z0-9_][A-Za-z0-9_.-]*):(?:[^=]|$)"#, options: .anchorsMatchLines)
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                if let range = Range(match.range(at: 1), in: source) { let target = String(source[range]); append("make:" + target, target, "make", [target]) }
            }
        }
        if try read("Package.swift") != nil {
            for verb in ["build", "test", "run"] { append("swift:" + verb, "swift " + verb, "swift", [verb]) }
        }
        let pinned = saved.filter { $0.repositoryPath == repository.path }
        var seen = Set<String>()
        return (pinned + commands).filter { seen.insert($0.id).inserted }
    }
}

struct ProjectCommandEvent: Sendable {
    enum Kind: Sendable { case output(String), finished(Int32), stopped, failed(String) }
    let kind: Kind
}

// Each runner owns exactly one process group. No process-name or port-based killing is used.
final class ProjectCommandProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var cancelled = false
    private var finished = false
    private let queue = DispatchQueue(label: "GitGatto.project-command", qos: .utility)

    func events(command: ProjectCommand) -> AsyncStream<ProjectCommandEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(512)) { continuation in
            continuation.onTermination = { @Sendable [weak self] _ in self?.cancel() }
            queue.async { [self] in execute(command, continuation: continuation) }
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            if pid > 0, !finished { kill(-pid, SIGTERM) }
        }
    }

    func stopAndWait() {
        cancel()
        queue.sync { }
    }

    private func execute(_ command: ProjectCommand, continuation: AsyncStream<ProjectCommandEvent>.Continuation) {
        let termination = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            self?.stopAndWait()
        }
        defer { NotificationCenter.default.removeObserver(termination); continuation.finish() }
        guard (1...86400).contains(command.timeoutSeconds), !command.executable.isEmpty,
              !([command.executable] + command.arguments).contains(where: { $0.contains("\0") }) else {
            continuation.yield(.init(kind: .failed(L10n.text("tools.error.command")))); return
        }
        let script = "cd -- \"$1\" || exit; shift; exec \"$@\""
        let argv = ["/bin/sh", "-c", script, "gitgatto-command", command.repositoryPath, command.executable] + command.arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = GitCommandRunner.commandPath(inheritedPath: env["PATH"])
        env["NO_COLOR"] = "1"; env["TERM"] = "dumb"
        let args = argv.map { strdup($0) }; let environment = env.map { strdup($0.key + "=" + $0.value) }
        defer { args.forEach { free($0) }; environment.forEach { free($0) } }
        var output: [Int32] = [0, 0]
        guard pipe(&output) == 0 else { continuation.yield(.init(kind: .failed(L10n.text("tools.error.command")))); return }
        defer { close(output[0]) }
        var actions: posix_spawn_file_actions_t?; var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, output[1], STDERR_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addclose(&actions, output[0]); posix_spawn_file_actions_addclose(&actions, output[1])
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)); posix_spawnattr_setpgroup(&attributes, 0)
        var child: pid_t = 0
        var arguments = args + [nil], envp = environment + [nil]
        let error = posix_spawn(&child, "/bin/sh", &actions, &attributes, &arguments, &envp)
        close(output[1])
        guard error == 0 else { continuation.yield(.init(kind: .failed(String(cString: strerror(error))))); return }
        lock.withLock { pid = child; if cancelled { kill(-child, SIGTERM) } }
        _ = fcntl(output[0], F_SETFL, O_NONBLOCK)
        let deadline = Date().addingTimeInterval(Double(command.timeoutSeconds))
        var stopAt: Date?; var status: Int32 = 0; var pending = Data(); var exited = false
        var timedOut = false; var redactor = ProjectCommandLogFilter()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while !exited {
            if Date() >= deadline { timedOut = true; cancel() }
            if lock.withLock({ cancelled }) {
                if stopAt == nil { stopAt = Date() }
                if let stopAt, Date().timeIntervalSince(stopAt) > 2 { lock.withLock { if !finished { kill(-child, SIGKILL) } } }
            }
            var descriptor = pollfd(fd: output[0], events: Int16(POLLIN), revents: 0)
            _ = poll(&descriptor, 1, 100)
            let count = read(output[0], &buffer, buffer.count)
            if count > 0 { pending.append(contentsOf: buffer.prefix(count)) }
            while let newline = pending.firstIndex(of: 10) {
                let line = String(decoding: pending[...newline], as: UTF8.self)
                pending.removeSubrange(...newline)
                continuation.yield(.init(kind: .output(redactor.consume(line))))
            }
            if pending.count > 32768 { pending.removeAll(); continuation.yield(.init(kind: .output(L10n.text("tools.output.omitted") + "\n"))) }
            var info = siginfo_t()
            if waitid(P_PID, id_t(child), &info, WEXITED | WNOHANG | WNOWAIT) == 0 { exited = info.si_pid == child }
            else if errno != EINTR {
                lock.withLock { finished = true; pid = 0 }
                continuation.yield(.init(kind: .failed(String(cString: strerror(errno))))); return
            }
        }
        // WNOWAIT keeps the leader unreaped, so its PID cannot be reused before group cleanup.
        lock.withLock { kill(-child, SIGKILL); finished = true; pid = 0 }
        while waitpid(child, &status, 0) == -1 && errno == EINTR { }
        while true {
            let count = read(output[0], &buffer, buffer.count)
            if count <= 0 { break }; pending.append(contentsOf: buffer.prefix(count))
            if pending.count > 65536 { break }
        }
        if !pending.isEmpty {
            let tail = String(decoding: pending, as: UTF8.self).components(separatedBy: "\n").map { redactor.consume($0 + "\n") }.joined()
            continuation.yield(.init(kind: .output(tail)))
        }
        if timedOut { continuation.yield(.init(kind: .failed(L10n.text("tools.error.timeout")))) }
        else if lock.withLock({ cancelled }) { continuation.yield(.init(kind: .stopped)) }
        else { continuation.yield(.init(kind: .finished((status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)))) }
    }
}

struct ProjectCommandLogFilter {
    private var privateBlock = false
    mutating func consume(_ line: String) -> String {
        if line.contains("-----BEGIN "), line.contains("PRIVATE KEY-----") { privateBlock = true; return "[redacted]\n" }
        if privateBlock {
            if line.contains("-----END "), line.contains("PRIVATE KEY-----") { privateBlock = false }
            return ""
        }
        return ProjectCommandOutput.redact(line)
    }
}

enum ProjectCommandOutput {
    static func redact(_ text: String) -> String {
        var value = text
        for pattern in [#"(?i)(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)"#,
                        #"(?i)(?:authorization["\s]*[:=]|(?:api[_-]?key|token|password|secret)["\s]*[:=])[^\r\n]+"#,
                        #"(?i)https?://[^/@\s]+:[^/@\s]+@"#] {
            value = value.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression)
        }
        return value
    }
    static func localURL(_ string: String) -> URL? {
        guard let url = URL(string: string), ["http", "https"].contains(url.scheme),
              ["localhost", "127.0.0.1", "::1", "[::1]"].contains(url.host), url.user == nil, url.password == nil else { return nil }
        return url
    }
}
