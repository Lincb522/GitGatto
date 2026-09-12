import Foundation
import Testing
@testable import GitGatto

@Suite("Repository creation", .serialized)
struct RepositoryBootstrapTests {
    @Test("Local initialization never stages existing files and does not need GitHub")
    func localOnly() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        let source = Data("existing project content\n".utf8)
        try source.write(to: f.folder.appendingPathComponent("source.swift"))
        let github = BootstrapGitHub(); await github.failAccount()
        let service = RepositoryBootstrapService(git: f.runner, github: github, environment: f.environment)
        var request = f.request; request.createRemote = false
        let events = BootstrapEvents()
        let result = try await service.create(request) { await events.append($0) }
        #expect(!result.pushed && result.remote == nil)
        #expect(try await f.git(["ls-tree", "HEAD"]).isEmpty)
        #expect(try await f.git(["rev-list", "--count", "HEAD"]) == "1")
        #expect(try await f.git(["symbolic-ref", "--short", "HEAD"]) == "main")
        #expect(try await f.git(["status", "--porcelain"]) == "?? source.swift")
        #expect(try Data(contentsOf: f.folder.appendingPathComponent("source.swift")) == source)
        #expect(try await f.git(["config", "--local", "user.name"]) == "Fixture Maintainer")
        #expect(await github.accountCalls == 0)
        #expect(await github.createCalls == 0)
        #expect(await events.last?.step == .verify)
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("global.gitconfig").path))
    }

    @Test("Existing unborn repository keeps its index and branch")
    func stagedFiles() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        _ = try await f.git(["init", "--initial-branch=trunk"])
        try Data("staged content".utf8).write(to: f.folder.appendingPathComponent("file.txt"))
        _ = try await f.git(["add", "file.txt"])
        let index = f.folder.appendingPathComponent(".git/index")
        let before = try Data(contentsOf: index)
        var request = f.request; request.createRemote = false
        let result = try await f.service().create(request) { _ in }
        #expect(result.branch == "trunk")
        #expect(try Data(contentsOf: index) == before)
        #expect(try await f.git(["ls-tree", "HEAD"]).isEmpty)
        #expect(try await f.git(["diff", "--cached", "--name-only"]) == "file.txt")
    }

    @Test("Create, connect, push and verify private or public repositories", arguments: [true, false])
    func remoteEndToEnd(isPrivate: Bool) async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        try await f.initBare()
        let github = BootstrapGitHub()
        let events = BootstrapEvents()
        var request = f.request; request.isPrivate = isPrivate
        let result = try await f.service(github).create(request) { await events.append($0) }
        let sha = try await f.git(["rev-parse", "HEAD"])
        #expect(result.pushed && result.remote?.isPrivate == isPrivate)
        #expect(try await f.git(["config", "--get", "remote.origin.url"]) == f.remoteURL)
        #expect(try await f.git(["config", "--get", "branch.main.remote"]) == "origin")
        #expect(try await f.git(["config", "--get", "branch.main.merge"]) == "refs/heads/main")
        #expect(try await f.git(["rev-parse", "refs/heads/main"], at: f.bare) == sha)
        #expect(try await f.git(["ls-tree", "refs/heads/main"], at: f.bare).isEmpty)
        #expect(await github.createCalls == 1)
        #expect(await github.authenticationCalls == 1)
        let states = await events.values
        #expect(states.filter { $0.state == .complete }.map(\.step) == RepositoryBootstrapStep.allCases.filter { $0 != .agent })
        #expect(GitHubService.repositoryCreationArguments(name: "demo", isPrivate: true) ==
                ["-X", "POST", "user/repos", "-f", "name=demo", "-F", "private=true", "-F", "auto_init=false"])
        #expect(GitHubService.repositoryCreationArguments(name: "demo", isPrivate: false).contains("private=false"))
    }

    @Test("GitHub authentication is repository-local, quoted and idempotent")
    func authenticationConfiguration() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        _ = try await f.git(["init", "--initial-branch=main"])
        _ = try await f.git(["config", "--local", "credential.https://elsewhere.invalid.helper", "existing-helper"])
        let executable = f.root.appendingPathComponent("folder with space and ' quote/gh")
        let commands = GitHubService.repositoryAuthenticationArguments(executable: executable)
        for _ in 0..<2 { for command in commands { _ = try await f.git(command) } }
        let value = try await f.git(["config", "--local", "--get-all", "credential.https://github.com.helper"])
        #expect(value.hasSuffix(" auth git-credential"))
        #expect(value.split(separator: "\n").count == 1)
        #expect(value.contains("'\"'\"'"))
        #expect(try await f.git(["config", "--local", "--get", "credential.https://elsewhere.invalid.helper"]) == "existing-helper")
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent("global.gitconfig").path))
    }

    @Test("Push failure retains local state; retry does not create a duplicate remote")
    func retry() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        try await f.initBare()
        let github = BootstrapGitHub()
        await f.runner.failNextPush()
        let service = f.service(github)
        await #expect(throws: GitCommandError.self) { try await service.create(f.request) { _ in } }
        let sha = try await f.git(["rev-parse", "HEAD"])
        #expect(await github.createCalls == 1)
        let result = try await service.create(f.request) { _ in }
        #expect(result.pushed)
        #expect(await github.createCalls == 1)
        #expect(try await f.git(["rev-parse", "HEAD"]) == sha)
    }

    @Test("Folder, identity, branch, account and name validation happen before mutations")
    func preflight() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        let github = BootstrapGitHub()
        let service = f.service(github)
        var request = f.request
        request.authorEmail = ""
        await #expect(throws: RepositoryBootstrapError.identity) { try await service.create(request) { _ in } }
        request = f.request; request.branch = "invalid branch"
        await #expect(throws: RepositoryBootstrapError.branch) { try await service.create(request) { _ in } }
        request = f.request; request.name = "../wrong"
        await #expect(throws: RepositoryBootstrapError.name) { try await service.create(request) { _ in } }
        request = f.request; request.owner = "different-account"
        await #expect(throws: RepositoryBootstrapError.remoteMismatch) { try await service.create(request) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: f.folder.appendingPathComponent(".git").path))
        #expect(await github.createCalls == 0)
        _ = try await f.git(["init", "--initial-branch=main"])
        let child = f.folder.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        await #expect(throws: RepositoryBootstrapError.nested) { try await service.inspect(child) }
        let alias = f.root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: child)
        await #expect(throws: RepositoryBootstrapError.nested) { try await service.inspect(alias) }
        try await f.initBare()
        await #expect(throws: RepositoryBootstrapError.folder) { try await service.inspect(f.bare) }
    }

    @Test("Existing remotes require consent and matching visibility; origin is never replaced")
    func existingRemote() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        try await f.initBare()
        let github = BootstrapGitHub(existing: true)
        let service = f.service(github)
        await #expect(throws: RepositoryBootstrapError.remoteExists) { try await service.create(f.request) { _ in } }
        var request = f.request; request.connectExisting = true; request.isPrivate = false
        await #expect(throws: RepositoryBootstrapError.remoteMismatch) { try await service.create(request) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: f.folder.appendingPathComponent(".git").path))
        request.isPrivate = true
        #expect(try await service.create(request) { _ in }.pushed)
        #expect(await github.createCalls == 0)
        _ = try await f.git(["remote", "set-url", "origin", "https://example.invalid/existing.git"])
        await #expect(throws: RepositoryBootstrapError.origin) { try await service.create(request) { _ in } }
        #expect(try await f.git(["config", "--get", "remote.origin.url"]) == "https://example.invalid/existing.git")
    }

    @Test("Existing project history is not uploaded by the bootstrap workflow")
    func existingHistory() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        let github = BootstrapGitHub()
        var local = f.request; local.createRemote = false
        _ = try await f.service().create(local) { _ in }
        try Data("project contents".utf8).write(to: f.folder.appendingPathComponent("project.txt"))
        _ = try await f.git(["add", "project.txt"])
        _ = try await f.git(["commit", "-m", "Project files"])
        let sha = try await f.git(["rev-parse", "HEAD"])
        let service = f.service(github)
        await #expect(throws: RepositoryBootstrapError.history) { try await service.create(f.request) { _ in } }
        #expect(await github.createCalls == 0)
        var request = f.request; request.pushInitialCommit = false
        let result = try await service.create(request) { _ in }
        #expect(!result.pushed && result.remote != nil)
        #expect(try await f.git(["rev-parse", "HEAD"]) == sha)
    }

    @Test("Concurrent commits cannot be picked up by the initial push")
    func concurrentCommit() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        try await f.initBare()
        await f.runner.commitBeforePush()
        let result = try await f.service().create(f.request) { _ in }
        #expect(result.pushed)
        #expect(try await f.git(["ls-tree", "refs/heads/main"], at: f.bare).isEmpty)
        #expect(try await f.git(["rev-list", "--count", "HEAD"]) == "2")
        #expect(try await f.git(["ls-tree", "HEAD"]).contains("concurrent.txt"))
    }

    @Test("Verification failure never reports success")
    func verification() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        try await f.initBare()
        await f.runner.mismatchVerification()
        let events = BootstrapEvents()
        await #expect(throws: RepositoryBootstrapError.verification) {
            try await f.service().create(f.request) { await events.append($0) }
        }
        #expect(await events.last?.step == .verify)
        #expect(await events.last?.state == .running)
    }

    @Test("Remote waits have a finite deadline and release the creation gate")
    func deadline() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        let github = BootstrapGitHub(); await github.delayAccount()
        let service = RepositoryBootstrapService(git: f.runner, github: github, environment: f.environment,
                                                 operationTimeout: .seconds(2))
        let start = ContinuousClock.now
        await #expect(throws: URLError.self) { try await service.create(f.request) { _ in } }
        #expect(start.duration(to: .now) < .seconds(5))
        #expect(!FileManager.default.fileExists(atPath: f.folder.appendingPathComponent(".git").path))
        var invalid = f.request; invalid.folder = f.root.appendingPathComponent("missing")
        await #expect(throws: RepositoryBootstrapError.folder) { try await service.create(invalid) { _ in } }
    }

    @MainActor @Test("Every form field, step and failure has bundled translations")
    func localizationAndEntry() throws {
        defer { L10n.activate(AppPreferencesStore.load().language) }
        let keys = "title folder choose files_note existing_note branch identity author email remote name visibility private public existing push success agent agent_prompt refresh_account recovery step.check step.local step.remote step.link step.push step.verify error.folder error.nested error.name error.branch error.identity error.origin error.remoteExists error.remoteMismatch error.history error.changed error.busy error.verification".split(separator: " ")
        for language in AppLanguage.allCases where language != .system {
            let bundle = L10n.bundle(preferredLanguages: [language.rawValue])
            #expect(bundle.bundleURL.lastPathComponent.lowercased() == language.rawValue.lowercased() + ".lproj")
            L10n.activate(language)
            for suffix in keys {
                let key = "repository.create.\(suffix)"
                #expect(bundle.localizedString(forKey: key, value: nil, table: nil) != key)
            }
            let report = GlobalErrorHandler.report(for: RepositoryBootstrapError.origin, context: .repositoryCreate)
            #expect(report.explanation == L10n.text("repository.create.error.origin"))
        }
        let model = WorkspaceViewModel(isBackgroundMonitor: true, monitoredRepositories: [])
        #expect(model.snapshot == nil)
        model.runGitAgentSkill(.repositorySetup)
        #expect(model.showsRepositoryCreation)
        #expect(!model.isCodexRunning)
        #expect(GitAgentProfile.repositorySetupPrompt.contains("Do not stage, commit, push"))
        #expect(GitAgentProfile.repositorySetupPrompt.contains("README.md and .gitignore only"))
    }
}

