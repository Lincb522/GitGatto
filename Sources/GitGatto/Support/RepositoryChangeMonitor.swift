import CoreServices
import Darwin
import Foundation

final class RepositoryChangeMonitor: @unchecked Sendable {
    private let rootPath: String
    private let callbackQueue = DispatchQueue(
        label: "dev.gitgatto.repository-change-monitor",
        qos: .utility
    )
    private let onChange: @Sendable () -> Void
    private let includesGitMetadata: Bool
    private let includesGitObjectChanges: Bool
    private var stream: FSEventStreamRef?
    private var watchdog: DispatchSourceTimer?
    /// Only read or written on `callbackQueue`; `start`/`stop` never touch it directly.
    private var watchdogFingerprint: RepositoryWatchdogFingerprint?

    init(
        repositoryURL: URL,
        includesGitMetadata: Bool = true,
        includesGitObjectChanges: Bool = false,
        onChange: @escaping @Sendable () -> Void
    ) {
        rootPath = repositoryURL.standardizedFileURL.path
        self.includesGitMetadata = includesGitMetadata
        self.includesGitObjectChanges = includesGitObjectChanges
        self.onChange = onChange
    }

    func start() {
        guard stream == nil, watchdog == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot
        )
        guard let createdStream = FSEventStreamCreate(
            nil,
            { _, info, eventCount, eventPaths, eventFlags, _ in
                guard let info else { return }
                let monitor = Unmanaged<RepositoryChangeMonitor>
                    .fromOpaque(info)
                    .takeUnretainedValue()
                monitor.receive(
                    eventCount: eventCount,
                    eventPaths: eventPaths,
                    eventFlags: eventFlags
                )
            },
            &context,
            [rootPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            flags
        ) else {
            startWatchdog()
            return
        }
        stream = createdStream
        FSEventStreamSetDispatchQueue(createdStream, callbackQueue)
        if !FSEventStreamStart(createdStream) {
            FSEventStreamInvalidate(createdStream)
            FSEventStreamRelease(createdStream)
            stream = nil
        }
        startWatchdog()
    }

    func stop() {
        watchdog?.setEventHandler {}
        watchdog?.cancel()
        watchdog = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    deinit {
        stop()
    }

    private func receive(
        eventCount: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
        for index in 0 ..< min(eventCount, paths.count) {
            if shouldRefresh(path: paths[index], flags: eventFlags[index]) {
                onChange()
                return
            }
        }
    }

    private func shouldRefresh(path: String, flags: FSEventStreamEventFlags) -> Bool {
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 {
            return true
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
            return true
        }
        let relativePath = path.hasPrefix(rootPath)
            ? String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : path
        guard !relativePath.isEmpty, relativePath != ".DS_Store" else { return false }
        if relativePath == ".git" || relativePath.hasPrefix(".git/") {
            guard includesGitMetadata else { return false }
            if includesGitObjectChanges {
                return true
            }
        }
        return !relativePath.hasPrefix(".git/objects/")
            && !relativePath.hasPrefix(".git/logs/")
            && relativePath != ".git/FETCH_HEAD"
    }

    private func startWatchdog() {
        // Establish the baseline before returning from start(). Otherwise a Git command issued
        // immediately after opening a repository can race the asynchronous seed and disappear
        // into the first fingerprint instead of producing a change callback.
        callbackQueue.sync {
            watchdogFingerprint = currentWatchdogFingerprint()
        }
        let watchdog = DispatchSource.makeTimerSource(queue: callbackQueue)
        watchdog.schedule(
            deadline: .now() + 1,
            repeating: 1,
            leeway: .milliseconds(150)
        )
        watchdog.setEventHandler { [weak self] in
            guard let self else { return }
            let current = self.currentWatchdogFingerprint()
            defer { self.watchdogFingerprint = current }
            guard current != self.watchdogFingerprint else { return }
            self.onChange()
        }
        self.watchdog = watchdog
        watchdog.resume()
    }

    private func currentWatchdogFingerprint() -> RepositoryWatchdogFingerprint {
        var paths = [rootPath]
        if includesGitMetadata {
            paths.append(contentsOf: [
                "\(rootPath)/.git",
                "\(rootPath)/.git/HEAD",
                "\(rootPath)/.git/index",
                "\(rootPath)/.git/refs",
            ])
        }
        if includesGitObjectChanges {
            paths.append(contentsOf: [
                "\(rootPath)/.git/logs",
                "\(rootPath)/.git/objects",
            ])
        }
        return RepositoryWatchdogFingerprint(
            entries: paths.map(RepositoryWatchdogEntry.init(path:))
        )
    }
}

private struct RepositoryWatchdogFingerprint: Equatable {
    let entries: [RepositoryWatchdogEntry]
}

private struct RepositoryWatchdogEntry: Equatable {
    let exists: Bool
    let device: UInt64
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    init(path: String) {
        var value = stat()
        guard lstat(path, &value) == 0 else {
            exists = false
            device = 0
            inode = 0
            size = 0
            modifiedSeconds = 0
            modifiedNanoseconds = 0
            changedSeconds = 0
            changedNanoseconds = 0
            return
        }
        exists = true
        device = UInt64(value.st_dev)
        inode = UInt64(value.st_ino)
        size = Int64(value.st_size)
        modifiedSeconds = Int64(value.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(value.st_mtimespec.tv_nsec)
        changedSeconds = Int64(value.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(value.st_ctimespec.tv_nsec)
    }
}
