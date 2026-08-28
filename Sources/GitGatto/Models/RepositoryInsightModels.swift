import Foundation

struct RepositoryFileRecord: Identifiable, Sendable, Hashable {
    let path: String

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var directory: String {
        let value = (path as NSString).deletingLastPathComponent
        return value == "." ? "" : value
    }
    var fileExtension: String { (path as NSString).pathExtension.lowercased() }
}

struct FileRevisionRecord: Identifiable, Sendable, Hashable {
    let hash: String
    let shortHash: String
    let author: String
    let authorEmail: String
    let date: Date
    let subject: String
    let path: String

    var id: String { hash }
}

struct FileVersionDocument: Sendable {
    let path: String
    let content: String?
    let isBinary: Bool
    let diff: DiffDocument
}

struct FileBlameLine: Identifiable, Sendable, Equatable {
    let commitHash: String
    let originalLineNumber: Int
    let finalLineNumber: Int
    let author: String
    let authorEmail: String
    let date: Date?
    let summary: String
    let sourcePath: String
    let text: String

    var id: String { "\(finalLineNumber):\(commitHash)" }
    var shortHash: String { String(commitHash.prefix(8)) }
    var isUncommitted: Bool { commitHash.allSatisfy { $0 == "0" } }
}

enum FileTimelineDetailMode: String, CaseIterable, Identifiable, Sendable {
    case content
    case changes
    case blame

    var id: String { rawValue }
}

enum RepositoryDiagnosticStatus: Sendable, Equatable {
    case passed
    case attention
    case failed
    case unavailable
}

struct GitHookRecord: Identifiable, Sendable, Equatable {
    let name: String
    let url: URL
    let isExecutable: Bool
    let isSymbolicLink: Bool
    let size: Int64

    var id: String { url.standardizedFileURL.path }
}

struct RepositoryDiagnostics: Sendable, Equatable {
    let generatedAt: Date
    let gitExecutablePath: String
    let gitVersion: String
    let repositoryRoot: URL
    let objectDatabaseHealthy: Bool
    let objectDatabaseMessage: String?
    let userName: String?
    let userEmail: String?
    let lfsVersion: String?
    let lfsError: String?
    let usesLFS: Bool
    let lfsFilterConfigured: Bool
    let lfsTrackedFileCount: Int
    let hooksDirectory: URL
    let hooksDirectoryExists: Bool
    let hooks: [GitHookRecord]

    var gitStatus: RepositoryDiagnosticStatus {
        objectDatabaseHealthy ? .passed : .failed
    }

    var identityStatus: RepositoryDiagnosticStatus {
        userName == nil || userEmail == nil ? .attention : .passed
    }

    var lfsStatus: RepositoryDiagnosticStatus {
        if usesLFS, lfsVersion == nil { return .failed }
        if usesLFS, !lfsFilterConfigured { return .attention }
        return lfsVersion == nil ? .unavailable : .passed
    }

    var hooksStatus: RepositoryDiagnosticStatus {
        if hooks.contains(where: { !$0.isExecutable }) { return .attention }
        if usesLFS, lfsVersion != nil, !hooks.contains(where: { $0.name == "pre-push" }) {
            return .attention
        }
        return .passed
    }

    var attentionCount: Int {
        [gitStatus, identityStatus, lfsStatus, hooksStatus].filter {
            $0 == .attention || $0 == .failed
        }.count
    }
}

enum RepositoryDiagnosticOperation: Sendable, Equatable {
    case refresh
    case configureLFS
    case repairHook
}
