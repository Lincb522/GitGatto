import Foundation
import Sparkle
import Testing
@testable import GitGatto

@Suite("Remaining optimization contracts")
struct RemainingOptimizationTests {
    @MainActor @Test func updateFailureStagesAndRedaction() {
        for (code, stage) in [(1000, AppUpdateStage.checking), (2001, .downloading), (3001, .verifying), (4005, .installing), (4012, .installing)] {
            let error = NSError(domain: SUSparkleErrorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: "Failure at https://example.com/download?key=synthetic-secret"])
            let diagnostic = AppUpdateDiagnostic.make(error: error, lastStage: .unknown)
            #expect(diagnostic.stage == stage)
            #expect(!diagnostic.report(version: "test", build: "1").contains("synthetic-secret"))
        }
        let generic = NSError(domain: "fixture", code: 9)
        #expect(AppUpdateDiagnostic.make(error: generic, lastStage: .unknown).stage == .unknown)
        let network = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        #expect(AppUpdateDiagnostic.make(error: network, lastStage: .downloading).stage == .downloading)
    }

    @Test func preferencesReopenAndFailedSavePreservesLastSavedValues() throws {
        let name = "GitGatto-settings-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var preferences = AppPreferences()
        preferences.liveRefreshInterval = 4
        preferences.monitoringEngineEnabled = false
        #expect(AppPreferencesStore.save(preferences, defaults: defaults))
        #expect(AppPreferencesStore.load(defaults: defaults) == preferences)
        var invalid = preferences
        invalid.liveRefreshInterval = .nan
        #expect(!AppPreferencesStore.save(invalid, defaults: defaults))
        #expect(AppPreferencesStore.load(defaults: defaults) == preferences)
        let reopened = try #require(UserDefaults(suiteName: name))
        #expect(AppPreferencesStore.load(defaults: reopened) == preferences)
    }

    @Test func bundlesContainExistingUniqueTools() {
        #expect(Set(DevelopmentToolBundle.all.map(\.id)).count == DevelopmentToolBundle.all.count)
        for bundle in DevelopmentToolBundle.all {
            #expect(bundle.tools.count == bundle.toolIDs.count)
            #expect(Set(bundle.toolIDs).count == bundle.toolIDs.count)
        }
    }

    @Test func receiptSurvivesTaskStorageAndOldRecordsDecode() throws {
        var record = DevelopmentToolTaskRecord(id: UUID(), toolID: "git", operation: .install,
            createdAt: Date(), updatedAt: Date(), state: .completed)
        record.receipt = .init(executableVerified: true, verificationDetail: nil,
            profilePath: "/tmp/fixture/.zprofile", environmentState: "updated", environmentError: nil, agentConfigurationComplete: false)
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(DevelopmentToolTaskRecord.self, from: data) == record)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "receipt")
        #expect(try JSONDecoder().decode(DevelopmentToolTaskRecord.self, from: JSONSerialization.data(withJSONObject: json)).receipt == nil)
    }

    @Test func fileRestorePreviewRejectsStaleWorkingFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitGatto-restore-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = GitCommandRunner()
        _ = try await runner.run(at: root, arguments: ["init", "-b", "main"])
        _ = try await runner.run(at: root, arguments: ["config", "user.name", "Fixture"])
        _ = try await runner.run(at: root, arguments: ["config", "user.email", "fixture@example.invalid"])
        let file = root.appendingPathComponent("file.txt")
        try Data("before\n".utf8).write(to: file)
        _ = try await runner.run(at: root, arguments: ["add", "file.txt"])
        _ = try await runner.run(at: root, arguments: ["-c", "commit.gpgsign=false", "commit", "-m", "fixture"])
        let revision = try #require(try await GitFileHistoryService().history(for: "file.txt", in: root).first)
        try Data("current\n".utf8).write(to: file)
        let service = FileRestorePreviewService()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        let preview = try await service.preview(path: "file.txt", revision: revision, repository: root)
        #expect(try String(contentsOf: file, encoding: .utf8) == "current\n")
        #expect(preview.diff.additionCount > 0)
        try Data("new edit\n".utf8).write(to: file)
        await #expect(throws: FileRestorePreviewError.self) { try await service.restore(preview) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "new edit\n")
        let refreshed = try await service.preview(path: "file.txt", revision: revision, repository: root)
        try await service.restore(refreshed)
        #expect(try String(contentsOf: file, encoding: .utf8) == "before\n")
        #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o755)
        let staged = try await runner.run(at: root, arguments: ["diff", "--cached", "--name-only"])
        #expect(staged.text.isEmpty)
    }
}
