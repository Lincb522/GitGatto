import AppKit
import Foundation
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Developer tool installation and updates")
struct DevelopmentToolTests {
    @Test("Catalog entries have stable unique identifiers and cover every tool category")
    func catalogStructure() {
        let tools = DevelopmentTool.catalog
        let filterCategories: Set<DevelopmentToolCategory> = [.all, .installed, .updates]
        #expect(tools.count == 63)
        #expect(tools.compactMap(\.homebrewFormula).count == 60)
        #expect(Set(tools.map(\.id)).count == tools.count)
        #expect(tools.allSatisfy { !$0.executableCandidates.isEmpty })
        #expect(Set(tools.map(\.category)) == Set(DevelopmentToolCategory.allCases).subtracting(filterCategories))
        #expect(tools.filter { $0.category == .essentials }.count == 8)
        #expect(tools.filter { $0.category == .runtimes }.count == 11)
        #expect(tools.filter { $0.category == .build }.count == 10)
        #expect(tools.filter { $0.category == .containers }.count == 8)
        #expect(tools.filter { $0.category == .cloud }.count == 5)
        #expect(tools.filter { $0.category == .databases }.count == 7)
        #expect(tools.filter { $0.category == .utilities }.count == 14)
    }

    @Test("Installer and upgrade prompts contain exact runtime values")
    func installerPromptsUseRuntimeValues() throws {
        let artifactURL = URL(fileURLWithPath: "/tmp/GitGatto Fixture/tool.pkg")
        let artifactPrompt = CodexService.downloadedArtifactInstallPrompt(
            url: artifactURL,
            displayName: "example/tool"
        )
        #expect(artifactPrompt.contains(artifactURL.path))
        #expect(artifactPrompt.contains("example/tool"))
        #expect(artifactPrompt.contains("Post-install configuration is required"))
        #expect(artifactPrompt.contains("Never stop after merely printing a suggested setup command"))

        let tool = try #require(DevelopmentTool.catalog.first { $0.id == "git-lfs" })
        let installPrompt = CodexService.developmentToolInstallPrompt(tool)
        #expect(installPrompt.contains(tool.name))
        #expect(installPrompt.contains(tool.packageHint))
        #expect(installPrompt.contains("git-lfs"))
        #expect(installPrompt.contains("every documented non-secret initialization"))
        #expect(installPrompt.contains("persists the verified executable directory"))
        #expect(!installPrompt.contains("report a required PATH line"))

        for catalogTool in DevelopmentTool.catalog {
            let prompt = CodexService.developmentToolInstallPrompt(catalogTool)
            #expect(prompt.contains(catalogTool.name))
            #expect(prompt.contains(catalogTool.packageHint))
            #expect(prompt.contains("Post-install configuration is a required phase for every tool"))
            #expect(prompt.contains("Run setup commands instead of returning them as instructions"))
            #expect(prompt.contains("documented configuration or status check"))
        }

        let upgradePrompt = CodexService.developmentToolUpgradePrompt(
            tool,
            packageName: "git-lfs",
            installedVersion: "3.7.1",
            latestVersion: "3.8.0"
        )
        #expect(upgradePrompt.contains("Exact Homebrew formula: git-lfs"))
        #expect(upgradePrompt.contains("3.7.1"))
        #expect(upgradePrompt.contains("3.8.0"))
        #expect(upgradePrompt.contains("upgrade only that formula"))
        #expect(upgradePrompt.contains("Post-upgrade configuration is a required phase"))
        #expect(upgradePrompt.contains("apply every documented non-secret migration"))
    }

    @Test("Post-install setup persists a user-local executable directory once")
    func persistsUserLocalPath() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitgatto-environment-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let profile = home.appendingPathComponent(".zprofile")
        try Data("export EXISTING_VALUE=1\n".utf8).write(to: profile)
        let executable = home.appendingPathComponent(".local/bin/example-tool")
        let configurator = DevelopmentToolEnvironmentConfigurator(
            homeDirectory: home,
            shellPath: "/bin/zsh",
            environmentPath: "/usr/bin:/bin",
            updatesProcessEnvironment: false
        )

        let first = try await configurator.configure(executableURL: executable)
        let second = try await configurator.configure(executableURL: executable)
        let content = try String(contentsOf: profile, encoding: .utf8)

