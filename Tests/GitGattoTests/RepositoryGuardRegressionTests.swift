import Foundation
import Testing
@testable import GitGatto

@Suite("Repository guard regressions", .serialized)
struct RepositoryGuardRegressionTests {
    @Test("Unchanged guard checkpoints reuse the newest backup and preserve retention slots")
    func reusesUnchangedCheckpoint() async throws {
        let fixture = try await GuardFixture.make()
        defer { fixture.remove() }
        let manual = try #require(await fixture.service.createBackup(for: fixture.repository, reason: .manual, policy: .standard))
        for _ in 0..<4 {
            let next = try #require(await fixture.service.createBackup(for: fixture.repository, reason: .externalCheckpoint, policy: .standard))
            #expect(next.id == manual.id)
        }
        #expect(try await fixture.service.loadBackups().count == 1)
    }

    @Test("A checkpoint with missing payload is rebuilt instead of being reused")
    func rebuildsIncompleteCheckpoint() async throws {
        let fixture = try await GuardFixture.make()
        defer { fixture.remove() }
        try fixture.write("tracked.txt", "uncommitted content\n")
        let before = try #require(await fixture.service.createBackup(for: fixture.repository, reason: .externalCheckpoint, policy: .standard))
        let directory = try await fixture.service.directory(for: before)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("workspace/tracked.txt"))
        let repaired = try #require(await fixture.service.createBackup(for: fixture.repository, reason: .externalCheckpoint, policy: .standard))
        #expect(repaired.id != before.id)
        let destination = fixture.root.appendingPathComponent("restored")
        _ = try await fixture.service.restore(repaired, to: destination)
        #expect(try String(contentsOf: destination.appendingPathComponent("tracked.txt"), encoding: .utf8) == "uncommitted content\n")
    }

    @MainActor
    @Test("Committing preserved work does not report lost changes or a destructive threshold")
    func acceptsNormalCommit() async throws {
        let fixture = try await GuardFixture.make()
        defer { fixture.remove() }
        let model = fixture.model()
        for index in 0..<21 { try fixture.write("file-\(index).txt", "new\n") }
        try fixture.write("tracked.txt", "checkpoint\n")
        await model.createExternalRepositoryProtectionBaseline(for: fixture.repository)
        try fixture.write("tracked.txt", "intended update\n")
        try await fixture.git(["add", "."])
        try await fixture.git(["commit", "-m", "save work"])
        await model.auditExternalRepositoryChange(for: fixture.repository)
        #expect(model.repositoryProtectionIncidents.isEmpty)
        #expect(try await fixture.service.loadBackups().first?.headSHA == fixture.head())
    }

    @MainActor
    @Test("Renaming a backed-up edit preserves its content without a deletion alert")
    func acceptsEditedRename() async throws {
        let fixture = try await GuardFixture.make()
        defer { fixture.remove() }
        let model = fixture.model()
        try fixture.write("tracked.txt", "preserved edit\n")
        await model.createExternalRepositoryProtectionBaseline(for: fixture.repository)
        try await fixture.git(["mv", "tracked.txt", "renamed.txt"])
        await model.auditExternalRepositoryChange(for: fixture.repository)
        #expect(model.repositoryProtectionIncidents.isEmpty)
    }

    @MainActor
    @Test("Large normal edits create a new baseline instead of freezing automatic protection")
    func acceptsLargeEditAndMeasuresActualLines() async throws {
        let fixture = try await GuardFixture.make()
        defer { fixture.remove() }
        let model = fixture.model()
        try fixture.write("tracked.txt", String(repeating: "A\n", count: 600))
        await model.createExternalRepositoryProtectionBaseline(for: fixture.repository)
        let before = try #require(try await fixture.service.loadBackups().first)
        try fixture.write("tracked.txt", String(repeating: "B\n", count: 600))
        let assessment = try await fixture.service.assessChanges(after: before, in: fixture.repository)
        #expect(assessment.changedLineCountSinceBaseline == 1_200)
        await model.auditExternalRepositoryChange(for: fixture.repository)
        #expect(model.repositoryProtectionIncidents.isEmpty)
        #expect(try await fixture.service.loadBackups().first?.id != before.id)
    }

    @MainActor
    @Test("Discarding an edit and cleaning an untracked file still preserve the old recovery point")
    func detectsDiscardAndClean() async throws {
        let fixture = try await GuardFixture.make()
        defer { fixture.remove() }
        let model = fixture.model()
        try fixture.write("tracked.txt", "valuable edit\n")
        try fixture.write("notes.txt", "valuable untracked work\n")
        await model.createExternalRepositoryProtectionBaseline(for: fixture.repository)
        let before = try #require(try await fixture.service.loadBackups().first)
        try await fixture.git(["restore", "tracked.txt"])
        try await fixture.git(["clean", "-f", "--", "notes.txt"])
        await model.auditExternalRepositoryChange(for: fixture.repository)
        let incident = try #require(model.repositoryProtectionIncidents.first)
        #expect(incident.assessment?.lostChangedPaths == ["tracked.txt"])
        #expect(incident.assessment?.deletedPaths == ["notes.txt"])
        #expect(incident.backup.id == before.id)
        #expect(try await fixture.service.loadBackups().count == 1)
    }

    @MainActor
    @Test("A hard reset that rewinds the current branch still requires review")
    func detectsHistoryRewind() async throws {
        let fixture = try await GuardFixture.make()
        defer { fixture.remove() }
        try fixture.write("tracked.txt", "committed work\n")
        try await fixture.git(["commit", "-am", "second commit"])
        let model = fixture.model()
        await model.createExternalRepositoryProtectionBaseline(for: fixture.repository)
        try await fixture.git(["reset", "--hard", "HEAD~1"])
        await model.auditExternalRepositoryChange(for: fixture.repository)
        #expect(model.repositoryProtectionIncidents.count == 1)
    }

    @Test("Guard deduplication notices refs and branch identity, not just working files")
    func preservesReferenceChanges() async throws {
        let fixture = try await GuardFixture.make()
        defer { fixture.remove() }
        let before = try #require(await fixture.service.createBackup(for: fixture.repository, reason: .externalCheckpoint, policy: .standard))
        try await fixture.git(["tag", "saved"])
        let tagged = try #require(await fixture.service.createBackup(for: fixture.repository, reason: .externalCheckpoint, policy: .standard))
        #expect(tagged.id != before.id)
        try await fixture.git(["switch", "-c", "feature"])
        let branched = try #require(await fixture.service.createBackup(for: fixture.repository, reason: .externalCheckpoint, policy: .standard))
        #expect(branched.id != tagged.id)
        #expect(branched.branchName == "feature")
    }
    @MainActor
    @Test("Switching clean branches does not look like history loss")
    func acceptsCleanBranchSwitch() async throws {
        let fixture = try await GuardFixture.make()
        defer { fixture.remove() }
        try await fixture.git(["branch", "other"])
        try fixture.write("tracked.txt", "main change\n")
        try await fixture.git(["commit", "-am", "main change"])
        let model = fixture.model()
        await model.createExternalRepositoryProtectionBaseline(for: fixture.repository)
        try await fixture.git(["switch", "other"])
        await model.auditExternalRepositoryChange(for: fixture.repository)
        #expect(model.repositoryProtectionIncidents.isEmpty)
    }

    @MainActor
    @Test("Deleting tracked content or Git metadata still raises a protection incident")
    func detectsFileAndMetadataDeletion() async throws {
        for metadata in [false, true] {
            let fixture = try await GuardFixture.make()
            defer { fixture.remove() }
            let model = fixture.model()
            await model.createExternalRepositoryProtectionBaseline(for: fixture.repository)
            try FileManager.default.removeItem(at: fixture.repository.appendingPathComponent(metadata ? ".git" : "tracked.txt"))
            await model.auditExternalRepositoryChange(for: fixture.repository)
            let incident = try #require(model.repositoryProtectionIncidents.first)
            #expect(incident.kind == (metadata ? .repositoryUnavailable : .destructiveChange))
            #expect(try await fixture.service.loadBackups().count == 1)
        }
    }

    @Test("A renamed file's checkpoint restores only its new path")
    func restoresRenameWithoutDuplicatingOriginal() async throws {
        let fixture = try await GuardFixture.make()
        defer { fixture.remove() }
        try await fixture.git(["mv", "tracked.txt", "renamed.txt"])
        let point = try #require(await fixture.service.createBackup(for: fixture.repository, reason: .externalCheckpoint, policy: .standard))
        let destination = fixture.root.appendingPathComponent("restored")
        _ = try await fixture.service.restore(point, to: destination)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("tracked.txt").path))
        #expect(try String(contentsOf: destination.appendingPathComponent("renamed.txt"), encoding: .utf8) == "base\n")
    }

}

