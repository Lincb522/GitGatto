import Combine
import Foundation

@MainActor
final class DeveloperToolsViewModel: ObservableObject {
    @Published var query = ""
    @Published var category: DevelopmentToolCategory = .all
    @Published var selectedTool: DevelopmentTool?
    @Published private(set) var statuses: [String: DevelopmentToolStatus] = [:]
    @Published private(set) var queuedOperations: [DevelopmentToolQueueItem] = []
    @Published private(set) var activeOperations: [String: DevelopmentToolQueueItem] = [:]
    @Published private(set) var selectedUpgradeToolIDs: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isCheckingUpdates = false

    private let installerFactory: () -> any CodexServing
    private let probe: any DevelopmentToolProbing
    private let updateChecker: any DevelopmentToolUpdateChecking
    private let environmentConfigurator: any DevelopmentToolEnvironmentConfiguring
    private let systemAuthorizer: any DevelopmentToolSystemAuthorizing
    private let maximumConcurrentOperations: Int
    private var operationTasks: [String: Task<Void, Never>] = [:]
    private var operationInstallers: [String: any CodexServing] = [:]
    private var refreshTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var hasLoaded = false

    init(
        installer: (any CodexServing)? = nil,
        probe: any DevelopmentToolProbing = DevelopmentToolProbe(),
        updateChecker: any DevelopmentToolUpdateChecking = DevelopmentToolUpdateService(),
        environmentConfigurator: any DevelopmentToolEnvironmentConfiguring = DevelopmentToolEnvironmentConfigurator(),
        systemAuthorizer: any DevelopmentToolSystemAuthorizing = DevelopmentToolSystemAuthorizer(),
        maximumConcurrentOperations: Int = 3
    ) {
        if let installer {
            installerFactory = { installer }
        } else {
            installerFactory = { CodexService(lane: .installer) }
        }
        self.probe = probe
        self.updateChecker = updateChecker
        self.environmentConfigurator = environmentConfigurator
        self.systemAuthorizer = systemAuthorizer
        self.maximumConcurrentOperations = max(1, maximumConcurrentOperations)
        selectedTool = DevelopmentTool.catalog.first

#if DEBUG
        if ProcessInfo.processInfo.environment["GITGATTO_DEVELOPER_TOOLS_INSTALL_PREVIEW"] == "1" {
            applyInstallationPreviewState()
        } else if ProcessInfo.processInfo.environment["GITGATTO_DEVELOPER_TOOLS_UPDATES_PREVIEW"] == "1" {
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
        activeOperations.values.sorted { $0.enqueuedAt < $1.enqueuedAt }.first?.toolID
    }

    var activeOperationCount: Int { activeOperations.count }

    var installQueueCount: Int {
        queuedOperations.filter { $0.operation == .install }.count
            + activeOperations.values.filter { $0.operation == .install }.count
    }

    var upgradeQueueCount: Int {
        queuedOperations.filter { $0.operation == .upgrade }.count
            + activeOperations.values.filter { $0.operation == .upgrade }.count
    }

    var selectedUpgradeCount: Int { selectedUpgradeToolIDs.count }

    var isAllVisibleUpgradesSelected: Bool {
        let visible = Set(visibleUpgradeableTools.map(\.id))
        return !visible.isEmpty && visible.isSubset(of: selectedUpgradeToolIDs)
    }

    var updateCount: Int {
        statuses.values.filter { $0.updateAvailability == .available }.count
    }

    func status(for tool: DevelopmentTool) -> DevelopmentToolStatus {
        statuses[tool.id] ?? DevelopmentToolStatus()
    }

    func queuePosition(for tool: DevelopmentTool) -> Int? {
        queuedOperations.firstIndex(where: { $0.toolID == tool.id }).map { $0 + 1 }
    }

    func isQueuedOrRunning(_ tool: DevelopmentTool) -> Bool {
        activeOperations[tool.id] != nil
            || queuedOperations.contains(where: { $0.toolID == tool.id })
    }

    func isUpgradeSelected(_ tool: DevelopmentTool) -> Bool {
        selectedUpgradeToolIDs.contains(tool.id)
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

    func toggleUpgradeSelection(_ tool: DevelopmentTool) {
        guard status(for: tool).canUpgrade else {
            selectedUpgradeToolIDs.remove(tool.id)
            return
        }
        if !selectedUpgradeToolIDs.insert(tool.id).inserted {
            selectedUpgradeToolIDs.remove(tool.id)
        }
    }

    func selectAllVisibleUpgrades() {
        let visible = Set(visibleUpgradeableTools.map(\.id))
        if !visible.isEmpty, visible.isSubset(of: selectedUpgradeToolIDs) {
            selectedUpgradeToolIDs.subtract(visible)
        } else {
            selectedUpgradeToolIDs.formUnion(visible)
        }
    }

    func clearUpgradeSelection() {
        selectedUpgradeToolIDs.removeAll()
    }

    func upgradeSelectedTools() {
        let selected = selectedUpgradeToolIDs
        for tool in DevelopmentTool.catalog where selected.contains(tool.id) {
            upgrade(tool)
        }
        selectedUpgradeToolIDs.subtract(selected)
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
                        guard status.state != .queued, status.state != .installing else { continue }
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
            guard status.state != .queued, status.state != .installing else { continue }
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
                guard let result = results[tool.id], !isQueuedOrRunning(tool) else { continue }
                apply(result, to: tool)
            }
            isCheckingUpdates = false
            updateTask = nil
            reconcileUpgradeSelection()
            keepSelectionVisible()
        }
    }

