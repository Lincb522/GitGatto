import AppKit
import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var model: WorkspaceViewModel
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue
    @AppStorage(AppStyleDefaults.accentKey) private var accentRaw = AppAccentChoice.coral.rawValue
    @AppStorage(AppStyleDefaults.customAccentKey) private var customAccentHex = "#4F7DFF"
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPage: SettingsPage = .appearance
    @State private var showsSavedState = false

    init(model: WorkspaceViewModel) {
        self.model = model
#if DEBUG
        let previewPage = ProcessInfo.processInfo.environment["GITGATTO_SETTINGS_PAGE"]
            .flatMap(SettingsPage.init(rawValue:)) ?? .appearance
        _selectedPage = State(initialValue: previewPage)
#endif
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: AppThemeLayout.panelSpacing) {
            settingsWindowBar(palette)
                .appGlassPanel()

            settingsNavigation(palette)
                .appGlassPanel(cornerRadius: 14, elevated: false)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    settingsHeader(palette)
                    pageContent
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(palette.surface.opacity(0.18))
            .appGlassPanel()
        }
        .padding(AppThemeLayout.workspaceInset)
        .frame(minWidth: 800, minHeight: 650)
        .background(Color.clear)
#if DEBUG
        .background(
            DebugSnapshotCapture(
                isReady: ProcessInfo.processInfo.environment["GITGATTO_SETTINGS_PREVIEW"] == "1"
            )
        )
