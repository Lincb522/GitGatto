import Foundation

protocol ProjectGoalReleaseServing: Sendable {
    func state(goal: ProjectGoal, remote: RepositoryRemoteIdentity?) async throws -> ProjectGoalReleaseState
    func publish(goal: ProjectGoal, remote: RepositoryRemoteIdentity) async throws
    func install(goal: ProjectGoal, remote: RepositoryRemoteIdentity) async throws -> URL
}

actor UnavailableProjectGoalReleaseService: ProjectGoalReleaseServing {
    func state(goal: ProjectGoal, remote: RepositoryRemoteIdentity?) async throws -> ProjectGoalReleaseState {
        ProjectGoalReleaseState(
            local: ProjectGoalReleaseLocalState(
                readmePath: nil,
                translationPaths: [],
                versionEvidence: [],
                buildEvidence: [],
                changelogPath: nil,
                releasePipelinePath: nil,
                installedApplication: nil
            ),
            tag: .absent,
            remote: .unavailable
        )
    }

    func publish(goal: ProjectGoal, remote: RepositoryRemoteIdentity) async throws {
        throw ProjectGoalRuntimeError.githubRemoteRequired
    }

    func install(goal: ProjectGoal, remote: RepositoryRemoteIdentity) async throws -> URL {
        throw ProjectGoalRuntimeError.releaseAssetRequired
    }
}

