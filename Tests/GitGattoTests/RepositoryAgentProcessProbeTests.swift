import Darwin
import Foundation
@testable import GitGatto
import Testing

@Suite("Repository Agent process attribution", .serialized)
struct RepositoryAgentProcessProbeTests {
    @Test("Recognizes Agent executables without substring false positives")
    func executableNames() {
        for name in ["codex", "claude", "gemini", "cursor", "copilot", "aider", "opencode", "amp", "goose", "continue", "zed-agent"] {
            #expect(RepositoryAgentProcessProbe.agentName(for: "/fixture/\(name)") == name)
        }
        #expect(RepositoryAgentProcessProbe.agentName(for: "/fixture/Cursor Helper (Renderer)") == "cursor")
        #expect(RepositoryAgentProcessProbe.agentName(for: "/fixture/codex-aarch64-apple-darwin") == "codex")
        #expect(RepositoryAgentProcessProbe.agentName(for: "/fixture/claude_code") == "claude")
        for name in ["sample", "example", "amplitude", "my-codex-notes", "node", "GitGatto",
                     "AMPDeviceDiscoveryAgent", "CursorUIViewService", "SimulatorTrampoline",
                     "AMPLibraryAgent", "AMPArtworkAgent", "SimStreamProcessorService"] {
            #expect(RepositoryAgentProcessProbe.agentName(for: "/fixture/\(name)") == nil)
        }
    }

    @Test("Repository matching respects directory boundaries")
    func directoryBoundaries() {
        #expect(RepositoryAgentProcessProbe.contains(repository: "/fixture/repo", directory: "/fixture/repo"))
        #expect(RepositoryAgentProcessProbe.contains(repository: "/fixture/repo", directory: "/fixture/repo/Sources"))
        #expect(!RepositoryAgentProcessProbe.contains(repository: "/fixture/repo", directory: "/fixture/repo-other"))
        #expect(!RepositoryAgentProcessProbe.contains(repository: "/fixture/repo", directory: "/fixture"))
        #expect(RepositoryAgentProcessProbe.observation(for: 0) == nil)
        #expect(RepositoryAgentProcessProbe.observation(for: -1) == nil)
    }

    @Test("Reads native process metadata on the deployment-target API")
    func currentProcess() throws {
        let observation = try #require(RepositoryAgentProcessProbe.observation(for: getpid()))
        #expect(observation.processID == getpid())
        #expect(!observation.executable.isEmpty)
        #expect(FileManager.default.fileExists(atPath: observation.workingDirectory))
    }

