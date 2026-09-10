import Foundation

/// One bounded event window and one running operation per key. Events arriving during a read
/// request a follow-up instead of cancelling the read or extending the window indefinitely.
@MainActor
final class RepositoryEventScheduler {
    private struct Job {
        let id: UUID
        let task: Task<Void, Never>
        var operation: @MainActor @Sendable () async -> Void
    }

    private var jobs: [String: Job] = [:]
    private var pending = Set<String>()

    deinit {
        for job in jobs.values { job.task.cancel() }
    }

    func schedule(
        key: String,
        delay: Duration,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        pending.insert(key)
        if jobs[key] != nil {
            jobs[key]?.operation = operation
            return
        }
        let id = UUID()
        let task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: delay) }
                catch { return }
                guard let self, self.jobs[key]?.id == id else { return }
                self.pending.remove(key)
                await self.jobs[key]?.operation()
                guard !Task.isCancelled, self.jobs[key]?.id == id else { return }
                if !self.pending.contains(key) {
                    self.jobs[key] = nil
                    return
                }
            }
        }
        jobs[key] = Job(id: id, task: task, operation: operation)
    }

    func cancelAll() {
        for job in jobs.values { job.task.cancel() }
        jobs.removeAll()
        pending.removeAll()
    }
}
