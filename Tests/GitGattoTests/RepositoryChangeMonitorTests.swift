import Foundation
@testable import GitGatto
import Testing

@Suite(.serialized)
struct RepositoryChangeMonitorTests {
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
        ) {
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
        let monitor = RepositoryChangeMonitor(repositoryURL: root, includesGitMetadata: false) {
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
            includesGitObjectChanges: true, filtersIgnoredPaths: true) { Task { await counter.increment() } }
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