    func install(_ tool: DevelopmentTool) {
        enqueue(.install, tool: tool)
    }

    func upgrade(_ tool: DevelopmentTool) {
        guard status(for: tool).canUpgrade else { return }
        enqueue(.upgrade, tool: tool)
    }

    func authorizeAndRetry(_ tool: DevelopmentTool) {
        let status = status(for: tool)
        guard let request = status.authorizationRequest else { return }
        enqueue(retryOperation(for: status), tool: tool, authorizationRequest: request)
    }

    func retry(_ tool: DevelopmentTool) {
        let status = status(for: tool)
        enqueue(retryOperation(for: status), tool: tool)
    }

    func cancel(_ tool: DevelopmentTool) {
        if let index = queuedOperations.firstIndex(where: { $0.toolID == tool.id }) {
            queuedOperations.remove(at: index)
            restoreAfterCancellation(tool)
            scheduleQueuedOperations()
            return
        }
        guard let task = operationTasks[tool.id] else { return }
        task.cancel()
        if let installer = operationInstallers[tool.id] {
            Task { await installer.cancel() }
        }
    }

    func cancelInstallation() {
        if let selectedTool, isQueuedOrRunning(selectedTool) {
            cancel(selectedTool)
        } else if let toolID = activeInstallationToolID,
                  let tool = DevelopmentTool.catalog.first(where: { $0.id == toolID }) {
            cancel(tool)
        }
    }

    private var visibleUpgradeableTools: [DevelopmentTool] {
        filteredTools.filter { status(for: $0).canUpgrade }
    }

    private func enqueue(
        _ operation: DevelopmentToolOperation,
        tool: DevelopmentTool,
        authorizationRequest: DevelopmentToolSystemAuthorizationRequest? = nil
    ) {
        guard !isQueuedOrRunning(tool) else { return }
        let startingStatus = statuses[tool.id] ?? DevelopmentToolStatus()
        let packageName = startingStatus.updatePackageName ?? tool.homebrewFormula
        if operation == .upgrade, packageName == nil { return }

        let item = DevelopmentToolQueueItem(
            toolID: tool.id,
            operation: operation,
            authorizationRequest: authorizationRequest
        )
        queuedOperations.append(item)

        var status = startingStatus
        status.state = .queued
        status.operation = operation
        status.phase = nil
        status.operationStartedAt = nil
        status.detail = L10n.text("developer_tools.queue.waiting")
        status.result = nil
        status.authorizationRequest = nil
        statuses[tool.id] = status
        selectedUpgradeToolIDs.remove(tool.id)
        scheduleQueuedOperations()
    }

