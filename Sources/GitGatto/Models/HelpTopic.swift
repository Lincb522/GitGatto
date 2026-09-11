import Foundation

enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted
    case changes
    case sync
    case history
    case fileHistory
    case branches
    case stash
    case worktrees
    case codeSearch
    case workScenes
    case projectCommands
    case ignoreRules
    case identities
    case intelligence
    case goals
    case regression
    case github
    case collaboration
    case applications
    case developerTools
    case recovery
    case monitoring
    case diagnostics
    case agent
    case translation
    case cliSettings
    case shortcuts
    case troubleshooting

    var workspaceSection: WorkspaceSection? {
        switch self {
        case .changes: .changes
        case .sync: .github
        case .history: .history
        case .fileHistory: .timeMachine
        case .branches: .branches
        case .stash: .stash
        case .worktrees: .worktrees
        case .intelligence: .intelligence
        case .goals: .goals
        case .regression: .regression
        case .gettingStarted, .github, .collaboration: .github
        case .applications, .developerTools: .marketplace
        case .recovery: .recovery
        case .diagnostics, .troubleshooting: .diagnostics
        case .agent: .codex
        default: nil
        }
    }

    var projectTool: ProjectTool? {
        switch self {
        case .codeSearch: .search
        case .workScenes: .scenes
        case .projectCommands: .commands
        case .ignoreRules: .ignore
        case .identities: .identities
        default: nil
        }
    }

    func matches(_ query: String) -> Bool {
        let tokens = query.localizedLowercase.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return true }
        let keys = [titleKey, summaryKey] + sections.flatMap { [$0.titleKey] + $0.bulletKeys }
        let text = keys.map { L10n.text($0) }.joined(separator: " ").localizedLowercase
        return tokens.allSatisfy { text.contains($0) }
    }

    var id: String { rawValue }
    var titleKey: String { "help.topic.\(rawValue).title" }
    var summaryKey: String { "help.topic.\(rawValue).summary" }

    var icon: String {
        switch self {
        case .gettingStarted: "play.circle"
        case .changes: "square.stack.3d.up"
        case .intelligence: "point.3.connected.trianglepath.dotted"
        case .sync: "arrow.up.arrow.down"
        case .goals: "checkmark.seal"
        case .regression: "record.circle"
        case .github: "shippingbox"
        case .agent: "sparkles"
        case .translation: "ai.translation"
        case .cliSettings: "gearshape"
        case .shortcuts: "command"
        case .troubleshooting: "wrench.and.screwdriver"
        case .history: "clock.arrow.circlepath"
        case .fileHistory: "doc.text"
        case .branches: "arrow.triangle.branch"
        case .stash: "archivebox"
        case .worktrees: "rectangle.split.2x1"
        case .recovery: "archivebox"
        case .monitoring: "dot.radiowaves.left.and.right"
        case .applications: "shippingbox"
        case .developerTools: "terminal"
        case .collaboration: "bubble.left.and.bubble.right"
        case .diagnostics: "wrench.and.screwdriver"
        case .codeSearch: "magnifyingglass"
        case .workScenes: "square.stack.3d.up"
        case .projectCommands: "terminal"
        case .ignoreRules: "eye.slash"
        case .identities: "person.crop.circle"
        }
    }

    var sections: [HelpArticleSection] {
        switch self {
        case .gettingStarted:
            [
                .init("help.gettingStarted.open.title", bullets: [
                    "help.gettingStarted.open.1",
                    "help.gettingStarted.open.2",
                    "help.gettingStarted.open.3"
                ]),
                .init("help.gettingStarted.navigation.title", bullets: [
                    "help.gettingStarted.navigation.1",
                    "help.gettingStarted.navigation.2",
                    "help.gettingStarted.navigation.3",
                    "help.gettingStarted.tools"
                ])
            ]
        case .changes:
            [
                .init("help.changes.stage.title", bullets: [
                    "help.changes.stage.1",
                    "help.changes.stage.2",
                    "help.changes.stage.3"
                ]),
                .init("help.changes.files.title", bullets: [
                    "help.changes.files.1",
                    "help.changes.files.2",
                    "help.changes.files.3"
                ])
            ]
        case .intelligence:
            [
                .init("help.intelligence.intent.title", bullets: [
                    "help.intelligence.intent.1",
                    "help.intelligence.intent.2",
                    "help.intelligence.intent.3"
                ]),
                .init("help.intelligence.provenance.title", bullets: [
                    "help.intelligence.provenance.1",
                    "help.intelligence.provenance.2",
                    "help.intelligence.provenance.3"
                ]),
                .init("help.intelligence.capsule.title", bullets: [
                    "help.intelligence.capsule.1",
                    "help.intelligence.capsule.2",
                    "help.intelligence.capsule.3"
                ]),
                .init("help.intelligence.activity.title", bullets: [
                    "help.intelligence.activity.1",
                    "help.intelligence.activity.2",
                    "help.intelligence.activity.3"
                ])
            ]
        case .sync:
            [
                .init("help.sync.commit.title", bullets: [
                    "help.sync.commit.1",
                    "help.sync.commit.2",
                    "help.sync.commit.3"
                ]),
                .init("help.sync.remote.title", bullets: [
                    "help.sync.remote.1",
                    "help.sync.remote.2",
                    "help.sync.remote.3"
                ])
            ]
        case .goals:
            [
                .init("help.goals.create.title", bullets: [
                    "help.goals.create.1",
                    "help.goals.create.2",
                    "help.goals.create.3",
                    "help.goals.create.4"
                ]),
                .init("help.goals.execute.title", bullets: [
                    "help.goals.execute.1",
                    "help.goals.execute.2",
                    "help.goals.execute.3",
                    "help.goals.execute.4"
                ]),
                .init("help.goals.release.title", bullets: [
                    "help.goals.release.1",
                    "help.goals.release.2",
                    "help.goals.release.3"
                ])
            ]
        case .regression:
            [
                .init("help.regression.start.title", bullets: [
                    "help.regression.start.1",
                    "help.regression.start.2",
                    "help.regression.start.3",
                    "help.regression.start.4"
                ]),
                .init("help.regression.verdict.title", bullets: [
                    "help.regression.verdict.1",
                    "help.regression.verdict.2",
                    "help.regression.verdict.3"
                ]),
                .init("help.regression.fix.title", bullets: [
                    "help.regression.fix.1",
                    "help.regression.fix.2",
                    "help.regression.fix.3",
                    "help.regression.fix.4"
                ])
            ]
        case .github:
            [
                .init("help.github.discover.title", bullets: [
                    "help.github.discover.1",
                    "help.github.discover.2",
                    "help.github.discover.3"
                ]),
                .init("help.github.detail.title", bullets: [
                    "help.github.detail.1",
                    "help.github.detail.2",
                    "help.github.detail.3",
                    "help.github.detail.4",
                    "help.github.detail.5"
                ])
            ]
        case .agent:
            [
                .init("ai.settings.title", bullets: [
                    "ai.api.help", "ai.settings.credentials", "ai.settings.arguments.help"
                ]),
                .init("help.agent.scope.title", bullets: [
                    "help.agent.scope.1",
                    "help.agent.scope.2",
                    "help.agent.scope.3"
                ]),
                .init("help.agent.workflow.title", bullets: [
                    "help.agent.workflow.1",
                    "help.agent.workflow.2",
                    "help.agent.workflow.3",
                    "help.agent.workflow.4"
                ])
            ]
        case .translation:
            [
                .init("help.translation.document.title", bullets: [
                    "help.translation.document.1",
                    "help.translation.document.2",
                    "help.translation.document.3"
                ]),
                .init("help.translation.channel.title", bullets: [
                    "help.translation.channel.1",
                    "help.translation.channel.2",
                    "help.translation.channel.3"
                ])
            ]
        case .cliSettings:
            [
                .init("help.cliSettings.providers.title", bullets: [
                    "help.cliSettings.providers.1",
                    "help.cliSettings.providers.2",
                    "help.cliSettings.providers.3"
                ]),
                .init("help.cliSettings.arguments.title", bullets: [
                    "help.cliSettings.arguments.1",
                    "help.cliSettings.arguments.2",
                    "help.cliSettings.arguments.3",
                    "help.cliSettings.arguments.4"
                ])
            ]
        case .shortcuts:
            [
                .init("help.shortcuts.workspace.title", bullets: [
                    "help.shortcuts.workspace.1",
                    "help.shortcuts.workspace.2",
                    "help.shortcuts.workspace.3",
                    "help.shortcuts.workspace.4",
                    "help.shortcuts.workspace.5"
                ]),
                .init("help.shortcuts.actions.title", bullets: [
                    "help.shortcuts.actions.1",
                    "help.shortcuts.actions.2",
                    "help.shortcuts.actions.3"
                ])
            ]
        case .history, .fileHistory, .branches, .stash, .worktrees, .recovery, .monitoring, .applications, .developerTools, .collaboration, .diagnostics, .codeSearch, .workScenes, .projectCommands, .ignoreRules, .identities:
            [
                .init("help.task.start", bullets: ["help.\(rawValue).start"]),
                .init("help.task.result", bullets: ["help.\(rawValue).result"]),
                .init("help.task.caution", bullets: ["help.\(rawValue).caution"])
            ]
        case .troubleshooting:
            [
                .init("help.troubleshooting.access.title", bullets: [
                    "help.troubleshooting.access.1",
                    "help.troubleshooting.access.2",
                    "help.troubleshooting.access.3"
                ]),
                .init("help.troubleshooting.operations.title", bullets: [
                    "help.troubleshooting.operations.1",
                    "help.troubleshooting.operations.2",
                    "help.troubleshooting.operations.3",
                    "help.troubleshooting.operations.4",
                    "help.troubleshooting.operations.5"
                ])
            ]
        }
    }

    static func topic(for section: WorkspaceSection) -> HelpTopic {
        switch section {
        case .changes: .changes
        case .intelligence: .intelligence
        case .stash: .stash
        case .history: .history
        case .timeMachine: .fileHistory
        case .recovery: .recovery
        case .branches: .branches
        case .worktrees: .worktrees
        case .diagnostics: .diagnostics
        case .regression: .regression
        case .github: .github
        case .marketplace: .applications
        case .goals: .goals
        case .codex: .agent
        }
    }

    static func topic(for tool: ProjectTool) -> HelpTopic {
        switch tool {
        case .search: .codeSearch
        case .scenes: .workScenes
        case .commands: .projectCommands
        case .ignore: .ignoreRules
        case .identities: .identities
        }
    }
}

struct HelpArticleSection {
    let titleKey: String
    let bulletKeys: [String]

    init(_ titleKey: String, bullets: [String]) {
        self.titleKey = titleKey
        self.bulletKeys = bullets
    }
}
