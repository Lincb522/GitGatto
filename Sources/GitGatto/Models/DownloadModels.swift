import Foundation

enum AppDownloadState: String, Codable, Sendable {
    case queued
    case downloading
    case paused
    case completed
    case failed
    case cancelled
    case installing
    case installed
}

struct AppDownloadRecord: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let repositoryName: String
    let assetID: Int64
    let fileName: String
    let sourceURL: URL
    let expectedBytes: Int64
    var destinationURL: URL?
    var state: AppDownloadState
    var progress: Double
    var receivedBytes: Int64
    var errorMessage: String?
    let createdAt: Date
    var updatedAt: Date

    var canInstallOnMac: Bool {
        guard state == .completed else { return false }
        let lower = fileName.lowercased()
        return lower.hasSuffix(".dmg") || lower.hasSuffix(".pkg") || lower.hasSuffix(".zip")
    }

    var needsAgentInstaller: Bool {
        guard state == .completed else { return false }
        return !canInstallOnMac
    }
}