    @Test("Fresh native scans include more than 24 Agents without launching subprocesses", .timeLimit(.minutes(2)))
    func completeNativeScan() async throws {
        let fixture = try await AgentProcessFixture.make()
        defer { fixture.remove() }
        for _ in 0..<26 { try await fixture.start(in: fixture.repository) }
        let expected = Set(fixture.children.map { $0.process.processIdentifier })
        let outside = try await fixture.start(in: fixture.neighbor)
        let alias = fixture.root.appendingPathComponent("repository-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.repository)
        let start = ContinuousClock.now
        let ownCPU = cpu(RUSAGE_SELF), childCPU = cpu(RUSAGE_CHILDREN)
        for _ in 0..<30 {
            let actual = RepositoryAgentProcessProbe.matchingAgents(for: alias)
            #expect(Set(actual.map(\.processID)) == expected)
            #expect(!actual.contains { $0.processID == outside.process.processIdentifier })
        }
        let duration = start.duration(to: .now).components
        let elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        let childDelta = cpu(RUSAGE_CHILDREN) - childCPU
        let ownDelta = cpu(RUSAGE_SELF) - ownCPU
        #expect(childDelta == 0)
        if let path = ProcessInfo.processInfo.environment["GITGATTO_ATTRIBUTION_MEASUREMENTS"] {
            let values: [String: Any] = ["scans": 30, "matchingFixtureAgents": 26,
                "wallSeconds": elapsed, "testProcessCPUSeconds": ownDelta,
                "childProcessCPUSeconds": childDelta]
            try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    @Test("Directory changes and exited Agents are reflected without a stale cache", .timeLimit(.minutes(1)))
    func changingDirectoryAndExit() async throws {
        let fixture = try await AgentProcessFixture.make()
        defer { fixture.remove() }
        let child = try await fixture.start(in: fixture.repository)
        let pid = child.process.processIdentifier
        #expect(RepositoryAgentProcessProbe.matchingAgents(for: fixture.repository).map(\.processID) == [pid])
        try child.input.fileHandleForWriting.write(contentsOf: Data((fixture.neighbor.path + "\n").utf8))
        try await fixture.wait {
            RepositoryAgentProcessProbe.matchingAgents(for: fixture.neighbor).contains { $0.processID == pid }
        }
        #expect(RepositoryAgentProcessProbe.matchingAgents(for: fixture.repository).isEmpty)
        try child.input.fileHandleForWriting.close()
        try await fixture.wait { !child.process.isRunning }
        #expect(RepositoryAgentProcessProbe.observation(for: pid) == nil)
        #expect(RepositoryAgentProcessProbe.matchingAgents(for: fixture.neighbor).isEmpty)
    }

    @Test("Cancelled sampling returns no partial candidates")
    func cancelledScan() async {
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return RepositoryAgentProcessProbe.matchingAgents(for: FileManager.default.temporaryDirectory)
        }
        task.cancel()
        #expect(await task.value.isEmpty)
    }

    @Test("Ledger preserves unknown, single-candidate and ambiguous confidence", .timeLimit(.minutes(2)))
    func ledgerAttribution() async throws {
        let fixture = try await AgentProcessFixture.make()
        defer { fixture.remove() }
        let git = GitCommandRunner()
        _ = try await git.run(at: fixture.repository, arguments: ["init", "-b", "main"])
        let file = fixture.repository.appendingPathComponent("file.txt")
        try Data("initial\n".utf8).write(to: file)
        _ = try await git.run(at: fixture.repository, arguments: ["add", "."])
        let commit = ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
            "-c", "commit.gpgsign=false", "commit", "-m", "Fixture"]
        _ = try await git.run(at: fixture.repository, arguments: commit)
        let ledger = RepositoryActivityLedger(rootURL: fixture.root.appendingPathComponent("ledger"))
        await ledger.seed([fixture.repository])
        let first = try await fixture.start(in: fixture.repository)
        let second = try await fixture.start(in: fixture.repository)
        try Data("changed\n".utf8).write(to: file)
        await ledger.recordChange(in: fixture.repository)
        let ambiguous = await ledger.events(for: fixture.repository).first
        #expect(ambiguous?.confidence == .ambiguous)
        #expect(ambiguous?.candidates.count == 2)
        try second.input.fileHandleForWriting.close()
        try await fixture.wait { !second.process.isRunning }
        _ = try await git.run(at: fixture.repository, arguments: ["add", "."])
        await ledger.recordChange(in: fixture.repository)
        #expect(await ledger.events(for: fixture.repository).first?.confidence == .medium)
        _ = try await git.run(at: fixture.repository, arguments: commit)
        await ledger.recordChange(in: fixture.repository)
        #expect(await ledger.events(for: fixture.repository).first?.confidence == .high)
        try first.input.fileHandleForWriting.close()
        try await fixture.wait { !first.process.isRunning }
        try Data("unknown\n".utf8).write(to: file)
        await ledger.recordChange(in: fixture.repository)
        let unknown = await ledger.events(for: fixture.repository).first
        #expect(unknown?.confidence == .unknown)
        #expect(unknown?.candidates.isEmpty == true)
    }

    private func cpu(_ who: Int32) -> Double {
        var value = rusage()
        getrusage(who, &value)
        return Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec)
            + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1_000_000
    }
}

private final class AgentProcessFixture {
    struct Child {
        let process: Process
        let input: Pipe
    }
    let root: URL
    let repository: URL
    let neighbor: URL
    var children: [Child] = []

    private init(root: URL) {
        self.root = root
        repository = root.appendingPathComponent("repository")
        neighbor = root.appendingPathComponent("repository-other")
    }

    static func make() async throws -> AgentProcessFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitGattoAgentProbe-\(UUID())")
        let fixture = AgentProcessFixture(root: root)
        do {
            try FileManager.default.createDirectory(at: fixture.repository, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: fixture.neighbor, withIntermediateDirectories: true)
            let source = root.appendingPathComponent("fixture.c")
            try Data("""
            #include <stdio.h>
            #include <unistd.h>
            #include <string.h>
            int main(void) {
                char path[4096];
                while (fgets(path, sizeof(path), stdin)) {
                    path[strcspn(path, "\\n")] = 0;
                    if (chdir(path) != 0) return 1;
                }
                return 0;
            }
            """.utf8).write(to: source)
            _ = try await ExternalProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["clang", source.path, "-o", root.appendingPathComponent("codex").path], timeout: .seconds(30))
            return fixture
        } catch {
            fixture.remove()
            throw error
        }
    }

    @discardableResult
    func start(in directory: URL) async throws -> Child {
        let process = Process(), input = Pipe()
        process.executableURL = root.appendingPathComponent("codex")
        process.currentDirectoryURL = directory
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let child = Child(process: process, input: input)
        children.append(child)
        try await wait { RepositoryAgentProcessProbe.observation(for: process.processIdentifier)?.executable.hasSuffix("/codex") == true }
        return child
    }

    func wait(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition())
    }

    func remove() {
        for child in children where child.process.isRunning { child.process.terminate() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while children.contains(where: { $0.process.isRunning }), ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        for child in children where child.process.isRunning { kill(child.process.processIdentifier, SIGKILL) }
        try? FileManager.default.removeItem(at: root)
    }
}
