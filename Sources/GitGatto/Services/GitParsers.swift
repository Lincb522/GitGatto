import Foundation

enum GitParsers {
    static func status(from data: Data) -> [WorkingTreeChange] {
        let records = data.split(separator: 0, omittingEmptySubsequences: true)
        var changes: [WorkingTreeChange] = []
        var index = 0

        while index < records.count {
            let record = String(decoding: records[index], as: UTF8.self)
            guard record.count >= 3 else {
                index += 1
                continue
            }

            let characters = Array(record)
            let indexStatus = GitFileStatus(character: characters[0])
            let workTreeStatus = GitFileStatus(character: characters[1])
            let path = String(record.dropFirst(3))
            var originalPath: String?

            if indexStatus == .renamed || indexStatus == .copied || workTreeStatus == .renamed || workTreeStatus == .copied {
                if index + 1 < records.count {
                    originalPath = String(decoding: records[index + 1], as: UTF8.self)
                    index += 1
                }
            }

            changes.append(
                WorkingTreeChange(
                    path: path,
                    originalPath: originalPath,
                    indexStatus: indexStatus,
                    workTreeStatus: workTreeStatus
                )
            )
            index += 1
        }

        return changes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func commits(from text: String) -> [CommitRecord] {
        let formatter = ISO8601DateFormatter()
        return text
            .split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .compactMap { record in
                let fields = record.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
                guard fields.count == 5, let date = formatter.date(from: fields[3]) else { return nil }
                return CommitRecord(
                    hash: fields[0].trimmingCharacters(in: .whitespacesAndNewlines),
                    shortHash: fields[1],
                    author: fields[2],
                    date: date,
                    subject: fields[4].trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
    }

    static func branches(from data: Data, currentBranch: String) -> [BranchRecord] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: false).map {
            String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .newlines)
        }
        var branches: [BranchRecord] = []
        var index = 0

        while index + 2 < fields.count {
            let name = fields[index]
            guard !name.isEmpty else {
                index += 1
                continue
            }
            let hash = fields[index + 1]
            let upstream = fields[index + 2].isEmpty ? nil : fields[index + 2]
            branches.append(
                BranchRecord(
                    name: name,
                    shortHash: hash,
                    upstream: upstream,
                    isCurrent: name == currentBranch
                )
            )
            index += 3
        }

        return branches.sorted {
            if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func diff(from text: String, path: String) -> DiffDocument {
        var oldLine: Int?
        var newLine: Int?
        var lines: [DiffLine] = []
        var rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n"), rawLines.last?.isEmpty == true {
            rawLines.removeLast()
        }

        for rawLine in rawLines {
            let kind: DiffLineKind
            let lineOld: Int?
            let lineNew: Int?

            if rawLine.hasPrefix("@@") {
                kind = .hunk
                let ranges = parseHunkRanges(rawLine)
                oldLine = ranges.old
                newLine = ranges.new
                lineOld = nil
                lineNew = nil
            } else if rawLine.hasPrefix("diff ") || rawLine.hasPrefix("index ") || rawLine.hasPrefix("---") || rawLine.hasPrefix("+++") || rawLine.hasPrefix("new file") || rawLine.hasPrefix("deleted file") {
                kind = .header
                lineOld = nil
                lineNew = nil
            } else if rawLine.hasPrefix("+") {
                kind = .addition
                lineOld = nil
                lineNew = newLine
                newLine = newLine.map { $0 + 1 }
            } else if rawLine.hasPrefix("-") {
                kind = .deletion
                lineOld = oldLine
                lineNew = nil
                oldLine = oldLine.map { $0 + 1 }
            } else {
                kind = .context
                lineOld = oldLine
                lineNew = newLine
                oldLine = oldLine.map { $0 + 1 }
                newLine = newLine.map { $0 + 1 }
            }

            lines.append(DiffLine(oldLineNumber: lineOld, newLineNumber: lineNew, text: rawLine, kind: kind))
        }

        return DiffDocument(path: path, lines: lines)
    }

    private static func parseHunkRanges(_ line: String) -> (old: Int?, new: Int?) {
        let parts = line.split(separator: " ")
        guard parts.count >= 3 else { return (nil, nil) }

        func start(_ range: Substring) -> Int? {
            let trimmed = range.dropFirst()
            return Int(trimmed.split(separator: ",").first ?? "")
        }

        return (start(parts[1]), start(parts[2]))
    }
}
