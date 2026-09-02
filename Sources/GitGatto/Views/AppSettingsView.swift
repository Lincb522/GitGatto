import AppKit
import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var model: WorkspaceViewModel
    @ObservedObject var updateManager: AppUpdateManager
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @AppStorage(AppStyleDefaults.accentKey) private var accentRaw = AppAccentChoice.coral.rawValue
    @AppStorage(AppStyleDefaults.customAccentKey) private var customAccentHex = "#4F7DFF"
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPage: SettingsPage = .appearance
    @State private var showsSavedState = false

    init(model: WorkspaceViewModel, updateManager: AppUpdateManager) {
        self.model = model
        self.updateManager = updateManager
#if DEBUG
        let previewPage = ProcessInfo.processInfo.environment["GITGATTO_SETTINGS_PAGE"]
            .flatMap(SettingsPage.init(rawValue:)) ?? .appearance
        _selectedPage = State(initialValue: previewPage)
#endif
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        Group {
            switch AppVisualTheme.resolved(themeRaw) {
            case .standard:
                standardLayout(palette)
            case .softGlass:
                softGlassLayout(palette)
            case .console:
                consoleLayout(palette)
            case .emerald:
                emeraldLayout(palette)
            case .folio:
                folioLayout(palette)
            }
        }
        .frame(minWidth: 820, minHeight: 650)
        .background(Color.clear)
#if DEBUG
        .background(
            DebugSnapshotCapture(
                isReady: ProcessInfo.processInfo.environment["GITGATTO_SETTINGS_PREVIEW"] == "1"
            )
        )
#endif
    }

    private func standardLayout(_ palette: AppPalette) -> some View {
        HStack(spacing: 0) {
            standardSidebar(palette)
                .frame(width: 216)
                .background(palette.sidebar)

            Rectangle()
                .fill(palette.divider)
                .frame(width: 1)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(L10n.text(selectedPage.titleKey))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.ink)

                    Spacer()
                    savedState(palette)
                    saveButton
                }
                .padding(.horizontal, 22)
                .frame(height: 64)
                .background(palette.surface)

                Rectangle()
                    .fill(palette.divider)
                    .frame(height: 1)

                settingsContent(palette, includesPageTitle: false)
                    .background(palette.background)
            }
        }
    }

    private func standardSidebar(_ palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AppBrandLockup(iconSize: 36, wordmarkWidth: 100, spacing: 8)
                .padding(.leading, 20)
                .padding(.top, 22)
                .frame(height: 82, alignment: .leading)

            VStack(spacing: 4) {
                ForEach(SettingsPage.allCases) { page in
                    Button {
                        select(page)
                    } label: {
                        HStack(spacing: 10) {
                            Image(gattoSymbol: page.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 18)
                                .foregroundStyle(selectedPage == page ? palette.primary : palette.mutedInk)
                            Text(L10n.text(page.titleKey))
                                .font(.system(size: 12.5, weight: selectedPage == page ? .semibold : .medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selectedPage == page ? palette.ink : palette.mutedInk)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(selectedPage == page ? palette.primarySoft : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Spacer()
        }
    }

    private func softGlassLayout(_ palette: AppPalette) -> some View {
        VStack(spacing: 12) {
            glassWindowBar(palette)
                .appGlassPanel()

            glassNavigation(palette)
                .appGlassPanel(cornerRadius: 14, elevated: false)

            settingsContent(palette, includesPageTitle: true)
                .appGlassPanel()
        }
        .padding(12)
    }

    private func emeraldLayout(_ palette: AppPalette) -> some View {
        let sidebarPalette = AppPalette(.dark)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                AppBrandLockup(iconSize: 36, wordmarkWidth: 98, spacing: 8)
                    .padding(.horizontal, 16)
                    .padding(.top, 22)
                    .frame(height: 82, alignment: .leading)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(SettingsPage.allCases) { page in
                            Button {
                                select(page)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(gattoSymbol: page.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(width: 22, height: 22)
                                    Text(L10n.text(page.titleKey))
                                        .font(.system(size: 11.5, weight: selectedPage == page ? .semibold : .medium))
                                    Spacer(minLength: 0)
                                    if selectedPage == page {
                                        Circle()
                                            .fill(sidebarPalette.accent)
                                            .frame(width: 6, height: 6)
                                    }
                                }
                                .foregroundStyle(selectedPage == page ? sidebarPalette.ink : sidebarPalette.mutedInk)
                                .padding(.horizontal, 12)
                                .frame(height: 40)
                                .background(selectedPage == page ? sidebarPalette.raisedSurface : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 10)
                }

                HStack(spacing: 8) {
                    savedState(sidebarPalette)
                    Spacer(minLength: 0)
                    saveButton
                }
                .padding(10)
            }
            .frame(width: 220)
            .background(sidebarPalette.sidebar)
            .emeraldSurface(.dark, cornerRadius: 16)
            .environment(\.colorScheme, .dark)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(gattoSymbol: selectedPage.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 38, height: 38)
                        .background(palette.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(L10n.text(selectedPage.titleKey))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: 64)
                .emeraldSurface(.elevated, cornerRadius: 16)

                settingsContent(palette, includesPageTitle: false)
                    .padding(6)
                    .emeraldSurface(.panel, cornerRadius: 16)
            }
        }
        .padding(12)
    }

    private func folioLayout(_ palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            folioSettingsRail()
                .frame(width: 58)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    AppBrandLockup(iconSize: 34, wordmarkWidth: 92, spacing: 7)

                    Rectangle()
                        .fill(palette.divider)
                        .frame(width: 1, height: 28)

                    Image(gattoSymbol: selectedPage.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 34, height: 34)
                        .background(palette.accentSoft)
                        .clipShape(Circle())

                    Text(L10n.text(selectedPage.titleKey))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.ink)

                    Spacer(minLength: 0)
                    savedState(palette)
                    saveButton
                }
                .padding(.horizontal, 16)
                .frame(height: 68)
                .folioSurface(.elevated, cornerRadius: 16)

                settingsContent(palette, includesPageTitle: false)
                    .padding(6)
                    .folioSurface(.panel, cornerRadius: 16)
            }
        }
        .padding(14)
    }

    private func folioSettingsRail() -> some View {
        let railPalette = AppPalette(
            .dark,
            theme: .folio,
            accentChoice: AppAccentChoice(rawValue: accentRaw) ?? .blue,
            customAccentHex: customAccentHex
        )
        return VStack(spacing: 7) {
            ForEach(SettingsPage.allCases) { page in
                Button {
                    select(page)
                } label: {
                    Image(gattoSymbol: page.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedPage == page ? railPalette.sidebar : railPalette.ink)
                        .frame(width: 38, height: 38)
                        .background(selectedPage == page ? railPalette.ink : Color.clear)
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(L10n.text(page.titleKey))
                .accessibilityLabel(L10n.text(page.titleKey))
                .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
            }

            Spacer(minLength: 0)

            Circle()
                .fill(model.isCodexRunning ? railPalette.warning : railPalette.success)
                .frame(width: 7, height: 7)
                .padding(.bottom, 5)
                .accessibilityHidden(true)
        }
        .padding(.top, 54)
        .padding(.bottom, 10)
        .frame(maxHeight: .infinity)
        .background(railPalette.sidebar)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
    }

    private func consoleLayout(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AppBrandLockup(iconSize: 30, wordmarkWidth: 76, spacing: 7)
                    .padding(.leading, AppThemeLayout.titlebarBrandLeading)

                Rectangle().fill(palette.divider).frame(width: 1, height: 26)

                Text(L10n.text("console.command.settings"))
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.accent)

                Spacer()

                HStack(spacing: 6) {
                    ConsoleBreathingLight(isBusy: model.isCodexRunning)
                    Text(L10n.text(model.isCodexRunning ? "console.status.running" : "console.status.ready"))
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(model.isCodexRunning ? palette.warning : palette.success)
                }
                .padding(.trailing, 14)
            }
            .padding(.top, 18)
            .frame(height: 72)
            .background(palette.sidebar)

            Rectangle().fill(palette.divider).frame(height: 1)

            HStack(spacing: 0) {
                consoleSettingsRail(palette)
                    .frame(width: 82)

                Rectangle().fill(palette.divider).frame(width: 1)

                settingsContent(palette, includesPageTitle: true)
                    .background(palette.background)

                Rectangle().fill(palette.divider).frame(width: 1)

                consoleSettingsStatus(palette)
                    .frame(width: 188)
            }
        }
    }

    private func consoleSettingsRail(_ palette: AppPalette) -> some View {
        VStack(spacing: 4) {
            ForEach(SettingsPage.allCases) { page in
                Button {
                    select(page)
                } label: {
                    VStack(spacing: 5) {
                        Image(gattoSymbol: page.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(L10n.text(page.titleKey))
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(selectedPage == page ? palette.accent : palette.mutedInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(selectedPage == page ? palette.accentSoft : Color.clear)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(selectedPage == page ? palette.accent : Color.clear)
                            .frame(width: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.text(page.titleKey))
                .accessibilityLabel(L10n.text(page.titleKey))
                .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .background(palette.sidebar)
    }

    private func consoleSettingsStatus(_ palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text(selectedPage.titleKey).uppercased())
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.accent)

            consoleStatusRow(
                title: L10n.text("settings.appearance.mode_control"),
                value: L10n.text("appearance.\(appearanceRaw)"),
                palette: palette
            )
            consoleStatusRow(
                title: L10n.text("settings.appearance.theme_section"),
                value: L10n.text("theme.console"),
                palette: palette
            )
            consoleStatusRow(
                title: L10n.text("settings.appearance.accent_section"),
                value: L10n.text("accent.\(accentRaw)"),
                palette: palette
            )

            Spacer(minLength: 10)
            savedState(palette)
            saveButton
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .background(palette.sidebar)
    }

    private func consoleStatusRow(title: String, value: String, palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.subtleInk)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.ink)
                .lineLimit(2)
        }
    }

    private func glassWindowBar(_ palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            AppBrandLockup(iconSize: 38, wordmarkWidth: 102, spacing: 8)

            Rectangle()
                .fill(palette.divider)
                .frame(width: 1, height: 26)

            Text(L10n.text("settings.title"))
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(palette.ink)

            Spacer()
            savedState(palette)
            saveButton
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .padding(.top, 18)
        .frame(height: 78)
    }

    private func glassNavigation(_ palette: AppPalette) -> some View {
        HStack(spacing: 6) {
            ForEach(SettingsPage.allCases) { page in
                Button {
                    select(page)
                } label: {
                    HStack(spacing: 8) {
                        Image(gattoSymbol: page.icon)
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
                .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
            }
        }
        .padding(7)
        .frame(height: 52)
    }

    private func settingsContent(_ palette: AppPalette, includesPageTitle: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if includesPageTitle {
                    HStack(spacing: 10) {
                        Image(gattoSymbol: selectedPage.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.primary)
                            .frame(width: 30, height: 30)
                            .background(palette.primarySoft)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        Text(L10n.text(selectedPage.titleKey))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(palette.ink)
                    }
                    .padding(.bottom, 2)
                }

                pageContent
            }
            .padding(.horizontal, includesPageTitle ? 28 : 26)
            .padding(.vertical, includesPageTitle ? 24 : 8)
            .frame(maxWidth: includesPageTitle ? 780 : 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func savedState(_ palette: AppPalette) -> some View {
        if showsSavedState {
            GattoLabel(L10n.text("settings.saved"), systemImage: "checkmark.circle.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.success)
                .transition(.opacity)
        }
    }

    private var saveButton: some View {
        Button(L10n.text("settings.save")) {
            model.saveSettings()
            if reduceMotion {
                showsSavedState = true
            } else {
                withAnimation(.easeOut(duration: 0.18)) { showsSavedState = true }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    private func select(_ page: SettingsPage) {
        selectedPage = page
        showsSavedState = false
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
        case .updates:
            UpdateSettingsPage(manager: updateManager)
        }
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance
    case general
    case git
    case agent
    case translation
    case updates

    var id: String { rawValue }
    var titleKey: String { "settings.\(rawValue).title" }

    var icon: String {
        switch self {
        case .appearance: "paintpalette"
        case .general: "slider.horizontal.3"
        case .git: "arrow.triangle.branch"
        case .agent: "sparkles"
        case .translation: "ai.translation"
        case .updates: "arrow.triangle.2.circlepath"
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
                columns: [GridItem(.adaptive(minimum: 190, maximum: 250), spacing: 12)],
                spacing: 12
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        SettingsSection(titleKey: "settings.appearance.accent_section") {
            LazyVGrid(
                columns: accentColumns,
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

    private var accentColumns: [GridItem] {
        if selectedTheme == .standard {
            [GridItem(.adaptive(minimum: 105, maximum: 150), spacing: 8)]
        } else {
            Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
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
                ThemeLayoutPreview(theme: theme, palette: preview)
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
                        Image(gattoSymbol: "checkmark.circle.fill")
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

private struct ThemeLayoutPreview: View {
    let theme: AppVisualTheme
    let palette: AppPalette

    var body: some View {
        switch theme {
        case .standard:
            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Circle().fill(palette.primary).frame(width: 7, height: 7)
                        RoundedRectangle(cornerRadius: 2).fill(palette.ink).frame(width: 25, height: 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(index == 0 ? palette.primarySoft : Color.clear)
                            .frame(height: 13)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(index == 0 ? palette.primary : palette.mutedInk.opacity(0.56))
                                    .frame(width: index == 0 ? 30 : 24, height: 3)
                                    .padding(.leading, 6)
                            }
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .frame(width: 70)
                .background(palette.sidebar)

                Rectangle().fill(palette.divider).frame(width: 1)

                VStack(spacing: 0) {
                    HStack {
                        RoundedRectangle(cornerRadius: 2).fill(palette.ink).frame(width: 50, height: 5)
                        Spacer()
                        RoundedRectangle(cornerRadius: 4).fill(palette.primary).frame(width: 40, height: 12)
                    }
                    .padding(8)
                    Rectangle().fill(palette.divider).frame(height: 1)
                    VStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 3).fill(palette.raisedSurface).frame(height: 18)
                        RoundedRectangle(cornerRadius: 3).fill(palette.raisedSurface).frame(height: 18)
                    }
                    .padding(8)
                }
                .background(palette.background)
            }
        case .softGlass:
            ZStack {
                LinearGradient(
                    colors: [palette.background, palette.primarySoft.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.raisedSurface)
                        .frame(height: 20)
                        .overlay(alignment: .leading) {
                            HStack(spacing: 4) {
                                Circle().fill(palette.primary).frame(width: 7, height: 7)
                                RoundedRectangle(cornerRadius: 2).fill(palette.ink).frame(width: 28, height: 4)
                            }
                            .padding(.leading, 7)
                        }
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(palette.surface)
                        .frame(height: 15)
                        .overlay {
                            HStack(spacing: 8) {
                                ForEach(0..<4, id: \.self) { index in
                                    Capsule()
                                        .fill(index == 0 ? palette.primary : palette.mutedInk.opacity(0.38))
                                        .frame(width: index == 0 ? 22 : 16, height: 3)
                                }
                            }
                        }
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.raisedSurface)
                        .overlay {
                            HStack(spacing: 7) {
                                RoundedRectangle(cornerRadius: 4).fill(palette.surface).frame(width: 55)
                                RoundedRectangle(cornerRadius: 4).fill(palette.surface)
                            }
                            .padding(7)
                        }
                }
                .padding(8)
            }
        case .emerald:
            ZStack {
                LinearGradient(
                    colors: [palette.accent.opacity(0.78), palette.background],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                HStack(spacing: 7) {
                    VStack(spacing: 5) {
                        HStack(spacing: 3) {
                            Circle().fill(palette.accent).frame(width: 6, height: 6)
                            RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.86)).frame(width: 24, height: 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(0..<4, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(index == 0 ? Color.white.opacity(0.14) : Color.clear)
                                .frame(height: 11)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(index == 0 ? palette.accent : Color.white.opacity(0.45))
                                        .frame(width: index == 0 ? 24 : 18, height: 3)
                                        .padding(.leading, 5)
                                }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(7)
                    .frame(width: 56)
                    .background(OKLCHColor(0.145, 0.045, 155).color)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(palette.raisedSurface)
                            .frame(height: 19)
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 7).fill(palette.raisedSurface)
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 7).fill(palette.accentSoft)
                                RoundedRectangle(cornerRadius: 7).fill(palette.raisedSurface)
                            }
                        }
                    }
                    .padding(7)
                    .background(palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(8)
            }
        case .folio:
            ZStack {
                palette.background

                HStack(spacing: 7) {
                    VStack(spacing: 5) {
                        Circle()
                            .fill(Color.white.opacity(0.92))
                            .frame(width: 14, height: 14)
                            .overlay {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(OKLCHColor(0.205, 0.008, 255).color)
                                    .frame(width: 7, height: 3)
                            }

                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(index == 0 ? Color.white.opacity(0.92) : Color.clear)
                                .frame(width: 13, height: 13)
                                .overlay {
                                    Circle()
                                        .fill(
                                            index == 0
                                                ? OKLCHColor(0.205, 0.008, 255).color
                                                : Color.white.opacity(0.58)
                                        )
                                        .frame(width: 4, height: 4)
                                }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .frame(width: 30)
                    .background(OKLCHColor(0.205, 0.008, 255).color)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(spacing: 6) {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(palette.ink)
                                .frame(width: 42, height: 5)
                            Spacer(minLength: 0)
                            Circle()
                                .fill(palette.accentSoft)
                                .frame(width: 14, height: 14)
                        }
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(palette.raisedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(palette.raisedSurface)
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(palette.accentSoft)
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(palette.raisedSurface)
                            }
                        }
                    }
                }
                .padding(8)
            }
        case .console:
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(palette.success)
                        .frame(width: 5, height: 5)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(palette.accent)
                        .frame(width: 28, height: 3)
                    Spacer()
                    RoundedRectangle(cornerRadius: 1)
                        .fill(palette.mutedInk.opacity(0.68))
                        .frame(width: 34, height: 3)
                }
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(palette.sidebar)

                Rectangle().fill(palette.divider).frame(height: 1)

                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(index == 0 ? palette.accentSoft : Color.clear)
                                .frame(height: 12)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(index == 0 ? palette.accent : palette.mutedInk.opacity(0.42))
                                        .frame(width: 8, height: 3)
                                }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(4)
                    .frame(width: 28)
                    .background(palette.sidebar)

                    Rectangle().fill(palette.divider).frame(width: 1)

                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.raisedSurface)
                            .frame(height: 18)
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(palette.surface)
                                .frame(width: 54)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(palette.surface)
                        }
                    }
                    .padding(6)
                    .background(palette.background)
                }

                Rectangle().fill(palette.divider).frame(height: 1)

                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(index == 0 ? palette.accentSoft : palette.raisedSurface)
                            .frame(width: index == 0 ? 36 : 25, height: 7)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .frame(height: 14)
                .background(palette.sidebar)
            }
            .background(palette.background)
        }
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
                    Image(gattoSymbol: "checkmark")
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
                .onChange(of: preferences.language) { _, language in
                    L10n.activate(language)
                    AppPreferencesStore.saveLanguage(language)
                    MenuTitleLocalizer.localizeMainMenu()
                }
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

            SettingsControlRow(
                titleKey: "settings.general.launch_animation",
                descriptionKey: "settings.general.launch_animation.body"
            ) {
                Toggle("", isOn: $preferences.launchAnimationEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }

        SettingsSection(titleKey: "settings.general.window") {
            SettingsControlRow(
                titleKey: "settings.general.close_behavior",
                descriptionKey: "settings.general.close_behavior.body"
            ) {
                Picker("", selection: $preferences.windowCloseBehavior) {
                    ForEach(WindowCloseBehavior.allCases) { behavior in
                        Text(L10n.text("settings.close_behavior.\(behavior.rawValue)"))
                            .tag(behavior)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }
        }
    }
}

private struct UpdateSettingsPage: View {
    @ObservedObject var manager: AppUpdateManager

    var body: some View {
        SettingsSection(titleKey: "settings.updates.automatic") {
            SettingsControlRow(
                titleKey: "settings.updates.checks",
                descriptionKey: "settings.updates.checks.body"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { manager.automaticallyChecksForUpdates },
                        set: { manager.setAutomaticallyChecksForUpdates($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!manager.isConfigured)
            }

            SettingsControlRow(
                titleKey: "settings.updates.downloads",
                descriptionKey: "settings.updates.downloads.body"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { manager.automaticallyDownloadsUpdates },
                        set: { manager.setAutomaticallyDownloadsUpdates($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!manager.isConfigured)
            }
        }

        SettingsSection(titleKey: "settings.updates.manual") {
            SettingsControlRow(
                titleKey: "settings.updates.check_now",
                descriptionKey: "settings.updates.check_now.body"
            ) {
                Button(L10n.text("update.check")) {
                    manager.checkForUpdates()
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!manager.canCheckForUpdates)
            }
        }
        .onAppear { manager.startIfConfigured() }
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
            GattoLabel(
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
                Image(gattoSymbol: model.liveSyncError == nil ? "dot.radiowaves.left.and.right" : "exclamationmark.triangle.fill")
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

    private let tools = ["git status", "git diff", "git log", "git reflog", "git worktree", "git lfs", "gh pr", "gh run"]

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                ForEach(GitAgentSkill.allCases) { skill in
                    GattoLabel(L10n.text(skill.titleKey), systemImage: skill.systemImage)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.mutedInk)
                        .symbolRenderingMode(.hierarchical)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 78), spacing: 6)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(tools, id: \.self) { tool in
                    Text(tool)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 7)
                        .frame(height: 23)
                        .background(palette.accentSoft)
                        .clipShape(Capsule())
                        .frame(maxWidth: .infinity, alignment: .leading)
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
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue

    @ViewBuilder
    var body: some View {
        let palette = AppPalette(colorScheme)
        switch AppVisualTheme.resolved(themeRaw) {
        case .softGlass:
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text(titleKey))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                VStack(alignment: .leading, spacing: 15) { content }
            }
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.black.opacity(0.30)
                            : Color.white.opacity(0.34)
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.64),
                        lineWidth: 1
                    )
            }
        case .console:
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Text(">")
                        .foregroundStyle(palette.accent)
                    Text(L10n.text(titleKey))
                        .foregroundStyle(palette.ink)
                }
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))

                VStack(alignment: .leading, spacing: 14) { content }
            }
            .padding(14)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(palette.divider, lineWidth: 1)
            }
        case .emerald:
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 8) {
                    Circle().fill(palette.accent).frame(width: 7, height: 7)
                    Text(L10n.text(titleKey))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.ink)
                }
                VStack(alignment: .leading, spacing: 14) { content }
            }
            .padding(17)
            .emeraldSurface(.elevated, cornerRadius: 16)
        case .folio:
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(palette.accent)
                        .frame(width: 4, height: 16)
                    Text(L10n.text(titleKey))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.ink)
                }
                VStack(alignment: .leading, spacing: 14) { content }
            }
            .padding(17)
            .background(palette.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(palette.divider.opacity(0.78), lineWidth: 1)
            }
        case .standard:
            HStack(alignment: .top, spacing: 26) {
                Text(L10n.text(titleKey))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .frame(width: 132, alignment: .leading)
                VStack(alignment: .leading, spacing: 15) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 20)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.divider).frame(height: 1)
            }
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
        rowContent(palette)
    }

    private func rowContent(_ palette: AppPalette) -> some View {
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
        HStack(spacing: 6) {
            ConnectivityMotionGlyph(state: motionState, size: 15)
            Text(label)
        }
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

    private var motionState: ConnectivityMotionState {
        switch availability.state {
        case .checking: .checking
        case .available: .available
        case .unavailable: .unavailable
        }
    }
}
