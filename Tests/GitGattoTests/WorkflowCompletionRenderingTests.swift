import AppKit
import SwiftUI
import Testing
import Sparkle
@testable import GitGatto

@Suite("Workflow completion rendering", .serialized)
@MainActor
struct WorkflowCompletionRenderingTests {
    @Test("Animated action and status icons retain their content area across themes")
    func motionIconContainers() async throws {
        let previousTheme = UserDefaults.standard.object(forKey: AppStyleDefaults.themeKey)
        let previousLanguage = AppPreferencesStore.load().language
        defer {
            UserDefaults.standard.set(previousTheme, forKey: AppStyleDefaults.themeKey)
            L10n.activate(previousLanguage)
        }
        for theme in AppVisualTheme.allCases {
            UserDefaults.standard.set(theme.rawValue, forKey: AppStyleDefaults.themeKey)
            for (width, language, scheme) in [(420, AppLanguage.simplifiedChinese, ColorScheme.light), (900, .english, .dark)] {
                let content = VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 20) {
                        CloneActionButton(title: "Clone", activeTitle: "Cloning", systemImage: "arrow.down",
                            isActive: true, isDisabled: false, action: {})
                        Button(action: {}) {
                            SubmitMotionLabel(title: "Commit", activeTitle: "Committing", systemImage: "checkmark", isActive: true)
                        }.buttonStyle(PrimaryButtonStyle())
                    }
                    ReadmeRewriteMotionLabel(title: "Writing README", isActive: true)
                    FlatAgentResolveButton(title: "Agent", isDisabled: false, action: {})
                    HStack(spacing: 24) {
                        ForEach([AppDownloadState.queued, .downloading, .paused, .completed], id: \.rawValue) { state in
                            CircularDownloadIndicator(state: state, progress: state == .queued ? 0 : state == .completed || state == .installed ? 1 : 0.62)
                        }
                    }
                    HStack(spacing: 24) {
                        ForEach([AppDownloadState.installed, .failed, .cancelled, .installing], id: \.rawValue) { state in
                            CircularDownloadIndicator(state: state, progress: state == .queued ? 0 : state == .completed || state == .installed ? 1 : 0.62)
                        }
                    }
                    HStack(spacing: 24) {
                        ConnectivityMotionGlyph(state: .checking)
                        ConnectivityMotionGlyph(state: .available)
                        ConnectivityMotionGlyph(state: .unavailable)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                try renderSwiftUI(content, name: "motion-icons-\(theme.rawValue)-\(width)",
                    width: width, height: 420, language: language, scheme: scheme)
            }
        }
    }