    private func scheduleQueuedOperations() {
        while operationTasks.count < maximumConcurrentOperations,
              let item = queuedOperations.first {
            queuedOperations.removeFirst()
            guard let tool = DevelopmentTool.catalog.first(where: { $0.id == item.toolID }) else {
                continue
            }

            let startingStatus = statuses[tool.id] ?? DevelopmentToolStatus()
            let packageName = startingStatus.updatePackageName ?? tool.homebrewFormula
            if item.operation == .upgrade, packageName == nil {
                restoreAfterCancellation(tool)
                continue
            }

            var running = startingStatus
            running.state = .installing
            running.operation = item.operation
            running.phase = .preparing
            running.operationStartedAt = Date()
            running.detail = phaseText(item.operation, phase: .preparing)
            running.result = nil
            running.authorizationRequest = nil
            statuses[tool.id] = running

            let installer = installerFactory()
            activeOperations[tool.id] = item
            operationInstallers[tool.id] = installer
            operationTasks[tool.id] = Task { [weak self] in
                guard let self else { return }
                await self.performOperation(
                    item.operation,
                    tool: tool,
                    packageName: packageName,
                    startingStatus: startingStatus,
                    authorizationRequest: item.authorizationRequest,
                    installer: installer
                )
                if Task.isCancelled {
                    self.restoreAfterCancellation(tool)
                }
                self.finishOperation(for: tool)
            }
        }
    }

