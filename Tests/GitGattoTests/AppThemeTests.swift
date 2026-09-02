import AppKit
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Application themes")
struct AppThemeTests {
    @Test("Uses glass by default and preserves saved theme selections")
    func resolvesStoredTheme() {
        #expect(AppVisualTheme.resolved(nil) == .softGlass)
        #expect(AppVisualTheme.resolved("unknown") == .softGlass)
        #expect(AppVisualTheme.resolved(AppVisualTheme.standard.rawValue) == .standard)
        #expect(AppVisualTheme.resolved(AppVisualTheme.softGlass.rawValue) == .softGlass)
        #expect(AppVisualTheme.resolved(AppVisualTheme.console.rawValue) == .console)
        #expect(AppVisualTheme.resolved(AppVisualTheme.emerald.rawValue) == .emerald)
        #expect(AppVisualTheme.resolved(AppVisualTheme.folio.rawValue) == .folio)
    }

    @MainActor
    @Test("Switches every theme while the window is attached")
    func switchesAttachedWindowThemes() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .resizable, .closable],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(
            rootView: AnyView(
                WindowThemeSurface(theme: .softGlass, colorScheme: .light)
                    .id(AppVisualTheme.softGlass.rawValue)
            )
        )
        window.contentView = hostingView
        window.orderFront(nil)

        for theme in [
            AppVisualTheme.standard,
            .console,
            .emerald,
            .folio,
            .softGlass,
            .standard,
            .softGlass
        ] {
            hostingView.rootView = AnyView(
                WindowThemeSurface(theme: theme, colorScheme: .light)
                    .id(theme.rawValue)
            )
            hostingView.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
            #expect(window.isOpaque == (theme != .softGlass))
        }

        #expect(window.titleVisibility == .hidden)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.isMovableByWindowBackground)
        window.orderOut(nil)
        window.contentView = nil
    }
}
