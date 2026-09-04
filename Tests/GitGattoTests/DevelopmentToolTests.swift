import AppKit
import Darwin
import Foundation
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Developer tool installation and updates", .serialized)
struct DevelopmentToolTests {
    @Test("Agent installation phases form one complete ordered progress sequence")
    func installationPhaseSequence() {
        #expect(AgentInstallPhase.allCases == [
            .preparing,
            .inspecting,
            .installing,
            .configuring,
            .verifying
        ])
        #expect(AgentInstallPhase.allCases.map(\.stepNumber) == [1, 2, 3, 4, 5])
    }

    @Test("Catalog entries have stable unique identifiers and cover every tool category")
    func catalogStructure() {
        let tools = DevelopmentTool.catalog
        let filterCategories: Set<DevelopmentToolCategory> = [.all, .installed, .updates]
        #expect(tools.count == 99)
        #expect(tools.compactMap(\.homebrewFormula).count == 96)
        #expect(Set(tools.map(\.id)).count == tools.count)
        #expect(tools.allSatisfy { !$0.executableCandidates.isEmpty })
        #expect(Set(tools.map(\.category)) == Set(DevelopmentToolCategory.allCases).subtracting(filterCategories))
        #expect(tools.filter { $0.category == .essentials }.count == 10)
        #expect(tools.filter { $0.category == .runtimes }.count == 13)
        #expect(tools.filter { $0.category == .build }.count == 19)
        #expect(tools.filter { $0.category == .containers }.count == 13)
        #expect(tools.filter { $0.category == .cloud }.count == 8)
        #expect(tools.filter { $0.category == .databases }.count == 7)
        #expect(tools.filter { $0.category == .utilities }.count == 29)
        for tool in tools {
            guard let logoName = tool.brandLogoName else { continue }
            let logoURL = AppResourceBundle.current.url(
                forResource: logoName,
                withExtension: "png",
                subdirectory: "ToolLogos"
            ) ?? AppResourceBundle.current.url(forResource: logoName, withExtension: "png")
            #expect(logoURL != nil, "Missing bundled logo for \(tool.id)")
        }
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
        #expect(installPrompt.contains("ownership of the Homebrew prefix alone is not proof"))
        #expect(installPrompt.contains("restore its original pinned state"))
        #expect(installPrompt.contains("otherwise allow Homebrew's normal source build"))
        #expect(installPrompt.contains("Formula-declared runtime and build dependencies are part of the requested installation"))
        #expect(installPrompt.contains("GITGATTO_RESULT: ACTION_REQUIRED"))
        #expect(!installPrompt.contains("report a required PATH line"))

        for catalogTool in DevelopmentTool.catalog {
            let prompt = CodexService.developmentToolInstallPrompt(catalogTool)
            #expect(prompt.contains(catalogTool.name))
            #expect(prompt.contains(catalogTool.packageHint))
            #expect(prompt.contains("Post-install configuration is a required phase for every tool"))
            #expect(prompt.contains("Run setup commands instead of returning them as instructions"))
            #expect(prompt.contains("credential-free local configuration check"))
            #expect(prompt.contains("These runtime states do not block installation"))
        }

        let upgradePrompt = CodexService.developmentToolUpgradePrompt(
            tool,
            packageName: "git-lfs",
            installedVersion: "3.7.1",
            latestVersion: "3.8.0"
        )
        #expect(upgradePrompt.contains("Exact Homebrew formula: git-lfs"))
        #expect(upgradePrompt.contains(tool.packageHint))
        #expect(upgradePrompt.contains("3.7.1"))
        #expect(upgradePrompt.contains("3.8.0"))
        #expect(upgradePrompt.contains("upgrade only that formula"))
        #expect(upgradePrompt.contains("HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade --formula --force-bottle git-lfs"))
        #expect(upgradePrompt.contains("HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade --formula git-lfs"))
        #expect(upgradePrompt.contains("If no compatible bottle exists"))
        #expect(upgradePrompt.contains("Homebrew's normal source build is allowed and must continue"))
        #expect(upgradePrompt.contains("Formula-declared runtime and build dependencies are part of this exact upgrade"))
        #expect(upgradePrompt.contains("Post-upgrade configuration is a required phase"))
        #expect(upgradePrompt.contains("apply every documented non-secret migration"))

        let postUpgradePrompt = CodexService.developmentToolPostUpgradePrompt(
            tool,
            packageName: "git-lfs",
            installedVersion: "3.7.1",
            latestVersion: "3.8.0"
        )
        #expect(postUpgradePrompt.contains("already upgraded through Homebrew outside this Agent sandbox"))
        #expect(postUpgradePrompt.contains(tool.packageHint))
        #expect(postUpgradePrompt.contains("Do not install, upgrade, reinstall, unlink, or remove any package"))
        #expect(postUpgradePrompt.contains("git lfs install"))
        #expect(postUpgradePrompt.contains("GITGATTO_RESULT: COMPLETE"))

        let compose = try #require(DevelopmentTool.catalog.first { $0.id == "docker-compose" })
        let postInstallPrompt = CodexService.developmentToolPostInstallPrompt(
            compose,
            packageName: "docker-compose"
        )
        #expect(postInstallPrompt.contains("already installed through its controlled Homebrew runner"))
        #expect(postInstallPrompt.contains("Write only inside the controlled directories supplied by GitGatto"))
        #expect(postInstallPrompt.contains("These runtime states do not block installation"))
        #expect(postInstallPrompt.contains("GITGATTO_RESULT: ACTION_REQUIRED"))
        #expect(compose.packageHint.contains("~/.docker/cli-plugins/docker-compose"))
        #expect(compose.packageHint.contains("never read or modify ~/.docker/config.json"))

        let githubCLI = try #require(DevelopmentTool.catalog.first { $0.id == "github-cli" })
        #expect(githubCLI.packageHint.contains("without inspecting or changing GitHub authentication state"))
        #expect(CodexService.developmentToolPostInstallPrompt(
            githubCLI,
            packageName: "gh"
        ).contains("even if an account is signed out or an existing token is invalid"))
    }

    @Test("Agent configuration status is explicit and removed from the displayed result")
    func parsesAgentConfigurationStatus() {
        let complete = CodexService.developmentToolResult(CodexRunResult(
            response: "GitHub CLI verified. Existing account token is invalid.\nGITGATTO_RESULT: COMPLETE",
            commandCount: 2,
            fileChangeCount: 0
        ))
        let blocked = CodexService.developmentToolResult(CodexRunResult(
            response: "Plugin registration needs user action.\nGITGATTO_RESULT: ACTION_REQUIRED",
            commandCount: 1,
            fileChangeCount: 0
        ))
        let unstructured = CodexService.developmentToolResult(CodexRunResult(
            response: "Installed",
            commandCount: 1,
            fileChangeCount: 0
        ))

        #expect(complete.response == "GitHub CLI verified. Existing account token is invalid.")
        #expect(!complete.requiresUserAction)
        #expect(blocked.response == "Plugin registration needs user action.")
        #expect(blocked.requiresUserAction)
        #expect(unstructured.requiresUserAction)
    }

    @Test("Homebrew upgrades run directly with bounded noninteractive environment")
    func homebrewUpgradeRunsOutsideAgentSandbox() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitgatto-homebrew-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("brew")
        let log = directory.appendingPathComponent("invocation.log")
        let script = """
        #!/bin/sh
        {
          printf 'arguments=%s\\n' "$*"
          printf 'auto_update=%s\\n' "$HOMEBREW_NO_AUTO_UPDATE"
          printf 'noninteractive=%s\\n' "$NONINTERACTIVE"
        } > '\(log.path)'
        printf 'upgraded node\\n'
        """
        try Data(script.utf8).write(to: executable)
        #expect(chmod(executable.path, 0o755) == 0)

        let service = DevelopmentToolHomebrewService(
            homebrewURL: executable,
            timeout: .seconds(5)
        )
        let output = try await service.run(.upgrade, formula: "node")
        let invocation = try String(contentsOf: log, encoding: .utf8)

        #expect(output == "upgraded node")
        #expect(invocation.contains("arguments=upgrade --formula node"))
        #expect(invocation.contains("auto_update=1"))
        #expect(invocation.contains("noninteractive=1"))

        await #expect(throws: DevelopmentToolHomebrewError.invalidFormula) {
            try await service.run(.upgrade, formula: "node;rm")
        }
    }

    @Test("Homebrew installs run through the controlled package runner")
    func homebrewInstallRunsOutsideAgentSandbox() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitgatto-homebrew-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("brew")
        let log = directory.appendingPathComponent("invocation.log")
        let script = """
        #!/bin/sh
        printf '%s\n' "$*" > '\(log.path)'
        """
        try Data(script.utf8).write(to: executable)
        #expect(chmod(executable.path, 0o755) == 0)

        let service = DevelopmentToolHomebrewService(
            homebrewURL: executable,
            timeout: .seconds(5)
        )
        _ = try await service.run(.install, formula: "docker-compose")
        let invocation = try String(contentsOf: log, encoding: .utf8)

        #expect(invocation.trimmingCharacters(in: .whitespacesAndNewlines) == "install --formula docker-compose")
    }

    @Test("Homebrew mutations are serialized across Agent lanes")
    func serializesHomebrewMutationsAcrossLanes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitgatto-homebrew-gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("brew")
        let activeDirectory = directory.appendingPathComponent("active")
        let log = directory.appendingPathComponent("invocation.log")
        let script = """
        #!/bin/sh
        if ! mkdir '\(activeDirectory.path)' 2>/dev/null; then
          printf 'overlap %s\n' "$3" >&2
          exit 73
        fi
        trap 'rmdir "\(activeDirectory.path)"' EXIT
        printf 'start %s\n' "$3" >> '\(log.path)'
        sleep 0.2
        printf 'end %s\n' "$3" >> '\(log.path)'
        """
        try Data(script.utf8).write(to: executable)
        #expect(chmod(executable.path, 0o755) == 0)

        let first = DevelopmentToolHomebrewService(homebrewURL: executable, timeout: .seconds(10))
        let second = DevelopmentToolHomebrewService(homebrewURL: executable, timeout: .seconds(10))
        async let node = first.run(.upgrade, formula: "node")
        async let go = second.run(.upgrade, formula: "go")
        _ = try await (node, go)

        let lines = try String(contentsOf: log, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        try #require(lines.count == 4)
        #expect(lines[0].hasPrefix("start "))
        #expect(lines[1] == lines[0].replacingOccurrences(of: "start ", with: "end "))
        #expect(lines[2].hasPrefix("start "))
        #expect(lines[3] == lines[2].replacingOccurrences(of: "start ", with: "end "))
    }

    @Test("Installer sandbox includes every Homebrew managed directory")
    func includesHomebrewManagedDirectories() {
        let paths = Set(CodexService.developmentToolWritableDirectories().map(\.standardizedFileURL.path))
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        #expect(paths.contains("\(home)/.docker/cli-plugins"))
        #expect(!paths.contains("\(home)/.docker"))
        for name in [
            "Homebrew",
            "Cellar",
            "Caskroom",
            "Frameworks",
            "bin",
            "etc",
            "include",
            "lib",
            "opt",
            "sbin",
            "share",
            "var"
        ] {
            #expect(paths.contains("/usr/local/\(name)"))
            #expect(paths.contains("/opt/homebrew/\(name)"))
        }
    }

    @Test("Non-Codex Agent installers cannot write outside the controlled scope")
    func externalAgentInstallerUsesControlledWriteScope() throws {
        let fileManager = FileManager.default
        let allowedDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/GitGattoSandboxTest/\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: allowedDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: allowedDirectory) }
        let allowedFile = allowedDirectory.appendingPathComponent("allowed")
        let deniedFile = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".gitgatto-sandbox-denied-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: deniedFile) }
        let profile = CodexService.installerSandboxProfile(
            writableDirectories: [allowedDirectory]
        )

        let allowed = Process()
        allowed.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        allowed.arguments = ["-p", profile, "/usr/bin/touch", allowedFile.path]
        try allowed.run()
        allowed.waitUntilExit()

        let denied = Process()
        denied.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        denied.arguments = ["-p", profile, "/usr/bin/touch", deniedFile.path]
        denied.standardError = Pipe()
        try denied.run()
        denied.waitUntilExit()

        #expect(allowed.terminationStatus == 0)
        #expect(fileManager.fileExists(atPath: allowedFile.path))
        #expect(denied.terminationStatus != 0)
        #expect(!fileManager.fileExists(atPath: deniedFile.path))
    }

    @Test("Installer sandbox denies reading credential stores even inside writable roots")
    func externalAgentInstallerCannotReadCredentialStores() throws {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let protectedPaths = CodexService.installerSandboxProtectedPaths(home: home)
            .map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        let profile = CodexService.installerSandboxProfile(
            writableDirectories: [home.appendingPathComponent(".config", isDirectory: true)]
        )

        for expected in [".ssh", ".config/gh", ".aws", ".docker/config.json", ".git-credentials"] {
            let resolved = home.appendingPathComponent(expected).standardizedFileURL.resolvingSymlinksInPath().path
            #expect(protectedPaths.contains(resolved))
            #expect(profile.contains("(deny file-read* file-write* (subpath \"\(resolved)\"))"))
        }

        // `~/.config/gh` sits under the writable `~/.config` root; the trailing denial must still win.
        let ghDirectory = home.appendingPathComponent(".config/gh", isDirectory: true)
        let existedBefore = fileManager.fileExists(atPath: ghDirectory.path)
        if !existedBefore {
            try fileManager.createDirectory(at: ghDirectory, withIntermediateDirectories: true)
        }
        defer {
            if !existedBefore { try? fileManager.removeItem(at: ghDirectory) }
        }
        let probeName = ".gitgatto-sandbox-probe-\(UUID().uuidString)"
        let probeFile = ghDirectory.appendingPathComponent(probeName)
        defer { try? fileManager.removeItem(at: probeFile) }

        let write = Process()
        write.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        write.arguments = ["-p", profile, "/usr/bin/touch", probeFile.path]
        write.standardError = Pipe()
        try write.run()
        write.waitUntilExit()

        let list = Process()
        list.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        list.arguments = ["-p", profile, "/bin/ls", ghDirectory.path]
        list.standardOutput = Pipe()
        list.standardError = Pipe()
        try list.run()
        list.waitUntilExit()

        #expect(write.terminationStatus != 0)
        #expect(!fileManager.fileExists(atPath: probeFile.path))
        #expect(list.terminationStatus != 0)
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

    @Test("A zero-byte executable is not accepted as an installed tool")
    func rejectsEmptyExecutable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitgatto-empty-tool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("empty-tool")
        try Data().write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let tool = DevelopmentTool(
            id: "empty-tool",
            name: "Empty Tool",
            category: .utilities,
            icon: "code",
            packageHint: "Fixture",
            homebrewFormula: nil,
            executableCandidates: ["empty-tool"],
            versionArguments: ["--version"]
        )
        let probe = DevelopmentToolProbe(additionalSearchDirectories: [directory.path])

        let result = await probe.probe(tool)

        #expect(!result.isInstalled)
        #expect(result.version == nil)
        #expect(result.executableURL == executable)
        #expect(result.failureDetail?.isEmpty == false)
    }

    @Test("System authorization runs only a validated Homebrew repair command")
    func validatesPrivilegedRepairCommand() async throws {
        let recorder = AuthorizationCommandRecorder()
        let authorizer = DevelopmentToolSystemAuthorizer(
            runAuthorization: { command, prompt in
                await recorder.record(command: command, prompt: prompt)
            }
        )
        let request = DevelopmentToolSystemAuthorizationRequest(
            toolName: "Python 3",
            homebrewPrefix: URL(fileURLWithPath: "/usr/local", isDirectory: true),
            repairDirectories: [
                URL(fileURLWithPath: "/usr/local/Cellar", isDirectory: true),
                URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
            ]
        )

        try await authorizer.authorize(request)
        let command = try #require(await recorder.commands.first)
        #expect(command.contains("/usr/sbin/chown -R"))
        #expect(command.contains("'/usr/local/Cellar'"))
        #expect(command.contains("/usr/sbin/chown \(getuid())"))
        #expect(command.contains("'/usr/local/bin'"))
        #expect(!command.contains("sudo"))
        #expect(!command.contains("chown -R \(getuid()) '/usr/local/bin'"))

        let invalidRequest = DevelopmentToolSystemAuthorizationRequest(
            toolName: "Python 3",
            homebrewPrefix: URL(fileURLWithPath: "/usr/local", isDirectory: true),
            repairDirectories: [URL(fileURLWithPath: "/etc", isDirectory: true)]
        )
        await #expect(throws: DevelopmentToolSystemAuthorizationError.invalidRequest) {
            try await authorizer.authorize(invalidRequest)
        }
        #expect(await recorder.commands.count == 1)
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
        #expect(status.operationStartedAt == nil)
        #expect(await fixture.installedToolIDs == ["git-lfs"])
        #expect(await fixture.configuredExecutableNames == ["git-lfs"])
    }

    @Test("A protected Homebrew repair asks once and retries installation automatically")
    @MainActor
    func authorizesSystemRepairAndRetries() async throws {
        let fixture = DevelopmentToolInstallFixture()
        await fixture.requireSystemAuthorization()
        let model = DeveloperToolsViewModel(
            installer: fixture,
            probe: fixture,
            updateChecker: fixture,
            environmentConfigurator: fixture,
            systemAuthorizer: fixture
        )
        let tool = try #require(DevelopmentTool.catalog.first { $0.id == "git-lfs" })

        model.install(tool)
        try await waitUntil { model.status(for: tool).state == .installed }

        #expect(await fixture.authorizationCount == 1)
        #expect(await fixture.installAttemptCount == 2)
        #expect(model.status(for: tool).authorizationRequest == nil)
    }

    @Test("Cancelled system authorization stays available as an explicit retry")
    @MainActor
    func retriesCancelledSystemAuthorization() async throws {
        let fixture = DevelopmentToolInstallFixture()
        await fixture.requireSystemAuthorization(cancelFirstRequest: true)
        let model = DeveloperToolsViewModel(
            installer: fixture,
            probe: fixture,
            updateChecker: fixture,
            environmentConfigurator: fixture,
            systemAuthorizer: fixture
        )
        let tool = try #require(DevelopmentTool.catalog.first { $0.id == "git-lfs" })

        model.install(tool)
        try await waitUntil { model.status(for: tool).state == .actionRequired }
        #expect(model.status(for: tool).authorizationRequest != nil)

        await fixture.allowSystemAuthorization()
        model.authorizeAndRetry(tool)
        try await waitUntil { model.status(for: tool).state == .installed }

        #expect(await fixture.authorizationCount == 2)
        #expect(await fixture.installAttemptCount == 2)
        #expect(model.status(for: tool).authorizationRequest == nil)
    }

    @Test("System authorization recovery renders at the default window size")
    @MainActor
    func rendersSystemAuthorizationRecovery() async throws {
        let fixture = DevelopmentToolInstallFixture()
        await fixture.requireSystemAuthorization(cancelFirstRequest: true)
        let developerTools = DeveloperToolsViewModel(
            installer: fixture,
            probe: fixture,
            updateChecker: fixture,
            environmentConfigurator: fixture,
            systemAuthorizer: fixture
        )
        let tool = try #require(DevelopmentTool.catalog.first { $0.id == "git-lfs" })
        developerTools.select(tool)
        developerTools.install(tool)
        try await waitUntil { developerTools.status(for: tool).state == .actionRequired }

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

        if let outputPath = ProcessInfo.processInfo.environment["GITGATTO_AUTHORIZATION_UI_SNAPSHOT_PATH"] {
            let data = try #require(representation.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
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

    @Test("Agent success text cannot override a failed local upgrade verification")
    @MainActor
    func rejectsUnverifiedAgentUpgradeSuccess() async throws {
        let fixture = DevelopmentToolInstallFixture()
        let tool = try #require(DevelopmentTool.catalog.first { $0.id == "git-lfs" })
        await fixture.seedInstalled(tool.id)
        await fixture.keepInstalledVersionDuringUpgrade()
        let model = DeveloperToolsViewModel(
            installer: fixture,
            probe: fixture,
            updateChecker: fixture,
            environmentConfigurator: fixture
        )

        model.refresh()
        try await waitUntil { model.status(for: tool).updateAvailability == .available }
        model.upgrade(tool)
        try await waitUntil { model.status(for: tool).state == .actionRequired }

        let status = model.status(for: tool)
        #expect(status.updateAvailability == .available)
        #expect(status.retryOperation == .upgrade)
        #expect(status.result == "Upgrade completed successfully")
        #expect(status.detail == L10n.format(
            "developer_tools.upgrade.still_outdated",
            "3.7.1",
            "3.8.0"
        ))
    }

    @Test("Incomplete Agent configuration remains actionable after a verified upgrade")
    @MainActor
    func keepsIncompleteConfigurationActionable() async throws {
        let fixture = DevelopmentToolInstallFixture()
        let tool = try #require(DevelopmentTool.catalog.first { $0.id == "git-lfs" })
        await fixture.seedInstalled(tool.id)
        await fixture.requireUserConfigurationAction()
        let model = DeveloperToolsViewModel(
            installer: fixture,
            probe: fixture,
            updateChecker: fixture,
            environmentConfigurator: fixture
        )

        model.refresh()
        try await waitUntil { model.status(for: tool).updateAvailability == .available }
        model.upgrade(tool)
        try await waitUntil { model.status(for: tool).state == .actionRequired }

        let status = model.status(for: tool)
        #expect(status.isInstalled)
        #expect(status.updateAvailability == .current)
        #expect(status.retryOperation == .upgrade)
        #expect(status.detail == L10n.text("developer_tools.configuration.action_required"))
    }

    @Test("Agent operations run in bounded parallel lanes and continue the queue")
    @MainActor
    func runsBoundedConcurrentInstallQueue() async throws {
        let fixture = ConcurrentDevelopmentToolFixture()
        let tools = Array(DevelopmentTool.catalog.filter { $0.homebrewFormula != nil }.prefix(4))
        #expect(tools.count == 4)
        let model = DeveloperToolsViewModel(
            installer: fixture,
            probe: fixture,
            updateChecker: fixture,
            environmentConfigurator: fixture,
            systemAuthorizer: fixture,
            maximumConcurrentOperations: 2
        )

        tools.forEach(model.install)
        try await waitUntil {
            model.activeOperationCount == 2 && model.queuedOperations.count == 2
        }
        try await waitUntilAsync { await fixture.peakConcurrency == 2 }

        #expect(model.installQueueCount == 4)
        #expect(await fixture.peakConcurrency == 2)
        let firstActiveID = try #require(await fixture.activeToolIDs.first)
        await fixture.release(firstActiveID)
        try await waitUntil {
            model.activeOperationCount == 2
                && model.queuedOperations.count == 1
        }
        try await waitUntilAsync { await fixture.startedToolIDs.count == 3 }

        #expect(await fixture.startedToolIDs.count == 3)
        for _ in 0..<8 where model.activeOperationCount > 0 || !model.queuedOperations.isEmpty {
            await fixture.releaseAll()
            try await Task.sleep(for: .milliseconds(30))
        }
        try await waitUntil {
            tools.allSatisfy { model.status(for: $0).state == .installed }
        }
        #expect(await fixture.peakConcurrency == 2)
    }

    @Test("Available upgrades support select all and batch queueing")
    @MainActor
    func selectsAndQueuesBatchUpgrades() async throws {
        let fixture = ConcurrentDevelopmentToolFixture()
        let tools = Array(DevelopmentTool.catalog.filter { $0.homebrewFormula != nil }.prefix(5))
        await fixture.seedInstalled(Set(tools.map(\.id)))
        let model = DeveloperToolsViewModel(
            installer: fixture,
            probe: fixture,
            updateChecker: fixture,
            environmentConfigurator: fixture,
            systemAuthorizer: fixture,
            maximumConcurrentOperations: 3
        )

        model.refresh()
        try await waitUntil { model.updateCount == tools.count }
        model.changeCategory(.updates)
        model.selectAllVisibleUpgrades()
        #expect(model.selectedUpgradeCount == tools.count)
        #expect(model.isAllVisibleUpgradesSelected)

        model.upgradeSelectedTools()
        try await waitUntil {
            model.activeOperationCount == 3 && model.queuedOperations.count == 2
        }
        #expect(model.selectedUpgradeCount == 0)
        #expect(model.upgradeQueueCount == tools.count)
        #expect(Set(model.activeOperations.values.map(\.operation)) == [.upgrade])

        for _ in 0..<8 where model.activeOperationCount > 0 || !model.queuedOperations.isEmpty {
            await fixture.releaseAll()
            try await Task.sleep(for: .milliseconds(30))
        }
        try await waitUntil {
            tools.allSatisfy {
                model.status(for: $0).updateAvailability == .current
                    && model.status(for: $0).state == .installed
            }
        }
        #expect(await fixture.peakConcurrency == 3)
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
            [ -z "$4" ] || { printf 'unexpected package arguments' >&2; exit 41; }
            printf 'git-lfs 3.7.1\\npython@3.14 3.14.0\\n'
            ;;
          outdated)
            [ -z "$3" ] || { printf '==> Auto-updating Homebrew\\n' >&2; exit 42; }
            [ "$HOMEBREW_NO_ENV_HINTS" = "1" ] || { printf 'environment hints were not disabled' >&2; exit 43; }
            printf '==> Auto-updated Homebrew!\\n' >&2
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

    @MainActor
    private func waitUntilAsync(
        timeout: Duration = .seconds(60),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for asynchronous developer tool state")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private actor ConcurrentDevelopmentToolFixture:
    CodexServing,
    DevelopmentToolProbing,
    DevelopmentToolUpdateChecking,
    DevelopmentToolEnvironmentConfiguring,
    DevelopmentToolSystemAuthorizing
{
    private(set) var startedToolIDs: [String] = []
    private(set) var activeToolIDs: Set<String> = []
    private(set) var peakConcurrency = 0
    private var installedToolIDs: Set<String> = []
    private var upgradedToolIDs: Set<String> = []
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]

    func seedInstalled(_ toolIDs: Set<String>) {
        installedToolIDs.formUnion(toolIDs)
    }

    func release(_ toolID: String) {
        waiters.removeValue(forKey: toolID)?.resume()
    }

    func releaseAll() {
        let continuations = Array(waiters.values)
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }

    func probe() async -> CodexAvailability { .unavailable }

    func probe(_ tool: DevelopmentTool) async -> DevelopmentToolProbeResult {
        let installed = installedToolIDs.contains(tool.id)
        let upgraded = upgradedToolIDs.contains(tool.id)
        return DevelopmentToolProbeResult(
            isInstalled: installed,
            version: installed ? (upgraded ? "2.0.0" : "1.0.0") : nil,
            executableURL: installed
                ? URL(fileURLWithPath: "/Users/fixture/.local/bin/\(tool.executableCandidates[0])")
                : nil
        )
    }

    func checkUpdates(for tools: [DevelopmentTool]) async -> [String: DevelopmentToolUpdateResult] {
        Dictionary(uniqueKeysWithValues: tools.map { tool in
            let installed = installedToolIDs.contains(tool.id)
            let upgraded = upgradedToolIDs.contains(tool.id)
            return (
                tool.id,
                DevelopmentToolUpdateResult(
                    availability: installed ? (upgraded ? .current : .available) : .unavailable,
                    installedVersion: installed ? (upgraded ? "2.0.0" : "1.0.0") : nil,
                    latestVersion: installed ? "2.0.0" : nil,
                    packageName: installed ? tool.homebrewFormula : nil,
                    isPinned: false,
                    detail: nil
                )
            )
        })
    }

    func configure(executableURL: URL) async throws -> DevelopmentToolEnvironmentConfiguration {
        .unchanged
    }

    func request(for tool: DevelopmentTool) async -> DevelopmentToolSystemAuthorizationRequest? {
        nil
    }

    func authorize(_ request: DevelopmentToolSystemAuthorizationRequest) async throws {}

    func installDevelopmentTool(
        _ tool: DevelopmentTool,
        progress: @escaping @Sendable (AgentInstallProgress) async -> Void
    ) async throws -> CodexRunResult {
        await progress(AgentInstallProgress(.preparing))
        try await waitForRelease(tool.id)
        activeToolIDs.remove(tool.id)
        try Task.checkCancellation()
        installedToolIDs.insert(tool.id)
        await progress(AgentInstallProgress(.installing))
        return CodexRunResult(response: "Installed", commandCount: 1, fileChangeCount: 0)
    }

    func upgradeDevelopmentTool(
        _ tool: DevelopmentTool,
        packageName: String,
        installedVersion: String?,
        latestVersion: String?,
        progress: @escaping @Sendable (AgentInstallProgress) async -> Void
    ) async throws -> CodexRunResult {
        await progress(AgentInstallProgress(.preparing))
        try await waitForRelease(tool.id)
        activeToolIDs.remove(tool.id)
        try Task.checkCancellation()
        upgradedToolIDs.insert(tool.id)
        await progress(AgentInstallProgress(.installing))
        return CodexRunResult(response: "Upgraded", commandCount: 1, fileChangeCount: 0)
    }

    private func waitForRelease(_ toolID: String) async throws {
        startedToolIDs.append(toolID)
        activeToolIDs.insert(toolID)
        peakConcurrency = max(peakConcurrency, activeToolIDs.count)
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters[toolID] = continuation
            }
        } onCancel: {
            Task { await self.release(toolID) }
        }
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

    func cancel() async {
        releaseAll()
    }
}

