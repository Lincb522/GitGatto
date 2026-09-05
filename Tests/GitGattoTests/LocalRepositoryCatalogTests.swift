import Foundation
import Testing
@testable import GitGatto

@Suite("Local repository catalog")
struct LocalRepositoryCatalogTests {
    @Test("Partitions by activity and sorts by use then modification time")
    func partitionsAndSortsRepositories() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let current = record("current", activityDaysAgo: 400, modifiedDaysAgo: 400, now: now)
        let opened = record("opened", activityDaysAgo: 300, modifiedDaysAgo: 300, now: now)
        let active = record("active", activityDaysAgo: 2, modifiedDaysAgo: 1, now: now)
        let recent = record("recent", activityDaysAgo: 80, modifiedDaysAgo: 60, now: now)
        let earlier = record("earlier", activityDaysAgo: 400, modifiedDaysAgo: 350, now: now)

        let sections = LocalRepositoryCatalog.sections(
            records: [earlier, active, recent, opened, current],
            recentRepositoryPaths: [opened.id],
            currentRepositoryPath: current.id,
            now: now
        )

        #expect(sections.map(\.kind) == [.active, .recent, .earlier])
        #expect(sections[0].repositories.map(\.id) == [current.id, opened.id, active.id])
        #expect(sections[1].repositories.map(\.id) == [recent.id])
        #expect(sections[2].repositories.map(\.id) == [earlier.id])
    }

    @Test("Keeps scan results separate until the selected projects are approved")
    func filtersAndSelectsScanResults() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let managed = record("managed", activityDaysAgo: 1, modifiedDaysAgo: 1, now: now)
        let older = record("older", activityDaysAgo: 8, modifiedDaysAgo: 8, now: now)
        let newer = record("newer", activityDaysAgo: 2, modifiedDaysAgo: 2, now: now)

        let candidates = RepositoryScanCatalog.merging(
            current: [older],
            incoming: [managed, newer, older],
            managedPaths: [managed.id]
        )

        #expect(candidates.map(\.id) == [newer.id, older.id])
        #expect(RepositoryScanCatalog.selected(from: candidates, paths: [older.id]).map(\.id) == [older.id])
    }

    @Test("Builds a compact searchable sidebar catalog without duplicating the current repository")
    func buildsSidebarCatalog() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let current = record("GitGatto", activityDaysAgo: 1, modifiedDaysAgo: 1, now: now)
        let related = LocalRepositoryRecord(
            url: URL(fileURLWithPath: "/tmp/clients/RepositoryKit", isDirectory: true),
            lastActivityAt: now.addingTimeInterval(-2 * 86_400),
            lastModifiedAt: now.addingTimeInterval(-2 * 86_400)
        )
        let unrelated = record("Website", activityDaysAgo: 90, modifiedDaysAgo: 90, now: now)
        let sections = [
            RepositoryCatalogSection(kind: .active, repositories: [current, related]),
            RepositoryCatalogSection(kind: .recent, repositories: [unrelated]),
        ]

        let fullCatalog = LocalRepositoryCatalog.sidebarCatalog(
            sections: sections,
            currentRepositoryPath: current.id,
            query: ""
        )
        #expect(fullCatalog.currentRepository?.id == current.id)
        #expect(fullCatalog.sections.flatMap(\.repositories).map(\.id) == [related.id, unrelated.id])

        let filteredCatalog = LocalRepositoryCatalog.sidebarCatalog(
            sections: sections,
            currentRepositoryPath: current.id,
            query: "clients"
        )
        #expect(filteredCatalog.currentRepository == nil)
        #expect(filteredCatalog.sections.map(\.kind) == [.active])
        #expect(filteredCatalog.sections[0].repositories.map(\.id) == [related.id])
    }

    private func record(
        _ name: String,
        activityDaysAgo: Double,
        modifiedDaysAgo: Double,
        now: Date
    ) -> LocalRepositoryRecord {
        LocalRepositoryRecord(
            url: URL(fileURLWithPath: "/tmp/\(name)", isDirectory: true),
            lastActivityAt: now.addingTimeInterval(-activityDaysAgo * 86_400),
            lastModifiedAt: now.addingTimeInterval(-modifiedDaysAgo * 86_400)
        )
    }
}
