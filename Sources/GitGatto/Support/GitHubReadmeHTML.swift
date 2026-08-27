import Foundation

enum GitHubReadmeHTML {
    static func normalized(
        _ html: String,
        linkBaseURL: URL,
        linkRootURL: URL,
        assetBaseURL: URL,
        assetRootURL: URL
    ) -> String {
        rewriteAttributes(in: html) { name, value in
            switch name.lowercased() {
            case "href":
                resolve(value, baseURL: linkBaseURL, rootURL: linkRootURL)
            case "src", "poster":
                resolve(value, baseURL: assetBaseURL, rootURL: assetRootURL)
            default:
                value
            }
        }
    }

    static func relativeAssetReferences(in html: String) -> [String] {
        var references: [String] = []
        _ = rewriteAttributes(in: html) { name, value in
            guard name.caseInsensitiveCompare("src") == .orderedSame
                    || name.caseInsensitiveCompare("poster") == .orderedSame,
                  isRelative(value),
                  isEmbeddableImage(value) else { return value }
            if !references.contains(value) {
                references.append(value)
            }
            return value
        }
        return references
    }

    static func replacingAssetReferences(
        in html: String,
        replacements: [String: String]
    ) -> String {
        rewriteAttributes(in: html) { name, value in
            guard name.caseInsensitiveCompare("src") == .orderedSame
                    || name.caseInsensitiveCompare("poster") == .orderedSame else { return value }
            return replacements[value] ?? value
        }
    }

    static func repositoryPath(for reference: String, readmePath: String) -> String? {
        guard isRelative(reference) else { return nil }
        let pathPart = String(
            reference
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        )
        let unescaped = pathPart.removingPercentEncoding ?? pathPart
        let startsAtRoot = unescaped.hasPrefix("/")
        var components = startsAtRoot
            ? []
            : readmePath.split(separator: "/").dropLast().map(String.init)

        for component in unescaped.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            switch component {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default:
                components.append(component)
            }
        }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: "/")
    }

    private static func rewriteAttributes(
        in html: String,
        transform: (String, String) -> String
    ) -> String {
        var output = html
        for quote in ["\"", "'"] {
            let escapedQuote = NSRegularExpression.escapedPattern(for: quote)
            let pattern = "(?i)\\b(href|src|poster)\\s*=\\s*\(escapedQuote)([^\(escapedQuote)]*)\(escapedQuote)"
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            let matches = expression.matches(in: output, range: range)
            for match in matches.reversed() {
                guard let nameRange = Range(match.range(at: 1), in: output),
                      let valueRange = Range(match.range(at: 2), in: output) else { continue }
                let name = String(output[nameRange])
                let value = String(output[valueRange])
                output.replaceSubrange(valueRange, with: transform(name, value))
            }
        }
        return output
    }

    private static func resolve(_ value: String, baseURL: URL, rootURL: URL) -> String {
        guard isRelative(value) else { return value }
        let isRootRelative = value.hasPrefix("/")
        let relativeValue = isRootRelative ? String(value.drop(while: { $0 == "/" })) : value
        let resolutionBase = isRootRelative ? rootURL : baseURL
        return URL(string: relativeValue, relativeTo: directoryURL(resolutionBase))?
            .absoluteURL.absoluteString ?? value
    }

    private static func isRelative(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.hasPrefix("#"),
              !value.hasPrefix("//") else { return false }
        return URLComponents(string: value)?.scheme == nil
    }

    private static func isEmbeddableImage(_ value: String) -> Bool {
        let path = value
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let extensionName = URL(fileURLWithPath: String(path)).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "ico", "avif"].contains(extensionName)
    }

    private static func directoryURL(_ url: URL) -> URL {
        guard !url.absoluteString.hasSuffix("/") else { return url }
        return URL(string: url.absoluteString + "/") ?? url
    }
}
