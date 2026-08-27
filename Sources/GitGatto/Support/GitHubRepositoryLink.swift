import Foundation

enum GitHubRepositoryLinkDestination: Equatable {
    case markdown(path: String)
    case file(path: String)
    case directory(path: String)
    case web(URL)
}

enum GitHubRepositoryLink {
    static func destination(
        for url: URL,
        repository: GitHubRepository
    ) -> GitHubRepositoryLinkDestination {
        guard url.scheme == "https" || url.scheme == "http",
              url.host?.caseInsensitiveCompare(repository.webURL.host ?? "") == .orderedSame else {
            return .web(url)
        }

        let pathComponents = url.path.split(separator: "/").map(String.init)
        let repositoryComponents = repository.fullName.split(separator: "/").map(String.init)
        guard pathComponents.count >= repositoryComponents.count + 2,
              zip(pathComponents, repositoryComponents).allSatisfy({
                  $0.caseInsensitiveCompare($1) == .orderedSame
              }) else {
            return .web(url)
        }

        let routeIndex = repositoryComponents.count
        let route = pathComponents[routeIndex]
        let branchComponents = repository.defaultBranch.split(separator: "/").map(String.init)
        let branchStart = routeIndex + 1
        let branchEnd = branchStart + branchComponents.count
        guard pathComponents.count >= branchEnd,
              Array(pathComponents[branchStart..<branchEnd]) == branchComponents else {
            return .web(url)
        }

        let path = pathComponents.dropFirst(branchEnd).joined(separator: "/")
        guard !path.isEmpty else { return .web(url) }

        switch route {
        case "tree":
            return .directory(path: path)
        case "blob":
            return isMarkdown(path) ? .markdown(path: path) : .file(path: path)
        default:
            return .web(url)
        }
    }

    private static func isMarkdown(_ path: String) -> Bool {
        ["md", "markdown", "mdown", "mkdn", "mkd", "mdx"]
            .contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }
}
