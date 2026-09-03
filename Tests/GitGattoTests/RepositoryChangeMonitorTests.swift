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
