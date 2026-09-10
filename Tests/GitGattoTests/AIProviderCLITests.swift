import Foundation
import Testing
@testable import GitGatto

@Suite("Additional Agent CLI execution")
struct AIProviderCLITests {
    @Test("DSH uses headless argv, isolated working directory, and OS read-only enforcement", .enabled(if: ProcessInfo.processInfo.environment["GITGATTO_CLI_FIXTURE"] == "1"))
    func dsh() async throws {
        let home = try #require(ProcessInfo.processInfo.environment["DSH_HOME"])
        #expect(home.contains("GitGatto-CLI-Fixture"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GitGatto-CLI-Fixture-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("dsh-fixture")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then printf 'fixture 1.0'; exit 0; fi
        [ "$1" = "--profile" ] && [ "$2" = "headless" ] || exit 91
        case "$3" in
          *fixture-edit*) printf changed > sample.txt || exit 92 ;;
          *) cat sample.txt ;;
        esac
        printf '\\nfixture completed'
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try "original".write(to: root.appendingPathComponent("sample.txt"), atomically: true, encoding: .utf8)
        var config = AIProviderConfiguration.preset(.dsh)
        config.executable = executable.path
        let configuration = config
        let service = CodexService(configurationSource: { _ in configuration })
        #expect(await service.probe().state == .available)
        let analysis = try await service.run(prompt: "inspect", context: [], in: root, mode: .analyze)
        #expect(analysis.response.contains("original"))
        await #expect(throws: CodexServiceError.self) {
            try await service.run(prompt: "fixture-edit", context: [], in: root, mode: .analyze)
        }
        #expect(try String(contentsOf: root.appendingPathComponent("sample.txt"), encoding: .utf8) == "original")
        let edit = try await service.run(prompt: "fixture-edit", context: [], in: root, mode: .edit)
        #expect(edit.response == "fixture completed")
        #expect(try String(contentsOf: root.appendingPathComponent("sample.txt"), encoding: .utf8) == "changed")
    }
}

@Suite("Agent API key storage")
struct AIAPICredentialStoreTests {
    @Test("Saves, updates, reads, and removes only a synthetic test credential", .enabled(if: ProcessInfo.processInfo.environment["GITGATTO_KEYCHAIN_FIXTURE"] == "1"))
    func keychain() throws {
        let configuration = AIAPIConfiguration(baseURL: "https://fixture.invalid/v1", model: "fixture", credentialID: "test-\(UUID())")
        defer { try? AIAPICredentialStore.delete(configuration) }
        #expect(!AIAPICredentialStore.contains(configuration))
        try AIAPICredentialStore.save("synthetic-key-one", for: configuration)
        #expect(AIAPICredentialStore.contains(configuration))
        #expect(try AIAPICredentialStore.read(configuration) == "synthetic-key-one")
        try AIAPICredentialStore.save("synthetic-key-two", for: configuration)
        #expect(try AIAPICredentialStore.read(configuration) == "synthetic-key-two")
        var changed = configuration
        changed.baseURL = "https://another-fixture.invalid/v1"
        #expect(try AIAPICredentialStore.read(changed) == nil)
        try AIAPICredentialStore.delete(configuration)
        #expect(!AIAPICredentialStore.contains(configuration))
    }
}
