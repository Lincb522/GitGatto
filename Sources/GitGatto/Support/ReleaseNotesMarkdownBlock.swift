import Foundation

struct ReleaseNotesMarkdownBlock: Identifiable {
    struct Attachment: Equatable {
        let url: URL
        let alt: String
        let width: CGFloat?
    }

    enum Kind: Equatable { case heading, paragraph, bullet, code, image(Attachment) }
    let id: Int
    let kind: Kind
    let text: String

    static func parse(_ source: String) -> [ReleaseNotesMarkdownBlock] {
        var blocks: [ReleaseNotesMarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var fence: String?

        func append(_ kind: Kind, _ text: String) {
            blocks.append(.init(id: blocks.count, kind: kind, text: text))
        }

        func appendText(_ text: String, kind: Kind = .paragraph) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            var cursor = text.startIndex
            for match in attachments?.matches(in: text, range: range) ?? [] {
                guard let matchedRange = Range(match.range, in: text),
                      let attachment = attachment(String(text[matchedRange])) else { continue }
                let prefix = String(text[cursor..<matchedRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.isEmpty { append(kind, prefix) }
                append(.image(attachment), "")
                cursor = matchedRange.upperBound
            }
            let tail = String(text[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { append(kind, tail) }
        }

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            appendText(paragraph.joined(separator: "\n"))
            paragraph.removeAll(keepingCapacity: true)
        }

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if let activeFence = fence {
                if line.hasPrefix(activeFence) {
                    append(.code, code.joined(separator: "\n"))
                    code.removeAll(keepingCapacity: true)
                    fence = nil
                } else { code.append(String(rawLine)) }
            } else if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flushParagraph()
                fence = String(line.prefix(while: { $0 == line.first }))
            } else if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("#") {
                flushParagraph()
                append(.heading, String(line.drop(while: { $0 == "#" || $0 == " " })))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                appendText(String(line.dropFirst(2)), kind: .bullet)
            } else { paragraph.append(String(rawLine)) }
        }
        flushParagraph()
        if fence != nil { append(.code, code.joined(separator: "\n")) }
        return blocks
    }

    // Match inline code first so an example containing <img> is never requested.
    private static let attachments = try? NSRegularExpression(
        pattern: #"(?is)`+[^`]*`+|<img\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>|!\[([^\]]*)\]\((https?://[^\s)]+)(?:\s+[\"'][^\"']*[\"'])?\)"#
    )

    private static func attachment(_ source: String) -> Attachment? {
        guard !source.hasPrefix("`") else { return nil }
        let src: String?
        let alt: String
        let width: CGFloat?
        if source.lowercased().hasPrefix("<img") {
            src = attribute("src", in: source)
            alt = attribute("alt", in: source) ?? ""
            width = attribute("width", in: source).flatMap(Double.init).flatMap {
                $0.isFinite && $0 > 0 ? CGFloat(min($0, 2048)) : nil
            }
        } else {
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            guard let match = attachments?.firstMatch(in: source, range: range),
                  let srcRange = Range(match.range(at: 2), in: source),
                  let altRange = Range(match.range(at: 1), in: source) else { return nil }
            src = String(source[srcRange])
            alt = String(source[altRange])
            width = nil
        }
        guard let src, let url = URL(string: decodeEntities(src)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return Attachment(url: url, alt: decodeEntities(alt), width: width)
    }

    private static func attribute(_ name: String, in source: String) -> String? {
        let pattern = "(?is)(?<![\\w:-])\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)) else { return nil }
        for index in 1...3 {
            if let range = Range(match.range(at: index), in: source) { return String(source[range]) }
        }
        return nil
    }

    private static func decodeEntities(_ value: String) -> String {
        value.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
