import Foundation

struct ConflictBlock: Identifiable, Equatable {
    enum Resolution { case current, incoming, both }
    let range: Range<Int>
    let current: String
    let incoming: String
    let base: String?
    var id: Int { range.lowerBound }

    static func parse(_ text: String) -> [Self] {
        let lines = linesPreservingEndings(text)
        var result: [Self] = []
        var start: Int?
        var base: Int?
        var separator: Int?
        var width = 0
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("<<<<<<<") {
                guard start == nil else { return [] }
                width = line.prefix(while: { $0 == "<" }).count
                start = index; base = nil; separator = nil
            } else if let beginning = start {
                if line.hasPrefix(String(repeating: "|", count: width)) {
                    guard base == nil, separator == nil else { return [] }
                    base = index
                } else if line.trimmingCharacters(in: .newlines) == String(repeating: "=", count: width) {
                    guard separator == nil else { return [] }
                    separator = index
                } else if line.hasPrefix(String(repeating: ">", count: width)) {
                    guard let divider = separator else { return [] }
                    result.append(Self(range: beginning..<(index + 1),
                        current: lines[(beginning + 1)..<(base ?? divider)].joined(),
                        incoming: lines[(divider + 1)..<index].joined(),
                        base: base.map { lines[($0 + 1)..<divider].joined() }))
                    start = nil; base = nil; separator = nil
                }
            }
        }
        return start == nil ? result : []
    }

    static func resolving(_ id: Int, using resolution: Resolution, in text: String) -> String? {
        guard let block = parse(text).first(where: { $0.id == id }) else { return nil }
        let replacement: String
        switch resolution {
        case .current: replacement = block.current
        case .incoming: replacement = block.incoming
        case .both: replacement = block.current + block.incoming
        }
        var lines = linesPreservingEndings(text)
        lines.replaceSubrange(block.range, with: [replacement])
        return lines.joined()
    }

    private static func linesPreservingEndings(_ text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        return lines.enumerated().map { $0.offset < lines.count - 1 ? $0.element + "\n" : $0.element }
    }
}
