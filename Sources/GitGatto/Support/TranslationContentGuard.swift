import Foundation

/// Reject a translation that changes executable snippets, references, or machine-readable values.
enum TranslationContentGuard {
    static func preservesProtectedContent(source: String, translation: String) -> Bool {
        protectedContent(source) == protectedContent(translation)
    }

    private static func protectedContent(_ text: String) -> [String: Int] {
        let pattern = #"(?ms)^[ \t]*(`{3,}|~{3,})[^\n]*\n.*?^[ \t]*\1[^\S\n]*(?:\n|$)|(`+)[^`\n]*\2|<[/!?]?[A-Za-z][^>]*>|https?://[^\s<>\)\]]+|\]\([^\)\n]*\)|&(?:[a-zA-Z]+|#\d+|#x[\da-fA-F]+);|(?<![A-Za-z0-9_])(?:GitGatto|GitHub|GitLab|Git|Node\.js|Homebrew|README|[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+|[A-Za-z][A-Za-z0-9_-]*(?:/[A-Za-z0-9_.-]*[A-Za-z0-9_-])+|\d+(?:\.\d+)*)(?![A-Za-z0-9_])"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let source = text as NSString
        var values: [String: Int] = [:]
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let value = source.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            values[value, default: 0] += 1
        }
        return values
    }
}
