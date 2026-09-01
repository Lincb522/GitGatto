import SwiftUI

struct ProjectGoalsWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @State private var showsMergeConfirmation = false
    @State private var showsReleasePublishConfirmation = false
    @State private var showsReleaseInstallConfirmation = false
    @State private var inAppBrowserPage: InAppBrowserPage?

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            commandBar(palette)
            Rectangle().fill(palette.divider).frame(height: 1)
            if model.currentRepositoryGoals.isEmpty {
                emptyState(palette)
            } else {
                HSplitView {
                    goalList(palette)
                        .frame(minWidth: 250, idealWidth: 292, maxWidth: 360)
                    if let goal = model.selectedProjectGoal {
                        goalDetail(goal, palette: palette)
                            .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(theme == .softGlass ? Color.clear : palette.background)
        .task(id: model.snapshot?.rootURL.standardizedFileURL.path) {
            if let first = model.currentRepositoryGoals.first {
                model.selectProjectGoal(first)
            }
            await model.prepareProjectReleaseDraftIfNeeded()
#if DEBUG
            if ProcessInfo.processInfo.environment["GITGATTO_WORKSPACE_PREVIEW"] == "1" {
                return
            }
#endif
            await model.refreshProjectGoals(showErrors: false)
        }
        .confirmationDialog(
            L10n.text("goal.merge.confirm.title"),
            isPresented: $showsMergeConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.text("goal.action.merge"), role: .destructive) {
                Task { await model.mergeSelectedProjectGoal() }
            }
            Button(L10n.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("goal.merge.confirm.message"))
        }
        .confirmationDialog(
            L10n.text("goal.release.publish.confirm.title"),
            isPresented: $showsReleasePublishConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.text("goal.action.publish_release")) {
                Task { await model.publishSelectedProjectRelease() }
            }
            Button(L10n.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("goal.release.publish.confirm.message"))
        }
        .confirmationDialog(
            L10n.text("goal.release.install.confirm.title"),
            isPresented: $showsReleaseInstallConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.text("goal.action.install_release")) {
                Task { await model.installSelectedProjectRelease() }
            }
            Button(L10n.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("goal.release.install.confirm.message"))
        }
        .sheet(item: $inAppBrowserPage) { page in
            InAppBrowserSheet(url: page.url, persistent: page.persistent)
        }
#if DEBUG
        .background(
            DebugSnapshotCapture(
                isReady: ProcessInfo.processInfo.environment["GITGATTO_GOALS_P1_PREVIEW"] != nil
                    || ProcessInfo.processInfo.environment["GITGATTO_GOALS_P2_PREVIEW"] != nil
            )
        )
