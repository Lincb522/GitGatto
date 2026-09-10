import Foundation
@testable import GitGatto
import Testing

@Suite("Repository event scheduling", .serialized)
struct RepositoryEventSchedulerTests {
    @MainActor
    @Test("A monitored Git repository converges after saves and external staging during a refresh", .timeLimit(.minutes(3)))
    func convergesAfterExternalChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitGattoEventPipeline-\(UUID())")
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let runner = GitCommandRunner()
        _ = try await runner.run(at: root, arguments: ["init"])
        let tracked = root.appendingPathComponent("tracked.txt")
        try "initial\n".write(to: tracked, atomically: true, encoding: .utf8)
        _ = try await runner.run(at: root, arguments: ["add", "."])
        let scheduler = RepositoryEventScheduler()
        let gate = SchedulerGate()
        let service = GitRepositoryService()
        let probe = SchedulerProbe()
        let monitor = RepositoryChangeMonitor(repositoryURL: root, filtersIgnoredPaths: true) {
            Task { @MainActor in
                probe.events += 1
                scheduler.schedule(key: root.path, delay: .milliseconds(100)) {
                    do {
                        let state = try await service.loadLiveState(at: root)
                        probe.reads += 1
                        if probe.reads == 1 { await gate.wait() }
                        probe.changes = state.changes
                    } catch { Issue.record(error) }
                }
            }
        }
        monitor.start()
        defer { monitor.stop(); scheduler.cancelAll() }
        try "first save\n".write(to: tracked, atomically: true, encoding: .utf8)
        try await wait { probe.reads == 1 }
        let before = probe.events
        try fm.removeItem(at: tracked)
        try "untracked\n".write(to: root.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)
        try "stage\n".write(to: root.appendingPathComponent("staged.txt"), atomically: true, encoding: .utf8)
        _ = try await runner.run(at: root, arguments: ["add", "staged.txt"])
        try await wait { probe.events > before }
        await gate.release()
        try await wait { probe.reads >= 2 && probe.changes.contains { $0.path == "untracked.txt" } }
        #expect(probe.changes.contains { $0.path == "untracked.txt" && $0.workTreeStatus == .untracked })
        #expect(probe.changes.contains { $0.path == "staged.txt" && $0.isStaged })
        #expect(probe.changes.contains { $0.path == "tracked.txt" && $0.workTreeStatus == .deleted })
    }

    @MainActor
    @Test("A burst shares one window and uses the latest request")
    func coalescesBursts() async throws {
        let scheduler = RepositoryEventScheduler()
        let probe = SchedulerProbe()
        for index in 0..<100 {
            scheduler.schedule(key: "repo", delay: .milliseconds(50)) { probe.values.append(index) }
        }
        try await wait { !probe.values.isEmpty }
        #expect(probe.values == [99])
    }

    @MainActor
    @Test("Events during an active scan produce exactly one follow-up without cancelling it")
    func preservesChangesDuringScan() async throws {
        let scheduler = RepositoryEventScheduler()
        let gate = SchedulerGate()
        let probe = SchedulerProbe()
        let operation: @MainActor @Sendable () async -> Void = {
            probe.starts += 1
            if probe.starts == 1 { await gate.wait() }
            #expect(!Task.isCancelled)
            probe.completions += 1
        }
        scheduler.schedule(key: "repo", delay: .milliseconds(20), operation: operation)
        try await wait { probe.starts == 1 }
        for _ in 0..<30 {
            scheduler.schedule(key: "repo", delay: .milliseconds(20), operation: operation)
        }
        #expect(probe.starts == 1)
        #expect(probe.completions == 0)
        await gate.release()
        try await wait { probe.completions == 2 }
        #expect(probe.starts == 2)
    }

    @MainActor
    @Test("Continuous saves do not indefinitely postpone the first scan")
    func boundsContinuousWrites() async throws {
        let scheduler = RepositoryEventScheduler()
        let probe = SchedulerProbe()
        for index in 0..<20 {
            probe.delivered = index
            scheduler.schedule(key: "repo", delay: .milliseconds(60)) {
                if probe.firstScanAfterEvent == nil { probe.firstScanAfterEvent = probe.delivered }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await wait { probe.firstScanAfterEvent != nil }
        #expect(try #require(probe.firstScanAfterEvent) < 19)
        scheduler.cancelAll()
    }

    @MainActor
    @Test("Cancellation removes pending reads, and a new scope can schedule immediately")
    func cancelsOldScope() async throws {
        let scheduler = RepositoryEventScheduler()
        let probe = SchedulerProbe()
        scheduler.schedule(key: "repo", delay: .seconds(1)) { probe.labels.append("old") }
        scheduler.cancelAll()
        scheduler.schedule(key: "repo", delay: .milliseconds(10)) { probe.labels.append("new") }
        try await wait { !probe.labels.isEmpty }
        #expect(probe.labels == ["new"])
    }

    @MainActor
    private func wait(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

@MainActor
private final class SchedulerProbe {
    var reads = 0
    var events = 0
    var changes: [WorkingTreeChange] = []
    var values: [Int] = []
    var labels: [String] = []
    var starts = 0
    var completions = 0
    var delivered = 0
    var firstScanAfterEvent: Int?
}

private actor SchedulerGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
