import CryptoKit
import Foundation

struct FileRestorePreview: Identifiable, Sendable {
    let id = UUID()
    let repository: URL
    let path: String
    let revision: FileRevisionRecord
    let currentHash: String
    let target: Data
    let diff: DiffDocument
}

actor FileRestorePreviewService {
    func preview(path: String, revision: FileRevisionRecord, repository: URL) async throws -> FileRestorePreview {
        _ = try ProjectToolsPolicy.relativePath(revision.path)
        guard ProjectToolsPolicy.allowsContent(revision.path),
              (40...64).contains(revision.hash.count), revision.hash.allSatisfy(\.isHexDigit) else {
            throw ProjectToolsError(key: "path")
        }
        let file = try destination(path, repository: repository)
        let current = try Data(contentsOf: file)
        let target = try await GitCommandRunner().run(at: repository,
            arguments: ["show", "\(revision.hash):\(revision.path)"]).output
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("GitGatto-restore-preview-\(UUID())")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try current.write(to: temporary.appendingPathComponent("current"))
        try target.write(to: temporary.appendingPathComponent("restore"))
        let result = try await ExternalProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["diff", "--no-index", "--no-color", "--no-ext-diff", "--", "current", "restore"],
            currentDirectoryURL: temporary, acceptedExitCodes: [0, 1], timeout: .seconds(30))
        try Task.checkCancellation()
        return .init(repository: repository, path: path, revision: revision, currentHash: Self.hash(current),
            target: target, diff: GitParsers.diff(from: result.outputText, path: path))
    }

    func restore(_ preview: FileRestorePreview) throws {
        let file = try destination(preview.path, repository: preview.repository)
        guard Self.hash(try Data(contentsOf: file)) == preview.currentHash else {
            throw FileRestorePreviewError.changed
        }
        try preview.target.write(to: file, options: .atomic)
    }

    private func destination(_ path: String, repository: URL) throws -> URL {
        _ = try ProjectToolsPolicy.relativePath(path)
        guard ProjectToolsPolicy.allowsContent(path) else { throw ProjectToolsError(key: "path") }
        let root = repository.resolvingSymlinksInPath().standardizedFileURL
        let file = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else { throw ProjectToolsError(key: "path") }
        return file
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

enum FileRestorePreviewError: LocalizedError {
    case changed
    var errorDescription: String? { L10n.text("file_timeline.restore.changed") }
}
