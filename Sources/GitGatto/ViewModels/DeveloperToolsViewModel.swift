import Combine
import Foundation

@MainActor
final class DeveloperToolsViewModel: ObservableObject {
    @Published var query = ""
    @Published var category: DevelopmentToolCategory = .all
    @Published var selectedTool: DevelopmentTool?
    @Published private(set) var statuses: [String: DevelopmentToolStatus] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var isCheckingUpdates = false

    private let installer: any CodexServing
    private let probe: any DevelopmentToolProbing
    private let updateChecker: any DevelopmentToolUpdateChecking
    private let environmentConfigurator: any DevelopmentToolEnvironmentConfiguring
    private var operationTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var hasLoaded = false

    init(
        installer: any CodexServing = CodexService(lane: .installer),
        probe: any DevelopmentToolProbing = DevelopmentToolProbe(),
        updateChecker: any DevelopmentToolUpdateChecking = DevelopmentToolUpdateService(),
        environmentConfigurator: any DevelopmentToolEnvironmentConfiguring = DevelopmentToolEnvironmentConfigurator()
    ) {
        self.installer = installer
        self.probe = probe
        self.updateChecker = updateChecker
        self.environmentConfigurator = environmentConfigurator
        selectedTool = DevelopmentTool.catalog.first

#if DEBUG
        if ProcessInfo.processInfo.environment["GITGATTO_DEVELOPER_TOOLS_UPDATES_PREVIEW"] == "1" {
            applyPreviewState()
        }
#endif
    }

    var filteredTools: [DevelopmentTool] {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return DevelopmentTool.catalog.filter { tool in
            let status = status(for: tool)
            let matchesCategory: Bool
            switch category {
            case .all:
                matchesCategory = true
            case .installed:
                matchesCategory = status.isInstalled
            case .updates:
                matchesCategory = status.updateAvailability == .available
            default:
                matchesCategory = tool.category == category
            }
            guard matchesCategory else { return false }
            guard !input.isEmpty else { return true }
            return tool.name.localizedCaseInsensitiveContains(input)
                || L10n.text(tool.summaryKey).localizedCaseInsensitiveContains(input)
        }
    }

    var activeInstallationToolID: String? {
        statuses.first(where: { $0.value.state == .installing })?.key
    }

    var updateCount: Int {
        statuses.values.filter { $0.updateAvailability == .available }.count
    }

    func status(for tool: DevelopmentTool) -> DevelopmentToolStatus {
        statuses[tool.id] ?? DevelopmentToolStatus()
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        refresh()
    }

    func select(_ tool: DevelopmentTool) {
        selectedTool = tool
    }

    func changeCategory(_ newCategory: DevelopmentToolCategory) {
        category = newCategory
        keepSelectionVisible()
    }

    func refresh() {
        refreshTask?.cancel()
        updateTask?.cancel()
        let probe = self.probe
        refreshTask = Task {
            isRefreshing = true
            let tools = DevelopmentTool.catalog
            let batchSize = 8
            for start in stride(from: 0, to: tools.count, by: batchSize) {
                guard !Task.isCancelled else { break }
                let end = min(start + batchSize, tools.count)
                await withTaskGroup(of: (String, DevelopmentToolProbeResult).self) { group in
                    for tool in tools[start..<end] {
                        group.addTask {
                            (tool.id, await probe.probe(tool))
                        }
                    }
                    for await (id, result) in group {
                        guard !Task.isCancelled else {
                            group.cancelAll()
                            return
                        }
                        var status = statuses[id] ?? DevelopmentToolStatus()
                        guard status.state != .installing else { continue }
                        status.isInstalled = result.isInstalled
                        status.version = result.version
                        status.state = result.isInstalled ? .installed : .idle
                        status.operation = nil
                        if result.isInstalled { status.detail = nil }
                        statuses[id] = status
                    }
                }
            }
            isRefreshing = false
            refreshTask = nil
            guard !Task.isCancelled else { return }
            checkForUpdates()
        }
    }

