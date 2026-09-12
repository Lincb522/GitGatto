import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class RepositoryIntelligenceViewModel: ObservableObject {
    @Published var selectedTab: RepositoryIntelligenceTab = .intent

    @Published private(set) var intentSelection: ChangeIntentSelection?
    @Published private(set) var intentPlan: ChangeIntentPlan?
    @Published var selectedIntentGroupID: UUID?
    @Published var verificationCommand = ""
    @Published var intentInstruction = ""
    @Published var intentSplitMode: ChangeIntentSplitMode = .automatic
    @Published private(set) var intentPlanReady = false
    @Published private(set) var isLoadingIntentPlan = false
    @Published private(set) var isRefiningIntentPlan = false
    @Published private(set) var isApplyingIntentPlan = false
    @Published private(set) var intentError: AppErrorReport?
    @Published private(set) var intentApplyResult: ChangeIntentApplyResult?

    @Published var provenanceRevision: String?
    @Published var provenancePath = ""
    @Published var provenanceLine = "1"
    @Published private(set) var provenanceReport: CodeProvenanceReport?
    @Published private(set) var isTracingProvenance = false
    @Published private(set) var provenanceError: AppErrorReport?

    @Published private(set) var capsules: [ReproductionCapsule] = []
    @Published var selectedCapsuleID: UUID?
    @Published var capsuleFailingCommand = ""
    @Published var capsuleFailureOutput = ""
    @Published private(set) var isWorkingWithCapsule = false
    @Published private(set) var capsuleError: AppErrorReport?
    @Published private(set) var restoredCapsuleURL: URL?

    @Published private(set) var activityEvents: [RepositoryActivityEvent] = []
    @Published var selectedActivityEventID: UUID?
    @Published private(set) var isLoadingActivity = false
    @Published private(set) var activityError: AppErrorReport?

    @Published private(set) var notice: String?

    private let intentService: any ChangeIntentServing
    private let provenanceService: any CodeProvenanceServing
    private let capsuleService: any ReproductionCapsuleServing
    private let activityLedger: any RepositoryActivityLedgerServing
    private let agentService: any CodexServing
    private var repositoryURL: URL?
    private var loadTask: Task<Void, Never>?
    private var agentTask: Task<Void, Never>?
    private var intentLoadID = UUID()
    private var intentAgentID = UUID()

    var isIntentBusy: Bool { isLoadingIntentPlan || isRefiningIntentPlan || isApplyingIntentPlan }
    var canApplyIntentPlan: Bool { !isIntentBusy && intentPlan?.canApply == true }

    init(
        intentService: any ChangeIntentServing,
        provenanceService: any CodeProvenanceServing = CodeProvenanceService(),
        capsuleService: any ReproductionCapsuleServing = ReproductionCapsuleService(),
        activityLedger: any RepositoryActivityLedgerServing = RepositoryActivityLedger.shared,
        agentService: any CodexServing = CodexService()
    ) {
        self.intentService = intentService
        self.provenanceService = provenanceService
        self.capsuleService = capsuleService
        self.activityLedger = activityLedger
        self.agentService = agentService
    }

    deinit {
        loadTask?.cancel()
        agentTask?.cancel()
    }

    var selectedCapsule: ReproductionCapsule? {
        guard let selectedCapsuleID else { return capsules.first }
        return capsules.first(where: { $0.id == selectedCapsuleID })
    }

    var selectedActivityEvent: RepositoryActivityEvent? {
        guard let selectedActivityEventID else { return activityEvents.first }
        return activityEvents.first(where: { $0.id == selectedActivityEventID })
    }

    func load(repositoryURL: URL) {
        let repository = repositoryURL.standardizedFileURL
        guard self.repositoryURL != repository else { return }
        self.repositoryURL = repository
        resetForRepositoryChange()
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            async let intent: Void = self.refreshIntentPlan()
            async let capsules: Void = self.refreshCapsules()
            async let activity: Void = self.refreshActivity()
            _ = await (intent, capsules, activity)
        }
    }

    func openIntentSelection(document: DiffDocument, change: WorkingTreeChange, selectedIDs: Set<UUID>, in repository: URL) {
        guard !isApplyingIntentPlan else { return }
        if repositoryURL != repository.standardizedFileURL {
            resetForRepositoryChange()
            repositoryURL = repository.standardizedFileURL
        }
        loadTask?.cancel()
        cancelIntentAgent()
        intentPlan = nil
        intentError = nil
        intentApplyResult = nil
        selectedTab = .intent
        do {
            intentSelection = try ChangeIntentSelection(document: document, change: change, selectedIDs: selectedIDs)
        } catch {
            intentSelection = nil
            intentError = GlobalErrorHandler.report(for: error, context: .intelligence(.intent), repositoryURL: repositoryURL)
            return
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            async let intent: Void = self.refreshIntentPlan()
            async let capsules: Void = self.refreshCapsules()
            async let activity: Void = self.refreshActivity()
            _ = await (intent, capsules, activity)
        }
    }

    func useAllIntentChanges() async {
        guard !isIntentBusy else { return }
        intentSelection = nil
        await refreshIntentPlan()
    }

    func refreshIntentPlan() async {
        guard !Task.isCancelled, let repositoryURL, !isApplyingIntentPlan else { return }
        cancelIntentAgent()
        let operationID = UUID()
        intentLoadID = operationID
        isLoadingIntentPlan = true
        intentError = nil
        intentApplyResult = nil
        defer { if intentLoadID == operationID { isLoadingIntentPlan = false } }
        do {
            let plan = try await intentService.makePlan(in: repositoryURL, selection: intentSelection)
            try Task.checkCancellation()
            guard self.repositoryURL == repositoryURL, intentLoadID == operationID else { return }
            intentPlan = plan
            intentPlanReady = false
            selectedIntentGroupID = plan.groups.first?.id
        } catch {
            guard !(error is CancellationError), self.repositoryURL == repositoryURL,
                  intentLoadID == operationID else { return }
            intentPlan = nil
            selectedIntentGroupID = nil
            intentError = (error as? ChangeIntentError) == .noChanges ? nil : GlobalErrorHandler.report(for: error, context: .intelligence(.intent), repositoryURL: repositoryURL)
        }
    }

    func refineIntentPlanWithAgent() {
        guard let repositoryURL, intentPlan != nil, !isIntentBusy else { return }
        let operationID = UUID()
        intentAgentID = operationID
        let selection = intentSelection
        let instruction = intentInstruction
        let splitMode = intentSplitMode
        let language = L10n.locale.identifier
        isRefiningIntentPlan = true
        intentError = nil
        notice = nil
        agentTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.intentAgentID == operationID {
                    self.isRefiningIntentPlan = false
                    self.agentTask = nil
                }
            }
            do {
                let plan = try await intentService.makePlan(in: repositoryURL, selection: selection)
                try Task.checkCancellation()
                let result = try await agentService.runWithProvidedContext(
                    prompt: ChangeIntentAgentPlanner.prompt(for: plan, instruction: instruction,
                        splitMode: splitMode, language: language), context: []
                )
                try Task.checkCancellation()
                let refined = try ChangeIntentAgentPlanner.refinedPlan(
                    from: result.response, original: plan, splitMode: splitMode
                )
                guard self.repositoryURL == repositoryURL, self.intentAgentID == operationID else { return }
                self.intentPlan = refined
                self.intentPlanReady = true
                self.selectedIntentGroupID = refined.groups.first?.id
            } catch {
                guard !(error is CancellationError), self.repositoryURL == repositoryURL,
                      self.intentAgentID == operationID else { return }
                self.intentError = GlobalErrorHandler.report(for: error, context: .intelligence(.intent), repositoryURL: repositoryURL)
            }
        }
    }

    func cancelIntentAgent() {
        intentAgentID = UUID()
        agentTask?.cancel()
        agentTask = nil
        isRefiningIntentPlan = false
    }

    func addIntentGroup() {
        guard !isIntentBusy, var plan = intentPlan else { return }
        let group = ChangeIntentGroup(
            title: L10n.text("intelligence.intent.new_group"),
            commitMessage: "chore: organize changes",
            kind: .other,
            unitIDs: []
        )
        plan.groups.append(group)
        intentPlanReady = true
        intentPlan = plan
        selectedIntentGroupID = group.id
    }

    func removeIntentGroup(_ id: UUID) {
        guard !isIntentBusy, var plan = intentPlan,
              plan.groups.count > 1,
              let index = plan.groups.firstIndex(where: { $0.id == id })
        else { return }
        let units = plan.groups[index].unitIDs
        plan.groups.remove(at: index)
        plan.groups[0].unitIDs.append(contentsOf: units)
        intentPlanReady = true
        intentPlan = plan
        selectedIntentGroupID = plan.groups.first?.id
    }

    func moveIntentGroup(_ id: UUID, offset: Int) {
        guard !isIntentBusy, var plan = intentPlan,
              let source = plan.groups.firstIndex(where: { $0.id == id })
        else { return }
        let destination = source + offset
        guard plan.groups.indices.contains(destination) else { return }
        plan.groups.swapAt(source, destination)
        intentPlanReady = true
        intentPlan = plan
        selectedIntentGroupID = id
    }

    func updateIntentGroup(
        _ id: UUID,
        title: String? = nil,
        message: String? = nil,
        kind: ChangeIntentKind? = nil
    ) {
        guard !isIntentBusy, var plan = intentPlan,
              let index = plan.groups.firstIndex(where: { $0.id == id }) else { return }
        if let title { plan.groups[index].title = title }
        if let message { plan.groups[index].commitMessage = message }
        if let kind { plan.groups[index].kind = kind }
        intentPlanReady = true
        intentPlan = plan
    }

    func moveIntentUnit(_ unitID: String, to groupID: UUID) {
        guard !isIntentBusy, var plan = intentPlan,
              plan.units.contains(where: { $0.id == unitID }),
              plan.groups.contains(where: { $0.id == groupID }) else { return }
        for index in plan.groups.indices {
            plan.groups[index].unitIDs.removeAll { $0 == unitID }
        }
        guard let target = plan.groups.firstIndex(where: { $0.id == groupID }) else { return }
        plan.groups[target].unitIDs.append(unitID)
        if plan.groups.count > 1 {
            plan.groups.removeAll { $0.unitIDs.isEmpty }
        }
        intentPlanReady = true
        intentPlan = plan
        selectedIntentGroupID = groupID
    }

    func mergeIntentGroups() {
        guard !isIntentBusy, var plan = intentPlan, var first = plan.groups.first else { return }
        first.unitIDs = plan.groups.flatMap(\.unitIDs)
        plan.groups = [first]
        intentPlan = plan
        intentPlanReady = true
        selectedIntentGroupID = first.id
    }

    func splitIntentUnits(_ unitIDs: [String]) {
        guard !isIntentBusy, var plan = intentPlan, !unitIDs.isEmpty,
              Set(unitIDs).count == unitIDs.count,
              unitIDs.allSatisfy({ id in plan.units.contains { $0.id == id } }),
              let first = plan.units.first(where: { unitIDs.contains($0.id) }) else { return }
        for index in plan.groups.indices { plan.groups[index].unitIDs.removeAll { unitIDs.contains($0) } }
        plan.groups.removeAll { $0.unitIDs.isEmpty }
        let name = URL(fileURLWithPath: first.path).deletingPathExtension().lastPathComponent
        let group = ChangeIntentGroup(title: name, commitMessage: "chore: update " + name,
            kind: ChangeIntentService.kind(for: first.path), unitIDs: unitIDs)
        plan.groups.append(group)
        intentPlan = plan
        intentPlanReady = true
        selectedIntentGroupID = group.id
    }

    func applyIntentPlan() async -> Bool {
        guard let repositoryURL, let plan = intentPlan, canApplyIntentPlan else { return false }
        isApplyingIntentPlan = true
        intentError = nil
        intentApplyResult = nil
        defer { isApplyingIntentPlan = false }
        do {
            let result = try await intentService.apply(
                plan,
                verificationCommand: verificationCommand,
                in: repositoryURL
            )
            guard self.repositoryURL == repositoryURL else {
                isApplyingIntentPlan = false
                await refreshIntentPlan()
                return false
            }
            intentApplyResult = result
            intentPlan = nil
            return true
        } catch {
            guard self.repositoryURL == repositoryURL else {
                isApplyingIntentPlan = false
                await refreshIntentPlan()
                return false
            }
            if !(error is CancellationError) { intentError = GlobalErrorHandler.report(for: error, context: .intelligence(.intent), repositoryURL: repositoryURL) }
            return false
        }
    }

    func traceProvenance() async {
        guard let repositoryURL, !isTracingProvenance else { return }
        let path = provenancePath
        guard let line = Int(provenanceLine) else {
            provenanceError = GlobalErrorHandler.report(for: CodeProvenanceError.invalidLine, context: .intelligence(.provenance), repositoryURL: repositoryURL)
            return
        }
        isTracingProvenance = true
        provenanceError = nil
        provenanceReport = nil
        defer { isTracingProvenance = false }
        do {
            let revision = provenanceRevision
            let report: CodeProvenanceReport
            if let revision {
                report = try await provenanceService.trace(commitHash: revision, filePath: path, line: line, in: repositoryURL)
            } else {
                report = try await provenanceService.trace(filePath: path, line: line, in: repositoryURL)
            }
            guard provenancePath == path, provenanceLine == String(line), provenanceRevision == revision else { return }
            guard self.repositoryURL == repositoryURL else { return }
            provenanceReport = report
        } catch is CancellationError {
            return
        } catch {
            guard self.repositoryURL == repositoryURL else { return }
            provenanceError = GlobalErrorHandler.report(for: error, context: .intelligence(.provenance), repositoryURL: repositoryURL)
        }
    }

    func chooseCapsuleExportDestination() async {
        guard let repositoryURL, !isWorkingWithCapsule else { return }
        let panel = NSSavePanel()
        panel.title = L10n.text("intelligence.capsule.export")
        panel.nameFieldStringValue = "\(repositoryURL.lastPathComponent)-failure.gatto"
        panel.allowedContentTypes = [UTType(filenameExtension: "gatto") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await exportCapsule(to: url)
    }

    func exportCapsule(to destinationURL: URL) async {
        guard let repositoryURL, !isWorkingWithCapsule else { return }
        isWorkingWithCapsule = true
        capsuleError = nil
        defer { isWorkingWithCapsule = false }
        do {
            let capsule = try await capsuleService.export(
                from: repositoryURL,
                failingCommand: capsuleFailingCommand,
                failureOutput: capsuleFailureOutput,
                to: destinationURL
            )
            await refreshCapsules()
            selectedCapsuleID = capsule.id
            notice = L10n.text("intelligence.capsule.notice.exported")
        } catch is CancellationError {
            return
        } catch {
            capsuleError = GlobalErrorHandler.report(for: error, context: .intelligence(.capsules), repositoryURL: repositoryURL)
        }
    }

    func chooseCapsuleImport() async {
        guard !isWorkingWithCapsule else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.text("intelligence.capsule.import")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "gatto") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await importCapsule(at: url)
    }

    func importCapsule(at archiveURL: URL) async {
        guard !isWorkingWithCapsule else { return }
        isWorkingWithCapsule = true
        capsuleError = nil
        defer { isWorkingWithCapsule = false }
        do {
            let capsule = try await capsuleService.importArchive(at: archiveURL)
            await refreshCapsules()
            selectedCapsuleID = capsule.id
            notice = L10n.text("intelligence.capsule.notice.imported")
        } catch is CancellationError {
            return
        } catch {
            capsuleError = GlobalErrorHandler.report(for: error, context: .intelligence(.capsules), repositoryURL: repositoryURL)
        }
    }

    func restoreSelectedCapsule() async {
        guard let repositoryURL, let capsule = selectedCapsule, !isWorkingWithCapsule else { return }
        isWorkingWithCapsule = true
        capsuleError = nil
        restoredCapsuleURL = nil
        defer { isWorkingWithCapsule = false }
        do {
            let url = try await capsuleService.restore(capsule, in: repositoryURL)
            restoredCapsuleURL = url
            notice = L10n.text("intelligence.capsule.notice.restored")
        } catch is CancellationError {
            return
        } catch {
            capsuleError = GlobalErrorHandler.report(for: error, context: .intelligence(.capsules), repositoryURL: repositoryURL)
        }
    }

    func deleteSelectedCapsule() async {
        guard let capsule = selectedCapsule, !isWorkingWithCapsule else { return }
        isWorkingWithCapsule = true
        capsuleError = nil
        defer { isWorkingWithCapsule = false }
        do {
            try await capsuleService.delete(capsule)
            await refreshCapsules()
        } catch {
            capsuleError = GlobalErrorHandler.report(for: error, context: .intelligence(.capsules), repositoryURL: repositoryURL)
        }
    }

    func revealRestoredCapsule() {
        guard let restoredCapsuleURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([restoredCapsuleURL])
    }

    func refreshCapsules() async {
        do {
            let values = try await capsuleService.capsules()
            capsules = values
            if let selectedCapsuleID,
               !values.contains(where: { $0.id == selectedCapsuleID })
            {
                self.selectedCapsuleID = values.first?.id
            } else if selectedCapsuleID == nil {
                selectedCapsuleID = values.first?.id
            }
            capsuleError = nil
        } catch {
            capsuleError = GlobalErrorHandler.report(for: error, context: .intelligence(.capsules), repositoryURL: repositoryURL)
        }
    }

    func refreshActivity() async {
        guard let repositoryURL else { return }
        isLoadingActivity = true
        activityError = nil
        defer { isLoadingActivity = false }
        await activityLedger.seed([repositoryURL])
        let values = await activityLedger.events(for: repositoryURL)
        guard self.repositoryURL == repositoryURL else { return }
        activityEvents = values
        if let selectedActivityEventID,
           !values.contains(where: { $0.id == selectedActivityEventID })
        {
            self.selectedActivityEventID = values.first?.id
        } else if selectedActivityEventID == nil {
            selectedActivityEventID = values.first?.id
        }
    }

    func clearActivity() async {
        guard let repositoryURL else { return }
        do {
            try await activityLedger.clearEvents(for: repositoryURL)
            activityEvents = []
            selectedActivityEventID = nil
            activityError = nil
        } catch {
            activityError = GlobalErrorHandler.report(for: error, context: .intelligence(.activity), repositoryURL: repositoryURL)
        }
    }

    func dismissNotice() {
        notice = nil
    }

    private func resetForRepositoryChange() {
        loadTask?.cancel()
        cancelIntentAgent()
        intentLoadID = UUID()
        isLoadingIntentPlan = false
        intentPlanReady = false
        intentInstruction = ""
        intentSelection = nil
        intentSplitMode = .automatic
        verificationCommand = ""
        intentPlan = nil
        selectedIntentGroupID = nil
        intentApplyResult = nil
        intentError = nil
        provenanceRevision = nil
        provenancePath = ""
        provenanceLine = "1"
        provenanceReport = nil
        provenanceError = nil
        capsules = []
        selectedCapsuleID = nil
        restoredCapsuleURL = nil
        capsuleError = nil
        activityEvents = []
        selectedActivityEventID = nil
        activityError = nil
        notice = nil
    }
}
