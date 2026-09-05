import Combine
import Foundation

@MainActor
final class AppDownloadSummary: ObservableObject {
    struct Snapshot: Equatable {
        let activeCount: Int
        let installedRepositoryNames: [String]

        init(records: [AppDownloadRecord]) {
            activeCount = records.filter { [.queued, .downloading, .installing].contains($0.state) }.count
            var seen = Set<String>()
            installedRepositoryNames = records
                .filter { $0.state == .installed }
                .sorted { $0.updatedAt > $1.updatedAt }
                .map(\.repositoryName)
                .filter { seen.insert($0.lowercased()).inserted }
        }
    }

    @Published private(set) var snapshot = Snapshot(records: [])
    private var subscription: AnyCancellable?

    var activeCount: Int { snapshot.activeCount }
    var installedRepositoryNames: [String] { snapshot.installedRepositoryNames }

    init(downloads: AppDownloadManager) {
        subscription = downloads.$records
            .map { Snapshot(records: $0) }
            .removeDuplicates()
            .sink { [weak self] in self?.snapshot = $0 }
    }
}
