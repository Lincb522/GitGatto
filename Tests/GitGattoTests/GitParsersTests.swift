import Foundation
import Testing
@testable import GitGatto

@Suite("Git output parsers")
struct GitParsersTests {
    @Test("Selects the Simplified Chinese localization case-insensitively")
    func selectsChineseLocalization() {
        let bundle = L10n.bundle(preferredLanguages: ["zh-Hans-CN"])
        #expect(bundle.localizedString(forKey: "nav.changes", value: nil, table: nil) == "工作区变更")
    }

    @Test("Parses staged, unstaged, untracked, and renamed records")
    func parsesStatusRecords() {
        var data = Data()
        for record in ["M  Sources/App.swift", " M README.md", "?? notes.txt", "R  Sources/New.swift", "Sources/Old.swift"] {
            data.append(contentsOf: record.utf8)
            data.append(0)
        }

        let changes = GitParsers.status(from: data)

        #expect(changes.count == 4)
        #expect(changes.first { $0.path == "Sources/App.swift" }?.isStaged == true)
        #expect(changes.first { $0.path == "README.md" }?.workTreeStatus == .modified)
        #expect(changes.first { $0.path == "notes.txt" }?.primaryStatus == .untracked)
        #expect(changes.first { $0.path == "Sources/New.swift" }?.originalPath == "Sources/Old.swift")
    }

    @Test("Parses branch sync metadata with working-tree records")
    func parsesBranchStatus() throws {
        var data = Data()
        for record in ["## feature/fast...origin/feature/fast [ahead 3, behind 2]", "M  Sources/App.swift", "?? notes.txt"] {
            data.append(contentsOf: record.utf8)
            data.append(0)
        }

        let snapshot = try #require(GitParsers.statusSnapshot(from: data))

        #expect(snapshot.branchName == "feature/fast")
        #expect(snapshot.upstreamName == "origin/feature/fast")
        #expect(snapshot.aheadCount == 3)
        #expect(snapshot.behindCount == 2)
        #expect(Set(snapshot.changes.map(\.path)) == ["Sources/App.swift", "notes.txt"])
    }

    @Test("Parses an unborn branch without creating a fake change")
    func parsesUnbornBranchStatus() throws {
        let data = Data("## No commits yet on main\0?? README.md\0".utf8)

        let snapshot = try #require(GitParsers.statusSnapshot(from: data))

        #expect(snapshot.branchName == "main")
        #expect(snapshot.upstreamName == nil)
        #expect(snapshot.changes.map(\.path) == ["README.md"])
    }

    @Test("Treats a deleted upstream as unavailable")
    func parsesDeletedUpstreamStatus() throws {
        let data = Data("## main...origin/main [gone]\0".utf8)

        let snapshot = try #require(GitParsers.statusSnapshot(from: data))

        #expect(snapshot.branchName == "main")
        #expect(snapshot.upstreamName == nil)
        #expect(snapshot.aheadCount == 0)
        #expect(snapshot.behindCount == 0)
    }

    @Test("Tracks line numbers across a unified diff")
    func parsesDiffLines() {
        let source = """
        diff --git a/file.txt b/file.txt
        --- a/file.txt
        +++ b/file.txt
        @@ -4,2 +4,3 @@
         same
        -old
        +new
        +more
        """

        let document = GitParsers.diff(from: source, path: "file.txt")
        let deletion = document.lines.first { $0.kind == .deletion }
        let additions = document.lines.filter { $0.kind == .addition }

        #expect(deletion?.oldLineNumber == 5)
        #expect(additions.map(\.newLineNumber) == [5, 6])
        #expect(document.lines.last?.text == "+more")
    }
}