    func checkForUpdates() {
        updateTask?.cancel()
        let installedTools = DevelopmentTool.catalog.filter { status(for: $0).isInstalled }
        guard !installedTools.isEmpty else {
            keepSelectionVisible()
            return
        }
        for tool in installedTools {
            var status = statuses[tool.id] ?? DevelopmentToolStatus()
            guard status.state != .installing else { continue }
            status.updateAvailability = .checking
            status.updateDetail = nil
            statuses[tool.id] = status
        }

        let checker = updateChecker
        updateTask = Task {
            isCheckingUpdates = true
            let results = await checker.checkUpdates(for: installedTools)
            guard !Task.isCancelled else {
                isCheckingUpdates = false
                updateTask = nil
                return
            }
            for tool in installedTools {
                guard let result = results[tool.id] else { continue }
                apply(result, to: tool)
            }
            isCheckingUpdates = false
            updateTask = nil
            keepSelectionVisible()
        }
    }

    func install(_ tool: DevelopmentTool) {
        perform(.install, tool: tool)
    }

    func upgrade(_ tool: DevelopmentTool) {
        guard status(for: tool).canUpgrade else { return }
        perform(.upgrade, tool: tool)
    }

    func cancelInstallation() {
        guard let toolID = activeInstallationToolID else { return }
        operationTask?.cancel()
        operationTask = nil
        let installer = self.installer
        Task { await installer.cancel() }
        var status = statuses[toolID] ?? DevelopmentToolStatus()
        status.state = status.isInstalled ? .installed : .idle
        status.operation = nil
        status.phase = nil
        status.detail = L10n.text("installer.error.cancelled")
        statuses[toolID] = status
    }

    private func perform(_ operation: DevelopmentToolOperation, tool: DevelopmentTool) {
        guard activeInstallationToolID == nil else { return }
        operationTask?.cancel()
        let startingStatus = statuses[tool.id] ?? DevelopmentToolStatus()
        let packageName = startingStatus.updatePackageName ?? tool.homebrewFormula
        if operation == .upgrade, packageName == nil { return }

        var status = startingStatus
        status.state = .installing
        status.operation = operation
        status.phase = .preparing
        status.detail = phaseText(operation, phase: .preparing)
        status.result = nil
        statuses[tool.id] = status

        let installer = self.installer
        let probe = self.probe
        let checker = self.updateChecker
        let environmentConfigurator = self.environmentConfigurator
        operationTask = Task {
            do {
                let result: CodexRunResult
                switch operation {
                case .install:
                    result = try await installer.installDevelopmentTool(tool) { [weak self] progress in
                        await self?.apply(progress, operation: operation, to: tool)
                    }
                case .upgrade:
                    result = try await installer.upgradeDevelopmentTool(
                        tool,
                        packageName: packageName ?? "",
                        installedVersion: startingStatus.version,
                        latestVersion: startingStatus.latestVersion
                    ) { [weak self] progress in
                        await self?.apply(progress, operation: operation, to: tool)
                    }
                }

                guard !Task.isCancelled else { return }
                let verification = await probe.probe(tool)
                var environmentConfiguration: DevelopmentToolEnvironmentConfiguration = .unchanged
                var environmentConfigurationError: Error?
                if verification.isInstalled, let executableURL = verification.executableURL {
                    var configuring = statuses[tool.id] ?? DevelopmentToolStatus()
                    configuring.phase = .configuring
                    configuring.detail = phaseText(operation, phase: .configuring)
                    statuses[tool.id] = configuring
                    do {
                        environmentConfiguration = try await environmentConfigurator.configure(
                            executableURL: executableURL
                        )
                    } catch {
                        environmentConfigurationError = error
                    }
                }
                let updateResults = verification.isInstalled
                    ? await checker.checkUpdates(for: [tool])
                    : [:]
                let updateResult = updateResults[tool.id]

                var completed = statuses[tool.id] ?? DevelopmentToolStatus()
                completed.operation = nil
                completed.phase = nil
                completed.isInstalled = verification.isInstalled
                completed.version = updateResult?.installedVersion ?? verification.version
                completed.result = result.response
                if let updateResult {
                    applyUpdate(updateResult, to: &completed)
                }

                switch operation {
                case .install:
                    if let environmentConfigurationError {
                        completed.state = .actionRequired
                        completed.detail = L10n.format(
                            "developer_tools.install.configuration_failed",
                            environmentConfigurationError.localizedDescription
                        )
                    } else {
                        completed.state = verification.isInstalled ? .installed : .actionRequired
                        completed.detail = verification.isInstalled
                            ? environmentConfiguration == .unchanged
                                ? L10n.text("developer_tools.install.verified")
                                : L10n.text("developer_tools.install.configured")
                            : L10n.text("developer_tools.install.action_required")
                    }
                case .upgrade:
                    let upgraded = verification.isInstalled
                        && updateResult?.availability != .available
                    if let environmentConfigurationError {
                        completed.state = .actionRequired
                        completed.detail = L10n.format(
                            "developer_tools.upgrade.configuration_failed",
                            environmentConfigurationError.localizedDescription
                        )
                    } else {
                        completed.state = upgraded ? .installed : .actionRequired
                        completed.detail = upgraded
                            ? environmentConfiguration == .unchanged
                                ? L10n.text("developer_tools.upgrade.verified")
                                : L10n.text("developer_tools.upgrade.configured")
                            : L10n.text("developer_tools.upgrade.action_required")
                    }
                }
                statuses[tool.id] = completed
            } catch is CancellationError {
                restoreAfterCancellation(tool)
            } catch {
                var failed = statuses[tool.id] ?? DevelopmentToolStatus()
                failed.state = .failed
                failed.operation = nil
                failed.phase = nil
                failed.detail = error.localizedDescription
                statuses[tool.id] = failed
            }
            operationTask = nil
        }
    }

