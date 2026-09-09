import AppKit
import SwiftUI
import Testing
@testable import GitGatto

@Suite("Goal workspace", .serialized)
struct ProjectGoalWorkspaceTests {
    @Test("Terminal goals have no executable action", arguments: [ProjectGoalStatus.completed, .cancelled])
    func terminalActions(status: ProjectGoalStatus) {
        for kind in ProjectGoalKind.templates {
            var goal = fixture(kind: kind)
            goal.status = status
            #expect(goal.nextAction == nil)
            #expect(!goal.canEditCommitMessage)
        }
    }

    @Test("Every goal status uses a bundled Reicon asset")
    func statusIconsExist() {
        for status in [ProjectGoalStatus.ready, .running, .waiting, .blocked, .completed, .cancelled] {
            let name = GattoIconAssets.assetName(for: ProjectGoalAppearance.icon(status))
            let bundle = AppResourceBundle.current
            #expect(bundle.url(forResource: name, withExtension: "svg", subdirectory: "UIIcons")
                ?? bundle.url(forResource: name, withExtension: "svg") != nil)
        }
    }

    @Test("Next actions retain release, merge and installation gates")
    func actionGates() {
        var goal = fixture(kind: .completeRelease)
        #expect(goal.nextAction == .refresh)
        goal.updateStep(.readme, status: .blocked)
        #expect(goal.nextAction == .prepareRelease)
        for kind in goal.kind.stepKinds.prefix(8) { goal.updateStep(kind, status: .completed) }
        #expect(goal.nextAction == .publish)
        for kind in [ProjectGoalStepKind.releaseTag, .githubRelease, .dmg] { goal.updateStep(kind, status: .completed) }
        #expect(goal.nextAction == .refresh)
        goal.updateStep(.updateFeed, status: .completed)
        #expect(goal.nextAction == .install)
        var delivery = fixture(kind: .githubDelivery)
        for kind in delivery.kind.stepKinds.dropLast() { delivery.updateStep(kind, status: .notRequired) }
        #expect(delivery.nextAction == .refresh)
        delivery.pullRequestNumber = 10
        #expect(delivery.nextAction == .merge)
        delivery.updateStep(.review, status: .waiting)
        #expect(delivery.nextAction == .refresh)
    }

    @Test("History filtering and ordering are independent of monitor timestamps")
    func historyFilter() {
        var active = fixture()
        active.commitMessage = "Fix toolbar layout"
        var older = fixture()
        older.status = .completed
        older.commitMessage = "Ship release"
        older.updatedAt = .distantFuture
        let values = [older, active]
        #expect(ProjectGoalPresentation.goals(values, filter: .all, query: "").first?.id == active.id)
        #expect(ProjectGoalPresentation.goals(values, filter: .history, query: "").map(\.id) == [older.id])
        #expect(ProjectGoalPresentation.goals(values, filter: .active, query: "toolbar").map(\.id) == [active.id])
        #expect(ProjectGoalPresentation.goals(values, filter: .all, query: "feature/goals").count == 2)
        #expect(ProjectGoalPresentation.goals(values, filter: .history, query: "toolbar").isEmpty)
    }

    @Test("Current goal takes precedence over the last selected history item")
    func primaryGoal() {
        let active = fixture()
        var history = fixture()
        history.status = .completed
        #expect(ProjectGoalPresentation.primaryGoal([history, active], selectedID: history.id)?.id == active.id)
        #expect(ProjectGoalPresentation.primaryGoal([history], selectedID: history.id)?.id == history.id)
        #expect(ProjectGoalPresentation.primaryGoal([], selectedID: nil) == nil)
    }

    @Test("Phases summarize existing steps without altering the persisted contract")
    func phases() throws {
        var goal = fixture(kind: .completeRelease)
        #expect(goal.phases == [.prepare, .submit, .deliver, .install])
        #expect(!goal.phaseIsComplete(.prepare))
        for kind in [ProjectGoalStepKind.readme, .translation, .version, .changelog, .releasePipeline] {
            goal.updateStep(kind, status: .notRequired)
        }
        #expect(goal.phaseIsComplete(.prepare))
        #expect(!goal.phaseIsComplete(.verify))
        let data = try JSONEncoder().encode(goal)
        #expect(try JSONDecoder().decode(ProjectGoal.self, from: data) == goal)
        #expect(!String(decoding: data, as: UTF8.self).contains("phases"))
    }

    @MainActor
    @Test("Starting a confirmed goal never crosses publication, installation, merge or selection gates")
    func startGates() async {
        for next in [ProjectGoalStepKind.releaseTag, .localApplication, .merge] {
            var goal = fixture(kind: next == .merge ? .githubDelivery : .completeRelease)
            for step in goal.steps.map(\.kind).prefix(while: { $0 != next }) {
                goal.updateStep(step, status: .completed)
            }
            goal.pullRequestNumber = 10
            let runtime = GoalWorkspaceRuntime()
            let model = await model(GoalWorkspaceStore([goal]), runtime)
            await model.startProjectGoal(id: goal.id)
            #expect(await runtime.executions == 0)
            #expect(await runtime.observations == 0)
        }
        let goal = fixture()
        let runtime = GoalWorkspaceRuntime()
        let model = await model(GoalWorkspaceStore([goal]), runtime)
        await model.startProjectGoal(id: UUID())
        #expect(await runtime.executions == 0)
        #expect(await runtime.observations == 0)
    }

    @MainActor
    @Test("A failed save cannot create and start a goal")
    func failedCreation() async {
        let store = GoalWorkspaceStore([])
        await store.setFailSaves()
        let runtime = GoalWorkspaceRuntime()
        let model = await model(store, runtime)
        model.projectGoalCommitMessage = "Do not execute"
        if await model.createProjectDeliveryGoal(), let id = model.selectedProjectGoal?.id {
            await model.startProjectGoal(id: id)
        }
        #expect(model.projectGoals.isEmpty)
        #expect(await runtime.executions == 0)
    }

    @MainActor
    @Test("A failed repair-plan save preserves failure evidence and never starts Agent")
    func failedRepairSave() async throws {
        var goal = fixture()
        goal.status = .blocked
        goal.lastActionFailure = ProjectGoalActionFailure(runID: 1, runNumber: 1, workflowName: "CI", conclusion: "failure",
            webURL: try #require(URL(string: "https://example.invalid/actions/1")), logExcerpt: nil)
        let store = GoalWorkspaceStore([goal])
        await store.setFailSaves()
        let agent = GoalRepairAgent(outcome: .success)
        let runtime = GoalWorkspaceRuntime()
        let model = WorkspaceViewModel(codexService: agent, codexConversationStore: GoalTestConversationStore(),
            projectGoalStore: store, makeProjectGoalRuntime: { _, _ in runtime })
        model.appPreferences.monitoringEngineEnabled = false
        model.apply(snapshot())
        await model.loadProjectGoals()
        model.retryCodexProbe()
        let deadline = ContinuousClock.now + .seconds(2)
        while model.codexAvailability.state != .available, ContinuousClock.now < deadline { await Task.yield() }
        #expect(model.canRepairSelectedProjectGoalWithAgent)
        await model.repairSelectedProjectGoalWithAgent()
        #expect(model.selectedProjectGoal == goal)
        #expect(model.activeProjectGoalID == nil)
        #expect(model.projectGoalAgentID == nil)
        #expect(!model.isCodexRunning)
    }

    @MainActor
    @Test("Agent repair stays in Goals and only resumes after success", arguments: GoalRepairOutcome.allCases)
    private func agentContinuation(outcome: GoalRepairOutcome) async throws {
        var goal = fixture()
        goal.status = .blocked
        goal.lastActionFailure = ProjectGoalActionFailure(
            runID: 1, runNumber: 1, workflowName: "CI", conclusion: "failure",
            webURL: try #require(URL(string: "https://example.invalid/actions/1")), logExcerpt: "test failure"
        )
        let runtime = GoalWorkspaceRuntime()
        let agent = GoalRepairAgent(outcome: outcome)
        let model = WorkspaceViewModel(codexService: agent, codexConversationStore: GoalTestConversationStore(),
                                       projectGoalStore: GoalWorkspaceStore([goal]), makeProjectGoalRuntime: { _, _ in runtime })
        model.appPreferences.monitoringEngineEnabled = false
        model.appPreferences.agentEditProtectionEnabled = false
        model.selectedSection = .goals
        model.apply(snapshot())
        await model.loadProjectGoals()
        model.retryCodexProbe()
        let deadline = ContinuousClock.now + .seconds(2)
        while model.codexAvailability.state != .available, ContinuousClock.now < deadline { await Task.yield() }
        #expect(model.codexAvailability.state == .available)
        let task = Task { await model.repairSelectedProjectGoalWithAgent() }
        await agent.waitUntilRunning()
        #expect(model.projectGoalAgentID == goal.id)
        #expect(model.selectedSection == .goals)
        #expect(!model.canPerformProjectGoalAction(.continueDelivery))
        switch outcome {
        case .cancel: model.cancelCodex()
        case .branchChanged: model.apply(snapshot(branch: "other"))
        default: break
        }
        await agent.resume()
        await task.value
        #expect(model.projectGoalAgentID == nil)
        #expect(model.selectedSection == .goals)
        #expect((await runtime.executions > 0) == (outcome == .success))
        if [.failure, .cancellationError, .cancel].contains(outcome) {
            #expect(model.selectedProjectGoal?.nextAction == .repair)
            #expect(model.selectedProjectGoal?.status == .blocked)
            #expect(model.selectedProjectGoal?.lastError?.isEmpty == false)
        }
    }

    @Test("Simplified goal controls are localized in every supported language")
    func newTranslations() throws {
        let keys = ["goal.workspace.current", "goal.workspace.start", "goal.workspace.waiting_auto",
                    "goal.workspace.agent_record", "goal.workspace.agent_continuation"]
            + ProjectGoalKind.templates.map { "goal.quick.\($0.rawValue)" }
            + ["deliverChanges", "githubDelivery", "completeRelease"].map { "goal.scope.\($0)" }
            + ["prepare", "submit", "verify", "publish", "merge", "install"].map { "goal.phase.\($0)" }
        for language in ["en", "zh-Hans", "zh-Hant", "ja", "ko", "fr", "de", "es", "pt-BR", "ru", "ar"] {
            let url = try #require(L10n.bundle(preferredLanguages: [language]).url(forResource: "Localizable", withExtension: "strings"))
            let values = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
            for key in keys { #expect(values[key]?.isEmpty == false, "\(language): \(key)") }
        }
    }

    @MainActor
    @Test("An in-flight refresh cannot undo cancellation or a saved message", arguments: [false, true], [false, true])
    func staleRefresh(editMessage: Bool, failure: Bool) async throws {
        let goal = fixture()
        let store = GoalWorkspaceStore([goal])
        let runtime = GoalWorkspaceRuntime(paused: true, fails: failure)
        let model = await model(store, runtime)
        let refresh = Task { await model.refreshProjectGoal(id: goal.id, showErrors: false) }
        await runtime.waitUntilObserving()
        if editMessage {
            #expect(await model.updateSelectedProjectGoalCommitMessage("A saved new message"))
        } else {
            await model.cancelSelectedProjectGoal()
        }
        let expected = try #require(model.selectedProjectGoal)
        await runtime.resume()
        await refresh.value
        #expect(model.selectedProjectGoal == expected)
        #expect(await store.load().first == expected)
    }

    @MainActor
    @Test("Refresh deduplicates concurrent requests and ignores changed array positions")
    func refreshIdentity() async throws {
        let goal = fixture()
        let store = GoalWorkspaceStore([goal])
        let runtime = GoalWorkspaceRuntime(paused: true)
        let model = await model(store, runtime)
        let first = Task { await model.refreshProjectGoal(id: goal.id, showErrors: false) }
        await runtime.waitUntilObserving()
        await model.refreshProjectGoal(id: goal.id, showErrors: false)
        #expect(await runtime.observations == 1)
        let other = fixture()
        await store.replace([other, goal])
        await model.loadProjectGoals()
        await runtime.resume()
        await first.value
        #expect(model.projectGoals.first { $0.id == other.id } == other)
        #expect(model.projectGoals.first { $0.id == goal.id }?.id == goal.id)
    }

    @MainActor
    @Test("Execution completion can supersede a background observation")
    func completionSupersedesRefresh() async {
        let goal = fixture()
        let runtime = GoalWorkspaceRuntime(paused: true)
        let store = GoalWorkspaceStore([goal])
        let model = await model(store, runtime)
        let background = Task { await model.refreshProjectGoal(id: goal.id, showErrors: false) }
        await runtime.waitUntilObserving()
        let completion = Task { await model.refreshProjectGoal(id: goal.id, showErrors: true, allowActiveExecution: true) }
        await runtime.waitUntilObserving(2)
        await runtime.resume()
        await background.value
        await completion.value
        #expect(await runtime.observations == 2)
        #expect(await store.saveCount == 1)
    }

    @MainActor
    @Test("Failed saves roll back message edits and cancellation", arguments: [false, true])
    func failedSave(editMessage: Bool) async throws {
        let goal = fixture()
        let store = GoalWorkspaceStore([goal])
        let model = await model(store, GoalWorkspaceRuntime())
        await store.setFailSaves()
        if editMessage {
            #expect(await !model.updateSelectedProjectGoalCommitMessage("Do not lose the old message"))
        } else {
            await model.cancelSelectedProjectGoal()
        }
        #expect(model.selectedProjectGoal == goal)
        #expect(await store.load() == [goal])
        #expect(model.activeProjectGoalID == nil)
    }

    @MainActor
    @Test("Creating a goal saves its plan without executing Git")
    func createDoesNotExecute() async throws {
        let runtime = GoalWorkspaceRuntime()
        let store = GoalWorkspaceStore([])
        let model = await model(store, runtime)
        model.projectGoalCommitMessage = "Create a plan only"
        #expect(await model.createProjectDeliveryGoal())
        #expect(model.currentRepositoryGoals.count == 1)
        #expect(await runtime.executions == 0)
        #expect(await !model.createGitHubDeliveryGoal())
        #expect(model.currentRepositoryGoals.count == 1)
    }

    @MainActor
    @Test("Cancelled delivery cannot be restarted through the model")
    func cancelledCannotExecute() async {
        var goal = fixture()
        goal.status = .cancelled
        let runtime = GoalWorkspaceRuntime()
        let model = await model(GoalWorkspaceStore([goal]), runtime)
        await model.continueSelectedProjectGoal()
        #expect(await runtime.executions == 0)
        #expect(await runtime.observations == 0)
        #expect(model.selectedProjectGoal?.status == .cancelled)
    }

    @Test("Planning identity rejects repository, branch and HEAD changes")
    func planningIdentity() {
        let original = snapshot()
        #expect(ProjectGoalPlanningIdentity(original) == ProjectGoalPlanningIdentity(snapshot()))
        #expect(ProjectGoalPlanningIdentity(original) != ProjectGoalPlanningIdentity(snapshot(branch: "other")))
        #expect(ProjectGoalPlanningIdentity(original) != ProjectGoalPlanningIdentity(snapshot(head: "bbb")))
    }

    @MainActor
    @Test("Goal surfaces render at compact and wide sizes in light, dark and RTL layouts")
    func renderSurfaces() async throws {
        if ProcessInfo.processInfo.environment["GITGATTO_GOAL_UI_OUTPUT"] == nil {
            let goal = fixture()
            let model = await model(GoalWorkspaceStore([goal]), GoalWorkspaceRuntime(cancelObservation: true))
            try await render(ProjectGoalsWorkspaceView(model: model), CGSize(width: 700, height: 620), .light, "smoke")
            return
        }
        let originalLanguage = AppPreferencesStore.load().language
        let originalArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        defer {
            L10n.activate(originalLanguage)
            UserDefaults.standard.setVolatileDomain(originalArguments, forName: UserDefaults.argumentDomain)
        }
        L10n.activate(.simplifiedChinese)
        let store = GoalWorkspaceStore([])
        let runtime = GoalWorkspaceRuntime(cancelObservation: true)
        let model = await model(store, runtime)
        var goal = fixture(kind: .githubDelivery)
        goal.commitMessage = "Fix keyboard navigation and long repository names without losing the selected goal"
        goal.lastError = "Push was rejected. Refresh the repository state and check the remote permission before retrying."
        for kind in [ProjectGoalStepKind.stageChanges, .commit] { goal.updateStep(kind, status: .completed, evidence: "0123456789abcdef") }
        goal.status = .blocked
        goal.updateStep(.push, status: .blocked, error: goal.lastError)
        await store.replace([goal])
        await model.loadProjectGoals()
        for size in [CGSize(width: 560, height: 700), CGSize(width: 1120, height: 760)] {
            for scheme in [ColorScheme.light, .dark] {
                try await render(ProjectGoalsWorkspaceView(model: model), size, scheme, "workspace")
                try await render(ProjectGoalDetailView(model: model, goal: goal), size, scheme, "detail")
            }
        }
        for theme in [AppVisualTheme.lumen, .console, .folio] {
            var arguments = originalArguments
            arguments[AppStyleDefaults.themeKey] = theme.rawValue
            UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            try await render(ProjectGoalsWorkspaceView(model: model), CGSize(width: 1120, height: 760), .light, "workspace-\(theme.rawValue)")
            try await render(ProjectGoalsWorkspaceView(model: model), CGSize(width: 1120, height: 760), .dark, "workspace-\(theme.rawValue)")
        }
        UserDefaults.standard.setVolatileDomain(originalArguments, forName: UserDefaults.argumentDomain)
        try await render(ProjectGoalComposerView(model: model, onCreated: {}, onCancel: {}), CGSize(width: 420, height: 620), .light, "existing-goal")
        for status in [ProjectGoalStatus.ready, .waiting, .completed, .cancelled] {
            var state = fixture()
            state.status = status
            if status == .waiting || status == .completed {
                state.targetHeadSHA = "aaa"
                for kind in state.kind.stepKinds { state.updateStep(kind, status: .completed) }
                if status == .waiting { state.updateStep(.actions, status: .waiting) }
            }
            await store.replace([state])
            await model.loadProjectGoals()
            try await render(ProjectGoalDetailView(model: model, goal: state), CGSize(width: 560, height: 700), .light, "state-\(status.rawValue)")
            if status == .waiting {
                model.appPreferences.monitoringEngineEnabled = true
                model.appPreferences.projectGoalMonitoringEnabled = true
                try await render(ProjectGoalDetailView(model: model, goal: state), CGSize(width: 420, height: 620), .dark, "waiting-auto")
                model.appPreferences.monitoringEngineEnabled = false
            }
            if status == .completed {
                try await render(ProjectGoalHistoryView(model: model, onSelected: {}), CGSize(width: 420, height: 620), .dark, "history")
            }
        }
        let runningRuntime = GoalWorkspaceRuntime(paused: true)
        let runningGoal = fixture()
        let runningModel = await self.model(GoalWorkspaceStore([runningGoal]), runningRuntime)
        let execution = Task { await runningModel.continueSelectedProjectGoal() }
        await runningRuntime.waitUntilObserving()
        try await render(ProjectGoalDetailView(model: runningModel, goal: runningGoal), CGSize(width: 560, height: 700), .light, "executing")
        execution.cancel()
        await runningRuntime.resume()
        await execution.value
        await store.replace([goal])
        await model.loadProjectGoals()
        L10n.activate(.arabic)
        try await render(ProjectGoalDetailView(model: model, goal: goal).environment(\.layoutDirection, .rightToLeft),
                         CGSize(width: 560, height: 700), .light, "detail-rtl")
        L10n.activate(.simplifiedChinese)
        try await render(ProjectGoalDetailView(model: model, goal: goal)
            .dynamicTypeSize(.accessibility3), CGSize(width: 420, height: 620), .dark, "accessible")
        await store.replace([])
        await model.loadProjectGoals()
        try await render(ProjectGoalsWorkspaceView(model: model), CGSize(width: 560, height: 700), .light, "empty")
        L10n.activate(.german)
        try await render(ProjectGoalComposerView(model: model, initialKind: .githubDelivery, onCreated: {}, onCancel: {}),
                         CGSize(width: 420, height: 620), .light, "composer-german")
        L10n.activate(.arabic)
        try await render(ProjectGoalComposerView(model: model, onCreated: {}, onCancel: {})
            .environment(\.layoutDirection, .rightToLeft), CGSize(width: 420, height: 620), .dark, "composer-rtl")
        L10n.activate(.simplifiedChinese)
        for size in [CGSize(width: 420, height: 620), CGSize(width: 960, height: 760)] {
            for kind in ProjectGoalKind.templates {
                try await render(ProjectGoalComposerView(model: model, initialKind: kind, onCreated: {}, onCancel: {}), size, .light, "composer-\(kind.rawValue)")
            }
        }
    }

    @MainActor
    private func render<V: View>(_ view: V, _ size: CGSize, _ scheme: ColorScheme, _ name: String) async throws {
        let window = GoalRenderWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: name == "accessible" ? .accessibilityHighContrastDarkAqua : scheme == .dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppPalette(scheme).background)
            .environment(\.colorScheme, scheme)
            .environment(\.locale, L10n.locale))
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        // Yield to SwiftUI's layout transaction before capturing this test-owned window.
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        if name == "composer-deliverChanges" {
            window.makeKeyAndOrderFront(nil)
            let deadline = ContinuousClock.now + .seconds(2)
            while !(window.firstResponder is NSTextView), ContinuousClock.now < deadline { await Task.yield() }
            #expect(window.firstResponder is NSTextView, "The commit field accepts keyboard focus")
        }
        #expect(abs(host.bounds.width - size.width) < 1)
        #expect(abs(host.bounds.height - size.height) < 1)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(data.count > 1000)
        if let path = ProcessInfo.processInfo.environment["GITGATTO_GOAL_UI_OUTPUT"] {
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("\(name)-\(Int(size.width))-\(scheme).png"))
            if name == "composer-completeRelease", size.width == 420 {
                let scroll = try #require(firstScrollView(in: host))
                let document = try #require(scroll.documentView)
                let bottom = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
                scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
                scroll.reflectScrolledClipView(scroll.contentView)
                await Task.yield()
                host.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                #expect(abs(scroll.contentView.bounds.origin.y - bottom) < 1)
                #expect(document.bounds.width <= scroll.contentView.bounds.width + 1)
                let bottomBitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bottomBitmap)
                let bottomPNG = try #require(bottomBitmap.representation(using: .png, properties: [:]))
                try bottomPNG.write(to: directory.appendingPathComponent("composer-release-bottom.png"))
            }
        }
    }

    @MainActor
    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { firstScrollView(in: $0) }.first
    }

    @MainActor
    private func model(_ store: GoalWorkspaceStore, _ runtime: GoalWorkspaceRuntime) async -> WorkspaceViewModel {
        let model = WorkspaceViewModel(projectGoalStore: store, makeProjectGoalRuntime: { _, _ in runtime })
        model.appPreferences.monitoringEngineEnabled = false
        model.selectedSection = .goals
        model.apply(snapshot())
        await model.loadProjectGoals()
        return model
    }

    private func snapshot(branch: String = "feature/goals", head: String = "aaa") -> RepositorySnapshot {
        RepositorySnapshot(rootURL: URL(fileURLWithPath: "/tmp/gitgatto-goal-fixture"), branchName: branch,
                           upstreamName: "origin/main", aheadCount: 0, behindCount: 0,
                           changes: [WorkingTreeChange(path: "App.swift", originalPath: nil, indexStatus: .unmodified, workTreeStatus: .modified)],
                           commits: [CommitRecord(hash: head, shortHash: head, author: "Fixture", date: .distantPast, subject: "Baseline")], branches: [])
    }

    private func fixture(kind: ProjectGoalKind = .deliverChanges) -> ProjectGoal {
        ProjectGoal(kind: kind, repositoryPath: "/tmp/gitgatto-goal-fixture", repositoryName: "GitGatto",
                    branchName: "feature/goals", baselineHeadSHA: "aaa", commitMessage: "Fix the goal workspace", createdAt: .distantPast)
    }
}

