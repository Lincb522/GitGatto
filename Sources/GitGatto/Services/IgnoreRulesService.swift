import Foundation

struct IgnoreInspection: Sendable {
    var path: String
    var tracked: Bool
    var source: String
    var line: String
    var pattern: String
    var ignored: Bool
}

struct IgnoreRuleDraft: Sendable {
    var file: URL
    var original: Data
    var text: String
}

actor IgnoreRulesService {
    func inspect(_ path: String, repository: URL) async throws -> IgnoreInspection {
        let path = try ProjectToolsPolicy.relativePath(path)
        let tracked = try await ProjectToolsPolicy.git(repository, ["ls-files", "--error-unmatch", "--", ":(literal)" + path], codes: [0, 1])
        let result = try await ProjectToolsPolicy.git(repository, ["check-ignore", "-v", "-z", "--no-index", "--stdin"], input: Data((path + "\0").utf8), codes: [0, 1])
        let parts = result.outputText.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        return IgnoreInspection(path: path, tracked: tracked.exitCode == 0, source: parts.count >= 4 ? parts[0] : "",
            line: parts.count >= 4 ? parts[1] : "", pattern: parts.count >= 4 ? parts[2] : "",
            ignored: parts.count >= 4 && !parts[2].hasPrefix("!"))
    }

    func load(repository: URL, localOnly: Bool) async throws -> IgnoreRuleDraft {
        let file: URL
        if localOnly {
            let path = try await ProjectToolsPolicy.text(repository, ["rev-parse", "--git-path", "info/exclude"])
            file = path.hasPrefix("/") ? URL(fileURLWithPath: path) : repository.appendingPathComponent(path)
        } else { file = repository.appendingPathComponent(".gitignore") }
        if FileManager.default.fileExists(atPath: file.path) {
            guard try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw ProjectToolsError(key: "path") }
        }
        let data = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : Data()
        guard data.count < 1_000_000, let text = String(data: data, encoding: .utf8) else { throw ProjectToolsError(key: "preview") }
        return IgnoreRuleDraft(file: file, original: data, text: text)
    }

    func preview(_ draft: IgnoreRuleDraft, repository: URL) async throws -> [String] {
        // Evaluate the proposed rules in an isolated repository, never by temporarily replacing live rules.
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        _ = try await ProjectToolsPolicy.git(temporary, ["init", "-q"])
        let files = try await ProjectToolsPolicy.git(repository, ["ls-files", "-z", "--cached", "--others", "--exclude-standard"])
        let ignored = try await ProjectToolsPolicy.git(repository, ["ls-files", "-z", "--others", "--ignored", "--exclude-standard"])
        let paths = Array(Set((files.outputText + ignored.outputText).split(separator: "\0").map(String.init))).sorted()
        guard paths.count <= 100_000 else { throw ProjectToolsError(key: "previewLimit") }
        let global = try await ProjectToolsPolicy.git(repository, ["config", "--path", "--get", "core.excludesFile"], codes: [0, 1])
        if global.exitCode == 0 {
            let path = global.outputText.trimmingCharacters(in: .newlines)
            let resolved = path.hasPrefix("/") ? path : repository.appendingPathComponent(path).path
            _ = try await ProjectToolsPolicy.git(temporary, ["config", "core.excludesFile", resolved])
        }
        // Copy only rule files, preserving nested precedence. No source or credential contents are read.
        let ruleFiles = try await ProjectToolsPolicy.git(repository, ["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", ".gitignore", "**/.gitignore"])
        for path in ruleFiles.outputText.split(separator: "\0").map(String.init) {
            let source = repository.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            guard source.resolvingSymlinksInPath().path.hasPrefix(repository.resolvingSymlinksInPath().path + "/") else { continue }
            let target = temporary.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: source).write(to: target)
        }
        let local = try await load(repository: repository, localOnly: true)
        try local.original.write(to: temporary.appendingPathComponent(".git/info/exclude"))
        let target = draft.file.lastPathComponent == ".gitignore" ? temporary.appendingPathComponent(".gitignore") : temporary.appendingPathComponent(".git/info/exclude")
        try Data(draft.text.utf8).write(to: target)
        guard !paths.isEmpty else { return [] }
        let input = Data((paths.joined(separator: "\0") + "\0").utf8)
        let before = try await ProjectToolsPolicy.git(repository, ["check-ignore", "--no-index", "-z", "--stdin"], input: input, codes: [0, 1])
        let after = try await ProjectToolsPolicy.git(temporary, ["check-ignore", "--no-index", "-z", "--stdin"], input: input, codes: [0, 1])
        let old = Set(before.outputText.split(separator: "\0").map(String.init)), new = Set(after.outputText.split(separator: "\0").map(String.init))
        return old.symmetricDifference(new).sorted().map { (new.contains($0) ? "+ " : "− ") + $0 }
    }

    func save(_ draft: IgnoreRuleDraft) throws {
        let current = FileManager.default.fileExists(atPath: draft.file.path) ? try Data(contentsOf: draft.file) : Data()
        guard current == draft.original else { throw ProjectToolsError(key: "changed") }
        try FileManager.default.createDirectory(at: draft.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(draft.text.utf8).write(to: draft.file, options: .atomic)
    }

    func stopTracking(_ path: String, repository: URL) async throws {
        let path = try ProjectToolsPolicy.relativePath(path)
        _ = try await ProjectToolsPolicy.git(repository, ["rm", "-r", "--cached", "--", ":(literal)" + path])
    }
}
