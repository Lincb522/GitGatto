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

    static func primaryImageURL(in document: GitHubReadmeDocument) -> URL? {
        let html = normalized(
            document.html,
            linkBaseURL: document.linkBaseURL,
            linkRootURL: document.linkRootURL,
            assetBaseURL: document.assetBaseURL,
            assetRootURL: document.assetRootURL
        )
        guard let expression = try? NSRegularExpression(
            pattern: #"(?is)<img\b[^>]*\bsrc\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#
        ) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in expression.matches(in: html, range: range).prefix(24) {
            guard let sourceRange = Range(match.range(at: 1), in: html) else { continue }
            let source = String(html[sourceRange])
            let lowercased = source.lowercased()
            guard !lowercased.hasPrefix("data:"),
                  !lowercased.contains("img.shields.io"),
                  !lowercased.contains("badge"),
                  !lowercased.contains("coverage"),
                  !lowercased.contains("status.svg"),
                  let url = URL(string: source),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
            return url
        }
        return nil
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

    static func embeddingLocalAssets(
        in html: String,
        readmePath: String,
        repositoryRootURL: URL
    ) throws -> String {
        let references = Array(relativeAssetReferences(in: html).prefix(24))
        guard !references.isEmpty else { return html }

        let standardizedRoot = repositoryRootURL.standardizedFileURL.resolvingSymlinksInPath()
        var replacements: [String: String] = [:]
        var totalSize = 0
        for reference in references {
            guard let path = repositoryPath(for: reference, readmePath: readmePath),
                  let mimeType = imageMIMEType(for: path) else { continue }
            let assetURL = standardizedRoot
                .appendingPathComponent(path)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard assetURL.path.hasPrefix(standardizedRoot.path + "/"),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: assetURL.path),
                  let fileSize = attributes[.size] as? NSNumber,
                  fileSize.intValue <= 4_000_000,
                  totalSize + fileSize.intValue <= 16_000_000 else { continue }
            let data = try Data(contentsOf: assetURL, options: [.mappedIfSafe])
            guard data.count <= 4_000_000,
                  totalSize + data.count <= 16_000_000 else { continue }
            totalSize += data.count
            replacements[reference] = "data:\(mimeType);base64,\(data.base64EncodedString())"
        }
        return replacingAssetReferences(in: html, replacements: replacements)
    }

    static func imageMIMEType(for path: String) -> String? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "svg": "image/svg+xml"
        case "webp": "image/webp"
        case "bmp": "image/bmp"
        case "ico": "image/x-icon"
        case "avif": "image/avif"
        default: nil
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