    private func performOperation(
        _ operation: DevelopmentToolOperation,
        tool: DevelopmentTool,
        packageName: String?,
        startingStatus: DevelopmentToolStatus,
        authorizationRequest: DevelopmentToolSystemAuthorizationRequest?,
        installer: any CodexServing
    ) async {
        let probe = self.probe
        let checker = self.updateChecker
        let environmentConfigurator = self.environmentConfigurator
        let systemAuthorizer = self.systemAuthorizer
        do {
            var hasAuthorizedSystemRepair = false
            if let authorizationRequest {
                let authorized = await requestSystemAuthorization(
                    authorizationRequest,
                    operation: operation,
                    tool: tool,
                    result: nil
                )
                guard authorized else { return }
                hasAuthorizedSystemRepair = true
            }

            var result = try await runAgentOperation(
                operation,
                tool: tool,
                packageName: packageName,
                startingStatus: startingStatus,
                installer: installer
            )

            try Task.checkCancellation()
            var discovery = await probe.probe(tool)
            var firstUpdateResult: DevelopmentToolUpdateResult?
            if operation == .upgrade, discovery.isInstalled {
                firstUpdateResult = await checker.checkUpdates(for: [tool])[tool.id]
            }
            let firstAttemptSucceeded = operation == .install
                ? discovery.isInstalled
                : discovery.isInstalled && firstUpdateResult?.availability != .available

            if !firstAttemptSucceeded,
               !hasAuthorizedSystemRepair,
               let request = await systemAuthorizer.request(for: tool) {
                let authorized = await requestSystemAuthorization(
                    request,
                    operation: operation,
                    tool: tool,
                    result: result.response
                )
                guard authorized else { return }
                result = try await runAgentOperation(
                    operation,
                    tool: tool,
                    packageName: packageName,
                    startingStatus: startingStatus,
                    installer: installer
                )
                try Task.checkCancellation()
                discovery = await probe.probe(tool)
            }

            var environmentConfiguration: DevelopmentToolEnvironmentConfiguration = .unchanged
            var environmentConfigurationError: Error?
            if discovery.isInstalled, let executableURL = discovery.executableURL {
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

            try Task.checkCancellation()
            var verifying = statuses[tool.id] ?? DevelopmentToolStatus()
            verifying.phase = .verifying
            verifying.detail = phaseText(operation, phase: .verifying)
            statuses[tool.id] = verifying
            let verification = await probe.probe(tool)
            let updateResults = verification.isInstalled
                ? await checker.checkUpdates(for: [tool])
                : [:]
            let updateResult = updateResults[tool.id]

            var completed = statuses[tool.id] ?? DevelopmentToolStatus()
            completed.operation = nil
            completed.phase = nil
            completed.operationStartedAt = nil
            completed.isInstalled = verification.isInstalled
            completed.version = updateResult?.installedVersion ?? verification.version
            completed.result = result.response
            completed.authorizationRequest = nil
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
            if Task.isCancelled {
                restoreAfterCancellation(tool)
            } else {
                var failed = statuses[tool.id] ?? DevelopmentToolStatus()
                failed.state = .failed
                failed.operation = nil
                failed.phase = nil
                failed.operationStartedAt = nil
                failed.detail = error.localizedDescription
                statuses[tool.id] = failed
            }
        }
    }

    private func finishOperation(for tool: DevelopmentTool) {
        operationTasks[tool.id] = nil
        operationInstallers[tool.id] = nil
        activeOperations[tool.id] = nil
        reconcileUpgradeSelection()
        scheduleQueuedOperations()
    }

    private func retryOperation(for status: DevelopmentToolStatus) -> DevelopmentToolOperation {
        status.isInstalled && status.updateAvailability == .available ? .upgrade : .install
    }

    private func runAgentOperation(
        _ operation: DevelopmentToolOperation,
        tool: DevelopmentTool,
        packageName: String?,
        startingStatus: DevelopmentToolStatus,
        installer: any CodexServing
    ) async throws -> CodexRunResult {
        switch operation {
        case .install:
            try await installer.installDevelopmentTool(tool) { [weak self] progress in
                await self?.apply(progress, operation: operation, to: tool)
            }
        case .upgrade:
            try await installer.upgradeDevelopmentTool(
                tool,
                packageName: packageName ?? "",
                installedVersion: startingStatus.version,
                latestVersion: startingStatus.latestVersion
            ) { [weak self] progress in
                await self?.apply(progress, operation: operation, to: tool)
            }
        }
    }

    private func requestSystemAuthorization(
        _ request: DevelopmentToolSystemAuthorizationRequest,
        operation: DevelopmentToolOperation,
        tool: DevelopmentTool,
        result: String?
    ) async -> Bool {
        var requesting = statuses[tool.id] ?? DevelopmentToolStatus()
        requesting.state = .installing
        requesting.operation = operation
        requesting.phase = .configuring
        requesting.detail = L10n.text("developer_tools.authorization.requesting")
        requesting.authorizationRequest = request
        if let result {
            requesting.result = result
        }
        statuses[tool.id] = requesting

        do {
            try await systemAuthorizer.authorize(request)
            var repaired = statuses[tool.id] ?? DevelopmentToolStatus()
            repaired.phase = .preparing
            repaired.detail = L10n.text("developer_tools.authorization.repaired")
            repaired.authorizationRequest = nil
            statuses[tool.id] = repaired
            return true
        } catch is CancellationError {
            restoreAfterCancellation(tool)
            return false
        } catch let error as DevelopmentToolSystemAuthorizationError {
            restoreAuthorizationRequest(
                request,
                for: tool,
                result: result,
                cancelled: error == .cancelled
            )
            return false
        } catch {
            restoreAuthorizationRequest(request, for: tool, result: result, cancelled: false)
            return false
        }
    }

    private func restoreAuthorizationRequest(
        _ request: DevelopmentToolSystemAuthorizationRequest,
        for tool: DevelopmentTool,
        result: String?,
        cancelled: Bool
    ) {
        var blocked = statuses[tool.id] ?? DevelopmentToolStatus()
        blocked.state = .actionRequired
        blocked.operation = nil
        blocked.phase = nil
        blocked.operationStartedAt = nil
        blocked.detail = L10n.text(cancelled
            ? "developer_tools.authorization.cancelled"
            : "developer_tools.authorization.failed")
        blocked.authorizationRequest = request
        if let result {
            blocked.result = result
        }
        statuses[tool.id] = blocked
    }

    private func apply(
        _ progress: AgentInstallProgress,
        operation: DevelopmentToolOperation,
        to tool: DevelopmentTool
    ) {
        guard activeOperations[tool.id] != nil else { return }
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
        cancelled.operationStartedAt = nil
        cancelled.detail = L10n.text("installer.error.cancelled")
        statuses[tool.id] = cancelled
    }

    private func reconcileUpgradeSelection() {
        selectedUpgradeToolIDs = selectedUpgradeToolIDs.filter { id in
            guard let tool = DevelopmentTool.catalog.first(where: { $0.id == id }) else { return false }
            return status(for: tool).canUpgrade
        }
    }

    private func keepSelectionVisible() {
        if let selectedTool, filteredTools.contains(selectedTool) { return }
        selectedTool = filteredTools.first
    }

#if DEBUG
    private func applyInstallationPreviewState() {
        guard let tool = DevelopmentTool.catalog.first(where: { $0.id == "git-lfs" }) else { return }
        hasLoaded = true
        category = .all
        selectedTool = tool
        let item = DevelopmentToolQueueItem(toolID: tool.id, operation: .install)
        activeOperations[tool.id] = item
        statuses[tool.id] = DevelopmentToolStatus(
            state: .installing,
            operation: .install,
            phase: .configuring,
            operationStartedAt: Date().addingTimeInterval(-52),
            detail: L10n.text("installer.phase.configuring")
        )
        if let queued = DevelopmentTool.catalog.first(where: { $0.id == "bun" }) {
            queuedOperations = [DevelopmentToolQueueItem(toolID: queued.id, operation: .install)]
            statuses[queued.id] = DevelopmentToolStatus(
                state: .queued,
                operation: .install,
                detail: L10n.text("developer_tools.queue.waiting")
            )
        }
    }

    private func applyPreviewState() {
        let previewIDs = ["git-lfs", "node", "python", "go"]
        let tools = previewIDs.compactMap { id in
            DevelopmentTool.catalog.first(where: { $0.id == id })
        }
        guard let selected = tools.first else { return }
        hasLoaded = true
        category = .updates
        selectedTool = selected
        for (index, tool) in tools.enumerated() {
            statuses[tool.id] = DevelopmentToolStatus(
                isInstalled: true,
                version: "\(index + 1).6.1",
                state: .installed,
                updateAvailability: .available,
                latestVersion: "\(index + 1).7.1",
                updatePackageName: tool.homebrewFormula
            )
        }
        let active = DevelopmentToolQueueItem(toolID: tools[0].id, operation: .upgrade)
        activeOperations[tools[0].id] = active
        statuses[tools[0].id]?.state = .installing
        statuses[tools[0].id]?.operation = .upgrade
        statuses[tools[0].id]?.phase = .installing
        statuses[tools[0].id]?.operationStartedAt = Date().addingTimeInterval(-18)
        statuses[tools[0].id]?.detail = L10n.text("developer_tools.upgrade.phase.installing")
        if tools.count > 1 {
            queuedOperations = [DevelopmentToolQueueItem(toolID: tools[1].id, operation: .upgrade)]
            statuses[tools[1].id]?.state = .queued
            statuses[tools[1].id]?.operation = .upgrade
            statuses[tools[1].id]?.detail = L10n.text("developer_tools.queue.waiting")
        }
        selectedUpgradeToolIDs = Set(tools.dropFirst(2).map(\.id))
    }
#endif
}
