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
        await store.replace([])
        await model.loadProjectGoals()
        try await render(ProjectGoalsWorkspaceView(model: model), CGSize(width: 560, height: 700), .light, "empty")
        for size in [CGSize(width: 420, height: 620), CGSize(width: 960, height: 760)] {
            for kind in ProjectGoalKind.templates {
                try await render(ProjectGoalComposerView(model: model, initialKind: kind, onCreated: {}, onCancel: {}), size, .light, "composer-\(kind.rawValue)")
            }
        }
    }

    @MainActor
    private func render<V: View>(_ view: V, _ size: CGSize, _ scheme: ColorScheme, _ name: String) async throws {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppPalette(scheme).background)
            .environment(\.colorScheme, scheme)
            .environment(\.locale, L10n.locale))
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
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
                let previous = scroll.contentView.bounds.origin.y
                let bottom = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
                scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
                scroll.reflectScrolledClipView(scroll.contentView)
                await Task.yield()
                host.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                #expect(abs(scroll.contentView.bounds.origin.y - previous) > 1)
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
