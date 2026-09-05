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
    private let filtersIgnoredPaths: Bool
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var pendingPaths = Set<String>()
    private var filterTask: Task<Void, Never>?
    private var filterGeneration = UUID()
    private var stream: FSEventStreamRef?
    private var watchdog: DispatchSourceTimer?
    /// Only read or written on `callbackQueue`; `start`/`stop` never touch it directly.
    private var watchdogFingerprint: RepositoryWatchdogFingerprint?

    init(
        repositoryURL: URL,
        includesGitMetadata: Bool = true,
        includesGitObjectChanges: Bool = false,
        filtersIgnoredPaths: Bool = false,
        onChange: @escaping @Sendable () -> Void
    ) {
        rootPath = Self.fileSystemPath(repositoryURL)
        self.includesGitMetadata = includesGitMetadata
        self.includesGitObjectChanges = includesGitObjectChanges
        self.filtersIgnoredPaths = filtersIgnoredPaths
        callbackQueue.setSpecific(key: queueKey, value: 1)
        self.onChange = onChange
    }

    private static func fileSystemPath(_ url: URL) -> String {
        // FSEvents reports /private/var even when Foundation preserves the /var alias.
        if let resolved = url.withUnsafeFileSystemRepresentation({ path in
            path.flatMap { realpath($0, nil) }
        }) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        return url.standardizedFileURL.path
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
        let cancelFilter = {
            self.filterGeneration = UUID()
            self.filterTask?.cancel()
            self.filterTask = nil
            self.pendingPaths.removeAll()
        }
        if DispatchQueue.getSpecific(key: queueKey) != nil { cancelFilter() }
        else { callbackQueue.sync(execute: cancelFilter) }
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
        var requiresImmediateRefresh = false
        for index in 0 ..< min(eventCount, paths.count) {
            let path = paths[index]
            let flags = eventFlags[index]
            guard shouldRefresh(path: path, flags: flags) else { continue }
            let relative = relativePath(path)
            if !filtersIgnoredPaths || relative == nil || relative == ".git"
                || relative?.hasPrefix(".git/") == true
                || flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged) != 0 {
                requiresImmediateRefresh = true
            } else if let relative {
                pendingPaths.insert(relative)
            }
        }
        if requiresImmediateRefresh { onChange() }
        filterPendingPaths()
    }

    private func relativePath(_ path: String) -> String? {
        guard path.hasPrefix(rootPath + "/") else { return nil }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func shouldRefresh(path: String, flags: FSEventStreamEventFlags) -> Bool {
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged) != 0 {
            return true
        }
        guard let relative = relativePath(path), relative != ".DS_Store" else { return false }
        if relative == ".git" || relative.hasPrefix(".git/") {
            guard includesGitMetadata else { return false }
            if filtersIgnoredPaths {
                if relative.hasSuffix(".lock") || relative == ".git/FETCH_HEAD"
                    || relative.hasPrefix(".git/logs/") { return false }
                if relative == ".git" {
                    return flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed) != 0
                }
            }
            if includesGitObjectChanges { return true }
        }
        return !relative.hasPrefix(".git/objects/")
            && !relative.hasPrefix(".git/logs/")
            && relative != ".git/FETCH_HEAD"
    }

    private func filterPendingPaths() {
        guard filterTask == nil, !pendingPaths.isEmpty else { return }
        let paths = pendingPaths.sorted()
        pendingPaths.removeAll()
        let generation = filterGeneration
        let root = rootPath
        filterTask = Task { [weak self] in
            let shouldNotify: Bool
            do {
                let output = try await ExternalProcessRunner().run(
                    executable: URL(fileURLWithPath: "/usr/bin/git"),
                    arguments: ["--no-optional-locks", "-C", root, "check-ignore", "--stdin", "-z"],
                    environment: ["LC_ALL": "C", "GIT_TERMINAL_PROMPT": "0"],
                    input: Data((paths.joined(separator: "\0") + "\0").utf8),
                    acceptedExitCodes: [0, 1], timeout: .seconds(5)
                )
                let ignored = Set(output.standardOutput.split(separator: 0).map { String(decoding: $0, as: UTF8.self) })
                shouldNotify = paths.contains { !ignored.contains($0) }
            } catch is CancellationError { return }
            catch { shouldNotify = true }
            guard !Task.isCancelled, let self else { return }
            self.callbackQueue.async { [weak self] in
                guard let self, self.filterGeneration == generation else { return }
                self.filterTask = nil
                if shouldNotify { self.onChange() }
                self.filterPendingPaths()
            }
        }
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
            entries: paths.map {
                RepositoryWatchdogEntry(path: $0, identityOnly: filtersIgnoredPaths && ($0 == rootPath || $0 == "\(rootPath)/.git"))
            }
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

    init(path: String, identityOnly: Bool = false) {
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
        size = identityOnly ? 0 : Int64(value.st_size)
        modifiedSeconds = identityOnly ? 0 : Int64(value.st_mtimespec.tv_sec)
        modifiedNanoseconds = identityOnly ? 0 : Int64(value.st_mtimespec.tv_nsec)
        changedSeconds = identityOnly ? 0 : Int64(value.st_ctimespec.tv_sec)
        changedNanoseconds = identityOnly ? 0 : Int64(value.st_ctimespec.tv_nsec)
    }
}
