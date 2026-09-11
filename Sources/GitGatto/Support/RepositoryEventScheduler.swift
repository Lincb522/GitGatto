import Foundation

/// Bounded event windows, one operation per key, and a shared concurrency limit.
/// Events during a read request one follow-up; urgent events can shorten a waiting window.
@MainActor
final class RepositoryEventScheduler {
    private struct Job {
        let id: UUID
        let order: UInt64
        var operation: @MainActor @Sendable () async -> Void
        var delay: Duration
        var deadline: ContinuousClock.Instant
        var priority: Int
        var wakeTask: Task<Void, Never>?
        var ready = false
        var running = false
        var pending = false
    }
    private let maximumConcurrentOperations: Int
    private var jobs: [String: Job] = [:]
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private var order: UInt64 = 0

    var isIdle: Bool { jobs.isEmpty && runningTasks.isEmpty }

    init(maximumConcurrentOperations: Int = .max) {
        self.maximumConcurrentOperations = max(1, maximumConcurrentOperations)
    }

    deinit {
        for job in jobs.values { job.wakeTask?.cancel() }
        for task in runningTasks.values { task.cancel() }
    }

    func schedule(key: String, delay: Duration, priority: Int = 0,
        operation: @escaping @MainActor @Sendable () async -> Void) {
        let deadline = ContinuousClock.now + max(.zero, delay)
        if var job = jobs[key] {
            job.operation = operation
            job.delay = job.pending ? min(job.delay, delay) : delay
            job.priority = max(job.priority, priority)
            if job.running { job.pending = true }
            else if !job.ready && deadline < job.deadline {
                job.wakeTask?.cancel()
                job.deadline = deadline
                job.wakeTask = wake(key: key, id: job.id, deadline: deadline)
            }
            jobs[key] = job
        } else {
            order &+= 1
            let id = UUID()
            jobs[key] = Job(id: id, order: order, operation: operation, delay: delay,
                deadline: deadline, priority: priority, wakeTask: wake(key: key, id: id, deadline: deadline))
        }
        drain()
    }

    private func wake(key: String, id: UUID, deadline: ContinuousClock.Instant) -> Task<Void, Never> {
        Task { [weak self] in
            do { try await ContinuousClock().sleep(until: deadline) }
            catch { return }
            guard !Task.isCancelled, let self, jobs[key]?.id == id, jobs[key]?.deadline == deadline else { return }
            jobs[key]?.ready = true
            jobs[key]?.wakeTask = nil
            drain()
        }
    }

    private func drain() {
        while runningTasks.count < maximumConcurrentOperations,
              let next = jobs.filter({ $0.value.ready && !$0.value.running }).sorted(by: {
                  $0.value.priority == $1.value.priority ? $0.value.order < $1.value.order : $0.value.priority > $1.value.priority
              }).first {
            let key = next.key, job = next.value
            jobs[key]?.running = true
            jobs[key]?.ready = false
            jobs[key]?.priority = 0
            runningTasks[job.id] = Task { [weak self] in
                await job.operation()
                self?.finished(key: key, id: job.id)
            }
        }
    }

    private func finished(key: String, id: UUID) {
        runningTasks[id] = nil
        if var job = jobs[key], job.id == id {
            if job.pending {
                job.pending = false; job.running = false
                job.deadline = .now + max(.zero, job.delay)
                job.wakeTask = wake(key: key, id: id, deadline: job.deadline)
                jobs[key] = job
            } else { jobs[key] = nil }
        }
        drain()
    }

    func cancelAll() {
        for job in jobs.values { job.wakeTask?.cancel() }
        for task in runningTasks.values { task.cancel() }
        jobs.removeAll()
        // Keep running permits until cancellation cleanup actually finishes.
    }
    func cancelAndWait() async {
        cancelAll()
        let tasks = Array(runningTasks.values)
        for task in tasks { await task.value }
    }

}
