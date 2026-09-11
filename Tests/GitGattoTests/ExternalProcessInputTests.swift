import Foundation
import Testing
@testable import GitGatto

@Suite("Subprocess input delivery", .serialized)
struct ExternalProcessInputTests {
    @Test("Early stdin closure returns a Swift error rather than SIGPIPE or an Objective-C exception", .timeLimit(.minutes(1)))
    func earlyExit() async throws {
        for _ in 0..<5 {
            do {
                _ = try await ExternalProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/true"),
                    arguments: [], input: Data(repeating: 65, count: 1_048_576), timeout: .seconds(5))
                Issue.record("A process that ignores this input must not be reported as accepting it")
            } catch is ExternalProcessInputError {}
        }
    }

    @Test("Child failure output is retained when stdin closes early", .timeLimit(.minutes(1)))
    func failedChild() async throws {
        do {
            _ = try await ExternalProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf 'input rejected' >&2; exit 7"],
                input: Data(repeating: 65, count: 1_048_576), timeout: .seconds(5))
            Issue.record("Expected the child failure")
        } catch let error as ExternalProcessError {
            #expect(error.exitCode == 7)
            #expect(error.output == "input rejected")
        }
    }

    @Test("Large stdin and both output streams are drained concurrently", .timeLimit(.minutes(1)))
    func largeInput() async throws {
        let input = Data(repeating: 65, count: 2_097_152)
        let result = try await ExternalProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "/usr/bin/head -c 1048576 /dev/zero >&2; exec /bin/cat"],
            input: input, timeout: .seconds(10))
        #expect(result.standardOutput == input)
        #expect(result.standardError.count == 1_048_576)
    }

    @Test("Timeout interrupts a blocked stdin writer", .timeLimit(.minutes(1)))
    func blockedWriterTimeout() async throws {
        let start = ContinuousClock.now
        do {
            _ = try await ExternalProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"], input: Data(repeating: 65, count: 1_048_576), timeout: .seconds(1))
            Issue.record("Expected a timeout")
        } catch is ExternalProcessTimeoutError {} catch is CancellationError {}
        #expect(start.duration(to: .now) < .seconds(10))
    }

    @Test("Cancellation interrupts a blocked stdin writer", .timeLimit(.minutes(1)))
    func blockedWriterCancellation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("ready")
        let task = Task {
            try await ExternalProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf ready > \"$1\"; exec /bin/sleep 30", "fixture", marker.path],
                input: Data(repeating: 65, count: 1_048_576), timeout: .seconds(20))
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: marker.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(FileManager.default.fileExists(atPath: marker.path))
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError {}
    }
}
