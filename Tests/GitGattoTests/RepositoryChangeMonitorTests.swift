import CoreServices
import Darwin
import Foundation
@testable import GitGatto
import Testing

@Suite(.serialized)
struct RepositoryChangeMonitorTests {
    @Test("Only clone-source events are filtered, never coalesced changes or recovery signals")
    func cloneEventPolicyPreservesChanges() {
        let root = URL(fileURLWithPath: "/GitGatto-event-policy-fixture")
        let monitor = RepositoryChangeMonitor(repositoryURL: root) { _ in}
        let path = root.appendingPathComponent("source.txt").path
        let cloned = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCloned | kFSEventStreamEventFlagItemIsFile)
        #expect(!monitor.shouldRefresh(path: path, flags: cloned))
        #expect(!monitor.shouldRefresh(path: path, flags: cloned | FSEventStreamEventFlags(kFSEventStreamEventFlagOwnEvent)))
        let changes = [
            kFSEventStreamEventFlagItemCreated, kFSEventStreamEventFlagItemRemoved,
            kFSEventStreamEventFlagItemRenamed, kFSEventStreamEventFlagItemModified,
            kFSEventStreamEventFlagItemInodeMetaMod, kFSEventStreamEventFlagItemFinderInfoMod,
            kFSEventStreamEventFlagItemChangeOwner, kFSEventStreamEventFlagItemXattrMod,
            kFSEventStreamEventFlagMustScanSubDirs, kFSEventStreamEventFlagRootChanged,
        ]
        for change in changes {
            #expect(monitor.shouldRefresh(path: path, flags: cloned | FSEventStreamEventFlags(change)))
        }
        #expect(monitor.shouldRefresh(path: path, flags: cloned | 0x80000000))
    }

    @Test("Clone creation, coalesced editing and chmod remain observable", .timeLimit(.minutes(1)))
    func cloneCreationAndEditingRemainObservable() async throws {
        let fm = FileManager.default
        let fixture = fm.temporaryDirectory.appendingPathComponent("GitGattoCloneMonitor-\(UUID())")
        let root = fixture.appendingPathComponent("repository")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fixture) }
        let runner = GitCommandRunner()
        _ = try await runner.run(at: root, arguments: ["init"])
        let source = root.appendingPathComponent("source.txt")
        try Data(repeating: 65, count: 65_536).write(to: source)
        _ = try await runner.run(at: root, arguments: ["add", "."])
        let counter = RepositoryMonitorEventCounter()
        let monitor = RepositoryChangeMonitor(repositoryURL: root, includesGitObjectChanges: true, filtersIgnoredPaths: true) { _ in
            Task { await counter.increment() }
        }
        monitor.start()
        defer { monitor.stop() }
        try await Task.sleep(for: .seconds(2))
        var before = await counter.value
        let destination = root.appendingPathComponent("new-clone.txt")
        try #require(clonefile(source.path, destination.path, 0) == 0)
        try await expectChange(counter, after: before)
        try await Task.sleep(for: .seconds(2))
        before = await counter.value
        try Data("edited\n".utf8).write(to: source)
        try #require(clonefile(source.path, fixture.appendingPathComponent("edited-copy.txt").path, 0) == 0)
        try await expectChange(counter, after: before)
        try await Task.sleep(for: .seconds(2))
        before = await counter.value
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        try await expectChange(counter, after: before)
    }

    private func expectChange(_ counter: RepositoryMonitorEventCounter, after previous: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while await counter.value == previous, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(await counter.value > previous)
    }

    @Test("The watchdog still detects new root files when file events are unavailable", .timeLimit(.minutes(1)))
    func watchdogDetectsNewFilesWithoutEventStream() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitGattoWatchdog-\(UUID())")
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        _ = try await GitCommandRunner().run(at: root, arguments: ["init"])
        let counter = RepositoryMonitorEventCounter()
        let monitor = RepositoryChangeMonitor(repositoryURL: root, filtersIgnoredPaths: true, eventStreamEnabled: false) { _ in
            Task { await counter.increment() }
        }
        monitor.start()
        defer { monitor.stop() }
        try "new\n".write(to: root.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while await counter.value == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(await counter.value > 0)
    }

    @Test("Status reads preserve the index and do not retrigger monitoring", .timeLimit(.minutes(1)))
    func statusReadsDoNotWriteIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitGattoReadMonitor-\(UUID())")
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let runner = GitCommandRunner()
        _ = try await runner.run(at: root, arguments: ["init"])
        let file = root.appendingPathComponent("tracked.txt")
        try "same contents\n".write(to: file, atomically: true, encoding: .utf8)
        _ = try await runner.run(at: root, arguments: ["add", "."])
        // A clean file with stale stat information makes ordinary git status refresh the index.
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: file.path)
        let index = root.appendingPathComponent(".git/index")
        let originalIndex = try Data(contentsOf: index)
        let counter = RepositoryMonitorEventCounter()
        let monitor = RepositoryChangeMonitor(repositoryURL: root) { _ in Task { await counter.increment() } }
        monitor.start()
        defer { monitor.stop() }
        try await Task.sleep(for: .seconds(2))
        let before = await counter.value
        for _ in 0..<5 {
            _ = try await runner.run(at: root, arguments: ["status", "--porcelain=v1", "-z", "--untracked-files=all"])
        }
        try await Task.sleep(for: .seconds(2))
        #expect(try Data(contentsOf: index) == originalIndex)
        #expect(await counter.value == before)
    }

    @Test("Live monitoring ignores transient locks but still reports external staging", .timeLimit(.minutes(1)))
    func ignoresLocksWithoutHidingStaging() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitGattoLiveLocks-\(UUID())")
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let runner = GitCommandRunner()
        _ = try await runner.run(at: root, arguments: ["init"])
        try "new\n".write(to: root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        let counter = RepositoryMonitorEventCounter()
        let monitor = RepositoryChangeMonitor(repositoryURL: root) { _ in Task { await counter.increment() } }
        monitor.start()
        defer { monitor.stop() }
        try await Task.sleep(for: .seconds(2))
        let before = await counter.value
        let lock = root.appendingPathComponent(".git/index.lock")
        try Data().write(to: lock)
        try await Task.sleep(for: .seconds(2))
        try fm.removeItem(at: lock)
        try await Task.sleep(for: .seconds(2))
        #expect(await counter.value == before)
        _ = try await runner.run(at: root, arguments: ["add", "new.txt"])
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while await counter.value == before, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(await counter.value > before)
    }

    @Test("Reports deletion of a monitored repository root", .timeLimit(.minutes(1)))
    func reportsRepositoryDeletion() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoRepositoryRootMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let counter = RepositoryMonitorEventCounter()
        let monitor = RepositoryChangeMonitor(
            repositoryURL: root,
            includesGitMetadata: true,
            includesGitObjectChanges: true
        ) { _ in
            Task { await counter.increment() }
        }
        monitor.start()
        defer { monitor.stop() }

        try await Task.sleep(for: .milliseconds(500))
        let settledValue = await counter.value
        try FileManager.default.removeItem(at: root)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while await counter.value == settledValue, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }

        #expect(await counter.value > settledValue)
    }

    @Test("Reports file changes without idle callbacks", .timeLimit(.minutes(1)))
    func reportsFileChanges() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoRepositoryMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let counter = RepositoryMonitorEventCounter()
        let monitor = RepositoryChangeMonitor(repositoryURL: root, includesGitMetadata: false) { _ in
            Task { await counter.increment() }
        }
        monitor.start()
        defer { monitor.stop() }

        try await Task.sleep(for: .milliseconds(500))
        let settledValue = await counter.value
        try await Task.sleep(for: .milliseconds(500))
        #expect(await counter.value == settledValue)

        try "changed\n".write(
            to: root.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while await counter.value == settledValue, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(await counter.value > settledValue)
    }
}