actor ProjectGoalReleaseService: ProjectGoalReleaseServing {
    private let githubService: any GitHubServing
    private let runner: GitCommandRunner
    private let fileManager: FileManager

    init(
        githubService: any GitHubServing,
        runner: GitCommandRunner = GitCommandRunner(),
        fileManager: FileManager = .default
    ) {
        self.githubService = githubService
        self.runner = runner
        self.fileManager = fileManager
    }

    func state(goal: ProjectGoal, remote: RepositoryRemoteIdentity?) async throws -> ProjectGoalReleaseState {
        let repositoryURL = URL(fileURLWithPath: goal.repositoryPath, isDirectory: true)
        let local = ProjectReleaseInspector.inspect(goal: goal, fileManager: fileManager)
        let tag = try await tagState(goal: goal, remote: remote, repositoryURL: repositoryURL)

        guard let remote, remote.isGitHub else {
            return ProjectGoalReleaseState(local: local, tag: tag, remote: .unavailable)
        }
        let remoteState = try await remoteState(goal: goal, remote: remote, tagState: tag)
        return ProjectGoalReleaseState(local: local, tag: tag, remote: remoteState)
    }

    func publish(goal: ProjectGoal, remote: RepositoryRemoteIdentity) async throws {
        guard remote.isGitHub else { throw ProjectGoalRuntimeError.githubRemoteRequired }
        guard let tag = goal.releaseTag,
              let target = goal.targetHeadSHA,
              !tag.isEmpty,
              !target.isEmpty else {
            throw ProjectGoalRuntimeError.releaseMetadataRequired
        }
        let repositoryURL = URL(fileURLWithPath: goal.repositoryPath, isDirectory: true)
        let local = try await localTagCommit(tag, repositoryURL: repositoryURL)
        if let local, local != target {
            throw ProjectGoalRuntimeError.releaseTagMismatch
        }
        if local == nil {
            let title = goal.releaseVersion.map { "\(goal.repositoryName) \($0)" } ?? tag
            _ = try await runner.run(
                at: repositoryURL,
                arguments: ["tag", "-a", tag, target, "-m", title]
            )
        }
        _ = try await runner.run(
            at: repositoryURL,
            arguments: ["push", remote.remoteName, "refs/tags/\(tag)"]
        )
    }

    func install(goal: ProjectGoal, remote: RepositoryRemoteIdentity) async throws -> URL {
        guard remote.isGitHub,
              let tag = goal.releaseTag else {
            throw ProjectGoalRuntimeError.githubRemoteRequired
        }
        let repository = Self.repository(remote: remote, defaultBranch: goal.branchName)
        guard let release = try await githubService.releases(for: repository).first(where: {
            $0.tagName.caseInsensitiveCompare(tag) == .orderedSame
        }),
        let diskImage = release.assets.first(where: {
            $0.name.lowercased().hasSuffix(".dmg")
        }) else {
            throw ProjectGoalRuntimeError.releaseAssetRequired
        }

        let temporary = fileManager.temporaryDirectory
            .appendingPathComponent("GitGatto-Release-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporary) }
        let archive = try await githubService.downloadReleaseAsset(
            diskImage,
            tag: release.tagName,
            in: repository,
            to: temporary
        )
        let destinationDirectory: URL
        if let installedPath = goal.installedApplicationPath {
            destinationDirectory = URL(fileURLWithPath: installedPath).deletingLastPathComponent()
        } else {
            destinationDirectory = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        }
        let installer = MacApplicationInstaller(
            applicationsDirectory: destinationDirectory
        )
        return try await installer.install(archive, replacingExisting: true)
    }

    private func tagState(
        goal: ProjectGoal,
        remote: RepositoryRemoteIdentity?,
        repositoryURL: URL
    ) async throws -> ProjectGoalReleaseTagState {
        guard let tag = goal.releaseTag,
              let target = goal.targetHeadSHA else { return .absent }
        if let local = try await localTagCommit(tag, repositoryURL: repositoryURL), local != target {
            return .mismatched(local)
        }
        guard let remote else {
            return try await localTagCommit(tag, repositoryURL: repositoryURL) == nil ? .absent : .localOnly
        }
        let result = try await runner.run(
            at: repositoryURL,
            arguments: [
                "ls-remote", "--tags", remote.remoteName,
                "refs/tags/\(tag)", "refs/tags/\(tag)^{}"
            ]
        )
        let records = result.text.split(whereSeparator: \Character.isNewline).compactMap { line -> (String, String)? in
            let fields = line.split(whereSeparator: \Character.isWhitespace)
            guard fields.count >= 2 else { return nil }
            return (String(fields[0]), String(fields[1]))
        }
        guard !records.isEmpty else {
            return try await localTagCommit(tag, repositoryURL: repositoryURL) == nil ? .absent : .localOnly
        }
        let resolved = records.first(where: { $0.1.hasSuffix("^{}") })?.0 ?? records[0].0
        return resolved == target ? .published : .mismatched(resolved)
    }

    private func localTagCommit(_ tag: String, repositoryURL: URL) async throws -> String? {
        let result = try await runner.run(
            at: repositoryURL,
            arguments: ["rev-parse", "-q", "--verify", "refs/tags/\(tag)^{}"],
            acceptedExitCodes: [0, 1, 128]
        )
        guard result.exitCode == 0 else { return nil }
        let value = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func remoteState(
        goal: ProjectGoal,
        remote: RepositoryRemoteIdentity,
        tagState: ProjectGoalReleaseTagState
    ) async throws -> ProjectGoalReleaseRemoteState {
        guard case .published = tagState,
              let tag = goal.releaseTag,
              let version = goal.releaseVersion else { return .absent }
        let repository = Self.repository(remote: remote, defaultBranch: goal.branchName)
        if let release = try await githubService.releases(for: repository).first(where: {
            $0.tagName.caseInsensitiveCompare(tag) == .orderedSame
        }) {
            let updateFeed = release.assets.first {
                $0.name.caseInsensitiveCompare("appcast.xml") == .orderedSame
            }
            let verified: Bool
            if let updateFeed {
                let data = try await githubService.releaseAssetData(updateFeed, in: repository)
                verified = Self.verifyUpdateFeed(data, version: version, buildNumber: goal.releaseBuildNumber)
            } else {
                verified = false
            }
            return .published(release, updateFeedVerified: verified)
        }

        let runs = try await githubService.actionRuns(for: repository)
            .filter { run in
                run.createdAt >= goal.createdAt.addingTimeInterval(-60)
                    && (run.branch?.caseInsensitiveCompare(tag) == .orderedSame
                        || run.displayTitle.localizedCaseInsensitiveContains(tag))
            }
            .sorted { $0.createdAt > $1.createdAt }
        guard let run = runs.first else { return .waiting(runNumber: nil) }
        if run.status.caseInsensitiveCompare("completed") != .orderedSame {
            return .waiting(runNumber: run.runNumber)
        }
        guard let conclusion = run.conclusion,
              conclusion.caseInsensitiveCompare("success") != .orderedSame else {
            return .waiting(runNumber: run.runNumber)
        }
        let detail = try? await githubService.actionRunDetail(run, in: repository, includeLog: true)
        return .failed(
            ProjectGoalActionFailure(
                runID: run.id,
                runNumber: run.runNumber,
                workflowName: run.name,
                conclusion: conclusion,
                webURL: run.webURL,
                logExcerpt: detail?.log.map { String($0.suffix(24_000)) }
            )
        )
    }

    static func verifyUpdateFeed(_ data: Data, version: String, buildNumber: String?) -> Bool {
        guard let source = String(data: data, encoding: .utf8),
              source.localizedCaseInsensitiveContains(".dmg"),
              source.contains(version) else { return false }
        guard let buildNumber, !buildNumber.isEmpty else { return true }
        return source.contains(buildNumber)
    }

    private static func repository(
        remote: RepositoryRemoteIdentity,
        defaultBranch: String
    ) -> GitHubRepository {
        let parts = remote.fullName.split(separator: "/", maxSplits: 1).map(String.init)
        return GitHubRepository(
            fullName: remote.fullName,
            name: parts.count == 2 ? parts[1] : remote.fullName,
            owner: parts.first ?? "",
            description: nil,
            webURL: URL(string: "https://github.com/\(remote.fullName)")!,
            stars: 0,
            forks: 0,
            openIssues: 0,
            language: nil,
            updatedAt: .distantPast,
            isPrivate: false,
            defaultBranch: defaultBranch
        )
    }
}

enum ProjectReleaseInspector {
    static func inspect(goal: ProjectGoal, fileManager: FileManager = .default) -> ProjectGoalReleaseLocalState {
        let root = URL(fileURLWithPath: goal.repositoryPath, isDirectory: true)
        let readmePath = readableFile(relativePath: "README.md", root: root, fileManager: fileManager)
            ? "README.md"
            : nil
        let translations = translatedReadmes(root: root, fileManager: fileManager)
        let versionEvidence = releaseValues(root: root, key: .version, fileManager: fileManager)
        let buildEvidence = releaseValues(root: root, key: .build, fileManager: fileManager)
        let changelogPath = changelog(
            version: goal.releaseVersion,
            root: root,
            fileManager: fileManager
        )
        let pipelinePath = releasePipeline(root: root, fileManager: fileManager)
        let installed = installedApplication(
            name: goal.releaseApplicationName ?? goal.repositoryName,
            preferredPath: goal.installedApplicationPath,
            fileManager: fileManager
        )
        return ProjectGoalReleaseLocalState(
            readmePath: readmePath,
            translationPaths: translations,
            versionEvidence: versionEvidence,
            buildEvidence: buildEvidence,
            changelogPath: changelogPath,
            releasePipelinePath: pipelinePath,
            installedApplication: installed
        )
    }

    static func suggestedVersion(at root: URL, fileManager: FileManager = .default) -> String? {
        let fixture = ProjectGoal(
            kind: .completeRelease,
            repositoryPath: root.path,
            repositoryName: root.lastPathComponent,
            branchName: "",
            baselineHeadSHA: "",
            commitMessage: ""
        )
        let values = inspect(goal: fixture, fileManager: fileManager).versionEvidence.map(\.value)
        guard let current = values.compactMap(SemanticVersion.init).max() else { return nil }
        return "\(current.major).\(current.minor).\(current.patch + 1)"
    }

    static func buildNumber(for version: String) -> String? {
        guard let parsed = SemanticVersion(version) else { return nil }
        return String(parsed.major * 1_000_000 + parsed.minor * 1_000 + parsed.patch)
    }

    private enum ValueKey {
        case version
        case build
    }

    private static func releaseValues(
        root: URL,
        key: ValueKey,
        fileManager: FileManager
    ) -> [ProjectGoalReleaseValueEvidence] {
        var values: [ProjectGoalReleaseValueEvidence] = []
        func record(path: String, source: String, patterns: [String]) {
            for pattern in patterns {
                for match in captures(pattern, source: source) where !match.contains("$(") {
                    values.append(ProjectGoalReleaseValueEvidence(path: path, value: match))
                }
            }
        }

        let textFiles = ["project.yml", "scripts/package-macos.sh"]
        for path in textFiles {
            guard let source = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
                continue
            }
            switch key {
            case .version:
                record(
                    path: path,
                    source: source,
                    patterns: [
                        #"MARKETING_VERSION:\s*\"?([0-9]+\.[0-9]+\.[0-9]+)\"?"#,
                        #"GITGATTO_VERSION:-([0-9]+\.[0-9]+\.[0-9]+)"#
                    ]
                )
            case .build:
                record(
                    path: path,
                    source: source,
                    patterns: [
                        #"CURRENT_PROJECT_VERSION:\s*\"?([0-9]+)\"?"#,
                        #"GITGATTO_BUILD_NUMBER:-([0-9]+)"#
                    ]
                )
            }
        }

        if let projects = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for project in projects where project.pathExtension == "xcodeproj" {
                let path = project.appendingPathComponent("project.pbxproj")
                guard let source = try? String(contentsOf: path, encoding: .utf8) else { continue }
                switch key {
                case .version:
                    record(
                        path: project.lastPathComponent + "/project.pbxproj",
                        source: source,
                        patterns: [#"MARKETING_VERSION = ([0-9]+\.[0-9]+\.[0-9]+);"#]
                    )
                case .build:
                    record(
                        path: project.lastPathComponent + "/project.pbxproj",
                        source: source,
                        patterns: [#"CURRENT_PROJECT_VERSION = ([0-9]+);"#]
                    )
                }
            }
        }
        var seen = Set<String>()
        return values.filter { seen.insert("\($0.path)\u{0}\($0.value)").inserted }
    }

    private static func translatedReadmes(root: URL, fileManager: FileManager) -> [String] {
        let directories = [root, root.appendingPathComponent("docs", isDirectory: true)]
        var paths: [String] = []
        for directory in directories {
            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for file in files {
                let name = file.lastPathComponent.lowercased()
                guard name.hasPrefix("readme"), name.hasSuffix(".md"), name != "readme.md" else { continue }
                guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                      ((try? Data(contentsOf: file).count) ?? 0) > 40 else { continue }
                paths.append(relativePath(file, root: root))
            }
        }
        return paths.sorted()
    }

    private static func changelog(
        version: String?,
        root: URL,
        fileManager: FileManager
    ) -> String? {
        guard let version else { return nil }
        for path in ["CHANGELOG.md", "CHANGES.md", "RELEASE_NOTES.md"] {
            let url = root.appendingPathComponent(path)
            guard fileManager.fileExists(atPath: url.path),
                  let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: version)
            if source.range(of: "(?m)^##\\s+(?:\\[)?v?\(escaped)(?:\\])?(?:\\s|$)", options: .regularExpression) != nil {
                return path
            }
        }
        return nil
    }

    private static func releasePipeline(root: URL, fileManager: FileManager) -> String? {
        let directory = root.appendingPathComponent(".github/workflows", isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for file in files where ["yml", "yaml"].contains(file.pathExtension.lowercased()) {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lower = source.lowercased()
            if lower.contains("tags:")
                && lower.contains(".dmg")
                && lower.contains("appcast.xml")
                && lower.contains("release") {
                return relativePath(file, root: root)
            }
        }
        return nil
    }

    private static func installedApplication(
        name: String,
        preferredPath: String?,
        fileManager: FileManager
    ) -> ProjectGoalInstalledApplication? {
        let appName = name.hasSuffix(".app") ? name : "\(name).app"
        let standardCandidates = [
            URL(fileURLWithPath: "/Applications", isDirectory: true).appendingPathComponent(appName),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent(appName)
        ]
        let candidates = preferredPath.map { [URL(fileURLWithPath: $0, isDirectory: true)] + standardCandidates }
            ?? standardCandidates
        for app in candidates where fileManager.fileExists(atPath: app.path) {
            let infoURL = app.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: infoURL),
                  let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let info = object as? [String: Any],
                  let version = info["CFBundleShortVersionString"] as? String,
                  let build = info["CFBundleVersion"] as? String else { continue }
            return ProjectGoalInstalledApplication(path: app.path, version: version, buildNumber: build)
        }
        return nil
    }

    private static func readableFile(relativePath path: String, root: URL, fileManager: FileManager) -> Bool {
        let url = root.appendingPathComponent(path)
        guard fileManager.fileExists(atPath: url.path) else { return false }
        return ((try? Data(contentsOf: url).count) ?? 0) > 40
    }

    private static func captures(_ pattern: String, source: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return expression.matches(in: source, range: range).compactMap { result in
            guard result.numberOfRanges > 1,
                  let range = Range(result.range(at: 1), in: source) else { return nil }
            return String(source[range])
        }
    }

    private static func relativePath(_ url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private struct SemanticVersion: Comparable {
        let major: Int
        let minor: Int
        let patch: Int

        init?(_ source: String) {
            let parts = source.split(separator: ".")
            guard parts.count == 3,
                  let major = Int(parts[0]),
                  let minor = Int(parts[1]),
                  let patch = Int(parts[2]) else { return nil }
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
    }
}
