import SwiftUI

struct ProjectGoalDetailView: View {
    @ObservedObject var model: WorkspaceViewModel
    let goal: ProjectGoal
    @Environment(\.colorScheme) private var colorScheme
    @State private var message: String
    @State private var isSavingMessage = false
    @State private var expandedSteps = Set<ProjectGoalStepKind>()
    @State private var confirmation: Confirmation?
    @State private var browserPage: InAppBrowserPage?
    @State private var showsMetadata = false
    @State private var showsLog = true

    private enum Confirmation: String, Identifiable {
        case merge, publish, install, cancel
        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .merge: "goal.merge.confirm.title"
            case .publish: "goal.release.publish.confirm.title"
            case .install: "goal.release.install.confirm.title"
            case .cancel: "goal.workspace.cancel_title"
            }
        }
        var messageKey: String {
            switch self {
            case .merge: "goal.merge.confirm.message"
            case .publish: "goal.release.publish.confirm.message"
            case .install: "goal.release.install.confirm.message"
            case .cancel: "goal.workspace.cancel_note"
            }
        }
        var actionKey: String {
            switch self {
            case .merge: "goal.action.merge"
            case .publish: "goal.action.publish_release"
            case .install: "goal.action.install_release"
            case .cancel: "goal.action.cancel"
            }
        }
    }

    init(model: WorkspaceViewModel, goal: ProjectGoal) {
        self.model = model
        self.goal = goal
        _message = State(initialValue: goal.commitMessage)
        _expandedSteps = State(initialValue: Set(goal.steps.filter { !$0.status.isSatisfied && $0.kind == goal.nextStep }.map(\.kind)))
    }

    private var unsavedMessage: Bool { goal.canEditCommitMessage && message != goal.commitMessage }
    private var executing: Bool { model.activeProjectGoalID == goal.id && !isSavingMessage }

    var body: some View {
        let palette = AppPalette(colorScheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(palette)
                if !goal.status.isTerminal { nextStep(palette) }
                if goal.canEditCommitMessage { messageEditor(palette) }
                steps(palette)
                if let failure = goal.lastActionFailure { failureDetails(failure, palette) }
                metadata(palette)
            }
            .font(.system(size: 12))
            .foregroundStyle(palette.ink)
            .frame(maxWidth: 900, alignment: .leading)
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .onChange(of: goal.nextStep) { _, step in
            if let step { expandedSteps.insert(step) }
        }
        .onChange(of: goal.commitMessage) { oldValue, newValue in
            if message == oldValue { message = newValue }
        }
        .confirmationDialog(
            L10n.text(confirmation?.titleKey ?? "goal.title"),
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible, presenting: confirmation
        ) { action in
            Button(L10n.text(action.actionKey), role: action == .cancel || action == .merge ? .destructive : nil) {
                guard model.selectedProjectGoal?.id == goal.id else { return }
                Task {
                    switch action {
                    case .merge: await model.mergeSelectedProjectGoal()
                    case .publish: await model.publishSelectedProjectRelease()
                    case .install: await model.installSelectedProjectRelease()
                    case .cancel: await model.cancelSelectedProjectGoal()
                    }
                }
            }
            Button(L10n.text("action.cancel"), role: .cancel) {}
        } message: { action in
            Text(L10n.text(action.messageKey))
        }
        .sheet(item: $browserPage) { InAppBrowserSheet(url: $0.url, persistent: $0.persistent) }
    }

    private func header(_ palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.text(goal.kind.titleKey)).foregroundStyle(palette.subtleInk)
                    Text(goal.displayTitle).font(.system(size: 18, weight: .semibold))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Menu {
                    if let url = goal.pullRequestURL {
                        Button(L10n.text("goal.action.open_pr")) { browserPage = InAppBrowserPage(url: url, persistent: true) }
                    }
                    if let url = goal.releaseURL {
                        Button(L10n.text("goal.action.open_release")) { browserPage = InAppBrowserPage(url: url, persistent: true) }
                    }
                    Button(L10n.text("goal.workspace.metadata")) { showsMetadata = true }
                    if !goal.status.isTerminal {
                        Divider()
                        Button(L10n.text("goal.action.cancel"), role: .destructive) { confirmation = .cancel }
                            .disabled(model.activeProjectGoalID != nil || model.isCodexRunning)
                    }
                } label: { Text(L10n.text("goal.workspace.more")) }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(L10n.text("goal.workspace.more"))
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { status(palette); branch(palette); Spacer(minLength: 0); completion(palette) }
                VStack(alignment: .leading, spacing: 8) { status(palette); branch(palette); completion(palette) }
            }
            ProgressView(value: goal.progress)
                .tint(ProjectGoalAppearance.color(goal.status, palette))
                .accessibilityLabel(L10n.text("goal.workspace.steps"))
            if let intent = goal.intent, !intent.isEmpty {
                Text(intent).foregroundStyle(palette.subtleInk).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func status(_ palette: AppPalette) -> some View {
        GattoLabel(L10n.text("goal.status.\(goal.status.rawValue)"), systemImage: ProjectGoalAppearance.icon(goal.status))
            .foregroundStyle(ProjectGoalAppearance.color(goal.status, palette))
    }

    private func branch(_ palette: AppPalette) -> some View {
        GattoLabel(goal.branchName, systemImage: "arrow.triangle.branch")
            .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.subtleInk)
            .lineLimit(2)
    }

    private func completion(_ palette: AppPalette) -> some View {
        Text(L10n.format("goal.workspace.completed_count", goal.satisfiedStepCount, goal.steps.count))
            .monospacedDigit().foregroundStyle(palette.subtleInk)
    }

    private func nextStep(_ palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 9) {
                if executing { ProgressView().controlSize(.small) }
                Text(L10n.text(executing ? "goal.workspace.executing" : "goal.workspace.next"))
                    .foregroundStyle(palette.subtleInk)
                if let next = goal.nextStep {
                    Text(L10n.text("goal.step.\(next.rawValue)")).fontWeight(.semibold)
                }
            }
            if let error = goal.lastError, !error.isEmpty {
                Text(error).foregroundStyle(palette.danger).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else if goal.status == .waiting {
                Text(L10n.text("goal.workspace.waiting")).foregroundStyle(palette.subtleInk)
            }
            if let url = goal.pullRequestURL {
                Button(L10n.text("goal.action.open_pr")) {
                    browserPage = InAppBrowserPage(url: url, persistent: true)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            if let action = goal.nextAction {
                Button(L10n.text(action.titleKey)) { perform(action) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.canPerformProjectGoalAction(action) || unsavedMessage)
                    .accessibilityIdentifier("goals.nextAction")
                if unsavedMessage {
                    Text(L10n.text("goal.workspace.save_first")).foregroundStyle(palette.warning)
                } else if action.requiresAgent, model.codexAvailability.state != .available {
                    Text(L10n.text("goal.workspace.agent_unavailable")).foregroundStyle(palette.warning)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(palette.raisedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.divider))
    }

    private func messageEditor(_ palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("goal.workspace.commit_message")).fontWeight(.semibold)
            TextField(L10n.text("goal.commit_message.placeholder"), text: $message, axis: .vertical)
                .lineLimit(2...6).textFieldStyle(.roundedBorder)
                .disabled(model.activeProjectGoalID == goal.id || model.isCodexRunning)
                .accessibilityIdentifier("goals.commitMessage")
            if unsavedMessage {
                HStack {
                    Button {
                        isSavingMessage = true
                        Task {
                            defer { isSavingMessage = false }
                            if await model.updateSelectedProjectGoalCommitMessage(message),
                               let saved = model.projectGoals.first(where: { $0.id == goal.id }) {
                                message = saved.commitMessage
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isSavingMessage { ProgressView().controlSize(.small) }
                            Text(L10n.text("goal.workspace.save"))
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.activeProjectGoalID != nil || model.activeOperation != nil || model.isCodexRunning || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(L10n.text("action.cancel")) { message = goal.commitMessage }
                        .buttonStyle(SecondaryButtonStyle()).disabled(model.activeProjectGoalID == goal.id)
                }
            }
        }
    }

    private func steps(_ palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("goal.workspace.steps")).font(.system(size: 13, weight: .semibold)).padding(.bottom, 12)
            ForEach(Array(goal.steps.enumerated()), id: \.element.id) { index, step in
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedSteps.contains(step.kind) },
                    set: { if $0 { expandedSteps.insert(step.kind) } else { expandedSteps.remove(step.kind) } }
                )) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let evidence = step.evidence, !evidence.isEmpty {
                            Text(evidence).foregroundStyle(palette.subtleInk).textSelection(.enabled)
                        }
                        if let error = step.error, !error.isEmpty {
                            Text(error).foregroundStyle(palette.danger).textSelection(.enabled)
                        }
                        if step.evidence?.isEmpty != false, step.error?.isEmpty != false {
                            Text(L10n.text(step.status == .notRequired ? "goal.step.status.notRequired" : "goal.workspace.no_evidence")).foregroundStyle(palette.subtleInk)
                        }
                    }
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            stepTitle(step, index, palette)
                            Spacer(minLength: 8)
                            stepStatus(step, palette)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            stepTitle(step, index, palette)
                            stepStatus(step, palette)
                        }
                    }
                    .padding(.vertical, 11)
                }
                if index < goal.steps.count - 1 { Divider().overlay(palette.divider) }
            }
        }
    }

    private func stepTitle(_ step: ProjectGoalStep, _ index: Int, _ palette: AppPalette) -> some View {
        HStack(spacing: 10) {
            if step.status.isSatisfied {
                Image(gattoSymbol: "checkmark.circle").foregroundStyle(palette.success).frame(width: 22)
                    .accessibilityHidden(true)
            } else {
                Text("\(index + 1)").monospacedDigit().foregroundStyle(palette.subtleInk).frame(width: 22)
            }
            Text(L10n.text("goal.step.\(step.kind.rawValue)"))
                .fontWeight(goal.nextStep == step.kind ? .semibold : .regular)
        }
    }

    private func stepStatus(_ step: ProjectGoalStep, _ palette: AppPalette) -> some View {
        Text(L10n.text("goal.step.status.\(step.status.rawValue)"))
            .font(.system(size: 11))
            .foregroundStyle(step.status == .blocked ? palette.danger : step.status == .waiting ? palette.warning : palette.subtleInk)
    }

    private func failureDetails(_ failure: ProjectGoalActionFailure, _ palette: AppPalette) -> some View {
        DisclosureGroup(isExpanded: $showsLog) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(failure.workflowName) · #\(failure.runNumber) · \(failure.conclusion)")
                if let log = failure.logExcerpt, !log.isEmpty {
                    Text(log).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
        } label: { Text(L10n.text("goal.actions.failure")).fontWeight(.semibold) }
    }

    private func metadata(_ palette: AppPalette) -> some View {
        DisclosureGroup(isExpanded: $showsMetadata) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), alignment: .leading)], alignment: .leading, spacing: 16) {
                metadataValue("goal.repository", goal.repositoryName, palette)
                metadataValue("goal.branch", goal.branchName, palette)
                metadataValue("goal.workspace.created", goal.createdAt.formatted(.dateTime.locale(L10n.locale).year().month().day().hour().minute()), palette)
                metadataValue("goal.remote", goal.remoteFullName, palette)
                metadataValue("goal.base_branch", goal.baseBranch, palette)
                metadataValue("goal.pull_request", goal.pullRequestNumber.map { "#\($0)" }, palette)
                metadataValue("goal.target_commit", goal.targetHeadSHA, palette)
                metadataValue("goal.release.version", goal.releaseVersion, palette)
                metadataValue("goal.release.build", goal.releaseBuildNumber, palette)
                metadataValue("goal.release.tag", goal.releaseTag, palette)
                metadataValue("goal.release.installed", goal.installedApplicationVersion.map { $0 + (goal.installedApplicationBuild.map { " (\($0))" } ?? "") }, palette)
                if goal.repairAttemptCount > 0 { metadataValue("goal.repair_attempts", String(goal.repairAttemptCount), palette) }
            }
            .padding(.vertical, 14)
        } label: { Text(L10n.text("goal.workspace.metadata")).fontWeight(.semibold) }
    }

    @ViewBuilder
    private func metadataValue(_ key: String, _ value: String?, _ palette: AppPalette) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text(key)).foregroundStyle(palette.subtleInk)
                Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func perform(_ action: ProjectGoalAction) {
        guard model.selectedProjectGoal?.id == goal.id else { return }
        switch action {
        case .continueDelivery: Task { await model.continueSelectedProjectGoal() }
        case .repair: Task { await model.repairSelectedProjectGoalWithAgent() }
        case .prepareRelease: model.prepareSelectedReleaseWithAgent()
        case .publish: confirmation = .publish
        case .install: confirmation = .install
        case .merge: confirmation = .merge
        case .refresh: Task { await model.refreshProjectGoals() }
        }
    }
}
