import AppKit
import Foundation
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Repository change intelligence", .serialized)
struct RepositoryIntelligenceTests {
    @Test("Splits distant hunks into verified atomic commits")
    func appliesAtomicCommitPlan() async throws {
        let fixture = try IntelligenceFixture()
        defer { fixture.remove() }
        let lines = (1...24).map { "line \($0)" }
        try (lines.joined(separator: "\n") + "\n").write(
            to: fixture.repository.appendingPathComponent("Sources/Feature.swift"),
            atomically: true,
            encoding: .utf8
        )
        try fixture.git(["add", "."])
        try fixture.git(["commit", "-m", "Initial"])

        var changed = lines
        changed[1] = "line 2 changed"
        changed[20] = "line 21 changed"
        try (changed.joined(separator: "\n") + "\n").write(
            to: fixture.repository.appendingPathComponent("Sources/Feature.swift"),
            atomically: true,
            encoding: .utf8
        )

        let backupStorage = RepositoryBackupService(rootURL: fixture.backups)
        let workspace = await WorkspaceViewModel(repositoryBackupService: backupStorage)
        let service = await ChangeIntentService(backupService: workspace.repositoryBackupService)
        let migratedDirectory = fixture.root.appendingPathComponent("migrated-backups")
        _ = try await backupStorage.migrateStorage(to: migratedDirectory)
        var plan = try await service.makePlan(in: fixture.repository)
        #expect(plan.units.count == 2)
        let first = try #require(plan.units.first)
        let second = try #require(plan.units.last)
        plan.groups = [
            ChangeIntentGroup(
                title: "First intent",
                commitMessage: "feat: update first intent",
                kind: .implementation,
                unitIDs: [first.id]
            ),
            ChangeIntentGroup(
                title: "Second intent",
                commitMessage: "fix: update second intent",
                kind: .fix,
                unitIDs: [second.id]
            ),
        ]

        let result = try await service.apply(plan, verificationCommand: nil, in: fixture.repository)

        #expect(result.commitHashes.count == 2)
        #expect(try fixture.gitOutput(["status", "--porcelain"]).isEmpty)
        let subjects = try fixture.gitOutput(["log", "-2", "--format=%s"])
            .split(separator: "\n").map(String.init)
        #expect(subjects == ["fix: update second intent", "feat: update first intent"])
        await workspace.reloadRepositoryBackups()
        #expect(await workspace.repositoryBackups.count == 1)
        #expect(await workspace.repositoryBackupDirectoryURL == migratedDirectory)
        #expect(try FileManager.default.contentsOfDirectory(atPath: migratedDirectory.path).isEmpty == false)
        #expect(!FileManager.default.fileExists(atPath: fixture.backups.path))
    }

