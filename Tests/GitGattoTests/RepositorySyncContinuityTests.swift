import Foundation
import Testing
@testable import GitGatto

@Suite("Batch sync continuity", .serialized)
struct RepositorySyncContinuityTests {
    @MainActor @Test("Retrying one failed operation preserves successes and failures from other operations")
    func retries() async throws {
        let a = URL(fileURLWithPath: "/tmp/sync-A"), b = URL(fileURLWithPath: "/tmp/sync-B")
        let service = SyncContinuityService()
        let model = RepositorySyncViewModel(service: service)
        model.load(repositories: [a, b])
        try await wait { !model.isRefreshing }
        model.selectedRepositoryIDs = [a.path, b.path]; model.run(.fetch)
        try await wait { model.activeBatchOperation == nil && !model.isRefreshing }
        model.selectedRepositoryIDs = [a.path]; model.run(.push)
        try await wait { model.activeBatchOperation == nil && !model.isRefreshing }
        #expect(model.failedOperations == [.fetch, .push])
        await service.allowSuccess()
        model.retryFailures(.fetch)
        try await wait { model.activeBatchOperation == nil && !model.isRefreshing }
        #expect(model.failedOperations == [.push])
        model.retryFailures(.push)
        try await wait { model.activeBatchOperation == nil && !model.isRefreshing }
        #expect(model.lastResults.count == 3)
        #expect(model.lastResults.values.allSatisfy { $0.succeeded })
        #expect(await service.calls["fetch:" + a.path] == 1)
        #expect(await service.calls["fetch:" + b.path] == 2)
        #expect(await service.calls["push:" + a.path] == 2)
    }

    @MainActor @Test("Cancellation keeps the batch locked until workers stop and does not start queued repositories")
    func cancellation() async throws {
        let service = SyncContinuityService(held: true)
        let model = RepositorySyncViewModel(service: service)
        let repositories = (0..<9).map { URL(fileURLWithPath: "/tmp/sync-\($0)") }
        model.load(repositories: repositories)
        try await wait { !model.isRefreshing }
        model.selectEligible(for: .fetch); model.run(.fetch)
        try await wait { await service.calls.count == 3 }
        model.cancel(); model.cancel()
        #expect(model.activeBatchOperation == .fetch)
        #expect(model.isCancelling)
        model.run(.push)
        #expect(await service.calls.count == 3)
        await service.finish()
        try await wait { model.activeBatchOperation == nil }
        #expect(!model.isCancelling)
        #expect(model.lastResults.isEmpty)
        #expect(model.runningRepositories.isEmpty)
        #expect(await service.calls.count == 3)
    }

    @MainActor private func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
        try #require(await condition())
    }
}

private actor SyncContinuityService: RepositorySyncServing {
    let held: Bool
    private var succeeds = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var calls: [String: Int] = [:]
    init(held: Bool = false) { self.held = held }
    func allowSuccess() { succeeds = true }
    func finish() { for continuation in continuations { continuation.resume() }; continuations = [] }
    func status(for repositoryURL: URL) -> RepositorySyncStatus {
        .init(repositoryURL: repositoryURL, branch: "main", upstream: "origin/main", hasRemote: true,
              aheadCount: 1, behindCount: 0, changedFileCount: 0, conflictCount: 0, lastCommitAt: nil, errorMessage: nil)
    }
    func perform(_ operation: RepositoryBatchOperation, in repositoryURL: URL) async -> RepositoryBatchResult {
        calls[operation.rawValue + ":" + repositoryURL.path, default: 0] += 1
        if held { await withCheckedContinuation { continuations.append($0) } }
        let success = succeeds || (operation == .fetch && repositoryURL.lastPathComponent == "sync-A")
        return .init(repositoryURL: repositoryURL, operation: operation, succeeded: success, message: success ? nil : "fixture failure")
    }
}
