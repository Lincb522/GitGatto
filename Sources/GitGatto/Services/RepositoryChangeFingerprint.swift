import CryptoKit
import Foundation

/// Captures index, working-tree and untracked content without modifying the repository.
enum RepositoryChangeFingerprint {
    static func capture(in repositoryURL: URL, runner: GitCommandRunner = GitCommandRunner(), expectedStatus: Data? = nil) async throws -> String {
        async let head = runner.run(at: repositoryURL, arguments: ["rev-parse", "HEAD"])
        async let status = runner.run(at: repositoryURL,
            arguments: ["status", "--porcelain=v1", "-z", "--branch", "--untracked-files=all"])
        async let working = runner.run(at: repositoryURL,
            arguments: ["diff", "--no-ext-diff", "--no-textconv", "--binary", "--full-index", "HEAD", "--"])
        async let staged = runner.run(at: repositoryURL,
            arguments: ["diff", "--no-ext-diff", "--no-textconv", "--cached", "--binary", "--full-index", "HEAD", "--"])
        let statusData = try await status.output
        if let expectedStatus, statusData != expectedStatus { throw ChangeIntentError.repositoryChanged }
        var digest = SHA256()
        for data in [try await head.output, statusData, try await working.output, try await staged.output] {
            digest.update(data: data)
            digest.update(data: Data([0]))
        }
        guard let snapshot = GitParsers.statusSnapshot(from: statusData) else {
            throw ChangeIntentError.invalidPlan(L10n.text("intelligence.intent.error.status"))
        }
        // Porcelain flags do not change when a modified or untracked file is edited again.
        // Hash untracked contents too; a stale plan must not silently commit newer work.
        for change in snapshot.changes where change.primaryStatus == .untracked {
            try Task.checkCancellation()
            let file = repositoryURL.appendingPathComponent(change.path)
            digest.update(data: Data(change.path.utf8))
            if let link = try? FileManager.default.destinationOfSymbolicLink(atPath: file.path) {
                digest.update(data: Data(link.utf8))
            } else {
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                    try Task.checkCancellation()
                    digest.update(data: chunk)
                }
            }
            digest.update(data: Data([0]))
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

}
