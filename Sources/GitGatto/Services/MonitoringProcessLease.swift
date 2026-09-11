import Darwin
import Foundation

/// Keep the inode in place and close on exec so Git children cannot retain the monitoring lease.
final class MonitoringProcessLease {
    private let descriptor: Int32
    private(set) var isHeld = false

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    deinit { close(descriptor) }

    func acquire() throws -> Bool {
        if isHeld { return true }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { isHeld = true; return true }
        guard errno == EWOULDBLOCK else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return false
    }

    func release() {
        guard isHeld else { return }
        flock(descriptor, LOCK_UN)
        isHeld = false
    }

    static var rootURL: URL {
        BackgroundMonitoringService.defaultRootURL().appendingPathComponent("Process", isDirectory: true)
    }
}

@MainActor
enum ForegroundMonitoringSession {
    private static var presence: MonitoringProcessLease?
    private static var runtime: MonitoringProcessLease?
    private static var preparationError: (any Error)?
    private(set) static var isApplicationProcess = false

    static func prepare() {
        isApplicationProcess = true
        do {
            let lease = try MonitoringProcessLease(url: MonitoringProcessLease.rootURL.appendingPathComponent("foreground.lock"))
            guard try lease.acquire() else { throw CocoaError(.fileLocking) }
            presence = lease
            runtime = try MonitoringProcessLease(url: MonitoringProcessLease.rootURL.appendingPathComponent("runtime.lock"))
        } catch { preparationError = error }
    }

    static func acquireRuntime() async throws {
        guard isApplicationProcess else { return }
        if let preparationError { throw preparationError }
        guard let runtime else { throw CocoaError(.fileLocking) }
        let deadline = ContinuousClock.now + .seconds(45)
        while try !runtime.acquire() {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw CocoaError(.fileLocking) }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
