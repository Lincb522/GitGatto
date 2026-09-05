import CryptoKit
import Foundation

/// Compares recoverable working content, rather than subtracting two diffs against different HEADs.
struct RepositoryBackupComparison {
    let manifest: RepositoryBackupManifest
    let workspace: URL
    let repository: URL
    let currentPaths: Set<String>
    let currentHead: String?
    let currentBranch: String?
    private let fileManager = FileManager.default

    struct Result {
        let changedPaths: [String]
        let changedLines: Int
        let deletedPaths: [String]
        let lostPaths: [String]
        let historyRewritten: Bool
    }

    func run() async throws -> Result {
        let backup = manifest.backup
        let headChanged = backup.headSHA != currentHead
        var committedPaths = Set<String>()
        var advancesHistory = false
        if headChanged, let currentHead {
            if let previous = backup.headSHA {
                let diff = try await git(["diff", "--no-renames", "--name-only", "-z", previous, currentHead, "--"])
                committedPaths = Set(paths(diff.standardOutput))
                let ancestry = try await git(["merge-base", "--is-ancestor", previous, currentHead], accepted: [0, 1])
                advancesHistory = ancestry.exitCode == 0 && backup.branchName == currentBranch
            } else {
                committedPaths = Set(paths(try await git(["ls-tree", "-r", "--name-only", "-z", currentHead]).standardOutput))
                advancesHistory = true
            }
        }
        let historyRewritten = backup.headSHA != nil && headChanged
            && backup.branchName == currentBranch && !advancesHistory
        let omitted = Set(manifest.omittedPaths)
        let copied = Set(manifest.copiedPaths)
        let deleted = Set(manifest.deletedPaths)
        let pathsToCompare = currentPaths.union(copied).union(deleted).union(committedPaths).subtracting(omitted).sorted()
        let tree = try await baselineTree(paths: pathsToCompare)
        let candidates = pathsToCompare.filter { tree[$0]?.mode != "160000" }
        guard !candidates.isEmpty else {
            return Result(changedPaths: [], changedLines: 0, deletedPaths: [], lostPaths: [], historyRewritten: historyRewritten)
        }

        let scratch = fileManager.temporaryDirectory.appendingPathComponent("GitGatto-Backup-Compare-\(UUID().uuidString)")
        let before = scratch.appendingPathComponent("before")
        let after = scratch.appendingPathComponent("after")
        try fileManager.createDirectory(at: before, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: scratch) }
        try fileManager.createDirectory(at: after, withIntermediateDirectories: true)
        var blobs: [(path: String, entry: TreeEntry, destination: URL)] = []
        var beforeHashes: [String: String] = [:]
        var afterHashes: [String: String] = [:]
        for (index, path) in candidates.enumerated() {
            try Task.checkCancellation()
            let currentURL = try contained(path, in: repository)
            if copied.contains(path), fileManager.contentsEqual(
                atPath: try contained(path, in: workspace).path, andPath: currentURL.path
            ) { continue }
            let oldURL = before.appendingPathComponent(String(index))
            let newURL = after.appendingPathComponent(String(index))
            if copied.contains(path) {
                try fileManager.copyItem(at: contained(path, in: workspace), to: oldURL)
                beforeHashes[path] = try signature(oldURL)
            } else if !deleted.contains(path), let entry = tree[path] {
                blobs.append((path, entry, oldURL))
            }
            if try itemExists(currentURL),
               try fileManager.attributesOfItem(atPath: currentURL.path)[.type] as? FileAttributeType != .typeDirectory {
                try fileManager.copyItem(at: currentURL, to: newURL)
                afterHashes[path] = try signature(newURL)
            }
        }

