import Foundation

enum GitHubSearchQueryResolver {
    static func requiresAgent(_ input: String) -> Bool {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        if query.range(
            of: #"^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)?$"#,
            options: .regularExpression
        ) != nil {
            return false
        }
        return query.contains(where: { $0.isWhitespace })
            || query.unicodeScalars.contains(where: { $0.value > 127 })
            || query.contains("?")
            || query.contains("，")
            || query.contains("。")
    }

    static func directQuery(_ input: String, scope: GitHubSearchScope) -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains("/") || scope == .developers { return value }
        return "\(value) in:name"
    }
}
