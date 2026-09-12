import Foundation

protocol RepositoryBootstrapGitRunning: Sendable {
    func run(at repositoryURL: URL, arguments: [String], environment: [String: String], acceptedExitCodes: Set<Int32>) async throws -> GitCommandResult
}

extension GitCommandRunner: RepositoryBootstrapGitRunning {}

protocol GitHubRepositoryCreating: Sendable {
    func currentAccount() async throws -> GitHubAccount
    func repositoryForCreation(owner: String, name: String) async throws -> GitHubRepository?
    func createRepository(name: String, isPrivate: Bool) async throws -> GitHubRepository
    func configureRepositoryAuthentication(in folder: URL) async throws
}

extension GitHubService: GitHubRepositoryCreating {
    func repositoryForCreation(owner: String, name: String) async throws -> GitHubRepository? {
        do { return try GitHubAPIParser.repository(from: await api(["-X", "GET", "repos/\(owner)/\(name)"])) }
        catch GitHubServiceError.resourceNotFound { return nil }
    }

    static func repositoryCreationArguments(name: String, isPrivate: Bool) -> [String] {
        ["-X", "POST", "user/repos", "-f", "name=\(name)", "-F", "private=\(isPrivate)", "-F", "auto_init=false"]
    }

    func createRepository(name: String, isPrivate: Bool) async throws -> GitHubRepository {
        try GitHubAPIParser.repository(from: await api(Self.repositoryCreationArguments(name: name, isPrivate: isPrivate)))
    }
}

