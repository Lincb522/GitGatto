import CryptoKit
import Foundation

protocol ReproductionCapsuleServing: Sendable {
    func capsules() async throws -> [ReproductionCapsule]
    func export(
        from repositoryURL: URL,
        failingCommand: String?,
        failureOutput: String?,
        to destinationURL: URL
    ) async throws -> ReproductionCapsule
    func importArchive(at archiveURL: URL) async throws -> ReproductionCapsule
    func restore(_ capsule: ReproductionCapsule, in repositoryURL: URL) async throws -> URL
    func delete(_ capsule: ReproductionCapsule) async throws
}

actor ReproductionCapsuleService: ReproductionCapsuleServing {
    private let rootURL: URL
    private let worktreeRootURL: URL
    private let gitRunner: GitCommandRunner
    private let processRunner: ExternalProcessRunner
    private let worktreeService: any GitWorktreeServing
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        rootURL: URL? = nil,
        worktreeRootURL: URL? = nil,
        gitRunner: GitCommandRunner = GitCommandRunner(),
        processRunner: ExternalProcessRunner = ExternalProcessRunner(),
        worktreeService: any GitWorktreeServing = GitWorktreeService(),
        fileManager: FileManager = .default
    ) {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GitGatto", isDirectory: true)
        self.rootURL = rootURL ?? applicationSupport.appendingPathComponent("Capsules", isDirectory: true)
        self.worktreeRootURL = worktreeRootURL
            ?? applicationSupport.appendingPathComponent("Capsule Worktrees", isDirectory: true)
        self.gitRunner = gitRunner
        self.processRunner = processRunner
        self.worktreeService = worktreeService
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func capsules() async throws -> [ReproductionCapsule] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).compactMap { directory -> ReproductionCapsule? in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            let manifestURL = directory.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(ReproductionCapsuleManifest.self, from: data),
                  manifest.formatVersion == ReproductionCapsuleManifest.formatVersion
            else { return nil }
            return ReproductionCapsule(manifest: manifest, directoryURL: directory)
        }.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    func export(
        from repositoryURL: URL,
        failingCommand: String?,
        failureOutput: String?,
        to destinationURL: URL
    ) async throws -> ReproductionCapsule {
        let repository = repositoryURL.standardizedFileURL
        let statusResult = try await gitRunner.run(
            at: repository,
            arguments: ["status", "--porcelain=v1", "-z", "--branch", "--untracked-files=all"]
        )
        guard let status = GitParsers.statusSnapshot(from: statusResult.output) else {
            throw ReproductionCapsuleError.invalidArchive
        }
        let patch = try await gitRunner.run(
            at: repository,
            arguments: ["diff", "--binary", "--full-index", "HEAD", "--"]
        ).output
        let untracked = status.changes.filter { $0.primaryStatus == .untracked }.map(\.path)
        guard !patch.isEmpty || !untracked.isEmpty else { throw ReproductionCapsuleError.noChanges }

        let id = UUID()
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("gitgatto-capsule-\(id.uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        let patchURL = staging.appendingPathComponent("changes.patch")
        try patch.write(to: patchURL, options: .atomic)
        let untrackedRoot = staging.appendingPathComponent("untracked", isDirectory: true)
        var copied: [String] = []
        var omitted: [String] = []
        for path in untracked {
            do {
                guard Self.isSafePayloadPath(path) else {
                    omitted.append(path)
                    continue
                }
                let source = try Self.containedURL(path: path, in: repository)
                let values = try source.resourceValues(forKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                ])
                guard values.isRegularFile == true,
                      values.isSymbolicLink != true,
                      (values.fileSize ?? 0) <= 20 * 1_024 * 1_024
                else {
                    omitted.append(path)
                    continue
                }
                let destination = try Self.containedURL(path: path, in: untrackedRoot)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: source, to: destination)
                copied.append(path)
            } catch {
                omitted.append(path)
            }
        }

        let baseSHA = try await gitText(["rev-parse", "HEAD"], in: repository)
        let branchResult = try await gitRunner.run(
            at: repository,
            arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"],
            acceptedExitCodes: [0, 1]
        )
        let remoteResult = try await gitRunner.run(
            at: repository,
            arguments: ["config", "--get", "remote.origin.url"],
            acceptedExitCodes: [0, 1]
        )
        let manifest = ReproductionCapsuleManifest(
            id: id,
            formatVersion: ReproductionCapsuleManifest.formatVersion,
            createdAt: Date(),
            repositoryName: repository.lastPathComponent,
            repositoryRemote: remoteResult.exitCode == 0
                ? Self.sanitizedRemote(remoteResult.text.trimmingCharacters(in: .whitespacesAndNewlines))
                : nil,
            baseSHA: baseSHA,
            branchName: branchResult.exitCode == 0
                ? branchResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            changedPaths: status.changes.map(\.path).sorted(),
            copiedUntrackedPaths: copied.sorted(),
            omittedPaths: omitted.sorted(),
            patchSHA256: Self.sha256(patch),
            failingCommand: Self.trimmedOptional(Self.redact(failingCommand), limit: 2_000),
            failureOutput: Self.trimmedOptional(Self.redact(failureOutput), limit: 20_000),
            tools: await toolVersions()
        )
        try encoder.encode(manifest).write(
            to: staging.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        try await validateDirectory(staging)
        let archive = destinationURL.pathExtension.lowercased() == "gatto"
            ? destinationURL
            : destinationURL.appendingPathExtension("gatto")
        guard !fileManager.fileExists(atPath: archive.path) else {
            throw ReproductionCapsuleError.destinationExists
        }
        try await createArchive(from: staging, at: archive)

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let storedURL = rootURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        try fileManager.copyItem(at: staging, to: storedURL)
        return ReproductionCapsule(manifest: manifest, directoryURL: storedURL)
    }

    func importArchive(at archiveURL: URL) async throws -> ReproductionCapsule {
        guard archiveURL.pathExtension.lowercased() == "gatto",
              fileManager.fileExists(atPath: archiveURL.path)
        else { throw ReproductionCapsuleError.invalidArchive }
        let extractionRoot = fileManager.temporaryDirectory
            .appendingPathComponent("gitgatto-capsule-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: extractionRoot) }
        try fileManager.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        guard let ditto = CommandExecutableLocator.find("ditto") else {
            throw ReproductionCapsuleError.invalidArchive
        }
        _ = try await processRunner.run(
            executable: ditto,
            arguments: ["-x", "-k", archiveURL.path, extractionRoot.path],
            timeout: .seconds(60)
        )
        guard let capsuleRoot = try locateCapsuleRoot(in: extractionRoot) else {
            throw ReproductionCapsuleError.invalidArchive
        }
        try await validateDirectory(capsuleRoot)
        let manifest = try decoder.decode(
            ReproductionCapsuleManifest.self,
            from: Data(contentsOf: capsuleRoot.appendingPathComponent("manifest.json"))
        )
        guard manifest.formatVersion == ReproductionCapsuleManifest.formatVersion else {
            throw ReproductionCapsuleError.unsupportedVersion
        }
        let patch = try Data(contentsOf: capsuleRoot.appendingPathComponent("changes.patch"))
        guard Self.sha256(patch) == manifest.patchSHA256 else {
            throw ReproductionCapsuleError.checksumMismatch
        }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let destination = rootURL.appendingPathComponent(manifest.id.uuidString.lowercased(), isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            return ReproductionCapsule(manifest: manifest, directoryURL: destination)
        }
        try fileManager.copyItem(at: capsuleRoot, to: destination)
        return ReproductionCapsule(manifest: manifest, directoryURL: destination)
    }

    func restore(_ capsule: ReproductionCapsule, in repositoryURL: URL) async throws -> URL {
        let repository = repositoryURL.standardizedFileURL
        let exists = try await gitRunner.run(
            at: repository,
            arguments: ["cat-file", "-e", "\(capsule.manifest.baseSHA)^{commit}"],
            acceptedExitCodes: [0, 1, 128]
        )
        guard exists.exitCode == 0 else { throw ReproductionCapsuleError.baseCommitMissing }
        try fileManager.createDirectory(at: worktreeRootURL, withIntermediateDirectories: true)
        let suffix = capsule.manifest.id.uuidString.lowercased().prefix(8)
        let destination = worktreeRootURL
            .appendingPathComponent("\(capsule.manifest.repositoryName)-\(suffix)", isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw ReproductionCapsuleError.destinationExists
        }
        let branch = "gatto/capsule-\(suffix)"
        try await worktreeService.createWorktree(
            branch: branch,
            startPoint: capsule.manifest.baseSHA,
            destination: destination,
            in: repository
        )
        do {
            let patchURL = capsule.directoryURL.appendingPathComponent("changes.patch")
            if (try? patchURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 > 0 {
                _ = try await gitRunner.run(
                    at: destination,
                    arguments: ["apply", "--index", "--binary", "--", patchURL.path]
                )
                _ = try await gitRunner.run(
                    at: destination,
                    arguments: ["reset", "--mixed", "--quiet", "HEAD"]
                )
            }
            let sourceRoot = capsule.directoryURL.appendingPathComponent("untracked", isDirectory: true)
            for path in capsule.manifest.copiedUntrackedPaths {
                let source = try Self.containedURL(path: path, in: sourceRoot)
                let target = try Self.containedURL(path: path, in: destination)
                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: source, to: target)
            }
            return destination
        } catch {
            if let worktrees = try? await worktreeService.worktrees(in: repository),
               let worktree = worktrees.first(where: {
                   $0.path.standardizedFileURL == destination.standardizedFileURL
               })
            {
                try? await worktreeService.removeWorktree(worktree, force: true, in: repository)
            }
            throw error
        }
    }

    func delete(_ capsule: ReproductionCapsule) async throws {
        guard capsule.directoryURL.standardizedFileURL.path.hasPrefix(rootURL.standardizedFileURL.path + "/") else {
            throw ReproductionCapsuleError.unsafePath(capsule.directoryURL.path)
        }
        try fileManager.removeItem(at: capsule.directoryURL)
    }

    private func createArchive(from directory: URL, at archive: URL) async throws {
        guard let ditto = CommandExecutableLocator.find("ditto") else {
            throw ReproductionCapsuleError.invalidArchive
        }
        _ = try await processRunner.run(
            executable: ditto,
            arguments: ["-c", "-k", "--norsrc", "--keepParent", directory.path, archive.path],
            timeout: .seconds(60)
        )
    }

    private func locateCapsuleRoot(in extractionRoot: URL) throws -> URL? {
        if fileManager.fileExists(atPath: extractionRoot.appendingPathComponent("manifest.json").path) {
            return extractionRoot
        }
        let children = try fileManager.contentsOfDirectory(
            at: extractionRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return children.first {
            fileManager.fileExists(atPath: $0.appendingPathComponent("manifest.json").path)
        }
    }

    private func validateDirectory(_ directory: URL) async throws {
        let root = directory.standardizedFileURL.path
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { throw ReproductionCapsuleError.invalidArchive }
        let entries = enumerator.compactMap { $0 as? URL }
        var entryCount = 0
        for entry in entries {
            entryCount += 1
            guard entryCount <= 10_000,
                  entry.standardizedFileURL.path.hasPrefix(root + "/")
            else { throw ReproductionCapsuleError.invalidArchive }
            let values = try entry.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard values.isSymbolicLink != true else {
                throw ReproductionCapsuleError.unsafePath(entry.path)
            }
        }
    }

    private func toolVersions() async -> [ReproductionCapsuleTool] {
        let probes: [(String, String, [String])] = [
            ("Git", "git", ["--version"]),
            ("Swift", "swift", ["--version"]),
            ("Xcode", "xcodebuild", ["-version"]),
            ("Node.js", "node", ["--version"]),
            ("Python", "python3", ["--version"]),
        ]
        var tools: [ReproductionCapsuleTool] = []
        for (name, executableName, arguments) in probes {
            guard let executable = CommandExecutableLocator.find(executableName),
                  let result = try? await processRunner.run(
                      executable: executable,
                      arguments: arguments,
                      timeout: .seconds(5)
                  )
            else { continue }
            let version = [result.outputText, result.errorText]
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " · ")
            if !version.isEmpty {
                tools.append(ReproductionCapsuleTool(name: name, version: String(version.prefix(300))))
            }
        }
        return tools
    }

    private func gitText(_ arguments: [String], in repositoryURL: URL) async throws -> String {
        try await gitRunner.run(at: repositoryURL, arguments: arguments)
            .text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSafePayloadPath(_ path: String) -> Bool {
        guard (try? CodeProvenanceService.safeRelativePath(path)) != nil else { return false }
        let components = path.lowercased().split(separator: "/").map(String.init)
        let name = components.last ?? ""
        let deniedNames: Set<String> = [
            ".env", ".env.local", ".env.production", ".env.development",
            "id_rsa", "id_ed25519", "credentials", "credentials.json",
            "secrets.json", ".netrc", ".npmrc", ".pypirc",
        ]
        let deniedExtensions: Set<String> = [
            "pem", "key", "p12", "pfx", "mobileprovision", "keystore",
        ]
        return !deniedNames.contains(name)
            && !name.hasPrefix(".env.")
            && !deniedExtensions.contains(URL(fileURLWithPath: name).pathExtension)
            && !components.contains(".ssh")
    }

    private static func sanitizedRemote(_ value: String) -> String {
        if var components = URLComponents(string: value), components.host != nil {
            components.user = nil
            components.password = nil
            return components.string ?? value
        }
        guard let at = value.firstIndex(of: "@"),
              let colon = value[at...].firstIndex(of: ":")
        else { return value }
        let user = value[..<at].lowercased()
        return user == "git" ? value : String(value[value.index(after: at)...colon]) + String(value[value.index(after: colon)...])
    }

    private static func redact(_ value: String?) -> String? {
        guard var value else { return nil }
        let replacements: [(String, String)] = [
            (#"(?i)(https?://)[^/@\s]+@"#, "$1***@"),
            (#"(?i)\b(?:gh[pousr]|github_pat)_[A-Za-z0-9_]+\b"#, "***"),
            (#"(?i)(authorization:\s*(?:bearer|token)\s+)[^\s]+"#, "$1***"),
            (#"(?i)(--?(?:token|password|secret|api[-_]?key)(?:=|\s+))[^\s]+"#, "$1***"),
        ]
        for (pattern, replacement) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            value = regex.stringByReplacingMatches(
                in: value,
                range: range,
                withTemplate: replacement
            )
        }
        return value
    }

    private static func containedURL(path: String, in root: URL) throws -> URL {
        guard let safe = try? CodeProvenanceService.safeRelativePath(path) else {
            throw ReproductionCapsuleError.unsafePath(path)
        }
        let root = root.standardizedFileURL
        let result = root.appendingPathComponent(safe).standardizedFileURL
        guard result.path.hasPrefix(root.path + "/") else {
            throw ReproductionCapsuleError.unsafePath(path)
        }
        return result
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func trimmedOptional(_ value: String?, limit: Int) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(limit))
    }
}
