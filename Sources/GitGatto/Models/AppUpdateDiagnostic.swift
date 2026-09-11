import Foundation
import Sparkle

enum AppUpdateStage: String, Equatable, Sendable {
    case checking, downloading, verifying, installing, unknown
}

struct AppUpdateDiagnostic: Equatable {
    let stage: AppUpdateStage
    let detail: String
    var recovery: String { L10n.text("update.recovery.\(stage.rawValue)") }

    @MainActor
    static func make(error: NSError, lastStage: AppUpdateStage) -> Self {
        var stage = lastStage
        var current: NSError? = error
        var seen = Set<ObjectIdentifier>()
        while let item = current, seen.count < 16, seen.insert(ObjectIdentifier(item)).inserted {
            if item.domain == SUSparkleErrorDomain {
                switch item.code {
                case 1...7, 1000, 1002...1007: stage = .checking
                case 2000...2001: stage = .downloading
                case 3000...3002: stage = .verifying
                case 4000...4012: stage = .installing
                default: break
                }
            }
            current = item.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return Self(stage: stage, detail: redact(AppUpdateManager.failureMessage(for: error)))
    }

    static func redact(_ value: String) -> String {
        ProjectCommandOutput.redact(value)
            .replacingOccurrences(of: #"https?://[^\s<>]+"#, with: "[URL]", options: .regularExpression)
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    func report(version: String, build: String) -> String {
        Self.redact("GitGatto \(version) (\(build))\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)\nStage: \(stage.rawValue)\n\(detail)")
    }
}
