import AppKit
import Foundation

enum MacApplicationInstallerError: LocalizedError, Sendable {
    case unsupportedFormat
    case noApplicationFound
    case destinationExists(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: L10n.text("installer.error.unsupported")
        case .noApplicationFound: L10n.text("installer.error.no_app")
        case let .destinationExists(name): L10n.format("installer.error.exists", name)
        case let .commandFailed(message): message
        }
    }
}

actor MacApplicationInstaller {
    private let fileManager: FileManager
    private let applicationsDirectory: URL

    init(fileManager: FileManager = .default, applicationsDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.applicationsDirectory = applicationsDirectory
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    }

    func install(_ archiveURL: URL, replacingExisting: Bool) async throws -> URL {
        let lower = archiveURL.lastPathComponent.lowercased()
        if lower.hasSuffix(".pkg") {
            _ = await MainActor.run { NSWorkspace.shared.open(archiveURL) }
            return archiveURL
        }
        if lower.hasSuffix(".dmg") {
            return try await installDMG(archiveURL, replacingExisting: replacingExisting)
        }
        if lower.hasSuffix(".zip") {
            return try await installZIP(archiveURL, replacingExisting: replacingExisting)
        }
        throw MacApplicationInstallerError.unsupportedFormat
    }

    private func installDMG(_ url: URL, replacingExisting: Bool) async throws -> URL {
        let output = try await run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-plist", url.path])
        let plist = try PropertyListSerialization.propertyList(from: output, format: nil)
        guard let dictionary = plist as? [String: Any],
              let entities = dictionary["system-entities"] as? [[String: Any]],
              let mountPath = entities.compactMap({ $0["mount-point"] as? String }).last else {
            throw MacApplicationInstallerError.commandFailed(L10n.text("installer.error.mount"))
        }
        let mountURL = URL(fileURLWithPath: mountPath, isDirectory: true)
        defer { Task { try? await self.run("/usr/bin/hdiutil", ["detach", mountPath]) } }
        let app = try findApplication(in: mountURL)
        return try copyApplication(app, replacingExisting: replacingExisting)
    }

    private func installZIP(_ url: URL, replacingExisting: Bool) async throws -> URL {
        let temporary = fileManager.temporaryDirectory
            .appendingPathComponent("GitGatto-Install-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporary) }
        _ = try await run("/usr/bin/ditto", ["-x", "-k", url.path, temporary.path])
        let app = try findApplication(in: temporary)
        return try copyApplication(app, replacingExisting: replacingExisting)
    }

    private func findApplication(in root: URL) throws -> URL {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw MacApplicationInstallerError.noApplicationFound }
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
            return url
        }
        throw MacApplicationInstallerError.noApplicationFound
    }

    private func copyApplication(_ app: URL, replacingExisting: Bool) throws -> URL {
        try fileManager.createDirectory(at: applicationsDirectory, withIntermediateDirectories: true)
        let destination = applicationsDirectory.appendingPathComponent(app.lastPathComponent, isDirectory: true)
        if fileManager.fileExists(atPath: destination.path) {
            guard replacingExisting else {
                throw MacApplicationInstallerError.destinationExists(app.lastPathComponent)
            }
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: app, to: destination)
        return destination
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = error
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    let message = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    continuation.resume(throwing: MacApplicationInstallerError.commandFailed(message))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}
