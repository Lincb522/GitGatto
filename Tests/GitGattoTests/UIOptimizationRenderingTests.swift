import AppKit
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Optimized workflow rendering", .serialized)
struct UIOptimizationRenderingTests {
    @MainActor @Test("Diff selection, disabled buttons and recovery errors fit every theme")
    func surfaces() async throws {
        let directory = ProcessInfo.processInfo.environment["GITGATTO_OPTIMIZATION_SNAPSHOTS"]
        let defaults = UserDefaults.standard
        let previousTheme = defaults.object(forKey: AppStyleDefaults.themeKey)
        defer { defaults.set(previousTheme, forKey: AppStyleDefaults.themeKey); L10n.activate(AppPreferencesStore.load().language) }
        let themes: [AppVisualTheme] = directory == nil ? [.standard] : [.standard, .softGlass, .console, .emerald, .folio, .lumen]
        let cases: [(Int, AppLanguage, ColorScheme)] = directory == nil
            ? [(700, .english, .light)]
            : [(700, .simplifiedChinese, .light), (1120, .german, .dark), (700, .arabic, .dark)]
        let source = "diff --git a/Sources/LongProject/File.swift b/Sources/LongProject/File.swift\nindex 1111111..2222222 100644\n--- a/Sources/LongProject/File.swift\n+++ b/Sources/LongProject/File.swift\n@@ -1,4 +1,4 @@\n struct State {\n-    let enabled = false\n+    let enabled = true\n     let id = 1\n }\n"
        let change = WorkingTreeChange(path: "Sources/LongProject/File.swift", originalPath: nil, indexStatus: .unmodified, workTreeStatus: .modified)
        let document = GitParsers.diff(from: source, path: change.path)
        for theme in themes {
            defaults.set(theme.rawValue, forKey: AppStyleDefaults.themeKey)
            for (width, language, scheme) in cases {
                L10n.activate(language)
                let report = GlobalErrorHandler.report(for: GitCommandError(arguments: ["push"], exitCode: 1,
            message: "refusing to allow an OAuth App to create or update workflow `.github/workflows/ci.yml` without `workflow` scope"),
            context: .git(.push), repositoryURL: URL(fileURLWithPath: "/tmp/fixture-project"))
                let content = VStack(spacing: 16) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { controls }
                        VStack(alignment: .leading, spacing: 12) { controls }
                    }.padding(16)
                    DiffInspectorView(change: change, document: document, previewURL: nil, onStageSelection: { _, _, _ in })
                }.background(AppPalette(scheme).background)
                try await render(content, name: "diff-\(theme.rawValue)-\(width)-\(language.rawValue)", width: width,
                    height: 630, language: language, scheme: scheme, directory: directory)
                try await render(GlobalErrorSheet(report: report, canUseAgent: false, useAgent: {}, dismiss: {}, recover: { _ in }),
                    name: "error-\(theme.rawValue)-\(width)-\(language.rawValue)", width: width, height: 640,
                    language: language, scheme: scheme, directory: directory)
            }
        }
    }

    @MainActor @Test("Regression setup and search remain usable in narrow, wide and RTL layouts")
    func guidedSurfaces() async throws {
        let directory = ProcessInfo.processInfo.environment["GITGATTO_OPTIMIZATION_SNAPSHOTS"]
        let preferences = AppPreferencesStore.load()
        defer { L10n.activate(preferences.language) }
        let model = WorkspaceViewModel()
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("GitGatto-guided-render-\(UUID())")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let tools = ProjectToolsViewModel(store: ProjectToolsStore(root: fixture))
        let cases: [(Int, AppLanguage, ColorScheme)] = directory == nil ? [(700, .english, .light)]
            : [(700, .simplifiedChinese, .light), (1120, .german, .dark), (700, .arabic, .dark)]
        for (width, language, scheme) in cases {
            L10n.activate(language)
            for mode in [RegressionInvestigationMode.manual, .automatic] {
                model.regressionMode = mode
                try await render(RegressionInvestigationWorkspaceView(model: model),
                    name: "regression-\(mode.rawValue)-\(width)-\(language.rawValue)", width: width, height: 760,
                    language: language, scheme: scheme, directory: directory)
            }
            tools.query = ProjectCodeQuery()
            try await render(ScrollView { ProjectCodeSearchPanel(workspace: model, tools: tools).padding(20) },
                name: "search-empty-\(width)-\(language.rawValue)", width: width, height: 620,
                language: language, scheme: scheme, directory: directory)
            tools.query.language = "Swift"
            try await render(ScrollView { ProjectCodeSearchPanel(workspace: model, tools: tools).padding(20) },
                name: "search-filtered-\(width)-\(language.rawValue)", width: width, height: 620,
                language: language, scheme: scheme, directory: directory)
        }
    }

    @MainActor @Test("Branch switch preview, progress, saved state and errors fit narrow and wide windows")
    func branchSwitchSurfaces() async throws {
        let directory = ProcessInfo.processInfo.environment["GITGATTO_OPTIMIZATION_SNAPSHOTS"]
        let preferences = AppPreferencesStore.load()
        defer { L10n.activate(preferences.language) }
        let changes = (1...40).map { WorkingTreeChange(path: "Sources/ProjectWithLongName/Components/Editor/File\($0).swift",
            originalPath: nil, indexStatus: .modified, workTreeStatus: .modified) }
        let preview = WorkSceneSwitchPreview(repository: URL(fileURLWithPath: "/tmp/project"), branch: "feature/long-working-branch-name",
            targetBranch: "release/long-target-branch-name", targetHead: "0123456", fingerprint: "fixture", changes: changes)
        let scene = WorkScene(name: "feature", repositoryPath: "/tmp/project", branch: preview.branch, head: "0123456",
            draft: "", agentDraft: "", relatedURL: "", section: "changes")
        let cases: [(Int, AppLanguage, ColorScheme)] = directory == nil ? [(480, .english, .light)]
            : [(480, .simplifiedChinese, .light), (800, .german, .dark), (480, .arabic, .dark)]
        for (width, language, scheme) in cases {
            L10n.activate(language)
            for state in ["loading", "preview", "busy", "error", "saved", "failedAfterSave"] {
                let content = BranchSwitchContent(preview: state == "loading" || state == "error" ? nil : preview,
                    error: state == "error" ? L10n.text("tools.error.branchChanged") : state == "failedAfterSave" ? L10n.text("branches.scene.switchFailed") : nil,
                    busy: state == "busy", finished: state == "saved", savedScene: state == "saved" || state == "failedAfterSave" ? scene : nil,
                    confirm: {}, retry: {}, close: {}, openScenes: {})
                try await render(content, name: "branch-\(state)-\(width)-\(language.rawValue)", width: width,
                    height: 580, language: language, scheme: scheme, directory: directory)
            }
        }
    }

    @MainActor @Test("Selection actions and scope remain readable at narrow, wide and RTL widths")
    func selectedPlanningSurfaces() async throws {
        let directory = ProcessInfo.processInfo.environment["GITGATTO_OPTIMIZATION_SNAPSHOTS"]
        defer { L10n.activate(AppPreferencesStore.load().language) }
        let source = "diff --git a/file.txt b/file.txt\n--- a/file.txt\n+++ b/file.txt\n@@ -1 +1 @@\n-old\n+new\n"
        let document = GitParsers.diff(from: source, path: "Sources/Preferences/VeryLongDirectoryName/RepositorySettingsView.swift")
        let change = WorkingTreeChange(path: document.path, originalPath: nil, indexStatus: .modified, workTreeStatus: .unmodified)
        let ids = Set(document.lines.filter { $0.kind == .addition || $0.kind == .deletion }.map(\.id))
        let selection = try ChangeIntentSelection(document: document, change: change, selectedIDs: ids)
        for (width, language, scheme) in [(360, AppLanguage.simplifiedChinese, ColorScheme.light), (900, .german, .dark), (360, .arabic, .dark)] {
            L10n.activate(language)
            for state in ["empty", "selected", "busy", "error"] {
                let content = VStack(alignment: .leading, spacing: 16) {
                    DiffSelectionActions(count: state == "empty" ? 0 : 2, isStaged: true, isBusy: state == "busy", onStage: {}, onPlan: {})
                    ChangeIntentSelectionBanner(selection: selection, isBusy: state == "busy", showAll: {})
                    if state == "error" { IntelligenceInlineError(report: GlobalErrorHandler.report(for: ChangeIntentError.selectionDependency, context: .intelligence(.intent))).padding(16) }
                    Spacer()
                }.background(AppPalette(scheme).background)
                let container = GeometryReader { _ in
                    content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                try await render(container, name: "selection-\(state)-\(width)-\(language.rawValue)", width: width,
                    height: 630, language: language, scheme: scheme, directory: directory)
            }
        }
    }

    @ViewBuilder private var controls: some View {
        Button(L10n.text("settings.save")) {}.buttonStyle(PrimaryButtonStyle())
        Button(L10n.text("settings.save")) {}.buttonStyle(PrimaryButtonStyle()).disabled(true)
        Button(L10n.text("settings.discard")) {}.buttonStyle(SecondaryButtonStyle())
        Button(L10n.text("settings.discard")) {}.buttonStyle(SecondaryButtonStyle()).disabled(true)
    }

    @MainActor private func render<V: View>(_ content: V, name: String, width: Int, height: Int,
        language: AppLanguage, scheme: ColorScheme, directory: String?) async throws {
        let view = content.environment(\.colorScheme, scheme)
            .environment(\.locale, L10n.locale)
            .environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
            .dynamicTypeSize(.accessibility1)
        let host = NSHostingView(rootView: view)
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: bounds, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        host.frame = bounds
        defer { window.contentView = nil; window.close() }
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        #expect(host.bounds.size == bounds.size)
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