        #expect(first == .updated(profileURL: profile))
        #expect(second == .unchanged)
        #expect(content.hasPrefix("export EXISTING_VALUE=1\n"))
        #expect(content.contains("export PATH=\"$HOME/.local/bin:$PATH\""))
        #expect(content.components(separatedBy: "# GitGatto PATH: $HOME/.local/bin").count == 2)
    }

    @Test("Post-install setup leaves an effective PATH unchanged")
    func keepsEffectivePathUnchanged() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitgatto-environment-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent(".local/bin", isDirectory: true)
        let configurator = DevelopmentToolEnvironmentConfigurator(
            homeDirectory: home,
            shellPath: "/bin/zsh",
            environmentPath: "\(directory.path):/usr/bin:/bin",
            updatesProcessEnvironment: false
        )

        let result = try await configurator.configure(
            executableURL: directory.appendingPathComponent("example-tool")
        )

        #expect(result == .unchanged)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".zprofile").path))
    }

    @Test("Agent install progress ends in a verified installed state")
    @MainActor
    func installsAndVerifiesTool() async throws {
        let fixture = DevelopmentToolInstallFixture()
        let model = DeveloperToolsViewModel(
            installer: fixture,
            probe: fixture,
            updateChecker: fixture,
            environmentConfigurator: fixture
        )
        let tool = try #require(DevelopmentTool.catalog.first { $0.id == "git-lfs" })

        model.install(tool)
        try await waitUntil { model.status(for: tool).state == .installed }

        let status = model.status(for: tool)
        #expect(status.isInstalled)
        #expect(status.version == "3.7.1")
        #expect(status.latestVersion == "3.8.0")
        #expect(status.updateAvailability == .available)
        #expect(status.result == "Installed and verified")
        #expect(await fixture.installedToolIDs == ["git-lfs"])
        #expect(await fixture.configuredExecutableNames == ["git-lfs"])
    }

    @Test("Installed and updates filters use scanned local state and Agent verifies an upgrade")
    @MainActor
    func detectsAndUpgradesInstalledTool() async throws {
        let fixture = DevelopmentToolInstallFixture()
        let tool = try #require(DevelopmentTool.catalog.first { $0.id == "git-lfs" })
        await fixture.seedInstalled(tool.id)
        let model = DeveloperToolsViewModel(
            installer: fixture,
            probe: fixture,
            updateChecker: fixture,
            environmentConfigurator: fixture
        )

        model.refresh()
        try await waitUntil {
            model.status(for: tool).updateAvailability == .available
        }

        model.changeCategory(.installed)
        #expect(model.filteredTools.contains(tool))
        model.changeCategory(.updates)
        #expect(model.filteredTools == [tool])

        model.upgrade(tool)
        try await waitUntil {
            model.status(for: tool).state == .installed
                && model.status(for: tool).updateAvailability == .current
        }

        let status = model.status(for: tool)
        #expect(status.version == "3.8.0")
        #expect(status.latestVersion == "3.8.0")
        #expect(!status.canUpgrade)
        #expect(await fixture.upgradedToolIDs == ["git-lfs"])
    }

    @Test("Homebrew scan maps versioned formula aliases and pinned updates")
    func homebrewUpdateScan() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitgatto-brew-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("brew")
        let script = """
        #!/bin/sh
        case "$1" in
          list)
            printf 'git-lfs 3.7.1\\npython@3.14 3.14.0\\n'
            exit 1
            ;;
          outdated)
            printf '%s' '{"formulae":[{"name":"git-lfs","installed_versions":["3.7.1"],"current_version":"3.8.0","pinned":false},{"name":"python@3.14","installed_versions":["3.14.0"],"current_version":"3.14.1","pinned":true}]}'
            ;;
        esac
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let tools = try [
            #require(DevelopmentTool.catalog.first { $0.id == "git-lfs" }),
            #require(DevelopmentTool.catalog.first { $0.id == "python" })
        ]
        let service = DevelopmentToolUpdateService(homebrewURL: executable)
        let results = await service.checkUpdates(for: tools)

        #expect(results["git-lfs"]?.availability == .available)
        #expect(results["git-lfs"]?.installedVersion == "3.7.1")
        #expect(results["git-lfs"]?.latestVersion == "3.8.0")
        #expect(results["git-lfs"]?.packageName == "git-lfs")
        #expect(results["python"]?.availability == .available)
        #expect(results["python"]?.packageName == "python@3.14")
        #expect(results["python"]?.isPinned == true)
    }

    @Test("Developer tool updates render without clipping at the default window size")
    @MainActor
    func rendersDeveloperToolUpdates() async throws {
        let fixture = DevelopmentToolInstallFixture()
        let tool = try #require(DevelopmentTool.catalog.first { $0.id == "git-lfs" })
        await fixture.seedInstalled(tool.id)
        let developerTools = DeveloperToolsViewModel(
            installer: fixture,
            probe: fixture,
            updateChecker: fixture,
            environmentConfigurator: fixture
        )
        developerTools.refresh()
        try await waitUntil {
            developerTools.status(for: tool).updateAvailability == .available
        }
        developerTools.select(tool)

        let view = GitHubMarketplaceView(
            model: GitHubMarketplaceViewModel(),
            developerTools: developerTools,
            downloads: AppDownloadManager(),
            showsDeveloperToolsInitially: true
        )
        .frame(width: 1_416, height: 876)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_416, height: 876)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        let representation = try #require(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        #expect(representation.pixelsWide == 1_416)
        #expect(representation.pixelsHigh == 876)

        if let outputPath = ProcessInfo.processInfo.environment["GITGATTO_UI_SNAPSHOT_PATH"] {
            let data = try #require(representation.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(60),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for developer tool state")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private actor DevelopmentToolInstallFixture:
    CodexServing,
    DevelopmentToolProbing,
    DevelopmentToolUpdateChecking,
    DevelopmentToolEnvironmentConfiguring
{
    private(set) var installedToolIDs: [String] = []
    private(set) var upgradedToolIDs: [String] = []
    private(set) var configuredExecutableNames: [String] = []

    func seedInstalled(_ toolID: String) {
        installedToolIDs = [toolID]
    }

    func probe() async -> CodexAvailability { .unavailable }

    func probe(_ tool: DevelopmentTool) async -> DevelopmentToolProbeResult {
        let installed = installedToolIDs.contains(tool.id)
        let upgraded = upgradedToolIDs.contains(tool.id)
        return DevelopmentToolProbeResult(
            isInstalled: installed,
            version: installed ? (upgraded ? "3.8.0" : "git-lfs/3.7.1") : nil,
            executableURL: installed
                ? URL(fileURLWithPath: "/Users/fixture/.local/bin/git-lfs")
                : nil
        )
    }

    func configure(executableURL: URL) async throws -> DevelopmentToolEnvironmentConfiguration {
        configuredExecutableNames.append(executableURL.lastPathComponent)
        return .updated(profileURL: URL(fileURLWithPath: "/Users/fixture/.zprofile"))
    }

    func checkUpdates(for tools: [DevelopmentTool]) async -> [String: DevelopmentToolUpdateResult] {
        Dictionary(uniqueKeysWithValues: tools.map { tool in
            let installed = installedToolIDs.contains(tool.id)
            let upgraded = upgradedToolIDs.contains(tool.id)
            let result: DevelopmentToolUpdateResult
            if installed, upgraded {
                result = DevelopmentToolUpdateResult(
                    availability: .current,
                    installedVersion: "3.8.0",
                    latestVersion: "3.8.0",
                    packageName: tool.homebrewFormula,
                    isPinned: false,
                    detail: nil
                )
            } else if installed {
                result = DevelopmentToolUpdateResult(
                    availability: .available,
                    installedVersion: "3.7.1",
                    latestVersion: "3.8.0",
                    packageName: tool.homebrewFormula,
                    isPinned: false,
                    detail: nil
                )
            } else {
                result = .unavailable()
            }
            return (tool.id, result)
        })
    }

    func run(
        prompt: String,
        context: [CodexMessage],
        in repositoryURL: URL,
        mode: CodexRunMode
    ) async throws -> CodexRunResult {
        throw CodexServiceError.executionFailed(-1)
    }

    func runWithProvidedContext(
        prompt: String,
        context: [CodexMessage]
    ) async throws -> CodexRunResult {
        throw CodexServiceError.executionFailed(-1)
    }

    func draftPullRequestReply(context: GitHubPullRequestContext) async throws -> String {
        throw CodexServiceError.executionFailed(-1)
    }

    func translate(_ text: String, target: CodexTranslationTarget) async throws -> String {
        throw CodexServiceError.executionFailed(-1)
    }

    func translateHTML(
        _ html: String,
        target: CodexTranslationTarget,
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> String {
        throw CodexServiceError.executionFailed(-1)
    }

    func installDevelopmentTool(
        _ tool: DevelopmentTool,
        progress: @escaping @Sendable (AgentInstallProgress) async -> Void
    ) async throws -> CodexRunResult {
        await progress(AgentInstallProgress(.preparing))
        await progress(AgentInstallProgress(.inspecting))
        await progress(AgentInstallProgress(.installing))
        if !installedToolIDs.contains(tool.id) {
            installedToolIDs.append(tool.id)
        }
        await progress(AgentInstallProgress(.verifying))
        return CodexRunResult(response: "Installed and verified", commandCount: 2, fileChangeCount: 0)
    }

    func upgradeDevelopmentTool(
        _ tool: DevelopmentTool,
        packageName: String,
        installedVersion: String?,
        latestVersion: String?,
        progress: @escaping @Sendable (AgentInstallProgress) async -> Void
    ) async throws -> CodexRunResult {
        #expect(packageName == "git-lfs")
        #expect(installedVersion?.contains("3.7.1") == true)
        #expect(latestVersion == "3.8.0")
        await progress(AgentInstallProgress(.preparing))
        await progress(AgentInstallProgress(.inspecting))
        await progress(AgentInstallProgress(.installing))
        upgradedToolIDs.append(tool.id)
        await progress(AgentInstallProgress(.verifying))
        return CodexRunResult(response: "Upgraded and verified", commandCount: 2, fileChangeCount: 0)
    }

    func cancel() async {}
}