private enum GoalWorkspaceFailure: Error { case expected }

private actor GoalWorkspaceStore: ProjectGoalStoring {
    private var goals: [ProjectGoal]
    private var failSaves = false
    private(set) var saveCount = 0
    init(_ goals: [ProjectGoal]) { self.goals = goals }
    func load() -> [ProjectGoal] { goals }
    func save(_ goals: [ProjectGoal]) throws {
        if failSaves { throw GoalWorkspaceFailure.expected }
        self.goals = goals
        saveCount += 1
    }
    func replace(_ goals: [ProjectGoal]) { self.goals = goals }
    func setFailSaves() { failSaves = true }
}

private actor GoalWorkspaceRuntime: ProjectGoalRunning {
    private let paused: Bool
    private let fails: Bool
    private let cancelObservation: Bool
    private var started: [(Int, CheckedContinuation<Void, Never>)] = []
    private var gates: [CheckedContinuation<Void, Never>] = []
    private(set) var observations = 0
    private(set) var executions = 0
    init(paused: Bool = false, fails: Bool = false, cancelObservation: Bool = false) {
        self.paused = paused
        self.fails = fails
        self.cancelObservation = cancelObservation
    }
    func observe(_ goal: ProjectGoal) async throws -> ProjectGoalObservation {
        observations += 1
        if paused {
            await withCheckedContinuation {
                gates.append($0)
                let ready = started.filter { $0.0 <= observations }
                started.removeAll { $0.0 <= observations }
                ready.forEach { $0.1.resume() }
            }
        }
        try Task.checkCancellation()
        if cancelObservation { throw CancellationError() }
        if fails { throw GoalWorkspaceFailure.expected }
        return ProjectGoalObservation(branchName: goal.branchName, upstreamName: "origin/main", aheadCount: 0,
                                      changes: [WorkingTreeChange(path: "App.swift", originalPath: nil, indexStatus: .unmodified, workTreeStatus: .modified)],
                                      headSHA: "aaa", targetPublished: false, remoteIdentity: nil, actions: .noWorkflows,
                                      pullRequest: .unavailable, baseBranch: nil)
    }
    func execute(_ step: ProjectGoalStepKind, goal: ProjectGoal) async throws -> ProjectGoalExecutionResult {
        executions += 1
        return .none
    }
    func waitUntilObserving(_ count: Int = 1) async {
        if observations >= count { return }
        await withCheckedContinuation { started.append((count, $0)) }
    }
    func resume() {
        let pending = gates
        gates.removeAll()
        pending.forEach { $0.resume() }
    }
}

