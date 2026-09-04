import SwiftUI

struct HelpCenterView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("help.selectedTopic") private var selectedTopicRaw = HelpTopic.gettingStarted.rawValue

    private var selectedTopic: HelpTopic {
        HelpTopic(rawValue: selectedTopicRaw) ?? .gettingStarted
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: AppThemeLayout.panelSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    AppBrandLockup(iconSize: 32, wordmarkWidth: 88, spacing: 7)
                    Text(L10n.text("help.short_title"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .frame(height: 76)

                Rectangle().fill(palette.divider).frame(height: 1)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(HelpTopic.allCases) { topic in
                            HelpTopicButton(
                                topic: topic,
                                isSelected: selectedTopic == topic
                            ) {
                                selectedTopicRaw = topic.rawValue
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
        .task {
            if let topic = ProcessInfo.processInfo.environment["GITGATTO_HELP_TOPIC_PREVIEW"],
               HelpTopic(rawValue: topic) != nil {
                selectedTopicRaw = topic
            }
        }
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
    case intelligence
    case sync
    case goals
    case regression
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

enum WorkspaceQuickGuideKind {
    case goals
    case regression

    var titleKey: String {
        switch self {
        case .goals: "goal.guide.title"
        case .regression: "regression.guide.title"
        }
    }

    var icon: String {
        switch self {
        case .goals: "checkmark.seal"
        case .regression: "record.circle"
        }
    }

    var helpTopicRawValue: String {
        switch self {
        case .goals: HelpTopic.goals.rawValue
        case .regression: HelpTopic.regression.rawValue
        }
    }

    var featureKeys: [String] {
        switch self {
        case .goals:
            (1...4).map { "goal.guide.feature.\($0)" }
        case .regression:
            (1...4).map { "regression.guide.feature.\($0)" }
        }
    }

    var stepKeys: [String] {
        switch self {
        case .goals:
            (1...4).map { "goal.guide.step.\($0)" }
        case .regression:
            (1...4).map { "regression.guide.step.\($0)" }
        }
    }

    var noteKey: String {
        switch self {
        case .goals: "goal.guide.note"
        case .regression: "regression.guide.note"
        }
    }
}

struct WorkspaceQuickGuideSheet: View {
    let guide: WorkspaceQuickGuideKind

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                GattoIcon(symbol: guide.icon, size: 20)
                    .foregroundStyle(palette.accent)
                    .frame(width: 38, height: 38)
                    .background(palette.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(L10n.text(guide.titleKey))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(gattoSymbol: "xmark")
                        .font(.system(size: 11.5, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.mutedInk)
                .help(L10n.text("action.close"))
            }
            .padding(18)

            Rectangle().fill(palette.divider).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    guideSection(
                        titleKey: "workspace.guide.features",
                        icon: "info.circle",
                        keys: guide.featureKeys,
                        numbered: false,
                        palette: palette
                    )
                    guideSection(
                        titleKey: "workspace.guide.steps",
                        icon: "play.circle",
                        keys: guide.stepKeys,
                        numbered: true,
                        palette: palette
                    )
                    HStack(alignment: .top, spacing: 9) {
                        GattoIcon(symbol: "exclamationmark", size: 15)
                            .foregroundStyle(palette.warning)
                        Text(L10n.text(guide.noteKey))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(palette.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(palette.warning.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle().fill(palette.divider).frame(height: 1)
            HStack {
                Spacer()
                Button {
                    UserDefaults.standard.set(guide.helpTopicRawValue, forKey: "help.selectedTopic")
                    openWindow(id: "help")
                    dismiss()
                } label: {
                    GattoLabel(L10n.text("workspace.guide.open_full"), systemImage: "doc.text")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(14)
            .layoutPriority(1)
        }
        .frame(width: 470, height: 540)
        .background(palette.background)
    }

    private func guideSection(
        titleKey: String,
        icon: String,
        keys: [String],
        numbered: Bool,
        palette: AppPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                GattoIcon(symbol: icon, size: 15)
                    .foregroundStyle(palette.accent)
                Text(L10n.text(titleKey))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
            }
            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    HStack(alignment: .top, spacing: 10) {
                        if numbered {
                            Text("\(index + 1)")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(palette.accent)
                                .frame(width: 20, height: 20)
                                .background(palette.accentSoft)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(palette.accent)
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                                .frame(width: 20)
                        }
                        Text(L10n.text(key))
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
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
                Image(gattoSymbol: topic.icon)
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
                Image(gattoSymbol: topic.icon)
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