private actor BootstrapEvents {
    var values: [RepositoryBootstrapEvent] = []
    var last: RepositoryBootstrapEvent? { values.last }
    func append(_ event: RepositoryBootstrapEvent) { values.append(event) }
}

actor BootstrapGitHub: GitHubRepositoryCreating {
    private(set) var accountCalls = 0
    private(set) var createCalls = 0
    private(set) var authenticationCalls = 0
    private var existing: Bool
    private var accountFails = false
    private var accountDelayed = false
    private var creationDelayed = false
    init(existing: Bool = false) { self.existing = existing }
    func failAccount() { accountFails = true }
    func delayCreation() { creationDelayed = true }
    func delayAccount() { accountDelayed = true }
    func currentAccount() async throws -> GitHubAccount {
        accountCalls += 1
        if accountFails { throw GitHubServiceError.executableNotFound }
        if accountDelayed { try await Task.sleep(for: .seconds(30)) }
        return GitHubAccount(login: "fixture-owner", name: nil, webURL: URL(string: "https://github.com/fixture-owner")!)
    }
    func repositoryForCreation(owner: String, name: String) async throws -> GitHubRepository? { existing ? repository(name) : nil }
    func createRepository(name: String, isPrivate: Bool) async throws -> GitHubRepository {
        if creationDelayed { try await Task.sleep(for: .seconds(30)) }
        createCalls += 1; existing = true
        return repository(name, isPrivate: isPrivate)
    }
    func configureRepositoryAuthentication(in folder: URL) { authenticationCalls += 1 }
    private func repository(_ name: String, isPrivate: Bool = true) -> GitHubRepository {
        GitHubRepository(fullName: "fixture-owner/\(name)", name: name, owner: "fixture-owner", description: nil,
            webURL: URL(string: "https://github.com/fixture-owner/\(name)")!, stars: 0, forks: 0, openIssues: 0,
            language: nil, updatedAt: Date(timeIntervalSince1970: 0), isPrivate: isPrivate, defaultBranch: "main")
    }
}