actor RepositoryBootstrapService {
    private let git: any RepositoryBootstrapGitRunning
    private let github: any GitHubRepositoryCreating
    private let environment: [String: String]
    private let operationTimeout: Duration
    private var busy = false
    private var createdRemotes: Set<String> = []

    init(git: any RepositoryBootstrapGitRunning = GitCommandRunner(),
         github: any GitHubRepositoryCreating = GitHubService(), environment: [String: String] = [:],
         operationTimeout: Duration = .seconds(120)) {
        self.operationTimeout = operationTimeout
        self.git = git
        self.github = github
        self.environment = environment
    }

    func currentAccount() async throws -> GitHubAccount {
        try await Self.bounded(.seconds(30)) { [github] in try await github.currentAccount() }
    }

    func existingRemote(_ origin: String) async throws -> GitHubRepository? {
        guard let fullName = GitHubRepositoryVisibilityService.fullName(remote: origin) else { return nil }
        let parts = fullName.split(separator: "/").map(String.init)
        return try await Self.bounded(.seconds(30)) { [github] in
            try await github.repositoryForCreation(owner: parts[0], name: parts[1])
        }
    }

    func isNameAvailable(owner: String, name: String) async throws -> Bool {
        guard GitHubRepositoryVisibilityService.validFullName("\(owner)/\(name)") else {
            throw RepositoryBootstrapError.name
        }
        return try await Self.bounded(.seconds(30)) { [github] in
            try await github.repositoryForCreation(owner: owner, name: name) == nil
        }
    }

    private static func matchesOrigin(_ origin: String, owner: String, name: String) -> Bool {
        GitHubRepositoryVisibilityService.fullName(remote: origin)?.caseInsensitiveCompare("\(owner)/\(name)") == .orderedSame
    }

    func inspect(_ folder: URL) async throws -> RepositoryBootstrapInspection {
        guard folder.isFileURL else { throw RepositoryBootstrapError.folder }
        // JSON-decoded file URLs can lose Foundation's directory hint. Restore it before root comparison.
        let folder = URL(fileURLWithPath: folder.path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RepositoryBootstrapError.folder
        }
        let bare = try await run(folder, ["rev-parse", "--is-bare-repository"], codes: [0, 128])
        guard bare.text.trimmingCharacters(in: .whitespacesAndNewlines) != "true" else { throw RepositoryBootstrapError.folder }
        let top = try await run(folder, ["rev-parse", "--show-toplevel"], codes: [0, 128])
        let isRepository = top.exitCode == 0
        if isRepository {
            let root = URL(fileURLWithPath: top.text.trimmingCharacters(in: .whitespacesAndNewlines)).standardizedFileURL.resolvingSymlinksInPath()
            guard root == folder, FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) else {
                throw RepositoryBootstrapError.nested
            }
        } else if FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) {
            throw RepositoryBootstrapError.folder
        }
        let head = isRepository ? try await run(folder, ["rev-parse", "--verify", "HEAD"], codes: [0, 128]) : nil
        let revision = head?.exitCode == 0 ? head?.text.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        var isEmptyInitial = false
        if let revision {
            let parents = try await run(folder, ["rev-list", "--parents", "-n", "1", revision])
            let tree = try await run(folder, ["ls-tree", revision])
            isEmptyInitial = parents.text.split(whereSeparator: \.isWhitespace).count == 1 && tree.text.isEmpty
        }
        let branch = isRepository ? try await run(folder, ["symbolic-ref", "--quiet", "--short", "HEAD"], codes: [0, 1, 128]).text.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let origin = isRepository ? try await config("remote.origin.url", in: folder) : ""
        return RepositoryBootstrapInspection(folder: folder, isRepository: isRepository, head: revision,
            isEmptyInitialCommit: isEmptyInitial, branch: branch.isEmpty ? nil : branch, origin: origin.isEmpty ? nil : origin,
            authorName: try await config("user.name", in: folder), authorEmail: try await config("user.email", in: folder))
    }

    func create(_ request: RepositoryBootstrapRequest,
                progress: @escaping @Sendable (RepositoryBootstrapEvent) async -> Void) async throws -> RepositoryBootstrapResult {
        try await Self.bounded(operationTimeout) { try await self.perform(request, progress: progress) }
    }

    static func bounded<Value: Sendable>(_ duration: Duration, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask { try await Task.sleep(for: duration); throw URLError(.timedOut) }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw CancellationError() }
            return value
        }
    }

    private func perform(_ request: RepositoryBootstrapRequest,
                         progress: @escaping @Sendable (RepositoryBootstrapEvent) async -> Void) async throws -> RepositoryBootstrapResult {
        guard !busy else { throw RepositoryBootstrapError.busy }
        busy = true
        defer { busy = false }
        await progress(.init(step: .check, state: .running))
        let initial = try await inspect(request.folder)
        let folder = initial.folder
        if !initial.isRepository {
            let validBranch = try await run(folder, ["check-ref-format", "--branch", request.branch], codes: [0, 128])
            guard validBranch.exitCode == 0, !request.branch.hasPrefix("-"), !request.branch.hasPrefix("@") else {
                throw RepositoryBootstrapError.branch
            }
        }
        if !initial.hasHEAD {
            let name = request.authorName.isEmpty ? initial.authorName : request.authorName
            let email = request.authorEmail.isEmpty ? initial.authorEmail : request.authorEmail
            guard !name.isEmpty, email.contains("@"), ![name, email].contains(where: { $0.contains("\n") || $0.contains("\0") }) else {
                throw RepositoryBootstrapError.identity
            }
        }
        var account: GitHubAccount?
        var remote: GitHubRepository?
        if request.createRemote {
            guard Self.validName(request.name) else { throw RepositoryBootstrapError.name }
            let current = try await github.currentAccount()
            guard GitHubRepositoryVisibilityService.validFullName("\(request.owner)/\(request.name)") else { throw RepositoryBootstrapError.remoteMismatch }
            account = current
            if let origin = initial.origin, !Self.matchesOrigin(origin, owner: request.owner, name: request.name) { throw RepositoryBootstrapError.origin }
            if request.pushInitialCommit, !initial.canPushInitialCommit,
               request.approvedExistingHead == nil || request.approvedExistingHead != initial.head {
                throw RepositoryBootstrapError.history
            }
            guard initial.branch != nil || !initial.isRepository else { throw RepositoryBootstrapError.branch }
            remote = try await github.repositoryForCreation(owner: request.owner, name: request.name)
            if remote == nil, current.login.caseInsensitiveCompare(request.owner) != .orderedSame {
                throw RepositoryBootstrapError.remoteMismatch
            }
            if let remote {
                guard request.connectExisting || createdRemotes.contains(remote.fullName.lowercased()) else {
                    throw RepositoryBootstrapError.remoteExists
                }
                try Self.verify(remote, account: current, request: request)
            }
        }
        await progress(.init(step: .check, state: .complete))
        try Task.checkCancellation()
        await progress(.init(step: .local, state: .running))
        if !initial.isRepository {
            guard !FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) else {
                throw RepositoryBootstrapError.changed
            }
            _ = try await run(folder, ["init", "--initial-branch=\(request.branch)", "--template="])
        }
        if !initial.hasHEAD {
            let current = try await inspect(folder)
            guard !current.hasHEAD else { throw RepositoryBootstrapError.changed }
            if !request.authorName.isEmpty { _ = try await run(folder, ["config", "--local", "user.name", request.authorName]) }
            if !request.authorEmail.isEmpty { _ = try await run(folder, ["config", "--local", "user.email", request.authorEmail]) }
            // A separate index keeps existing staged files out of the initialization commit.
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("GitGatto-InitialIndex-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: temporary) }
            let indexEnvironment = environment.merging(["GIT_INDEX_FILE": temporary.appendingPathComponent("index").path]) { _, new in new }
            _ = try await git.run(at: folder, arguments: ["read-tree", "--empty"], environment: indexEnvironment, acceptedExitCodes: [0])
            _ = try await git.run(at: folder, arguments: ["commit", "--allow-empty", "-m", "Initial commit"], environment: indexEnvironment, acceptedExitCodes: [0])
        }
        let local = try await inspect(folder)
        guard local.hasHEAD, initial.hasHEAD || local.isEmptyInitialCommit else { throw RepositoryBootstrapError.verification }
        await progress(.init(step: .local, state: .complete))
        guard request.createRemote, let account else {
            for step in [RepositoryBootstrapStep.remote, .link, .push] { await progress(.init(step: step, state: .skipped)) }
            await progress(.init(step: .verify, state: .complete))
            return RepositoryBootstrapResult(folder: folder, branch: local.branch, remote: nil, pushed: false)
        }
        try Task.checkCancellation()
        await progress(.init(step: .remote, state: .running))
        if remote == nil {
            guard account.login.caseInsensitiveCompare(request.owner) == .orderedSame else { throw RepositoryBootstrapError.remoteMismatch }
            let created = try await github.createRepository(name: request.name, isPrivate: request.isPrivate)
            try Self.verify(created, account: account, request: request)
            createdRemotes.insert(created.fullName.lowercased())
            remote = created
        }
        guard let remote else { throw RepositoryBootstrapError.verification }
        await progress(.init(step: .remote, state: .complete))
        try Task.checkCancellation()
        await progress(.init(step: .link, state: .running))
        let expected = Self.remoteURL(owner: request.owner, name: request.name)
        let origin = try await config("remote.origin.url", in: folder)
        if origin.isEmpty { _ = try await run(folder, ["remote", "add", "origin", expected]) }
        else if !Self.matchesOrigin(origin, owner: request.owner, name: request.name) { throw RepositoryBootstrapError.origin }
        try await github.configureRepositoryAuthentication(in: folder)
        await progress(.init(step: .link, state: .complete))
        var pushed = false
        if request.pushInitialCommit {
            try Task.checkCancellation()
            let current = try await inspect(folder)
            guard let head = current.head, let branch = current.branch, branch == local.branch,
                  current.isEmptyInitialCommit || (request.approvedExistingHead == head && initial.head == head) else {
                throw RepositoryBootstrapError.history
            }
            await progress(.init(step: .push, state: .running))
            _ = try await run(folder, ["push", expected, "\(head):refs/heads/\(branch)"])
            await progress(.init(step: .push, state: .complete))
            await progress(.init(step: .verify, state: .running))
            let advertised = try await run(folder, ["ls-remote", "--exit-code", "--heads", expected, "refs/heads/\(branch)"])
            guard advertised.text.split(whereSeparator: \.isWhitespace).first.map(String.init) == head else {
                throw RepositoryBootstrapError.verification
            }
            let trackingRef = "refs/remotes/origin/\(branch)"
            let previous = try await run(folder, ["rev-parse", "--verify", trackingRef], codes: [0, 128])
            let previousHash = previous.exitCode == 0 ? previous.text.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            // Compare-and-swap avoids overwriting a concurrently refreshed tracking ref.
            _ = try await run(folder, ["update-ref", trackingRef, head, previousHash])
            pushed = true
        } else {
            await progress(.init(step: .push, state: .skipped))
            await progress(.init(step: .verify, state: .running))
        }
        // Track even an empty remote without uploading history. A later normal push can publish it.
        guard let branch = local.branch,
              try await run(folder, ["symbolic-ref", "--quiet", "--short", "HEAD"]).text.trimmingCharacters(in: .whitespacesAndNewlines) == branch else {
            throw RepositoryBootstrapError.changed
        }
        _ = try await run(folder, ["config", "--local", "branch.\(branch).remote", "origin"])
        _ = try await run(folder, ["config", "--local", "branch.\(branch).merge", "refs/heads/\(branch)"])
        guard try await config("branch.\(branch).remote", in: folder) == "origin",
              try await config("branch.\(branch).merge", in: folder) == "refs/heads/\(branch)" else { throw RepositoryBootstrapError.verification }
        guard Self.matchesOrigin(try await config("remote.origin.url", in: folder), owner: request.owner, name: request.name) else { throw RepositoryBootstrapError.origin }
        await progress(.init(step: .verify, state: .complete))
        return RepositoryBootstrapResult(folder: folder, branch: local.branch, remote: remote, pushed: pushed)
    }

    static func validName(_ name: String) -> Bool {
        (1...100).contains(name.utf8.count) && name != "." && name != ".." && !name.hasSuffix(".git")
            && name.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
    }

    private static func remoteURL(owner: String, name: String) -> String { "https://github.com/\(owner)/\(name).git" }

    private static func verify(_ remote: GitHubRepository, account: GitHubAccount, request: RepositoryBootstrapRequest) throws {
        guard remote.owner.caseInsensitiveCompare(request.owner) == .orderedSame,
              remote.name.caseInsensitiveCompare(request.name) == .orderedSame,
              remote.fullName.caseInsensitiveCompare("\(request.owner)/\(request.name)") == .orderedSame,
              remote.isPrivate == request.isPrivate,
              remote.webURL.scheme == "https", remote.webURL.host == "github.com",
              remote.webURL.path.caseInsensitiveCompare("/\(remote.fullName)") == .orderedSame else { throw RepositoryBootstrapError.remoteMismatch }
    }

    private func config(_ key: String, in folder: URL) async throws -> String {
        try await run(folder, ["config", "--get", key], codes: [0, 1]).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run(_ folder: URL, _ arguments: [String], codes: Set<Int32> = [0]) async throws -> GitCommandResult {
        try await git.run(at: folder, arguments: arguments, environment: environment, acceptedExitCodes: codes)
    }
}
