import Foundation

struct MarketplaceApplicationDetails: Equatable {
    let summary: String?
    let paragraphs: [String]
    let features: [String]
    let screenshots: [URL]
    let logoURL: URL?

    static func fallback(description: String?) -> MarketplaceApplicationDetails {
        MarketplaceApplicationDetails(
            summary: description,
            paragraphs: [],
            features: [],
            screenshots: [],
            logoURL: nil
        )
    }
}

enum MarketplaceApplicationDetailsExtractor {
    static func extract(
        from document: GitHubReadmeDocument,
        repositoryDescription: String?
    ) -> MarketplaceApplicationDetails {
        let html = GitHubReadmeHTML.normalized(
            document.html,
            linkBaseURL: document.linkBaseURL,
            linkRootURL: document.linkRootURL,
            assetBaseURL: document.assetBaseURL,
            assetRootURL: document.assetRootURL
        )
        let headings = elements(
            pattern: #"(?is)<h[1-6]\b[^>]*>(.*?)</h[1-6]>"#,
            in: html
        ).map { Element(location: $0.location, text: plainText($0.value)) }
        let paragraphs = elements(
            pattern: #"(?is)<p\b[^>]*>(.*?)</p>"#,
            in: html
        )
        .filter { acceptsParagraph($0, headings: headings) }
        .map { plainText($0.value) }
        .filter { $0.count >= 24 }
        .filter { comparisonKey($0) != repositoryDescription.map(comparisonKey) }
        .uniqued()
        .prefix(4)
        let features = elements(
            pattern: #"(?is)<li\b[^>]*>(.*?)</li>"#,
            in: html
        )
        .filter { element in
            isFeatureHeading(heading(at: element.location, in: headings))
        }
        .map { plainText($0.value) }
        .filter { $0.count >= 3 && $0.count <= 240 }
        .uniqued()
        .prefix(8)
        let images = imageCandidates(in: html)
        let logo = images.first(where: \.isLogo)?.url
            ?? GitHubReadmeHTML.primaryImageURL(in: document)
        let screenshots = images
            .filter { !$0.isLogo && $0.url != logo }
            .map(\.url)
            .uniqued()
            .prefix(6)

        return MarketplaceApplicationDetails(
            summary: repositoryDescription,
            paragraphs: Array(paragraphs),
            features: Array(features),
            screenshots: Array(screenshots),
            logoURL: logo
        )
    }

    private struct Element {
        let location: Int
        let text: String
    }

    private struct ImageCandidate {
        let url: URL
        let isLogo: Bool
    }

    private static func elements(pattern: String, in html: String) -> [(location: Int, value: String)] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        return expression.matches(in: html, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: html) else { return nil }
            return (match.range.location, String(html[valueRange]))
        }
    }

    private static func acceptsParagraph(_ element: (location: Int, value: String), headings: [Element]) -> Bool {
        let text = plainText(element.value)
        guard text.count >= 24 else { return false }
        let section = heading(at: element.location, in: headings).lowercased()
        return !excludedSectionTerms.contains(where: section.contains)
    }

    private static func heading(at location: Int, in headings: [Element]) -> String {
        headings.last(where: { $0.location < location })?.text ?? ""
    }

    private static func isFeatureHeading(_ heading: String) -> Bool {
        let value = heading.lowercased()
        return featureSectionTerms.contains(where: value.contains)
    }

    private static func imageCandidates(in html: String) -> [ImageCandidate] {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?is)<img\b([^>]*)>"#
        ) else { return [] }
        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        return expression.matches(in: html, range: range).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: html) else { return nil }
            let attributes = String(html[attributesRange])
            guard let source = attribute("src", in: attributes),
                  let url = URL(string: source),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            let alt = attribute("alt", in: attributes) ?? ""
            let identity = "\(source) \(alt)".lowercased()
            guard !discardedImageTerms.contains(where: identity.contains) else { return nil }
            return ImageCandidate(
                url: url,
                isLogo: logoTerms.contains(where: identity.contains)
            )
        }
    }

    private static func attribute(_ name: String, in attributes: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let expression = try? NSRegularExpression(
            pattern: "(?is)\\b\(escaped)\\s*=\\s*[\\\"']([^\\\"']+)[\\\"']"
        ) else { return nil }
        let range = NSRange(attributes.startIndex ..< attributes.endIndex, in: attributes)
        guard let match = expression.firstMatch(in: attributes, range: range),
              let valueRange = Range(match.range(at: 1), in: attributes) else { return nil }
        return String(attributes[valueRange])
    }

    private static func plainText(_ html: String) -> String {
        var value = html
        value = replacing(#"(?is)<(?:script|style)\b[^>]*>.*?</(?:script|style)>"#, in: value, with: " ")
        value = replacing(#"(?is)<br\s*/?>|</(?:p|div|li)>"#, in: value, with: " ")
        value = replacing(#"(?is)<[^>]+>"#, in: value, with: " ")
        value = decodeEntities(value)
        return value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(_ pattern: String, in value: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex ..< value.endIndex, in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }

    private static func decodeEntities(_ value: String) -> String {
        var output = value
        let named = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
        ]
        for (entity, replacement) in named {
            output = output.replacingOccurrences(of: entity, with: replacement)
        }
        guard let expression = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
            return output
        }
        let range = NSRange(output.startIndex ..< output.endIndex, in: output)
        for match in expression.matches(in: output, range: range).reversed() {
            guard let matchRange = Range(match.range(at: 0), in: output),
                  let valueRange = Range(match.range(at: 1), in: output) else { continue }
            let encoded = String(output[valueRange])
            let radix = encoded.hasPrefix("x") ? 16 : 10
            let digits = encoded.hasPrefix("x") ? String(encoded.dropFirst()) : encoded
            guard let scalarValue = UInt32(digits, radix: radix),
                  let scalar = UnicodeScalar(scalarValue) else { continue }
            output.replaceSubrange(matchRange, with: String(scalar))
        }
        return output
    }

    private static func comparisonKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static let excludedSectionTerms = [
        "install", "getting started", "quick start", "build", "contribut", "license",
        "changelog", "roadmap", "development", "documentation", "usage", "support",
        "安装", "开始使用", "快速开始", "构建", "贡献", "协议", "更新日志", "开发", "文档", "用法",
    ]
    private static let featureSectionTerms = [
        "feature", "highlight", "capabilit", "what it does", "功能", "特性", "亮点", "特色", "能力",
    ]
    private static let discardedImageTerms = [
        "img.shields.io", "badge", "coverage", "workflow", "build status", "sponsor", "analytics",
    ]
    private static let logoTerms = [
        "appicon", "app-icon", "app_icon", "logo", "brand", "icon.png", "icon.svg",
    ]
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var known = Set<Element>()
        return filter { known.insert($0).inserted }
    }
}
