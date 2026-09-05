import Foundation
import Testing
@testable import GitGatto

@Suite("Code surface data")
struct CodeSurfaceTests {
    @Test("Preserves empty lines, trailing newlines and Unicode source", arguments: [
        "", "\n", "one\n\nthree\n", "let 猫 = \"🐱\"\n// café", "one\r\ntwo\r\n"
    ])
    func preservesSourceLines(content: String) {
        let cache = CodeLineCache()
        let expected = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(cache.lines(for: content) == expected)
        #expect(cache.lines(for: content) == expected)
    }

    @Test("Reuses unchanged line storage and refreshes edited content")
    func reusesLineStorage() {
        let cache = CodeLineCache()
        let content = (0..<2_000).map { "let value\($0) = \($0)" }.joined(separator: "\n")
        let first = cache.lines(for: content)
        let second = cache.lines(for: content)
        first.withUnsafeBufferPointer { original in
            second.withUnsafeBufferPointer { reused in
                #expect(original.baseAddress == reused.baseAddress)
            }
        }
        let edited = cache.lines(for: content + "\n// changed")
        #expect(edited.count == first.count + 1)
        #expect(edited.last == "// changed")
        #expect(cache.lines(for: content) == first)
    }

    @Test("Diff statistics include only additions, deletions and file headers")
    func diffStatistics() {
        let kinds: [(DiffLineKind, String)] = [
            (.header, "diff --git a/one.swift b/one.swift"),
            (.header, "+++ b/one.swift"), (.header, "--- a/one.swift"),
            (.hunk, "@@ -1,2 +1,3 @@"), (.context, " unchanged"),
            (.addition, "+added"), (.addition, "+another"), (.deletion, "-removed"),
            (.header, "diff --git a/image.png b/image.png"),
            (.header, "Binary files differ")
        ]
        let document = DiffDocument(path: "commit", lines: kinds.map {
            DiffLine(oldLineNumber: nil, newLineNumber: nil, text: $0.1, kind: $0.0)
        })
        #expect(document.fileCount == 2)
        #expect(document.additionCount == 2)
        #expect(document.deletionCount == 1)
        let empty = DiffDocument(path: "empty", lines: [])
        #expect(empty.fileCount == 0 && empty.additionCount == 0 && empty.deletionCount == 0)
    }
}
