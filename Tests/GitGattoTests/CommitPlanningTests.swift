import AppKit
import Foundation
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Commit planning workflow", .serialized)
struct CommitPlanningTests {
    @MainActor @Test("Git revision failures are explained in the selected language")
    func localizedRevisionFailure() async throws {
        defer { L10n.activate(AppPreferencesStore.load().language) }
        L10n.activate(.simplifiedChinese)
        let fixture = try PlanningFixture(); defer { fixture.remove() }
        let service = PlanningService()
        await service.setGitFailure(GitCommandError(arguments: ["show", "HEAD"], exitCode: 128,
            message: "fatal: ambiguous argument 'HEAD': unknown revision or path not in the working tree."))
        let model = fixture.model(service: service)
        model.load(repositoryURL: fixture.repository)
        try await eventually { model.intentError != nil && !model.isIntentBusy }
        #expect(model.intentError?.explanation == L10n.text("error.explanation.git_revision"))
        #expect(model.intentError?.exitCode == 128)
        #expect(model.intentError?.message.contains("ambiguous argument") == true)
        await service.setGitFailure(nil)
        await model.refreshIntentPlan()
        #expect(model.intentError == nil && model.intentPlan != nil)
        await service.setFailure(.noChanges)
        await model.refreshIntentPlan()
        #expect(model.intentError == nil && model.intentPlan == nil)
    }

    @MainActor @Test("Diff handoff, refresh and Agent replan retain scope until explicitly using all changes")
    func selectedScopeWorkflow() async throws {
        let fixture = try PlanningFixture(); defer { fixture.remove() }
        let service = PlanningService(); let agent = PlanningAgent()
        let model = fixture.model(service: service, agent: agent)
        let source = "diff --git a/file.txt b/file.txt\n--- a/file.txt\n+++ b/file.txt\n@@ -1 +1 @@\n-old\n+new\n"
        let document = GitParsers.diff(from: source, path: "file.txt")
        let change = WorkingTreeChange(path: "file.txt", originalPath: nil, indexStatus: .unmodified, workTreeStatus: .modified)
        let ids = Set(document.lines.filter { $0.kind == .addition || $0.kind == .deletion }.map(\.id))
        let selection = try ChangeIntentSelection(document: document, change: change, selectedIDs: ids)
        model.openIntentSelection(document: document, change: change, selectedIDs: ids, in: fixture.repository)
        model.load(repositoryURL: fixture.repository)
        try await eventually { model.intentPlan != nil && !model.isIntentBusy }
        #expect(await service.readCount == 1)
        await model.refreshIntentPlan()
        model.refineIntentPlanWithAgent()
        try await eventually { await agent.prompts.count == 1 }
        await agent.finish(0, response: PlanningFixture.response)
        try await eventually { !model.isIntentBusy }
        #expect(await service.selections == [selection, selection, selection])
        #expect(model.intentPlan?.selection == selection)
        await service.setFailure(.repositoryChanged)
        await model.refreshIntentPlan()
        #expect(model.intentSelection == selection)
        #expect(model.intentError != nil && model.intentPlan == nil)
        await service.setFailure(nil)
        await model.useAllIntentChanges()
        #expect(model.intentSelection == nil)
        #expect(model.intentPlan?.selection == nil)
        #expect(await service.selections.last! == nil)
    }

    @Test("Planning includes intent, locale and bounded redacted content")
    func contextContract() throws {
        var plan = PlanningFixture.plan()
        plan.units[0].contextPreview = String(repeating: "implementation detail\n", count: 900)
        plan.units.append(PlanningFixture.unit("private", path: ".env.local", preview: "synthetic-private-value"))
        plan.units.append(PlanningFixture.unit("config", path: "config.txt", preview: "api_key=synthetic-sensitive-value\npublic=true"))
        let prompt = try ChangeIntentAgentPlanner.prompt(for: plan, instruction: "Keep the settings and tests together", splitMode: .single, language: "zh-Hans")
        #expect(prompt.contains("Keep the settings and tests together"))
        #expect(prompt.contains("Return exactly one commit"))
        #expect(prompt.contains("zh-Hans"))
        #expect(prompt.contains("implementation detail"))
        #expect(prompt.contains("contentTruncated\":true"))
        #expect(prompt.contains("public=true"))
        #expect(!prompt.contains("synthetic-private-value"))
        #expect(!prompt.contains("synthetic-sensitive-value"))
        #expect(prompt.utf8.count < 90_000)
        plan.units = (0...500).map { PlanningFixture.unit("\($0)") }
        #expect(throws: CodexServiceError.self) { try ChangeIntentAgentPlanner.prompt(for: plan) }
    }

