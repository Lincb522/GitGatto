import Foundation
import Sparkle
import Testing
@testable import GitGatto

@Suite("App update configuration")
struct AppUpdateManagerTests {
    @Test("Uses the HTTPS GitHub release feed")
    @MainActor
    func validatesFeedConfiguration() {
        #expect(AppUpdateManager.hasUpdateConfiguration([
            "SUFeedURL": "https://github.com/Lincb522/GitGatto/releases/latest/download/appcast.xml"
        ]))

        #expect(!AppUpdateManager.hasUpdateConfiguration([
            "SUFeedURL": "http://github.com/Lincb522/GitGatto/releases/latest/download/appcast.xml"
        ]))

        #expect(!AppUpdateManager.hasUpdateConfiguration([:]))
    }

    @Test("Treats Sparkle's no-update result as the current version")
    @MainActor
    func classifiesNoUpdateResult() {
        let noUpdate = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.noUpdateError.rawValue)
        )
        #expect(AppUpdateManager.stateAfterAborting(with: noUpdate) == .current)

        let failure = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.downloadError.rawValue),
            userInfo: [NSLocalizedDescriptionKey: "Download failed"]
        )
        #expect(
            AppUpdateManager.stateAfterAborting(with: failure)
                == .failed(message: "Download failed")
        )
    }

    @Test("Retries until Sparkle's progress job is registered")
    func retriesUntilProgressJobIsRegistered() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let argumentsFile = directory.appendingPathComponent("arguments")
        let attemptsFile = directory.appendingPathComponent("attempts")
        let launchctl = directory.appendingPathComponent("launchctl")
        let script = """
        #!/bin/sh
        attempts=0
        if [ -f "\(attemptsFile.path)" ]; then
          attempts=$(cat "\(attemptsFile.path)")
        fi
        attempts=$((attempts + 1))
        printf '%s' "$attempts" > "\(attemptsFile.path)"
        if [ "$attempts" -lt 2 ]; then
          exit 1
        fi
        printf '%s\\n' "$@" > "\(argumentsFile.path)"
        """
        try script.write(to: launchctl, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: launchctl.path
        )

        let recovery = SparkleProgressLaunchRecovery(
            bundleIdentifier: "dev.gitgatto.client",
            userID: 501,
            launchctlURL: launchctl,
            retryCount: 2,
            retryDelay: .zero
        )
        await recovery.run()

        #expect(try String(contentsOf: attemptsFile, encoding: .utf8) == "2")
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        #expect(arguments == [
            "kickstart",
            "-k",
            "gui/501/dev.gitgatto.client-sparkle-progress"
        ])
    }
}
