import Darwin
import Foundation
@testable import GitGatto
import Testing

@Suite("Monitoring workload measurements", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["GITGATTO_MONITOR_MEASUREMENTS"] != nil))
struct MonitoringPerformanceTests {
    @MainActor
    @Test("Measures real Git subprocess cost while live status, activity and protection remain enabled", .timeLimit(.minutes(5)))
    func measureMonitoringWorkload() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GITGATTO_MONITOR_MEASUREMENTS"]))
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("GitGattoMonitorMeasure-\(UUID())")
        let repository = fixture.appendingPathComponent("repository")
        let fm = FileManager.default
        try fm.createDirectory(at: repository, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fixture) }
        let runner = GitCommandRunner()
        _ = try await runner.run(at: repository, arguments: ["init", "-b", "main"])
        for directory in 0..<50 {
            let folder = repository.appendingPathComponent("Sources/Group\(directory)")
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in 0..<50 {
                try Data("let value = \(file)\n".utf8).write(to: folder.appendingPathComponent("File\(file).swift"))
            }
        }
        try Data(".build/\n".utf8).write(to: repository.appendingPathComponent(".gitignore"))
        _ = try await runner.run(at: repository, arguments: ["add", "."])
        // The identity belongs only to this generated fixture, never the developer's Git config.
        _ = try await runner.run(at: repository, arguments: [
            "-c", "user.name=Monitoring Fixture", "-c", "user.email=fixture@example.invalid",
            "-c", "commit.gpgsign=false", "commit", "-m", "Fixture",
        ])
        for file in 0..<250 {
            try Data("untracked \(file)\n".utf8).write(to: repository.appendingPathComponent("New\(file).txt"))
        }
        try fm.createDirectory(at: repository.appendingPathComponent(".build"), withIntermediateDirectories: true)
        let history = BackgroundMonitoringService(rootURL: fixture.appendingPathComponent("activity"))
        let ledger = RepositoryActivityLedger(rootURL: fixture.appendingPathComponent("ledger"))
        let protection = RepositoryBackupService(rootURL: fixture.appendingPathComponent("backups"))
        let baseline = try #require(try await protection.createBackup(for: repository, reason: .externalCheckpoint, policy: .standard))
        let service = GitRepositoryService()
        let engine = MonitoringEngine(backgroundService: history)
        engine.configure(preferences: AppPreferences(), repositories: [repository])
        await ledger.seed([repository])
        let liveScheduler = RepositoryEventScheduler()
        let guardScheduler = RepositoryEventScheduler()
        let ledgerScheduler = RepositoryEventScheduler()
        let probe = MonitoringWorkloadProbe()
        let liveMonitor = RepositoryChangeMonitor(repositoryURL: repository, filtersIgnoredPaths: true) {
            Task { @MainActor in
                probe.callbacks += 1
                engine.recordRepositoryChange(at: repository)
                liveScheduler.schedule(key: repository.path, delay: .seconds(1)) {
                    probe.activeOperations += 1
                    defer { probe.activeOperations -= 1 }
                    do {
                        let state = try await service.loadLiveState(at: repository)
                        probe.statusReads += 1
                        probe.changes = state.changes
                        ledgerScheduler.schedule(key: repository.path, delay: .milliseconds(500)) {
                            probe.activeOperations += 1
                            defer { probe.activeOperations -= 1 }
                            await ledger.recordChange(in: repository, liveState: state)
                        }
                    } catch { probe.errors.append(error.localizedDescription) }
                }
            }
        }
        let guardMonitor = RepositoryChangeMonitor(repositoryURL: repository, includesGitObjectChanges: true, filtersIgnoredPaths: true) {
            Task { @MainActor in
                probe.callbacks += 1
                guardScheduler.schedule(key: repository.path, delay: .seconds(1.5)) {
                    probe.activeOperations += 1
                    defer { probe.activeOperations -= 1 }
                    do {
                        probe.assessment = try await protection.assessChanges(after: baseline, in: repository)
                        probe.guardReads += 1
                    } catch { probe.errors.append(error.localizedDescription) }
                }
            }
        }
        liveMonitor.start()
        guardMonitor.start()
        defer {
            liveMonitor.stop(); guardMonitor.stop()
            liveScheduler.cancelAll(); guardScheduler.cancelAll(); ledgerScheduler.cancelAll()
        }
        try await wait { !engine.dailyActivity.isEmpty }
        try await settle(probe)
        var phases: [MonitoringMeasurement] = []

        var start = MonitoringCPUSample()
        var counts = probe.counts
        try await Task.sleep(for: .seconds(8))
        phases.append(MonitoringMeasurement(name: "idle", start: start, counts: counts, probe: probe))
        #expect(probe.counts == counts)

        start = MonitoringCPUSample(); counts = probe.counts
        for index in 0..<40 {
            try Data("let value = \(index + 100)\n".utf8).write(to: repository.appendingPathComponent("Sources/Group0/File0.swift"), options: .atomic)
            try await Task.sleep(for: .milliseconds(100))
        }
        try await wait { probe.changes.contains { $0.path == "Sources/Group0/File0.swift" } && probe.guardReads > counts[1] }
        try await settle(probe)
        phases.append(MonitoringMeasurement(name: "40_continuous_saves", start: start, counts: counts, probe: probe))
        #expect(probe.statusReads - counts[0] < 40)

        start = MonitoringCPUSample(); counts = probe.counts
        for index in 0..<1_000 {
            try Data("build output\n".utf8).write(to: repository.appendingPathComponent(".build/\(index).o"))
        }
        try await settle(probe)
        phases.append(MonitoringMeasurement(name: "1000_ignored_build_files", start: start, counts: counts, probe: probe))
        #expect(probe.counts == counts)

        start = MonitoringCPUSample(); counts = probe.counts
        _ = try await runner.run(at: repository, arguments: ["add", "Sources/Group0/File0.swift"])
        try fm.removeItem(at: repository.appendingPathComponent("Sources/Group1/File1.swift"))
        try Data("new file\n".utf8).write(to: repository.appendingPathComponent("AddedDuringMonitoring.txt"))
        try await wait {
            probe.changes.contains { $0.path == "Sources/Group0/File0.swift" && $0.isStaged }
                && probe.changes.contains { $0.path == "AddedDuringMonitoring.txt" && $0.workTreeStatus == .untracked }
                && probe.assessment?.deletedPaths.contains("Sources/Group1/File1.swift") == true
        }
        try await settle(probe)
        phases.append(MonitoringMeasurement(name: "external_stage_delete_and_new_file", start: start, counts: counts, probe: probe))

        start = MonitoringCPUSample(); counts = probe.counts
        try await Task.sleep(for: .seconds(8))
        phases.append(MonitoringMeasurement(name: "idle_after_changes", start: start, counts: counts, probe: probe))
        #expect(probe.counts == counts)
        #expect(probe.errors.isEmpty)
        #expect(await history.historyQueryCount == 1)
        #expect(await ledger.statusQueryCount == 1)
        let report = MonitoringWorkloadReport(
            trackedFileCount: 2_501, untrackedFileCount: 250,
            historyReads: await history.historyQueryCount,
            ledgerIndependentStatusReads: await ledger.statusQueryCount,
            phases: phases,
            errors: probe.errors
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(report).write(to: output, options: .atomic)
    }

    @MainActor
    private func wait(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(40))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        try #require(condition())
    }

    @MainActor
    private func settle(_ probe: MonitoringWorkloadProbe) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(45))
        var unchangedSince = ContinuousClock.now
        var counts = probe.counts
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
            if probe.counts != counts || probe.activeOperations > 0 {
                unchangedSince = .now
                counts = probe.counts
            } else if unchangedSince.duration(to: .now) >= .seconds(3) { return }
        }
        Issue.record("Monitoring workload did not settle")
    }
}

