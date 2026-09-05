import AppKit
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Rendering measurements", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["GITGATTO_RENDER_MEASUREMENTS"] == "1"))
struct RenderingPerformanceTests {
    @MainActor
    @Test("Measures repeated palette resolution and large code surface updates")
    func measureRendering() throws {
        let clock = ContinuousClock()
        var palettes: [AppPalette] = []
        let paletteDuration = clock.measure {
            for index in 0..<20_000 {
                palettes.append(AppPalette(index.isMultiple(of: 2) ? .light : .dark, theme: .softGlass))
            }
        }
        #expect(palettes.count == 20_000)
        print("RENDER_MEASURE palette_20000=\(paletteDuration)")

        let content = (0..<20_000).map { "let value\($0) = \($0) // source line" }.joined(separator: "\n")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        let hosting = NSHostingView(rootView: CodeDocumentView(content: content, fileName: "Example.swift"))
        window.contentView = hosting
        defer { window.orderOut(nil); window.contentView = nil }
        let initialDuration = clock.measure {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
        }
        print("RENDER_MEASURE code_initial=\(initialDuration)")
        var updateDurations: [Double] = []
        for index in 0..<20 {
            let duration = clock.measure {
                hosting.rootView = CodeDocumentView(
                    content: content, fileName: "Example.swift", showsStatusBar: index.isMultiple(of: 2)
                )
                hosting.layoutSubtreeIfNeeded()
                hosting.displayIfNeeded()
            }
            let components = duration.components
            updateDurations.append(Double(components.seconds) + Double(components.attoseconds) / 1e18)
        }
        print("RENDER_MEASURE code_updates_seconds=\(updateDurations)")

        func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        let scrollView = try #require(scrollViews(in: hosting).first)
        let documentView = try #require(scrollView.documentView)
        #expect(documentView.bounds.height > scrollView.contentSize.height)
        let scrollDuration = clock.measure {
            for index in 1...20 {
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: index * 100))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                hosting.layoutSubtreeIfNeeded()
                hosting.displayIfNeeded()
            }
        }
        #expect(scrollView.contentView.bounds.minY > 0)
        print("RENDER_MEASURE code_scroll_20=\(scrollDuration)")
    }

    @Test("Compares source preparation in the same process")
    func compareSourcePreparation() {
        let content = (0..<20_000).map { "let value\($0) = \($0) // source line" }.joined(separator: "\n")
        let cache = CodeLineCache()
        let clock = ContinuousClock()
        var uncached: Duration = .zero
        var cached: Duration = .zero
        for _ in 0..<25 {
            var oldLines: [String] = []
            var newLines: [String] = []
            uncached += clock.measure {
                oldLines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            }
            cached += clock.measure { newLines = cache.lines(for: content) }
            #expect(oldLines == newLines)
        }
        print("RENDER_MEASURE same_process_uncached_25=\(uncached) cached_25=\(cached)")
    }
}
