import AppKit
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Upstream and visibility interface", .serialized)
@MainActor
struct RepositoryUpstreamRenderingTests {
    @Test("Visible entry actions and visibility states fit narrow, wide and RTL layouts")
    func surfaces() async throws {
        defer { L10n.activate(AppPreferencesStore.load().language) }
        let directory = ProcessInfo.processInfo.environment["GITGATTO_BOOTSTRAP_SNAPSHOTS"]
        let cases: [(Int, AppLanguage, ColorScheme)] = directory == nil ? [(380, .english, .light)]
            : [(380, .simplifiedChinese, .light), (660, .german, .dark), (380, .arabic, .dark)]
        let workspace = WorkspaceViewModel(isBackgroundMonitor: true, monitoredRepositories: [])
        for (width, language, scheme) in cases {
            L10n.activate(language)
            for state in ["entries", "private", "public", "permission", "error", "agent"] {
                let f = try BootstrapFixture(); defer { f.remove() }
                let visibility = VisibilityFixture(isPrivate: state != "public")
                if state == "permission" { await visibility.setMode("permission") }
                let visibilityModel = GitHubVisibilityViewModel(service: .init(transport: visibility))
                await visibilityModel.load("fixture-owner/demo")
                if state == "error" {
                    await visibility.setMode("policy")
                    visibilityModel.requestChange(); visibilityModel.confirmChange()
                    _ = await visibilityModel.performChange()
                }
                let bootstrap = RepositoryBootstrapViewModel(service: f.service(), folder: f.folder, agent: UpstreamAgentFixture(mode: "delay"))
                var root: AnyView
                switch state {
                case "agent":
                    bootstrap.name = "demo"
                    await bootstrap.inspectFolder(); await bootstrap.refreshAccount()
                    bootstrap.authorName = "Fixture Maintainer"; bootstrap.authorEmail = "fixture@example.invalid"
                    bootstrap.manualOptions = false
                    bootstrap.requestCreate(usingAgent: true)
                    root = AnyView(RepositoryBootstrapSheet(workspace: workspace, model: bootstrap) { _, _ in })
                case "entries": root = AnyView(RepositoryUpstreamActions(model: workspace))
                default:
                    root = AnyView(GitHubVisibilityControl(fullName: "fixture-owner/demo", model: visibilityModel).padding(16))
                }
                let bounds = NSRect(x: 0, y: 0, width: width, height: state == "agent" ? 660 : 320)
                let host = NSHostingView(rootView: AnyView(root
                    .environment(\.colorScheme, scheme).environment(\.locale, L10n.locale)
                    .environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
                    .dynamicTypeSize(.accessibility1)
                    .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
                    .background(AppPalette(scheme).surface)))
                host.sizingOptions = []
                let window = NSWindow(contentRect: bounds, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = host; host.frame = bounds
                if state == "agent" {
                    let deadline = ContinuousClock.now.advanced(by: .seconds(60))
                    while bootstrap.steps[.agent] != .running {
                        try #require(ContinuousClock.now < deadline); await Task.yield()
                    }
                }
                await Task.yield()
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                #expect(host.bounds.size == bounds.size)
                for scroll in descendants(host).compactMap({ $0 as? NSScrollView }) {
                    if let document = scroll.documentView { #expect(document.bounds.width <= scroll.contentView.bounds.width + 2) }
                }
                for button in descendants(host).compactMap({ $0 as? NSButton }) where !button.isHidden {
                    let frame = host.convert(button.bounds, from: button)
                    #expect(frame.minX >= -1 && frame.maxX <= bounds.maxX + 1)
                }
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                #expect(data.count > 2_000)
                if let directory {
                    let folder = URL(fileURLWithPath: directory)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try data.write(to: folder.appendingPathComponent("upstream-\(language.rawValue)-\(width)-\(state).png"))
                }
                host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close()
                if state == "agent" {
                    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                    while bootstrap.isRunning { try #require(ContinuousClock.now < deadline); await Task.yield() }
                    #expect(bootstrap.result == nil)
                    #expect(!FileManager.default.fileExists(atPath: f.folder.appendingPathComponent(".git").path))
                }
            }
        }
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}

@Suite("Repository setup command palette", .serialized)
@MainActor
struct RepositorySetupCommandPaletteTests {
    @Test("Search finds setup commands and Return passes the chosen mode and folder")
    func setupCommands() async throws {
        defer { L10n.activate(AppPreferencesStore.load().language) }
        let f = try BootstrapFixture(); defer { f.remove() }
        _ = try await f.git(["init", "-b", "main"])
        let snapshot = try await GitRepositoryService().loadRepositoryOverview(at: f.folder)
        for (width, language, scheme) in [(380, AppLanguage.simplifiedChinese, ColorScheme.light), (650, .german, .dark), (380, .arabic, .dark)] {
            L10n.activate(language)
            for mode in ["create", "agent", "manual"] {
                let defaultsName = "GitGatto.setup-palette.\(UUID())"
                let defaults = try #require(UserDefaults(suiteName: defaultsName))
                defer { defaults.removePersistentDomain(forName: defaultsName) }
                let workspace = WorkspaceViewModel(isBackgroundMonitor: true, monitoredRepositories: [])
                if mode != "create" { workspace.apply(snapshot, preservingSelection: false) }
                var requests: [(URL?, Bool)] = []
                var dismissals = 0
                let usage = CommandUsageStore(defaults: defaults)
                let root = GlobalCommandPalette(model: workspace, openSettings: {}, openScanner: {}, openHelp: {},
                    openRepositorySetup: { requests.append(($0, $1)) }, dismiss: { dismissals += 1 }, usage: usage)
                let bounds = NSRect(x: 0, y: 0, width: width, height: 510)
                let host = NSHostingView(rootView: root.environment(\.colorScheme, scheme)
                    .environment(\.locale, L10n.locale)
                    .environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
                    .dynamicTypeSize(.accessibility1).frame(width: bounds.width, height: bounds.height))
                host.sizingOptions = []
                let window = NSWindow(contentRect: bounds, styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = host; host.frame = bounds
                defer { window.contentView = nil; window.close() }
                window.makeKeyAndOrderFront(nil)
                await Task.yield(); host.layoutSubtreeIfNeeded()
                let field = try #require(descendants(host).compactMap { $0 as? NSTextField }.first { $0.isEditable })
                window.makeFirstResponder(field)
                let editor = try #require(field.currentEditor() as? NSTextView)
                let key = mode == "create" ? "repository.create.title" : "repository.upstream.\(mode)"
                editor.selectAll(nil); editor.insertText(L10n.text(key), replacementRange: editor.selectedRange())
                await Task.yield(); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                #expect(field.stringValue == L10n.text(key))
                #expect(host.bounds.size == bounds.size)
                for scroll in descendants(host).compactMap({ $0 as? NSScrollView }) {
                    if let document = scroll.documentView { #expect(document.bounds.width <= scroll.contentView.bounds.width + 2) }
                }
                if let directory = ProcessInfo.processInfo.environment["GITGATTO_BOOTSTRAP_SNAPSHOTS"] {
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let data = try #require(bitmap.representation(using: .png, properties: [:]))
                    let folder = URL(fileURLWithPath: directory)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try data.write(to: folder.appendingPathComponent("setup-palette-\(language.rawValue)-\(width)-\(mode).png"))
                }
                let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
                window.sendEvent(event); await Task.yield()
                #expect(dismissals == 1)
                try #require(requests.count == 1)
                #expect(requests[0].0 == (mode == "create" ? nil : snapshot.rootURL))
                #expect(requests[0].1 == (mode == "agent"))
                #expect(usage.recent.first == (mode == "create" ? "repository-create" : "repository-upstream-\(mode)"))
            }
        }
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
