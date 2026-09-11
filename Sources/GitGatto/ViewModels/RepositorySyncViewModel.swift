import Combine
import Foundation

@MainActor
final class RepositorySyncViewModel: ObservableObject {
    @Published private(set) var statuses: [RepositorySyncStatus] = []
    @Published private(set) var runningRepositories: [String: RepositoryBatchOperation] = [:]
    @Published private(set) var lastResults: [String: RepositoryBatchResult] = [:]
    @Published var selectedRepositoryIDs = Set<String>()
    @Published private(set) var isRefreshing = false
    @Published private(set) var isCancelling = false
    @Published private(set) var activeBatchOperation: RepositoryBatchOperation?

    private let service: any RepositorySyncServing
    private var refreshTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var loadedRepositoryIDs = Set<String>()
    private var refreshRequestID: UUID?
    private var batchID: UUID?

    init(service: any RepositorySyncServing = RepositorySyncService()) {
        self.service = service
    }

    var failedResults: [RepositoryBatchResult] {
        lastResults.values.filter { !$0.succeeded }.sorted {
            $0.repositoryURL.lastPathComponent.localizedStandardCompare($1.repositoryURL.lastPathComponent)
                == .orderedAscending
        }
    }

    var failedOperations: [RepositoryBatchOperation] {
        RepositoryBatchOperation.allCases.filter { operation in failedResults.contains { $0.operation == operation } }
    }

    func load(repositories: [URL], force: Bool = false) {
        let normalized = repositories.map(\.standardizedFileURL)
        let ids = Set(normalized.map(\.path))
        guard force || ids != loadedRepositoryIDs else { return }
        refreshTask?.cancel()
        loadedRepositoryIDs = ids
        selectedRepositoryIDs.formIntersection(ids)
        isRefreshing = true
        let requestID = UUID()
        refreshRequestID = requestID
        let service = self.service
        refreshTask = Task {
            defer {
                if refreshRequestID == requestID {
                    isRefreshing = false
                    refreshTask = nil
                    refreshRequestID = nil
                }
            }
            let values = await Self.boundedMap(normalized, limit: 4) { url in
                await service.status(for: url)
            }
            guard !Task.isCancelled else { return }
            statuses = values.sorted(by: Self.compareStatus)
        }
    }

    func toggleSelection(_ status: RepositorySyncStatus) {
        if selectedRepositoryIDs.contains(status.id) {
            selectedRepositoryIDs.remove(status.id)
        } else {
            selectedRepositoryIDs.insert(status.id)
        }
    }

    func selectEligible(for operation: RepositoryBatchOperation) {
        selectedRepositoryIDs = Set(statuses.filter { $0.supports(operation) }.map(\.id))
    }

    func clearSelection() {
        selectedRepositoryIDs.removeAll()
    }

    func run(_ operation: RepositoryBatchOperation) {
        guard activeBatchOperation == nil else { return }
        let selected = statuses.filter {
            selectedRepositoryIDs.contains($0.id) && $0.supports(operation)
        }
        guard !selected.isEmpty else { return }

        operationTask?.cancel()
        activeBatchOperation = operation
        let id = UUID()
        batchID = id
        let selectedIDs = Set(selected.map(\.id))
        lastResults = lastResults.filter { $0.value.operation != operation || !selectedIDs.contains($0.value.repositoryURL.standardizedFileURL.path) }
        let service = self.service
        operationTask = Task {
            defer {
                if batchID == id {
                    batchID = nil
                    activeBatchOperation = nil
                    operationTask = nil
                    isCancelling = false
                    runningRepositories.removeAll()
                }
            }
            let values = await Self.boundedMap(selected, limit: 3) { status in
                await MainActor.run { if self.batchID == id && !self.isCancelling { self.runningRepositories[status.id] = operation } }
                let result = await service.perform(operation, in: status.repositoryURL)
                await MainActor.run {
                    guard self.batchID == id, !self.isCancelling else { return }
                    self.runningRepositories[status.id] = nil
                    self.lastResults[result.id] = result
                }
                return result
            }
            guard !Task.isCancelled, batchID == id else { return }
            load(repositories: statuses.map(\.repositoryURL), force: true)
            if values.allSatisfy(\.succeeded) {
                selectedRepositoryIDs.removeAll()
            }
        }
    }

    func retryFailures(_ operation: RepositoryBatchOperation) {
        guard activeBatchOperation == nil else { return }
        selectedRepositoryIDs = Set(failedResults.filter { $0.operation == operation }.map { $0.repositoryURL.standardizedFileURL.path })
        run(operation)
    }

    func cancel() {
        guard operationTask != nil, !isCancelling else { return }
        isCancelling = true
        operationTask?.cancel()
    }

    private static func compareStatus(_ lhs: RepositorySyncStatus, _ rhs: RepositorySyncStatus) -> Bool {
        let leftPriority = priority(lhs.health)
        let rightPriority = priority(rhs.health)
        if leftPriority != rightPriority { return leftPriority < rightPriority }
        if lhs.lastCommitAt != rhs.lastCommitAt {
            return (lhs.lastCommitAt ?? .distantPast) > (rhs.lastCommitAt ?? .distantPast)
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func priority(_ health: RepositorySyncHealth) -> Int {
        switch health {
        case .conflicted: 0
        case .diverged: 1
        case .behind: 2
        case .ahead: 3
        case .changed: 4
        case .noUpstream: 5
        case .unavailable: 6
        case .clean: 7
        }
    }

    private static func boundedMap<Input: Sendable, Output: Sendable>(
        _ values: [Input],
        limit: Int,
        transform: @escaping @Sendable (Input) async -> Output
    ) async -> [Output] {
        guard !values.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, Output).self) { group in
            var iterator = values.enumerated().makeIterator()
            for _ in 0..<min(max(1, limit), values.count) {
                guard !Task.isCancelled else { break }
                if let (index, value) = iterator.next() {
                    group.addTask { (index, await transform(value)) }
                }
            }
            var results = Array<Output?>(repeating: nil, count: values.count)
            while let (index, output) = await group.next() {
                results[index] = output
                if !Task.isCancelled, let (nextIndex, nextValue) = iterator.next() {
                    group.addTask { (nextIndex, await transform(nextValue)) }
                }
            }
            return results.compactMap { $0 }
        }
    }
}