        // Batch object reads without staging, writing Git objects, or changing the source index.
        var cursor = 0
        while cursor < blobs.count {
            try Task.checkCancellation()
            var end = cursor
            var bytes = 0
            repeat {
                bytes += blobs[end].entry.size
                end += 1
            } while end < blobs.count && bytes + blobs[end].entry.size <= 8 * 1024 * 1024
            let batch = Array(blobs[cursor..<end])
            let input = Data(batch.map { $0.entry.object + "\n" }.joined().utf8)
            let output = try await git(["cat-file", "--batch"], input: input).standardOutput
            var offset = output.startIndex
            for item in batch {
                guard let newline = output[offset...].firstIndex(of: 10) else { throw CocoaError(.fileReadCorruptFile) }
                let header = String(decoding: output[offset..<newline], as: UTF8.self).split(separator: " ")
                guard header.count == 3, header[0] == item.entry.object, header[1] == "blob",
                      let count = Int(header[2]), count == item.entry.size,
                      output.distance(from: newline, to: output.endIndex) >= count + 2
                else { throw CocoaError(.fileReadCorruptFile) }
                let start = output.index(after: newline)
                let finish = output.index(start, offsetBy: count)
                let content = output.subdata(in: start..<finish)
                if item.entry.mode == "120000" {
                    guard let target = String(data: content, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
                    try fileManager.createSymbolicLink(atPath: item.destination.path, withDestinationPath: target)
                } else {
                    try content.write(to: item.destination)
                }
                beforeHashes[item.path] = try signature(item.destination)
                offset = output.index(after: finish)
            }
            cursor = end
        }

        var addedByHash: [String: [String]] = [:]
        for path in candidates where beforeHashes[path] == nil {
            if let hash = afterHashes[path] { addedByHash[hash, default: []].append(path) }
        }
        var renamed = Set<String>()
        for path in candidates where afterHashes[path] == nil {
            if let hash = beforeHashes[path], var destinations = addedByHash[hash], !destinations.isEmpty {
                destinations.removeLast()
                addedByHash[hash] = destinations
                renamed.insert(path)
            }
        }
        let changed = candidates.filter { beforeHashes[$0] != afterHashes[$0] }
        let removed = candidates.filter {
            beforeHashes[$0] != nil && afterHashes[$0] == nil && !renamed.contains($0)
                && !(advancesHistory && committedPaths.contains($0))
        }
        let lost = candidates.filter {
            copied.contains($0) && afterHashes[$0] != nil && beforeHashes[$0] != afterHashes[$0]
                && !currentPaths.contains($0) && !(advancesHistory && committedPaths.contains($0))
        }
        let numstat = try await git([
            "diff", "--no-index", "--no-ext-diff", "--no-textconv", "--find-renames", "--numstat", "--",
            before.path, after.path,
        ], accepted: [0, 1])
        let lines = numstat.outputText.split(whereSeparator: \.isNewline).reduce(0) { total, line in
            let fields = line.split(separator: "\t", maxSplits: 2)
            return total + (fields.first.flatMap { Int($0) } ?? 0)
                + (fields.count > 1 ? Int(fields[1]) ?? 0 : 0)
        }
        return Result(changedPaths: changed, changedLines: lines, deletedPaths: removed,
                      lostPaths: lost, historyRewritten: historyRewritten)
    }

    private struct TreeEntry {
        let mode: String
        let object: String
        let size: Int
    }

    private func baselineTree(paths: [String]) async throws -> [String: TreeEntry] {
        guard let head = manifest.backup.headSHA, !paths.isEmpty else { return [:] }
        var output = Data()
        var cursor = 0
        while cursor < paths.count {
            var end = cursor
            var bytes = 0
            repeat {
                bytes += paths[end].utf8.count + 1
                end += 1
            } while end < paths.count && bytes + paths[end].utf8.count < 32_768
            output.append(try await git(["ls-tree", "-r", "-l", "-z", head, "--"] + paths[cursor..<end]).standardOutput)
            cursor = end
        }
        var entries: [String: TreeEntry] = [:]
        for record in output.split(separator: 0) {
            guard let tab = record.firstIndex(of: 9) else { throw CocoaError(.fileReadCorruptFile) }
            let fields = String(decoding: record[..<tab], as: UTF8.self).split(whereSeparator: \.isWhitespace)
            guard fields.count == 4 else { throw CocoaError(.fileReadCorruptFile) }
            let path = String(decoding: record[record.index(after: tab)...], as: UTF8.self)
            entries[path] = TreeEntry(mode: String(fields[0]), object: String(fields[2]), size: Int(fields[3]) ?? 0)
        }
        return entries
    }

    private func git(_ arguments: [String], accepted: Set<Int32> = [0], input: Data = Data()) async throws -> ExternalProcessResult {
        try await ExternalProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["--no-optional-locks", "-C", repository.path] + arguments,
            environment: ["LC_ALL": "C", "GIT_TERMINAL_PROMPT": "0", "GIT_LITERAL_PATHSPECS": "1"],
            input: input, acceptedExitCodes: accepted, timeout: .seconds(30))
    }

    private func paths(_ data: Data) -> [String] {
        data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
    }

    private func contained(_ path: String, in root: URL) throws -> URL {
        let result = root.appendingPathComponent(path).standardizedFileURL
        guard !path.hasPrefix("/"), result.path.hasPrefix(root.standardizedFileURL.path + "/") else {
            throw RepositoryBackupError.invalidBackupPath
        }
        return result
    }

    private func itemExists(_ url: URL) throws -> Bool {
        do {
            _ = try fileManager.attributesOfItem(atPath: url.path)
            return true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return false
        }
    }

    private func signature(_ url: URL) throws -> String {
        if let target = try? fileManager.destinationOfSymbolicLink(atPath: url.path) {
            return "link:" + target
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var digest = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            digest.update(data: data)
        }
        return "file:" + digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