struct BootstrapFixture {
    let root: URL
    let folder: URL
    let bare: URL
    let runner: BootstrapGitRunner
    let environment: [String: String]
    var remoteURL: String { "https://github.com/fixture-owner/demo.git" }
    var request: RepositoryBootstrapRequest {
        RepositoryBootstrapRequest(folder: folder, name: "demo", owner: "fixture-owner", authorName: "Fixture Maintainer", authorEmail: "fixture@example.invalid")
    }
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("GitGatto-Bootstrap-\(UUID())").resolvingSymlinksInPath()
        folder = root.appendingPathComponent("Project with spaces")
        bare = root.appendingPathComponent("isolated.git")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        environment = ["HOME": root.path, "XDG_CONFIG_HOME": root.path,
            "GIT_CONFIG_GLOBAL": root.appendingPathComponent("global.gitconfig").path, "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Fixture Maintainer", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
            "GIT_COMMITTER_NAME": "Fixture Maintainer", "GIT_COMMITTER_EMAIL": "fixture@example.invalid"]
        runner = BootstrapGitRunner(bare: bare)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func initBare() async throws { _ = try await git(["init", "--bare", bare.path], at: root) }
    func service(_ github: BootstrapGitHub = BootstrapGitHub()) -> RepositoryBootstrapService {
        RepositoryBootstrapService(git: runner, github: github, environment: environment)
    }
    func git(_ arguments: [String], at url: URL? = nil) async throws -> String {
        try await runner.run(at: url ?? folder, arguments: arguments, environment: environment, acceptedExitCodes: [0])
            .text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

actor BootstrapGitRunner: RepositoryBootstrapGitRunning {
    private let bare: URL
    private var failPush = false
    private var changeBeforePush = false
    private var mismatches = false
    init(bare: URL) { self.bare = bare }
    func failNextPush() { failPush = true }
    func commitBeforePush() { changeBeforePush = true }
    func mismatchVerification() { mismatches = true }
    func run(at repositoryURL: URL, arguments: [String], environment: [String: String], acceptedExitCodes: Set<Int32>) async throws -> GitCommandResult {
        let native = GitCommandRunner()
        var args = arguments
        if args.first == "push" || args.first == "ls-remote" {
            // No network transports are allowed in this fixture. Only the synthetic GitHub URL is routed locally.
            guard let index = args.firstIndex(of: "https://github.com/fixture-owner/demo.git") else {
                throw RepositoryBootstrapError.remoteMismatch
            }
            args[index] = bare.path
            if args.first == "push", failPush {
                failPush = false
                throw GitCommandError(arguments: arguments, exitCode: 1, message: "synthetic push failure")
            }
            if args.first == "push", changeBeforePush {
                changeBeforePush = false
                try Data("concurrent contents".utf8).write(to: repositoryURL.appendingPathComponent("concurrent.txt"))
                _ = try await native.run(at: repositoryURL, arguments: ["add", "concurrent.txt"], environment: environment)
                _ = try await native.run(at: repositoryURL, arguments: ["commit", "-m", "Concurrent project edit"], environment: environment)
            }
            if args.first == "ls-remote", mismatches {
                return GitCommandResult(output: Data("0000000000000000000000000000000000000000\trefs/heads/main\n".utf8), errorOutput: Data(), exitCode: 0)
            }
        }
        return try await native.run(at: repositoryURL, arguments: args, environment: environment, acceptedExitCodes: acceptedExitCodes)
    }
}
