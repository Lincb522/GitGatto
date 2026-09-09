import SwiftUI

struct ProjectGoalComposerView: View {
    @ObservedObject var model: WorkspaceViewModel
    let onCreated: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var kind = ProjectGoalKind.deliverChanges
    @State private var message = ""
    @State private var intent = ""
    @State private var version = ""
    @State private var build = ""
    @State private var isCreating = false
    @State private var showsPlan = false
    @State private var showsBuild = false
    @State private var planningTask: Task<Void, Never>?
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case message, intent, version }

    init(
        model: WorkspaceViewModel,
        initialKind: ProjectGoalKind = .deliverChanges,
        onCreated: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.model = model
        self.onCreated = onCreated
        self.onCancel = onCancel
        _kind = State(initialValue: initialKind)
    }

    private var activeGoal: ProjectGoal? { model.currentRepositoryGoals.first { !$0.status.isTerminal } }
    private var busy: Bool {
        isCreating || model.activeProjectGoalID != nil || model.activeOperation != nil || model.isCodexRunning
    }
    private var steps: [ProjectGoalStepKind] {
        kind == .custom ? model.projectGoalCandidate?.stepKinds ?? [] : kind.stepKinds
    }
    private var valid: Bool {
        guard model.snapshot != nil, activeGoal == nil, !busy else { return false }
        switch kind {
        case .custom: return model.projectGoalCandidate != nil
        case .completeRelease:
            return ProjectReleaseInspector.buildNumber(for: version) != nil && !build.isEmpty && build.allSatisfy(\.isNumber)
        case .deliverChanges, .githubDelivery:
            return model.snapshot?.changes.isEmpty == true || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.text("goal.new")).font(.system(size: 18, weight: .semibold))
                    Spacer()
                    if !model.currentRepositoryGoals.isEmpty {
                        Button(L10n.text("action.cancel")) {
                            planningTask?.cancel()
                            onCancel()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(isCreating)
                        .keyboardShortcut(.cancelAction)
                    }
                }
                if let activeGoal, !isCreating {
                    Text(L10n.text("goal.workspace.one_active"))
                        .foregroundStyle(palette.subtleInk)
                    Button(activeGoal.displayTitle) {
                        model.selectProjectGoal(activeGoal)
                        onCreated()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    context(palette)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                        ForEach(ProjectGoalKind.templates, id: \.self) { option in
                            Button { kind = option } label: {
                                Text(L10n.text("goal.quick.\(option.rawValue)"))
                                    .fontWeight(kind == option ? .semibold : .regular)
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .background(kind == option ? palette.accentSoft : palette.raisedSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
                                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(kind == option ? palette.accent : palette.divider))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(kind == option ? .isSelected : [])
                        }
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("goals.template")
                    fields(palette)
                    if !steps.isEmpty {
                        DisclosureGroup(L10n.text("goal.workspace.plan"), isExpanded: $showsPlan) {
                            VStack(alignment: .leading, spacing: 12) {
                                if let candidate = model.projectGoalCandidate, kind == .custom {
                                    Text(candidate.title).fontWeight(.medium)
                                    Text(candidate.commitMessage).textSelection(.enabled)
                                    if let version = candidate.releaseVersion {
                                        Text("v\(version) · \(candidate.releaseBuildNumber ?? "")")
                                            .font(.system(size: 12, design: .monospaced))
                                    }
                                }
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), alignment: .leading)], alignment: .leading, spacing: 12) {
                                    ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                                        HStack(alignment: .top, spacing: 9) {
                                            Text("\(index + 1)").monospacedDigit().foregroundStyle(palette.subtleInk)
                                                .frame(width: 22, alignment: .trailing)
                                            Text(L10n.text("goal.step.\(step.rawValue)"))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 12)
                        }
                        .padding(16)
                        .background(palette.raisedSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.divider))
                    }
                    if kind != .custom || model.projectGoalCandidate != nil {
                        Text(L10n.text("goal.scope.\(kind == .custom ? (steps.contains(.releaseTag) ? "completeRelease" : steps.contains(.pullRequest) ? "githubDelivery" : "deliverChanges") : kind.rawValue)"))
                            .foregroundStyle(palette.subtleInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            isCreating = true
                            Task {
                                model.projectGoalCommitMessage = message
                                model.projectGoalReleaseVersion = version
                                model.projectGoalReleaseBuildNumber = build
                                let created: Bool
                                switch kind {
                                case .deliverChanges: created = await model.createProjectDeliveryGoal()
                                case .githubDelivery: created = await model.createGitHubDeliveryGoal()
                                case .completeRelease: created = await model.createCompleteReleaseGoal()
                                case .custom: created = await model.confirmCustomProjectGoalCandidate()
                                }
                                isCreating = false
                                if created, let id = model.selectedProjectGoal?.id {
                                    onCreated()
                                    await model.startProjectGoal(id: id)
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isCreating { ProgressView().controlSize(.small) }
                                Text(L10n.text("goal.workspace.start"))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!valid)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("goals.create")
                    }
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(palette.ink)
            .frame(maxWidth: 680, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .task(id: kind) {
            if message.isEmpty { message = model.commitMessage }
            focusedField = kind == .custom ? .intent : kind == .completeRelease ? .version : .message
            if kind == .completeRelease, version.isEmpty {
                await model.prepareProjectReleaseDraftIfNeeded()
                if version.isEmpty {
                    version = model.projectGoalReleaseVersion
                    build = model.projectGoalReleaseBuildNumber
                }
            }
        }
        .onChange(of: kind) { _, _ in model.cancelCustomProjectGoalCandidate() }
        .onChange(of: model.projectGoalCandidate) { _, candidate in
            if candidate != nil { showsPlan = true }
        }
        .onDisappear {
            planningTask?.cancel()
            model.cancelCustomProjectGoalCandidate()
        }
    }

    private func context(_ palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.snapshot?.rootURL.lastPathComponent ?? "—").fontWeight(.semibold)
            Text(model.snapshot?.branchName ?? "—")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.subtleInk)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func fields(_ palette: AppPalette) -> some View {
        switch kind {
        case .custom:
            VStack(alignment: .leading, spacing: 12) {
                TextField(L10n.text("goal.custom.placeholder"), text: $intent, axis: .vertical)
                    .lineLimit(3...8)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .intent)
                    .disabled(model.isPlanningProjectGoal || isCreating)
                    .onChange(of: intent) { _, _ in model.cancelCustomProjectGoalCandidate() }
                HStack(spacing: 10) {
                    Button {
                        model.projectGoalCustomIntent = intent
                        planningTask = Task { await model.proposeCustomProjectGoal() }
                    } label: {
                        HStack(spacing: 8) {
                            if model.isPlanningProjectGoal { ProgressView().controlSize(.small) }
                            Text(L10n.text(model.isPlanningProjectGoal ? "goal.custom.planning" : "goal.custom.action.generate"))
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(busy || intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.codexAvailability.state != .available)
                    if model.isPlanningProjectGoal {
                        Button(L10n.text("action.cancel")) { planningTask?.cancel() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                if model.codexAvailability.state != .available {
                    Text(L10n.text("goal.workspace.agent_unavailable")).foregroundStyle(palette.warning)
                }
                if let error = model.projectGoalPlanningError {
                    Text(error).foregroundStyle(palette.danger).textSelection(.enabled)
                }
            }
        case .completeRelease:
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent(L10n.text("goal.release.version")) {
                    TextField("1.2.3", text: $version)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .version)
                        .onChange(of: version) { oldValue, newValue in
                            if build.isEmpty || build == ProjectReleaseInspector.buildNumber(for: oldValue),
                               let suggested = ProjectReleaseInspector.buildNumber(for: newValue) { build = suggested }
                        }
                }
                DisclosureGroup(L10n.text("goal.release.build"), isExpanded: $showsBuild) {
                    TextField(L10n.text("goal.release.build.placeholder"), text: $build).textFieldStyle(.roundedBorder)
                        .padding(.top, 8)
                }
                if !version.isEmpty, ProjectReleaseInspector.buildNumber(for: version) == nil {
                    Text(ProjectGoalRuntimeError.invalidReleaseVersion.localizedDescription).foregroundStyle(palette.warning)
                }
                if !build.isEmpty, !build.allSatisfy(\.isNumber) {
                    Text(ProjectGoalRuntimeError.invalidReleaseBuildNumber.localizedDescription).foregroundStyle(palette.warning)
                }
            }
            .disabled(isCreating)
        case .deliverChanges, .githubDelivery:
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("goal.workspace.commit_message")).fontWeight(.medium)
                TextField(L10n.text("goal.commit_message.placeholder"), text: $message, axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .message)
                    .disabled(isCreating)
            }
        }
    }
}
