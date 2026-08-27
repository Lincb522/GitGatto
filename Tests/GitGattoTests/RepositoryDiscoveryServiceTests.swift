import Foundation
import Testing
@testable import GitGatto

@Suite("Local repository discovery")
struct RepositoryDiscoveryServiceTests {
    @Test("Finds Git repositories and skips generated dependency trees")
    func discoversRepositories() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = root.appendingPathComponent("Projects/First", isDirectory: true)
        let second = root.appendingPathComponent("Workspace/Second", isDirectory: true)
        let secondGitDirectory = root.appendingPathComponent("Workspace/metadata/second.git", isDirectory: true)
        let dependency = root.appendingPathComponent("Projects/First/node_modules/Dependency", isDirectory: true)
        let nestedRepository = root.appendingPathComponent("Projects/First/Tools/Nested", isDirectory: true)
        let derivedCheckout = root.appendingPathComponent(
            "Build/AgentDerivedData/SourcePackages/checkouts/Generated",
            isDirectory: true
        )
        let restricted = root.appendingPathComponent("Restricted", isDirectory: true)
        try FileManager.default.createDirectory(
            at: first.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "ref: refs/heads/main\n".write(
            to: first.appendingPathComponent(".git/HEAD"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondGitDirectory, withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(
            to: secondGitDirectory.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
        try "gitdir: ../metadata/second.git\n".write(
            to: second.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: dependency.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: nestedRepository.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "ref: refs/heads/main\n".write(
            to: nestedRepository.appendingPathComponent(".git/HEAD"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: derivedCheckout.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "ref: refs/heads/main\n".write(
            to: derivedCheckout.appendingPathComponent(".git/HEAD"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: restricted.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "ref: refs/heads/main\n".write(
            to: restricted.appendingPathComponent(".git/HEAD"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: restricted.path
        )

        var discovered: [LocalRepositoryRecord] = []
        for await batch in RepositoryDiscoveryService().repositories(in: [root]) {
            discovered.append(contentsOf: batch)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: restricted.path
        )

        #expect(Set(discovered.map(\.id)) == [
            first.standardizedFileURL.path,
            second.standardizedFileURL.path
        ])

        let restoredCatalog = RepositoryDiscoveryService().catalogRecords(
            for: [nestedRepository, second, first]
        )
        #expect(Set(restoredCatalog.map(\.id)) == [
            first.standardizedFileURL.path,
            second.standardizedFileURL.path
        ])
    }
}
