import Foundation

protocol GitEnvironmentDiagnosticServing: Sendable {
    func diagnose(repositoryURL: URL) async throws -> RepositoryDiagnostics
    func installLocalLFS(repositoryURL: URL) async throws
    func makeHookExecutable(_ hook: GitHookRecord) async throws
}

actor GitEnvironmentDiagnosticService: GitEnvironmentDiagnosticServing {
    private let runner: GitCommandRunner

    init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    func diagnose(repositoryURL: URL) async throws -> RepositoryDiagnostics {
        let rootResult = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "--show-toplevel"]
        )
        let root = URL(
            fileURLWithPath: rootResult.text.trimmingCharacters(in: .whitespacesAndNewlines),
            isDirectory: true
        )
        let gitVersion = try await runner.run(at: root, arguments: ["version"])
        let integrity = try await runner.run(
            at: root,
            arguments: ["fsck", "--connectivity-only", "--no-dangling", "--no-progress"],
            acceptedExitCodes: [0, 1, 2, 128]
        )
        let userName = try await configValue("user.name", in: root)
        let userEmail = try await configValue("user.email", in: root)
        let hooksDirectory = try await resolvedHooksDirectory(in: root)
        let hooks = hookRecords(in: hooksDirectory)

        let lfsVersionResult = try await runner.run(
            at: root,
            arguments: ["lfs", "version"],
            acceptedExitCodes: [0, 1, 128, 129]
        )
        let lfsVersion = lfsVersionResult.exitCode == 0
            ? lfsVersionResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let lfsError = lfsVersionResult.exitCode == 0
            ? nil
            : boundedMessage(lfsVersionResult)
        let lfsFilter = try await configValue("filter.lfs.process", in: root)
        let usesLFS = try await repositoryUsesLFS(root)
        let lfsTrackedFileCount: Int
        if lfsVersion != nil {
            let tracked = try await runner.run(
                at: root,
                arguments: ["lfs", "ls-files", "-n"],
                acceptedExitCodes: [0, 1]
            )
            lfsTrackedFileCount = tracked.text
                .split(whereSeparator: \Character.isNewline)
                .filter { !$0.isEmpty }
                .count
        } else {
            lfsTrackedFileCount = 0
        }

        return RepositoryDiagnostics(
            generatedAt: Date(),
            gitExecutablePath: "/usr/bin/git",
            gitVersion: gitVersion.text.trimmingCharacters(in: .whitespacesAndNewlines),
            repositoryRoot: root,
            objectDatabaseHealthy: integrity.exitCode == 0,
            objectDatabaseMessage: integrity.exitCode == 0 ? nil : boundedMessage(integrity),
            userName: userName,
            userEmail: userEmail,
            lfsVersion: lfsVersion,
            lfsError: lfsError,
            usesLFS: usesLFS,
            lfsFilterConfigured: lfsFilter?.contains("git-lfs") == true,
            lfsTrackedFileCount: lfsTrackedFileCount,
            hooksDirectory: hooksDirectory,
            hooksDirectoryExists: FileManager.default.fileExists(atPath: hooksDirectory.path),
            hooks: hooks
        )
    }

    func installLocalLFS(repositoryURL: URL) async throws {
        _ = try await runner.run(
            at: repositoryURL,
            arguments: ["lfs", "install", "--local"]
        )
    }

    func makeHookExecutable(_ hook: GitHookRecord) async throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: hook.url.path)
        let current = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: current | 0o111)],
            ofItemAtPath: hook.url.path
        )
    }

    private func configValue(_ key: String, in repositoryURL: URL) async throws -> String? {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["config", "--get", key],
            acceptedExitCodes: [0, 1]
        )
        guard result.exitCode == 0 else { return nil }
        let value = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func resolvedHooksDirectory(in repositoryURL: URL) async throws -> URL {
        if let configured = try await configValue("core.hooksPath", in: repositoryURL) {
            let expanded = (configured as NSString).expandingTildeInPath
            if expanded.hasPrefix("/") {
                return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
            }
            return repositoryURL.appendingPathComponent(expanded, isDirectory: true).standardizedFileURL
        }
        let gitDirectory = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "--absolute-git-dir"]
        )
        return URL(
            fileURLWithPath: gitDirectory.text.trimmingCharacters(in: .whitespacesAndNewlines),
            isDirectory: true
        ).appendingPathComponent("hooks", isDirectory: true)
    }

    private func repositoryUsesLFS(_ repositoryURL: URL) async throws -> Bool {
        let files = try await runner.run(at: repositoryURL, arguments: ["ls-files", "-z"])
        let attributePaths = files.output
            .split(separator: 0)
            .map { String(decoding: $0, as: UTF8.self) }
            .filter { ($0 as NSString).lastPathComponent == ".gitattributes" }
        for path in attributePaths {
            let url = repositoryURL.appendingPathComponent(path)
            if let contents = try? String(contentsOf: url, encoding: .utf8),
               contents.contains("filter=lfs") {
                return true
            }
        }
        return false
    }

    private func hookRecords(in directory: URL) -> [GitHookRecord] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard !url.lastPathComponent.hasSuffix(".sample"),
                  let values = try? url.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
                  ),
                  values.isRegularFile == true || values.isSymbolicLink == true else { return nil }
            return GitHookRecord(
                name: url.lastPathComponent,
                url: url,
                isExecutable: FileManager.default.isExecutableFile(atPath: url.path),
                isSymbolicLink: values.isSymbolicLink == true,
                size: Int64(values.fileSize ?? 0)
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func boundedMessage(_ result: GitCommandResult) -> String? {
        let output = String(decoding: result.output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let error = String(decoding: result.errorOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = [output, error].filter { !$0.isEmpty }.joined(separator: "\n")
        return message.isEmpty ? nil : String(message.prefix(8_000))
    }
}