#endif
    }

    private func settingsWindowBar(_ palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            AppBrandLockup(iconSize: 38, wordmarkWidth: 102, spacing: 8)
                .padding(.leading, 46)

            Rectangle()
                .fill(palette.divider)
                .frame(width: 1, height: 26)

            Text(L10n.text("settings.title"))
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(palette.ink)

            Spacer()

            if showsSavedState {
                Label(L10n.text("settings.saved"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.success)
                    .transition(.opacity)
            }

            Button(L10n.text("settings.save")) {
                model.saveSettings()
                withAnimation(.easeOut(duration: 0.18)) { showsSavedState = true }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .frame(height: 70)
        .background(palette.sidebar.opacity(0.22))
    }

    private func settingsNavigation(_ palette: AppPalette) -> some View {
        HStack(spacing: 6) {
            ForEach(SettingsPage.allCases) { page in
                Button {
                    selectedPage = page
                    showsSavedState = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: page.icon)
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(L10n.text(page.titleKey))
                            .font(.system(size: 12, weight: selectedPage == page ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selectedPage == page ? palette.ink : palette.mutedInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(selectedPage == page ? palette.primarySoft : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(7)
        .frame(height: 52)
        .background(palette.sidebar.opacity(0.18))
    }

    private func settingsHeader(_ palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(selectedPage.titleKey))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(palette.ink)
            Text(L10n.text(selectedPage.subtitleKey))
                .font(.system(size: 12.5))
                .foregroundStyle(palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .appearance:
            AppearanceSettingsPage(
                appearanceRaw: $appearanceRaw,
                themeRaw: $themeRaw,
                accentRaw: $accentRaw,
                customAccentHex: $customAccentHex
            )
        case .general:
            GeneralSettingsPage(preferences: $model.appPreferences)
        case .git:
            GitSettingsPage(model: model, preferences: $model.appPreferences)
        case .agent:
            AgentSettingsPage(model: model)
        case .translation:
            TranslationSettingsPage(model: model)
        }
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance
    case general
    case git
    case agent
    case translation

    var id: String { rawValue }
    var titleKey: String { "settings.\(rawValue).title" }
    var subtitleKey: String { "settings.\(rawValue).subtitle" }

    var icon: String {
        switch self {
        case .appearance: "paintpalette"
        case .general: "slider.horizontal.3"
        case .git: "arrow.triangle.branch"
        case .agent: "sparkles"
        case .translation: "character.book.closed"
        }
    }
}

private struct AppearanceSettingsPage: View {
    @Binding var appearanceRaw: String
    @Binding var themeRaw: String
    @Binding var accentRaw: String
    @Binding var customAccentHex: String
    @Environment(\.colorScheme) private var colorScheme

    private var selectedTheme: AppVisualTheme {
        AppVisualTheme.resolved(themeRaw)
    }

    private var selectedAccent: AppAccentChoice {
        AppAccentChoice(rawValue: accentRaw) ?? .coral
    }

    var body: some View {
        SettingsSection(titleKey: "settings.appearance.mode") {
            SettingsControlRow(
                titleKey: "settings.appearance.mode_control",
                descriptionKey: "settings.appearance.mode_control.body"
            ) {
                Picker("", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(L10n.text("appearance.\(appearance.rawValue)"))
                            .tag(appearance.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
        }

        SettingsSection(titleKey: "settings.appearance.theme_section") {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(AppVisualTheme.allCases) { theme in
                    ThemeChoiceButton(
                        theme: theme,
                        isSelected: selectedTheme == theme,
                        colorScheme: colorScheme,
                        accent: selectedAccent,
                        customAccentHex: customAccentHex
                    ) {
                        themeRaw = theme.rawValue
                    }
                }
            }
        }

        SettingsSection(titleKey: "settings.appearance.accent_section") {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(AppAccentChoice.allCases) { accent in
                    AccentChoiceButton(
                        accent: accent,
                        isSelected: selectedAccent == accent,
                        colorScheme: colorScheme,
                        customAccentHex: customAccentHex
                    ) {
                        accentRaw = accent.rawValue
                    }
                }
            }

            if selectedAccent == .custom {
                SettingsControlRow(
                    titleKey: "settings.appearance.custom_accent",
                    descriptionKey: "settings.appearance.custom_accent.body"
                ) {
                    ColorPicker("", selection: customColorBinding, supportsOpacity: false)
                        .labelsHidden()
                }
            }
        }
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: customAccentHex) ?? Color(red: 0.31, green: 0.49, blue: 1) },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                customAccentHex = String(
                    format: "#%02X%02X%02X",
                    Int((rgb.redComponent * 255).rounded()),
                    Int((rgb.greenComponent * 255).rounded()),
                    Int((rgb.blueComponent * 255).rounded())
                )
            }
        )
    }
}

private struct ThemeChoiceButton: View {
    let theme: AppVisualTheme
    let isSelected: Bool
    let colorScheme: ColorScheme
    let accent: AppAccentChoice
    let customAccentHex: String
    let action: () -> Void

    var body: some View {
        let preview = AppPalette(
            colorScheme,
            theme: theme,
            accentChoice: accent,
            customAccentHex: customAccentHex
        )
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    LinearGradient(
                        colors: [preview.background, preview.primarySoft.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(preview.sidebar)
                            .frame(width: 54)
                            .overlay {
                                VStack(spacing: 5) {
                                    Circle().fill(preview.primary).frame(width: 9, height: 9)
                                    RoundedRectangle(cornerRadius: 2).fill(preview.ink.opacity(0.72)).frame(width: 26, height: 4)
                                    RoundedRectangle(cornerRadius: 2).fill(preview.divider).frame(width: 30, height: 4)
                                }
                            }
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(preview.surface)
                            .overlay {
                                VStack(spacing: 8) {
                                    HStack {
                                        RoundedRectangle(cornerRadius: 2).fill(preview.ink).frame(width: 54, height: 5)
                                        Spacer()
                                        RoundedRectangle(cornerRadius: 4).fill(preview.primary).frame(width: 42, height: 12)
                                    }
                                    RoundedRectangle(cornerRadius: 4).fill(preview.raisedSurface).frame(height: 28)
                                }
                                .padding(10)
                            }
                    }
                    .padding(10)
                }
                .frame(height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.76), lineWidth: 1)
                }

                HStack(spacing: 6) {
                    Text(L10n.text("theme.\(theme.rawValue)"))
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(preview.primary)
                    }
                }
            }
            .padding(10)
            .foregroundStyle(preview.ink)
            .background(preview.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? preview.primary : preview.divider, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct AccentChoiceButton: View {
    let accent: AppAccentChoice
    let isSelected: Bool
    let colorScheme: ColorScheme
    let customAccentHex: String
    let action: () -> Void

    var body: some View {
        let palette = AppPalette(
            colorScheme,
            accentChoice: accent,
            customAccentHex: customAccentHex
        )
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(palette.primary)
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.7), lineWidth: 1)
                    }
                Text(L10n.text("accent.\(accent.rawValue)"))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(palette.primary)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .foregroundStyle(palette.ink)
            .background(isSelected ? palette.primarySoft : palette.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? palette.primary : palette.divider, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct GeneralSettingsPage: View {
    @Binding var preferences: AppPreferences

    var body: some View {
        SettingsSection(titleKey: "settings.general.language_section") {
            SettingsControlRow(
                titleKey: "settings.general.language",
                descriptionKey: "settings.general.language.body"
            ) {
                Picker("", selection: $preferences.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(L10n.text("settings.language.\(language.rawValue)"))
                            .tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }
        }

        SettingsSection(titleKey: "settings.general.startup") {
            SettingsControlRow(
                titleKey: "settings.general.default_workspace",
                descriptionKey: "settings.general.default_workspace.body"
            ) {
                Picker("", selection: $preferences.defaultWorkspace) {
                    ForEach(WorkspaceSection.allCases) { section in
                        Text(L10n.text("nav.\(section.rawValue)"))
                            .tag(section)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }

            SettingsControlRow(
                titleKey: "settings.general.reopen_repository",
                descriptionKey: "settings.general.reopen_repository.body"
            ) {
                Toggle("", isOn: $preferences.reopenLastRepository)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }
}

private struct GitSettingsPage: View {
    @ObservedObject var model: WorkspaceViewModel
    @Binding var preferences: AppPreferences
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsSection(titleKey: "settings.git.discovery") {
            SettingsControlRow(
                titleKey: "repository.scan.now",
                descriptionKey: "repository.scan.now.body"
            ) {
                Button {
                    openWindow(id: "repository-scanner")
                } label: {
                    if model.isScanningRepositories {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text(L10n.text("repository.scan.view_progress"))
                        }
                    } else {
                        Text(L10n.text("repository.scan.open"))
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            let palette = AppPalette(colorScheme)
            Label(
                L10n.format("repository.scan.managed", model.localRepositories.count),
                systemImage: "externaldrive.fill"
            )
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(palette.subtleInk)
        }

        SettingsSection(titleKey: "settings.git.live") {
            SettingsControlRow(
                titleKey: "settings.git.live_refresh",
                descriptionKey: "settings.git.live_refresh.body"
            ) {
                Toggle("", isOn: $preferences.liveRefreshEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsControlRow(
                titleKey: "settings.git.refresh_interval",
                descriptionKey: "settings.git.refresh_interval.body"
            ) {
                intervalPicker(
                    selection: $preferences.liveRefreshInterval,
                    values: [0.5, 1, 2, 5]
                )
            }

            SettingsControlRow(
                titleKey: "settings.git.remote_refresh",
                descriptionKey: "settings.git.remote_refresh.body"
            ) {
                Toggle("", isOn: $preferences.remoteRefreshEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsControlRow(
                titleKey: "settings.git.remote_interval",
                descriptionKey: "settings.git.remote_interval.body"
            ) {
                intervalPicker(
                    selection: $preferences.remoteRefreshInterval,
                    values: [15, 30, 60, 120]
                )
            }
        }

        SettingsSection(titleKey: "settings.git.status") {
            let palette = AppPalette(colorScheme)
            HStack(spacing: 9) {
                Image(systemName: model.liveSyncError == nil ? "dot.radiowaves.left.and.right" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.liveSyncError == nil ? palette.success : palette.warning)
                Text(model.liveSyncError ?? L10n.text(preferences.liveRefreshEnabled ? "settings.git.status.active" : "settings.git.status.paused"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.mutedInk)
                    .textSelection(.enabled)
            }
        }

        SettingsSection(titleKey: "settings.git.safety") {
            SettingsControlRow(
                titleKey: "settings.git.confirm_discard",
                descriptionKey: "settings.git.confirm_discard.body"
            ) {
                Toggle("", isOn: $preferences.confirmDiscardChanges)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private func intervalPicker(selection: Binding<Double>, values: [Double]) -> some View {
        Picker("", selection: selection) {
            ForEach(values, id: \.self) { value in
                Text(L10n.format("settings.seconds", value)).tag(value)
            }
        }
        .labelsHidden()
        .frame(width: 130)
    }
}

private struct TranslationSettingsPage: View {
    @ObservedObject var model: WorkspaceViewModel

    var body: some View {
        SettingsSection(titleKey: "settings.translation.defaults") {
            SettingsControlRow(
                titleKey: "settings.translation.default_target",
                descriptionKey: "settings.translation.default_target.body"
            ) {
                Picker("", selection: $model.appPreferences.defaultTranslationTarget) {
                    ForEach(CodexTranslationTarget.allCases) { target in
                        Text(L10n.text("codex.translate.\(target.rawValue)"))
                            .tag(target)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }
        }

        AIConfigurationEditor(
            titleKey: "settings.translation.engine",
            descriptionKey: "settings.translation.engine.body",
            lane: .translation,
            configuration: $model.translationAIConfiguration,
            availability: model.translationAIAvailability
        )
    }
}

private struct AgentSettingsPage: View {
    @ObservedObject var model: WorkspaceViewModel

    var body: some View {
        SettingsSection(titleKey: "settings.agent.profile") {
            GitAgentCapabilitiesView()

            SettingsControlRow(
                titleKey: "settings.agent.draft_detail",
                descriptionKey: "settings.agent.draft_detail.body"
            ) {
                Picker("", selection: $model.appPreferences.commitDraftDetail) {
                    ForEach(CommitDraftDetail.allCases) { detail in
                        Text(L10n.text("commit.draft_detail.\(detail.rawValue)"))
                            .tag(detail)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
        }

        SettingsSection(titleKey: "settings.agent.engine") {
            AIConfigurationEditor(
                titleKey: "ai.settings.project",
                descriptionKey: "ai.settings.project.body",
                lane: .project,
                configuration: $model.projectAIConfiguration,
                availability: model.codexAvailability
            )
        }
    }
}

private struct GitAgentCapabilitiesView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let skills = [
        "settings.agent.skill.changes",
        "settings.agent.skill.commits",
        "settings.agent.skill.history",
        "settings.agent.skill.conflicts",
        "settings.agent.skill.pull_requests",
        "settings.agent.skill.actions"
    ]

    private let tools = ["git status", "git diff", "git log", "git show", "gh pr", "gh issue", "gh run"]

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                ForEach(skills, id: \.self) { key in
                    Label(L10n.text(key), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.mutedInk)
                        .symbolRenderingMode(.hierarchical)
                }
            }

            HStack(spacing: 6) {
                ForEach(tools, id: \.self) { tool in
                    Text(tool)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 7)
                        .frame(height: 23)
                        .background(palette.accentSoft)
                        .clipShape(Capsule())
                }
            }

            Text(L10n.text("settings.agent.tools.body"))
                .font(.system(size: 10.5))
                .foregroundStyle(palette.subtleInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let titleKey: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text(titleKey))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(palette.ink)
            content
        }
        .padding(.bottom, 22)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.divider).frame(height: 1)
        }
    }
}

private struct SettingsControlRow<Control: View>: View {
    let titleKey: String
    let descriptionKey: String
    @ViewBuilder let control: Control
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(titleKey))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.ink)
                Text(L10n.text(descriptionKey))
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            control
        }
    }
}

private struct AIConfigurationEditor: View {
    let titleKey: String
    let descriptionKey: String
    let lane: AIExecutionLane
    @Binding var configuration: AIProviderConfiguration
    let availability: CodexAvailability

    @Environment(\.colorScheme) private var colorScheme
    @State private var showsArguments = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(titleKey))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.ink)
                    Text(L10n.text(descriptionKey))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.mutedInk)
                }
                Spacer()
                AISettingsAvailability(availability: availability)
            }

            HStack(spacing: 10) {
                fieldLabel("ai.settings.provider")
                Picker("", selection: providerBinding) {
                    ForEach(AIProviderPreset.allCases) { preset in
                        Text(L10n.text(preset.localizationKey)).tag(preset)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                Spacer()
            }

            HStack(spacing: 10) {
                fieldLabel("ai.settings.name")
                TextField("", text: $configuration.displayName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 10) {
                fieldLabel("ai.settings.executable")
                TextField(L10n.text("ai.settings.executable.placeholder"), text: $configuration.executable)
                    .textFieldStyle(.roundedBorder)
                Button(L10n.text("github.action.choose")) { chooseExecutable() }
                    .buttonStyle(SecondaryButtonStyle())
            }

            DisclosureGroup(isExpanded: $showsArguments) {
                VStack(alignment: .leading, spacing: 12) {
                    argumentField(titleKey: "ai.settings.version_arguments", text: $configuration.versionArguments, minHeight: 42)

                    if lane == .project {
                        argumentField(titleKey: "ai.settings.analyze_arguments", text: $configuration.analyzeArguments)
                        argumentField(titleKey: "ai.settings.edit_arguments", text: $configuration.editArguments)
                    } else {
                        argumentField(titleKey: "ai.settings.translation_arguments", text: $configuration.translationArguments)
                    }

                    HStack {
                        Text(L10n.text("ai.settings.output"))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(palette.mutedInk)
                        Picker("", selection: $configuration.outputFormat) {
                            ForEach(AIOutputFormat.allCases) { format in
                                Text(L10n.text("ai.output.\(format.rawValue)")).tag(format)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        Spacer()
                    }

                    Text(L10n.text("ai.settings.arguments.help"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.subtleInk)
                }
                .padding(.top, 10)
            } label: {
                Text(L10n.text("ai.settings.arguments"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.mutedInk)
            }

            Text(L10n.text("ai.settings.credentials"))
                .font(.system(size: 10.5))
                .foregroundStyle(palette.subtleInk)
        }
    }

    private var providerBinding: Binding<AIProviderPreset> {
        Binding(
            get: { configuration.preset },
            set: { configuration = .preset($0) }
        )
    }

    private func fieldLabel(_ key: String) -> some View {
        let palette = AppPalette(colorScheme)
        return Text(L10n.text(key))
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(palette.mutedInk)
            .frame(width: 82, alignment: .leading)
    }

    private func argumentField(
        titleKey: String,
        text: Binding<String>,
        minHeight: CGFloat = 78
    ) -> some View {
        let palette = AppPalette(colorScheme)
        return VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text(titleKey))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.mutedInk)
            TextEditor(text: text)
                .font(.system(size: 11.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: minHeight)
                .background(palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.divider, lineWidth: 1)
                }
        }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("github.action.choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        configuration.executable = url.path
    }
}

private struct AISettingsAvailability: View {
    let availability: CodexAvailability
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        Label(label, systemImage: availability.state == .available ? "checkmark.circle.fill" : "circle.dotted")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(availability.state == .available ? palette.success : palette.subtleInk)
    }

    private var label: String {
        switch availability.state {
        case .checking: L10n.text("codex.status.checking")
        case .available: L10n.text("codex.status.available")
        case .unavailable: L10n.text("codex.status.unavailable")
        }
    }
}
