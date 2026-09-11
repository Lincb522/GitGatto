import Foundation

struct DevelopmentToolReceipt: Codable, Equatable, Sendable {
    let executableVerified: Bool
    let verificationDetail: String?
    let profilePath: String?
    let environmentState: String
    let environmentError: String?
    let agentConfigurationComplete: Bool
}

struct DevelopmentToolBundle: Identifiable, Equatable {
    let id: String
    let title: String
    let toolIDs: [String]
    var tools: [DevelopmentTool] { toolIDs.compactMap { id in DevelopmentTool.catalog.first { $0.id == id } } }
    static let all: [Self] = [
        .init(id: "web", title: "Web / Node.js", toolIDs: ["git", "node", "pnpm", "bun"]),
        .init(id: "python", title: "Python", toolIDs: ["git", "python", "uv", "just"]),
        .init(id: "swift", title: "Swift / Xcode", toolIDs: ["xcode-command-line-tools", "git", "swiftlint", "swiftformat", "xcodegen"]),
        .init(id: "rust", title: "Rust / C++", toolIDs: ["git", "rust", "cmake", "ninja"]),
        .init(id: "containers", title: "Docker", toolIDs: ["docker", "docker-compose", "kubernetes-cli"]),
        .init(id: "data", title: "SQL / Redis", toolIDs: ["postgresql", "redis", "sqlite"])
    ]
}
