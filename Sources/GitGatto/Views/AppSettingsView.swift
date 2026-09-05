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
            case .lumen:
                lumenLayout(palette)
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
        VStack(spacing: 0) {
            settingsWindowBar(palette)
            settingsCategoryBar(palette, iconLabels: true)
                .padding(.bottom, 10)
                .background(palette.sidebar)
            Rectangle().fill(palette.divider).frame(height: 1)
            settingsContent(palette, includesPageTitle: false)
                .background(palette.background)
        }
    }

    private func softGlassLayout(_ palette: AppPalette) -> some View {
        HStack(spacing: 0) {
            settingsIndex(palette)
                .frame(width: 202)
            Rectangle().fill(palette.divider.opacity(0.65)).frame(width: 1)
            VStack(spacing: 0) {
                settingsPageBar(palette)
                settingsContent(palette, includesPageTitle: false)
            }
            .padding(.trailing, 8)
        }
    }

    private func emeraldLayout(_ palette: AppPalette) -> some View {
        HStack(spacing: 0) {
            settingsIndex(AppPalette(.dark, theme: .emerald))
                .frame(width: 216)
                .background(AppPalette(.dark, theme: .emerald).sidebar)
                .environment(\.colorScheme, .dark)
            VStack(spacing: 0) {
                settingsPageBar(palette)
                Rectangle().fill(palette.divider).frame(height: 1)
                settingsContent(palette, includesPageTitle: false)
            }
            .background(palette.background)
        }
    }

    private func folioLayout(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            settingsWindowBar(palette)
            settingsCategoryBar(palette, iconLabels: false)
                .padding(.bottom, 16)
            settingsContent(palette, includesPageTitle: false)
                .folioSurface(.panel, cornerRadius: 16)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
        }
        .background(palette.background)
    }

    private func settingsWindowBar(_ palette: AppPalette) -> some View {
        HStack(spacing: 16) {
            AppBrandLockup(iconSize: 30, wordmarkWidth: 88, spacing: 7)
            Text(L10n.text("settings.title"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.mutedInk)
            Spacer(minLength: 12)
            savedState(palette)
            saveButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .frame(height: 78)
        .background(palette.sidebar)
    }

    private func settingsPageBar(_ palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            Text(L10n.text(selectedPage.titleKey))
                .font(.system(size: 17, weight: .semibold,
                              design: AppStyleDefaults.theme == .console ? .monospaced : .default))
                .foregroundStyle(palette.ink)
            Spacer(minLength: 12)
            savedState(palette)
            saveButton
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
        .frame(height: 82)
    }

    private func settingsIndex(_ palette: AppPalette) -> some View {
        let theme = AppStyleDefaults.theme
        return VStack(alignment: .leading, spacing: 0) {
            AppBrandLockup(iconSize: 30, wordmarkWidth: 88, spacing: 7)
                .padding(.leading, 20)
                .padding(.top, 18)
                .frame(height: 82)
            ScrollView(.vertical) {
                VStack(spacing: theme == .console ? 2 : 6) {
                    ForEach(SettingsPage.allCases) { page in
                        Button { select(page) } label: {
                            HStack(spacing: 10) {
                                Image(gattoSymbol: page.icon)
                                    .font(.system(size: 14, weight: .medium))
                                    .frame(width: 22)
                                Text(L10n.text(page.titleKey))
                                    .font(.system(size: 12.5, weight: selectedPage == page ? .semibold : .medium,
                                                  design: theme == .console ? .monospaced : .default))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(selectedPage == page ? palette.ink : palette.mutedInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, theme == .console ? 10 : 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedPage == page ? palette.raisedSurface : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
        }
    }

    private func settingsCategoryBar(_ palette: AppPalette, iconLabels: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: iconLabels ? 8 : 6) {
                ForEach(SettingsPage.allCases) { page in
                    Button { select(page) } label: {
                        Group {
                            if iconLabels {
                                VStack(spacing: 7) {
                                    Image(gattoSymbol: page.icon)
                                        .font(.system(size: 20, weight: .regular))
                                    Text(L10n.text(page.titleKey))
                                        .font(.system(size: 11.5, weight: selectedPage == page ? .semibold : .medium))
                                }
                                .padding(.horizontal, 12)
                                .frame(minWidth: 78, minHeight: 64)
                            } else {
                                HStack(spacing: 7) {
                                    Image(gattoSymbol: page.icon).font(.system(size: 12))
                                    Text(L10n.text(page.titleKey)).font(.system(size: 12, weight: .medium))
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(selectedPage == page ? (iconLabels ? palette.primary : palette.surface) : palette.mutedInk)
                        .background(selectedPage == page ? (iconLabels ? palette.primarySoft : palette.ink) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: iconLabels ? 8 : 16))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
                }
            }
            .padding(.horizontal, 22)
        }
    }

    private func lumenLayout(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                AppBrandLockup(iconSize: 36, wordmarkWidth: 108, spacing: 9)
                Rectangle().fill(palette.divider).frame(width: 1, height: 26)
                Text(L10n.text("settings.title"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 12)
                savedState(palette)
                saveButton
            }
            .padding(.horizontal, 26)
            .padding(.top, 24)
            .padding(.bottom, 8)
            .frame(height: 94)
            .lumenSurface(.chrome, cornerRadius: 0)

            lumenSettingsNavigation(palette)

            settingsContent(palette, includesPageTitle: false)
                .lumenSurface(.panel, cornerRadius: 14)
                .padding(18)
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    private func lumenSettingsNavigation(_ palette: AppPalette) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(SettingsPage.allCases) { page in
                    Button {
                        select(page)
                    } label: {
                        HStack(spacing: 8) {
                            Image(gattoSymbol: page.icon)
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 20, height: 20)
                            Text(L10n.text(page.titleKey))
                                .font(.system(size: 12.5, weight: selectedPage == page ? .semibold : .medium))
                                .fixedSize()
                        }
                        .foregroundStyle(selectedPage == page ? palette.ink : palette.mutedInk)
                        .padding(.horizontal, 12)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottom) {
                            if selectedPage == page {
                                Capsule().fill(palette.primary).frame(height: 2)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
                }
            }
            .padding(.horizontal, 18)
        }
        .scrollIndicators(.hidden)
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.divider).frame(height: 1)
        }
    }

    private func consoleLayout(_ palette: AppPalette) -> some View {
        HStack(spacing: 0) {
            settingsIndex(palette)
                .frame(width: 190)
                .background(palette.sidebar)
            Rectangle().fill(palette.divider).frame(width: 1)
            VStack(spacing: 0) {
                settingsPageBar(palette)
                    .background(palette.surface)
                Rectangle().fill(palette.divider).frame(height: 1)
                settingsContent(palette, includesPageTitle: false)
                    .background(palette.background)
            }
        }
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
        case .monitoring:
            MonitoringSettingsPage(
                engine: model.monitoringEngine,
                preferences: $model.appPreferences
            )
        case .recovery:
            RecoverySettingsPage(model: model, preferences: $model.appPreferences)
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
    case monitoring
    case recovery
    case agent
    case translation
    case updates

    var id: String {
        rawValue
    }

    var titleKey: String {
        "settings.\(rawValue).title"
    }

    var icon: String {
        switch self {
        case .appearance: "paintpalette"
        case .general: "slider.horizontal.3"
        case .git: "arrow.triangle.branch"
        case .monitoring: "dot.radiowaves.left.and.right"
        case .recovery: "externaldrive.badge.timemachine"
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch theme {
        case .standard, .softGlass:
            HStack(spacing: theme == .softGlass ? 6 : 0) {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.ink)
                        .frame(width: 32, height: 5)
                        .padding(.vertical, 8)
                    ForEach(0 ..< 4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(index == 0 ? palette.primary.opacity(0.55) : palette.mutedInk.opacity(0.28))
                            .frame(width: index == 0 ? 38 : 28, height: 6)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 7)
                .frame(width: 54)
                .background(palette.sidebar)
                VStack(spacing: 0) {
                    HStack {
                        RoundedRectangle(cornerRadius: 2).fill(palette.ink).frame(width: 30, height: 4)
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 3).fill(palette.primary).frame(width: 18, height: 10)
                    }
                    .padding(8)
                    Rectangle().fill(palette.divider).frame(height: 1)
                    HStack(spacing: 0) {
                        palette.raisedSurface.frame(width: 38)
                        Rectangle().fill(palette.divider).frame(width: 1)
                        palette.surface
                    }
                }
                .background(theme == .softGlass ? (colorScheme == .dark ? Color.black.opacity(0.4) : Color.white.opacity(0.7)) : palette.background)
                .clipShape(RoundedRectangle(cornerRadius: theme == .softGlass ? 7 : 0))
                .padding(.vertical, theme == .softGlass ? 8 : 0)
                .padding(.trailing, theme == .softGlass ? 7 : 0)
            }
            .background(palette.background)
        case .emerald:
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(Color.white).frame(width: 30, height: 5).padding(.vertical, 10)
                    ForEach(0 ..< 4, id: \.self) { index in
                        Capsule().fill(Color.white.opacity(index == 0 ? 0.75 : 0.25)).frame(width: 28, height: 5)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(width: 52)
                .background(AppPalette(.dark, theme: .emerald).sidebar)
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(palette.ink).frame(width: 42, height: 6).padding(.top, 10)
                    Capsule().fill(palette.mutedInk.opacity(0.4)).frame(width: 34, height: 3)
                    Rectangle().fill(palette.divider).frame(height: 1)
                    HStack(spacing: 8) {
                        palette.background
                        VStack(spacing: 7) {
                            ForEach(0 ..< 3, id: \.self) { _ in Capsule().fill(palette.divider).frame(height: 4) }
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3).fill(palette.raisedSurface).frame(height: 25)
                        }
                        .frame(width: 34)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.bottom, 8)
            }
            .background(palette.background)
        case .folio:
            VStack(spacing: 7) {
                HStack {
                    Capsule().fill(palette.ink).frame(width: 36, height: 5)
                    Spacer()
                    Capsule().fill(palette.raisedSurface).frame(width: 45, height: 13)
                }
                .frame(height: 18)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(0 ..< 4, id: \.self) { index in
                            HStack(spacing: 4) {
                                Circle().fill(palette.mutedInk).frame(width: 4, height: 4)
                                Capsule().fill(palette.mutedInk.opacity(0.55)).frame(height: 3)
                            }
                            .padding(4)
                            .background(index == 0 ? palette.raisedSurface : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: 38)
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            ForEach(0 ..< 3, id: \.self) { _ in RoundedRectangle(cornerRadius: 3).fill(palette.surface).frame(height: 16) }
                        }
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 6).fill(palette.surface)
                            RoundedRectangle(cornerRadius: 6).fill(palette.surface).frame(width: 32)
                        }
                    }
                }
            }
            .padding(8)
            .background(palette.background)
        case .lumen:
            ZStack {
                palette.background
                RadialGradient(
                    colors: [palette.danger.opacity(0.24), .clear],
                    center: .topLeading,
                    startRadius: 2,
                    endRadius: 110
                )
                RadialGradient(
                    colors: [palette.accent.opacity(0.22), .clear],
                    center: .topTrailing,
                    startRadius: 4,
                    endRadius: 120
                )

                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Circle().fill(palette.primary).frame(width: 7, height: 7)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.ink)
                            .frame(width: 30, height: 4)
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(palette.raisedSurface.opacity(0.84))
                            .frame(width: 44, height: 13)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(palette.raisedSurface.opacity(0.76))


                    HStack(spacing: 6) {
                        VStack(spacing: 4) {
                            ForEach(0 ..< 4, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(index == 0 ? palette.primarySoft : Color.clear)
                                    .frame(height: 10)
                                    .overlay(alignment: .leading) {
                                        Circle()
                                            .fill(index == 0 ? palette.primary : palette.mutedInk.opacity(0.45))
                                            .frame(width: 4, height: 4)
                                            .padding(.leading, 5)
                                    }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(5)
                        .frame(width: 48)

                        RoundedRectangle(cornerRadius: 7)
                            .fill(palette.surface)
                            .padding(.vertical, 7)
                            .padding(.trailing, 7)
                    }
                }

            }
        case .console:
            VStack(spacing: 0) {
                HStack {
                    Capsule().fill(palette.ink).frame(width: 28, height: 4)
                    Spacer()
                    Capsule().fill(palette.accent).frame(width: 22, height: 3)
                }
                .padding(7)
                .background(palette.sidebar)
                Rectangle().fill(palette.divider).frame(height: 1)
                HStack(spacing: 1) {
                    VStack(spacing: 9) {
                        ForEach(0 ..< 5, id: \.self) { _ in Rectangle().fill(palette.mutedInk).frame(width: 6, height: 6) }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 8)
                    .frame(width: 18)
                    .background(palette.sidebar)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(0 ..< 3, id: \.self) { index in
                            Rectangle().fill(palette.mutedInk.opacity(0.4)).frame(width: index == 0 ? 26 : 18, height: 3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(7)
                    .frame(width: 42)
                    .background(palette.sidebar)
                    VStack(spacing: 1) {
                        HStack(spacing: 1) {
                            palette.surface.frame(width: 34)
                            palette.sidebar
                        }
                        .frame(height: 15)
                        HStack(spacing: 1) {
                            palette.surface.frame(width: 36)
                            palette.background
                        }
                    }
                }
                Rectangle().fill(palette.sidebar).frame(height: 9)
            }
            .background(palette.divider)

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
        SettingsSection(titleKey: "settings.github.account") {
            GitHubAccountSettings(model: model)
        }

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

}

private struct GitHubAccountSettings: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(alignment: .center, spacing: 16) {
            Image(gattoSymbol: model.githubAccount == nil ? "person.crop.circle" : "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(model.githubAccount == nil ? palette.subtleInk : palette.success)
                .frame(width: 32, height: 32)
                .background(palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(model.githubAccount == nil
                    ? "settings.github.account.signed_out"
                    : "settings.github.account.connected"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.ink)

                Text(accountDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.mutedInk)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            if model.githubAccount == nil {
                Button {
                    model.beginGitHubLogin()
                } label: {
                    HStack(spacing: 7) {
                        if model.isLaunchingGitHubLogin {
                            ProgressView().controlSize(.small)
                        }
                        Text(L10n.text("github.action.login"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isLaunchingGitHubLogin)
            }

            Button(L10n.text("github.action.retry")) {
                model.retryGitHubProbe()
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.githubAvailability.state == .checking)
        }

        if let error = model.githubError {
            Text(error)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.danger)
                .textSelection(.enabled)
        } else if let activity = model.githubActivity {
            Text(activity)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.mutedInk)
        }
    }

    private var accountDetail: String {
        if let account = model.githubAccount {
            return L10n.format("settings.github.account.connected.body", account.login)
        }
        return L10n.text("settings.github.account.signed_out.body")
    }
}

private struct MonitoringSettingsPage: View {
    @ObservedObject var engine: MonitoringEngine
    @Binding var preferences: AppPreferences
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)

        SettingsSection(titleKey: "settings.monitoring.engine") {
            SettingsControlRow(
                titleKey: "settings.monitoring.engine_enabled",
                descriptionKey: "settings.monitoring.engine_enabled.body"
            ) {
                Toggle("", isOn: $preferences.monitoringEngineEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsControlRow(
                titleKey: "settings.monitoring.status_bar",
                descriptionKey: "settings.monitoring.status_bar.body"
            ) {
                Toggle("", isOn: $preferences.statusBarMonitoringEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(overallColor(palette))
                    .frame(width: 8, height: 8)
                Text(L10n.text(engine.overallState.localizationKey))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text(L10n.format("monitoring.summary", engine.activeChannelCount, engine.repositoryCount))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.mutedInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(palette.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(palette.divider, lineWidth: 1)
            }
        }

        SettingsSection(titleKey: "settings.monitoring.channels") {
            monitoringToggle(.workingTree, isOn: $preferences.liveRefreshEnabled)
            monitoringToggle(.remote, isOn: $preferences.remoteRefreshEnabled)
            monitoringToggle(.repositoryProtection, isOn: $preferences.repositoryBackupEnabled)
            monitoringToggle(.githubActions, isOn: $preferences.githubActionsMonitoringEnabled)
            monitoringToggle(.projectGoals, isOn: $preferences.projectGoalMonitoringEnabled)
        }

        SettingsSection(titleKey: "settings.monitoring.cadence") {
            SettingsControlRow(
                titleKey: "settings.git.refresh_interval",
                descriptionKey: "settings.git.refresh_interval.body"
            ) {
                intervalPicker(
                    selection: $preferences.liveRefreshInterval,
                    values: [0.5, 1, 2, 5]
                )
                .disabled(!preferences.monitoringEngineEnabled || !preferences.liveRefreshEnabled)
            }

            SettingsControlRow(
                titleKey: "settings.git.remote_interval",
                descriptionKey: "settings.git.remote_interval.body"
            ) {
                intervalPicker(
                    selection: $preferences.remoteRefreshInterval,
                    values: [15, 30, 60, 120]
                )
                .disabled(!preferences.monitoringEngineEnabled || !preferences.remoteRefreshEnabled)
            }
        }

        SettingsSection(titleKey: "monitoring.activity.title") {
            RepositoryActivityHeatmap(
                activity: engine.dailyActivity,
                accent: palette.primary,
                emptyColor: palette.divider.opacity(0.42),
                futureColor: palette.divider.opacity(0.18),
                labelColor: palette.subtleInk
            )
            .frame(height: 82)
            .accessibilityLabel(L10n.text("monitoring.activity.accessibility"))
        }
    }

    private func monitoringToggle(
        _ category: MonitoringCategory,
        isOn: Binding<Bool>
    ) -> some View {
        SettingsControlRow(
            titleKey: category.titleKey,
            descriptionKey: category.descriptionKey
        ) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!preferences.monitoringEngineEnabled)
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

    private func overallColor(_ palette: AppPalette) -> Color {
        switch engine.overallState {
        case .paused: palette.subtleInk
        case .healthy: palette.success
        case .monitoring: palette.primary
        case .attention: palette.warning
        }
    }
}

private struct RecoverySettingsPage: View {
    @ObservedObject var model: WorkspaceViewModel
    @Binding var preferences: AppPreferences
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        SettingsSection(titleKey: "settings.recovery.protection") {
            SettingsControlRow(
                titleKey: "settings.recovery.agent_protection",
                descriptionKey: "settings.recovery.agent_protection.body"
            ) {
                Toggle("", isOn: $preferences.agentEditProtectionEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!preferences.repositoryBackupEnabled)
            }

            SettingsControlRow(
                titleKey: "settings.recovery.external_protection",
                descriptionKey: "settings.recovery.external_protection.body"
            ) {
                Toggle("", isOn: $preferences.externalRepositoryProtectionEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!preferences.repositoryBackupEnabled)
            }

            HStack(spacing: 10) {
                Image(gattoSymbol: "externaldrive")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 34, height: 34)
                    .background(palette.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("settings.recovery.protected_repositories"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.mutedInk)
                    Text(L10n.format("settings.recovery.protected_repositories.value", model.protectedRepositoryCount))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(L10n.text("settings.recovery.storage_used"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.mutedInk)
                    Text(ByteCountFormatter.string(fromByteCount: model.repositoryBackupStorageBytes, countStyle: .file))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.ink)
                }
            }
        }

        SettingsSection(titleKey: "settings.recovery.storage") {
            VStack(alignment: .leading, spacing: 9) {
                Text(L10n.text("settings.recovery.storage.location"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.ink)
                Text(model.repositoryBackupDirectoryURL.path(percentEncoded: false))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.mutedInk)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .help(model.repositoryBackupDirectoryURL.path(percentEncoded: false))

                HStack(spacing: 8) {
                    Button(L10n.text("settings.recovery.storage.choose")) {
                        model.chooseRepositoryBackupDirectory()
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button(L10n.text("settings.recovery.storage.reveal")) {
                        model.revealRepositoryBackupStorage()
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button(L10n.text("settings.recovery.storage.reset")) {
                        model.resetRepositoryBackupDirectory()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isUsingDefaultDirectory)

                    if model.isMigratingRepositoryBackupStorage {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.text("settings.recovery.storage.migrating"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.mutedInk)
                    }
                }
                .disabled(model.isMigratingRepositoryBackupStorage)

                if let error = model.repositoryProtectionError {
                    GattoLabel(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }

        SettingsSection(titleKey: "settings.recovery.schedule") {
            SettingsControlRow(
                titleKey: "settings.git.backup_interval",
                descriptionKey: "settings.git.backup_interval.body"
            ) {
                Picker("", selection: $preferences.repositoryBackupIntervalMinutes) {
                    ForEach([5.0, 10.0, 15.0, 30.0, 60.0], id: \.self) { value in
                        Text(L10n.format("settings.minutes", value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .disabled(!preferences.repositoryBackupEnabled)
            }

            SettingsControlRow(
                titleKey: "settings.git.backup_major_files",
                descriptionKey: "settings.git.backup_major_files.body"
            ) {
                Picker("", selection: $preferences.majorBackupFileThreshold) {
                    ForEach([5, 10, 20, 40, 80], id: \.self) { value in
                        Text(L10n.format("settings.files", value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .disabled(!preferences.repositoryBackupEnabled)
            }

            SettingsControlRow(
                titleKey: "settings.git.backup_major_lines",
                descriptionKey: "settings.git.backup_major_lines.body"
            ) {
                Picker("", selection: $preferences.majorBackupLineThreshold) {
                    ForEach([100, 300, 500, 1000, 2000], id: \.self) { value in
                        Text(L10n.format("settings.lines", value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .disabled(!preferences.repositoryBackupEnabled)
            }
        }

        SettingsSection(titleKey: "settings.recovery.retention") {
            SettingsControlRow(
                titleKey: "settings.git.backup_retention",
                descriptionKey: "settings.git.backup_retention.body"
            ) {
                Picker("", selection: $preferences.repositoryBackupRetentionCount) {
                    ForEach(1 ... RepositoryBackupPolicy.maximumRetentionCount, id: \.self) { value in
                        Text(L10n.format("settings.backups", value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .disabled(!preferences.repositoryBackupEnabled)
            }

            SettingsControlRow(
                titleKey: "settings.git.backup_file_limit",
                descriptionKey: "settings.git.backup_file_limit.body"
            ) {
                Picker("", selection: $preferences.repositoryBackupMaximumFileSizeMB) {
                    ForEach([10, 25, 50, 100, 250], id: \.self) { value in
                        Text(L10n.format("settings.megabytes", value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .disabled(!preferences.repositoryBackupEnabled)
            }
        }
    }

    private var isUsingDefaultDirectory: Bool {
        model.repositoryBackupDirectoryURL.standardizedFileURL
            == RepositoryBackupService.defaultRootURL().standardizedFileURL
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

            SettingsControlRow(
                titleKey: "settings.agent.conversation_context",
                descriptionKey: "settings.agent.conversation_context.body"
            ) {
                Picker("", selection: $model.appPreferences.agentConversationHistoryLimit) {
                    ForEach([8, 16, 24, 40], id: \.self) { value in
                        Text(L10n.format("settings.agent.messages", value)).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            SettingsControlRow(
                titleKey: "settings.agent.default_mode",
                descriptionKey: "settings.agent.default_mode.body"
            ) {
                Picker("", selection: $model.appPreferences.defaultAgentRunMode) {
                    ForEach(CodexRunMode.allCases) { mode in
                        Text(L10n.text("codex.mode.\(mode.rawValue)")).tag(mode)
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

    private let tools = ["git status", "git diff", "git log", "git reflog", "git fsck", "git worktree", "git lfs", "gh pr", "gh release", "gh run"]

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
                Text(L10n.text(titleKey))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 12) { content }
            }
            .padding(.vertical, 18)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.divider).frame(height: 1) }
        case .emerald:
            VStack(alignment: .leading, spacing: 20) {
                Text(L10n.text(titleKey))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.ink)
                VStack(alignment: .leading, spacing: 18) { content }
            }
            .padding(.vertical, 24)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.divider).frame(height: 1) }
        case .folio:
            HStack(alignment: .top, spacing: 22) {
                Text(L10n.text(titleKey))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.mutedInk)
                    .frame(width: 118, alignment: .leading)
                VStack(alignment: .leading, spacing: 18) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 22)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.divider).frame(height: 1) }
        case .lumen:
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.text(titleKey))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.ink)
                VStack(alignment: .leading, spacing: 18) { content }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 20)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.divider).frame(height: 1)
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