private actor RepositoryMonitorEventCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

@Suite("Guard event filtering", .serialized)
struct GuardEventFilteringTests {
    @Test("Ignored build files and Git locks do not trigger guard callbacks, but tracked files and object deletion do", .timeLimit(.minutes(1)))
    func filtersNoiseWithoutHidingRepositoryDamage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitGattoGuardMonitor-\(UUID().uuidString)").resolvingSymlinksInPath()
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let runner = GitCommandRunner()
        _ = try await runner.run(at: root, arguments: ["init"])
        try ".build/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: root.appendingPathComponent(".build"), withIntermediateDirectories: true)
        try "tracked\n".write(to: root.appendingPathComponent(".build/keep.txt"), atomically: true, encoding: .utf8)
        _ = try await runner.run(at: root, arguments: ["add", "-f", ".gitignore", ".build/keep.txt"])
        let counter = RepositoryMonitorEventCounter()
        let monitor = RepositoryChangeMonitor(repositoryURL: root, includesGitMetadata: true,
            includesGitObjectChanges: true, filtersIgnoredPaths: true) { _ in Task { await counter.increment() } }
        monitor.start()
        defer { monitor.stop() }
        try await Task.sleep(for: .seconds(2))
        let before = await counter.value
        try "object output".write(to: root.appendingPathComponent(".build/output.o"), atomically: true, encoding: .utf8)
        try Data().write(to: root.appendingPathComponent(".git/index.lock"))
        try await Task.sleep(for: .seconds(2))
        try fm.removeItem(at: root.appendingPathComponent(".git/index.lock"))
        try await Task.sleep(for: .seconds(2))
        #expect(await counter.value == before)
        try "changed\n".write(to: root.appendingPathComponent(".build/keep.txt"), atomically: true, encoding: .utf8)
        let fileDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await counter.value == before, ContinuousClock.now < fileDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(await counter.value > before)
        let beforeDeletion = await counter.value
        try fm.removeItem(at: root.appendingPathComponent(".git/objects"))
        let deletionDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await counter.value == beforeDeletion, ContinuousClock.now < deletionDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(await counter.value > beforeDeletion)
    }
}
