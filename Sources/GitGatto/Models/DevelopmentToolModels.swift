import Foundation

enum AgentInstallPhase: String, Sendable, Codable {
    case preparing
    case inspecting
    case installing
    case configuring
    case verifying
}

struct AgentInstallProgress: Sendable, Equatable {
    let phase: AgentInstallPhase
    let detail: String?

    init(_ phase: AgentInstallPhase, detail: String? = nil) {
        self.phase = phase
        self.detail = detail
    }
}

enum DevelopmentToolCategory: String, CaseIterable, Identifiable, Sendable {
    case all
    case installed
    case updates
    case essentials
    case runtimes
    case build
    case containers
    case cloud
    case databases
    case utilities

    var id: String { rawValue }
}

struct DevelopmentTool: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let category: DevelopmentToolCategory
    let icon: String
    let packageHint: String
    let homebrewFormula: String?
    let executableCandidates: [String]
    let versionArguments: [String]

    var summaryKey: String { "developer_tools.tool.\(id).summary" }

    static let catalog: [DevelopmentTool] = [
        DevelopmentTool(
            id: "xcode-command-line-tools",
            name: "Xcode Command Line Tools",
            category: .essentials,
            icon: "hammer",
            packageHint: "Use Apple's xcode-select --install flow. Do not select or switch an existing Xcode installation.",
            homebrewFormula: nil,
            executableCandidates: ["clang"],
            versionArguments: ["--version"]
        ),
        DevelopmentTool(
            id: "homebrew",
            name: "Homebrew",
            category: .essentials,
            icon: "shippingbox",
            packageHint: "Use only the official Homebrew installer or official macOS package.",
            homebrewFormula: nil,
            executableCandidates: ["brew"],
            versionArguments: ["--version"]
        ),
        brew(
            id: "git",
            name: "Git",
            category: .essentials,
            icon: "arrow.triangle.branch",
            formula: "git",
            executable: "git"
        ),
        brew(
            id: "github-cli",
            name: "GitHub CLI",
            category: .essentials,
            icon: "github",
            formula: "gh",
            executable: "gh"
        ),
        brew(
            id: "git-lfs",
            name: "Git LFS",
            category: .essentials,
            icon: "externaldrive.fill",
            formula: "git-lfs",
            executable: "git-lfs",
            versionArguments: ["version"],
            packageHint: "Homebrew formula: git-lfs. Configure only the current user with git lfs install after installation."
        ),
        brew(
            id: "lazygit",
            name: "lazygit",
            category: .essentials,
            icon: "terminal",
            formula: "lazygit",
            executable: "lazygit"
        ),
        brew(
            id: "git-delta",
            name: "delta",
            category: .essentials,
            icon: "code.source",
            formula: "git-delta",
            executable: "delta"
        ),
        brew(
            id: "tig",
            name: "tig",
            category: .essentials,
            icon: "history.file",
            formula: "tig",
            executable: "tig"
        ),

        brew(
            id: "node",
            name: "Node.js LTS",
            category: .runtimes,
            icon: "chevron.left.forwardslash.chevron.right",
            formula: "node",
            executable: "node",
            packageHint: "Prefer an existing user-level version manager; otherwise use the Homebrew node formula."
        ),
        brew(
            id: "python",
            name: "Python 3",
            category: .runtimes,
            icon: "code",
            formula: "python",
            executable: "python3",
            packageHint: "Use the current stable Homebrew python formula. Do not replace /usr/bin/python3."
        ),
        brew(
            id: "go",
            name: "Go",
            category: .runtimes,
            icon: "code",
            formula: "go",
            executable: "go",
            versionArguments: ["version"]
        ),
        DevelopmentTool(
            id: "rust",
            name: "Rust",
            category: .runtimes,
            icon: "gearshape",
            packageHint: "Prefer the official rustup installer in unattended user mode. Keep toolchains under the current user's home directory.",
            homebrewFormula: nil,
            executableCandidates: ["rustc", "cargo"],
            versionArguments: ["--version"]
        ),
        brew(
            id: "openjdk",
            name: "OpenJDK",
            category: .runtimes,
            icon: "curlybraces.square",
            formula: "openjdk",
            executable: "java",
            packageHint: "Use the current stable Homebrew openjdk formula."
        ),
        brew(
            id: "ruby",
            name: "Ruby",
            category: .runtimes,
            icon: "code",
            formula: "ruby",
            executable: "ruby"
        ),
        brew(
            id: "php",
            name: "PHP",
            category: .runtimes,
            icon: "code",
            formula: "php",
            executable: "php"
        ),
        brew(
            id: "deno",
            name: "Deno",
            category: .runtimes,
            icon: "terminal",
            formula: "deno",
            executable: "deno"
        ),
        brew(
            id: "lua",
            name: "Lua",
            category: .runtimes,
            icon: "code",
            formula: "lua",
            executable: "lua",
            versionArguments: ["-v"]
        ),
        brew(
            id: "kotlin",
            name: "Kotlin",
            category: .runtimes,
            icon: "curlybraces.square",
            formula: "kotlin",
            executable: "kotlin",
            versionArguments: ["-version"]
        ),
        brew(
            id: "zig",
            name: "Zig",
            category: .runtimes,
            icon: "code",
            formula: "zig",
            executable: "zig",
            versionArguments: ["version"]
        ),

        brew(
            id: "cmake",
            name: "CMake",
            category: .build,
            icon: "wrench.and.screwdriver",
            formula: "cmake",
            executable: "cmake"
        ),
        brew(
            id: "cocoapods",
            name: "CocoaPods",
            category: .build,
            icon: "square.stack.3d.up",
            formula: "cocoapods",
            executable: "pod",
            packageHint: "Homebrew formula: cocoapods. Do not modify a project or run pod install without a selected project."
        ),
        brew(
            id: "swiftlint",
            name: "SwiftLint",
            category: .build,
            icon: "checkmark.seal",
            formula: "swiftlint",
            executable: "swiftlint",
            versionArguments: ["version"]
        ),
        brew(
            id: "ninja",
            name: "Ninja",
            category: .build,
            icon: "hammer",
            formula: "ninja",
            executable: "ninja"
        ),
        brew(
            id: "meson",
            name: "Meson",
            category: .build,
            icon: "hammer",
            formula: "meson",
            executable: "meson"
        ),
        brew(
            id: "gradle",
            name: "Gradle",
            category: .build,
            icon: "square.stack.3d.up",
            formula: "gradle",
            executable: "gradle"
        ),
        brew(
            id: "maven",
            name: "Maven",
            category: .build,
            icon: "square.stack.3d.up",
            formula: "maven",
            executable: "mvn"
        ),
        brew(
            id: "swiftformat",
            name: "SwiftFormat",
            category: .build,
            icon: "checkmark.seal",
            formula: "swiftformat",
            executable: "swiftformat"
        ),
        brew(
            id: "xcodegen",
            name: "XcodeGen",
            category: .build,
            icon: "doc.badge.gearshape",
            formula: "xcodegen",
            executable: "xcodegen"
        ),
        brew(
            id: "protobuf",
            name: "Protocol Buffers",
            category: .build,
            icon: "doc.on.doc",
            formula: "protobuf",
            executable: "protoc"
        ),

        brew(
            id: "docker",
            name: "Docker CLI",
            category: .containers,
            icon: "shippingbox",
            formula: "docker",
            executable: "docker",
            packageHint: "Homebrew formula: docker. Install the command-line client only; do not start or replace a container engine."
        ),
        brew(
            id: "docker-compose",
            name: "Docker Compose",
            category: .containers,
            icon: "square.stack.3d.up",
            formula: "docker-compose",
            executable: "docker-compose",
            versionArguments: ["version"]
        ),
        brew(
            id: "colima",
            name: "Colima",
            category: .containers,
            icon: "shippingbox",
            formula: "colima",
            executable: "colima",
            versionArguments: ["version"],
            packageHint: "Homebrew formula: colima. Install only; do not start a virtual machine automatically."
        ),
        brew(
            id: "podman",
            name: "Podman",
            category: .containers,
            icon: "shippingbox",
            formula: "podman",
            executable: "podman"
        ),
        brew(
            id: "kubernetes-cli",
            name: "kubectl",
            category: .containers,
            icon: "point.3.connected.trianglepath.dotted",
            formula: "kubernetes-cli",
            executable: "kubectl",
            versionArguments: ["version", "--client"],
            packageHint: "Homebrew formula: kubernetes-cli. Do not change kubeconfig or connect to a cluster."
        ),
        brew(
            id: "helm",
            name: "Helm",
            category: .containers,
            icon: "point.3.connected.trianglepath.dotted",
            formula: "helm",
            executable: "helm",
            versionArguments: ["version", "--short"]
        ),
        brew(
            id: "kind",
            name: "kind",
            category: .containers,
            icon: "point.3.connected.trianglepath.dotted",
            formula: "kind",
            executable: "kind",
            versionArguments: ["version"]
        ),
        brew(
            id: "minikube",
            name: "Minikube",
            category: .containers,
            icon: "point.3.connected.trianglepath.dotted",
            formula: "minikube",
            executable: "minikube",
            versionArguments: ["version", "--short"],
            packageHint: "Homebrew formula: minikube. Install only; do not create or start a cluster automatically."
        ),

        brew(
            id: "awscli",
            name: "AWS CLI",
            category: .cloud,
            icon: "globe",
            formula: "awscli",
            executable: "aws",
            packageHint: "Homebrew formula: awscli. Do not sign in, read credentials, or create a profile."
        ),
        brew(
            id: "azure-cli",
            name: "Azure CLI",
            category: .cloud,
            icon: "globe",
            formula: "azure-cli",
            executable: "az",
            packageHint: "Homebrew formula: azure-cli. Do not sign in, read credentials, or change subscriptions."
        ),
        brew(
            id: "opentofu",
            name: "OpenTofu",
            category: .cloud,
            icon: "building.2",
            formula: "opentofu",
            executable: "tofu",
            versionArguments: ["version"]
        ),
        brew(
            id: "ansible",
            name: "Ansible",
            category: .cloud,
            icon: "building.2",
            formula: "ansible",
            executable: "ansible"
        ),
        brew(
            id: "pulumi",
            name: "Pulumi CLI",
            category: .cloud,
            icon: "building.2",
            formula: "pulumi",
            executable: "pulumi",
            versionArguments: ["version"],
            packageHint: "Homebrew formula: pulumi. Do not sign in, select a stack, or change cloud resources."
        ),

        brew(
            id: "postgresql",
            name: "PostgreSQL",
            category: .databases,
            icon: "internaldrive",
            formula: "postgresql",
            executable: "psql",
            packageHint: "Homebrew formula: postgresql. Install only; do not initialize a database or start a service automatically."
        ),
        brew(
            id: "mysql",
            name: "MySQL",
            category: .databases,
            icon: "internaldrive",
            formula: "mysql",
            executable: "mysql",
            packageHint: "Homebrew formula: mysql. Install only; do not initialize a database or start a service automatically."
        ),
        brew(
            id: "redis",
            name: "Redis",
            category: .databases,
            icon: "internaldrive",
            formula: "redis",
            executable: "redis-server",
            packageHint: "Homebrew formula: redis. Install only; do not start a service automatically."
        ),
        brew(
            id: "sqlite",
            name: "SQLite",
            category: .databases,
            icon: "internaldrive",
            formula: "sqlite",
            executable: "sqlite3"
        ),
        brew(
            id: "mariadb",
            name: "MariaDB",
            category: .databases,
            icon: "internaldrive",
            formula: "mariadb",
            executable: "mariadb",
            packageHint: "Homebrew formula: mariadb. Install only; do not initialize a database or start a service automatically."
        ),
        brew(
            id: "duckdb",
            name: "DuckDB",
            category: .databases,
            icon: "internaldrive",
            formula: "duckdb",
            executable: "duckdb"
        ),
        brew(
            id: "mongosh",
            name: "MongoDB Shell",
            category: .databases,
            icon: "terminal",
            formula: "mongosh",
            executable: "mongosh"
        ),

        brew(
            id: "pnpm",
            name: "pnpm",
            category: .utilities,
            icon: "square.stack.3d.up",
            formula: "pnpm",
            executable: "pnpm",
            packageHint: "Prefer Corepack when available; otherwise use the Homebrew pnpm formula. Do not install global project dependencies."
        ),
        brew(
            id: "ffmpeg",
            name: "FFmpeg",
            category: .utilities,
            icon: "media.fit",
            formula: "ffmpeg",
            executable: "ffmpeg",
            versionArguments: ["-version"]
        ),
        brew(
            id: "ripgrep",
            name: "ripgrep",
            category: .utilities,
            icon: "magnifyingglass",
            formula: "ripgrep",
            executable: "rg"
        ),
        brew(
            id: "jq",
            name: "jq",
            category: .utilities,
            icon: "curlybraces.square",
            formula: "jq",
            executable: "jq"
        ),
        brew(
            id: "yq",
            name: "yq",
            category: .utilities,
            icon: "doc.text",
            formula: "yq",
            executable: "yq"
        ),
        brew(
            id: "fd",
            name: "fd",
            category: .utilities,
            icon: "magnifyingglass",
            formula: "fd",
            executable: "fd"
        ),
        brew(
            id: "fzf",
            name: "fzf",
            category: .utilities,
            icon: "magnifyingglass",
            formula: "fzf",
            executable: "fzf"
        ),
        brew(
            id: "bat",
            name: "bat",
            category: .utilities,
            icon: "doc.text",
            formula: "bat",
            executable: "bat"
        ),
        brew(
            id: "eza",
            name: "eza",
            category: .utilities,
            icon: "folder",
            formula: "eza",
            executable: "eza"
        ),
        brew(
            id: "tree",
            name: "tree",
            category: .utilities,
            icon: "folder",
            formula: "tree",
            executable: "tree"
        ),
        brew(
            id: "tmux",
            name: "tmux",
            category: .utilities,
            icon: "terminal",
            formula: "tmux",
            executable: "tmux",
            versionArguments: ["-V"]
        ),
        brew(
            id: "shellcheck",
            name: "ShellCheck",
            category: .utilities,
            icon: "checkmark.seal",
            formula: "shellcheck",
            executable: "shellcheck"
        ),
        brew(
            id: "shfmt",
            name: "shfmt",
            category: .utilities,
            icon: "text.cursor",
            formula: "shfmt",
            executable: "shfmt"
        ),
        brew(
            id: "httpie",
            name: "HTTPie",
            category: .utilities,
            icon: "globe",
            formula: "httpie",
            executable: "http"
        )
    ]

    private static func brew(
        id: String,
        name: String,
        category: DevelopmentToolCategory,
        icon: String,
        formula: String,
        executable: String,
        versionArguments: [String] = ["--version"],
        packageHint: String? = nil
    ) -> DevelopmentTool {
        DevelopmentTool(
            id: id,
            name: name,
            category: category,
            icon: icon,
            packageHint: packageHint ?? "Homebrew formula: \(formula).",
            homebrewFormula: formula,
            executableCandidates: [executable],
            versionArguments: versionArguments
        )
    }
}