    @Test("Agent plans reject empty groups and enforce one-commit mode")
    func responseContract() throws {
        let plan = PlanningFixture.plan()
        let two = #"{"groups":[{"title":"A","message":"feat: A","kind":"implementation","unitIDs":["a","b"]},{"title":"B","message":"docs: B","kind":"documentation","unitIDs":["c"]}]}"#
        #expect(try ChangeIntentAgentPlanner.refinedPlan(from: two, original: plan).canApply)
        #expect(throws: ChangeIntentError.self) { try ChangeIntentAgentPlanner.refinedPlan(from: two, original: plan, splitMode: .single) }
        let empty = #"{"groups":[{"title":"A","message":"feat: A","kind":"implementation","unitIDs":["a","b","c"]},{"title":"B","message":"docs: B","kind":"documentation","unitIDs":[]}]}"#
        #expect(throws: ChangeIntentError.self) { try ChangeIntentAgentPlanner.refinedPlan(from: empty, original: plan) }
        #expect(try ChangeIntentAgentPlanner.refinedPlan(from: PlanningFixture.response, original: plan, splitMode: .single).groups.count == 1)
    }

    @MainActor
    @Test("Opening is local; explicit planning reads fresh changes through context-only Agent")
    func contextOnlyWorkflow() async throws {
        let fixture = try PlanningFixture()
        defer { fixture.remove() }
        let service = PlanningService()
        let agent = PlanningAgent()
        let model = fixture.model(service: service, agent: agent)
        model.load(repositoryURL: fixture.repository)
        try await eventually { model.intentPlan != nil }
        #expect(await agent.prompts.isEmpty)
        #expect(!model.intentPlanReady)
        model.intentInstruction = "Keep everything together"
        model.intentSplitMode = .single
        model.refineIntentPlanWithAgent()
        try await eventually { await agent.prompts.count == 1 }
        #expect(await service.readCount == 2)
        #expect(await agent.prompts[0].contains("Keep everything together"))
        #expect(!model.canApplyIntentPlan)
        model.addIntentGroup()
        #expect(model.intentPlan?.groups.count == 2)
        #expect(await model.applyIntentPlan() == false)
        await agent.finish(0, response: PlanningFixture.response)
        try await eventually { !model.isRefiningIntentPlan }
        #expect(model.intentPlanReady)
        #expect(model.intentPlan?.groups.count == 1)
        #expect(model.canApplyIntentPlan)
        #expect(await agent.repositoryRuns == 0)
        #expect(await service.applyCount == 0)
    }

    @MainActor
    @Test("Cancellation and repository changes discard late Agent results without clearing a newer run")
    func staleAgentResults() async throws {
        let fixture = try PlanningFixture()
        defer { fixture.remove() }
        let service = PlanningService()
        let agent = PlanningAgent()
        let model = fixture.model(service: service, agent: agent)
        model.load(repositoryURL: fixture.repository)
        try await eventually { model.intentPlan != nil }
        model.refineIntentPlanWithAgent()
        try await eventually { await agent.prompts.count == 1 }
        model.cancelIntentAgent()
        model.refineIntentPlanWithAgent()
        try await eventually { await agent.prompts.count == 2 }
        await agent.finish(0, response: PlanningFixture.response)
        try await eventually { await agent.completed.contains(0) }
        #expect(model.isRefiningIntentPlan)
        #expect(!model.intentPlanReady)
        await agent.finish(1, response: PlanningFixture.response)
        try await eventually { model.intentPlanReady }
        model.refineIntentPlanWithAgent()
        try await eventually { await agent.prompts.count == 3 }
        let other = fixture.root.appendingPathComponent("other")
        model.load(repositoryURL: other)
        try await eventually { model.intentPlan?.repositoryPath == other.path }
        await agent.finish(2, response: PlanningFixture.response)
        try await eventually { await agent.completed.contains(2) }
        #expect(model.intentPlan?.repositoryPath == other.path)
        #expect(!model.intentPlanReady)
        #expect(!model.isRefiningIntentPlan)
        #expect(await agent.cancelCalls == 0)
    }

    @MainActor
    @Test("Late reads cannot replace a newer draft or clear its loading state")
    func overlappingReads() async throws {
        let fixture = try PlanningFixture()
        defer { fixture.remove() }
        let service = PlanningService()
        await service.pauseReads()
        let model = fixture.model(service: service)
        model.load(repositoryURL: fixture.repository)
        try await eventually { await service.readCount == 1 }
        let newer = Task { await model.refreshIntentPlan() }
        try await eventually { await service.readCount == 2 }
        await service.finishRead(1)
        try await eventually { await service.completedReads.contains(1) }
        #expect(model.isLoadingIntentPlan)
        #expect(model.intentPlan == nil)
        await service.finishRead(2)
        await newer.value
        #expect(!model.isLoadingIntentPlan)
        #expect(model.intentPlan != nil)
    }

