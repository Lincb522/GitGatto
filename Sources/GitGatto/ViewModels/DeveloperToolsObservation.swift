import Combine
import Foundation

@MainActor
final class DeveloperToolsObservation: ObservableObject {
    enum Scope { case catalog, selectedTool }

    let model: DeveloperToolsViewModel
    private var subscriptions = Set<AnyCancellable>()

    init(model: DeveloperToolsViewModel, scope: Scope) {
        self.model = model
        var changes: [AnyPublisher<Void, Never>] = [
            model.$queuedOperations.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$activeOperations.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
        ]
        switch scope {
        case .catalog:
            changes += [
                model.$statuses.map { $0.mapValues(CatalogStatus.init) }
                    .removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$query.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$category.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$selectedTool.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$selectedUpgradeToolIDs.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$isRefreshing.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
                model.$isCheckingUpdates.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            ]
        case .selectedTool:
            changes.append(
                Publishers.CombineLatest(model.$selectedTool, model.$statuses)
                    .map { tool, statuses in
                        tool.map { SelectedStatus(tool: $0, status: statuses[$0.id] ?? DevelopmentToolStatus()) }
                    }
                    .removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher()
            )
        }
        Publishers.MergeMany(changes).sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
    }

    private struct SelectedStatus: Equatable {
        let tool: DevelopmentTool
        let status: DevelopmentToolStatus
    }

    private struct CatalogStatus: Equatable {
        let state: DevelopmentToolInstallState
        let version: String?
        let latestVersion: String?
        let isInstalled: Bool
        let isUpdatePinned: Bool
        let updateAvailability: DevelopmentToolUpdateAvailability

        init(_ status: DevelopmentToolStatus) {
            state = status.state
            version = status.version
            latestVersion = status.latestVersion
            isInstalled = status.isInstalled
            isUpdatePinned = status.isUpdatePinned
            updateAvailability = status.updateAvailability
        }
    }
}
