import Foundation

/// Reject a translation that changes executable snippets, references, or machine-readable values.
enum TranslationContentGuard {
    static func preservesProtectedContent(source: String, translation: String) -> Bool {
        protectedContent(source) == protectedContent(translation)
    }

    static func protectedContent(_ text: String) -> [String: Int] {
        let pattern = #"(?ms)^[ \t]*(`{3,}|~{3,})[^\n]*\n.*?^[ \t]*\1[^\S\n]*(?:\n|$)|(`+)[^`\n]*\2|<[/!?]?[A-Za-z][^>]*>|(?<url>https?://[^\s<>\)\]"'，。；：！？、…“”‘’]+)|\]\([^\)\n]*\)|(?<entity>&(?:[a-zA-Z]+|#\d+|#[xX][\da-fA-F]+);)|(?<![A-Za-z0-9_])(?:GitGatto|GitHub|GitLab|Git|Node\.js|Homebrew|README|[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+|[A-Za-z][A-Za-z0-9_-]*(?:/[A-Za-z0-9_.-]*[A-Za-z0-9_-])+|\d+(?:\.\d+)*)(?![A-Za-z0-9_])"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let source = text as NSString
        var values: [String: Int] = [:]
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            var value = source.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            if match.range(withName: "url").location != NSNotFound {
                // Bare URLs can touch prose punctuation; explicit link targets remain byte-for-byte protected.
                while let last = value.last, ".,;:!?".contains(last) {
                    value.removeLast()
                }
            } else if match.range(withName: "entity").location != NSNotFound {
                value = canonicalEntity(value)
            }
            values[value, default: 0] += 1
        }
        return values
    }

    private static func canonicalEntity(_ entity: String) -> String {
        let named: [String: UInt32] = ["&amp;": 38, "&apos;": 39, "&quot;": 34, "&lt;": 60, "&gt;": 62, "&nbsp;": 160]
        let codePoint: UInt32?
        if entity.hasPrefix("&#x") || entity.hasPrefix("&#X") {
            codePoint = UInt32(entity.dropFirst(3).dropLast(), radix: 16)
        } else if entity.hasPrefix("&#") {
            codePoint = UInt32(entity.dropFirst(2).dropLast())
        } else {
            codePoint = named[entity]
        }
        guard let codePoint, UnicodeScalar(codePoint) != nil else { return entity }
        return "&#\(codePoint);"
    }
}
