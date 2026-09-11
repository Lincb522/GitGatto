import AppKit
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Issue attachment rendering", .serialized)
@MainActor
struct IssueImageRenderingTests {
    @Test("HTML image loads in the native issue renderer at narrow and wide widths",
          .enabled(if: ProcessInfo.processInfo.environment["GITGATTO_ATTACHMENT_FIXTURE_URL"] != nil),
          .timeLimit(.minutes(1)))
    func rendersIssueImage() async throws {
        let url = try #require(ProcessInfo.processInfo.environment["GITGATTO_ATTACHMENT_FIXTURE_URL"].flatMap(URL.init(string:)))
        let data = try await RemoteImageDataCache.shared.data(for: url)
        #expect(NSImage(data: data) != nil)
        for width in [380, 1000] {
            for scheme in [ColorScheme.light, .dark] {
                let text = """
                功能很完善，但是前端的一些小图标做的不太完善，希望越来越好。
                <img width="872" height="59" alt="Issue attachment" src="\(url.absoluteString)" />
                这是截图后面的文字。A longer reply with a [link](https://example.com/docs).
                """
                let root = ScrollView {
                    ReleaseNotesMarkdownView(text: text, openURL: { _ in })
                        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                }
                .environment(\.colorScheme, scheme)
                .background(scheme == .dark ? Color.black : Color.white)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 320),
                                      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                let hosting = NSHostingView(rootView: root)
                window.contentView = hosting
                window.orderFront(nil)
                defer { window.orderOut(nil); window.contentView = nil }
                let clock = ContinuousClock()
                let deadline = clock.now.advanced(by: .seconds(15))
                var loadedBitmap: NSBitmapImageRep?
                var imageWidth = 0
                var lastBitmap: NSBitmapImageRep?
                while clock.now < deadline {
                    hosting.layoutSubtreeIfNeeded()
                    hosting.displayIfNeeded()
                    let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    lastBitmap = bitmap
                    var columns = Set<Int>()
                    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                        for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                            if color.redComponent > 0.85 && color.greenComponent < 0.35 && color.blueComponent > 0.65 {
                                columns.insert(x)
                            }
                        }
                    }
                    if let left = columns.min(), let right = columns.max(), columns.count > 80 {
                        loadedBitmap = bitmap
                        imageWidth = right - left
                        break
                    }
                    try await Task.sleep(for: .milliseconds(25))
                }
                if loadedBitmap == nil, let directory = ProcessInfo.processInfo.environment["GITGATTO_APPEARANCE_OUTPUT"] {
                    try lastBitmap?.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("issue-debug-\(width)-\(scheme).png"))
                }
                let bitmap = try #require(loadedBitmap, "The issue image was not rendered")
                #expect(imageWidth > 250)
                #expect(imageWidth < bitmap.pixelsWide)
                #expect(hosting.fittingSize.width <= CGFloat(width) + 1)
                if let directory = ProcessInfo.processInfo.environment["GITGATTO_APPEARANCE_OUTPUT"] {
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("issue-image-\(width)-\(scheme).png"))
                }
            }
        }
    }

    @Test("Default application icons and Markdown text render at narrow and wide widths")
    func rendersMissingImages() async throws {
        try await verifyCenterRendering(
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    MarketplaceLogoView(url: nil, size: 44)
                    MarketplaceLogoView(url: nil, size: 72)
                    Text("Application · 应用")
                }
                ReleaseNotesMarkdownView(text: """
                    ## Issue
                    A long description with **emphasis** and `code`.
                    图像无法加载时仍可通过附件链接打开查看。
                    """, openURL: { _ in })
                Spacer()
            }.padding(), name: "default-app-icons"
        )
    }
}
