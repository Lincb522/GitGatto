import Foundation

struct AppReleaseNote: Identifiable, Equatable, Sendable {
    let id: String
    let version: String
    let title: String
    let body: String
    let publishedAt: Date?
    let webURL: URL
    let isPrerelease: Bool
}

enum AppReleaseNotesSource: Equatable, Sendable {
    case bundled
    case github
}

enum GitHubReleaseServiceError: LocalizedError, Sendable {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "GitHub returned an invalid releases response."
        case let .httpStatus(status):
            "GitHub releases request failed with HTTP \(status)."
        }
    }
}

struct GitHubReleaseService: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func releases() async throws -> [AppReleaseNote] {
        var nextURL: URL? = AppLinks.releasesAPI
        var visitedURLs = Set<URL>()
        var releases: [AppReleaseNote] = []

        while let pageURL = nextURL, visitedURLs.insert(pageURL).inserted {
            var request = URLRequest(
                url: pageURL,
                cachePolicy: .reloadRevalidatingCacheData,
                timeoutInterval: 15
            )
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("GitGatto", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubReleaseServiceError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                throw GitHubReleaseServiceError.httpStatus(httpResponse.statusCode)
            }
            releases.append(contentsOf: try Self.decodeReleases(data))
            nextURL = Self.nextPageURL(from: httpResponse.value(forHTTPHeaderField: "Link"))
        }

        return releases.sorted { lhs, rhs in
            (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
        }
    }

    static func decodeReleases(_ data: Data) throws -> [AppReleaseNote] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([GitHubReleasePayload].self, from: data)
            .filter { !$0.draft }
            .map(\.releaseNote)
            .sorted { lhs, rhs in
                (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
            }
    }

    static func nextPageURL(from linkHeader: String?) -> URL? {
        linkHeader?
            .split(separator: ",")
            .lazy
            .compactMap { component -> URL? in
                let parts = component.split(separator: ";", maxSplits: 1)
                guard parts.count == 2,
                      parts[1].trimmingCharacters(in: .whitespaces) == "rel=\"next\"" else {
                    return nil
                }
                let value = parts[0].trimmingCharacters(in: .whitespaces)
                guard value.hasPrefix("<"), value.hasSuffix(">") else { return nil }
                return URL(string: String(value.dropFirst().dropLast()))
            }
            .first
    }
}

private struct GitHubReleasePayload: Decodable {
    let id: Int64
    let tagName: String
    let name: String?
    let body: String?
    let publishedAt: Date?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case body
        case publishedAt = "published_at"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }

    var releaseNote: AppReleaseNote {
        let version = tagName.first == "v" || tagName.first == "V"
            ? String(tagName.dropFirst())
            : tagName
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if let trimmedName, !trimmedName.isEmpty {
            title = trimmedName
        } else {
            title = tagName
        }
        return AppReleaseNote(
            id: "github-\(id)",
            version: version,
            title: title,
            body: body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            publishedAt: publishedAt,
            webURL: htmlURL,
            isPrerelease: prerelease
        )
    }
}
