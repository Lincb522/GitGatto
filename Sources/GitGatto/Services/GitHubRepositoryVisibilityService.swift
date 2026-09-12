import Foundation

protocol GitHubVisibilityTransport: Sendable {
    func visibilityAPI(_ arguments: [String]) async throws -> Data
}

extension GitHubService: GitHubVisibilityTransport {
    func visibilityAPI(_ arguments: [String]) async throws -> Data { try await api(arguments) }
}

struct GitHubVisibilityState: Sendable, Equatable, Decodable {
    struct Permissions: Sendable, Equatable, Decodable { let admin: Bool }
    let id: Int64
    let fullName: String
    let isPrivate: Bool
    let visibility: String
    let fork: Bool
    let archived: Bool
    let permissions: Permissions?
    var canChange: Bool { permissions?.admin == true && !fork && !archived && ["public", "private"].contains(visibility) }
    enum CodingKeys: String, CodingKey {
        case id, visibility, fork, archived, permissions
        case fullName = "full_name", isPrivate = "private"
    }
}

enum GitHubVisibilityError: String, LocalizedError {
    case permission, changed, verification
    var errorDescription: String? { L10n.text("repository.visibility.error.\(rawValue)") }
}

actor GitHubRepositoryVisibilityService {
    let transport: any GitHubVisibilityTransport
    private var busy = false
    init(transport: any GitHubVisibilityTransport = GitHubService()) { self.transport = transport }

    static func validFullName(_ name: String) -> Bool {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { RepositoryBootstrapService.validName(String($0)) }
    }

    static func fullName(remote: String) -> String? {
        guard let identity = CodeProvenanceService.parseRemote(remote), identity.host.lowercased() == "github.com",
              validFullName(identity.fullName) else { return nil }
        return identity.fullName
    }

    func load(_ fullName: String) async throws -> GitHubVisibilityState {
        guard Self.validFullName(fullName) else { throw GitHubVisibilityError.verification }
        let data = try await RepositoryBootstrapService.bounded(.seconds(30)) { [transport] in
            try await transport.visibilityAPI(["-X", "GET", "repos/\(fullName)"])
        }
        let state = try JSONDecoder().decode(GitHubVisibilityState.self, from: data)
        guard state.fullName.caseInsensitiveCompare(fullName) == .orderedSame,
              state.isPrivate == (state.visibility != "public") else { throw GitHubVisibilityError.verification }
        return state
    }

    func change(_ expected: GitHubVisibilityState, toPrivate: Bool) async throws -> GitHubVisibilityState {
        guard !busy else { throw RepositoryBootstrapError.busy }
        busy = true
        defer { busy = false }
        let current = try await load(expected.fullName)
        guard current.id == expected.id, current.isPrivate == expected.isPrivate else { throw GitHubVisibilityError.changed }
        guard current.canChange else { throw GitHubVisibilityError.permission }
        if current.isPrivate == toPrivate { return current }
        try Task.checkCancellation()
        _ = try await RepositoryBootstrapService.bounded(.seconds(30)) { [transport] in
            try await transport.visibilityAPI(["-X", "PATCH", "repos/\(expected.fullName)", "-F", "private=\(toPrivate)"])
        }
        let result = try await load(expected.fullName)
        guard result.id == expected.id, result.isPrivate == toPrivate else { throw GitHubVisibilityError.verification }
        return result
    }
}
