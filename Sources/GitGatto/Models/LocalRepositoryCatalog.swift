import Foundation

struct LocalRepositoryRecord: Identifiable, Sendable, Equatable {
    let url: URL
    let lastActivityAt: Date
    let lastModifiedAt: Date

    var id: String { url.standardizedFileURL.path }
    var sortDate: Date { max(lastActivityAt, lastModifiedAt) }
}

enum RepositoryCatalogSectionKind: String, CaseIterable, Identifiable, Sendable {
    case active
    case recent
    case earlier

    var id: String { rawValue }
    var titleKey: String { "repository.section.\(rawValue)" }
}

struct RepositoryCatalogSection: Identifiable, Sendable, Equatable {
    let kind: RepositoryCatalogSectionKind
    let repositories: [LocalRepositoryRecord]

    var id: String { kind.id }
}

enum LocalRepositoryCatalog {
    private static let activeWindow: TimeInterval = 30 * 24 * 60 * 60
    private static let recentWindow: TimeInterval = 180 * 24 * 60 * 60

    static func sections(
        records: [LocalRepositoryRecord],
        recentRepositoryPaths: [String],
        currentRepositoryPath: String?,
        now: Date = Date()
    ) -> [RepositoryCatalogSection] {
        var recentRanks: [String: Int] = [:]
        for (index, path) in recentRepositoryPaths.enumerated() where recentRanks[path] == nil {
            recentRanks[path] = index
        }
        let currentPath = currentRepositoryPath.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }
        let activeCutoff = now.addingTimeInterval(-activeWindow)
        let recentCutoff = now.addingTimeInterval(-recentWindow)

        let grouped = Dictionary(grouping: records) { record in
            let path = record.id
            if path == currentPath || recentRanks[path] != nil || record.sortDate >= activeCutoff {
                return RepositoryCatalogSectionKind.active
            }
            if record.sortDate >= recentCutoff {
                return RepositoryCatalogSectionKind.recent
            }
            return RepositoryCatalogSectionKind.earlier
        }

        return RepositoryCatalogSectionKind.allCases.compactMap { kind in
            guard let repositories = grouped[kind], !repositories.isEmpty else { return nil }
            let sorted = repositories.sorted { lhs, rhs in
                compare(
                    lhs,
                    rhs,
                    currentPath: currentPath,
                    recentRanks: recentRanks
                )
            }
            return RepositoryCatalogSection(kind: kind, repositories: sorted)
        }
    }

    private static func compare(
        _ lhs: LocalRepositoryRecord,
        _ rhs: LocalRepositoryRecord,
        currentPath: String?,
        recentRanks: [String: Int]
    ) -> Bool {
        if lhs.id == currentPath, rhs.id != currentPath { return true }
        if rhs.id == currentPath, lhs.id != currentPath { return false }

        switch (recentRanks[lhs.id], recentRanks[rhs.id]) {
        case let (lhsRank?, rhsRank?) where lhsRank != rhsRank:
            return lhsRank < rhsRank
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        if lhs.lastActivityAt != rhs.lastActivityAt {
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
        if lhs.lastModifiedAt != rhs.lastModifiedAt {
            return lhs.lastModifiedAt > rhs.lastModifiedAt
        }
        let nameOrder = lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
    }
}

enum RepositoryScanCatalog {
    static func merging(
        current: [LocalRepositoryRecord],
        incoming: [LocalRepositoryRecord],
        managedPaths: Set<String>
    ) -> [LocalRepositoryRecord] {
        var recordsByPath = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for record in incoming where !managedPaths.contains(record.id) {
            recordsByPath[record.id] = record
        }
        for path in managedPaths {
            recordsByPath[path] = nil
        }
        return recordsByPath.values.sorted(by: compare)
    }

    static func selected(
        from records: [LocalRepositoryRecord],
        paths: Set<String>
    ) -> [LocalRepositoryRecord] {
        records.filter { paths.contains($0.id) }.sorted(by: compare)
    }

    private static func compare(_ lhs: LocalRepositoryRecord, _ rhs: LocalRepositoryRecord) -> Bool {
        if lhs.sortDate != rhs.sortDate { return lhs.sortDate > rhs.sortDate }
        let nameOrder = lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
    }
}
