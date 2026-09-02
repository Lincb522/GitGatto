import CoreServices
import Foundation

final class RepositoryChangeMonitor: @unchecked Sendable {
    private let rootPath: String
    private let callbackQueue = DispatchQueue(
        label: "dev.gitgatto.repository-change-monitor",
        qos: .utility
    )
    private let onChange: @Sendable () -> Void
    private let includesGitMetadata: Bool
    private var stream: FSEventStreamRef?

    init(
        repositoryURL: URL,
        includesGitMetadata: Bool = true,
        onChange: @escaping @Sendable () -> Void
    ) {
        rootPath = repositoryURL.standardizedFileURL.path
        self.includesGitMetadata = includesGitMetadata
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }
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
        ) else { return }
        stream = createdStream
        FSEventStreamSetDispatchQueue(createdStream, callbackQueue)
        FSEventStreamStart(createdStream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
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
        let relativePath = path.hasPrefix(rootPath)
            ? String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : path
        guard !relativePath.isEmpty, relativePath != ".DS_Store" else { return false }
        if relativePath == ".git" || relativePath.hasPrefix(".git/") {
            guard includesGitMetadata else { return false }
        }
        return !relativePath.hasPrefix(".git/objects/")
            && !relativePath.hasPrefix(".git/logs/")
            && relativePath != ".git/FETCH_HEAD"
    }
}
