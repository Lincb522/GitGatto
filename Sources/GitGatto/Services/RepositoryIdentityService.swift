import Foundation
import Darwin

struct IdentityValue: Identifiable, Sendable {
    var key: String
    var value: String
    var origin: String
    var id: String { key }
}

actor RepositoryIdentityService {
    let store: ProjectToolsStore
    let environment: [String: String]
    private var busy = false
    init(store: ProjectToolsStore, environment: [String: String] = [:]) { self.store = store; self.environment = environment }

    func effective(repository: URL) async throws -> [IdentityValue] {
        var values: [IdentityValue] = []
        for key in ["user.name", "user.email", "commit.gpgsign", "gpg.format", "user.signingkey"] {
            let result = try await ProjectToolsPolicy.git(repository, ["config", "--show-origin", "--get", key], codes: [0, 1], environment: environment)
            let parts = result.outputText.trimmingCharacters(in: .newlines).split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            values.append(IdentityValue(key: key, value: parts.count == 2 ? String(parts[1]) : "", origin: parts.first.map(String.init) ?? ""))
        }
        return values
    }

    func save(_ profile: RepositoryIdentityProfile) async throws {
        guard !busy else { throw ProjectToolsError(key: "busy") }
        busy = true; defer { busy = false }
        guard !profile.title.isEmpty, !profile.name.isEmpty, profile.email.contains("@"),
              [profile.name, profile.email, profile.signingKey].allSatisfy({ !$0.contains("\n") && !$0.contains("\0") }),
              ["ssh", "openpgp", "x509"].contains(profile.signingFormat), !profile.signCommits || !profile.signingKey.isEmpty else { throw ProjectToolsError(key: "identity") }
        let file = profileURL(profile.id)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let old = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
        let content = """
        [user]
            name = \(Self.quote(profile.name))
            email = \(Self.quote(profile.email))
            signingkey = \(Self.quote(profile.signingKey))
        [commit]
            gpgsign = \(profile.signCommits ? "true" : "false")
        [gpg]
            format = \(profile.signingFormat)
        [gitgatto]
            expectedName = \(Self.quote(profile.name))
            expectedEmail = \(Self.quote(profile.email))
            expectedSign = \(profile.signCommits ? "true" : "false")
            expectedFormat = \(profile.signingFormat)
            expectedKey = \(Self.quote(profile.signingKey))
        """
        try Data(content.utf8).write(to: file, options: .atomic)
        do {
            try await store.update { state in
                state.profiles.removeAll { $0.id == profile.id }; state.profiles.append(profile)
            }
        } catch {
            if let old { try old.write(to: file, options: .atomic) } else { try FileManager.default.removeItem(at: file) }
            throw error
        }
    }

    func bind(_ profile: RepositoryIdentityProfile, to target: URL, directory: Bool, repository: URL) async throws {
        guard !busy else { throw ProjectToolsError(key: "busy") }
        busy = true; defer { busy = false }
        let state = try await store.load()
        // Git matches physical gitdir paths; Foundation may retain macOS aliases such as /var.
        guard let resolved = realpath(target.path, nil) else { throw ProjectToolsError(key: "binding") }
        defer { free(resolved) }
        let path = String(cString: resolved)
        guard state.profiles.contains(where: { $0.id == profile.id }), !state.bindings.contains(where: { $0.path == path && $0.directory == directory }),
              !path.contains("\n"), !path.contains("\0"), !path.contains(where: { "*?[]\\".contains($0) }) else { throw ProjectToolsError(key: "binding") }
        let include = profileURL(profile.id).path
        let key = directory ? "includeIf.gitdir:" + path + "/.path" : "include.path"
        let scope = directory ? "--global" : "--local"
        let binding = RepositoryIdentityBinding(profileID: profile.id, path: path, directory: directory, configKey: key, includePath: include)
        _ = try await ProjectToolsPolicy.git(repository, ["config", scope, "--add", key, include], environment: environment)
        do { try await store.update { $0.bindings.append(binding) } }
        catch {
            _ = try await ProjectToolsPolicy.git(repository, ["config", scope, "--fixed-value", "--unset-all", key, include], codes: [0, 5], environment: environment)
            throw error
        }
    }

    func unbind(_ binding: RepositoryIdentityBinding) async throws {
        guard !busy else { throw ProjectToolsError(key: "busy") }
        busy = true; defer { busy = false }
        let root = URL(fileURLWithPath: binding.path)
        _ = try await ProjectToolsPolicy.git(root, ["config", binding.directory ? "--global" : "--local", "--fixed-value", "--unset-all", binding.configKey, binding.includePath], codes: [0, 5], environment: environment)
        try await store.update { $0.bindings.removeAll { $0.id == binding.id } }
    }

    func delete(_ profile: RepositoryIdentityProfile) async throws {
        guard !busy else { throw ProjectToolsError(key: "busy") }
        busy = true; defer { busy = false }
        try await store.update { state in
            guard !state.bindings.contains(where: { $0.profileID == profile.id }) else { throw ProjectToolsError(key: "bound") }
            state.profiles.removeAll { $0.id == profile.id }
        }
        let file = profileURL(profile.id)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    static func verifyBinding(repository: URL, environment: [String: String] = [:]) async throws {
        let expectedKeys = ["expectedName", "expectedEmail", "expectedSign", "expectedFormat", "expectedKey"]
        let actualKeys = ["user.name", "user.email", "commit.gpgsign", "gpg.format", "user.signingkey"]
        let marker = try await ProjectToolsPolicy.git(repository, ["config", "--get", "gitgatto.expectedEmail"], codes: [0, 1], environment: environment)
        guard marker.exitCode == 0 else { return }
        var expectedAuthor = [String]()
        for (expected, actual) in zip(expectedKeys, actualKeys) {
            let options = actual == "commit.gpgsign" ? ["--bool"] : []
            let a = try await ProjectToolsPolicy.git(repository, ["config"] + options + ["--get", "gitgatto." + expected], codes: [0, 1], environment: environment)
            let b = try await ProjectToolsPolicy.git(repository, ["config"] + options + ["--get", actual], codes: [0, 1], environment: environment)
            if actual == "user.name" || actual == "user.email" { expectedAuthor.append(a.outputText.trimmingCharacters(in: .newlines)) }
            guard a.outputText.trimmingCharacters(in: .newlines) == b.outputText.trimmingCharacters(in: .newlines) else { throw ProjectToolsError(key: "identityMismatch") }
        }
        let author = try await ProjectToolsPolicy.git(repository, ["var", "GIT_AUTHOR_IDENT"], environment: environment)
        guard expectedAuthor.count == 2, author.outputText.hasPrefix(expectedAuthor[0] + " <" + expectedAuthor[1] + "> ") else { throw ProjectToolsError(key: "identityMismatch") }
    }

    private func profileURL(_ id: UUID) -> URL { store.root.appendingPathComponent("Identities/" + id.uuidString + ".gitconfig") }
    private static func quote(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
}