    private func apply(
        _ progress: AgentInstallProgress,
        operation: DevelopmentToolOperation,
        to tool: DevelopmentTool
    ) {
        var current = statuses[tool.id] ?? DevelopmentToolStatus()
        current.state = .installing
        current.operation = operation
        current.phase = progress.phase
        current.detail = progress.detail ?? phaseText(operation, phase: progress.phase)
        statuses[tool.id] = current
    }

    private func phaseText(_ operation: DevelopmentToolOperation, phase: AgentInstallPhase) -> String {
        switch operation {
        case .install:
            L10n.text("installer.phase.\(phase.rawValue)")
        case .upgrade:
            L10n.text("developer_tools.upgrade.phase.\(phase.rawValue)")
        }
    }

    private func apply(_ result: DevelopmentToolUpdateResult, to tool: DevelopmentTool) {
        var status = statuses[tool.id] ?? DevelopmentToolStatus()
        applyUpdate(result, to: &status)
        statuses[tool.id] = status
    }

    private func applyUpdate(_ result: DevelopmentToolUpdateResult, to status: inout DevelopmentToolStatus) {
        status.updateAvailability = result.availability
        status.latestVersion = result.latestVersion
        status.updatePackageName = result.packageName
        status.isUpdatePinned = result.isPinned
        status.updateDetail = result.detail
        if let installedVersion = result.installedVersion {
            status.version = installedVersion
        }
    }

    private func restoreAfterCancellation(_ tool: DevelopmentTool) {
        var cancelled = statuses[tool.id] ?? DevelopmentToolStatus()
        cancelled.state = cancelled.isInstalled ? .installed : .idle
        cancelled.operation = nil
        cancelled.phase = nil
        cancelled.detail = L10n.text("installer.error.cancelled")
        statuses[tool.id] = cancelled
    }

    private func keepSelectionVisible() {
        if let selectedTool, filteredTools.contains(selectedTool) { return }
        selectedTool = filteredTools.first
    }

#if DEBUG
    private func applyPreviewState() {
        guard let tool = DevelopmentTool.catalog.first(where: { $0.id == "git-lfs" }) else { return }
        hasLoaded = true
        category = .updates
        selectedTool = tool
        statuses[tool.id] = DevelopmentToolStatus(
            isInstalled: true,
            version: "3.6.1",
            state: .installed,
            updateAvailability: .available,
            latestVersion: "3.7.1",
            updatePackageName: "git-lfs"
        )
    }
#endif
}
