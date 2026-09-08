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
                VStack(alignment: .leading, spacing: 6) {
                    AppBrandLockup(iconSize: 32, wordmarkWidth: 88, spacing: 7)
                    Text(L10n.text("help.short_title"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle().fill(palette.divider).frame(height: 1)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(HelpTopic.allCases) { topic in
                                HelpTopicButton(
                                    topic: topic,
                                    isSelected: selectedTopic == topic
                                ) {
                                    selectedTopicRaw = topic.rawValue
                                }
                                .id(topic.id)
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: selectedTopicRaw, initial: true) { _, _ in
                        proxy.scrollTo(selectedTopic.id, anchor: .center)
                    }
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
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(minHeight: 36)
            .background(isSelected ? palette.primarySoft : (isHovering ? palette.raisedSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
    }
}

struct HelpArticleView: View {
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
