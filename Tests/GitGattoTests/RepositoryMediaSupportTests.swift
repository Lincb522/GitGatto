import AVFoundation
import Foundation
import Testing
@testable import GitGatto

@Suite("Repository media")
struct RepositoryMediaSupportTests {
    @Test("Recognizes common and legacy video containers")
    func recognizesVideoContainers() {
        for name in [
            "clip.mp4", "clip.mov", "clip.mkv", "clip.webm", "clip.avi",
            "clip.flv", "clip.mxf", "clip.m2ts", "clip.rmvb", "clip.wmv",
            "clip.h265", "clip.bik", "clip.r3d", "clip.y4m", "clip.wtv"
        ] {
            #expect(RepositoryMediaKind(fileName: name) == .video)
        }
    }

    @Test("Separates raster images and SVG source")
    func recognizesImages() {
        #expect(RepositoryMediaKind(fileName: "cover.webp") == .image)
        #expect(RepositoryMediaKind(fileName: "photo.heic") == .image)
        #expect(RepositoryMediaKind(fileName: "diagram.svg") == .svg)
        #expect(RepositoryMediaKind(fileName: "README.md") == nil)
    }

    @Test("Converts a non-native container into an AVFoundation playable preview", .timeLimit(.minutes(1)))
    func convertsUnsupportedContainer() async throws {
        guard let ffmpeg = RepositoryVideoTranscoder.executableURL() else { return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitGattoVideoTranscodeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("fixture.mkv")
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = ffmpeg
        process.arguments = [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi",
            "-i", "color=c=blue:s=160x90:d=0.2",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", source.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let output = try await RepositoryVideoTranscoder.playableURL(for: source)
        #expect(output.pathExtension == "mp4")
        #expect((try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0)
        #expect((try? await AVURLAsset(url: output).load(.isPlayable)) == true)
    }
}
