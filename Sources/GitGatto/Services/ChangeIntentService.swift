import CryptoKit
import Foundation

protocol ChangeIntentServing: Sendable {
    func makePlan(in repositoryURL: URL) async throws -> ChangeIntentPlan
    func apply(
        _ plan: ChangeIntentPlan,
        verificationCommand: String?,
        in repositoryURL: URL
    ) async throws -> ChangeIntentApplyResult
}

actor ChangeIntentService: ChangeIntentServing {
    private let runner: GitCommandRunner
    private let backupService: any RepositoryBackupServing

    init(
        runner: GitCommandRunner = GitCommandRunner(),
        backupService: any RepositoryBackupServing = RepositoryBackupService()
    ) {
        self.runner = runner
        self.backupService = backupService
    }

    func makePlan(in repositoryURL: URL) async throws -> ChangeIntentPlan {
        let repository = repositoryURL.standardizedFileURL
        let statusResult = try await runner.run(
            at: repository,
            arguments: ["status", "--porcelain=v1", "-z", "--branch", "--untracked-files=all"]
        )
        guard let status = GitParsers.statusSnapshot(from: statusResult.output) else {
            throw ChangeIntentError.invalidPlan(L10n.text("intelligence.intent.error.status"))
        }
        guard !status.changes.isEmpty else { throw ChangeIntentError.noChanges }
        guard !status.changes.contains(where: {
            $0.indexStatus == .conflicted || $0.workTreeStatus == .conflicted
        }) else {
            throw ChangeIntentError.unresolvedConflicts
        }

        var changeUnits: [ChangeIntentUnit] = []
        for change in status.changes {
            try Task.checkCancellation()
            changeUnits.append(contentsOf: try await units(for: change, in: repository))
        }
        guard !changeUnits.isEmpty else { throw ChangeIntentError.noChanges }
        let groups = Self.defaultGroups(for: changeUnits)
        return ChangeIntentPlan(
            repositoryPath: repository.path,
            repositoryFingerprint: try await fingerprint(in: repository),
            units: changeUnits,
            groups: groups
        )
    }

    func apply(
        _ plan: ChangeIntentPlan,
        verificationCommand: String?,
        in repositoryURL: URL
    ) async throws -> ChangeIntentApplyResult {
        let repository = repositoryURL.standardizedFileURL
        guard plan.repositoryPath == repository.path else {
            throw ChangeIntentError.invalidPlan(L10n.text("intelligence.intent.error.repository"))
        }
        guard try await fingerprint(in: repository) == plan.repositoryFingerprint else {
            throw ChangeIntentError.repositoryChanged
        }
        let unitByID = Dictionary(uniqueKeysWithValues: plan.units.map { ($0.id, $0) })
        let assignedIDs = plan.groups.flatMap(\.unitIDs)
        guard Set(assignedIDs) == Set(unitByID.keys),
              assignedIDs.count == unitByID.count,
              plan.groups.allSatisfy({
                  !$0.unitIDs.isEmpty
                      && !$0.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              })
        else {
            throw ChangeIntentError.invalidPlan(L10n.text("intelligence.intent.error.assignment"))
        }

        _ = try await backupService.createBackup(
            for: repository,
            reason: .manual,
            policy: .standard
        )
        let startingHead = try await gitText(["rev-parse", "HEAD"], in: repository)
        let stagedPatch = try await runner.run(
            at: repository,
            arguments: ["diff", "--cached", "--binary", "--full-index", "HEAD", "--"]
        ).output
        var createdHashes: [String] = []
        var verificationOutputs: [String] = []

        do {
            _ = try await runner.run(at: repository, arguments: ["reset", "--mixed", "--quiet", "HEAD"])
            for group in plan.groups {
                try Task.checkCancellation()
                for id in group.unitIDs {
                    guard let unit = unitByID[id] else {
                        throw ChangeIntentError.invalidPlan(L10n.text("intelligence.intent.error.assignment"))
                    }
                    try await stage(unit, in: repository)
                }
                let staged = try await runner.run(
                    at: repository,
                    arguments: ["diff", "--cached", "--quiet"],
                    acceptedExitCodes: [0, 1]
                )
                guard staged.exitCode == 1 else {
                    throw ChangeIntentError.invalidPlan(
                        L10n.format("intelligence.intent.error.empty_group", group.title)
                    )
                }
                _ = try await runner.run(
                    at: repository,
                    arguments: ["commit", "-m", group.commitMessage]
                )
                let hash = try await gitText(["rev-parse", "HEAD"], in: repository)
                createdHashes.append(hash)

                let command = verificationCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if command.isEmpty {
                    let check = try await runner.run(
                        at: repository,
                        arguments: ["diff", "--check", "HEAD^", "HEAD"]
                    )
                    verificationOutputs.append(check.text)
                } else {
                    let output = try await verify(command: command, in: repository)
                    verificationOutputs.append(output)
                }
            }
            return ChangeIntentApplyResult(
                commitHashes: createdHashes,
                verificationOutputs: verificationOutputs
            )
        } catch {
            await restoreOriginalState(
                head: startingHead,
                stagedPatch: stagedPatch,
                in: repository
            )
            throw error
        }
    }

    private func units(
        for change: WorkingTreeChange,
        in repositoryURL: URL
    ) async throws -> [ChangeIntentUnit] {
        let status = "\(change.indexStatus.rawValue)\(change.workTreeStatus.rawValue)"
        if change.primaryStatus == .untracked {
            return [wholeFileUnit(change: change, status: status)]
        }
        let patch = try await runner.run(
            at: repositoryURL,
            arguments: [
                "diff", "--binary", "--full-index", "--find-renames", "HEAD", "--", change.path,
            ]
        ).text
        guard !patch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [wholeFileUnit(change: change, status: status)]
        }
        let pieces = Self.splitPatch(patch)
        guard !pieces.hunks.isEmpty else {
            return [wholeFileUnit(change: change, status: status, patch: patch)]
        }
        return pieces.hunks.enumerated().map { index, hunk in
            let completePatch = (pieces.prelude + hunk).joined(separator: "\n") + "\n"
            let counts = Self.lineCounts(in: hunk)
            return ChangeIntentUnit(
                id: Self.unitID(path: change.path, index: index, patch: completePatch),
                path: change.path,
                originalPath: change.originalPath,
                kind: .hunk,
                status: status,
                hunkHeader: hunk.first,
                patch: completePatch,
                addedLineCount: counts.added,
                deletedLineCount: counts.deleted
            )
        }
    }

    private func wholeFileUnit(
        change: WorkingTreeChange,
        status: String,
        patch: String? = nil
    ) -> ChangeIntentUnit {
        ChangeIntentUnit(
            id: Self.unitID(path: change.path, index: 0, patch: patch ?? status),
            path: change.path,
            originalPath: change.originalPath,
            kind: .wholeFile,
            status: status,
            hunkHeader: nil,
            patch: patch,
            addedLineCount: patch.map { Self.lineCounts(in: $0.components(separatedBy: "\n")).added } ?? 0,
            deletedLineCount: patch.map { Self.lineCounts(in: $0.components(separatedBy: "\n")).deleted } ?? 0
        )
    }

    private func stage(_ unit: ChangeIntentUnit, in repositoryURL: URL) async throws {
        switch unit.kind {
        case .wholeFile:
            var paths = [unit.path]
            if let originalPath = unit.originalPath, originalPath != unit.path {
                paths.append(originalPath)
            }
            _ = try await runner.run(
                at: repositoryURL,
                arguments: ["add", "-A", "--"] + paths
            )
        case .hunk:
            guard let patch = unit.patch else {
                throw ChangeIntentError.unsupportedChange(unit.path)
            }
            let patchURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("gitgatto-intent-\(UUID().uuidString)")
                .appendingPathExtension("patch")
            defer { try? FileManager.default.removeItem(at: patchURL) }
            try Data(patch.utf8).write(to: patchURL, options: .atomic)
            _ = try await runner.run(
                at: repositoryURL,
                arguments: ["apply", "--cached", "--recount", "--unidiff-zero", "--", patchURL.path]
            )
        }
    }

    private func verify(command: String, in repositoryURL: URL) async throws -> String {
        let result: ExternalProcessResult
        do {
            result = try await ExternalProcessRunner().run(
                executable: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-lc", command],
                currentDirectoryURL: repositoryURL,
                timeout: .seconds(600)
            )
        } catch {
            throw ChangeIntentError.verificationFailed(
                command: command,
                output: String(error.localizedDescription.prefix(12_000))
            )
        }
        return String(
            String(decoding: result.standardOutput + result.standardError, as: UTF8.self)
                .prefix(12_000)
        )
    }

    private func restoreOriginalState(
        head: String,
        stagedPatch: Data,
        in repositoryURL: URL
    ) async {
        _ = try? await runner.run(
            at: repositoryURL,
            arguments: ["reset", "--mixed", "--quiet", head]
        )
        guard !stagedPatch.isEmpty else { return }
        let patchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitgatto-index-\(UUID().uuidString)")
            .appendingPathExtension("patch")
        defer { try? FileManager.default.removeItem(at: patchURL) }
        try? stagedPatch.write(to: patchURL, options: .atomic)
        _ = try? await runner.run(
            at: repositoryURL,
            arguments: ["apply", "--cached", "--binary", "--", patchURL.path]
        )
    }

    private func fingerprint(in repositoryURL: URL) async throws -> String {
        async let head = runner.run(at: repositoryURL, arguments: ["rev-parse", "HEAD"])
        async let status = runner.run(
            at: repositoryURL,
            arguments: ["status", "--porcelain=v1", "-z", "--untracked-files=all"]
        )
        let payload = try await head.output + status.output
        return SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    private func gitText(_ arguments: [String], in repositoryURL: URL) async throws -> String {
        try await runner.run(at: repositoryURL, arguments: arguments)
            .text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func splitPatch(_ patch: String) -> (prelude: [String], hunks: [[String]]) {
        var lines = patch.components(separatedBy: "\n")
        if lines.last?.isEmpty == true { lines.removeLast() }
        guard let firstHunk = lines.firstIndex(where: { $0.hasPrefix("@@") }) else {
            return (lines, [])
        }
        let prelude = Array(lines[..<firstHunk])
        var hunks: [[String]] = []
        var current: [String] = []
        for line in lines[firstHunk...] {
            if line.hasPrefix("@@"), !current.isEmpty {
                hunks.append(current)
                current = []
            }
            current.append(line)
        }
        if !current.isEmpty { hunks.append(current) }
        return (prelude, hunks)
    }

    static func lineCounts(in lines: [String]) -> (added: Int, deleted: Int) {
        var added = 0
        var deleted = 0
        for line in lines {
            if line.hasPrefix("+") && !line.hasPrefix("+++") { added += 1 }
            if line.hasPrefix("-") && !line.hasPrefix("---") { deleted += 1 }
        }
        return (added, deleted)
    }

    private static func unitID(path: String, index: Int, patch: String) -> String {
        let payload = Data("\(path)\u{0}\(index)\u{0}\(patch)".utf8)
        return SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    static func defaultGroups(for units: [ChangeIntentUnit]) -> [ChangeIntentGroup] {
        var remaining = units
        var relatedCodeGroups: [[ChangeIntentUnit]] = []
        let implementationUnits = remaining.filter { kind(for: $0.path) == .implementation }
        let testUnits = remaining.filter { kind(for: $0.path) == .tests }
        let implementationsBySubject = Dictionary(grouping: implementationUnits) {
            relationshipSubject(for: $0.path)
        }
        let testsBySubject = Dictionary(grouping: testUnits) {
            relationshipSubject(for: $0.path)
        }
        for subject in Set(implementationsBySubject.keys).intersection(testsBySubject.keys).sorted() {
            relatedCodeGroups.append(
                (implementationsBySubject[subject] ?? []) + (testsBySubject[subject] ?? [])
            )
        }
        let relatedIDs = Set(relatedCodeGroups.flatMap { $0.map(\.id) })
        remaining.removeAll { relatedIDs.contains($0.id) }

        var result = relatedCodeGroups.map { members in
            let subject = commonSubject(for: members.map(\.path))
            return ChangeIntentGroup(
                title: defaultTitle(for: .implementation),
                commitMessage: defaultMessage(for: .implementation, subject: subject),
                kind: .implementation,
                unitIDs: members.map(\.id)
            )
        }
        let grouped = Dictionary(grouping: remaining) { kind(for: $0.path) }
        let order = ChangeIntentKind.allCases
        result.append(contentsOf: order.compactMap { kind in
            guard let members = grouped[kind], !members.isEmpty else { return nil }
            let subject = commonSubject(for: members.map(\.path))
            return ChangeIntentGroup(
                title: defaultTitle(for: kind),
                commitMessage: defaultMessage(for: kind, subject: subject),
                kind: kind,
                unitIDs: members.map(\.id)
            )
        })
        return result
    }

    static func kind(for path: String) -> ChangeIntentKind {
        let value = path.lowercased()
        let components = value.split(separator: "/").map(String.init)
        let ext = URL(fileURLWithPath: value).pathExtension
        if components.contains(where: { $0 == "tests" || $0 == "test" || $0 == "spec" || $0 == "specs" }) {
            return .tests
        }
        if value.hasPrefix("docs/") || value.contains("/docs/")
            || ["md", "mdx", "rst", "adoc"].contains(ext)
        {
            return .documentation
        }
        if ["png", "jpg", "jpeg", "gif", "webp", "svg", "pdf", "mov", "mp4", "m4v", "wav", "mp3"].contains(ext) {
            return .assets
        }
        let configurationNames = [
            "package.swift", "package.json", "project.yml", "podfile", "cartfile",
            "cargo.toml", "go.mod", "pyproject.toml", "dockerfile", "makefile",
        ]
        if configurationNames.contains(URL(fileURLWithPath: value).lastPathComponent)
            || ["yml", "yaml", "toml", "xcconfig", "plist", "json"].contains(ext)
        {
            return .configuration
        }
        return .implementation
    }

    private static func commonSubject(for paths: [String]) -> String {
        guard let first = paths.first else { return "changes" }
        let stem = URL(fileURLWithPath: first).deletingPathExtension().lastPathComponent
        if paths.count == 1 { return stem }
        let top = first.split(separator: "/").first.map(String.init) ?? "project"
        return top.lowercased() == "sources" ? "implementation" : top
    }

    private static func relationshipSubject(for path: String) -> String {
        var value = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.lowercased()
        for suffix in ["integrationtests", "uitests", "tests", "test", "specs", "spec"]
            where value.hasSuffix(suffix)
        {
            value.removeLast(suffix.count)
            break
        }
        return value
    }

    private static func defaultTitle(for kind: ChangeIntentKind) -> String {
        L10n.text("intelligence.intent.kind.\(kind.rawValue)")
    }

    private static func defaultMessage(for kind: ChangeIntentKind, subject: String) -> String {
        let prefix: String
        switch kind {
        case .implementation: prefix = "feat"
        case .fix: prefix = "fix"
        case .refactor: prefix = "refactor"
        case .tests: prefix = "test"
        case .documentation: prefix = "docs"
        case .configuration, .assets, .other: prefix = "chore"
        }
        return "\(prefix): update \(subject)"
    }
}

enum ChangeIntentAgentPlanner {
    private struct Response: Decodable {
        let groups: [Group]
    }

    private struct Group: Decodable {
        let title: String
        let message: String
        let kind: ChangeIntentKind
        let unitIDs: [String]
    }

    static func prompt(for plan: ChangeIntentPlan) -> String {
        let units = plan.units.map { unit in
            let sample = unit.patch?
                .split(separator: "\n")
                .filter { $0.hasPrefix("+") || $0.hasPrefix("-") }
                .prefix(6)
                .joined(separator: "\n") ?? ""
            return "ID: \(unit.id)\nPath: \(unit.path)\nHunk: \(unit.hunkHeader ?? "whole file")\nSample:\n\(sample)"
        }.joined(separator: "\n---\n")
        return """
        Organize the supplied change units into a small ordered series of atomic Git commits.
        Group by intent rather than by file type. Keep implementation and its directly corresponding tests together when that makes the commit independently understandable. Every unit ID must appear exactly once. Do not invent IDs. Commit messages must be specific, imperative, and no longer than 72 characters.

        Return JSON only in this exact shape:
        {"groups":[{"title":"...","message":"...","kind":"implementation|fix|refactor|tests|documentation|configuration|assets|other","unitIDs":["..."]}]}

        Change units:
        \(units)
        """
    }

    static func refinedPlan(from response: String, original: ChangeIntentPlan) throws -> ChangeIntentPlan {
        var json = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```") {
            let lines = json.split(separator: "\n", omittingEmptySubsequences: false)
            json = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: Data(json.utf8))
        guard !decoded.groups.isEmpty, decoded.groups.count <= 12 else {
            throw ChangeIntentError.invalidPlan(L10n.text("intelligence.intent.error.agent_plan"))
        }
        let available = Set(original.units.map(\.id))
        let assigned = decoded.groups.flatMap(\.unitIDs)
        guard assigned.count == available.count, Set(assigned) == available else {
            throw ChangeIntentError.invalidPlan(L10n.text("intelligence.intent.error.assignment"))
        }
        var result = original
        result.groups = decoded.groups.map {
            ChangeIntentGroup(
                title: String($0.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)),
                commitMessage: String($0.message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(72)),
                kind: $0.kind,
                unitIDs: $0.unitIDs
            )
        }
        guard result.groups.allSatisfy({ !$0.title.isEmpty && !$0.commitMessage.isEmpty }) else {
            throw ChangeIntentError.invalidPlan(L10n.text("intelligence.intent.error.agent_plan"))
        }
        return result
    }
}
