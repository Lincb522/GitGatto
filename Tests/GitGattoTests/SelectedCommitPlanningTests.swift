import Foundation
import Testing
@testable import GitGatto

@Suite("Selected diff commit planning", .serialized)
struct SelectedCommitPlanningTests {
    @Test("Only selected lines are committed; other index and worktree content is retained", arguments: [false, true])
    func exactSelection(staged: Bool) async throws {
        let f = try SelectionFixture()
        defer { f.remove() }
        var index = f.base
        index[1] = "already staged"
        if staged { index[14] = "selected"; index[15] = "not selected" }
        try f.write(index); try await f.git(["add", "file.txt"])
        var working = index
        working[28] = "keep working"
        if !staged { working[14] = "selected"; working[15] = "not selected" }
        try f.write(working)
        try Data("untracked".utf8).write(to: f.repository.appendingPathComponent("untracked.txt"))
        let (request, _, _) = try await f.selection(staged: staged)
        let beforeIndex = try Data(contentsOf: f.repository.appendingPathComponent(".git/index"))
        let head = try await f.git(["rev-parse", "HEAD"])
        let plan = try await f.service.makePlan(in: f.repository, selection: request)
        #expect(try Data(contentsOf: f.repository.appendingPathComponent(".git/index")) == beforeIndex)
        #expect(try await f.git(["rev-parse", "HEAD"]) == head)
        #expect(plan.selection == request)
        #expect(plan.units.allSatisfy { $0.kind == .hunk && $0.path == "file.txt" })
        let roundTrip = try JSONDecoder().decode(ChangeIntentPlan.self, from: JSONEncoder().encode(plan))
        #expect(roundTrip == plan)
        let result = try await f.service.apply(roundTrip, verificationCommand: nil, in: f.repository)
        #expect(result.commitHashes.count == 1)
        var committed = f.base; committed[14] = "selected"
        #expect(try await f.git(["show", "HEAD:file.txt"]) == f.text(committed))
        if !staged { index[14] = "selected" }
        #expect(try await f.git(["show", ":file.txt"]) == f.text(index))
        #expect(try String(contentsOf: f.repository.appendingPathComponent("file.txt"), encoding: .utf8) == f.text(working))
        #expect(try String(contentsOf: f.repository.appendingPathComponent("untracked.txt"), encoding: .utf8) == "untracked")
    }

    @Test("Partial staging and unstaging retain the position of adjacent replacements")
    func adjacentPartialStage() async throws {
        let f = try SelectionFixture(); defer { f.remove() }
        var work = f.base; work[14] = "selected"; work[15] = "not selected"
        try f.write(work)
        let (_, document, change) = try await f.selection(staged: false)
        let ids = Set(document.lines.filter { $0.text == "+selected" || $0.text == "-line 15" }.map(\.id))
        let service = GitRepositoryService()
        try await service.stageSelection(ids, document: document, change: change, in: f.repository)
        var expected = f.base; expected[14] = "selected"
        #expect(try await f.git(["show", ":file.txt"]) == f.text(expected))
        try await f.git(["add", "."])
        let (_, stagedDocument, stagedChange) = try await f.selection(staged: true)
        let reverse = Set(stagedDocument.lines.filter { $0.text == "+selected" || $0.text == "-line 15" }.map(\.id))
        try await service.stageSelection(reverse, document: stagedDocument, change: stagedChange, in: f.repository)
        expected = f.base; expected[15] = "not selected"
        #expect(try await f.git(["show", ":file.txt"]) == f.text(expected))
        #expect(try String(contentsOf: f.repository.appendingPathComponent("file.txt"), encoding: .utf8) == f.text(work))
    }

