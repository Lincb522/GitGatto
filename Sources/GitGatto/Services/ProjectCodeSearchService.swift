import Foundation

struct ProjectCodeSearchService: Sendable {
    func search(_ query: ProjectCodeQuery, repositories: [URL], limit: Int = 500) async throws -> ProjectSearchResult {
        guard !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return ProjectSearchResult() }
        guard !query.text.contains("\n"), !query.text.contains("\0"), query.text.utf8.count <= 1024 else { throw ProjectToolsError(key: "query") }
        let directory = query.directory.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !directory.isEmpty { _ = try ProjectToolsPolicy.relativePath(directory) }
        let ext = query.fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard !ext.contains(where: { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "-" }), limit > 0 else { throw ProjectToolsError(key: "query") }
        let languageExtensions = ProjectCodeQuery.languageExtensions[query.language]
        guard query.language.isEmpty || languageExtensions != nil else { throw ProjectToolsError(key: "query") }
        if let languageExtensions, !ext.isEmpty, !languageExtensions.contains(ext.lowercased()) { return ProjectSearchResult() }
        let extensions = ext.isEmpty ? languageExtensions : [ext.lowercased()]
        var result = ProjectSearchResult()
        for repository in repositories {
            try Task.checkCancellation()
            do {
                let revision: String?
                if query.scope == .revision {
                    revision = try await ProjectToolsPolicy.text(repository, ["rev-parse", "--verify", "--end-of-options", query.revision + "^{commit}"])
                } else { revision = nil }
                let list = try await ProjectToolsPolicy.git(repository, revision.map { ["ls-tree", "-r", "--name-only", "-z", $0] } ?? ["ls-files", "-z", "--cached", "--others", "--exclude-standard"])
                let files = Array(Set(list.outputText.split(separator: "\0").map(String.init))).sorted().filter {
                    ProjectToolsPolicy.allowsContent($0) && (directory.isEmpty || $0.hasPrefix(directory + "/")) && (extensions == nil || extensions?.contains(($0 as NSString).pathExtension.lowercased()) == true)
                }
                if query.scope == .history {
                    let include = extensions.map { values in values.map { ":(top,glob,icase)" + (directory.isEmpty ? "" : directory + "/") + "**/*." + $0 } } ?? [directory.isEmpty ? ":(top,glob)**" : ":(top,literal)" + directory]
                    guard !directory.contains(where: { "*?[]\\".contains($0) }) else { throw ProjectToolsError(key: "path") }
                    let excluded = [".env*", "credentials", "auth.json", "*.pem", "*.key", "id_rsa*", "id_ed25519*"]
                        .flatMap { [":(top,glob,icase,exclude)**/" + $0, ":(top,glob,icase,exclude)**/" + $0 + "/**"] }
                    let paths = include + excluded
                    let log = try await ProjectToolsPolicy.git(repository, ["log", "--no-ext-diff", "--no-textconv", "--all", "-n", "100", "--format=%H%x00%s%x00", "-S" + query.text, "--"] + paths)
                    let fields = log.outputText.split(separator: "\0", omittingEmptySubsequences: false)
                    for i in stride(from: 0, to: fields.count - 1, by: 2) {
                        let sha = fields[i].trimmingCharacters(in: .whitespacesAndNewlines)
                        if sha.count >= 40 { result.matches.append(ProjectCodeMatch(repository: repository, path: "", line: nil, text: String(fields[i + 1]), revision: sha)) }
                    }
                    if fields.count >= 200 { result.limited = true }
                } else if query.filenamesOnly {
                    result.matches += files.filter { $0.localizedStandardContains(query.text) }.prefix(max(0, limit - result.matches.count)).map {
                        ProjectCodeMatch(repository: repository, path: $0, line: nil, text: $0, revision: revision)
                    }
                } else {
                    for offset in stride(from: 0, to: files.count, by: 32) {
                        try Task.checkCancellation()
                        let paths = files[offset..<min(files.count, offset + 32)].map { ":(literal)" + $0 }
                        var args = ["grep", "-n", "-z", "-I", "-F", "-m", "20", "-e", query.text]
                        if let revision { args.append(revision) } else { args += ["--untracked", "--exclude-standard"] }
                        let output = try await ProjectToolsPolicy.git(repository, args + ["--"] + paths, codes: [0, 1])
                        let matches = Self.parse(output.outputText, repository: repository, revision: revision)
                        if Dictionary(grouping: matches, by: \.path).values.contains(where: { $0.count >= 20 }) { result.limited = true }
                        result.matches += matches
                        if result.matches.count >= limit { result.limited = true; break }
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { result.failures.append(repository.lastPathComponent + ": " + ProjectCommandOutput.redact(error.localizedDescription)) }
            if result.matches.count >= limit { result.limited = true; break }
        }
        result.matches = Array(result.matches.prefix(limit))
        return result
    }

    static func parse(_ text: String, repository: URL, revision: String?) -> [ProjectCodeMatch] {
        var rest = text[...]; var values: [ProjectCodeMatch] = []
        while let first = rest.firstIndex(of: "\0") {
            var path = String(rest[..<first]); rest = rest[rest.index(after: first)...]
            guard let second = rest.firstIndex(of: "\0"), let line = Int(rest[..<second]) else { break }
            rest = rest[rest.index(after: second)...]
            let end = rest.firstIndex(of: "\n") ?? rest.endIndex
            let content = String(rest[..<end].prefix(2000))
            rest = end == rest.endIndex ? rest[end...] : rest[rest.index(after: end)...]
            if let revision, path.hasPrefix(revision + ":") { path.removeFirst(revision.count + 1) }
            values.append(ProjectCodeMatch(repository: repository, path: path, line: line, text: ProjectCommandOutput.redact(content), revision: revision))
        }
        return values
    }

    func preview(_ match: ProjectCodeMatch) async throws -> String {
        if let revision = match.revision {
            guard (40...64).contains(revision.count), revision.allSatisfy(\.isHexDigit) else { throw ProjectToolsError(key: "query") }
        }
        if match.path.isEmpty, let revision = match.revision {
            let metadata = try await ProjectToolsPolicy.git(match.repository, ["show", "--format=fuller", "--stat", revision])
            let changed = try await ProjectToolsPolicy.git(match.repository, ["diff-tree", "--root", "--no-commit-id", "--name-only", "-r", "-z", revision])
            let candidates = changed.outputText.split(separator: "\0").map(String.init).filter { ProjectToolsPolicy.allowsContent($0) && !$0.contains("\n") }.prefix(40)
            guard !candidates.isEmpty else { return String(metadata.outputText.prefix(80_000)) }
            let objects = candidates.flatMap { [revision + ":" + $0, revision + "^:" + $0] }
            let sizes = try await ProjectToolsPolicy.git(match.repository, ["cat-file", "--batch-check=%(objectsize)"], input: Data((objects.joined(separator: "\n") + "\n").utf8))
            let bytes = sizes.outputText.split(separator: "\n").map { Int($0) ?? 0 }
            var budget = 2_000_000; var paths: [String] = []
            for (index, path) in candidates.enumerated() where bytes.count > index * 2 + 1 {
                let size = bytes[index * 2] + bytes[index * 2 + 1]
                if size <= budget { budget -= size; paths.append(":(literal)" + path) }
            }
            guard !paths.isEmpty else { return String(metadata.outputText.prefix(80_000)) }
            let patch = try await ProjectToolsPolicy.git(match.repository, ["show", "--format=", "--no-ext-diff", "--no-textconv", "--unified=3", revision, "--"] + paths)
            return ProjectCommandOutput.redact(String((metadata.outputText + "\n" + patch.outputText).prefix(80_000)))
        }
        let path = try ProjectToolsPolicy.relativePath(match.path)
        guard ProjectToolsPolicy.allowsContent(path) else { throw ProjectToolsError(key: "path") }
        let text: String
        if let revision = match.revision {
            let size = try await ProjectToolsPolicy.text(match.repository, ["cat-file", "-s", revision + ":" + path])
            guard let bytes = Int(size), bytes <= 2_000_000 else { throw ProjectToolsError(key: "preview") }
            text = try await ProjectToolsPolicy.git(match.repository, ["show", revision + ":" + path]).outputText
        } else {
            let file = match.repository.appendingPathComponent(path).resolvingSymlinksInPath()
            guard file.path.hasPrefix(match.repository.resolvingSymlinksInPath().path + "/"),
                  (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_000_000 else { throw ProjectToolsError(key: "preview") }
            text = try String(contentsOf: file, encoding: .utf8)
        }
        let lines = text.components(separatedBy: "\n"); let start = max(0, (match.line ?? 1) - 12)
        let excerpt = lines.enumerated().dropFirst(start).prefix(100).map { "\($0.offset + 1)  \($0.element.prefix(2000))" }.joined(separator: "\n")
        let truncated = excerpt.count > 80_000 || lines.dropFirst(start).prefix(100).contains { $0.count > 2000 }
        return String(excerpt.prefix(80_000)) + (truncated ? "\n" + L10n.text("tools.output.omitted") : "")
    }
}
