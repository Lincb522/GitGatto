import Foundation

protocol GitHubReadmeTranslationStoring: Sendable {
    func load(
        repositoryName: String,
        source: GitHubReadmeDocument,
        target: CodexTranslationTarget
    ) async throws -> GitHubReadmeDocument?
    func save(
        _ document: GitHubReadmeDocument,
        repositoryName: String,
        source: GitHubReadmeDocument,
        target: CodexTranslationTarget
    ) async throws
}

actor GitHubReadmeTranslationStore: GitHubReadmeTranslationStoring {
    private let directoryURL: URL

    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("GitGatto", isDirectory: true)
            .appendingPathComponent("README Translations", isDirectory: true)
    }

    func load(
        repositoryName: String,
        source: GitHubReadmeDocument,
        target: CodexTranslationTarget
    ) async throws -> GitHubReadmeDocument? {
        let fileURL = fileURL(
            repositoryName: repositoryName,
            source: source,
            target: target
        )
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let html = try String(contentsOf: fileURL, encoding: .utf8)
        return source.replacingHTML(with: html)
    }

    func save(
        _ document: GitHubReadmeDocument,
        repositoryName: String,
        source: GitHubReadmeDocument,
        target: CodexTranslationTarget
    ) async throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try document.html.write(
            to: fileURL(repositoryName: repositoryName, source: source, target: target),
            atomically: true,
            encoding: .utf8
        )
    }

    private func fileURL(
        repositoryName: String,
        source: GitHubReadmeDocument,
        target: CodexTranslationTarget
    ) -> URL {
        let key = StableHash.hex(
            "\(repositoryName)\u{0}\(source.path)\u{0}\(target.rawValue)\u{0}\(source.html)"
        )
        return directoryURL.appendingPathComponent("\(key).html")
    }
}
