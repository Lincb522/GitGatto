import Foundation

struct AIAPIToolRunner: AIAPIToolExecuting {
    let directory: URL
    let writableDirectories: [URL]
    let allowsNetwork: Bool
    var additionalReadableDirectories: [URL] = []

    func execute(_ call: AIAPIToolCall) async throws -> AIAPIToolOutput {
        guard let data = call.function.arguments.data(using: .utf8), data.count <= 256_000 else {
            throw AIAPIError.invalidTool
        }
        let arguments: [String]
        let input: String?
        let event: CodexOperationEvent
        switch call.function.name {
        case "run_command":
            struct Command: Decodable { var arguments: [String] }
            guard let command = try? JSONDecoder().decode(Command.self, from: data),
                  let first = command.arguments.first, !first.isEmpty, !first.hasPrefix("-"),
                  command.arguments.count < 256,
                  command.arguments.allSatisfy({ !$0.contains("\0") }) else { throw AIAPIError.invalidTool }
            arguments = ["/usr/bin/env"] + command.arguments
            input = nil
            // Arguments can contain user code or sensitive output. Record only the executable.
            event = CodexOperationEvent(kind: .command, summary: URL(fileURLWithPath: first).lastPathComponent)
        case "write_file":
            struct File: Decodable { var path: String; var content: String }
            guard let file = try? JSONDecoder().decode(File.self, from: data) else { throw AIAPIError.invalidTool }
            let path = try writeTarget(file.path)
            arguments = ["/bin/sh", "-c", """
                temporary=$(mktemp "${1}.gitgatto.XXXXXX") || exit 1
                trap 'rm -f "$temporary"' EXIT
                if [ -e "$1" ]; then chmod "$(stat -f %Lp "$1")" "$temporary" || exit 1; fi
                cat > "$temporary" && mv -f "$temporary" "$1"
                """, "gitgatto-write", path.path]
            input = file.content
            event = CodexOperationEvent(kind: .fileChange, summary: file.path)
        default:
            throw AIAPIError.invalidTool
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("GitGatto-API-Tool-\(UUID())")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let profile = Self.sandboxProfile(
            directory: directory, writableDirectories: writableDirectories,
            temporaryDirectory: temporary, allowsNetwork: allowsNetwork,
            additionalReadableDirectories: additionalReadableDirectories
        )
        let invocation = CodexCommandInvocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
            arguments: ["-p", profile] + arguments, input: input, currentDirectoryURL: directory,
            environment: [
                "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "PATH": GitCommandRunner.commandPath(inheritedPath: "/usr/bin:/bin:/usr/sbin:/sbin"),
                "TMPDIR": temporary.path, "LANG": "en_US.UTF-8",
                "GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0", "GIT_PAGER": "cat",
                // API tools are credential-free. App-owned Git operations and external CLIs
                // retain their normal authentication and configuration outside this sandbox.
                "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"
            ]
        )
        let output = try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: CodexCommandOutput.self) { group in
                group.addTask { try await invocation.run() }
                group.addTask {
                    try await Task.sleep(for: .seconds(120))
                    invocation.cancel()
                    throw CodexServiceError.timedOut
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw AIAPIError.invalidResponse }
                return result
            }
        } onCancel: { invocation.cancel() }
        if call.function.name == "write_file", output.exitCode != 0 { throw AIAPIError.pathDenied }
        let result: [String: Any] = [
            "exit_code": output.exitCode,
            "stdout": call.function.name == "write_file" ? "" : String(decoding: output.standardOutput.prefix(48_000), as: UTF8.self),
            "stderr": String(decoding: output.standardError.prefix(12_000), as: UTF8.self)
        ]
        let json = try JSONSerialization.data(withJSONObject: result)
        return AIAPIToolOutput(content: String(decoding: json, as: UTF8.self), event: event)
    }

    private func writeTarget(_ path: String) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else { throw AIAPIError.pathDenied }
        let requested = directory.appendingPathComponent(path).standardizedFileURL
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: requested.path)) == nil else {
            throw AIAPIError.pathDenied
        }
        let target = requested.resolvingSymlinksInPath()
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard target.path.hasPrefix(root), writableDirectories.contains(where: {
            let allowed = $0.standardizedFileURL.resolvingSymlinksInPath().path
            return target.path.hasPrefix(allowed + "/")
        }) else { throw AIAPIError.pathDenied }
        return target
    }

    static func sandboxProfile(
        directory: URL, writableDirectories: [URL], temporaryDirectory: URL, allowsNetwork: Bool,
        additionalReadableDirectories: [URL] = []
    ) -> String {
        func quoted(_ url: URL) -> String {
            let path = AgentSandboxPath.canonical(url)
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(path)\""
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let writable = writableDirectories + [temporaryDirectory]
        let readable = [directory, temporaryDirectory] + writableDirectories + additionalReadableDirectories
        let readExceptions = readable
            .map { "(require-not (subpath \(quoted($0))))" }.joined(separator: " ")
        // Git resolves absolute worktree paths by inspecting each parent directory. Permit
        // only ancestor metadata, not listing or reading the rest of the user's home.
        let readablePaths = readable.map(AgentSandboxPath.canonical)
        var ancestors: Set<String> = []
        for path in readablePaths {
            var parent = URL(fileURLWithPath: path).deletingLastPathComponent()
            while parent.path != "/" {
                if !readablePaths.contains(where: { parent.path == $0 || parent.path.hasPrefix($0 + "/") }) {
                    ancestors.insert(parent.path)
                }
                parent.deleteLastPathComponent()
            }
        }
        let metadataExceptions = ancestors.sorted().map {
            "(require-not (literal \(quoted(URL(fileURLWithPath: $0)))))"
        }.joined(separator: " ")
        let writeExceptions = writable.map { "(require-not (subpath \(quoted($0))))" }.joined(separator: " ")
        let protected = CodexService.installerSandboxProtectedPaths() + [
            home.appendingPathComponent("Library/Keychains"), home.appendingPathComponent(".codex"),
            home.appendingPathComponent(".claude"), home.appendingPathComponent(".dsh"),
            home.appendingPathComponent(".npmrc")
        ]
        let protectedRules = protected.map { "(deny file-read* file-write* (subpath \(quoted($0))))" }.joined(separator: "\n")
        return """
        (version 1)
        (allow default)
        (deny file-write* (require-all (require-not (literal "/dev/null")) \(writeExceptions)))
        (deny file-read-data file-read-xattr (require-all (subpath \(quoted(home))) \(readExceptions)))
        (deny file-read-metadata (require-all (subpath \(quoted(home))) \(readExceptions) \(metadataExceptions)))
        \(protectedRules)
        (deny file-read* file-write* (regex #"(^|/)(\\.env(\\.[^/]*)?|credentials([^/]*)?|[^/]*\\.(pem|key))($|/)"))
        (deny mach-lookup (global-name "com.apple.securityd"))
        \(allowsNetwork ? "" : "(deny network*)")
        """
    }
}