    @Test("Rejects Agent plans that omit or duplicate a change unit")
    func validatesAgentPlanCoverage() throws {
        let units = ["a", "b"].map {
            ChangeIntentUnit(
                id: $0,
                path: "\($0).swift",
                originalPath: nil,
                kind: .wholeFile,
                status: "??",
                hunkHeader: nil,
                patch: nil,
                addedLineCount: 0,
                deletedLineCount: 0
            )
        }
        let plan = ChangeIntentPlan(
            repositoryPath: "/tmp/repo",
            repositoryFingerprint: "fingerprint",
            units: units,
            groups: []
        )
        let valid = try ChangeIntentAgentPlanner.refinedPlan(
            from: #"{"groups":[{"title":"A","message":"feat: a","kind":"implementation","unitIDs":["a"]},{"title":"B","message":"test: b","kind":"tests","unitIDs":["b"]}]}"#,
            original: plan
        )
        #expect(valid.groups.flatMap(\.unitIDs) == ["a", "b"])

        #expect(throws: ChangeIntentError.self) {
            try ChangeIntentAgentPlanner.refinedPlan(
                from: #"{"groups":[{"title":"A","message":"feat: a","kind":"implementation","unitIDs":["a","a"]}]}"#,
                original: plan
            )
        }
    }

    @Test("Keeps a source change with its directly corresponding test")
    func groupsRelatedSourceAndTest() {
        let source = ChangeIntentUnit(
            id: "source",
            path: "Sources/SessionStore.swift",
            originalPath: nil,
            kind: .hunk,
            status: " M",
            hunkHeader: "@@ -1 +1 @@",
            patch: "patch",
            addedLineCount: 1,
            deletedLineCount: 1
        )
        let test = ChangeIntentUnit(
            id: "test",
            path: "Tests/SessionStoreTests.swift",
            originalPath: nil,
            kind: .hunk,
            status: " M",
            hunkHeader: "@@ -1 +1 @@",
            patch: "patch",
            addedLineCount: 1,
            deletedLineCount: 1
        )

        let groups = ChangeIntentService.defaultGroups(for: [source, test])

        #expect(groups.count == 1)
        #expect(Set(groups[0].unitIDs) == ["source", "test"])
        #expect(groups[0].kind == .implementation)
    }

    @Test("Restores HEAD and the original staging boundary when verification fails")
    func rollsBackFailedIntentPlan() async throws {
        let fixture = try IntelligenceFixture()
        defer { fixture.remove() }
        let stagedFile = fixture.repository.appendingPathComponent("Sources/Staged.swift")
        let unstagedFile = fixture.repository.appendingPathComponent("Sources/Unstaged.swift")
        try "let staged = 1\n".write(to: stagedFile, atomically: true, encoding: .utf8)
        try "let unstaged = 1\n".write(to: unstagedFile, atomically: true, encoding: .utf8)
        try fixture.git(["add", "."])
        try fixture.git(["commit", "-m", "Initial"])
        let startingHead = try fixture.gitOutput(["rev-parse", "HEAD"])

        try "let staged = 2\n".write(to: stagedFile, atomically: true, encoding: .utf8)
        try "let unstaged = 2\n".write(to: unstagedFile, atomically: true, encoding: .utf8)
        try fixture.git(["add", "Sources/Staged.swift"])

        let service = ChangeIntentService(
            backupService: RepositoryBackupService(rootURL: fixture.backups)
        )
        let plan = try await service.makePlan(in: fixture.repository)
        await #expect(throws: ChangeIntentError.self) {
            _ = try await service.apply(
                plan,
                verificationCommand: "exit 19",
                in: fixture.repository
            )
        }

        #expect(try fixture.gitOutput(["rev-parse", "HEAD"]) == startingHead)
        #expect(try fixture.gitOutput(["diff", "--cached", "--name-only"]) == "Sources/Staged.swift")
        #expect(try fixture.gitOutput(["diff", "--name-only"]) == "Sources/Unstaged.swift")
        #expect(try String(contentsOf: stagedFile, encoding: .utf8) == "let staged = 2\n")
        #expect(try String(contentsOf: unstagedFile, encoding: .utf8) == "let unstaged = 2\n")
    }

    @Test("Traces a line to its local originating commit")
    func tracesLocalCodeProvenance() async throws {
        let fixture = try IntelligenceFixture()
        defer { fixture.remove() }
        let file = fixture.repository.appendingPathComponent("Sources/Origin.swift")
        try "let answer = 42\n".write(to: file, atomically: true, encoding: .utf8)
        try fixture.git(["add", "."])
        try fixture.git(["commit", "-m", "Add answer"])

        let report = try await CodeProvenanceService().trace(
            filePath: "Sources/Origin.swift",
            line: 1,
            in: fixture.repository
        )

        #expect(report.sourceText == "let answer = 42")
        #expect(report.commit.subject == "Add answer")
        #expect(report.commit.changedPaths == ["Sources/Origin.swift"])
        #expect(report.pullRequest == nil)
        #expect(report.remoteUnavailableReason != nil)
    }

    @Test("Parses GitHub remotes without changing repository names that contain dot-git")
    func parsesRemoteIdentity() throws {
        let https = try #require(CodeProvenanceService.parseRemote(
            "https://github.com/Lincb522/my.git-tools.git"
        ))
        let ssh = try #require(CodeProvenanceService.parseRemote(
            "git@github.example.com:team/my.git-tools.git"
        ))

        #expect(https.host == "github.com")
        #expect(https.fullName == "Lincb522/my.git-tools")
        #expect(ssh.host == "github.example.com")
        #expect(ssh.fullName == "team/my.git-tools")
    }

    @Test("Exports a redacted capsule and restores it in an isolated worktree")
    func roundTripsFailureCapsule() async throws {
        let fixture = try IntelligenceFixture()
        defer { fixture.remove() }
        let tracked = fixture.repository.appendingPathComponent("Sources/Capsule.swift")
        try "let value = 1\n".write(to: tracked, atomically: true, encoding: .utf8)
        try fixture.git(["add", "."])
        try fixture.git(["commit", "-m", "Initial"])

        try "let value = 2\n".write(to: tracked, atomically: true, encoding: .utf8)
        try "safe notes\n".write(
            to: fixture.repository.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "TOKEN=secret\n".write(
            to: fixture.repository.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )

        let archive = fixture.root.appendingPathComponent("failure.gatto")
        let service = ReproductionCapsuleService(
            rootURL: fixture.capsules,
            worktreeRootURL: fixture.worktrees
        )
        let exported = try await service.export(
            from: fixture.repository,
            failingCommand: "tool --token github_pat_supersecret",
            failureOutput: "https://github_pat_supersecret@github.com/repo failed",
            to: archive
        )

        #expect(FileManager.default.fileExists(atPath: archive.path))
        #expect(exported.manifest.copiedUntrackedPaths == ["notes.txt"])
        #expect(exported.manifest.omittedPaths == [".env"])
        #expect(exported.manifest.failingCommand?.contains("supersecret") == false)
        #expect(exported.manifest.failureOutput?.contains("supersecret") == false)

        let importedService = ReproductionCapsuleService(
            rootURL: fixture.importedCapsules,
            worktreeRootURL: fixture.worktrees
        )
        let imported = try await importedService.importArchive(at: archive)
        let restored = try await importedService.restore(imported, in: fixture.repository)

        #expect(try String(contentsOf: restored.appendingPathComponent("Sources/Capsule.swift"), encoding: .utf8) == "let value = 2\n")
        #expect(try String(contentsOf: restored.appendingPathComponent("notes.txt"), encoding: .utf8) == "safe notes\n")
        #expect(!FileManager.default.fileExists(atPath: restored.appendingPathComponent(".env").path))
        #expect(try fixture.gitOutput(["-C", restored.path, "status", "--porcelain"]).contains("Sources/Capsule.swift"))
    }

    @Test("Records repository changes without inventing an Agent identity")
    func recordsUnattributedRepositoryActivity() async throws {
        let fixture = try IntelligenceFixture()
        defer { fixture.remove() }
        let file = fixture.repository.appendingPathComponent("Sources/Ledger.swift")
        try "let state = 1\n".write(to: file, atomically: true, encoding: .utf8)
        try fixture.git(["add", "."])
        try fixture.git(["commit", "-m", "Initial"])

        let ledger = RepositoryActivityLedger(rootURL: fixture.ledger)
        await ledger.seed([fixture.repository])
        try "let state = 2\n".write(to: file, atomically: true, encoding: .utf8)
        await ledger.recordChange(in: fixture.repository)
        let events = await ledger.events(for: fixture.repository)
        let event = try #require(events.first)

        #expect(event.changedPaths == ["Sources/Ledger.swift"])
        #expect(event.refChanged == false)
        if event.candidates.isEmpty {
            #expect(event.confidence == .unknown)
        } else {
            #expect(event.confidence != .high)
        }
    }

    @MainActor
    @Test("Change Center renders real repository data in light and dark appearances")
    func rendersChangeCenter() async throws {
        let fixture = try IntelligenceFixture()
        defer { fixture.remove() }
        let file = fixture.repository.appendingPathComponent("Sources/Preview.swift")
        try "let preview = 1\n".write(to: file, atomically: true, encoding: .utf8)
        try fixture.git(["add", "."])
        try fixture.git(["commit", "-m", "Initial"])
        try "let preview = 2\n".write(to: file, atomically: true, encoding: .utf8)

        let workspace = WorkspaceViewModel()
        workspace.appPreferences.monitoringEngineEnabled = false
        await workspace.openRepository(fixture.repository)
        let intelligence = RepositoryIntelligenceViewModel(
            intentService: ChangeIntentService(
                backupService: RepositoryBackupService(rootURL: fixture.backups)
            ),
            capsuleService: ReproductionCapsuleService(
                rootURL: fixture.capsules,
                worktreeRootURL: fixture.worktrees
            ),
            activityLedger: RepositoryActivityLedger(rootURL: fixture.ledger)
        )
        intelligence.load(repositoryURL: fixture.repository)
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while intelligence.intentPlan == nil,
              intelligence.intentError == nil,
              ContinuousClock.now < deadline
        {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(intelligence.intentPlan != nil)

        let light = RepositoryIntelligenceWorkspaceView(model: intelligence, workspaceModel: workspace)
            .frame(width: 1_100, height: 700)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
            .environment(\.colorScheme, .light)
        let lightData = try render(light, width: 1_100, height: 700)
        #expect(lightData.count > 20_000)

        intelligence.selectedTab = .capsules
        let dark = RepositoryIntelligenceWorkspaceView(model: intelligence, workspaceModel: workspace)
            .frame(width: 1_100, height: 700)
            .environment(\.locale, Locale(identifier: "en"))
            .environment(\.colorScheme, .dark)
        let darkData = try render(dark, width: 1_100, height: 700)
        #expect(darkData.count > 20_000)

        if let outputPath = ProcessInfo.processInfo.environment["GITGATTO_INTELLIGENCE_SNAPSHOT_DIRECTORY"] {
            let output = URL(fileURLWithPath: outputPath, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try lightData.write(to: output.appendingPathComponent("change-center-intent-light.png"), options: .atomic)
            try darkData.write(to: output.appendingPathComponent("change-center-capsules-dark.png"), options: .atomic)
        }
    }

    @MainActor
    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat) throws -> Data {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        let representation = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        return try #require(representation.representation(using: .png, properties: [:]))
    }
}

private struct IntelligenceFixture {
    let root: URL
    let repository: URL
    let backups: URL
    let capsules: URL
    let importedCapsules: URL
    let worktrees: URL
    let ledger: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGatto-Intelligence-\(UUID().uuidString)", isDirectory: true)
        repository = root.appendingPathComponent("repository", isDirectory: true)
        backups = root.appendingPathComponent("backups", isDirectory: true)
        capsules = root.appendingPathComponent("capsules", isDirectory: true)
        importedCapsules = root.appendingPathComponent("imported-capsules", isDirectory: true)
        worktrees = root.appendingPathComponent("worktrees", isDirectory: true)
        ledger = root.appendingPathComponent("ledger", isDirectory: true)
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try git(["init", "--initial-branch=main"])
        try git(["config", "user.name", "GitGatto Test"])
        try git(["config", "user.email", "gitgatto@example.invalid"])
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func git(_ arguments: [String]) throws -> String {
        try gitOutput(arguments)
    }

    func gitOutput(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repository
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw IntelligenceTestError.commandFailed(text)
        }
        return text
    }
}

private enum IntelligenceTestError: Error {
    case commandFailed(String)
}
