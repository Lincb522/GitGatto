import Foundation

protocol GitFileHistoryServing: Sendable {
    func trackedFiles(in repositoryURL: URL) async throws -> [RepositoryFileRecord]
    func history(for path: String, in repositoryURL: URL) async throws -> [FileRevisionRecord]
    func document(
        for path: String,
        revision: FileRevisionRecord?,
        in repositoryURL: URL
    ) async throws -> FileVersionDocument
    func blame(
        for path: String,
        revision: FileRevisionRecord?,
        in repositoryURL: URL
    ) async throws -> [FileBlameLine]
    func restore(
        path: String,
        from revision: FileRevisionRecord,
        in repositoryURL: URL
    ) async throws
}

actor GitFileHistoryService: GitFileHistoryServing {
    private let runner: GitCommandRunner

    init(runner: GitCommandRunner = GitCommandRunner()) {
        self.runner = runner
    }

    func trackedFiles(in repositoryURL: URL) async throws -> [RepositoryFileRecord] {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["ls-files", "-z"]
        )
        return result.output
            .split(separator: 0)
            .map { RepositoryFileRecord(path: String(decoding: $0, as: UTF8.self)) }
            .filter { !$0.path.isEmpty }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func history(for path: String, in repositoryURL: URL) async throws -> [FileRevisionRecord] {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: [
                "log", "--follow", "-n", "250", "--date=iso-strict",
                "--pretty=format:%x1e%H%x1f%h%x1f%an%x1f%ae%x1f%ad%x1f%s",
                "--name-status", "-z", "--", path
            ]
        )
        return Self.parseHistory(result.output)
    }

    func document(
        for path: String,
        revision: FileRevisionRecord?,
        in repositoryURL: URL
    ) async throws -> FileVersionDocument {
        let data: Data
        let displayPath: String
        let diffResult: GitCommandResult
        let previewURL: URL?

        if let revision {
            displayPath = revision.path
            let content = try await runner.run(
                at: repositoryURL,
                arguments: ["show", "\(revision.hash):\(revision.path)"]
            )
            data = content.output
            if RepositoryMediaKind(fileName: displayPath) != nil {
                previewURL = try RepositoryMediaCache.store(
                    data,
                    key: "file-history:\(revision.hash):\(displayPath)",
                    path: displayPath
                )
            } else {
                previewURL = nil
            }
            diffResult = try await runner.run(
                at: repositoryURL,
                arguments: [
                    "show", "--format=", "--no-color", "--no-ext-diff", "--unified=4",
                    revision.hash, "--", revision.path
                ]
            )
        } else {
            displayPath = path
            let fileURL = try validatedFileURL(path: path, in: repositoryURL)
            data = try Data(contentsOf: fileURL)
            previewURL = RepositoryMediaKind(fileName: displayPath) == nil ? nil : fileURL
            diffResult = try await runner.run(
                at: repositoryURL,
                arguments: ["diff", "HEAD", "--no-color", "--no-ext-diff", "--unified=4", "--", path],
                acceptedExitCodes: [0, 1]
            )
        }

        let content = Self.textContent(data)
        return FileVersionDocument(
            path: displayPath,
            content: content,
            isBinary: content == nil,
            previewURL: previewURL,
            diff: GitParsers.diff(from: diffResult.text, path: displayPath)
        )
    }

    func blame(
        for path: String,
        revision: FileRevisionRecord?,
        in repositoryURL: URL
    ) async throws -> [FileBlameLine] {
        var arguments = ["blame", "--line-porcelain", "--date=iso-strict"]
        if let revision {
            arguments.append(revision.hash)
        }
        arguments += ["--", revision?.path ?? path]
        let result = try await runner.run(at: repositoryURL, arguments: arguments)
        return Self.parseBlame(result.text)
    }

    func restore(
        path: String,
        from revision: FileRevisionRecord,
        in repositoryURL: URL
    ) async throws {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["show", "\(revision.hash):\(revision.path)"]
        )
        let destination = try validatedFileURL(path: path, in: repositoryURL)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try result.output.write(to: destination, options: .atomic)
    }

    static func parseHistory(_ data: Data) -> [FileRevisionRecord] {
        data.split(separator: 0x1E).compactMap { rawRecord in
            guard let newline = rawRecord.firstIndex(of: 0x0A) else { return nil }
            let metadata = String(decoding: rawRecord[..<newline], as: UTF8.self)
            let fields = metadata.split(separator: "\u{1f}", omittingEmptySubsequences: false)
            guard fields.count == 6,
                  let date = ISO8601DateFormatter().date(from: String(fields[4])) else { return nil }

            let statusData = rawRecord[rawRecord.index(after: newline)...]
            let statusFields = statusData.split(separator: 0).map {
                String(decoding: $0, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            guard let status = statusFields.first else { return nil }
            let historicalPath: String?
            if status.hasPrefix("R") || status.hasPrefix("C") {
                historicalPath = statusFields.count >= 3 ? statusFields[2] : nil
            } else {
                historicalPath = statusFields.count >= 2 ? statusFields[1] : nil
            }
            guard let historicalPath, !historicalPath.isEmpty else { return nil }

            return FileRevisionRecord(
                hash: String(fields[0]),
                shortHash: String(fields[1]),
                author: String(fields[2]),
                authorEmail: String(fields[3]),
                date: date,
                subject: String(fields[5]),
                path: historicalPath
            )
        }
    }

    static func parseBlame(_ value: String) -> [FileBlameLine] {
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [FileBlameLine] = []
        var index = 0

        while index < lines.count {
            let header = lines[index].split(separator: " ")
            guard header.count >= 3,
                  header[0].count == 40,
                  let originalLine = Int(header[1]),
                  let finalLine = Int(header[2]) else {
                index += 1
                continue
            }

            let hash = String(header[0])
            var author = ""
            var email = ""
            var date: Date?
            var summary = ""
            var sourcePath = ""
            var text: String?
            index += 1

            while index < lines.count {
                let line = lines[index]
                if line.hasPrefix("\t") {
                    text = String(line.dropFirst())
                    index += 1
                    break
                }
                if line.hasPrefix("author ") {
                    author = String(line.dropFirst("author ".count))
                } else if line.hasPrefix("author-mail ") {
                    email = String(line.dropFirst("author-mail ".count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                } else if line.hasPrefix("author-time "),
                          let timestamp = TimeInterval(line.dropFirst("author-time ".count)) {
                    date = Date(timeIntervalSince1970: timestamp)
                } else if line.hasPrefix("summary ") {
                    summary = String(line.dropFirst("summary ".count))
                } else if line.hasPrefix("filename ") {
                    sourcePath = String(line.dropFirst("filename ".count))
                }
                index += 1
            }

            guard let text else { continue }
            result.append(
                FileBlameLine(
                    commitHash: hash,
                    originalLineNumber: originalLine,
                    finalLineNumber: finalLine,
                    author: author,
                    authorEmail: email,
                    date: date,
                    summary: summary,
                    sourcePath: sourcePath,
                    text: text
                )
            )
        }
        return result
    }

    private func validatedFileURL(path: String, in repositoryURL: URL) throws -> URL {
        let root = repositoryURL.standardizedFileURL
        let candidate = root.appendingPathComponent(path).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else {
            throw GitCommandError(
                arguments: ["show", "--", path],
                exitCode: 128,
                message: "File path is outside the repository."
            )
        }
        return candidate
    }

    private static func textContent(_ data: Data) -> String? {
        guard !data.contains(0) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
