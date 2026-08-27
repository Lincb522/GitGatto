import Foundation

struct RepositoryDiscoveryService: Sendable {
    private static let skippedDirectoryNames: Set<String> = [
        ".build", ".cache", ".cargo", ".codex", ".gradle", ".m2", ".npm", ".nuget",
        ".rustup", ".spotlight-v100", ".temporaryitems", ".trash", ".trashes",
        ".tmp", "applications", "archives", "backups.backupdb", "build", "checkouts",
        "deriveddata", "dist", "externalsources", "library", "node_modules", "outputs",
        "pods", "references", "sourcepackages", "system", "target", "vendor"
    ]

    static func defaultRoots(fileManager: FileManager = .default) -> [URL] {
        var roots = [fileManager.homeDirectoryForCurrentUser]
        let volumesURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        let mountedVolumes = (try? fileManager.contentsOfDirectory(
            at: volumesURL,
            includingPropertiesForKeys: [.isDirectoryKey, .volumeIsBrowsableKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for volume in mountedVolumes {
            let values = try? volume.resourceValues(forKeys: [.isDirectoryKey, .volumeIsBrowsableKey])
            guard values?.isDirectory == true, values?.volumeIsBrowsable != false else { continue }
            roots.append(volume)
        }

        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    func repositories(in roots: [URL]) -> AsyncStream<[LocalRepositoryRecord]> {
        AsyncStream { continuation in
            let worker = Task.detached(priority: .utility) {
                let fileManager = FileManager.default
                let keys: [URLResourceKey] = [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .isPackageKey
                ]
                var emitted = Set<String>()

                for root in roots {
                    guard !Task.isCancelled,
                          fileManager.fileExists(atPath: root.path) else { continue }

                    if let record = Self.record(for: root, fileManager: fileManager) {
                        if emitted.insert(record.id).inserted {
                            continuation.yield([record])
                        }
                        continue
                    }

                    guard let enumerator = fileManager.enumerator(
                        at: root,
                        includingPropertiesForKeys: keys,
                        options: [.skipsPackageDescendants],
                        errorHandler: { _, _ in true }
                    ) else { continue }

                    while let item = enumerator.nextObject() as? URL {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        let values = try? item.resourceValues(forKeys: Set(keys))
                        let isDirectory = values?.isDirectory == true
                        if isDirectory {
                            if Self.shouldSkipDirectory(
                                item,
                                isSymbolicLink: values?.isSymbolicLink == true
                            ) {
                                enumerator.skipDescendants()
                                continue
                            }
                            if let record = Self.record(for: item, fileManager: fileManager) {
                                enumerator.skipDescendants()
                                if emitted.insert(record.id).inserted {
                                    continuation.yield([record])
                                }
                            }
                        }
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    func record(for repositoryURL: URL) -> LocalRepositoryRecord? {
        Self.record(for: repositoryURL, fileManager: .default)
    }

    func catalogRecords(for repositoryURLs: [URL]) -> [LocalRepositoryRecord] {
        Self.catalogRecords(for: repositoryURLs, fileManager: .default)
    }

    func records(for repositoryURLs: [URL]) async -> [LocalRepositoryRecord] {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            return Self.catalogRecords(for: repositoryURLs, fileManager: fileManager)
        }.value
    }

    private static func catalogRecords(
        for repositoryURLs: [URL],
        fileManager: FileManager
    ) -> [LocalRepositoryRecord] {
        let candidates = repositoryURLs
            .compactMap { record(for: $0, fileManager: fileManager) }
            .sorted {
                let lhsDepth = $0.url.pathComponents.count
                let rhsDepth = $1.url.pathComponents.count
                if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }
                return $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
        var accepted: [LocalRepositoryRecord] = []
        for candidate in candidates {
            let nested = accepted.contains { parent in
                candidate.id.hasPrefix(parent.id + "/")
            }
            if !nested { accepted.append(candidate) }
        }
        return accepted
    }

    private static func record(
        for repositoryURL: URL,
        fileManager: FileManager
    ) -> LocalRepositoryRecord? {
        let repository = repositoryURL.standardizedFileURL
        guard isEligibleRepositoryPath(repository),
              let gitDirectory = gitDirectory(for: repository, fileManager: fileManager),
              hasDirectoryAccess(repository, fileManager: fileManager),
              hasDirectoryAccess(gitDirectory, fileManager: fileManager) else { return nil }

        let headURL = gitDirectory.appendingPathComponent("HEAD")
        guard fileManager.isReadableFile(atPath: headURL.path) else { return nil }

        let repositoryDate = modificationDate(of: repository) ?? .distantPast
        let contentDates = ((try? fileManager.contentsOfDirectory(
            at: repository,
            includingPropertiesForKeys: [.contentModificationDateKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter {
                $0.lastPathComponent != ".git"
                    && !shouldSkipDirectoryName($0.lastPathComponent)
            }
            .compactMap(modificationDate)
        let lastModifiedAt = ([repositoryDate] + contentDates).max() ?? repositoryDate

        let activityCandidates = [
            gitDirectory.appendingPathComponent("logs/HEAD"),
            gitDirectory.appendingPathComponent("index"),
            headURL
        ].compactMap(modificationDate)
        let lastActivityAt = activityCandidates.max() ?? lastModifiedAt

        return LocalRepositoryRecord(
            url: repository,
            lastActivityAt: lastActivityAt,
            lastModifiedAt: lastModifiedAt
        )
    }

    private static func gitDirectory(for repository: URL, fileManager: FileManager) -> URL? {
        let marker = repository.appendingPathComponent(".git")
        guard let values = try? marker.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]), values.isSymbolicLink != true else { return nil }

        if values.isDirectory == true {
            return marker.standardizedFileURL
        }
        guard values.isRegularFile == true,
              fileManager.isReadableFile(atPath: marker.path),
              let contents = try? String(contentsOf: marker, encoding: .utf8),
              let firstLine = contents.split(whereSeparator: \.isNewline).first else { return nil }
        let prefix = "gitdir:"
        guard firstLine.lowercased().hasPrefix(prefix) else { return nil }
        let path = firstLine.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, relativeTo: repository)
            .standardizedFileURL
    }

    private static func hasDirectoryAccess(_ url: URL, fileManager: FileManager) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true else { return false }
        return fileManager.isReadableFile(atPath: url.path)
            && fileManager.isWritableFile(atPath: url.path)
            && fileManager.isExecutableFile(atPath: url.path)
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private static func shouldSkipDirectory(_ url: URL, isSymbolicLink: Bool) -> Bool {
        isSymbolicLink || shouldSkipDirectoryName(url.lastPathComponent)
    }

    private static func shouldSkipDirectoryName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized != ".git" && normalized.hasPrefix(".")
            || normalized.hasPrefix(".build-")
            || normalized.hasSuffix("deriveddata")
            || skippedDirectoryNames.contains(normalized)
    }

    private static func isEligibleRepositoryPath(_ url: URL) -> Bool {
        !url.pathComponents.dropFirst().contains(where: shouldSkipDirectoryName)
    }
}
