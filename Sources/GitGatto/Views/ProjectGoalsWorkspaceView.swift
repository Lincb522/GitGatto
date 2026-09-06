import SwiftUI

struct ProjectGoalsWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @State private var query = ""
    @State private var filter = ProjectGoalListFilter.all
    @State private var showsComposer = false
    @State private var showsCompactDetail = false
    @State private var showsQuickGuide = false

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }
    private var goals: [ProjectGoal] {
        ProjectGoalPresentation.goals(model.currentRepositoryGoals, filter: filter, query: query)
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        GeometryReader { geometry in
            VStack(spacing: 0) {
                commandBar(palette, compact: geometry.size.width < 760)
                Divider().overlay(palette.divider)
                if showsComposer {
                    ProjectGoalComposerView(model: model) {
                        showsComposer = false
                        showsCompactDetail = true
                        query = ""
                        filter = .all
                    } onCancel: {
                        showsComposer = false
                    }
                } else if model.currentRepositoryGoals.isEmpty {
                    ContentUnavailableView {
                        GattoLabel(L10n.text("goal.empty"), systemImage: "checkmark.seal")
                    } description: {
                        Text(L10n.text("goal.workspace.empty"))
                    } actions: {
                        Button(L10n.text("goal.new")) { showsComposer = true }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(model.snapshot == nil)
                    }
                } else if geometry.size.width < 760 {
                    if showsCompactDetail, let goal = model.selectedProjectGoal {
                        ProjectGoalDetailView(model: model, goal: goal).id(goal.id)
                    } else {
                        goalList(palette)
                    }
                } else {
                    HSplitView {
                        goalList(palette)
                            .frame(minWidth: 240, idealWidth: 278, maxWidth: 340)
                        if let goal = model.selectedProjectGoal, goals.contains(where: { $0.id == goal.id }) {
                            ProjectGoalDetailView(model: model, goal: goal)
                                .id(goal.id)
                                .frame(minWidth: 390, maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ContentUnavailableView.search(text: query)
                                .frame(minWidth: 390, maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
        }
        .foregroundStyle(palette.ink)
        .fontDesign(theme == .console ? .monospaced : .default)
        .background(theme == .softGlass ? Color.clear : palette.background)
        .task(id: model.snapshot?.rootURL.standardizedFileURL.path) {
            showsComposer = false
            showsCompactDetail = false
            query = ""
            filter = .all
            if let goal = model.selectedProjectGoal { model.selectProjectGoal(goal) }
#if DEBUG
            if ProcessInfo.processInfo.environment["GITGATTO_WORKSPACE_PREVIEW"] == "1" { return }
#endif
            await model.refreshProjectGoals(showErrors: false)
        }
        .onChange(of: goals.map(\.id)) { _, ids in
            if let first = goals.first, !ids.contains(model.selectedProjectGoalID ?? first.id) {
                model.selectProjectGoal(first)
            }
        }
        .sheet(isPresented: $showsQuickGuide) { WorkspaceQuickGuideSheet(guide: .goals) }
#if DEBUG
        .background(DebugSnapshotCapture(
            isReady: ProcessInfo.processInfo.environment["GITGATTO_GOALS_P1_PREVIEW"] != nil
                || ProcessInfo.processInfo.environment["GITGATTO_GOALS_P2_PREVIEW"] != nil
                || ProcessInfo.processInfo.environment["GITGATTO_GOALS_P3_PREVIEW"] != nil
        ))
#endif
    }

    private func commandBar(_ palette: AppPalette, compact: Bool) -> some View {
        HStack(spacing: 10) {
            if compact, showsCompactDetail, !showsComposer {
                Button {
                    showsCompactDetail = false
                } label: {
                    GattoLabel(L10n.text("goal.workspace.list"), systemImage: "chevron.left")
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Text(L10n.text("goal.title")).font(.system(size: 15, weight: .semibold))
            }
            Spacer(minLength: 4)
            ToolbarIconButton(systemName: "info.circle", helpKey: "workspace.guide.open") {
                showsQuickGuide = true
            }
            Button {
                showsComposer = true
            } label: {
                GattoLabel(L10n.text("goal.new"), systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.snapshot == nil || showsComposer)
            ToolbarIconButton(
                systemName: "arrow.clockwise", helpKey: "goal.action.refresh",
                isActive: model.isRefreshingProjectGoals,
                isDisabled: model.isRefreshingProjectGoals || model.activeProjectGoalID != nil
            ) { Task { await model.refreshProjectGoals() } }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
        .background(theme == .softGlass ? palette.surface.opacity(0.16) : palette.surface)
    }

    private func goalList(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                TextField(L10n.text("goal.workspace.search"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("goals.search")
                Picker(L10n.text("goal.workspace.filter"), selection: $filter) {
                    ForEach(ProjectGoalListFilter.allCases) { value in
                        Text(L10n.text("goal.workspace.filter.\(value.rawValue)")).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(12)
            if goals.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(goals) { goal in
                            Button {
                                model.selectProjectGoal(goal)
                                showsCompactDetail = true
                            } label: {
                                row(goal, palette: palette)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(model.selectedProjectGoal?.id == goal.id ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme == .softGlass ? palette.surface.opacity(0.10) : palette.surface)
    }

    private func row(_ goal: ProjectGoal, palette: AppPalette) -> some View {
        let selected = model.selectedProjectGoal?.id == goal.id
        return HStack(alignment: .top, spacing: 10) {
            Image(gattoSymbol: ProjectGoalAppearance.icon(goal.status))
                .font(.system(size: 17))
                .foregroundStyle(ProjectGoalAppearance.color(goal.status, palette))
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(goal.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(goal.branchName).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                    .foregroundStyle(palette.subtleInk)
                HStack(spacing: 6) {
                    Text(L10n.text("goal.status.\(goal.status.rawValue)"))
                    Spacer(minLength: 0)
                    Text("\(goal.satisfiedStepCount)/\(goal.steps.count)")
                        .monospacedDigit()
                }
                .font(.system(size: 11))
                .foregroundStyle(ProjectGoalAppearance.color(goal.status, palette))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .foregroundStyle(palette.ink)
        .background(selected ? palette.accentSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? palette.accent.opacity(0.35) : .clear))
        .contentShape(Rectangle())
    }
}

enum ProjectGoalAppearance {
    static func icon(_ status: ProjectGoalStatus) -> String {
        switch status {
        case .ready: "play.circle"
        case .running: "arrow.triangle.2.circlepath"
        case .waiting: "clock.arrow.circlepath"
        case .blocked: "exclamationmark.triangle.fill"
        case .completed: "checkmark.circle"
        case .cancelled: "xmark.circle.fill"
        }
    }

    static func color(_ status: ProjectGoalStatus, _ palette: AppPalette) -> Color {
        switch status {
        case .ready, .running: palette.accent
        case .waiting: palette.warning
        case .blocked: palette.danger
        case .completed: palette.success
        case .cancelled: palette.subtleInk
        }
    }
}
