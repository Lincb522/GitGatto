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
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var baselines: [String: Snapshot] = [:]
    private var activePaths = Set<String>()
    private enum SnapshotInput {
        case readRepository
        case liveState(RepositoryLiveState)
    }
    private var pendingSnapshots: [String: SnapshotInput] = [:]
    private(set) var statusQueryCount = 0

    init(
        rootURL: URL? = nil,
        gitRunner: GitCommandRunner = GitCommandRunner(),
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GitGatto/Activity Ledger", isDirectory: true)
        self.gitRunner = gitRunner
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
            guard baselines[repository.path] == nil, !activePaths.contains(repository.path) else { continue }
            await recordChange(in: repository)
        }
    }

    func recordChange(in repositoryURL: URL) async {
        await recordChange(in: repositoryURL, liveState: nil)
    }

    func recordChange(in repositoryURL: URL, liveState: RepositoryLiveState?) async {
        let repository = repositoryURL.standardizedFileURL
        let path = repository.path
        // A live result arriving during a disk read may be older than that read's eventual result.
        // Re-read once at the follow-up boundary rather than applying snapshots out of order.
        pendingSnapshots[path] = activePaths.contains(path)
            ? .readRepository
            : liveState.map(SnapshotInput.liveState) ?? .readRepository
        guard !activePaths.contains(path) else { return }
        activePaths.insert(path)
        defer { activePaths.remove(path) }
        while let input = pendingSnapshots.removeValue(forKey: path), !Task.isCancelled {
            let state: RepositoryLiveState?
            switch input {
            case .readRepository: state = nil
            case let .liveState(value): state = value
            }
            guard let current = try? await snapshot(in: repository, liveState: state) else { continue }
            await record(current, in: repository)
        }
    }

    private func record(_ current: Snapshot, in repository: URL) async {
        let path = repository.path
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
        let candidates = RepositoryAgentProcessProbe.matchingAgents(for: repository)
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

    private func snapshot(in repositoryURL: URL, liveState: RepositoryLiveState?) async throws -> Snapshot {
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
        var states: [String: String] = [:]
        if let liveState {
            for change in liveState.changes {
                states[change.path] = change.indexStatus.rawValue + change.workTreeStatus.rawValue
            }
        } else {
            statusQueryCount += 1
            let status = try await gitRunner.run(
                at: repositoryURL,
                arguments: ["status", "--porcelain=v1", "-z", "--untracked-files=all"]
            )
            var fields = status.output.split(separator: 0).makeIterator()
            while let field = fields.next() {
                let value = String(decoding: field, as: UTF8.self)
                guard value.count >= 4 else { continue }
                let code = String(value.prefix(2))
                states[String(value.dropFirst(3))] = code
                if code.contains("R") || code.contains("C") { _ = fields.next() }
            }
        }
        let (head, branch) = try await (headResult, branchResult)
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