    @MainActor
    @Test("Manual grouping preserves coverage and incomplete plans cannot apply")
    func manualGrouping() async throws {
        let fixture = try PlanningFixture()
        defer { fixture.remove() }
        let model = fixture.model()
        model.load(repositoryURL: fixture.repository)
        try await eventually { model.intentPlan != nil }
        let original = try #require(model.intentPlan)
        #expect(original.fileCount == 3)
        #expect(original.files(in: original.groups[0]).count == 2)
        model.moveIntentUnit("unknown", to: original.groups[0].id)
        #expect(model.intentPlan == original)
        model.mergeIntentGroups()
        #expect(model.intentPlan?.groups.count == 1)
        model.splitIntentUnits(["a", "b"])
        #expect(model.intentPlan?.groups.count == 2)
        #expect(model.intentPlan?.canApply == true)
        let first = try #require(model.intentPlan?.groups.first)
        model.moveIntentGroup(first.id, offset: 1)
        #expect(model.intentPlan?.groups.last?.id == first.id)
        model.addIntentGroup()
        #expect(!model.canApplyIntentPlan)
        let added = try #require(model.intentPlan?.groups.last)
        model.moveIntentUnit("c", to: added.id)
        #expect(model.canApplyIntentPlan)
        model.updateIntentGroup(added.id, message: "  ")
        #expect(!model.canApplyIntentPlan)
        model.updateIntentGroup(added.id, message: "docs: explain settings")
        #expect(model.canApplyIntentPlan)
        #expect(Set(model.intentPlan?.groups.flatMap(\.unitIDs) ?? []) == ["a", "b", "c"])
    }

    @MainActor
    @Test("A failed Agent preserves the draft and can be retried")
    func retryAfterFailure() async throws {
        let fixture = try PlanningFixture()
        defer { fixture.remove() }
        let agent = PlanningAgent()
        let model = fixture.model(agent: agent)
        model.load(repositoryURL: fixture.repository)
        try await eventually { model.intentPlan != nil }
        let draft = model.intentPlan
        model.refineIntentPlanWithAgent()
        try await eventually { await agent.prompts.count == 1 }
        await agent.finish(0, response: "not a plan")
        try await eventually { model.intentError != nil }
        #expect(model.intentPlan == draft)
        #expect(model.canApplyIntentPlan)
        model.refineIntentPlanWithAgent()
        try await eventually { await agent.prompts.count == 2 }
        await agent.finish(1, response: PlanningFixture.response)
        try await eventually { model.intentPlanReady }
        #expect(model.intentError == nil)
    }

    @MainActor
    @Test("Commit planner renders narrow, wide, busy, empty, error and expanded states")
    func renderedStates() async throws {
        let fixture = try PlanningFixture()
        defer { fixture.remove() }
        let service = PlanningService()
        let agent = PlanningAgent()
        let model = fixture.model(service: service, agent: agent)
        let workspace = WorkspaceViewModel(repositoryBackupService: RepositoryBackupService(rootURL: fixture.root.appendingPathComponent("backups")))
        await service.pauseReads()
        model.load(repositoryURL: fixture.repository)
        try await eventually { model.isLoadingIntentPlan }
        let directory = ProcessInfo.processInfo.environment["GITGATTO_PLANNING_SNAPSHOT_DIRECTORY"].map { URL(fileURLWithPath: $0) }
        let previousLanguage = AppLanguage(rawValue: L10n.locale.identifier) ?? .system
        defer { if directory != nil { L10n.activate(previousLanguage) } }
        if directory != nil { L10n.activate(.simplifiedChinese) }
        try await render(model, workspace: workspace, width: 500, dark: false, name: "loading", directory: directory)
        await service.finishRead(1)
        await service.resumeReads()
        try await eventually { model.intentPlan != nil }
        try await render(model, workspace: workspace, width: 1_000, dark: false, name: "draft-wide", directory: directory)
        try await render(model, workspace: workspace, width: 500, dark: true, name: "draft-narrow-dark", directory: directory)
        model.refineIntentPlanWithAgent()
        try await eventually { await agent.prompts.count == 1 }
        try await render(model, workspace: workspace, width: 500, dark: false, name: "planning", directory: directory)
        await agent.finish(0, response: PlanningFixture.response)
        try await eventually { model.intentPlanReady }
        try await render(model, workspace: workspace, width: 1_000, dark: true, name: "ready-wide-dark", directory: directory)
        model.addIntentGroup()
        try await render(model, workspace: workspace, width: 500, dark: false, name: "editor-narrow", directory: directory, scrollToEnd: true)
        if directory != nil {
            L10n.activate(.german)
            try await render(model, workspace: workspace, width: 500, dark: false, name: "german-narrow", directory: directory, scrollToEnd: true)
            L10n.activate(.arabic)
            try await render(model, workspace: workspace, width: 500, dark: true, name: "arabic-narrow", directory: directory, rtl: true)
            L10n.activate(.simplifiedChinese)
        }
        await service.setFailure(.noChanges)
        await model.refreshIntentPlan()
        try await render(model, workspace: workspace, width: 500, dark: false, name: "empty", directory: directory)
        await service.setFailure(.invalidPlan(String(repeating: "Cannot read the updated repository. Refresh and retry. ", count: 4)))
        await model.refreshIntentPlan()
        try await render(model, workspace: workspace, width: 500, dark: true, name: "error", directory: directory)
        await service.setFailure(nil)
        await model.refreshIntentPlan()
        let applying = Task { await model.applyIntentPlan() }
        try await eventually { model.isApplyingIntentPlan }
        try await render(model, workspace: workspace, width: 500, dark: false, name: "applying", directory: directory)
        await service.finishApply()
        #expect(await applying.value)
        try await render(model, workspace: workspace, width: 500, dark: true, name: "success", directory: directory)
    }

