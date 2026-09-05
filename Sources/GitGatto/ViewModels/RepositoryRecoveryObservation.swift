import Combine
import Foundation

@MainActor
final class RepositoryRecoveryObservation: ObservableObject {
    let model: WorkspaceViewModel
    private var subscriptions = Set<AnyCancellable>()
    private(set) var slots: [UUID: Int] = [:]

    init(model: WorkspaceViewModel) {
        self.model = model
        model.$repositoryBackups.removeDuplicates().sink { [weak self] backups in
            guard let self else { return }
            var positions: [UUID: Int] = [:]
            for group in Dictionary(grouping: backups, by: \.repositoryPath).values {
                for (index, backup) in group.sorted(by: { $0.createdAt > $1.createdAt }).enumerated() {
                    positions[backup.id] = index
                }
            }
            objectWillChange.send()
            slots = positions
        }.store(in: &subscriptions)

        let changes: [AnyPublisher<Void, Never>] = [
            model.$selectedRepositoryBackupID.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$repositoryBackupStorageBytes.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$repositoryBackupDirectoryURL.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$isLoadingRepositoryBackups.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$isMigratingRepositoryBackupStorage.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$activeRepositoryBackupPath.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$repositoryProtectionError.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$repositoryProtectionIncidents.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$snapshot.map { $0?.rootURL }.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$localRepositories.map(\.count).removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$appPreferences.map(\.repositoryBackupEnabled).removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$appPreferences.map(\.language).removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes).sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
    }
}
