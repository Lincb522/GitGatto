import Foundation

actor BackgroundMonitoringService {
    private struct ActivityArchive: Codable {
        var eventsByRepository: [String: [String: Int]] = [:]
    }

    private let rootURL: URL
    private let archiveURL: URL
    private let runner: GitCommandRunner
    private let fileManager: FileManager
    private var lastRecordedAtByRepository: [String: Date] = [:]
    private var cachedArchive: ActivityArchive?

    init(
        rootURL: URL = BackgroundMonitoringService.defaultRootURL(),
        runner: GitCommandRunner = GitCommandRunner(),
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        archiveURL = rootURL.appendingPathComponent("activity.json", isDirectory: false)
        self.runner = runner
        self.fileManager = fileManager
    }

    static func defaultRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("GitGatto", isDirectory: true)
            .appendingPathComponent("Monitoring", isDirectory: true)
    }

    @discardableResult
    func recordRepositoryChange(
        at repositoryURL: URL,
        date: Date = Date(),
        minimumInterval: TimeInterval = 15
    ) throws -> Int {
        let path = repositoryURL.standardizedFileURL.path
        let day = Self.dayKey(for: date)
        if let previous = lastRecordedAtByRepository[path],
           date.timeIntervalSince(previous) < minimumInterval
        {
            return try loadArchive().eventsByRepository[path]?[day] ?? 0
        }

        lastRecordedAtByRepository[path] = date
        var archive = try loadArchive()
        var repositoryEvents = archive.eventsByRepository[path] ?? [:]
        repositoryEvents[day, default: 0] += 1
        repositoryEvents = repositoryEvents.filter { key, _ in
            guard let storedDate = Self.date(fromDayKey: key) else { return false }
            return storedDate >= Calendar.current.date(byAdding: .day, value: -400, to: date) ?? .distantPast
        }
        archive.eventsByRepository[path] = repositoryEvents
        try save(archive)
        return repositoryEvents[day] ?? 0
    }

    func dailyActivity(
        for repositoryURL: URL,
        endingAt endDate: Date = Date()
    ) async throws -> [RepositoryDailyActivity] {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: endDate)
        let weekday = calendar.component(.weekday, from: endDay)
        let startOfCurrentWeek = calendar.date(byAdding: .day, value: -(weekday - 1), to: endDay) ?? endDay
        let startDay = calendar.date(byAdding: .day, value: -(52 * 7), to: startOfCurrentWeek) ?? endDay
        let endOfCurrentWeek = calendar.date(byAdding: .day, value: 6, to: startOfCurrentWeek) ?? endDay

        let commitCounts = try await commitCounts(
            for: repositoryURL,
            startingAt: startDay
        )
        let path = repositoryURL.standardizedFileURL.path
        let storedEvents = try loadArchive().eventsByRepository[path] ?? [:]

        var result: [RepositoryDailyActivity] = []
        var cursor = startDay
        while cursor <= endOfCurrentWeek {
            let key = Self.dayKey(for: cursor)
            result.append(RepositoryDailyActivity(
                date: cursor,
                commitCount: commitCounts[key] ?? 0,
                monitoredChangeCount: storedEvents[key] ?? 0
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private func commitCounts(
        for repositoryURL: URL,
        startingAt startDate: Date
    ) async throws -> [String: Int] {
        let formatter = ISO8601DateFormatter()
        let result = try await runner.run(
            at: repositoryURL,
            arguments: [
                "log",
                "--all",
                "--since=\(formatter.string(from: startDate))",
                "--date=format:%Y-%m-%d",
                "--pretty=format:%ad",
            ],
            acceptedExitCodes: [0, 128]
        )
        guard result.exitCode == 0 else { return [:] }
        return result.text
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .reduce(into: [:]) { counts, day in
                counts[day, default: 0] += 1
            }
    }

    private func loadArchive() throws -> ActivityArchive {
        if let cachedArchive { return cachedArchive }
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            let archive = ActivityArchive()
            cachedArchive = archive
            return archive
        }
        let data = try Data(contentsOf: archiveURL)
        let archive = try JSONDecoder().decode(ActivityArchive.self, from: data)
        cachedArchive = archive
        return archive
    }

    private func save(_ archive: ActivityArchive) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(archive)
        try data.write(to: archiveURL, options: .atomic)
        cachedArchive = archive
    }

    private static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func date(fromDayKey key: String) -> Date? {
        let fields = key.split(separator: "-").compactMap { Int($0) }
        guard fields.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(
            year: fields[0],
            month: fields[1],
            day: fields[2]
        ))
    }
}