#endif
    }

    private func commandBar(_ palette: AppPalette) -> some View {
        HStack(spacing: 10) {
            Text(L10n.text("goal.title"))
                .font(font(15, weight: .semibold))
                .foregroundStyle(palette.ink)
            if model.activeProjectGoalCount > 0 {
                CountBadge(count: model.activeProjectGoalCount, emphasized: false)
            }
            Spacer()
            Button {
                model.projectGoalCommitMessage = ""
            } label: {
                HStack(spacing: 6) {
                    Image(gattoSymbol: "plus")
                    Text(L10n.text("goal.new"))
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.currentRepositoryGoals.contains { !$0.status.isTerminal })
            ToolbarIconButton(
                systemName: "arrow.clockwise",
                helpKey: "goal.action.refresh",
                isActive: model.isRefreshingProjectGoals,
                isDisabled: model.isRefreshingProjectGoals || model.activeProjectGoalID != nil
            ) {
                Task { await model.refreshProjectGoals() }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .background(theme == .softGlass ? palette.surface.opacity(0.16) : palette.surface)
    }

    private func emptyState(_ palette: AppPalette) -> some View {
        VStack(spacing: 16) {
            Image(gattoSymbol: "checkmark.seal")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(palette.accent)
                .frame(width: 58, height: 58)
                .background(palette.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(L10n.text("goal.empty"))
                .font(font(15, weight: .semibold))
                .foregroundStyle(palette.ink)
            goalComposer(palette)
                .frame(maxWidth: 460)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func goalList(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.currentRepositoryGoals) { goal in
                        Button {
                            model.selectProjectGoal(goal)
                        } label: {
                            goalRow(goal, palette: palette)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }

            if !model.currentRepositoryGoals.contains(where: { !$0.status.isTerminal }) {
                Rectangle().fill(palette.divider).frame(height: 1)
                goalComposer(palette)
                    .padding(12)
            }
        }
        .background(theme == .softGlass ? palette.surface.opacity(0.10) : palette.surface)
    }

    private func goalRow(_ goal: ProjectGoal, palette: AppPalette) -> some View {
        let selected = model.selectedProjectGoal?.id == goal.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(gattoSymbol: statusIcon(goal.status))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(statusColor(goal.status, palette: palette))
                    .frame(width: 24, height: 24)
                    .background(statusColor(goal.status, palette: palette).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(goalTitle(goal))
                    .font(font(12, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Int(goal.progress * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.subtleInk)
            }
            ProgressView(value: goal.progress)
                .tint(statusColor(goal.status, palette: palette))
            HStack {
                Text(L10n.text("goal.status.\(goal.status.rawValue)"))
                Spacer()
                Text(goal.updatedAt, style: .relative)
            }
            .font(font(9.5, weight: .medium))
            .foregroundStyle(palette.subtleInk)
        }
        .padding(12)
        .background(selected ? palette.accentSoft : palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? palette.accent.opacity(0.42) : palette.divider, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    private func goalComposer(_ palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L10n.text("goal.delivery.title"))
                .font(font(11.5, weight: .semibold))
                .foregroundStyle(palette.ink)
            TextField(
                L10n.text("goal.commit_message.placeholder"),
                text: $model.projectGoalCommitMessage
            )
            .textFieldStyle(.plain)
            .font(font(11, weight: .regular))
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(palette.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(palette.divider, lineWidth: 1)
            }
            HStack(spacing: 8) {
                Button(L10n.text("goal.action.create_github")) {
                    Task { await model.createGitHubDeliveryGoal() }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(L10n.text("goal.action.create_commit")) {
                    Task { await model.createProjectDeliveryGoal() }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .disabled(goalCreationDisabled)
            Rectangle().fill(palette.divider).frame(height: 1)
            HStack(spacing: 8) {
                TextField(
                    L10n.text("goal.release.version.placeholder"),
                    text: Binding(
                        get: { model.projectGoalReleaseVersion },
                        set: { model.updateProjectReleaseVersionDraft($0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(palette.divider, lineWidth: 1)
                }
                TextField(
                    L10n.text("goal.release.build.placeholder"),
                    text: $model.projectGoalReleaseBuildNumber
                )
                .textFieldStyle(.plain)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(width: 92, height: 34)
                .background(palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(palette.divider, lineWidth: 1)
                }
            }
            Button(L10n.text("goal.action.create_release")) {
                Task { await model.createCompleteReleaseGoal() }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(
                model.activeProjectGoalID != nil
                    || model.projectGoalReleaseVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.projectGoalReleaseBuildNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }

    private func goalDetail(_ goal: ProjectGoal, palette: AppPalette) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                summaryCard(goal, palette: palette)
                stepTrack(goal, palette: palette)
                metadataCard(goal, palette: palette)
                if let failure = goal.lastActionFailure {
                    actionsFailureCard(goal, failure: failure, palette: palette)
                }
                if goal.lastActionFailure == nil,
                   let error = goal.lastError,
                   !error.isEmpty {
                    Text(error)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.danger)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.dangerSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
            .padding(16)
        }
    }

    private func summaryCard(_ goal: ProjectGoal, palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(gattoSymbol: statusIcon(goal.status))
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(statusColor(goal.status, palette: palette))
                    .frame(width: 42, height: 42)
                    .background(statusColor(goal.status, palette: palette).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(goalTitle(goal))
                        .font(font(17, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text(L10n.text("goal.status.\(goal.status.rawValue)"))
                        .font(font(11, weight: .medium))
                        .foregroundStyle(statusColor(goal.status, palette: palette))
                }
                Spacer()
                Text("\(Int(goal.progress * 100))%")
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.ink)
            }
            ProgressView(value: goal.progress)
                .tint(statusColor(goal.status, palette: palette))

            if goal.targetHeadSHA == nil {
                TextField(
                    L10n.text("goal.commit_message.placeholder"),
                    text: Binding(
                        get: { goal.commitMessage },
                        set: { model.updateSelectedProjectGoalCommitMessage($0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(font(11.5, weight: .regular))
                .padding(.horizontal, 11)
                .frame(height: 36)
                .background(palette.background.opacity(theme == .softGlass ? 0.35 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(palette.divider, lineWidth: 1)
                }
            }

            HStack(spacing: 8) {
                if canContinue(goal) {
                    Button(L10n.text("goal.action.continue")) {
                        Task { await model.continueSelectedProjectGoal() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(
                        model.activeProjectGoalID != nil
                            || model.activeOperation != nil
                            || model.isCodexRunning
                    )
                }

                if goal.lastActionFailure != nil {
                    Button(L10n.text("goal.action.agent_repair")) {
                        Task { await model.repairSelectedProjectGoalWithAgent() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!model.canRepairSelectedProjectGoalWithAgent)
                }

                if model.canPrepareSelectedReleaseWithAgent {
                    Button(L10n.text("goal.action.prepare_release")) {
                        model.prepareSelectedReleaseWithAgent()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                if model.canPublishSelectedProjectRelease {
                    Button(L10n.text("goal.action.publish_release")) {
                        showsReleasePublishConfirmation = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                if model.canInstallSelectedProjectRelease {
                    Button(L10n.text("goal.action.install_release")) {
                        showsReleaseInstallConfirmation = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                if let releaseURL = goal.releaseURL {
                    Button(L10n.text("goal.action.open_release")) {
                        inAppBrowserPage = InAppBrowserPage(url: releaseURL, persistent: true)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                if model.canMergeSelectedProjectGoal {
                    Button(L10n.text("goal.action.merge")) {
                        showsMergeConfirmation = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                if !goal.status.isTerminal {
                    Button(L10n.text("goal.action.cancel")) {
                        Task { await model.cancelSelectedProjectGoal() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.activeProjectGoalID == goal.id)
                }
                Spacer()
            }
        }
        .goalPanel(palette: palette, theme: theme)
    }

    private func stepTrack(_ goal: ProjectGoal, palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(goal.steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Image(gattoSymbol: stepIcon(step.kind))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(stepColor(step.status, palette: palette))
                            .frame(width: 32, height: 32)
                            .background(stepColor(step.status, palette: palette).opacity(0.12))
                            .clipShape(Circle())
                        if index < goal.steps.count - 1 {
                            Rectangle()
                                .fill(step.status.isSatisfied ? palette.success.opacity(0.45) : palette.divider)
                                .frame(width: 2, height: 34)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.text("goal.step.\(step.kind.rawValue)"))
                                .font(font(12, weight: .semibold))
                                .foregroundStyle(palette.ink)
                            Spacer()
                            Text(L10n.text("goal.step.status.\(step.status.rawValue)"))
                                .font(font(10, weight: .semibold))
                                .foregroundStyle(stepColor(step.status, palette: palette))
                        }
                        if let evidence = step.evidence, !evidence.isEmpty {
                            Text(evidence)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.subtleInk)
                        }
                        if let error = step.error, !error.isEmpty {
                            Text(error)
                                .font(font(10, weight: .regular))
                                .foregroundStyle(palette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 7)
                }
            }
        }
        .goalPanel(palette: palette, theme: theme)
    }

    private func metadataCard(_ goal: ProjectGoal, palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            metadataRow("goal.repository", value: goal.repositoryName, palette: palette)
            Rectangle().fill(palette.divider).frame(height: 1)
            metadataRow("goal.branch", value: goal.branchName, palette: palette)
            if let remote = goal.remoteFullName {
                Rectangle().fill(palette.divider).frame(height: 1)
                metadataRow("goal.remote", value: remote, palette: palette)
            }
            if let baseBranch = goal.baseBranch, goal.kind == .githubDelivery {
                Rectangle().fill(palette.divider).frame(height: 1)
                metadataRow("goal.base_branch", value: baseBranch, palette: palette)
            }
            if let number = goal.pullRequestNumber {
                Rectangle().fill(palette.divider).frame(height: 1)
                metadataRow("goal.pull_request", value: "#\(number)", palette: palette, monospaced: true)
            }
            if goal.repairAttemptCount > 0 {
                Rectangle().fill(palette.divider).frame(height: 1)
                metadataRow(
                    "goal.repair_attempts",
                    value: String(goal.repairAttemptCount),
                    palette: palette,
                    monospaced: true
                )
            }
            if let target = goal.targetHeadSHA {
                Rectangle().fill(palette.divider).frame(height: 1)
                metadataRow("goal.target_commit", value: String(target.prefix(12)), palette: palette, monospaced: true)
            }
            if let version = goal.releaseVersion {
                Rectangle().fill(palette.divider).frame(height: 1)
                metadataRow(
                    "goal.release.version",
                    value: version,
                    palette: palette,
                    monospaced: true
                )
            }
            if let build = goal.releaseBuildNumber {
                Rectangle().fill(palette.divider).frame(height: 1)
                metadataRow(
                    "goal.release.build",
                    value: build,
                    palette: palette,
                    monospaced: true
                )
            }
            if let tag = goal.releaseTag {
                Rectangle().fill(palette.divider).frame(height: 1)
                metadataRow("goal.release.tag", value: tag, palette: palette, monospaced: true)
            }
            if let installed = goal.installedApplicationVersion {
                Rectangle().fill(palette.divider).frame(height: 1)
                metadataRow(
                    "goal.release.installed",
                    value: installed + (goal.installedApplicationBuild.map { " (\($0))" } ?? ""),
                    palette: palette,
                    monospaced: true
                )
            }
        }
        .goalPanel(palette: palette, theme: theme)
    }

    private func metadataRow(
        _ key: String,
        value: String,
        palette: AppPalette,
        monospaced: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Text(L10n.text(key))
                .font(font(10.5, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            Spacer()
            Text(value)
                .font(monospaced ? .system(size: 10.5, weight: .medium, design: .monospaced) : font(10.5, weight: .medium))
                .foregroundStyle(palette.ink)
                .textSelection(.enabled)
        }
        .padding(.vertical, 10)
    }

    private func stepIcon(_ kind: ProjectGoalStepKind) -> String {
        switch kind {
        case .readme: "doc.richtext"
        case .translation: "globe"
        case .version: "curlybraces.square"
        case .changelog: "clock.arrow.circlepath"
        case .releasePipeline: "checkmark.shield"
        case .stageChanges: "square.stack.3d.up"
        case .commit: "checkmark.circle"
        case .push: "arrow.up.circle"
        case .pullRequest: "git.pull.request"
        case .review: "doc.text.magnifyingglass"
        case .actions: "checkmark.shield"
        case .artifact: "shippingbox"
        case .merge: "arrow.triangle.merge"
        case .releaseTag: "text.badge.plus"
        case .githubRelease: "arrow.up.forward.app"
        case .dmg: "shippingbox"
        case .updateFeed: "arrow.triangle.2.circlepath"
        case .localApplication: "arrow.down.app"
        }
    }

    private var goalCreationDisabled: Bool {
        model.activeProjectGoalID != nil
            || (model.snapshot?.changes.isEmpty == false
                && model.projectGoalCommitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func goalTitle(_ goal: ProjectGoal) -> String {
        switch goal.kind {
        case .deliverChanges: L10n.text("goal.delivery.title")
        case .githubDelivery: L10n.text("goal.github_delivery.title")
        case .completeRelease: L10n.text("goal.complete_release.title")
        }
    }

    private func canContinue(_ goal: ProjectGoal) -> Bool {
        guard !goal.status.isTerminal,
              goal.status != .waiting,
              let next = goal.nextStep,
              goal.step(next)?.status != .blocked else { return false }
        return [.stageChanges, .commit, .push, .pullRequest].contains(next)
    }

    private func actionsFailureCard(
        _ goal: ProjectGoal,
        failure: ProjectGoalActionFailure,
        palette: AppPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(gattoSymbol: "exclamationmark.triangle.fill")
                    .foregroundStyle(palette.danger)
                Text(L10n.text("goal.actions.failure"))
                    .font(font(12, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
                Text("#\(failure.runNumber)")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.subtleInk)
            }
            Text(failure.workflowName)
                .font(font(10.5, weight: .medium))
                .foregroundStyle(palette.ink)
            if let explanation = goal.step(.actions)?.error {
                Text(explanation)
                    .font(font(10.5, weight: .regular))
                    .foregroundStyle(palette.danger)
            }
            Text(failure.conclusion)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(palette.danger)
            if let log = failure.logExcerpt, !log.isEmpty {
                Text(log)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(palette.ink)
                    .textSelection(.enabled)
                    .lineLimit(14)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.background.opacity(theme == .softGlass ? 0.28 : 1))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            Button(L10n.text("goal.action.agent_repair")) {
                Task { await model.repairSelectedProjectGoalWithAgent() }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!model.canRepairSelectedProjectGoalWithAgent)
        }
        .goalPanel(palette: palette, theme: theme)
    }

    private func statusIcon(_ status: ProjectGoalStatus) -> String {
        switch status {
        case .ready: "play.circle"
        case .running: "arrow.triangle.2.circlepath"
        case .waiting: "clock.arrow.circlepath"
        case .blocked: "exclamationmark.triangle.fill"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    private func statusColor(_ status: ProjectGoalStatus, palette: AppPalette) -> Color {
        switch status {
        case .ready: palette.accent
        case .running: palette.accent
        case .waiting: palette.warning
        case .blocked: palette.danger
        case .completed: palette.success
        case .cancelled: palette.subtleInk
        }
    }

    private func stepColor(_ status: ProjectGoalStepStatus, palette: AppPalette) -> Color {
        switch status {
        case .pending: palette.subtleInk
        case .running: palette.accent
        case .waiting: palette.warning
        case .blocked: palette.danger
        case .completed: palette.success
        case .notRequired: palette.mutedInk
        }
    }

    private func font(_ size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: theme == .console ? .monospaced : .default)
    }
}

private extension View {
    func goalPanel(palette: AppPalette, theme: AppVisualTheme) -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme == .softGlass ? palette.surface.opacity(0.16) : palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(palette.divider, lineWidth: 1)
            }
    }
}