    @MainActor
    private func render(_ model: RepositoryIntelligenceViewModel, workspace: WorkspaceViewModel, width: CGFloat, dark: Bool,
                        name: String, directory: URL?, scrollToEnd: Bool = false, rtl: Bool = false) async throws {
        let view = RepositoryIntelligenceWorkspaceView(model: model, workspaceModel: workspace)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            .environment(\.dynamicTypeSize, .accessibility1)
            .frame(width: width, height: 700)
        let host = NSHostingView(rootView: view)
        let window = PlanningRenderWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        defer { window.close() }
        host.frame = NSRect(x: 0, y: 0, width: width, height: 700)
        host.layoutSubtreeIfNeeded()
        for _ in 0..<6 { await Task.yield() }
        if scrollToEnd {
            for scroll in descendants(host).compactMap({ $0 as? NSScrollView }) where scroll.hasVerticalScroller {
                if let document = scroll.documentView {
                    document.scroll(NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
            }
            host.layoutSubtreeIfNeeded()
            for _ in 0..<6 { await Task.yield() }
        }
        let fields = descendants(host).compactMap { $0 as? NSTextField }.filter(\.isEditable)
        if name == "editor-narrow" { #expect(!fields.isEmpty) }
        for field in fields.prefix(1) { #expect(window.makeFirstResponder(field)) }
        host.layoutSubtreeIfNeeded()
        #expect(host.bounds.width == width)
        for scroll in descendants(host).compactMap({ $0 as? NSScrollView }) where scroll.hasVerticalScroller {
            if let document = scroll.documentView {
                #expect(document.frame.width <= scroll.contentView.bounds.width + 2)
            }
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(data.count > 8_000)
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(name + ".png"))
            let metrics: [String: Any] = ["width": width, "height": 700, "editableFields": fields.count,
                "focusedField": fields.first.map { window.firstResponder === $0.currentEditor() } ?? false,
                "verticalScrollViews": descendants(host).compactMap { $0 as? NSScrollView }.filter(\.hasVerticalScroller).count]
            try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys, .prettyPrinted])
                .write(to: directory.appendingPathComponent(name + ".json"))
        }
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    @MainActor
    private func eventually(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw PlanningFailure.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct PlanningFixture {
    let root: URL
    var repository: URL { root.appendingPathComponent("repository") }
    static let response = #"{"groups":[{"title":"改进设置与说明","message":"feat: improve settings and help","kind":"implementation","unitIDs":["a","b","c"]}]}"#
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("GitGatto-Planning-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    @MainActor func model(service: PlanningService = PlanningService(), agent: PlanningAgent = PlanningAgent()) -> RepositoryIntelligenceViewModel {
        RepositoryIntelligenceViewModel(intentService: service,
            capsuleService: ReproductionCapsuleService(rootURL: root.appendingPathComponent("capsules"), worktreeRootURL: root.appendingPathComponent("worktrees")),
            activityLedger: RepositoryActivityLedger(rootURL: root.appendingPathComponent("ledger")), agentService: agent)
    }
    static func unit(_ id: String, path: String? = nil, preview: String? = nil) -> ChangeIntentUnit {
        ChangeIntentUnit(id: id, path: path ?? "Sources/Preferences/\(id).swift", originalPath: nil, kind: .wholeFile,
                         status: "??", hunkHeader: nil, patch: nil, addedLineCount: 12, deletedLineCount: 2, contextPreview: preview)
    }
    static func plan(in url: URL = URL(fileURLWithPath: "/tmp/synthetic-planning")) -> ChangeIntentPlan {
        let units = [unit("a", path: "Sources/Settings/VeryLongDirectoryName/AdvancedRepositorySettingsView.swift"),
                     unit("b", path: "Tests/AdvancedRepositorySettingsTests.swift"), unit("c", path: "docs/settings.md")]
        return ChangeIntentPlan(repositoryPath: url.path, repositoryFingerprint: "synthetic", units: units, groups: [
            ChangeIntentGroup(title: "调整仓库设置并补充回归测试", commitMessage: "feat: improve repository settings and regression coverage", kind: .implementation, unitIDs: ["a", "b"]),
            ChangeIntentGroup(title: "补充使用说明", commitMessage: "docs: explain repository settings", kind: .documentation, unitIDs: ["c"]),
        ])
    }
}

private actor PlanningService: ChangeIntentServing {
    var readCount = 0
    var selections: [ChangeIntentSelection?] = []
    var applyCount = 0
    private var failure: ChangeIntentError?
    private var gitFailure: GitCommandError?
    private var applyGate: CheckedContinuation<Void, Never>?
    private var readsPaused = false
    private var readGates: [Int: CheckedContinuation<Void, Never>] = [:]
    var completedReads: Set<Int> = []
    func pauseReads() { readsPaused = true }
    func resumeReads() { readsPaused = false }
    func finishRead(_ index: Int) { readGates.removeValue(forKey: index)?.resume() }
    func makePlan(in repositoryURL: URL, selection: ChangeIntentSelection?) async throws -> ChangeIntentPlan {
        selections.append(selection)
        readCount += 1
        let index = readCount
        if readsPaused { await withCheckedContinuation { readGates[index] = $0 } }
        completedReads.insert(index)
        if let gitFailure { throw gitFailure }
        if let failure { throw failure }
        var plan = PlanningFixture.plan(in: repositoryURL)
        plan.selection = selection
        return plan
    }
    func apply(_ plan: ChangeIntentPlan, verificationCommand: String?, in repositoryURL: URL) async -> ChangeIntentApplyResult {
        applyCount += 1
        await withCheckedContinuation { applyGate = $0 }
        return ChangeIntentApplyResult(commitHashes: ["1234567890abcdef", "abcdef1234567890"], verificationOutputs: [])
    }
    func setGitFailure(_ value: GitCommandError?) { gitFailure = value }
    func setFailure(_ value: ChangeIntentError?) { failure = value }
    func finishApply() { applyGate?.resume(); applyGate = nil }
}

private actor PlanningAgent: CodexServing {
    var prompts: [String] = []
    var repositoryRuns = 0
    var cancelCalls = 0
    var completed: Set<Int> = []
    private var gates: [Int: CheckedContinuation<String, Never>] = [:]
    func runWithProvidedContext(prompt: String, context: [CodexMessage]) async -> CodexRunResult {
        let index = prompts.count
        prompts.append(prompt)
        let response = await withCheckedContinuation { gates[index] = $0 }
        completed.insert(index)
        return CodexRunResult(response: response, commandCount: 0, fileChangeCount: 0)
    }
    func finish(_ index: Int, response: String) { gates.removeValue(forKey: index)?.resume(returning: response) }
    func run(prompt: String, context: [CodexMessage], in repositoryURL: URL, mode: CodexRunMode) throws -> CodexRunResult {
        repositoryRuns += 1
        throw PlanningFailure.unexpected
    }
    func probe() -> CodexAvailability { CodexAvailability(state: .available, version: "synthetic") }
    func draftPullRequestReply(context: GitHubPullRequestContext) throws -> String { throw PlanningFailure.unexpected }
    func translate(_ text: String, target: CodexTranslationTarget) throws -> String { throw PlanningFailure.unexpected }
    func translateHTML(_ html: String, target: CodexTranslationTarget, progress: @escaping @Sendable (Int, Int) async -> Void) throws -> String { throw PlanningFailure.unexpected }
    func cancel() { cancelCalls += 1 }
}

private enum PlanningFailure: Error { case unexpected, timeout }
@MainActor private final class PlanningRenderWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