@MainActor private final class GoalRenderWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private enum GoalRepairOutcome: CaseIterable, Sendable { case success, failure, cancellationError, cancel, branchChanged }

private actor GoalTestConversationStore: CodexConversationStoring {
    func load(for repositoryURL: URL) -> [CodexMessage] { [] }
    func save(_ messages: [CodexMessage], for repositoryURL: URL) {}
}

private actor GoalRepairAgent: CodexServing {
    private let outcome: GoalRepairOutcome
    private var running = false
    private var started: CheckedContinuation<Void, Never>?
    private var gate: CheckedContinuation<Void, Never>?
    init(outcome: GoalRepairOutcome) { self.outcome = outcome }
    func probe() -> CodexAvailability { CodexAvailability(state: .available, version: "fixture") }
    func run(prompt: String, context: [CodexMessage], in repositoryURL: URL, mode: CodexRunMode) async throws -> CodexRunResult {
        running = true
        await withCheckedContinuation { gate = $0; started?.resume(); started = nil }
        if outcome == .failure { throw GoalWorkspaceFailure.expected }
        if outcome == .cancellationError { throw CancellationError() }
        return CodexRunResult(response: "Repair complete", commandCount: 1, fileChangeCount: 1)
    }
    func waitUntilRunning() async {
        if !running { await withCheckedContinuation { started = $0 } }
    }
    func resume() { gate?.resume(); gate = nil }
    func runWithProvidedContext(prompt: String, context: [CodexMessage]) throws -> CodexRunResult { throw GoalWorkspaceFailure.expected }
    func draftPullRequestReply(context: GitHubPullRequestContext) throws -> String { throw GoalWorkspaceFailure.expected }
    func translate(_ text: String, target: CodexTranslationTarget) throws -> String { throw GoalWorkspaceFailure.expected }
    func translateHTML(_ html: String, target: CodexTranslationTarget, progress: @escaping @Sendable (Int, Int) async -> Void) throws -> String { throw GoalWorkspaceFailure.expected }
    func cancel() {}
}
