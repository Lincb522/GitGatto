import AppKit
import Foundation
import SwiftUI
@testable import GitGatto
import Testing

@Suite("Monitoring engine")
struct MonitoringEngineTests {
    @MainActor
    @Test("Configures every monitoring channel independently")
    func configuresChannelsIndependently() {
        let engine = MonitoringEngine()
        var preferences = AppPreferences()
        preferences.remoteRefreshEnabled = false
        preferences.githubActionsMonitoringEnabled = false

        engine.configure(
            preferences: preferences,
            repositories: [URL(fileURLWithPath: "/tmp/repository")],
            selectedRepositoryURL: nil
        )

        #expect(engine.isChannelEnabled(.workingTree))
        #expect(!engine.isChannelEnabled(.remote))
        #expect(engine.isChannelEnabled(.repositoryProtection))
        #expect(!engine.isChannelEnabled(.githubActions))
        #expect(engine.isChannelEnabled(.projectGoals))
        #expect(engine.activeChannelCount == 3)
        #expect(engine.overallState == .healthy)
    }

    @MainActor
    @Test("Master switch pauses every monitoring channel")
    func masterSwitchPausesChannels() {
        let engine = MonitoringEngine()
        var preferences = AppPreferences()
        preferences.monitoringEngineEnabled = false

        engine.configure(
            preferences: preferences,
            repositories: [],
            selectedRepositoryURL: nil
        )

        #expect(engine.overallState == .paused)
        #expect(engine.activeChannelCount == 0)
        #expect(engine.channels.allSatisfy { !$0.isEnabled && $0.state == .paused })
    }

    @Test("Background service combines commit and monitored activity without inventing days")
    func loadsRepositoryActivity() async throws {
        let root = temporaryDirectory("Monitoring")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try run(["init"], at: repository)
        try run(["config", "user.name", "GitGatto Tests"], at: repository)
        try run(["config", "user.email", "tests@example.invalid"], at: repository)
        try "activity\n".write(
            to: repository.appendingPathComponent("activity.txt"),
            atomically: true,
            encoding: .utf8
        )
        try run(["add", "activity.txt"], at: repository)
        try run(["commit", "-m", "Record activity"], at: repository)

        let service = BackgroundMonitoringService(
            rootURL: root.appendingPathComponent("store", isDirectory: true)
        )
        _ = try await service.recordRepositoryChange(
            at: repository,
            minimumInterval: 0
        )
        let activity = try await service.dailyActivity(for: repository)
        let today = try #require(activity.last(where: { Calendar.current.isDateInToday($0.date) }))

        #expect(today.commitCount == 1)
        #expect(today.monitoredChangeCount == 1)
        #expect(activity.count == 371)
    }

    @MainActor
    @Test(
        "Status bar monitoring surface renders at its supported size",
        .enabled(if: ProcessInfo.processInfo.environment["GITGATTO_MONITORING_SNAPSHOT"] != nil)
    )
    func rendersStatusBarSurface() async throws {
        _ = NSApplication.shared
        let model = WorkspaceViewModel()
        let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        await model.openRepository(repository, showFailure: false)
        model.monitoringEngine.configure(
            preferences: model.appPreferences,
            repositories: [repository],
            selectedRepositoryURL: repository
        )
        for _ in 0 ..< 80 where model.monitoringEngine.dailyActivity.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!model.monitoringEngine.dailyActivity.isEmpty)

        let content = AppThemeRoot {
            MonitoringStatusBarView(model: model, engine: model.monitoringEngine)
        }
        .frame(width: 430, height: 620)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 430, height: 620)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        window.layoutIfNeeded()
        window.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(bitmap.pixelsWide >= 430)
        #expect(bitmap.pixelsHigh >= 620)
        #expect(data.count > 10_000)

        if let outputPath = ProcessInfo.processInfo.environment["GITGATTO_MONITORING_SNAPSHOT"] {
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
    }

    private func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGatto\(name)Tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func run(_ arguments: [String], at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = Pipe()
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw TestGitError(output: output)
        }
    }
}

private struct TestGitError: Error {
    let output: String
}
