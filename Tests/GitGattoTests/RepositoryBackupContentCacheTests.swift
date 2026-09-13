import Foundation
import Testing
@testable import GitGatto

@Suite("Backup content comparison cache", .serialized)
struct RepositoryBackupContentCacheTests {
    @Test("Unchanged files reuse equality without retaining file contents")
    func reusesEquality() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let cache = RepositoryBackupContentCache()
        var reads = 0
        for _ in 0..<20 {
            #expect(cache.contentsEqual(fixture.left, fixture.right) { left, right in
                reads += 1
                return FileManager.default.contentsEqual(atPath: left, andPath: right)
            })
        }
        #expect(reads == 1)
    }

    @Test("Same-size in-place edits with restored modification time invalidate equality")
    func detectsRestoredModificationTime() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let cache = RepositoryBackupContentCache()
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: fixture.right.path)
        #expect(cache.contentsEqual(fixture.left, fixture.right))
        let handle = try FileHandle(forWritingTo: fixture.right)
        try handle.write(contentsOf: Data("other".utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: fixture.right.path)
        #expect(!cache.contentsEqual(fixture.left, fixture.right))
        try Data("hello".utf8).write(to: fixture.right)
        #expect(cache.contentsEqual(fixture.left, fixture.right))
    }

    @Test("Atomic replacement, missing files and altered backup payloads are not cached as equal")
    func detectsEitherSideChanges() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let cache = RepositoryBackupContentCache()
        #expect(cache.contentsEqual(fixture.left, fixture.right))
        try Data("other".utf8).write(to: fixture.right, options: .atomic)
        #expect(!cache.contentsEqual(fixture.left, fixture.right))
        try Data("hello".utf8).write(to: fixture.right, options: .atomic)
        #expect(cache.contentsEqual(fixture.left, fixture.right))
        try Data("other".utf8).write(to: fixture.left)
        #expect(!cache.contentsEqual(fixture.left, fixture.right))
        try FileManager.default.removeItem(at: fixture.right)
        #expect(!cache.contentsEqual(fixture.left, fixture.right))
    }

    @Test("Symlinks always use the uncached filesystem comparison")
    func doesNotCacheSymlinks() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let cache = RepositoryBackupContentCache()
        let link = fixture.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.right)
        var reads = 0
        for _ in 0..<3 {
            let expected = FileManager.default.contentsEqual(atPath: fixture.left.path, andPath: link.path)
            let actual = cache.contentsEqual(fixture.left, link) { left, right in
                reads += 1
                return FileManager.default.contentsEqual(atPath: left, andPath: right)
            }
            #expect(actual == expected)
        }
        #expect(reads == 3)
        try Data("other".utf8).write(to: fixture.right)
        #expect(!cache.contentsEqual(fixture.left, link))
    }

    @Test("Files mutated during comparison never populate the cache")
    func rejectsRacingWrite() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let cache = RepositoryBackupContentCache()
        var writeError: Error?
        #expect(cache.contentsEqual(fixture.left, fixture.right) { _, right in
            do { try Data("other".utf8).write(to: URL(fileURLWithPath: right), options: .atomic) }
            catch { writeError = error }
            return true
        })
        #expect(writeError == nil)
        #expect(!cache.contentsEqual(fixture.left, fixture.right))
    }

    @Test("Measures cold and repeated comparison of the same large payload",
          .enabled(if: ProcessInfo.processInfo.environment["GITGATTO_BACKUP_CACHE_MEASUREMENTS"] == "1"))
    func measuresRepeatedComparison() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let content = Data(repeating: 0x41, count: 32 * 1_024 * 1_024)
        try content.write(to: fixture.left)
        try content.write(to: fixture.right)
        let clock = ContinuousClock()
        let cache = RepositoryBackupContentCache()
        var fullReads = 0
        let compare: (String, String) -> Bool = { left, right in
            fullReads += 1
            return FileManager.default.contentsEqual(atPath: left, andPath: right)
        }
        let cold = clock.measure { #expect(cache.contentsEqual(fixture.left, fixture.right, compare: compare)) }
        var uncached: Duration = .zero
        var cached: Duration = .zero
        for _ in 0..<20 {
            // Interleave both paths to reduce drift from system load and the filesystem cache.
            uncached += clock.measure { #expect(compare(fixture.left.path, fixture.right.path)) }
            cached += clock.measure { #expect(cache.contentsEqual(fixture.left, fixture.right, compare: compare)) }
        }
        #expect(fullReads == 21)
        print("BACKUP_COMPARE_MEASURE payload_bytes=\(content.count) repeats=20 cold=\(cold) uncached=\(uncached) cached=\(cached) full_reads=\(fullReads)")
    }

    private struct Fixture {
        let root: URL
        let left: URL
        let right: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("GitGattoContentCache-\(UUID())")
            left = root.appendingPathComponent("backup")
            right = root.appendingPathComponent("working")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("hello".utf8).write(to: left)
            try Data("hello".utf8).write(to: right)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
