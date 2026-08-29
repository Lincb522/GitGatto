import Foundation
import UniformTypeIdentifiers

enum RepositoryMediaKind: Sendable, Hashable {
    case image
    case video
    case svg

    init?(fileName: String) {
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        guard !fileExtension.isEmpty else { return nil }
        if fileExtension == "svg" {
            self = .svg
            return
        }
        if Self.videoExtensions.contains(fileExtension) {
            self = .video
            return
        }
        if Self.imageExtensions.contains(fileExtension) {
            self = .image
            return
        }
        guard let type = UTType(filenameExtension: fileExtension) else { return nil }
        if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) {
            self = .video
        } else if type.conforms(to: .image) {
            self = .image
        } else {
            return nil
        }
    }

    private static let imageExtensions: Set<String> = [
        "apng", "avif", "bmp", "cr2", "cr3", "dng", "exr", "gif", "heic", "heif",
        "ico", "jp2", "jpeg", "jpg", "jxl", "nef", "orf", "png", "psd", "raf",
        "raw", "tga", "tif", "tiff", "webp"
    ]

    private static let videoExtensions: Set<String> = [
        "264", "265", "3g2", "3gp", "amv", "asf", "avi", "bik", "bink", "dav",
        "divx", "dv", "f4v", "flv", "h264", "h265", "hevc", "ivf", "m1v", "m2p",
        "m2t", "m2ts", "m2v", "m4v", "mj2", "mjpeg", "mjpg", "mkv", "mod", "mov",
        "mp4", "mpe", "mpeg", "mpg", "mpv", "mts", "mxf", "nsv", "nut", "ogm",
        "ogv", "qt", "r3d", "rec", "rm", "rmvb", "roq", "smk", "str", "tod", "trp",
        "ts", "ty", "vob", "webm", "wm", "wmv", "wtv", "xesc", "y4m", "yuv"
    ]
}

struct RepositoryMediaItem: Identifiable, Sendable, Hashable {
    let path: String

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var kind: RepositoryMediaKind? { RepositoryMediaKind(fileName: path) }
}

enum RepositoryMediaCache {
    static func store(_ data: Data, key: String, path: String) throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GitGatto/RepositoryPreviews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileExtension = (path as NSString).pathExtension
        let url = directory
            .appendingPathComponent(StableHash.hex(key))
            .appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }
}

enum RepositoryVideoTranscoder {
    static func executableURL() -> URL? {
        let fileManager = FileManager.default
        let pathDirectories = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let candidates = pathDirectories.map { "\($0)/ffmpeg" } + [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    static func playableURL(for sourceURL: URL) async throws -> URL {
        guard sourceURL.isFileURL, let executableURL = executableURL() else {
            throw RepositoryVideoTranscodeError.ffmpegUnavailable
        }
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let cacheKey = "\(sourceURL.standardizedFileURL.path):\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GitGatto/VideoPlayback", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory
            .appendingPathComponent(StableHash.hex(cacheKey))
            .appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        return try await RepositoryVideoTranscodeInvocation(
            executableURL: executableURL,
            sourceURL: sourceURL,
            destinationURL: destination
        ).run()
    }
}

private enum RepositoryVideoTranscodeError: LocalizedError {
    case ffmpegUnavailable
    case failed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .ffmpegUnavailable: "ffmpeg is not available."
        case let .failed(message): message
        case .timedOut: "Video conversion timed out."
        }
    }
}

private final class RepositoryVideoTranscodeInvocation: @unchecked Sendable {
    private let executableURL: URL
    private let sourceURL: URL
    private let destinationURL: URL
    private let process = Process()
    private let lock = NSLock()
    private var started = false
    private var cancelled = false

    init(executableURL: URL, sourceURL: URL, destinationURL: URL) {
        self.executableURL = executableURL
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
    }

    func run() async throws -> URL {
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { [self] in
                try runBlocking()
            }.value
        } onCancel: {
            self.cancel()
        }
    }

    private func runBlocking() throws -> URL {
        let temporaryURL = destinationURL
            .deletingPathExtension()
            .appendingPathExtension("partial.mp4")
        try? FileManager.default.removeItem(at: temporaryURL)
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = [
            "-hide_banner", "-loglevel", "error", "-y",
            "-i", sourceURL.path,
            "-map", "0:v:0?", "-map", "0:a:0?",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-movflags", "+faststart",
            temporaryURL.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }

        lock.lock()
        if cancelled {
            lock.unlock()
            throw CancellationError()
        }
        do {
            try process.run()
            started = true
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }

        if completion.wait(timeout: .now() + 300) == .timedOut {
            process.terminate()
            try? FileManager.default.removeItem(at: temporaryURL)
            throw RepositoryVideoTranscodeError.timedOut
        }
        if cancelled {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw CancellationError()
        }
        guard process.terminationStatus == 0 else {
            let message = String(
                decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: temporaryURL)
            throw RepositoryVideoTranscodeError.failed(message)
        }
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let shouldTerminate = started && process.isRunning
        lock.unlock()
        if shouldTerminate { process.terminate() }
    }
}
