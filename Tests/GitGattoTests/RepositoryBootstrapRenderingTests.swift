import AppKit
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Repository creation interface", .serialized)
@MainActor
struct RepositoryBootstrapRenderingTests {
    @Test("Local-only mode remains available without GitHub; failures remain retryable")
    func viewModel() async throws {
        let f = try BootstrapFixture(); defer { f.remove() }
        let github = BootstrapGitHub(); await github.failAccount()
        let model = RepositoryBootstrapViewModel(service: f.service(github), manualOptions: true)
        #expect(model.isPrivate && !model.canCreate)
        model.folder = f.folder; model.name = "demo"
        await model.inspectFolder(); await model.refreshAccount()
        #expect(model.accountError != nil && !model.canCreate)
        model.createRemote = false
        #expect(model.canCreate)
        model.authorName = "Fixture Maintainer"; model.authorEmail = "invalid"
        model.requestCreate(); await model.performRequest()
        #expect(model.error != nil && model.result == nil && !model.isRunning && model.canCreate)
        await model.inspectFolder()
        #expect(model.error != nil)
        model.authorEmail = "fixture@example.invalid"
        model.requestCreate(); await model.performRequest()
        #expect(model.result != nil && model.error == nil && !model.canCreate)
    }

    @Test("Empty, form, public, progress, failure and completion layouts fit narrow and RTL windows")
    func surfaces() async throws {
        defer { L10n.activate(AppPreferencesStore.load().language) }
        let directory = ProcessInfo.processInfo.environment["GITGATTO_BOOTSTRAP_SNAPSHOTS"]
        let cases: [(Int, AppLanguage, ColorScheme)] = directory == nil ? [(560, .english, .light)]
            : [(380, .simplifiedChinese, .light), (660, .german, .dark), (380, .arabic, .dark)]
        let workspace = WorkspaceViewModel(isBackgroundMonitor: true, monitoredRepositories: [])
        for (width, language, scheme) in cases {
            L10n.activate(language)
            for state in ["empty", "form", "public", "busy", "error", "success"] {
                let f = try BootstrapFixture(); defer { f.remove() }
                try await f.initBare()
                let github = BootstrapGitHub()
                let model = RepositoryBootstrapViewModel(service: f.service(github), manualOptions: true)
                if state != "empty" {
                    model.folder = f.folder; model.name = "demo"
                    await model.inspectFolder(); await model.refreshAccount()
                    model.authorName = "Fixture Maintainer"; model.authorEmail = "fixture@example.invalid"
                }
                if state == "public" { model.isPrivate = false }
                if state == "error" { await f.runner.failNextPush() }
                if state == "error" || state == "success" { model.requestCreate(); await model.performRequest() }
                if state == "busy" { await github.delayCreation(); model.requestCreate() }
                let view = RepositoryBootstrapSheet(workspace: workspace, model: model) { _, _ in }
                    .environment(\.colorScheme, scheme).environment(\.locale, L10n.locale)
                    .environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
                    .dynamicTypeSize(.accessibility1)
                let host = NSHostingView(rootView: AnyView(view))
                let bounds = NSRect(x: 0, y: 0, width: width, height: 660)
                let window = NSWindow(contentRect: bounds, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = host; host.frame = bounds
                if state == "busy" {
                    let deadline = ContinuousClock.now.advanced(by: .seconds(60))
                    while model.steps[.remote] != .running {
                        try #require(ContinuousClock.now < deadline)
                        await Task.yield()
                    }
                }
                await Task.yield()
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                #expect(host.bounds.size == bounds.size)
                let scroll = try #require(descendants(host).compactMap { $0 as? NSScrollView }.first)
                let document = try #require(scroll.documentView)
                #expect(document.bounds.width <= scroll.contentView.bounds.width + 2)
                if state == "form" || state == "public" {
                    let fields = descendants(host).compactMap { $0 as? NSTextField }.filter(\.isEditable)
                    let field = try #require(fields.first)
                    #expect(window.makeFirstResponder(field))
                }
                let name = "\(language.rawValue)-\(width)-\(state)"
                try capture(host, directory: directory, name: name)
                if document.bounds.height > scroll.contentView.bounds.height {
                    document.scrollToVisible(NSRect(x: 0, y: document.bounds.maxY - 1, width: 1, height: 1))
                    host.layoutSubtreeIfNeeded()
                    #expect(scroll.documentVisibleRect.maxY >= document.bounds.maxY - 2)
                    try capture(host, directory: directory, name: name + "-bottom")
                }
                if state == "public" { #expect(model.isPrivate == false) }
                if state == "error" { #expect(model.error != nil && model.result == nil) }
                if state == "success" { #expect(model.result?.pushed == true) }
                host.rootView = AnyView(EmptyView())
                window.contentView = nil; window.close()
                if state == "busy" {
                    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                    while model.isRunning {
                        try #require(ContinuousClock.now < deadline)
                        await Task.yield()
                    }
                    #expect(model.result == nil)
                }
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func capture(_ host: NSHostingView<AnyView>, directory: String?, name: String) throws {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(png.count > 4_096)
        if let directory {
            let root = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try png.write(to: root.appendingPathComponent(name + ".png"), options: .atomic)
        }
    }
}
