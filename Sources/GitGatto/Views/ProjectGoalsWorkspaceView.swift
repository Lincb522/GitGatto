import SwiftUI

struct ProjectGoalsWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @State private var showsComposer = false
    @State private var showsHistory = false
    @State private var showsQuickGuide = false

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }
    private var currentGoal: ProjectGoal? {
        ProjectGoalPresentation.primaryGoal(model.currentRepositoryGoals, selectedID: model.selectedProjectGoalID)
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            commandBar(palette)
            Divider().overlay(palette.divider)
            if showsHistory {
                ProjectGoalHistoryView(model: model) { showsHistory = false }
            } else if showsComposer || model.currentRepositoryGoals.isEmpty {
                ProjectGoalComposerView(model: model) {
                    showsComposer = false
                } onCancel: {
                    showsComposer = false
                }
            } else if let goal = model.selectedProjectGoal ?? currentGoal {
                ProjectGoalDetailView(model: model, goal: goal).id(goal.id)
            }
        }
        .foregroundStyle(palette.ink)
        .fontDesign(theme == .console ? .monospaced : .default)
        .background(theme == .softGlass ? Color.clear : palette.background)
        .task(id: model.snapshot?.rootURL.standardizedFileURL.path) {
            showsComposer = false
            showsHistory = false
            if let goal = currentGoal { model.selectProjectGoal(goal) }
#if DEBUG
            if ProcessInfo.processInfo.environment["GITGATTO_WORKSPACE_PREVIEW"] == "1" { return }
#endif
            await model.refreshProjectGoals(showErrors: false)
        }
        .onChange(of: model.currentRepositoryGoals.map(\.id)) { _, _ in
            if model.selectedProjectGoal == nil, let goal = currentGoal { model.selectProjectGoal(goal) }
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

    private func commandBar(_ palette: AppPalette) -> some View {
        HStack(spacing: 10) {
            if showsHistory || (!showsComposer && model.selectedProjectGoal?.status.isTerminal == true && currentGoal?.status.isTerminal == false) {
                Button {
                    showsHistory = false
                    if let goal = currentGoal { model.selectProjectGoal(goal) }
                } label: {
                    GattoLabel(L10n.text("goal.workspace.current"), systemImage: "chevron.left")
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Text(L10n.text("goal.title")).font(.system(size: 15, weight: .semibold))
            }
            Spacer(minLength: 4)
            ToolbarIconButton(systemName: "info.circle", helpKey: "workspace.guide.open") { showsQuickGuide = true }
            ToolbarIconButton(systemName: "clock.arrow.circlepath", helpKey: "goal.workspace.filter.history", isDisabled: showsComposer) {
                showsHistory.toggle()
            }
            if !showsComposer && !model.currentRepositoryGoals.isEmpty {
                Button {
                    showsHistory = false
                    showsComposer = true
                } label: {
                    GattoLabel(L10n.text("goal.new"), systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.snapshot == nil || model.currentRepositoryGoals.contains { !$0.status.isTerminal })
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
        .background(theme == .softGlass ? palette.surface.opacity(0.16) : palette.surface)
    }
}

struct ProjectGoalHistoryView: View {
    @ObservedObject var model: WorkspaceViewModel
    let onSelected: () -> Void
    @State private var query = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        let goals = ProjectGoalPresentation.goals(model.currentRepositoryGoals, filter: .history, query: query)
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("goal.workspace.filter.history")).font(.system(size: 18, weight: .semibold))
            TextField(L10n.text("goal.workspace.search"), text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("goals.search")
            if goals.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(goals) { goal in
                            Button {
                                model.selectProjectGoal(goal)
                                onSelected()
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(gattoSymbol: ProjectGoalAppearance.icon(goal.status))
                                        .foregroundStyle(ProjectGoalAppearance.color(goal.status, palette))
                                        .frame(width: 24, height: 24).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(goal.displayTitle).fontWeight(.semibold)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(goal.branchName).foregroundStyle(palette.subtleInk)
                                        Text(goal.createdAt.formatted(.dateTime.locale(L10n.locale).year().month().day().hour().minute()))
                                            .foregroundStyle(palette.subtleInk)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(palette.raisedSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(L10n.text("goal.status.\(goal.status.rawValue)"))
                        }
                    }
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(palette.ink)
        .padding(22)
        .frame(maxWidth: 900, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
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
