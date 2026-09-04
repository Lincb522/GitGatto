import CryptoKit
import Foundation

protocol RepositoryActivityLedgerServing: Sendable {
    func seed(_ repositoryURLs: [URL]) async
    func recordChange(in repositoryURL: URL) async
    func events(for repositoryURL: URL) async -> [RepositoryActivityEvent]
    func clearEvents(for repositoryURL: URL) async throws
}

actor RepositoryActivityLedger: RepositoryActivityLedgerServing {
    static let shared = RepositoryActivityLedger()

    private let rootURL: URL
    private let gitRunner: GitCommandRunner
    private let processRunner: ExternalProcessRunner
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var baselines: [String: Snapshot] = [:]
    private var activePaths = Set<String>()

    init(
        rootURL: URL? = nil,
        gitRunner: GitCommandRunner = GitCommandRunner(),
        processRunner: ExternalProcessRunner = ExternalProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GitGatto/Activity Ledger", isDirectory: true)
        self.gitRunner = gitRunner
        self.processRunner = processRunner
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func seed(_ repositoryURLs: [URL]) async {
        for repositoryURL in repositoryURLs {
            let repository = repositoryURL.standardizedFileURL
            guard baselines[repository.path] == nil,
                  let snapshot = try? await snapshot(in: repository)
            else { continue }
            baselines[repository.path] = snapshot
        }
    }

    func recordChange(in repositoryURL: URL) async {
        let repository = repositoryURL.standardizedFileURL
        let path = repository.path
        guard !activePaths.contains(path) else { return }
        activePaths.insert(path)
        defer { activePaths.remove(path) }
        guard let current = try? await snapshot(in: repository) else { return }
        guard let previous = baselines[path] else {
            baselines[path] = current
            return
        }
        baselines[path] = current
        guard previous != current else { return }

        var changed = Set(
            Set(previous.status.keys).union(current.status.keys).filter {
                previous.status[$0] != current.status[$0]
            }
        )
        let refChanged = previous.headSHA != current.headSHA || previous.branch != current.branch
        if refChanged,
           let old = previous.headSHA,
           let new = current.headSHA,
           let committedPaths = try? await gitRunner.run(
               at: repository,
               arguments: ["diff", "--name-only", "-z", old, new]
           ).output.split(separator: 0).map({ String(decoding: $0, as: UTF8.self) })
        {
            changed.formUnion(committedPaths)
        }
        guard !changed.isEmpty || refChanged else { return }
        let candidates = await matchingAgents(for: repository)
        let confidence: RepositoryActivityConfidence
        switch candidates.count {
        case 0: confidence = .unknown
        case 1: confidence = refChanged ? .high : .medium
        default: confidence = .ambiguous
        }
        let deleted = changed.filter {
            current.status[$0]?.contains("D") == true
                || (current.status[$0] == nil && previous.status[$0] != nil)
        }.sorted()
        let event = RepositoryActivityEvent(
            repositoryPath: path,
            previousHeadSHA: previous.headSHA,
            headSHA: current.headSHA,
            previousBranch: previous.branch,
            branch: current.branch,
            changedPaths: changed.sorted(),
            deletedPaths: deleted,
            refChanged: refChanged,
            candidates: candidates,
            confidence: confidence
        )
        try? persist(event)
    }

    func events(for repositoryURL: URL) async -> [RepositoryActivityEvent] {
        let repository = repositoryURL.standardizedFileURL
        return (try? load(repositoryPath: repository.path)) ?? []
    }

    func clearEvents(for repositoryURL: URL) async throws {
        let url = eventFileURL(repositoryPath: repositoryURL.standardizedFileURL.path)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func snapshot(in repositoryURL: URL) async throws -> Snapshot {
        async let headResult = gitRunner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "--verify", "HEAD"],
            acceptedExitCodes: [0, 128]
        )
        async let branchResult = gitRunner.run(
            at: repositoryURL,
            arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"],
            acceptedExitCodes: [0, 1]
        )
        async let statusResult = gitRunner.run(
            at: repositoryURL,
            arguments: ["status", "--porcelain=v1", "-z", "--untracked-files=all"]
        )
        let (head, branch, status) = try await (headResult, branchResult, statusResult)
        var states: [String: String] = [:]
        for field in status.output.split(separator: 0) {
            let value = String(decoding: field, as: UTF8.self)
            guard value.count >= 4 else { continue }
            let code = String(value.prefix(2))
            let path = String(value.dropFirst(3))
            states[path] = code
        }
        return Snapshot(
            headSHA: head.exitCode == 0
                ? head.text.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            branch: branch.exitCode == 0
                ? branch.text.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            status: states
        )
    }

    private func matchingAgents(for repositoryURL: URL) async -> [RepositoryActivityAgent] {
        guard let ps = CommandExecutableLocator.find("ps"),
              let lsof = CommandExecutableLocator.find("lsof"),
              let result = try? await processRunner.run(
                  executable: ps,
                  arguments: ["-axo", "pid=,comm="],
                  timeout: .seconds(4)
              )
        else { return [] }
        let known = [
            "codex", "claude", "gemini", "cursor", "copilot", "aider",
            "opencode", "amp", "goose", "continue", "zed-agent",
        ]
        let processes: [(Int32, String)] = result.outputText.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2,
                  let pid = Int32(parts[0]) else { return nil }
            let executable = URL(fileURLWithPath: String(parts[1])).lastPathComponent.lowercased()
            guard let name = known.first(where: { executable.contains($0) }) else { return nil }
            return (pid, name)
        }
        var matches: [RepositoryActivityAgent] = []
        for (pid, name) in processes.prefix(24) {
            guard let cwd = try? await processRunner.run(
                executable: lsof,
                arguments: ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"],
                acceptedExitCodes: [0, 1],
                timeout: .seconds(2)
            ).outputText.split(separator: "\n").first(where: { $0.hasPrefix("n/") })
            else { continue }
            let path = String(cwd.dropFirst())
            if path == repositoryURL.path || path.hasPrefix(repositoryURL.path + "/") {
                matches.append(RepositoryActivityAgent(processID: pid, name: name))
            }
        }
        return matches
    }

    private func persist(_ event: RepositoryActivityEvent) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        var values = try load(repositoryPath: event.repositoryPath)
        if let latest = values.first,
           latest.headSHA == event.headSHA,
           latest.branch == event.branch,
           latest.changedPaths == event.changedPaths,
           latest.candidates == event.candidates,
           event.occurredAt.timeIntervalSince(latest.occurredAt) < 2
        {
            return
        }
        values.insert(event, at: 0)
        if values.count > 500 { values.removeLast(values.count - 500) }
        try encoder.encode(values).write(
            to: eventFileURL(repositoryPath: event.repositoryPath),
            options: .atomic
        )
    }

    private func load(repositoryPath: String) throws -> [RepositoryActivityEvent] {
        let url = eventFileURL(repositoryPath: repositoryPath)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try decoder.decode([RepositoryActivityEvent].self, from: Data(contentsOf: url))
    }

    private func eventFileURL(repositoryPath: String) -> URL {
        let digest = SHA256.hash(data: Data(repositoryPath.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return rootURL.appendingPathComponent(digest).appendingPathExtension("json")
    }

    private struct Snapshot: Sendable, Equatable {
        let headSHA: String?
        let branch: String?
        let status: [String: String]
    }
}