enum DevelopmentToolInstallState: String, Sendable, Equatable {
    case idle
    case installing
    case installed
    case actionRequired
    case failed
}

enum DevelopmentToolOperation: String, Sendable, Equatable {
    case install
    case upgrade
}

enum DevelopmentToolUpdateAvailability: String, Sendable, Equatable {
    case unknown
    case checking
    case current
    case available
    case unavailable
    case failed
}

struct DevelopmentToolUpdateResult: Sendable, Equatable {
    let availability: DevelopmentToolUpdateAvailability
    let installedVersion: String?
    let latestVersion: String?
    let packageName: String?
    let isPinned: Bool
    let detail: String?

    static func unavailable(detail: String? = nil) -> DevelopmentToolUpdateResult {
        DevelopmentToolUpdateResult(
            availability: .unavailable,
            installedVersion: nil,
            latestVersion: nil,
            packageName: nil,
            isPinned: false,
            detail: detail
        )
    }
}

struct DevelopmentToolStatus: Sendable, Equatable {
    var isInstalled = false
    var version: String?
    var state: DevelopmentToolInstallState = .idle
    var operation: DevelopmentToolOperation?
    var phase: AgentInstallPhase?
    var detail: String?
    var result: String?
    var updateAvailability: DevelopmentToolUpdateAvailability = .unknown
    var latestVersion: String?
    var updatePackageName: String?
    var isUpdatePinned = false
    var updateDetail: String?

    var canUpgrade: Bool {
        isInstalled && updateAvailability == .available && !isUpdatePinned
    }
}