    @Test("Translation state styling covers the complete button in every theme")
    func translationButtonCoverage() async throws {
        let previousTheme = UserDefaults.standard.object(forKey: AppStyleDefaults.themeKey)
        let previousLanguage = AppPreferencesStore.load().language
        defer {
            UserDefaults.standard.set(previousTheme, forKey: AppStyleDefaults.themeKey)
            L10n.activate(previousLanguage)
        }
        let cases: [(Int, AppLanguage, ColorScheme, Bool)] = [
            (420, .simplifiedChinese, .light, false),
            (900, .german, .dark, false),
            (420, .arabic, .dark, true),
            (900, .english, .light, true)
        ]
        let fallback = try #require(DevelopmentTool.catalog.first { $0.id == "lazygit" })
        let branded = try #require(DevelopmentTool.catalog.first { $0.id == "git" })
        for theme in AppVisualTheme.allCases {
            UserDefaults.standard.set(theme.rawValue, forKey: AppStyleDefaults.themeKey)
            for (width, language, scheme, largeText) in cases {
                L10n.activate(language)
                let active = translationControls(state: "loading")
                    .environment(\.colorScheme, scheme)
                let host = NSHostingView(rootView: active.fixedSize())
                let size = host.fittingSize
                #expect(abs(size.height - 34) < 0.5)
                #expect(size.width <= CGFloat(width - 48))

                let content = VStack(alignment: .leading, spacing: 18) {
                    DocumentTranslationActionLabel(title: "", activeTitle: L10n.text("codex.status.translating"),
                        isActive: true, showsCancelIndicator: true)
                        .fixedSize()
                    ForEach(["original", "translated", "loading", "failed", "disabled"], id: \.self) { state in
                        translationControls(state: state)
                    }
                    HStack(spacing: 24) {
                        ForEach([CGFloat(31), 46], id: \.self) { logoSize in
                            DevelopmentToolLogoView(tool: fallback, size: logoSize, fallbackColor: AppPalette(scheme).ink)
                            DevelopmentToolLogoView(tool: branded, size: logoSize, fallbackColor: AppPalette(scheme).ink)
                        }
                        ToolbarIconButton(systemName: "arrow.clockwise", helpKey: "action.refresh", action: {})
                        GattoIcon(symbol: "arrow.down", size: 19)
                        GattoIcon(symbol: "arrow.up", size: 19)
                    }
                }
                .dynamicTypeSize(largeText ? .accessibility1 : .large)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                try await render(content, name: "icon-translation-\(theme.rawValue)-\(width)-\(language.rawValue)",
                    width: width, height: 380, language: language, scheme: scheme)
                // NSView.cacheDisplay omits transforms from nested animation layers.
                // Render the SwiftUI label directly to verify its actual glyph placement.
                let label = DocumentTranslationActionLabel(title: "", activeTitle: L10n.text("codex.status.translating"),
                    isActive: true, showsCancelIndicator: true)
                    .fixedSize()
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                let bitmap = try renderSwiftUI(label, name: "translation-glyph-\(theme.rawValue)-\(width)-\(language.rawValue)",
                    width: width, height: 82, language: language, scheme: scheme)
                let scale = CGFloat(bitmap.pixelsWide) / CGFloat(width)
                let originX = language == .arabic ? CGFloat(width - 24 - 34) : 24
                let ink = try #require(NSColor(AppPalette(scheme).onPrimary).usingColorSpace(.deviceRGB))
                var points: [CGPoint] = []
                for y in Int(30 * scale)..<Int(52 * scale) {
                    for x in Int((originX + 6) * scale)..<Int((originX + 28) * scale) {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                        if abs(color.redComponent - ink.redComponent) < 0.15,
                           abs(color.greenComponent - ink.greenComponent) < 0.15,
                           abs(color.blueComponent - ink.blueComponent) < 0.15 {
                            points.append(CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale))
                        }
                    }
                }
                let minX = try #require(points.map(\.x).min()), maxX = try #require(points.map(\.x).max())
                let minY = try #require(points.map(\.y).min()), maxY = try #require(points.map(\.y).max())
                #expect(abs((minX + maxX) / 2 - (originX + 17)) < 2)
                #expect(abs((minY + maxY) / 2 - 41) < 2)
            }
        }
    }

    @discardableResult
    private func renderSwiftUI<Content: View>(_ content: Content, name: String, width: Int, height: Int,
        language: AppLanguage, scheme: ColorScheme) throws -> NSBitmapImageRep {
        let view = content
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: language.rawValue))
            .environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
            .frame(width: CGFloat(width), height: CGFloat(height))
            .background(AppPalette(scheme).background)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        #expect(bitmap.pixelsWide == width * 2)
        #expect(bitmap.pixelsHigh == height * 2)
        if let directory = ProcessInfo.processInfo.environment["GITGATTO_COMPLETION_SNAPSHOTS"] {
            let root = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: root.appendingPathComponent(name + ".png"))
        }
        return bitmap
    }

    private func translationControls(state: String) -> DocumentTranslationControls {
        DocumentTranslationControls(
            activeTarget: state == "translated" ? .english : nil,
            availableTargets: [.english, .simplifiedChinese], preferredTarget: .english,
            isTranslating: state == "loading", isDisabled: state == "disabled",
            error: state == "failed" ? "Fixture translation failed" : nil, completionID: nil,
            showOriginal: {}, showTranslation: { _ in }, translate: { _ in }, cancel: {},
            progressTitle: L10n.text("codex.status.translating") + " · 12 / 120"
        )
    }

    @Test func translationReceiptAndUpdateStates() async throws {
        let prior = AppPreferencesStore.load().language
        defer { L10n.activate(prior) }
        for (width, language, scheme) in [(700, AppLanguage.simplifiedChinese, ColorScheme.light), (1120, .german, .dark), (700, .arabic, .dark)] {
            L10n.activate(language)
            for state in ["original", "translated", "loading", "failed"] {
                let content = VStack(alignment: .leading, spacing: 24) {
                    DocumentTranslationControls(activeTarget: state == "translated" ? .english : nil,
                        availableTargets: [.english, .simplifiedChinese], preferredTarget: .english,
                        isTranslating: state == "loading", isDisabled: false,
                        error: state == "failed" ? "Fixture translation failed" : nil, completionID: nil,
                        showOriginal: {}, showTranslation: { _ in }, translate: { _ in }, cancel: {})
                    Text("README · let value = 1 · Git / Node.js")
                    SettingsSaveFeedback(failed: state == "failed", pending: state == "loading", saved: state == "translated", palette: AppPalette(scheme))
                    DevelopmentToolReceiptView(receipt: .init(executableVerified: state != "failed",
                        verificationDetail: state == "failed" ? "Version check returned exit 1" : nil,
                        profilePath: "/tmp/fixture/long-configuration-directory/.zprofile", environmentState: state == "failed" ? "failed" : "updated",
                        environmentError: nil, agentConfigurationComplete: state != "failed"))
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                try await render(content, name: "translation-\(state)-\(width)-\(language.rawValue)", width: width, height: 380, language: language, scheme: scheme)
            }
            for code in [2001, 3001, 4012] {
                let manager = AppUpdateManager()
                manager.recordUpdateFailure(NSError(domain: SUSparkleErrorDomain, code: code,
                    userInfo: [NSLocalizedDescriptionKey: "Fixture failure — download / validation / permissions"]))
                try await render(UpdateCenterView(manager: manager, loadsReleaseNotes: false),
                    name: "update-\(code)-\(width)-\(language.rawValue)", width: width, height: 820, language: language, scheme: scheme)
            }
        }
    }

    @Test func goalCommandsAndNavigation() async throws {
        let previous = UserDefaults.standard.object(forKey: "app.preferences")
        var preferences = AppPreferences(); preferences.monitoringEngineEnabled = false
        AppPreferencesStore.save(preferences)
        defer { UserDefaults.standard.set(previous, forKey: "app.preferences"); L10n.activate(AppPreferencesStore.load().language) }
        let model = WorkspaceViewModel()
        for (width, language, scheme) in [(700, AppLanguage.simplifiedChinese, ColorScheme.light), (1120, .german, .dark), (700, .arabic, .dark)] {
            L10n.activate(language)
            try await render(ProjectGoalComposerView(model: model, onCreated: {}, onCancel: {}),
                name: "goal-composer-\(width)-\(language.rawValue)", width: width, height: 820, language: language, scheme: scheme)
            try await render(DevelopmentToolBundleSheet(model: DeveloperToolsViewModel()),
                name: "tool-bundle-\(width)-\(language.rawValue)", width: width, height: 820, language: language, scheme: scheme)
            try await render(GlobalCommandPalette(model: model, openSettings: {}, openScanner: {}, openHelp: {}, dismiss: {}),
                name: "command-palette-\(width)-\(language.rawValue)", width: width, height: 600, language: language, scheme: scheme)
        }
    }

    @Test func conflictEditSaveAndContinue() async throws {
        let defaults = UserDefaults.standard
        let keys = ["app.preferences", "recentRepositories", "managedLocalRepositories", "localRepositories", "excludedRepositories"]
        let values = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, values) { defaults.set(value, forKey: key) }; L10n.activate(AppPreferencesStore.load().language) }
        var preferences = AppPreferences()
        preferences.monitoringEngineEnabled = false
        preferences.repositoryBackupEnabled = false
        preferences.agentEditProtectionEnabled = false
        AppPreferencesStore.save(preferences)
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("GitGatto-conflict-ui-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = GitCommandRunner()
        func git(_ arguments: [String]) async throws {
            _ = try await runner.run(at: root, arguments: arguments, environment: ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_TEMPLATE_DIR": ""])
        }
        try await git(["init", "-b", "main"])
        try await git(["config", "user.name", "Fixture"])
        try await git(["config", "user.email", "fixture@example.invalid"])
        try await git(["config", "commit.gpgsign", "false"])
        let file = root.appendingPathComponent("conflict.txt")
        try "base\n".write(to: file, atomically: true, encoding: .utf8)
        try await git(["add", "."]); try await git(["commit", "-m", "base"])
        try await git(["switch", "-c", "feature"])
        try "feature\n".write(to: file, atomically: true, encoding: .utf8)
        try await git(["commit", "-am", "feature"])
        try await git(["switch", "main"])
        try "main\n".write(to: file, atomically: true, encoding: .utf8)
        try await git(["commit", "-am", "main"])
        let model = WorkspaceViewModel()
        await model.openRepository(root)
        await model.merge(branch: "feature")
        model.selectConflict(path: "conflict.txt")
        let deadline = ContinuousClock.now + .seconds(15)
        while model.conflictDocument == nil, ContinuousClock.now < deadline { await Task.yield() }
        _ = try #require(model.conflictDocument)
        let state = try #require(model.repositoryOperationState)
        for (width, language, scheme) in [(700, AppLanguage.simplifiedChinese, ColorScheme.light), (1120, .german, .dark), (700, .arabic, .dark)] {
            L10n.activate(language)
            try await render(ConflictResolutionWorkspaceView(model: model, state: state), name: "conflict-edit-\(width)-\(language.rawValue)", width: width, height: 820, language: language, scheme: scheme)
        }
        let block = try #require(ConflictBlock.parse(model.conflictResolutionText).first)
        model.conflictResolutionText = try #require(ConflictBlock.resolving(block.id, using: .both, in: model.conflictResolutionText))
        #expect(!model.conflictResolutionContainsMarkers)
        await model.saveConflictResolution()
        let resolved = try #require(model.repositoryOperationState)
        #expect(resolved.conflictedPaths.isEmpty)
        try await render(ConflictResolutionWorkspaceView(model: model, state: resolved), name: "conflict-continue", width: 700, height: 820, language: .simplifiedChinese, scheme: .dark)
        await model.continueRepositoryOperation()
        #expect(model.repositoryOperationState == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".git/MERGE_HEAD").path))
        #expect(try String(contentsOf: file, encoding: .utf8).contains("feature"))
        #expect(try String(contentsOf: file, encoding: .utf8).contains("main"))
        model.refreshRepositoryFiles()
        let fileDeadline = ContinuousClock.now + .seconds(15)
        while model.isLoadingRepositoryFiles || model.isLoadingFileTimeline, ContinuousClock.now < fileDeadline { await Task.yield() }
        _ = try #require(model.selectedRepositoryFile)
        let revision = try #require(model.fileRevisions.last)
        model.selectFileRevision(revision)
        while model.isLoadingFileTimeline, ContinuousClock.now < fileDeadline { await Task.yield() }
        _ = try #require(model.fileVersionDocument)
        await model.prepareGoalFromChanges()
        #expect(model.projectGoalSourceDraft?.repositoryPath == root.path)
        for (width, language, scheme) in [(700, AppLanguage.simplifiedChinese, ColorScheme.light), (1120, .german, .dark), (700, .arabic, .dark)] {
            L10n.activate(language)
            try await render(ProjectGoalComposerView(model: model, onCreated: {}, onCancel: {}), name: "goal-context-\(width)-\(language.rawValue)", width: width, height: 820, language: language, scheme: scheme)
            try await render(FileTimelineWorkspaceView(model: model), name: "file-history-\(width)-\(language.rawValue)", width: width, height: 820, language: language, scheme: scheme)
            model.fileTimelineDetailMode = .blame
            try await render(FileTimelineWorkspaceView(model: model), name: "file-blame-\(width)-\(language.rawValue)", width: width, height: 820, language: language, scheme: scheme)
            model.fileTimelineDetailMode = .content
            let beforePreview = try Data(contentsOf: file)
            try await render(FileRestorePreviewSheet(repository: root, path: "conflict.txt", revision: revision, restored: {}), name: "file-restore-preview-\(width)-\(language.rawValue)", width: width, height: 820, language: language, scheme: scheme, waitForScrollContent: true)
            #expect(try Data(contentsOf: file) == beforePreview)
            model.settingsDestination = "monitoring"
            try await render(AppSettingsView(model: model, updateManager: AppUpdateManager()), name: "settings-\(max(820, width))-\(language.rawValue)", width: max(820, width), height: 820, language: language, scheme: scheme)
            model.settingsDestination = "monitoring"
            try await render(AppSettingsView(model: model, updateManager: AppUpdateManager()), name: "settings-policy-\(max(820, width))-\(language.rawValue)", width: max(820, width), height: 820, language: language, scheme: scheme, scrollToBottom: true)
        }
        model.inspectFileContext("conflict.txt", line: 2)
        #expect(model.intelligenceNavigation?.path == "conflict.txt")
        #expect(model.intelligenceNavigation?.line == 2)
        #expect(model.intelligenceNavigation?.tab == .provenance)
        model.inspectFailureContext(command: "swift test", output: "Fixture failure", repositoryPath: root.path)
        #expect(model.intelligenceNavigation?.tab == .capsules)
        let navigation = model.intelligenceNavigation
        model.inspectFailureContext(command: "wrong", output: "wrong", repositoryPath: "/tmp/wrong-project")
        #expect(model.intelligenceNavigation == navigation)
        model.restartLiveRefreshLoop()
    }

    @Test func commandPaletteKeyboardNavigation() async throws {
        let name = "GitGatto-keyboard-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let prior = UserDefaults.standard.object(forKey: "app.preferences")
        var preferences = AppPreferences(); preferences.monitoringEngineEnabled = false
        AppPreferencesStore.save(preferences)
        defer { UserDefaults.standard.set(prior, forKey: "app.preferences") }
        let model = WorkspaceViewModel()
        let usage = CommandUsageStore(defaults: defaults)
        var dismissals = 0
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 580), styleMask: [.titled], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: GlobalCommandPalette(model: model, openSettings: {}, openScanner: {}, openHelp: {}, dismiss: { dismissals += 1 }, usage: usage))
        window.contentView = hosting
        defer { window.orderOut(nil); window.contentView = nil }
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        func textField(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap { textField($0) }.first
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while textField(hosting) == nil, ContinuousClock.now < deadline { await Task.yield(); hosting.layoutSubtreeIfNeeded() }
        let field = try #require(textField(hosting))
        window.makeFirstResponder(field)
        func key(_ code: UInt16, characters: String) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
            window.sendEvent(event)
        }
        try key(125, characters: String(UnicodeScalar(NSDownArrowFunctionKey)!))
        await Task.yield(); hosting.layoutSubtreeIfNeeded()
        try key(36, characters: "\r")
        await Task.yield()
        #expect(dismissals == 1)
        #expect(model.selectedSection == WorkspaceSection.allCases[1])
        #expect(usage.recent.first == "section." + WorkspaceSection.allCases[1].rawValue)
    }

    @discardableResult
    private func render<Content: View>(_ content: Content, name: String, width: Int, height: Int,
                                      language: AppLanguage, scheme: ColorScheme, scrollToBottom: Bool = false, waitForScrollContent: Bool = false) async throws -> NSBitmapImageRep {
        L10n.activate(language)
        let directory = ProcessInfo.processInfo.environment["GITGATTO_COMPLETION_SNAPSHOTS"]
        let view = content.environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: language.rawValue))
            .environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
            .frame(width: CGFloat(width), height: CGFloat(height))
            .background(AppPalette(scheme).background)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        defer { window.orderOut(nil); window.contentView = nil }
        window.orderFront(nil)
        await Task.yield(); await Task.yield()
        hosting.layoutSubtreeIfNeeded(); hosting.displayIfNeeded()
        func scrollView(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView($0) }.first
        }
        if waitForScrollContent {
            let deadline = ContinuousClock.now + .seconds(8)
            while scrollView(hosting) == nil, ContinuousClock.now < deadline {
                await Task.yield(); hosting.layoutSubtreeIfNeeded()
            }
            _ = try #require(scrollView(hosting))
            hosting.displayIfNeeded()
        }
        if scrollToBottom {
            func scrollViews(_ view: NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
            }
            let scroll = try #require(scrollViews(hosting).max {
                ($0.documentView?.bounds.height ?? 0) - $0.contentView.bounds.height <
                    ($1.documentView?.bounds.height ?? 0) - $1.contentView.bounds.height
            })
            let document = try #require(scroll.documentView)
            let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
            #expect(maximum > 1)
            let initial = scroll.contentView.bounds.origin.y
            scroll.contentView.scroll(to: NSPoint(x: 0, y: initial < maximum / 2 ? maximum : 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            await Task.yield(); hosting.layoutSubtreeIfNeeded(); hosting.displayIfNeeded()
            print("COMPLETION_SCROLL name=\(name) initial=\(initial) final=\(scroll.contentView.bounds.origin.y) range=\(maximum) document_flipped=\(document.isFlipped)")
            #expect(abs(scroll.contentView.bounds.origin.y - initial) > 1)
        }
        #expect(L10n.text("settings.save") == L10n.bundle(preferredLanguages: language.preferredLanguages)
            .localizedString(forKey: "settings.save", value: nil, table: nil))
        let image = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: image)
        let png = try #require(image.representation(using: .png, properties: [:]))
        #expect(png.count > 4096)
        #expect(hosting.bounds.width == CGFloat(width))
        if let directory {
            let root = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try png.write(to: root.appendingPathComponent(name + ".png"))
        }
        return image
    }
}
