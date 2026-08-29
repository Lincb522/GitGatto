import Foundation

struct SparkleProgressLaunchRecovery {
    private let bundleIdentifier: String
    private let userID: uid_t
    private let launchctlURL: URL
    private let retryCount: Int
    private let retryDelay: Duration

    init(
        bundleIdentifier: String,
        userID: uid_t = getuid(),
        launchctlURL: URL = URL(fileURLWithPath: "/bin/launchctl"),
        retryCount: Int = 80,
        retryDelay: Duration = .milliseconds(100)
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.userID = userID
        self.launchctlURL = launchctlURL
        self.retryCount = retryCount
        self.retryDelay = retryDelay
    }

    var jobTarget: String {
        "gui/\(userID)/\(bundleIdentifier)-sparkle-progress"
    }

    func run() async {
        guard #available(macOS 26.0, *) else { return }

        for _ in 0 ..< retryCount {
            guard !Task.isCancelled else { return }
            if await kickstart() {
                return
            }
            try? await Task.sleep(for: retryDelay)
        }
    }

    private func kickstart() async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = launchctlURL
            process.arguments = ["kickstart", "-k", jobTarget]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { completedProcess in
                continuation.resume(returning: completedProcess.terminationStatus == 0)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}
