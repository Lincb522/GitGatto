import Foundation

struct RepositoryBackupFile: Identifiable, Sendable, Equatable {
    let path: String
    let byteCount: Int64
    var id: String { path }
}

actor RepositoryBackupInspectionService {
    private let backups: any RepositoryBackupServing
    private let runner: GitCommandRunner
    private var temporaryRoot: URL?
    private var snapshotURL: URL?
    private var repositoryURL: URL?
    private var files: [RepositoryBackupFile] = []
    private var generation = UUID()

    init(backups: any RepositoryBackupServing, runner: GitCommandRunner = GitCommandRunner()) {
        self.backups = backups
        self.runner = runner
    }

    func prepare(_ backup: RepositoryBackup) async throws -> [RepositoryBackupFile] {
        try close()
        let generation = self.generation
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("GitGatto-Inspect-\(UUID())")
        var ready = false
        defer { if !ready { try? FileManager.default.removeItem(at: root) } }
        let restored = try await backups.restore(backup, to: root.appendingPathComponent("snapshot"))
        let snapshot = restored.standardizedFileURL.resolvingSymlinksInPath()
        try Task.checkCancellation()
        guard self.generation == generation else { throw CancellationError() }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: snapshot, includingPropertiesForKeys: Array(keys), errorHandler: { _, error in
            enumerationError = error
            return false
        }) else {
            throw RepositoryBackupError.backupMissing
        }
        var collected: [RepositoryBackupFile] = []
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            if url.lastPathComponent == ".git" { enumerator.skipDescendants(); continue }
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isRegularFile == true else { continue }
            guard collected.count < 100_000 else { throw BackupInspectionError.tooLarge }
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard path.hasPrefix(snapshot.path + "/") else { throw BackupInspectionError.unsafePath }
            collected.append(.init(path: String(path.dropFirst(snapshot.path.count + 1)), byteCount: Int64(values.fileSize ?? 0)))
        }
        if let enumerationError { throw enumerationError }
        temporaryRoot = root
        snapshotURL = snapshot
        repositoryURL = URL(fileURLWithPath: backup.repositoryPath).standardizedFileURL.resolvingSymlinksInPath()
        files = collected.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        ready = true
        return files
    }

    func compare(path: String) async throws -> DiffDocument {
        let generation = self.generation
        guard let snapshotURL, let repositoryURL, files.contains(where: { $0.path == path }) else {
            throw RepositoryBackupError.backupMissing
        }
        let saved = try containedFile(path, root: snapshotURL)
        let current = try containedFile(path, root: repositoryURL)
        for url in [saved, current] where FileManager.default.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= 2_000_000 else { throw BackupInspectionError.tooLarge }
        }
        let currentPath = FileManager.default.fileExists(atPath: current.path) ? current.path : "/dev/null"
        let result = try await runner.run(at: snapshotURL,
            arguments: ["diff", "--no-index", "--no-ext-diff", "--no-textconv", "--no-color", "--", saved.path, currentPath],
            acceptedExitCodes: [0, 1])
        try Task.checkCancellation()
        guard self.generation == generation else { throw CancellationError() }
        return GitParsers.diff(from: result.text, path: path)
    }

    func export(paths: Set<String>, to destination: URL) throws -> URL {
        guard let snapshotURL, let repositoryURL, !paths.isEmpty,
              paths.isSubset(of: Set(files.map(\.path))) else { throw RepositoryBackupError.backupMissing }
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard destination != repositoryURL, !destination.path.hasPrefix(repositoryURL.path + "/"),
              temporaryRoot.map({ destination != $0 && !destination.path.hasPrefix($0.path + "/") }) == true else {
            throw BackupInspectionError.chooseOutsideRepository
        }
        guard !FileManager.default.fileExists(atPath: destination.path),
              (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw RepositoryBackupError.destinationExists
        }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".GitGatto-Files-\(UUID())")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        for path in paths.sorted() {
            try Task.checkCancellation()
            let source = try containedFile(path, root: snapshotURL)
            let target = try containedFile(path, root: staging)
            guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw RepositoryBackupError.backupMissing }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: target)
        }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: destination)
        return destination
    }

    func close() throws {
        generation = UUID()
        if let temporaryRoot { try FileManager.default.removeItem(at: temporaryRoot) }
        temporaryRoot = nil; snapshotURL = nil; repositoryURL = nil; files = []
    }

    private func containedFile(_ path: String, root: URL) throws -> URL {
        let url = root.appendingPathComponent(path).standardizedFileURL
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
              url.path.hasPrefix(root.path + "/"), url.resolvingSymlinksInPath().path == url.path else {
            throw BackupInspectionError.unsafePath
        }
        return url
    }
}

enum BackupInspectionError: LocalizedError {
    case tooLarge, chooseOutsideRepository, unsafePath
    var errorDescription: String? {
        switch self {
        case .tooLarge: L10n.text("recovery.compare.tooLarge")
        case .chooseOutsideRepository: L10n.text("recovery.compare.outside")
        case .unsafePath: L10n.text("recovery.compare.unsafePath")
        }
    }
}
