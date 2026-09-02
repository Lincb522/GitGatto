import AppKit
import Foundation
import SwiftUI
@testable import GitGatto
import Testing

@Suite("Repository disaster recovery")
struct RepositoryBackupServiceTests {
    @MainActor
    @Test("A monitored repository change creates a major backup", .timeLimit(.minutes(1)))
    func monitorsManagedRepository() async throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let defaults = UserDefaults.standard
        let previousManaged = defaults.array(forKey: "managedLocalRepositories")
        let previousRecent = defaults.array(forKey: "recentRepositories")
        defaults.removeObject(forKey: "managedLocalRepositories")
        defaults.removeObject(forKey: "recentRepositories")
        defer {
            if let previousManaged {
                defaults.set(previousManaged, forKey: "managedLocalRepositories")
            } else {
                defaults.removeObject(forKey: "managedLocalRepositories")
            }
            if let previousRecent {
                defaults.set(previousRecent, forKey: "recentRepositories")
            } else {
                defaults.removeObject(forKey: "recentRepositories")
            }
        }
        let backingService = RepositoryBackupService(
            rootURL: fixture.root.appendingPathComponent("backups", isDirectory: true)
        )
        let service = RecordingRepositoryBackupService(backing: backingService)
        let model = WorkspaceViewModel(repositoryBackupService: service)
        model.appPreferences.repositoryBackupEnabled = true
        model.appPreferences.majorBackupFileThreshold = 1
        model.appPreferences.majorBackupLineThreshold = 10000
        await model.openRepository(fixture.repository)
        model.restartRepositoryProtection()
        #expect(model.localRepositories.contains {
            $0.standardizedFileURL.resolvingSymlinksInPath()
                == fixture.repository.standardizedFileURL.resolvingSymlinksInPath()
        })
        try await Task.sleep(for: .milliseconds(500))

        try "monitored\n".write(
            to: fixture.repository.appendingPathComponent("monitored.txt"),
            atomically: true,
            encoding: .utf8
        )
        model.scheduleMajorRepositoryBackup(for: fixture.repository)
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while model.repositoryBackups.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(200))
        }
        model.appPreferences.repositoryBackupEnabled = false
        model.restartRepositoryProtection()

        #expect(await service.createCallCount > 0)
        #expect(model.repositoryBackups.first?.reason == .majorChange)
        #expect(
            model.repositoryBackups.first?.repositoryPath
                == fixture.repository.standardizedFileURL.resolvingSymlinksInPath().path
        )
    }

    @Test("Creates a restorable snapshot without changing the source repository")
    func createsAndRestoresSnapshot() async throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let storeURL = fixture.root.appendingPathComponent("backups", isDirectory: true)
        let service = RepositoryBackupService(rootURL: storeURL)

        try "changed\nline two\n".write(
            to: fixture.repository.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "untracked\n".write(
            to: fixture.repository.appendingPathComponent("new.txt"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.removeItem(at: fixture.repository.appendingPathComponent("deleted.txt"))

        let backup = try #require(await service.createBackup(
            for: fixture.repository,
            reason: .scheduled,
            policy: .standard
        ))
        let duplicate = try await service.createBackup(
            for: fixture.repository,
            reason: .scheduled,
            policy: .standard
        )
        let destination = fixture.root.appendingPathComponent("recovered", isDirectory: true)
        let restored = try await service.restore(backup, to: destination)

        #expect(duplicate == nil)
        #expect(backup.changedFileCount == 3)
        #expect(try String(contentsOf: restored.appendingPathComponent("tracked.txt"), encoding: .utf8) == "changed\nline two\n")
        #expect(try String(contentsOf: restored.appendingPathComponent("new.txt"), encoding: .utf8) == "untracked\n")
        #expect(!FileManager.default.fileExists(atPath: restored.appendingPathComponent("deleted.txt").path))
        #expect(try git(["status", "--porcelain"], at: fixture.repository).contains("tracked.txt"))
        #expect(try git(["status", "--porcelain"], at: restored).contains("tracked.txt"))
    }

    @Test("Creates immediate backups only after a major-change threshold")
    func detectsMajorChanges() async throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let service = RepositoryBackupService(
            rootURL: fixture.root.appendingPathComponent("backups", isDirectory: true)
        )
        try "one\n".write(
            to: fixture.repository.appendingPathComponent("one.txt"),
            atomically: true,
            encoding: .utf8
        )
        let policy = RepositoryBackupPolicy(
            majorFileThreshold: 2,
            majorLineThreshold: 100,
            retentionCount: 5,
            maximumFileSize: 1024 * 1024
        )

        #expect(try await service.createBackup(
            for: fixture.repository,
            reason: .majorChange,
            policy: policy
        ) == nil)

        try "two\n".write(
            to: fixture.repository.appendingPathComponent("two.txt"),
            atomically: true,
            encoding: .utf8
        )
        let backup = try await service.createBackup(
            for: fixture.repository,
            reason: .majorChange,
            policy: policy
        )
        #expect(backup?.reason == .majorChange)
        #expect(backup?.changedFileCount == 2)
    }

    @Test("Records files above the configured size without copying them")
    func omitsOversizedFiles() async throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let service = RepositoryBackupService(
            rootURL: fixture.root.appendingPathComponent("backups", isDirectory: true)
        )
        try Data(repeating: 0x5A, count: 2048).write(
            to: fixture.repository.appendingPathComponent("large.bin")
        )
        let policy = RepositoryBackupPolicy(
            majorFileThreshold: 1,
            majorLineThreshold: 1,
            retentionCount: 5,
            maximumFileSize: 1024
        )

        let backup = try #require(await service.createBackup(
            for: fixture.repository,
            reason: .majorChange,
            policy: policy
        ))
        let restored = try await service.restore(
            backup,
            to: fixture.root.appendingPathComponent("recovered-large-file", isDirectory: true)
        )

        #expect(backup.omittedFileCount == 1)
        #expect(!FileManager.default.fileExists(atPath: restored.appendingPathComponent("large.bin").path))
    }

    @Test("Rolling retention keeps only the three newest backups")
    func keepsThreeRollingBackups() async throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let service = RepositoryBackupService(
            rootURL: fixture.root.appendingPathComponent("backups", isDirectory: true)
        )
        let policy = RepositoryBackupPolicy(
            majorFileThreshold: 1,
            majorLineThreshold: 1,
            retentionCount: 30,
            maximumFileSize: 1024 * 1024
        )
        var created: [RepositoryBackup] = []
        for index in 0 ..< 4 {
            try "rolling-\(index)\n".write(
                to: fixture.repository.appendingPathComponent("rolling.txt"),
                atomically: true,
                encoding: .utf8
            )
            try created.append(#require(await service.createBackup(
                for: fixture.repository,
                reason: .manual,
                policy: policy
            )))
        }

        let backups = try await service.loadBackups()
        let visibleDirectories = try FileManager.default.contentsOfDirectory(
            at: fixture.root.appendingPathComponent("backups", isDirectory: true),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        #expect(backups.count == 3)
        #expect(Set(backups.map(\.id)) == Set(created.suffix(3).map(\.id)))
        #expect(!backups.contains(where: { $0.id == created[0].id }))
        #expect(visibleDirectories.count == 3)
    }

    @Test("Backup management can reveal and delete one repository's snapshots")
    func managesRepositoryBackups() async throws {
        let fixture = try BackupFixture()
        let otherFixture = try BackupFixture()
        defer {
            fixture.remove()
            otherFixture.remove()
        }
        let service = RepositoryBackupService(
            rootURL: fixture.root.appendingPathComponent("backups", isDirectory: true)
        )
        let first = try #require(await service.createBackup(
            for: fixture.repository,
            reason: .manual,
            policy: .standard
        ))
        let second = try #require(await service.createBackup(
            for: otherFixture.repository,
            reason: .manual,
            policy: .standard
        ))

        let firstDirectory = try await service.directory(for: first)
        #expect(FileManager.default.fileExists(atPath: firstDirectory.path))

        try await service.deleteBackups(forRepositoryPath: first.repositoryPath)
        let remaining = try await service.loadBackups()

        #expect(!FileManager.default.fileExists(atPath: firstDirectory.path))
        #expect(remaining.map(\.id) == [second.id])
    }

    @MainActor
    @Test("Recovery management renders at the default window size")
    func rendersRecoveryManagement() async throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let service = RepositoryBackupService(
            rootURL: fixture.root.appendingPathComponent("backups", isDirectory: true)
        )
        for index in 0..<3 {
            try "render-\(index)\n".write(
                to: fixture.repository.appendingPathComponent("render.txt"),
                atomically: true,
                encoding: .utf8
            )
            _ = try await service.createBackup(
                for: fixture.repository,
                reason: .manual,
                policy: .standard
            )
        }
        let model = WorkspaceViewModel(repositoryBackupService: service)
        await model.reloadRepositoryBackups()

        let view = RepositoryRecoveryView(model: model)
            .frame(width: 1_416, height: 876)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_416, height: 876)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        let representation = try #require(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

        #expect(representation.pixelsWide == 1_416)
        #expect(representation.pixelsHigh == 876)
        #expect(model.repositoryBackups.count == 3)
        if let outputPath = ProcessInfo.processInfo.environment["GITGATTO_RECOVERY_UI_SNAPSHOT_PATH"] {
            let data = try #require(representation.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
    }

    @Test("Migrates existing backups and keeps them restorable")
    func migratesBackupStorage() async throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("backups", isDirectory: true)
        let destination = fixture.root.appendingPathComponent("external/GitGatto Recovery", isDirectory: true)
        let service = RepositoryBackupService(rootURL: source)
        try "migrated\n".write(
            to: fixture.repository.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        let backup = try #require(await service.createBackup(
            for: fixture.repository,
            reason: .manual,
            policy: .standard
        ))

        let migrated = try await service.migrateStorage(to: destination)
        let loaded = try await service.loadBackups()
        let restored = try await service.restore(
            backup,
            to: fixture.root.appendingPathComponent("restored-after-migration", isDirectory: true)
        )

        #expect(migrated.path == destination.standardizedFileURL.resolvingSymlinksInPath().path)
        #expect((await service.storageDirectory()).path == migrated.path)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(loaded.map(\.id) == [backup.id])
        #expect(try String(contentsOf: restored.appendingPathComponent("tracked.txt"), encoding: .utf8) == "migrated\n")
    }

    @Test("Refuses a nonempty migration destination without moving the source")
    func rejectsNonemptyMigrationDestination() async throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("backups", isDirectory: true)
        let destination = fixture.root.appendingPathComponent("occupied", isDirectory: true)
        let service = RepositoryBackupService(rootURL: source)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("unrelated".utf8).write(to: destination.appendingPathComponent("keep.txt"))

        await #expect(throws: RepositoryBackupError.self) {
            try await service.migrateStorage(to: destination)
        }

        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try String(contentsOf: destination.appendingPathComponent("keep.txt"), encoding: .utf8) == "unrelated")
        #expect(await service.storageDirectory() == source.standardizedFileURL)
    }
}

