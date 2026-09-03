import CryptoKit
import Darwin
import Foundation

protocol RepositoryBackupServing: Sendable {
    func loadBackups() async throws -> [RepositoryBackup]
    func createBackup(
        for repositoryURL: URL,
        reason: RepositoryBackupReason,
        policy: RepositoryBackupPolicy
    ) async throws -> RepositoryBackup?
    func assessChanges(
        after backup: RepositoryBackup,
        in repositoryURL: URL
    ) async throws -> RepositoryProtectionAssessment
    func restore(_ backup: RepositoryBackup, to destinationURL: URL) async throws -> URL
    func delete(_ backup: RepositoryBackup) async throws
    func deleteBackups(forRepositoryPath repositoryPath: String?) async throws
    func pruneBackups(retainingPerRepository limit: Int) async throws
    func directory(for backup: RepositoryBackup) async throws -> URL
    func storageByteCount() async throws -> Int64
    func storageDirectory() async -> URL
    func migrateStorage(to destinationURL: URL) async throws -> URL
}

actor RepositoryBackupService: RepositoryBackupServing {
    private var rootURL: URL
    private let runner: GitCommandRunner
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var activeStorageOperations = 0
    private var isMigratingStorage = false
    private var activeStagingDirectoryNames = Set<String>()

    nonisolated static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GitGatto", isDirectory: true)
            .appendingPathComponent("Recovery", isDirectory: true)
    }

    init(
        rootURL: URL? = nil,
        runner: GitCommandRunner = GitCommandRunner(),
        fileManager: FileManager = .default
    ) {
        self.runner = runner
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL.standardizedFileURL
        } else {
            self.rootURL = Self.defaultRootURL(fileManager: fileManager)
        }
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    func loadBackups() async throws -> [RepositoryBackup] {
        try beginStorageOperation()
        defer { endStorageOperation() }
        try recoverInterruptedTransactions()
        return try manifests().map(\.backup).sorted { $0.createdAt > $1.createdAt }
    }

    func createBackup(
        for repositoryURL: URL,
        reason: RepositoryBackupReason,
        policy: RepositoryBackupPolicy
    ) async throws -> RepositoryBackup? {
        try beginStorageOperation()
        defer { endStorageOperation() }
        let repository = repositoryURL.standardizedFileURL.resolvingSymlinksInPath()
        guard fileManager.fileExists(atPath: repository.appendingPathComponent(".git").path) else {
            throw RepositoryBackupError.repositoryUnavailable
        }

        try recoverInterruptedTransactions()
        let maximumFileSize = max(1, policy.maximumFileSize)
        let state = try await inspect(repository, maximumFileSize: maximumFileSize)
        if reason == .majorChange,
           state.changedPaths.count < max(1, policy.majorFileThreshold),
           state.changedLineCount < max(1, policy.majorLineThreshold)
        {
            return nil
        }
        let alwaysCreatesRecoveryPoint = reason == .manual
            || reason == .agentCheckpoint
            || reason == .externalCheckpoint
        if !alwaysCreatesRecoveryPoint, state.changedPaths.isEmpty {
            return nil
        }
        if !alwaysCreatesRecoveryPoint,
           try manifests().contains(where: {
               $0.backup.repositoryPath == repository.path && $0.fingerprint == state.fingerprint
           })
        {
            return nil
        }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let id = UUID()
        let directoryName = id.uuidString.lowercased()
        let stagingURL = rootURL.appendingPathComponent(".\(directoryName).staging", isDirectory: true)
        let finalURL = rootURL.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        activeStagingDirectoryNames.insert(stagingURL.lastPathComponent)
        var completed = false
        defer {
            activeStagingDirectoryNames.remove(stagingURL.lastPathComponent)
            if !completed {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        let workspaceURL = stagingURL.appendingPathComponent("workspace", isDirectory: true)
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        var copiedPaths: [String] = []
        var omittedPaths: [String] = []
        var copiedBytes: Int64 = 0
        for path in state.changedPaths where !state.deletedPaths.contains(path) {
            let source = try containedURL(path: path, in: repository)
            let values = try? source.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            let fileSize = Int64(values?.fileSize ?? 0)
            guard values?.isDirectory != true, fileSize <= maximumFileSize else {
                omittedPaths.append(path)
                continue
            }
            let destination = try containedURL(path: path, in: workspaceURL)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: destination)
            copiedPaths.append(path)
            copiedBytes += fileSize
        }

        var bundleFileName: String?
        if state.headSHA != nil {
            let name = "repository.bundle"
            let bundleURL = stagingURL.appendingPathComponent(name)
            _ = try await runner.run(
                at: repository,
                arguments: ["bundle", "create", bundleURL.path, "--all"]
            )
            bundleFileName = name
        }

        let provisional = RepositoryBackup(
            id: id,
            repositoryPath: repository.path,
            repositoryName: repository.lastPathComponent,
            branchName: state.branchName,
            headSHA: state.headSHA,
            createdAt: Date(),
            reason: reason,
            changedFileCount: state.changedPaths.count,
            changedLineCount: state.changedLineCount,
            storedByteCount: copiedBytes,
            omittedFileCount: omittedPaths.count,
            directoryName: directoryName
        )
        let provisionalManifest = RepositoryBackupManifest(
            backup: provisional,
            copiedPaths: copiedPaths,
            deletedPaths: state.deletedPaths,
            omittedPaths: omittedPaths,
            fingerprint: state.fingerprint,
            indexFingerprint: state.indexFingerprint,
            bundleFileName: bundleFileName
        )
        try write(provisionalManifest, to: stagingURL)
        let actualBytes = try recursiveByteCount(at: stagingURL)
        let backup = RepositoryBackup(
            id: provisional.id,
            repositoryPath: provisional.repositoryPath,
            repositoryName: provisional.repositoryName,
            branchName: provisional.branchName,
            headSHA: provisional.headSHA,
            createdAt: provisional.createdAt,
            reason: provisional.reason,
            changedFileCount: provisional.changedFileCount,
            changedLineCount: provisional.changedLineCount,
            storedByteCount: actualBytes,
            omittedFileCount: provisional.omittedFileCount,
            directoryName: provisional.directoryName
        )
        try write(
            RepositoryBackupManifest(
                backup: backup,
                copiedPaths: copiedPaths,
                deletedPaths: state.deletedPaths,
                omittedPaths: omittedPaths,
                fingerprint: state.fingerprint,
                indexFingerprint: state.indexFingerprint,
                bundleFileName: bundleFileName
            ),
            to: stagingURL
        )
        try writeCommitMarker(for: backup, in: stagingURL)
        try synchronizeTree(at: stagingURL)
        try fileManager.moveItem(at: stagingURL, to: finalURL)
        completed = true
        try synchronizeFileSystemItem(at: rootURL)
        let retentionCount = RepositoryBackupPolicy.clampedRetentionCount(policy.retentionCount)
        try enforceRetention(for: repository.path, limit: retentionCount)
        try synchronizeFileSystemItem(at: rootURL)
        return backup
    }

    func assessChanges(
        after backup: RepositoryBackup,
        in repositoryURL: URL
    ) async throws -> RepositoryProtectionAssessment {
        try beginStorageOperation()
        defer { endStorageOperation() }
        let repository = repositoryURL.standardizedFileURL.resolvingSymlinksInPath()
        guard repository.path == backup.repositoryPath else {
            throw RepositoryBackupError.invalidBackupPath
        }
        let baseline = try manifest(for: backup)
        let current = try await inspect(repository, maximumFileSize: .max)
        var deletedPaths = Set(current.deletedPaths).subtracting(baseline.deletedPaths)
        var lostChangedPaths = Set<String>()
        let currentChangedPaths = Set(current.changedPaths)
        let baselineWorkspace = try backupDirectory(for: backup)
            .appendingPathComponent("workspace", isDirectory: true)
        for path in baseline.copiedPaths {
            let url = try containedURL(path: path, in: repository)
            if !Self.itemExists(at: url, fileManager: fileManager) {
                deletedPaths.insert(path)
                continue
            }
            guard !currentChangedPaths.contains(path) else { continue }
            let preservedURL = try containedURL(path: path, in: baselineWorkspace)
            if Self.itemExists(at: preservedURL, fileManager: fileManager),
               !fileManager.contentsEqual(atPath: preservedURL.path, andPath: url.path)
            {
                lostChangedPaths.insert(path)
            }
        }
        return RepositoryProtectionAssessment(
            backupID: backup.id,
            changedFileCount: current.changedPaths.count,
            changedLineCount: current.changedLineCount,
            deletedPaths: deletedPaths.sorted(),
            lostChangedPaths: lostChangedPaths.sorted(),
            headChanged: current.headSHA != backup.headSHA,
            branchChanged: current.branchName != backup.branchName,
            indexChanged: baseline.indexFingerprint.map { $0 != current.indexFingerprint } ?? false
        )
    }

    func restore(_ backup: RepositoryBackup, to destinationURL: URL) async throws -> URL {
        try beginStorageOperation()
        defer { endStorageOperation() }
        let destination = destinationURL.standardizedFileURL
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw RepositoryBackupError.destinationExists
        }
        let manifest = try manifest(for: backup)
        let backupURL = try backupDirectory(for: backup)
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        if let bundleFileName = manifest.bundleFileName {
            let bundleURL = backupURL.appendingPathComponent(bundleFileName)
            guard fileManager.fileExists(atPath: bundleURL.path) else {
                throw RepositoryBackupError.backupMissing
            }
            _ = try await runner.run(
                at: parent,
                arguments: ["clone", bundleURL.path, destination.path]
            )
            if let headSHA = backup.headSHA {
                _ = try await runner.run(
                    at: destination,
                    arguments: ["reset", "--hard", headSHA]
                )
            }
        } else {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            _ = try await runner.run(at: destination, arguments: ["init"])
        }

        let workspaceURL = backupURL.appendingPathComponent("workspace", isDirectory: true)
        for path in manifest.copiedPaths {
            let source = try containedURL(path: path, in: workspaceURL)
            let target = try containedURL(path: path, in: destination)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: target)
        }
        for path in manifest.deletedPaths {
            let target = try containedURL(path: path, in: destination)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
        }
        return destination
    }

    func delete(_ backup: RepositoryBackup) async throws {
        try beginStorageOperation()
        defer { endStorageOperation() }
        let directory = try backupDirectory(for: backup)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw RepositoryBackupError.backupMissing
        }
        try fileManager.removeItem(at: directory)
    }

    func deleteBackups(forRepositoryPath repositoryPath: String?) async throws {
        try beginStorageOperation()
        defer { endStorageOperation() }
        let candidates = try manifests().filter { manifest in
            repositoryPath == nil || manifest.backup.repositoryPath == repositoryPath
        }
        for manifest in candidates {
            let directory = try backupDirectory(for: manifest.backup)
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
        }
    }

    func pruneBackups(retainingPerRepository limit: Int) async throws {
        try beginStorageOperation()
        defer { endStorageOperation() }
        let retentionCount = RepositoryBackupPolicy.clampedRetentionCount(limit)
        let repositoryPaths = try Set(manifests().map(\.backup.repositoryPath))
        for repositoryPath in repositoryPaths {
            try enforceRetention(for: repositoryPath, limit: retentionCount)
        }
    }

    func directory(for backup: RepositoryBackup) async throws -> URL {
        try beginStorageOperation()
        defer { endStorageOperation() }
        let directory = try backupDirectory(for: backup)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw RepositoryBackupError.backupMissing
        }
        return directory
    }

    func storageByteCount() async throws -> Int64 {
        try beginStorageOperation()
        defer { endStorageOperation() }
        guard fileManager.fileExists(atPath: rootURL.path) else { return 0 }
        return try recursiveByteCount(at: rootURL)
    }

    func storageDirectory() async -> URL {
        rootURL
    }

    func migrateStorage(to destinationURL: URL) async throws -> URL {
        let source = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let destination = destinationURL.standardizedFileURL.resolvingSymlinksInPath()
        if source == destination {
            return destination
        }
        guard activeStorageOperations == 0, !isMigratingStorage else {
            throw RepositoryBackupError.storageBusy
        }
        guard !Self.isNested(destination, inside: source),
              !Self.isNested(source, inside: destination)
        else {
            throw RepositoryBackupError.invalidBackupPath
        }
        if fileManager.fileExists(atPath: destination.path) {
            let contents = try fileManager.contentsOfDirectory(atPath: destination.path)
            guard contents.isEmpty else {
                throw RepositoryBackupError.migrationDestinationNotEmpty
            }
        }

        isMigratingStorage = true
        defer { isMigratingStorage = false }
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(
            ".GitGatto-Recovery-Migration-\(UUID().uuidString)",
            isDirectory: true
        )
        var installedDestination = false
        defer {
            if fileManager.fileExists(atPath: staging.path) {
                try? fileManager.removeItem(at: staging)
            }
            if !installedDestination,
               fileManager.fileExists(atPath: destination.path),
               (try? fileManager.contentsOfDirectory(atPath: destination.path).isEmpty) == true
            {
                try? fileManager.removeItem(at: destination)
            }
        }

        if fileManager.fileExists(atPath: source.path) {
            try fileManager.copyItem(at: source, to: staging)
        } else {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        }
        let sourceInventory = try storageInventory(at: source)
        let stagingInventory = try storageInventory(at: staging)
        guard sourceInventory == stagingInventory else {
            throw RepositoryBackupError.migrationVerificationFailed
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: staging, to: destination)
        installedDestination = true
        rootURL = destination
        if fileManager.fileExists(atPath: source.path) {
            try? fileManager.removeItem(at: source)
        }
        return destination
    }

    private func beginStorageOperation() throws {
        guard !isMigratingStorage else { throw RepositoryBackupError.storageBusy }
        activeStorageOperations += 1
    }

    private func endStorageOperation() {
        activeStorageOperations = max(0, activeStorageOperations - 1)
    }

    private static func isNested(_ candidate: URL, inside root: URL) -> Bool {
        candidate.path.hasPrefix("\(root.path)/")
    }

    private func recoverInterruptedTransactions() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let candidates = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ).filter { $0.lastPathComponent.hasSuffix(".staging") }

        var changedStorage = false
        for stagingURL in candidates where !activeStagingDirectoryNames.contains(stagingURL.lastPathComponent) {
            guard let manifest = committedManifest(in: stagingURL),
                  stagingURL.lastPathComponent == ".\(manifest.backup.directoryName).staging"
            else {
                try fileManager.removeItem(at: stagingURL)
                changedStorage = true
                continue
            }
            let finalURL = rootURL.appendingPathComponent(
                manifest.backup.directoryName,
                isDirectory: true
            )
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: stagingURL)
            } else {
                try fileManager.moveItem(at: stagingURL, to: finalURL)
            }
            changedStorage = true
        }
        if changedStorage {
            try synchronizeFileSystemItem(at: rootURL)
        }
    }

    private func committedManifest(in directory: URL) -> RepositoryBackupManifest? {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let markerURL = directory.appendingPathComponent("commit.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let markerData = try? Data(contentsOf: markerURL),
              let manifest = try? decoder.decode(RepositoryBackupManifest.self, from: manifestData),
              let marker = try? decoder.decode(RepositoryBackupCommitMarker.self, from: markerData),
              marker.schemaVersion == RepositoryBackupCommitMarker.currentSchemaVersion,
              marker.backupID == manifest.backup.id,
              marker.manifestSHA256 == Self.digest(manifestData)
        else {
            return nil
        }
        return manifest
    }

    private func writeCommitMarker(for backup: RepositoryBackup, in directory: URL) throws {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let marker = RepositoryBackupCommitMarker(
            schemaVersion: RepositoryBackupCommitMarker.currentSchemaVersion,
            backupID: backup.id,
            manifestSHA256: Self.digest(manifestData)
        )
        let data = try encoder.encode(marker)
        try data.write(to: directory.appendingPathComponent("commit.json"), options: .atomic)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func synchronizeTree(at root: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw RepositoryBackupError.backupMissing
        }
        var directories = [root]
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            if values.isDirectory == true {
                directories.append(item)
            } else if values.isRegularFile == true, values.isSymbolicLink != true {
                try synchronizeFileSystemItem(at: item)
            }
        }
        for directory in directories.sorted(by: { $0.path.count > $1.path.count }) {
            try synchronizeFileSystemItem(at: directory)
        }
    }

    private func synchronizeFileSystemItem(at url: URL) throws {
        let descriptor: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY)
        }
        guard descriptor >= 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        defer { Darwin.close(descriptor) }
        if fcntl(descriptor, F_FULLFSYNC) != 0, fsync(descriptor) != 0 {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func storageInventory(at root: URL) throws -> [String: RepositoryBackupStorageEntry] {
        guard fileManager.fileExists(atPath: root.path) else { return [:] }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        guard let enumerator = fileManager.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: []
        ) else { return [:] }
        var inventory: [String: RepositoryBackupStorageEntry] = [:]
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let canonicalItem = item.standardizedFileURL.resolvingSymlinksInPath()
            let relative = String(canonicalItem.path.dropFirst(canonicalRoot.path.count + 1))
            inventory[relative] = try RepositoryBackupStorageEntry(
                byteCount: Int64(values.fileSize ?? 0),
                sha256: Self.fileDigest(at: canonicalItem)
            )
        }
        return inventory
    }

    private static func fileDigest(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func inspect(
        _ repository: URL,
        maximumFileSize: Int64
    ) async throws -> RepositoryBackupState {
        let headResult = try await runner.run(
            at: repository,
            arguments: ["rev-parse", "--verify", "HEAD"],
            acceptedExitCodes: [0, 128]
        )
        let headSHA = headResult.exitCode == 0
            ? headResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        if headSHA != nil {
            _ = try await runner.run(
                at: repository,
                arguments: ["cat-file", "-e", "HEAD^{commit}"]
            )
        }
        let branchResult = try await runner.run(
            at: repository,
            arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"],
            acceptedExitCodes: [0, 1]
        )
        let branch = branchResult.exitCode == 0
            ? branchResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let index = try await runner.run(
            at: repository,
            arguments: ["ls-files", "--stage", "-z"]
        )
        let indexFingerprint = Self.digest(index.output)

        var paths = Set<String>()
        if headSHA != nil {
            let changed = try await runner.run(
                at: repository,
                arguments: ["diff", "--name-only", "-z", "HEAD", "--"]
            )
            paths.formUnion(Self.nullSeparatedPaths(changed.output))
        } else {
            let indexed = try await runner.run(
                at: repository,
                arguments: ["ls-files", "--cached", "-z"]
            )
            paths.formUnion(Self.nullSeparatedPaths(indexed.output))
        }
        let untracked = try await runner.run(
            at: repository,
            arguments: ["ls-files", "--others", "--exclude-standard", "-z"]
        )
        paths.formUnion(Self.nullSeparatedPaths(untracked.output))
        let sortedPaths = paths.sorted()
        let deletedPaths = sortedPaths.filter { path in
            guard let url = try? containedURL(path: path, in: repository) else { return false }
            return !Self.itemExists(at: url, fileManager: fileManager)
        }
        let changedLineCount: Int
        if headSHA != nil {
            let numstat = try await runner.run(
                at: repository,
                arguments: ["diff", "--numstat", "HEAD", "--"]
            )
            changedLineCount = Self.lineChangeCount(numstat.text)
        } else {
            changedLineCount = 0
        }
        var hasher = SHA256()
        hasher.update(data: Data((headSHA ?? "unborn").utf8))
        for path in sortedPaths {
            hasher.update(data: Data(path.utf8))
            guard !deletedPaths.contains(path),
                  let url = try? containedURL(path: path, in: repository) else { continue }
            let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isDirectoryKey,
            ])
            if values?.isDirectory == true {
                hasher.update(data: Data("directory".utf8))
            } else if Int64(values?.fileSize ?? 0) > maximumFileSize {
                let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
                hasher.update(data: Data("oversized:\(values?.fileSize ?? 0):\(modified)".utf8))
            } else {
                try Self.update(&hasher, withContentsOf: url, fileManager: fileManager)
            }
        }
        let fingerprint = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return RepositoryBackupState(
            headSHA: headSHA?.isEmpty == false ? headSHA : nil,
            branchName: branch?.isEmpty == false ? branch : nil,
            changedPaths: sortedPaths,
            deletedPaths: deletedPaths,
            changedLineCount: changedLineCount,
            indexFingerprint: indexFingerprint,
            fingerprint: fingerprint
        )
    }

    private func manifests() throws -> [RepositoryBackupManifest] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).compactMap { directory in
            try? Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        }.compactMap { try? decoder.decode(RepositoryBackupManifest.self, from: $0) }
    }

    private func manifest(for backup: RepositoryBackup) throws -> RepositoryBackupManifest {
        let directory = try backupDirectory(for: backup)
        let url = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              let manifest = try? decoder.decode(RepositoryBackupManifest.self, from: data),
              manifest.backup.id == backup.id
        else {
            throw RepositoryBackupError.backupMissing
        }
        return manifest
    }

    private func write(_ manifest: RepositoryBackupManifest, to directory: URL) throws {
        let data = try encoder.encode(manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func backupDirectory(for backup: RepositoryBackup) throws -> URL {
        let directory = rootURL.appendingPathComponent(backup.directoryName, isDirectory: true)
            .standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path
        guard directory.path.hasPrefix("\(rootPath)/") else {
            throw RepositoryBackupError.invalidBackupPath
        }
        return directory
    }

    private func enforceRetention(for repositoryPath: String, limit: Int) throws {
        let candidates = try manifests()
            .filter { $0.backup.repositoryPath == repositoryPath }
            .sorted { $0.backup.createdAt < $1.backup.createdAt }
        guard candidates.count > limit else { return }
        for manifest in candidates.prefix(candidates.count - limit) {
            let directory = try backupDirectory(for: manifest.backup)
            try fileManager.removeItem(at: directory)
        }
    }

    private func containedURL(path: String, in root: URL) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/") else {
            throw RepositoryBackupError.invalidBackupPath
        }
        let resolvedRoot = root.standardizedFileURL
        let candidate = resolvedRoot.appendingPathComponent(path).standardizedFileURL
        guard candidate.path.hasPrefix("\(resolvedRoot.path)/") else {
            throw RepositoryBackupError.invalidBackupPath
        }
        return candidate
    }

    private func recursiveByteCount(at url: URL) throws -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    private static func nullSeparatedPaths(_ data: Data) -> [String] {
        data.split(separator: 0).compactMap { String(data: $0, encoding: .utf8) }
    }

    private static func lineChangeCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isNewline).reduce(into: 0) { total, line in
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count >= 2 else { return }
            total += Int(fields[0]) ?? 0
            total += Int(fields[1]) ?? 0
        }
    }

    private static func itemExists(at url: URL, fileManager: FileManager) -> Bool {
        if fileManager.fileExists(atPath: url.path) {
            return true
        }
        return (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func update(
        _ hasher: inout SHA256,
        withContentsOf url: URL,
        fileManager: FileManager
    ) throws {
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) {
            hasher.update(data: Data(destination.utf8))
            return
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
    }
}

private struct RepositoryBackupState: Sendable {
    let headSHA: String?
    let branchName: String?
    let changedPaths: [String]
    let deletedPaths: [String]
    let changedLineCount: Int
    let indexFingerprint: String
    let fingerprint: String
}

private struct RepositoryBackupStorageEntry: Equatable {
    let byteCount: Int64
    let sha256: String
}

private struct RepositoryBackupCommitMarker: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let backupID: UUID
    let manifestSHA256: String
}
