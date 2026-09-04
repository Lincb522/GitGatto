import Foundation

extension GitRepositoryService {
    func referenceSnapshot(in repositoryURL: URL) async throws -> GitReferenceSnapshot {
        async let localReferencesResult = runner.run(
            at: repositoryURL,
            arguments: [
                "for-each-ref",
                "--format=%(refname)%00%(refname:short)%00%(objectname)",
                "refs/heads",
                "refs/remotes",
            ]
        )
        async let tagsResult = runner.run(
            at: repositoryURL,
            arguments: [
                "for-each-ref",
                "--sort=-creatordate",
                "--format=%(refname:short)%00%(objectname)%00%(*objectname)%00%(objecttype)%00%(creatordate:unix)%00%(creator)%00%(subject)",
                "refs/tags",
            ]
        )
        async let remotesResult = runner.run(
            at: repositoryURL,
            arguments: ["remote", "-v"]
        )
        async let reflogResult = runner.run(
            at: repositoryURL,
            arguments: [
                "reflog", "show", "--all", "-n", "250",
                "--format=%gD%x00%H%x00%at%x00%gs",
            ],
            acceptedExitCodes: [0, 128]
        )
        async let headResult = runner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "HEAD"],
            acceptedExitCodes: [0, 128]
        )

        let (referenceOutput, tagOutput, remoteOutput, reflogOutput, headOutput) = try await (
            localReferencesResult,
            tagsResult,
            remotesResult,
            reflogResult,
            headResult
        )
        let tags = Self.parseTags(tagOutput.text)
        var references = Self.parseReferences(referenceOutput.text)
        references.append(contentsOf: tags.map {
            GitReferenceRecord(name: $0.name, revision: $0.name, shortHash: $0.shortHash, kind: .tag)
        })
        if headOutput.exitCode == 0 {
            let hash = headOutput.text.trimmingCharacters(in: .whitespacesAndNewlines)
            references.insert(
                GitReferenceRecord(name: "HEAD", revision: "HEAD", shortHash: String(hash.prefix(8)), kind: .head),
                at: 0
            )
        }

        return GitReferenceSnapshot(
            references: references,
            tags: tags,
            remotes: Self.parseRemotes(remoteOutput.text),
            reflog: reflogOutput.exitCode == 0 ? Self.parseReflog(reflogOutput.text) : []
        )
    }

    func compare(
        from baseRevision: String,
        to targetRevision: String,
        mode: GitComparisonMode,
        in repositoryURL: URL
    ) async throws -> DiffDocument {
        let base = baseRevision.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = targetRevision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !target.isEmpty else {
            throw GitReferenceServiceError.invalidName(base.isEmpty ? baseRevision : targetRevision)
        }
        let baseHash = try await resolvedCommit(base, in: repositoryURL)
        let targetHash = try await resolvedCommit(target, in: repositoryURL)
        let separator = mode == .direct ? ".." : "..."
        let result = try await runner.run(
            at: repositoryURL,
            arguments: [
                "diff", "--find-renames", "--find-copies", "--no-ext-diff", "--no-textconv",
                "--no-color", "--unified=4", "\(baseHash)\(separator)\(targetHash)", "--",
            ]
        )
        return GitParsers.diff(from: result.text, path: "\(base)\(separator)\(target)")
    }

    func createBranch(
        named name: String,
        from startPoint: String,
        checksOut: Bool,
        in repositoryURL: URL
    ) async throws {
        let name = try await validatedBranchName(name, in: repositoryURL)
        let startPoint = try await resolvedCommit(startPoint, in: repositoryURL)
        let arguments = checksOut
            ? ["switch", "-c", name, startPoint]
            : ["branch", name, startPoint]
        _ = try await runner.run(at: repositoryURL, arguments: arguments)
    }

    func renameBranch(from oldName: String, to newName: String, in repositoryURL: URL) async throws {
        let oldName = try await existingBranchName(oldName, in: repositoryURL)
        let newName = try await validatedBranchName(newName, in: repositoryURL)
        _ = try await runner.run(at: repositoryURL, arguments: ["branch", "-m", "--", oldName, newName])
    }

    func deleteBranch(named name: String, force: Bool, in repositoryURL: URL) async throws {
        let name = try await existingBranchName(name, in: repositoryURL)
        let currentResult = try await runner.run(at: repositoryURL, arguments: ["branch", "--show-current"])
        guard currentResult.text.trimmingCharacters(in: .whitespacesAndNewlines) != name else {
            throw GitReferenceServiceError.currentBranchCannotBeDeleted
        }
        _ = try await runner.run(
            at: repositoryURL,
            arguments: ["branch", force ? "-D" : "-d", "--", name]
        )
    }

    func setUpstream(_ upstream: String?, for branch: String, in repositoryURL: URL) async throws {
        let branch = try await existingBranchName(branch, in: repositoryURL)
        if let upstream = upstream?.trimmingCharacters(in: .whitespacesAndNewlines), !upstream.isEmpty {
            guard !upstream.hasPrefix("-") else { throw GitReferenceServiceError.invalidName(upstream) }
            let exists = try await runner.run(
                at: repositoryURL,
                arguments: ["rev-parse", "--verify", "\(upstream)^{commit}"],
                acceptedExitCodes: [0, 128]
            )
            guard exists.exitCode == 0 else { throw GitReferenceServiceError.invalidName(upstream) }
            _ = try await runner.run(
                at: repositoryURL,
                arguments: ["branch", "--set-upstream-to", upstream, branch]
            )
        } else {
            _ = try await runner.run(
                at: repositoryURL,
                arguments: ["branch", "--unset-upstream", branch],
                acceptedExitCodes: [0, 1, 128]
            )
        }
    }

    func mergedBranchCandidates(into base: String, in repositoryURL: URL) async throws -> [String] {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["branch", "--merged", base, "--format=%(refname:short)"]
        )
        let current = try await runner.run(at: repositoryURL, arguments: ["branch", "--show-current"])
            .text.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.text
            .split(whereSeparator: \Character.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != current && $0 != base }
    }

    func createTag(
        named name: String,
        at revision: String,
        message: String?,
        signed: Bool,
        in repositoryURL: URL
    ) async throws {
        let name = try await validatedTagName(name, in: repositoryURL)
        let revision = try await resolvedCommit(revision, in: repositoryURL)
        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        var arguments = ["tag"]
        if signed {
            arguments.append("-s")
        } else if trimmedMessage?.isEmpty == false {
            arguments.append("-a")
        }
        if let trimmedMessage, !trimmedMessage.isEmpty {
            arguments += ["-m", trimmedMessage]
        }
        arguments += [name, revision]
        _ = try await runner.run(at: repositoryURL, arguments: arguments)
    }

    func deleteTag(named name: String, in repositoryURL: URL) async throws {
        let name = try await existingTagName(name, in: repositoryURL)
        _ = try await runner.run(at: repositoryURL, arguments: ["tag", "--delete", "--", name])
    }

    func pushTag(named name: String, to remote: String, in repositoryURL: URL) async throws {
        let name = try await existingTagName(name, in: repositoryURL)
        let remote = try validatedRemoteName(remote)
        _ = try await runner.run(
            at: repositoryURL,
            arguments: ["push", remote, "refs/tags/\(name)"]
        )
    }

    func deleteRemoteTag(named name: String, from remote: String, in repositoryURL: URL) async throws {
        let name = try await existingTagName(name, in: repositoryURL)
        let remote = try validatedRemoteName(remote)
        _ = try await runner.run(
            at: repositoryURL,
            arguments: ["push", remote, ":refs/tags/\(name)"]
        )
    }

    func addRemote(named name: String, fetchURL: String, pushURL: String?, in repositoryURL: URL) async throws {
        let name = try validatedRemoteName(name)
        let fetchURL = try validatedRemoteURL(fetchURL)
        _ = try await runner.run(at: repositoryURL, arguments: ["remote", "add", name, fetchURL])
        if let pushURL, !pushURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                _ = try await runner.run(
                    at: repositoryURL,
                    arguments: ["remote", "set-url", "--push", name, try validatedRemoteURL(pushURL)]
                )
            } catch {
                _ = try? await runner.run(at: repositoryURL, arguments: ["remote", "remove", name])
                throw error
            }
        }
    }

    func updateRemote(
        named name: String,
        newName: String,
        fetchURL: String,
        pushURL: String,
        in repositoryURL: URL
    ) async throws {
        let currentName = try validatedRemoteName(name)
        let nextName = try validatedRemoteName(newName)
        let fetchURL = try validatedRemoteURL(fetchURL)
        let pushURL = try validatedRemoteURL(pushURL)
        var activeName = currentName
        if currentName != nextName {
            _ = try await runner.run(at: repositoryURL, arguments: ["remote", "rename", currentName, nextName])
            activeName = nextName
        }
        do {
            _ = try await runner.run(
                at: repositoryURL,
                arguments: ["remote", "set-url", activeName, fetchURL]
            )
            _ = try await runner.run(
                at: repositoryURL,
                arguments: ["remote", "set-url", "--push", activeName, pushURL]
            )
        } catch {
            if currentName != nextName {
                _ = try? await runner.run(at: repositoryURL, arguments: ["remote", "rename", nextName, currentName])
            }
            throw error
        }
    }

    func deleteRemote(named name: String, in repositoryURL: URL) async throws {
        let name = try validatedRemoteName(name)
        _ = try await runner.run(at: repositoryURL, arguments: ["remote", "remove", name])
    }

    func fetchRemote(named name: String, prunes: Bool, in repositoryURL: URL) async throws {
        let name = try validatedRemoteName(name)
        var arguments = ["fetch", name, "--tags"]
        if prunes { arguments.append("--prune") }
        _ = try await runner.run(at: repositoryURL, arguments: arguments)
    }

    func testRemote(named name: String, in repositoryURL: URL) async throws {
        let name = try validatedRemoteName(name)
        _ = try await runner.run(at: repositoryURL, arguments: ["ls-remote", name, "HEAD"])
    }

    func restoreReflogEntry(
        _ entry: GitReflogRecord,
        as branchName: String,
        in repositoryURL: URL
    ) async throws {
        let name = try await validatedBranchName(branchName, in: repositoryURL)
        let hash = try await resolvedCommit(entry.hash, in: repositoryURL)
        _ = try await runner.run(at: repositoryURL, arguments: ["branch", name, hash])
    }

    func amendHead(message: String, in repositoryURL: URL) async throws {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw GitReferenceServiceError.invalidName(message) }
        _ = try await runner.run(at: repositoryURL, arguments: ["commit", "--amend", "-m", message])
    }

    func rewriteCommit(
        _ hash: String,
        mode: GitCommitRewriteMode,
        newMessage: String?,
        in repositoryURL: URL
    ) async throws -> RepositoryOperationTransition {
        try await requireCleanWorkingTree(in: repositoryURL)
        let hash = try await resolvedCommit(hash, in: repositoryURL)
        if try await isCommitPublishedAnywhere(hash, in: repositoryURL) {
            throw GitReferenceServiceError.publishedCommitCannotBeRewritten
        }

        let parentResult = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "\(hash)^"],
            acceptedExitCodes: [0, 128]
        )
        guard parentResult.exitCode == 0 else { throw GitReferenceServiceError.rootCommitCannotBeRewritten }
        var base = parentResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .squash || mode == .fixup {
            let previousParent = try await runner.run(
                at: repositoryURL,
                arguments: ["rev-parse", "\(base)^"],
                acceptedExitCodes: [0, 128]
            )
            guard previousParent.exitCode == 0 else { throw GitReferenceServiceError.firstCommitCannotBeFolded }
            base = previousParent.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let ancestor = try await runner.run(
            at: repositoryURL,
            arguments: ["merge-base", "--is-ancestor", hash, "HEAD"],
            acceptedExitCodes: [0, 1, 128]
        )
        guard ancestor.exitCode == 0 else { throw GitReferenceServiceError.invalidName(hash) }
        let merges = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-list", "--merges", "\(base)..HEAD"]
        )
        guard merges.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitReferenceServiceError.mergeHistoryCannotBeRewritten
        }

        let commitsResult = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-list", "--reverse", "\(base)..HEAD"]
        )
        let commits = commitsResult.text.split(whereSeparator: \Character.isNewline).map(String.init)
        guard let selectedIndex = commits.firstIndex(of: hash) else {
            throw GitReferenceServiceError.invalidName(hash)
        }
        if (mode == .squash || mode == .fixup), selectedIndex == 0 {
            throw GitReferenceServiceError.firstCommitCannotBeFolded
        }

        let action: String = switch mode {
        case .reword: "reword"
        case .squash: "squash"
        case .fixup: "fixup"
        case .drop: "drop"
        case .split: "edit"
        }
        let todo = commits.map { commit in
            "\(commit == hash ? action : "pick") \(commit)"
        }.joined(separator: "\n") + "\n"
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGatto-Rewrite-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let todoURL = temporaryDirectory.appendingPathComponent("todo")
        let sequenceEditorURL = temporaryDirectory.appendingPathComponent("sequence-editor.sh")
        try todo.write(to: todoURL, atomically: true, encoding: .utf8)
        try "#!/bin/sh\ncp \"$GITGATTO_TODO_FILE\" \"$1\"\n".write(
            to: sequenceEditorURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sequenceEditorURL.path)

        var environment = [
            "GIT_SEQUENCE_EDITOR": sequenceEditorURL.path,
            "GITGATTO_TODO_FILE": todoURL.path,
            "GIT_EDITOR": "/usr/bin/true",
        ]
        if mode == .reword {
            let message = newMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !message.isEmpty else { throw GitReferenceServiceError.invalidName(message) }
            let messageURL = temporaryDirectory.appendingPathComponent("message")
            let messageEditorURL = temporaryDirectory.appendingPathComponent("message-editor.sh")
            try (message + "\n").write(to: messageURL, atomically: true, encoding: .utf8)
            try "#!/bin/sh\ncat \"$GITGATTO_MESSAGE_FILE\" > \"$1\"\n".write(
                to: messageEditorURL,
                atomically: true,
                encoding: .utf8
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: messageEditorURL.path)
            environment["GIT_EDITOR"] = messageEditorURL.path
            environment["GITGATTO_MESSAGE_FILE"] = messageURL.path
        }

        let arguments = ["rebase", "-i", base]
        let result = try await runner.run(
            at: repositoryURL,
            arguments: arguments,
            environment: environment,
            acceptedExitCodes: [0, 1]
        )
        if mode == .split,
           try await repositoryOperationState(in: repositoryURL) != nil
        {
            _ = try await runner.run(at: repositoryURL, arguments: ["reset", "HEAD^"])
        }
        return try await transition(result, arguments: arguments, in: repositoryURL)
    }

    func cherryPick(_ hash: String, in repositoryURL: URL) async throws -> RepositoryOperationTransition {
        let hash = try await resolvedCommit(hash, in: repositoryURL)
        let arguments = ["cherry-pick", hash]
        let result = try await runner.run(at: repositoryURL, arguments: arguments, acceptedExitCodes: [0, 1])
        return try await transition(result, arguments: arguments, in: repositoryURL)
    }

    func revertCommit(_ hash: String, in repositoryURL: URL) async throws -> RepositoryOperationTransition {
        let hash = try await resolvedCommit(hash, in: repositoryURL)
        let arguments = ["revert", "--no-edit", hash]
        let result = try await runner.run(at: repositoryURL, arguments: arguments, acceptedExitCodes: [0, 1])
        return try await transition(result, arguments: arguments, in: repositoryURL)
    }

    func reset(to hash: String, mode: GitResetMode, in repositoryURL: URL) async throws {
        let hash = try await resolvedCommit(hash, in: repositoryURL)
        _ = try await runner.run(at: repositoryURL, arguments: ["reset", "--\(mode.rawValue)", hash])
    }

    func reorderCommits(
        _ orderedHashes: [String],
        in repositoryURL: URL
    ) async throws -> RepositoryOperationTransition {
        try await requireCleanWorkingTree(in: repositoryURL)
        var resolved: [String] = []
        for hash in orderedHashes {
            resolved.append(try await resolvedCommit(hash, in: repositoryURL))
        }
        guard resolved.count >= 2, Set(resolved).count == resolved.count else {
            throw GitReferenceServiceError.invalidName(orderedHashes.joined(separator: ", "))
        }
        for hash in resolved {
            if try await isCommitPublishedAnywhere(hash, in: repositoryURL) {
                throw GitReferenceServiceError.publishedCommitCannotBeRewritten
            }
        }
        let fullHistory = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-list", "--reverse", "HEAD"]
        ).text.split(whereSeparator: \Character.isNewline).map(String.init)
        guard let firstIndex = fullHistory.indices.first(where: { Set(resolved).contains(fullHistory[$0]) }) else {
            throw GitReferenceServiceError.invalidName(orderedHashes.joined(separator: ", "))
        }
        let current = Array(fullHistory[firstIndex...])
        guard current.count == resolved.count, Set(current) == Set(resolved) else {
            throw GitReferenceServiceError.invalidName(orderedHashes.joined(separator: ", "))
        }
        let parent = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "\(current[0])^"],
            acceptedExitCodes: [0, 128]
        )
        guard parent.exitCode == 0 else { throw GitReferenceServiceError.rootCommitCannotBeRewritten }
        let base = parent.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let merges = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-list", "--merges", "\(base)..HEAD"]
        )
        guard merges.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitReferenceServiceError.mergeHistoryCannotBeRewritten
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGatto-Reorder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let todoURL = temporaryDirectory.appendingPathComponent("todo")
        let editorURL = temporaryDirectory.appendingPathComponent("sequence-editor.sh")
        try (resolved.map { "pick \($0)" }.joined(separator: "\n") + "\n")
            .write(to: todoURL, atomically: true, encoding: .utf8)
        try "#!/bin/sh\ncp \"$GITGATTO_TODO_FILE\" \"$1\"\n"
            .write(to: editorURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: editorURL.path)
        let arguments = ["rebase", "-i", base]
        let result = try await runner.run(
            at: repositoryURL,
            arguments: arguments,
            environment: [
                "GIT_SEQUENCE_EDITOR": editorURL.path,
                "GITGATTO_TODO_FILE": todoURL.path,
                "GIT_EDITOR": "/usr/bin/true",
            ],
            acceptedExitCodes: [0, 1]
        )
        return try await transition(result, arguments: arguments, in: repositoryURL)
    }

    nonisolated static func parseReferences(_ text: String) -> [GitReferenceRecord] {
        text.split(whereSeparator: \Character.isNewline).compactMap { row in
            let fields = row.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3, !fields[0].isEmpty, !fields[1].isEmpty else { return nil }
            let fullName = fields[0]
            let name = fields[1]
            guard !fullName.hasSuffix("/HEAD") else { return nil }
            let kind: GitReferenceKind = fullName.hasPrefix("refs/remotes/") ? .remoteBranch : .localBranch
            return GitReferenceRecord(
                name: name,
                revision: name,
                shortHash: String(fields[2].prefix(8)),
                kind: kind
            )
        }
    }

    nonisolated static func parseTags(_ text: String) -> [GitTagRecord] {
        text.split(whereSeparator: \Character.isNewline).compactMap { row in
            let fields = row.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 7, !fields[0].isEmpty else { return nil }
            let isAnnotated = fields[3] == "tag"
            let targetHash = isAnnotated && !fields[2].isEmpty ? fields[2] : fields[1]
            let timestamp = TimeInterval(fields[4]).map(Date.init(timeIntervalSince1970:))
            return GitTagRecord(
                name: fields[0],
                hash: targetHash,
                shortHash: String(targetHash.prefix(8)),
                subject: fields[6],
                creator: fields[5].isEmpty ? nil : fields[5],
                createdAt: timestamp,
                isAnnotated: isAnnotated
            )
        }
    }

    nonisolated static func parseRemotes(_ text: String) -> [GitRemoteRecord] {
        struct URLs { var fetch = ""; var push = "" }
        var values: [String: URLs] = [:]
        for line in text.split(whereSeparator: \Character.isNewline) {
            let parts = line.split(whereSeparator: \Character.isWhitespace)
            guard parts.count >= 3 else { continue }
            let name = String(parts[0])
            let url = String(parts[1])
            let kind = String(parts[2])
            if kind == "(fetch)" { values[name, default: URLs()].fetch = url }
            if kind == "(push)" { values[name, default: URLs()].push = url }
        }
        return values.keys.sorted().compactMap { name in
            guard let urls = values[name] else { return nil }
            return GitRemoteRecord(name: name, fetchURL: urls.fetch, pushURL: urls.push)
        }
    }

    nonisolated static func parseReflog(_ text: String) -> [GitReflogRecord] {
        text.split(whereSeparator: \Character.isNewline).compactMap { row in
            let fields = row.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4, let timestamp = TimeInterval(fields[2]) else { return nil }
            return GitReflogRecord(
                selector: fields[0],
                hash: fields[1],
                shortHash: String(fields[1].prefix(8)),
                createdAt: Date(timeIntervalSince1970: timestamp),
                subject: fields[3]
            )
        }
    }

    private func validatedBranchName(_ value: String, in repositoryURL: URL) async throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw GitReferenceServiceError.invalidName(name) }
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["check-ref-format", "--branch", name],
            acceptedExitCodes: [0, 1, 128]
        )
        guard result.exitCode == 0 else { throw GitReferenceServiceError.invalidName(name) }
        return name
    }

    private func existingBranchName(_ value: String, in repositoryURL: URL) async throws -> String {
        let name = try await validatedBranchName(value, in: repositoryURL)
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["show-ref", "--verify", "--quiet", "refs/heads/\(name)"],
            acceptedExitCodes: [0, 1, 128]
        )
        guard result.exitCode == 0 else { throw GitReferenceServiceError.invalidName(name) }
        return name
    }

    private func validatedTagName(_ value: String, in repositoryURL: URL) async throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw GitReferenceServiceError.invalidName(name) }
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["check-ref-format", "refs/tags/\(name)"],
            acceptedExitCodes: [0, 1, 128]
        )
        guard result.exitCode == 0 else { throw GitReferenceServiceError.invalidName(name) }
        return name
    }

    private func existingTagName(_ value: String, in repositoryURL: URL) async throws -> String {
        let name = try await validatedTagName(value, in: repositoryURL)
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["show-ref", "--verify", "--quiet", "refs/tags/\(name)"],
            acceptedExitCodes: [0, 1, 128]
        )
        guard result.exitCode == 0 else { throw GitReferenceServiceError.invalidName(name) }
        return name
    }

    private func resolvedCommit(_ value: String, in repositoryURL: URL) async throws -> String {
        let revision = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !revision.isEmpty else { throw GitReferenceServiceError.invalidName(revision) }
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "--verify", "\(revision)^{commit}"],
            acceptedExitCodes: [0, 128]
        )
        guard result.exitCode == 0 else { throw GitReferenceServiceError.invalidName(revision) }
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func validatedRemoteName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard !name.isEmpty,
              !name.hasPrefix("-"),
              name.unicodeScalars.allSatisfy(allowed.contains) else {
            throw GitReferenceServiceError.invalidName(name)
        }
        return name
    }

    private nonisolated func validatedRemoteURL(_ value: String) throws -> String {
        let url = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !url.contains(where: \Character.isNewline) else {
            throw GitReferenceServiceError.invalidName(url)
        }
        return url
    }

    private func requireCleanWorkingTree(in repositoryURL: URL) async throws {
        let status = try await runner.run(at: repositoryURL, arguments: ["status", "--porcelain"])
        guard status.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitReferenceServiceError.workingTreeNotClean
        }
    }

    private func isCommitPublishedAnywhere(_ hash: String, in repositoryURL: URL) async throws -> Bool {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["branch", "--remotes", "--contains", hash, "--format=%(refname:short)"]
        )
        return !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func transition(
        _ result: GitCommandResult,
        arguments: [String],
        in repositoryURL: URL
    ) async throws -> RepositoryOperationTransition {
        if let state = try await repositoryOperationState(in: repositoryURL) {
            return .paused(state)
        }
        guard result.exitCode == 0 else {
            let output = [result.text, String(decoding: result.errorOutput, as: UTF8.self)]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw GitCommandError(
                arguments: arguments,
                exitCode: result.exitCode,
                message: output.isEmpty ? "git exited with status \(result.exitCode)" : output
            )
        }
        return .completed
    }
}
