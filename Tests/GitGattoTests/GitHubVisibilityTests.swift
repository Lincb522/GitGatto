import Foundation
import Testing
@testable import GitGatto

@Suite("Repository visibility", .serialized)
struct GitHubVisibilityTests {
    @Test("Both visibility directions require fresh permission checks and verified responses", arguments: [true, false])
    func change(isPrivate: Bool) async throws {
        let transport = VisibilityFixture(isPrivate: isPrivate)
        let service = GitHubRepositoryVisibilityService(transport: transport)
        let before = try await service.load("fixture-owner/demo")
        let result = try await service.change(before, toPrivate: !isPrivate)
        #expect(result.isPrivate != isPrivate)
        let commands = await transport.commands
        #expect(commands.count == 4)
        #expect(commands[2] == ["-X", "PATCH", "repos/fixture-owner/demo", "-F", "private=\(!isPrivate)"])
    }

    @Test("No PATCH for insufficient permission, forks, archived repos or concurrent changes", arguments: ["permission", "fork", "archived", "changed"])
    func rejected(mode: String) async throws {
        let transport = VisibilityFixture()
        let service = GitHubRepositoryVisibilityService(transport: transport)
        let before = try await service.load("fixture-owner/demo")
        await transport.setMode(mode)
        await #expect(throws: GitHubVisibilityError.self) { try await service.change(before, toPrivate: false) }
        #expect(await !transport.commands.contains { $0.contains("PATCH") })
    }

    @Test("Policy rejection and unverifiable writes never claim a successful switch", arguments: ["policy", "verification"])
    func failedWrite(mode: String) async throws {
        let transport = VisibilityFixture()
        let service = GitHubRepositoryVisibilityService(transport: transport)
        let before = try await service.load("fixture-owner/demo")
        await transport.setMode(mode)
        await #expect(throws: (any Error).self) { try await service.change(before, toPrivate: false) }
    }

    @Test("Remote names reject non-GitHub hosts and path traversal")
    func names() {
        #expect(GitHubRepositoryVisibilityService.fullName(remote: "git@github.com:owner/project.git") == "owner/project")
        #expect(GitHubRepositoryVisibilityService.fullName(remote: "https://github.com/owner/project.git") == "owner/project")
        for remote in ["https://example.invalid/a/b", "https://github.com/a/../b", "git@github.com:a/b/c", "https://github.com.evil.invalid/a/b"] {
            #expect(GitHubRepositoryVisibilityService.fullName(remote: remote) == nil)
        }
    }

    @Test("Visibility UI requires explicit confirmation and does not optimistically change state", arguments: ["fixture-owner/demo", "Fixture-Owner/DEMO"])
    @MainActor func confirmation(fullName: String) async throws {
        let transport = VisibilityFixture()
        let model = GitHubVisibilityViewModel(service: .init(transport: transport))
        await model.load(fullName)
        model.requestChange()
        #expect(model.showsConfirmation && !model.isBusy && model.state?.isPrivate == true)
        #expect(await transport.commands.count == 1)
        model.confirmChange()
        #expect(model.isBusy && model.state?.isPrivate == true)
        let result = await model.performChange()
        #expect(result?.isPrivate == false && model.state?.isPrivate == false && model.error == nil)
    }
}

actor VisibilityFixture: GitHubVisibilityTransport {
    var isPrivate: Bool
    var mode = "normal"
    private(set) var commands: [[String]] = []
    init(isPrivate: Bool = true) { self.isPrivate = isPrivate }
    func setMode(_ mode: String) { self.mode = mode }
    func visibilityAPI(_ arguments: [String]) async throws -> Data {
        commands.append(arguments)
        if arguments.contains("PATCH") {
            if mode == "policy" { throw URLError(.userAuthenticationRequired) }
            if mode != "verification" { isPrivate = arguments.contains("private=true") }
        }
        return try JSONSerialization.data(withJSONObject: [
            "id": mode == "changed" ? 2 : 1, "full_name": "fixture-owner/demo", "private": isPrivate,
            "visibility": isPrivate ? "private" : "public", "fork": mode == "fork", "archived": mode == "archived",
            "permissions": ["admin": mode != "permission"]
        ])
    }
}
