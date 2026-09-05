import AppKit
import SwiftUI
import Testing

@MainActor
func verifyCenterRendering<Content: View>(_ content: Content, name: String) async throws {
    let snapshotDirectory = ProcessInfo.processInfo.environment["GITGATTO_CENTERS_SNAPSHOT_DIR"]
    // Run the full bitmap matrix separately from concurrent WebKit integration tests.
    let sizes = snapshotDirectory == nil ? [(700, 620)] : [(700, 620), (1_416, 876)]
    let appearances = snapshotDirectory == nil ? [ColorScheme.light] : [.light, .dark]
    for (width, height) in sizes {
        for scheme in appearances {
            await Task.yield()
            let view = content
                .environment(\.colorScheme, scheme)
                .frame(width: CGFloat(width), height: CGFloat(height))
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            #expect(hosting.bounds.width == CGFloat(width))
            #expect(hosting.bounds.height == CGFloat(height))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            #expect(png.count > 4_096)
            if let path = snapshotDirectory {
                let directory = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let appearance = scheme == .dark ? "dark" : "light"
                try png.write(to: directory.appendingPathComponent("\(name)-\(width)-\(appearance).png"))
            }
        }
    }
}
