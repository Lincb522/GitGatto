import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class RepositoryIntelligenceViewModel: ObservableObject {
    @Published var selectedTab: RepositoryIntelligenceTab = .intent

    @Published private(set) var intentPlan: ChangeIntentPlan?
    @Published var selectedIntentGroupID: UUID?
    @Published var selectedIntentUnitID: String?
    @Published var verificationCommand = ""
    @Published private(set) var isLoadingIntentPlan = false
    @Published private(set) var isRefiningIntentPlan = false
    @Published private(set) var isApplyingIntentPlan = false
    @Published private(set) var intentError: String?
    @Published private(set) var intentApplyResult: ChangeIntentApplyResult?

    @Published var provenancePath = ""
    @Published var provenanceLine = "1"
    @Published private(set) var provenanceReport: CodeProvenanceReport?
    @Published private(set) var isTracingProvenance = false
    @Published private(set) var provenanceError: String?

    @Published private(set) var capsules: [ReproductionCapsule] = []
    @Published var selectedCapsuleID: UUID?
    @Published var capsuleFailingCommand = ""
    @Published var capsuleFailureOutput = ""
    @Published private(set) var isWorkingWithCapsule = false
    @Published private(set) var capsuleError: String?
    @Published private(set) var restoredCapsuleURL: URL?

    @Published private(set) var activityEvents: [RepositoryActivityEvent] = []
    @Published var selectedActivityEventID: UUID?
    @Published private(set) var isLoadingActivity = false
    @Published private(set) var activityError: String?

    @Published private(set) var notice: String?

    private let intentService: any ChangeIntentServing
    private let provenanceService: any CodeProvenanceServing
    private let capsuleService: any ReproductionCapsuleServing
    private let activityLedger: any RepositoryActivityLedgerServing
    private let agentService: any CodexServing
    private var repositoryURL: URL?
    private var loadTask: Task<Void, Never>?
    private var agentTask: Task<Void, Never>?

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

    var selectedIntentGroup: ChangeIntentGroup? {
        guard let selectedIntentGroupID else { return intentPlan?.groups.first }
        return intentPlan?.groups.first(where: { $0.id == selectedIntentGroupID })
    }

    var selectedIntentUnit: ChangeIntentUnit? {
        guard let selectedIntentUnitID else { return nil }
        return intentPlan?.units.first(where: { $0.id == selectedIntentUnitID })
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

    func refreshIntentPlan() async {
        guard let repositoryURL, !isApplyingIntentPlan else { return }
        isLoadingIntentPlan = true
        intentError = nil
        intentApplyResult = nil
        defer { isLoadingIntentPlan = false }
        do {
            let plan = try await intentService.makePlan(in: repositoryURL)
            guard self.repositoryURL == repositoryURL else { return }
            intentPlan = plan
            selectedIntentGroupID = plan.groups.first?.id
            selectedIntentUnitID = plan.groups.first?.unitIDs.first
        } catch is CancellationError {
            return
        } catch ChangeIntentError.noChanges {
            intentPlan = nil
            selectedIntentGroupID = nil
            selectedIntentUnitID = nil
        } catch {
            guard self.repositoryURL == repositoryURL else { return }
            intentPlan = nil
            intentError = error.localizedDescription
        }
    }

    func refineIntentPlanWithAgent() {
        guard let repositoryURL, let plan = intentPlan, !isRefiningIntentPlan else { return }
        agentTask?.cancel()
        isRefiningIntentPlan = true
        intentError = nil
        agentTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isRefiningIntentPlan = false }
            do {
                let result = try await agentService.run(
                    prompt: ChangeIntentAgentPlanner.prompt(for: plan),
                    context: [],
                    in: repositoryURL,
                    mode: .analyze
                )
                let refined = try ChangeIntentAgentPlanner.refinedPlan(
                    from: result.response,
                    original: plan
                )
                guard self.repositoryURL == repositoryURL,
                      self.intentPlan?.id == plan.id else { return }
                self.intentPlan = refined
                self.selectedIntentGroupID = refined.groups.first?.id
                self.selectedIntentUnitID = refined.groups.first?.unitIDs.first
                self.notice = L10n.text("intelligence.intent.notice.refined")
            } catch is CancellationError {
                return
            } catch {
                guard self.repositoryURL == repositoryURL else { return }
                self.intentError = error.localizedDescription
            }
        }
    }

    func cancelIntentAgent() {
        agentTask?.cancel()
        agentTask = nil
        isRefiningIntentPlan = false
        Task { await agentService.cancel() }
    }

    func addIntentGroup() {
        guard var plan = intentPlan else { return }
        let group = ChangeIntentGroup(
            title: L10n.text("intelligence.intent.new_group"),
            commitMessage: "chore: organize changes",
            kind: .other,
            unitIDs: []
        )
        plan.groups.append(group)
        intentPlan = plan
        selectedIntentGroupID = group.id
    }

    func removeIntentGroup(_ id: UUID) {
        guard var plan = intentPlan,
              plan.groups.count > 1,
              let index = plan.groups.firstIndex(where: { $0.id == id })
        else { return }
        let units = plan.groups[index].unitIDs
        plan.groups.remove(at: index)
        plan.groups[0].unitIDs.append(contentsOf: units)
        intentPlan = plan
        selectedIntentGroupID = plan.groups.first?.id
    }

    func moveIntentGroup(_ id: UUID, offset: Int) {
        guard var plan = intentPlan,
              let source = plan.groups.firstIndex(where: { $0.id == id })
        else { return }
        let destination = source + offset
        guard plan.groups.indices.contains(destination) else { return }
        plan.groups.swapAt(source, destination)
        intentPlan = plan
        selectedIntentGroupID = id
    }

    func updateIntentGroup(
        _ id: UUID,
        title: String? = nil,
        message: String? = nil,
        kind: ChangeIntentKind? = nil
    ) {
        guard var plan = intentPlan,
              let index = plan.groups.firstIndex(where: { $0.id == id }) else { return }
        if let title { plan.groups[index].title = title }
        if let message { plan.groups[index].commitMessage = message }
        if let kind { plan.groups[index].kind = kind }
        intentPlan = plan
    }

    func moveIntentUnit(_ unitID: String, to groupID: UUID) {
        guard var plan = intentPlan,
              plan.groups.contains(where: { $0.id == groupID }) else { return }
        for index in plan.groups.indices {
            plan.groups[index].unitIDs.removeAll { $0 == unitID }
        }
        guard let target = plan.groups.firstIndex(where: { $0.id == groupID }) else { return }
        plan.groups[target].unitIDs.append(unitID)
        if plan.groups.count > 1 {
            plan.groups.removeAll { $0.unitIDs.isEmpty }
        }
        intentPlan = plan
        selectedIntentGroupID = groupID
        selectedIntentUnitID = unitID
    }

    func applyIntentPlan() async -> Bool {
        guard let repositoryURL, let plan = intentPlan, !isApplyingIntentPlan else { return false }
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
            guard self.repositoryURL == repositoryURL else { return false }
            intentApplyResult = result
            intentPlan = nil
            notice = L10n.format("intelligence.intent.notice.applied", result.commitHashes.count)
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard self.repositoryURL == repositoryURL else { return false }
            intentError = error.localizedDescription
            return false
        }
    }

    func traceProvenance() async {
        guard let repositoryURL, !isTracingProvenance else { return }
        let path = provenancePath
        guard let line = Int(provenanceLine) else {
            provenanceError = CodeProvenanceError.invalidLine.localizedDescription
            return
        }
        isTracingProvenance = true
        provenanceError = nil
        provenanceReport = nil
        defer { isTracingProvenance = false }
        do {
            let report = try await provenanceService.trace(
                filePath: path,
                line: line,
                in: repositoryURL
            )
            guard self.repositoryURL == repositoryURL else { return }
            provenanceReport = report
        } catch is CancellationError {
            return
        } catch {
            guard self.repositoryURL == repositoryURL else { return }
            provenanceError = error.localizedDescription
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
            capsuleError = error.localizedDescription
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
            capsuleError = error.localizedDescription
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
            capsuleError = error.localizedDescription
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
            capsuleError = error.localizedDescription
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
            capsuleError = error.localizedDescription
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
            activityError = error.localizedDescription
        }
    }

    func dismissNotice() {
        notice = nil
    }

    private func resetForRepositoryChange() {
        loadTask?.cancel()
        agentTask?.cancel()
        intentPlan = nil
        selectedIntentGroupID = nil
        selectedIntentUnitID = nil
        intentApplyResult = nil
        intentError = nil
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
