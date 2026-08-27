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