@MainActor
private final class MonitoringWorkloadProbe {
    var callbacks = 0
    var statusReads = 0
    var guardReads = 0
    var activeOperations = 0
    var changes: [WorkingTreeChange] = []
    var assessment: RepositoryProtectionAssessment?
    var errors: [String] = []
    var counts: [Int] { [statusReads, guardReads, callbacks] }
}

private struct MonitoringCPUSample {
    let time = ContinuousClock.now
    let parent: Double
    let children: Double

    init() {
        var own = rusage(), child = rusage()
        getrusage(RUSAGE_SELF, &own)
        getrusage(RUSAGE_CHILDREN, &child)
        parent = Self.seconds(own)
        children = Self.seconds(child)
    }

    private static func seconds(_ usage: rusage) -> Double {
        Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
}

private struct MonitoringMeasurement: Codable {
    let name: String
    let wallSeconds: Double
    let testProcessCPUSeconds: Double
    let childProcessCPUSeconds: Double
    let statusReads: Int
    let guardReads: Int
    let callbacks: Int

    @MainActor
    init(name: String, start: MonitoringCPUSample, counts: [Int], probe: MonitoringWorkloadProbe) {
        let end = MonitoringCPUSample()
        let duration = start.time.duration(to: end.time).components
        self.name = name
        wallSeconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        testProcessCPUSeconds = end.parent - start.parent
        childProcessCPUSeconds = end.children - start.children
        statusReads = probe.statusReads - counts[0]
        guardReads = probe.guardReads - counts[1]
        callbacks = probe.callbacks - counts[2]
    }
}

private struct MonitoringWorkloadReport: Codable {
    let trackedFileCount: Int
    let untrackedFileCount: Int
    let historyReads: Int
    let ledgerIndependentStatusReads: Int
    let phases: [MonitoringMeasurement]
    let errors: [String]
}
