import SwiftUI

struct HelpCenterView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTopic: HelpTopic = .gettingStarted

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: AppThemeLayout.panelSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    AppBrandLockup(iconSize: 32, wordmarkWidth: 88, spacing: 7)
                        .padding(
                            .leading,
                            AppThemeLayout.titlebarBrandLeading
                                - AppThemeLayout.workspaceInset
                                - 18
                        )
                    Text(L10n.text("help.short_title"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                }
                .padding(.horizontal, 18)
                .frame(height: 62)

                Rectangle().fill(palette.divider).frame(height: 1)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(HelpTopic.allCases) { topic in
                            HelpTopicButton(
                                topic: topic,
                                isSelected: selectedTopic == topic
                            ) {
                                selectedTopic = topic
                            }
                        }
                    }
                    .padding(10)
                }
            }
            .frame(width: 226)
            .background(palette.sidebar.opacity(0.28))
            .appGlassPanel()

            HelpArticleView(topic: selectedTopic)
                .appGlassPanel()
        }
        .padding(AppThemeLayout.workspaceInset)
        .frame(minWidth: 820, minHeight: 600)
        .background(Color.clear)
#if DEBUG
        .background(
            DebugSnapshotCapture(
                isReady: ProcessInfo.processInfo.environment["GITGATTO_HELP_PREVIEW"] == "1"
            )
        )
#endif
    }
}

private enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted
    case changes
    case sync
    case github
    case agent
    case translation
    case cliSettings
    case shortcuts
    case troubleshooting

    var id: String { rawValue }
    var titleKey: String { "help.topic.\(rawValue).title" }
    var summaryKey: String { "help.topic.\(rawValue).summary" }

    var icon: String {
        switch self {
        case .gettingStarted: "play.circle"
        case .changes: "square.stack.3d.up"
        case .sync: "arrow.up.arrow.down"
        case .github: "shippingbox"
        case .agent: "sparkles"
        case .translation: "character.book.closed"
        case .cliSettings: "gearshape"
        case .shortcuts: "command"
        case .troubleshooting: "wrench.and.screwdriver"
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
                    "help.gettingStarted.navigation.3"
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
                    "help.github.detail.4"
                ])
            ]
        case .agent:
            [
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
}

private struct HelpArticleSection {
    let titleKey: String
    let bulletKeys: [String]

    init(_ titleKey: String, bullets: [String]) {
        self.titleKey = titleKey
        self.bulletKeys = bullets
    }
}

private struct HelpTopicButton: View {
    let topic: HelpTopic
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: topic.icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.primary : palette.mutedInk)
                    .frame(width: 18)
                Text(L10n.text(topic.titleKey))
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? palette.ink : palette.mutedInk)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(isSelected ? palette.primarySoft : (isHovering ? palette.raisedSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct HelpArticleView: View {
    let topic: HelpTopic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: topic.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .frame(width: 40, height: 40)
                    .background(palette.primarySoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(L10n.text(topic.titleKey))
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(palette.ink)
                    .padding(.top, 16)

                Text(L10n.text(topic.summaryKey))
                    .font(.system(size: 13.5))
                    .foregroundStyle(palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                ForEach(Array(topic.sections.enumerated()), id: \.offset) { index, section in
                    if index > 0 {
                        Rectangle().fill(palette.divider).frame(height: 1).padding(.vertical, 24)
                    } else {
                        Spacer().frame(height: 28)
                    }

                    Text(L10n.text(section.titleKey))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.ink)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(section.bulletKeys, id: \.self) { key in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(palette.primary)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 6)
                                Text(L10n.text(key))
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(palette.mutedInk)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.top, 14)
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 42)
            .padding(.vertical, 38)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(topic.id)
        .background(palette.background)
    }
}