private struct GuardFixture {
    let root: URL
    let repository: URL
    let service: RepositoryBackupService

    static func make() async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitGattoGuardRegression-\(UUID().uuidString)")
        let repository = root.appendingPathComponent("repository")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        let fixture = Self(root: root, repository: repository, service: RepositoryBackupService(rootURL: root.appendingPathComponent("backups")))
        try await fixture.git(["init", "-b", "main"])
        try await fixture.git(["config", "user.name", "Guard Tests"])
        try await fixture.git(["config", "user.email", "guard@example.invalid"])
        try fixture.write("tracked.txt", "base\n")
        try await fixture.git(["add", "."])
        try await fixture.git(["commit", "-m", "base"])
        return fixture
    }

    func git(_ arguments: [String]) async throws {
        _ = try await GitCommandRunner().run(at: repository, arguments: arguments,
            environment: ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"])
    }
    func head() async throws -> String {
        try await GitCommandRunner().run(at: repository, arguments: ["rev-parse", "HEAD"]).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func write(_ path: String, _ text: String) throws {
        try text.write(to: repository.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }
    @MainActor func model() -> WorkspaceViewModel {
        let model = WorkspaceViewModel(repositoryBackupService: service)
        model.appPreferences.repositoryBackupEnabled = true
        model.appPreferences.externalRepositoryProtectionEnabled = true
        model.appPreferences.majorBackupFileThreshold = 20
        model.appPreferences.majorBackupLineThreshold = 500
        return model
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
