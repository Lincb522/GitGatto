import Foundation

/// Builds an index-only edit from the exact diff displayed to the user.
struct PartialDiffPatch {
    static func supports(_ document: DiffDocument) -> Bool {
        guard let text = document.sourceText, document.fileCount == 1 else { return false }
        return text.contains("\n@@ ") && !text.contains("\nnew file mode ")
            && !text.contains("\ndeleted file mode ") && !text.contains("\nold mode ")
            && !text.contains("\nrename from ") && !text.contains("\ncopy from ")
            && !text.contains("\nBinary files ") && !text.contains("GIT binary patch")
    }

    static func make(from document: DiffDocument, selectedIDs: Set<UUID>, reversing: Bool) throws -> String {
        guard supports(document), !selectedIDs.isEmpty else { throw PartialDiffError.unsupported }
        let lines = document.lines
        guard let firstHunk = lines.firstIndex(where: { $0.kind == .hunk }) else { throw PartialDiffError.unsupported }
        // File names remain Git-quoted. Do not reconstruct paths from display strings.
        let headers = lines[..<firstHunk].map(\.text).filter { !$0.hasPrefix("index ") }
        var output = headers
        var offset = 0
        var hasChanges = false
        var index = firstHunk
        while index < lines.count {
            guard lines[index].kind == .hunk else { throw PartialDiffError.unsupported }
            let header = lines[index].text.split(separator: " ")
            guard header.count >= 3,
                  let start = Int(header[reversing ? 2 : 1].dropFirst().split(separator: ",")[0]) else {
                throw PartialDiffError.unsupported
            }
            index += 1
            var body: [String] = []
            var oldCount = 0
            var newCount = 0
            var selected = false
            var previousWasIncluded = false
            while index < lines.count, lines[index].kind != .hunk {
                let line = lines[index]
                defer { index += 1 }
                if line.text.hasPrefix("\\ No newline") {
                    if previousWasIncluded { body.append(line.text) }
                    continue
                }
                if line.text.first == "+" || line.text.first == "-" {
                    var edits: [(line: DiffLine, kind: Character, marker: String?)] = []
                    var end = index
                    while end < lines.count {
                        let entry = lines[end]
                        if entry.text.hasPrefix("\\ No newline"), !edits.isEmpty {
                            edits[edits.count - 1].marker = entry.text
                        } else if let raw = entry.text.first, raw == "+" || raw == "-" {
                            edits.append((entry, reversing ? (raw == "+" ? "-" : "+") : raw, nil))
                        } else { break }
                        end += 1
                    }
                    let removals = edits.filter { $0.kind == "-" }
                    let additions = edits.filter { $0.kind == "+" }
                    // Align the two sides of a replacement block. Keeping an unselected
                    // deletion as context must not move an earlier selected replacement below it.
                    for position in 0..<max(removals.count, additions.count) {
                        if position < removals.count {
                            let entry = removals[position]
                            let removes = selectedIDs.contains(entry.line.id)
                            body.append((removes ? "-" : " ") + entry.line.text.dropFirst())
                            if let marker = entry.marker { body.append(marker) }
                            oldCount += 1
                            if removes { selected = true } else { newCount += 1 }
                        }
                        if position < additions.count {
                            let entry = additions[position]
                            if selectedIDs.contains(entry.line.id) {
                                body.append("+" + entry.line.text.dropFirst())
                                if let marker = entry.marker { body.append(marker) }
                                newCount += 1; selected = true
                            }
                        }
                    }
                    index = end - 1
                    previousWasIncluded = false
                } else if line.text.first == " " {
                    body.append(line.text); oldCount += 1; newCount += 1; previousWasIncluded = true
                } else { throw PartialDiffError.unsupported }
            }
            if selected {
                output.append("@@ -\(start),\(oldCount) +\(start + offset),\(newCount) @@")
                output.append(contentsOf: body)
                offset += newCount - oldCount
                hasChanges = true
            }
        }
        guard hasChanges else { throw PartialDiffError.unsupported }
        return output.joined(separator: "\n") + "\n"
    }
}

enum PartialDiffError: LocalizedError, Equatable {
    case unsupported, changed
    var errorDescription: String? {
        L10n.text(self == .changed ? "diff.partial.changed" : "diff.partial.unsupported")
    }
}