    @Test("A commit hook cannot expand the selected commit without failing and restoring the index")
    func hookExpandsSelection() async throws {
        let f = try SelectionFixture(); defer { f.remove() }
        var content = f.base; content[14] = "selected"; try f.write(content)
        let extra = f.repository.appendingPathComponent("unselected.txt")
        try Data("not selected\n".utf8).write(to: extra)
        let hooks = f.repository.appendingPathComponent(".git/hooks")
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        let hook = hooks.appendingPathComponent("pre-commit")
        try Data("#!/bin/sh\ngit add -- unselected.txt\n".utf8).write(to: hook)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        let (request, _, _) = try await f.selection(staged: false)
        let plan = try await f.service.makePlan(in: f.repository, selection: request)
        let before = try await f.state()
        await #expect(throws: ChangeIntentError.repositoryChanged) {
            _ = try await f.service.apply(plan, verificationCommand: nil, in: f.repository)
        }
        #expect(try await f.state() == before)
        #expect(try await f.git(["ls-files", "--", "unselected.txt"]).isEmpty)
        #expect(try String(contentsOf: extra, encoding: .utf8) == "not selected\n")
    }

    @Test("An unstaged edit that depends on an unselected staged line is rejected without index writes")
    func dependentSelection() async throws {
        let f = try SelectionFixture(); defer { f.remove() }
        var content = f.base; content[14] = "staged dependency"
        try f.write(content); try await f.git(["add", "."])
        content[14] = "selected"; try f.write(content)
        let (request, _, _) = try await f.selection(staged: false, deleted: "staged dependency")
        let before = try await f.state()
        await #expect(throws: ChangeIntentError.selectionDependency) {
            _ = try await f.service.makePlan(in: f.repository, selection: request)
        }
        #expect(try await f.state() == before)
    }

    @Test("Stale displayed selection and changed plan fail before repository mutation")
    func staleSelection() async throws {
        let f = try SelectionFixture(); defer { f.remove() }
        var content = f.base; content[14] = "selected"; try f.write(content)
        let (request, _, _) = try await f.selection(staged: false)
        let plan = try await f.service.makePlan(in: f.repository, selection: request)
        content[15] = "newer edit"; try f.write(content)
        let before = try await f.state()
        await #expect(throws: PartialDiffError.changed) { _ = try await f.service.makePlan(in: f.repository, selection: request) }
        await #expect(throws: ChangeIntentError.repositoryChanged) { _ = try await f.service.apply(plan, verificationCommand: nil, in: f.repository) }
        #expect(try await f.state() == before)
    }

    @Test("Verification failure and cancellation restore HEAD and preexisting staged content", arguments: [false, true])
    func rollback(cancel: Bool) async throws {
        let f = try SelectionFixture(); defer { f.remove() }
        var content = f.base; content[1] = "already staged"
        try f.write(content); try await f.git(["add", "."])
        content[14] = "selected"; try f.write(content)
        let (request, _, _) = try await f.selection(staged: false)
        let plan = try await f.service.makePlan(in: f.repository, selection: request)
        let before = try await f.state()
        if cancel {
            let marker = f.root.appendingPathComponent("verifying")
            let task = Task { try await f.service.apply(plan,
                verificationCommand: "touch '\(marker.path)'; exec /bin/sleep 30", in: f.repository) }
            let deadline = ContinuousClock.now + .seconds(45)
            while !FileManager.default.fileExists(atPath: marker.path), ContinuousClock.now < deadline { await Task.yield() }
            let reached = FileManager.default.fileExists(atPath: marker.path)
            task.cancel()
            _ = try? await task.value
            #expect(reached)
        } else {
            await #expect(throws: ChangeIntentError.self) {
                _ = try await f.service.apply(plan, verificationCommand: "exit 7", in: f.repository)
            }
        }
        #expect(try await f.state() == before)
    }

    @Test("Selected changes survive index line offsets, CRLF and no newline at EOF", arguments: ["\n", "\r\n"])
    func offsetsAndEOF(separator: String) async throws {
        let f = try SelectionFixture(separator: separator, trailingNewline: false); defer { f.remove() }
        var index = f.base; index.insert("staged insertion", at: 0)
        try f.write(index); try await f.git(["add", "."])
        var work = index; work[15] = "selected"; try f.write(work)
        let (request, _, _) = try await f.selection(staged: false)
        let plan = try await f.service.makePlan(in: f.repository, selection: request)
        _ = try await f.service.apply(plan, verificationCommand: nil, in: f.repository)
        var expected = f.base; expected[14] = "selected"
        #expect(try await f.git(["show", "HEAD:file.txt"]) == f.text(expected))
        #expect(try await f.git(["show", ":file.txt"]) == f.text(work))
    }
}

private struct SelectionFixture {
    let root: URL
    let repository: URL
    let service: ChangeIntentService
    let base = (1...32).map { "line \($0)" }
    let separator: String
    let trailingNewline: Bool
    init(separator: String = "\n", trailingNewline: Bool = true) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("selected-plan-\(UUID())")
        repository = root.appendingPathComponent("repo")
        self.separator = separator; self.trailingNewline = trailingNewline
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        service = ChangeIntentService(backupService: RepositoryBackupService(rootURL: root.appendingPathComponent("backups")))
        for args in [["init", "--template=", "-b", "main"], ["config", "user.name", "Test"], ["config", "user.email", "test@example.invalid"], ["config", "commit.gpgsign", "false"], ["config", "core.autocrlf", "false"]] {
            try Self.run(args, in: repository)
        }
        if separator == "\r\n" { try Self.run(["config", "core.whitespace", "cr-at-eol"], in: repository) }
        try write(base)
        try Self.run(["add", "."], in: repository); try Self.run(["commit", "-m", "initial"], in: repository)
    }
    func text(_ lines: [String]) -> String { lines.joined(separator: separator) + (trailingNewline ? separator : "") }
    func write(_ lines: [String]) throws { try Data(text(lines).utf8).write(to: repository.appendingPathComponent("file.txt")) }
    @discardableResult func git(_ args: [String]) async throws -> String { try await GitCommandRunner().run(at: repository, arguments: args).text }
    func selection(staged: Bool, deleted: String = "line 15") async throws -> (ChangeIntentSelection, DiffDocument, WorkingTreeChange) {
        let change = WorkingTreeChange(path: "file.txt", originalPath: nil, indexStatus: staged ? .modified : .unmodified, workTreeStatus: .modified)
        let source = try await git(["diff"] + (staged ? ["--cached"] : []) + ["--no-ext-diff", "--no-textconv", "--no-color", "--unified=4", "--", "file.txt"])
        let document = GitParsers.diff(from: source, path: "file.txt")
        let ids = Set(document.lines.filter { $0.text.trimmingCharacters(in: .newlines) == "+selected" || $0.text.trimmingCharacters(in: .newlines) == "-\(deleted)" }.map(\.id))
        #expect(ids.count == 2)
        return (try ChangeIntentSelection(document: document, change: change, selectedIDs: ids), document, change)
    }
    func state() async throws -> [String] {
        [try await git(["rev-parse", "HEAD"]), try await git(["diff", "--cached", "--binary"]),
         try await git(["diff", "--binary"]), try String(contentsOf: repository.appendingPathComponent("file.txt"), encoding: .utf8)]
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    private static func run(_ args: [String], in repository: URL) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p.arguments = ["-C", repository.path] + args
        p.environment = ProcessInfo.processInfo.environment.merging(["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]) { _, new in new }
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