private actor DevelopmentToolInstallFixture:
    CodexServing,
    DevelopmentToolProbing,
    DevelopmentToolUpdateChecking,
    DevelopmentToolEnvironmentConfiguring,
    DevelopmentToolSystemAuthorizing
{
    private(set) var installedToolIDs: [String] = []
    private(set) var upgradedToolIDs: [String] = []
    private(set) var configuredExecutableNames: [String] = []
    private(set) var authorizationCount = 0
    private(set) var installAttemptCount = 0
    private var requiresSystemAuthorization = false
    private var isSystemAuthorized = false
    private var cancelsAuthorization = false
    private var reportsUserConfigurationAction = false
    private var keepsInstalledVersionDuringUpgrade = false

    func seedInstalled(_ toolID: String) {
        installedToolIDs = [toolID]
    }

    func requireSystemAuthorization(cancelFirstRequest: Bool = false) {
        requiresSystemAuthorization = true
        cancelsAuthorization = cancelFirstRequest
    }

    func allowSystemAuthorization() {
        cancelsAuthorization = false
    }

    func requireUserConfigurationAction() {
        reportsUserConfigurationAction = true
    }

    func keepInstalledVersionDuringUpgrade() {
        keepsInstalledVersionDuringUpgrade = true
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

    func request(for tool: DevelopmentTool) async -> DevelopmentToolSystemAuthorizationRequest? {
        guard requiresSystemAuthorization, !isSystemAuthorized else { return nil }
        return DevelopmentToolSystemAuthorizationRequest(
            toolName: tool.name,
            homebrewPrefix: URL(fileURLWithPath: "/usr/local", isDirectory: true),
            repairDirectories: [URL(fileURLWithPath: "/usr/local/Cellar", isDirectory: true)]
        )
    }

    func authorize(_ request: DevelopmentToolSystemAuthorizationRequest) async throws {
        authorizationCount += 1
        if cancelsAuthorization {
            throw DevelopmentToolSystemAuthorizationError.cancelled
        }
        isSystemAuthorized = true
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
        installAttemptCount += 1
        await progress(AgentInstallProgress(.preparing))
        await progress(AgentInstallProgress(.inspecting))
        await progress(AgentInstallProgress(.installing))
        if requiresSystemAuthorization, !isSystemAuthorized {
            return CodexRunResult(
                response: "Homebrew permission denied for /usr/local/Cellar",
                commandCount: 1,
                fileChangeCount: 0
            )
        }
        if !installedToolIDs.contains(tool.id) {
            installedToolIDs.append(tool.id)
        }
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
        if !keepsInstalledVersionDuringUpgrade {
            upgradedToolIDs.append(tool.id)
        }
        return CodexRunResult(
            response: keepsInstalledVersionDuringUpgrade
                ? "Upgrade completed successfully"
                : "Upgraded and verified",
            commandCount: 2,
            fileChangeCount: 0,
            requiresUserAction: reportsUserConfigurationAction
        )
    }

    func cancel() async {}
}

private actor AuthorizationCommandRecorder {
    private(set) var commands: [String] = []
    private(set) var prompts: [String] = []

    func record(command: String, prompt: String) {
        commands.append(command)
        prompts.append(prompt)
    }
}
