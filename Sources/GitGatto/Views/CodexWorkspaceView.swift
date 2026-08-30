import SwiftUI

struct CodexWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsComposerSkills = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            header(palette)
            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)

            if model.codexAvailability.state == .unavailable {
                unavailableState(palette)
            } else {
                conversation(palette)
                composer(palette)
            }
        }
        .background(palette.background)
#if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.environment["GITGATTO_COMPOSER_TOOLS_PREVIEW"] == "1" {
                showsComposerSkills = true
            }
        }
#endif
    }

    private func header(_ palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(L10n.text("ai.title"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text(model.projectAIConfiguration.localizedName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.primary)
                    CodexAvailabilityBadge(availability: model.codexAvailability)
                }
                Text(scopeText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.subtleInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Menu {
                ForEach(GitAgentSkill.allCases) { skill in
                    Button {
                        model.runGitAgentSkill(skill)
                    } label: {
                        GattoLabel(L10n.text(skill.titleKey), systemImage: skill.systemImage)
                    }
                    .disabled(
                        model.codexAvailability.state != .available
                            || model.isCodexRunning
                            || model.snapshot == nil
                    )
                }
            } label: {
                GattoLabel(L10n.text("codex.action.skills"), systemImage: "square.grid.2x2")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            CodexModeControl(selection: $model.codexRunMode)

            ToolbarIconButton(
                systemName: "gearshape",
                helpKey: "settings.agent.title"
            ) {
                openSettings()
            }

            ToolbarIconButton(
                systemName: "trash",
                helpKey: "codex.action.clear",
                isDisabled: model.codexMessages.isEmpty || model.isCodexRunning
            ) {
                model.clearCodexConversation()
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 68)
        .background(palette.surface)
    }

    private var scopeText: String {
        guard let snapshot = model.snapshot else { return L10n.text("codex.scope") }
        return L10n.format(
            "codex.scope.repository",
            snapshot.rootURL.lastPathComponent,
            snapshot.branchName,
            snapshot.stagedChanges.count,
            snapshot.unstagedChanges.count
        )
    }

    private func conversation(_ palette: AppPalette) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if model.codexMessages.isEmpty && !model.isCodexRunning {
                        CodexEmptyState(model: model)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 56)
                    } else {
                        ForEach(model.codexMessages) { message in
                            CodexMessageRow(
                                message: message,
                                showsCommitActions: model.codexCommitDraft?.messageID == message.id,
                                automaticallyStagedCount: model.codexCommitDraft?.messageID == message.id
                                    ? model.codexCommitDraft?.automaticallyStagedCount ?? 0
                                    : 0,
                                canCommit: model.canCommitCodexDraft,
                                canCommitAndPush: model.canCommitAndPushCodexDraft,
                                canRewrite: model.canRewriteCodexCommitDraft,
                                activeCommitOperation: model.activeOperation,
                                commitCompletionID: model.notice?.message == L10n.text("notice.committed")
                                    ? model.notice?.id
                                    : nil,
                                commitPushCompletionID: model.notice?.message == L10n.text("notice.committed_pushed")
                                    ? model.notice?.id
                                    : nil,
                                rewrite: model.rewriteCodexCommitDraft,
                                commit: {
                                    Task { await model.commitCodexDraft() }
                                },
                                commitAndPush: {
                                    Task { await model.commitAndPushCodexDraft() }
                                }
                            )
                                .id(message.id)
                        }
                    }

                    if model.isCodexRunning {
                        HStack(spacing: 9) {
                            ProgressView()
                                .controlSize(.small)
                            Text(model.codexActivity ?? L10n.text("codex.status.running"))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(palette.mutedInk)
                            Spacer()
                        }
                        .id("codex-running")
                    } else if let error = model.codexError {
                        HStack(alignment: .top, spacing: 9) {
                            Image(gattoSymbol: "exclamationmark.triangle.fill")
                                .foregroundStyle(palette.danger)
                            Text(error)
                                .font(.system(size: 12.5))
                                .foregroundStyle(palette.ink)
                            Spacer()
                        }
                        .padding(12)
                        .background(palette.dangerSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .id("codex-error")
                    } else if let activity = model.codexActivity, !model.codexMessages.isEmpty {
                        Text(activity)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.subtleInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("codex-activity")
                    }
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.codexMessages.count) {
                if let id = model.codexMessages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: model.isCodexRunning) {
                if model.isCodexRunning {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("codex-running", anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func composer(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)

            if showsComposerSkills {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(GitAgentSkill.allCases) { skill in
                            Button {
                                showsComposerSkills = false
                                model.runGitAgentSkill(skill)
                            } label: {
                                GattoLabel(L10n.text(skill.titleKey), systemImage: skill.systemImage)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                }
                .frame(maxWidth: 808)
                .frame(maxWidth: .infinity)
                .background(palette.surface)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 12) {
                ComposerToolsButton(
                    isExpanded: showsComposerSkills,
                    isDisabled: model.codexAvailability.state != .available
                        || model.snapshot == nil
                        || model.isCodexRunning
                ) {
                    withAnimation(
                        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)
                    ) {
                        showsComposerSkills.toggle()
                    }
                }

                ZStack(alignment: .topLeading) {
                    if model.codexPrompt.isEmpty {
                        Text(L10n.text("codex.composer.placeholder"))
                            .font(.system(size: 13))
                            .foregroundStyle(palette.subtleInk)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $model.codexPrompt)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.ink)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(minHeight: 64, maxHeight: 108)
                        .disabled(model.isPromptTranslating)
                }
                .background(palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(palette.divider, lineWidth: 1)
                }

                if model.isPromptTranslating {
                    Button {} label: {
                        DocumentTranslationActionLabel(
                            title: L10n.text("codex.action.translate"),
                            activeTitle: L10n.text("codex.status.translating"),
                            isActive: true,
                            completionID: model.promptTranslationCompletionID
                        )
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(true)
                } else {
                    MotionLabelMenu(
                        accessibilityLabel: L10n.text("codex.action.translate"),
                        isDisabled: !model.canTranslatePrompt
                    ) {
                        ForEach(CodexTranslationTarget.allCases) { target in
                            Button(L10n.text("codex.translate.\(target.rawValue)")) {
                                model.codexTranslationTarget = target
                                model.translateCodexPrompt()
                            }
                        }
                    } label: {
                        DocumentTranslationActionLabel(
                            title: L10n.text("codex.action.translate"),
                            activeTitle: L10n.text("codex.status.translating"),
                            isActive: false,
                            completionID: model.promptTranslationCompletionID,
                            showsInitialCompletion: true
                        )
                        .font(.system(size: 11.5, weight: .semibold))
                    }
                }

                if model.isCodexRunning {
                    Button {
                        model.cancelCodex()
                    } label: {
                        HStack(spacing: 7) {
                            GattoLoadingGlyph(size: 16)
                            Text(L10n.text("codex.status.writing"))
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .help(L10n.text("codex.action.cancel"))
                } else {
                    Button {
                        model.runCodex()
                    } label: {
                        GattoLabel(L10n.text("codex.action.run"), systemImage: "sparkles")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.canRunCodex)
                    .opacity(model.canRunCodex ? 1 : 0.48)
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, promptStatus == nil ? 16 : 6)
            .frame(maxWidth: .infinity)
            .background(palette.surface)

            if let promptStatus {
                HStack(spacing: 7) {
                    Image(gattoSymbol: model.promptTranslationError == nil ? "checkmark.circle" : "exclamationmark.triangle.fill")
                    Text(promptStatus)
                        .lineLimit(2)
                    Spacer()
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(model.promptTranslationError == nil ? palette.subtleInk : palette.danger)
                .frame(maxWidth: 760)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .background(palette.surface)
            }
        }
    }

    private var promptStatus: String? {
        model.promptTranslationError ?? model.promptTranslationActivity
    }

    private func unavailableState(_ palette: AppPalette) -> some View {
        VStack(spacing: 14) {
            Image(gattoSymbol: "terminal")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            Text(L10n.text("ai.unavailable.title"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text(L10n.text("ai.unavailable.body"))
                .font(.system(size: 12.5))
                .foregroundStyle(palette.mutedInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
            HStack(spacing: 8) {
                Button(L10n.text("ai.settings.open")) {
                    openSettings()
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(L10n.text("codex.action.retry")) {
                    model.retryCodexProbe()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CodexAvailabilityBadge: View {
    let availability: CodexAvailability
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 5) {
            ConnectivityMotionGlyph(state: motionState, size: 14)
            Text(label)
                .lineLimit(1)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(palette.mutedInk)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(palette.raisedSurface)
        .clipShape(Capsule())
        .overlay { Capsule().stroke(palette.divider, lineWidth: 1) }
    }

    private var label: String {
        switch availability.state {
        case .checking:
            L10n.text("codex.status.checking")
        case .available:
            availability.version ?? L10n.text("codex.status.available")
        case .unavailable:
            L10n.text("codex.status.unavailable")
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

private struct CodexModeControl: View {
    @Binding var selection: CodexRunMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 2) {
            modeButton(.analyze, image: "eye")
            modeButton(.edit, image: "pencil")
        }
        .padding(3)
        .background(palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.divider, lineWidth: 1)
        }
    }

    private func modeButton(_ mode: CodexRunMode, image: String) -> some View {
        let palette = AppPalette(colorScheme)
        let isSelected = selection == mode
        return Button {
            selection = mode
        } label: {
            GattoLabel(L10n.text("codex.mode.\(mode.rawValue)"), systemImage: image)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isSelected ? palette.primary : palette.mutedInk)
                .padding(.horizontal, 10)
                .frame(height: 27)
                .background(isSelected ? palette.primarySoft : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(L10n.text("codex.mode.\(mode.rawValue).help"))
    }
}

private struct CodexEmptyState: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(palette.accentSoft)
                    .frame(width: 58, height: 58)
                Image(gattoSymbol: "sparkles")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
            VStack(spacing: 6) {
                Text(L10n.text("codex.empty.title"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text(L10n.text("codex.empty.body"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.mutedInk)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                quickAction(.explainChanges, image: "doc.text.magnifyingglass")
                quickAction(.reviewStaged, image: "checkmark.seal")
                quickAction(.draftCommit, image: "text.badge.plus")
            }
        }
    }

    private func quickAction(_ action: CodexQuickAction, image: String) -> some View {
        Button {
            model.runCodexQuickAction(action)
        } label: {
            GattoLabel(L10n.text("codex.quick.\(action.rawValue)"), systemImage: image)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 31)
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(model.codexAvailability.state != .available || model.snapshot == nil)
    }
}

private struct CodexMessageRow: View {
    let message: CodexMessage
    let showsCommitActions: Bool
    let automaticallyStagedCount: Int
    let canCommit: Bool
    let canCommitAndPush: Bool
    let canRewrite: Bool
    let activeCommitOperation: OperationKind?
    let commitCompletionID: UUID?
    let commitPushCompletionID: UUID?
    let rewrite: () -> Void
    let commit: () -> Void
    let commitAndPush: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsOperationEvents = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                Image(gattoSymbol: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 26, height: 26)
                    .background(palette.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Spacer(minLength: 56)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(displayText)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, message.role == .user ? 13 : 0)
                    .padding(.vertical, message.role == .user ? 10 : 3)
                    .background(message.role == .user ? palette.primarySoft : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(maxWidth: message.role == .user ? 560 : .infinity, alignment: .leading)

                if let operation = message.operation {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            if !operation.events.isEmpty {
                                withAnimation(.easeOut(duration: 0.16)) {
                                    showsOperationEvents.toggle()
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(gattoSymbol: operation.mode == .edit ? "pencil" : "eye")
                                Text(L10n.text("codex.operation.title"))
                                Text("·")
                                Text(L10n.text("codex.mode.\(operation.mode.rawValue)"))
                                if operation.commandCount > 0 || operation.fileChangeCount > 0 {
                                    Text("·")
                                    Text(
                                        L10n.format(
                                            "codex.operation.summary",
                                            operation.commandCount,
                                            operation.fileChangeCount
                                        )
                                    )
                                }
                                Text("·")
                                Text(operation.completedAt, style: .time)
                                if !operation.events.isEmpty {
                                    Image(gattoSymbol: "chevron.right")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .rotationEffect(.degrees(showsOperationEvents ? 90 : 0))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showsOperationEvents {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(Array(operation.events.enumerated()), id: \.offset) { _, event in
                                    HStack(alignment: .top, spacing: 7) {
                                        Image(gattoSymbol: event.kind == .command ? "terminal" : "doc.badge.ellipsis")
                                            .frame(width: 13)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(
                                                L10n.text(
                                                    event.kind == .command
                                                        ? "codex.operation.command"
                                                        : "codex.operation.file_change"
                                                )
                                            )
                                            .font(.system(size: 9.5, weight: .semibold))
                                            Text(event.summary)
                                                .font(.system(size: 10.5, design: .monospaced))
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.raisedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(palette.divider, lineWidth: 1)
                            }
                        }
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
                }

                if message.role == .assistant, showsCommitActions {
                    VStack(alignment: .leading, spacing: 9) {
                        if automaticallyStagedCount > 0 {
                            GattoLabel(
                                L10n.format("codex.draft.auto_staged", automaticallyStagedCount),
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.success)
                        }

                        HStack(spacing: 8) {
                            Button(action: commit) {
                                SubmitMotionLabel(
                                    title: L10n.text("action.commit"),
                                    activeTitle: L10n.text("codex.status.committing"),
                                    systemImage: "checkmark.circle.fill",
                                    isActive: activeCommitOperation == .commit,
                                    completionID: commitCompletionID
                                )
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!canCommit)
                            .opacity(canCommit ? 1 : 0.48)

                            Button(action: commitAndPush) {
                                SubmitMotionLabel(
                                    title: L10n.text("codex.action.commit_push"),
                                    activeTitle: L10n.text("sync.progress.commit_push"),
                                    systemImage: "arrow.up.circle",
                                    isActive: activeCommitOperation == .commitAndPush,
                                    completionID: commitPushCompletionID
                                )
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(!canCommitAndPush)
                            .opacity(canCommitAndPush ? 1 : 0.48)

                            Button(action: rewrite) {
                                GattoLabel(L10n.text("codex.action.rewrite"), systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(!canRewrite || activeCommitOperation != nil)
                        }
                    }
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var displayText: AttributedString {
        let text = message.role == .assistant
            ? CodexResponseFormatter.clean(message.text)
            : message.text
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