private actor RecordingRepositoryBackupService: RepositoryBackupServing {
    private let backing: RepositoryBackupService
    private(set) var createCallCount = 0

    init(backing: RepositoryBackupService) {
        self.backing = backing
    }

    func loadBackups() async throws -> [RepositoryBackup] {
        try await backing.loadBackups()
    }

    func createBackup(
        for repositoryURL: URL,
        reason: RepositoryBackupReason,
        policy: RepositoryBackupPolicy
    ) async throws -> RepositoryBackup? {
        createCallCount += 1
        return try await backing.createBackup(for: repositoryURL, reason: reason, policy: policy)
    }

    func restore(_ backup: RepositoryBackup, to destinationURL: URL) async throws -> URL {
        try await backing.restore(backup, to: destinationURL)
    }

    func delete(_ backup: RepositoryBackup) async throws {
        try await backing.delete(backup)
    }

    func deleteBackups(forRepositoryPath repositoryPath: String?) async throws {
        try await backing.deleteBackups(forRepositoryPath: repositoryPath)
    }

    func pruneBackups(retainingPerRepository limit: Int) async throws {
        try await backing.pruneBackups(retainingPerRepository: limit)
    }

    func directory(for backup: RepositoryBackup) async throws -> URL {
        try await backing.directory(for: backup)
    }

    func storageByteCount() async throws -> Int64 {
        try await backing.storageByteCount()
    }

    func storageDirectory() async -> URL {
        await backing.storageDirectory()
    }

    func migrateStorage(to destinationURL: URL) async throws -> URL {
        try await backing.migrateStorage(to: destinationURL)
    }
}

private struct BackupFixture {
    let root: URL
    let repository: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoBackupTests-\(UUID().uuidString)", isDirectory: true)
        repository = root.appendingPathComponent("repository", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try git(["init", "-b", "main"], at: repository)
        try git(["config", "user.name", "GitGatto Test"], at: repository)
        try git(["config", "user.email", "gitgatto@example.invalid"], at: repository)
        try "base\n".write(
            to: repository.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "delete me\n".write(
            to: repository.appendingPathComponent("deleted.txt"),
            atomically: true,
            encoding: .utf8
        )
        try git(["add", "tracked.txt", "deleted.txt"], at: repository)
        try git(["commit", "-m", "Initial commit"], at: repository)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

@discardableResult
private func git(_ arguments: [String], at directory: URL) throws -> String {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", directory.path] + arguments
    process.standardOutput = output
    process.standardError = error
    process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
    try process.run()
    process.waitUntilExit()
    let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard process.terminationStatus == 0 else {
        throw GitCommandError(
            arguments: arguments,
            exitCode: process.terminationStatus,
            message: stderr
        )
    }
    return stdout
}
