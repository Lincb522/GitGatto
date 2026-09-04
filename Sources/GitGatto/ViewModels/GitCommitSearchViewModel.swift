import Combine
import Foundation

@MainActor
final class GitCommitSearchViewModel: ObservableObject {
    @Published var query = CommitSearchQuery()
    @Published private(set) var results: [CommitRecord] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasSearched = false

    private let service: any GitCommitSearchServing
    private var task: Task<Void, Never>?

    init(service: any GitCommitSearchServing = GitCommitSearchService()) {
        self.service = service
    }

    func search(in repositoryURL: URL?) {
        guard let repositoryURL else { return }
        task?.cancel()
        isSearching = true
        errorMessage = nil
        hasSearched = true
        let query = query
        let service = self.service
        task = Task {
            defer {
                if !Task.isCancelled {
                    isSearching = false
                    task = nil
                }
            }
            do {
                let values = try await service.search(query, in: repositoryURL)
                guard !Task.isCancelled else { return }
                results = values
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                errorMessage = error.localizedDescription
            }
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        query = CommitSearchQuery()
        results = []
        isSearching = false
        errorMessage = nil
        hasSearched = false
    }
}
