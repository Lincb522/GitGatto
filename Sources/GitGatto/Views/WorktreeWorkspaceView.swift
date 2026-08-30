import SwiftUI

struct WorktreeWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @State private var confirmsRemoval = false

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }

    var body: some View {
        let palette = AppPalette(colorScheme)
        Group {
            if theme == .emerald {
                VStack(spacing: 10) {
                    commandBar(palette)
                        .emeraldSurface(.elevated, cornerRadius: 16)
                    GeometryReader { proxy in
                        let collectionWidth = min(max(292, proxy.size.width * 0.36), 390)
                        HStack(spacing: 10) {
                            collection(palette)
                                .frame(width: collectionWidth)
                                .emeraldSurface(.elevated, cornerRadius: 16)
                            inspector(palette)
                                .emeraldSurface(.panel, cornerRadius: 16)
                        }
                    }
                }
                .padding(10)
            } else if theme == .folio {
                VStack(spacing: 10) {
                    commandBar(palette)
                        .folioSurface(.elevated, cornerRadius: 16)
                    GeometryReader { proxy in
                        let collectionWidth = min(max(292, proxy.size.width * 0.36), 390)
                        HStack(spacing: 10) {
                            collection(palette)
                                .frame(width: collectionWidth)
                                .folioSurface(.elevated, cornerRadius: 16)
                            inspector(palette)
                                .folioSurface(.panel, cornerRadius: 16)
                        }
                    }
                }
                .padding(10)
            } else {
                VStack(spacing: 0) {
                    commandBar(palette)
                    Rectangle().fill(palette.divider).frame(height: 1)
                    GeometryReader { proxy in
                        let collectionWidth = min(max(292, proxy.size.width * 0.36), 390)
                        HStack(spacing: 0) {
                            collection(palette).frame(width: collectionWidth)
                            Rectangle().fill(palette.divider).frame(width: 1)
                            inspector(palette)
                        }
                    }
                }
            }
        }
        .background(theme == .softGlass ? Color.clear : palette.background)
        .confirmationDialog(
            L10n.text("worktree.remove.confirm.title"),
            isPresented: $confirmsRemoval,
            titleVisibility: .visible
        ) {
            Button(L10n.text("worktree.action.remove"), role: .destructive) {
                Task { await model.removeSelectedWorktree(force: false) }
            }
            Button(L10n.text("worktree.action.force_remove"), role: .destructive) {
                Task { await model.removeSelectedWorktree(force: true) }
            }
        }
    }

    private func commandBar(_ palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Text(L10n.text("worktree.title"))
                    .font(font(size: 15, weight: .semibold))
                    .foregroundStyle(palette.ink)
                CountBadge(count: model.worktrees.count)
            }

            Spacer(minLength: 12)

            HStack(spacing: 7) {
                TextField(L10n.text("worktree.branch.placeholder"), text: $model.worktreeBranchName)
                    .textFieldStyle(.plain)
                    .font(font(size: 11.5, weight: .medium))
                    .frame(width: 170)
                Rectangle().fill(palette.divider).frame(width: 1, height: 18)
                TextField(L10n.text("worktree.start_point.placeholder"), text: $model.worktreeStartPoint)
                    .textFieldStyle(.plain)
                    .font(font(size: 11.5, weight: .medium))
                    .frame(width: 92)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(palette.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous)
                    .stroke(palette.divider, lineWidth: 1)
            }

            Button {
                model.chooseWorktreeDestinationAndCreate()
            } label: {
                if model.activeWorktreeOperation == .create {
                    ProgressView().controlSize(.small)
                } else {
                    GattoLabel(L10n.text("worktree.action.create"), systemImage: "plus")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(
                model.worktreeBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.activeWorktreeOperation != nil
            )

            ToolbarIconButton(
                systemName: "arrow.clockwise",
                helpKey: "action.refresh",
                isActive: model.activeWorktreeOperation == .refresh,
                isDisabled: model.activeWorktreeOperation != nil
            ) {
                model.refreshWorktrees()
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .background(theme == .softGlass ? palette.surface.opacity(0.16) : palette.surface)
    }

    private func collection(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("worktree.collection.title"))
                    .font(font(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.mutedInk)
                Spacer()
                if model.worktrees.contains(where: { model.worktreeAgentRuns[$0.id]?.state == .running }) {
                    GattoLabel(L10n.text("worktree.agent.running_short"), systemImage: "sparkles")
                        .font(font(size: 9.5, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 42)

            Rectangle().fill(palette.divider).frame(height: 1)

            if model.worktrees.isEmpty {
                VStack(spacing: 9) {
                    Image(gattoSymbol: "arrow.triangle.branch")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(palette.subtleInk)
                    Text(L10n.text("worktree.empty"))
                        .font(font(size: 12, weight: .medium))
                        .foregroundStyle(palette.mutedInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: theme == .console ? 2 : 4) {
                        ForEach(model.worktrees) { worktree in
                            WorktreeRow(
                                worktree: worktree,
                                run: model.worktreeAgentRuns[worktree.id],
                                selected: model.selectedWorktree?.id == worktree.id,
                                theme: theme
                            ) {
                                model.selectWorktree(worktree)
                            }
                            .contextMenu {
                                Button(L10n.text("worktree.action.open")) {
                                    model.selectWorktree(worktree)
                                    model.openSelectedWorktree()
                                }
                                Button(L10n.text("worktree.action.reveal")) {
                                    model.selectWorktree(worktree)
                                    model.revealSelectedWorktree()
                                }
                                if !worktree.isMain {
                                    Divider()
                                    Button(L10n.text("worktree.action.remove"), role: .destructive) {
                                        model.selectWorktree(worktree)
                                        confirmsRemoval = true
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }

            if let error = model.worktreeError {
                Rectangle().fill(palette.divider).frame(height: 1)
                GattoLabel(error, systemImage: "exclamationmark.triangle.fill")
                    .font(font(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.danger)
                    .textSelection(.enabled)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.dangerSoft)
            }
        }
        .background(theme == .softGlass ? palette.sidebar.opacity(0.16) : palette.sidebar)
    }

    @ViewBuilder
    private func inspector(_ palette: AppPalette) -> some View {
        if let worktree = model.selectedWorktree {
            VStack(spacing: 0) {
                worktreeHeader(worktree, palette: palette)
                Rectangle().fill(palette.divider).frame(height: 1)
                agentWorkspace(worktree, palette: palette)
            }
        } else {
            VStack(spacing: 9) {
                Image(gattoSymbol: "rectangle.split.2x1")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
                Text(L10n.text("worktree.selection.empty"))
                    .font(font(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.mutedInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func worktreeHeader(_ worktree: GitWorktreeRecord, palette: AppPalette) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: theme == .console ? 4 : 9, style: .continuous)
                        .fill(worktree.isMain ? palette.primarySoft : palette.accentSoft)
                    Image(gattoSymbol: worktree.isMain ? "house.fill" : "arrow.triangle.branch")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(worktree.isMain ? palette.primary : palette.accent)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(worktree.branch ?? L10n.text("worktree.detached"))
                        .font(font(size: 15, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(worktree.path.path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)

                Button(L10n.text("worktree.action.open")) { model.openSelectedWorktree() }
                    .buttonStyle(SecondaryButtonStyle())
                Button(L10n.text("worktree.action.reveal")) { model.revealSelectedWorktree() }
                    .buttonStyle(SecondaryButtonStyle())
                if !worktree.isMain {
                    Button {
                        confirmsRemoval = true
                    } label: {
                        Image(gattoSymbol: "trash")
                            .foregroundStyle(palette.danger)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.activeWorktreeOperation != nil)
                    .help(L10n.text("worktree.action.remove"))
                }
            }

            HStack(spacing: 14) {
                WorktreeMetric(icon: "number", value: worktree.shortHash, color: palette.mutedInk)
                WorktreeMetric(icon: "square.stack.3d.up", value: L10n.format("worktree.changes", worktree.changesCount), color: worktree.changesCount > 0 ? palette.warning : palette.mutedInk)
                WorktreeMetric(icon: "arrow.up", value: "\(worktree.aheadCount)", color: palette.mutedInk)
                WorktreeMetric(icon: "arrow.down", value: "\(worktree.behindCount)", color: palette.mutedInk)
                if worktree.isLocked {
                    WorktreeMetric(icon: "lock.fill", value: L10n.text("worktree.locked"), color: palette.warning)
                }
                if worktree.isPrunable {
                    WorktreeMetric(icon: "exclamationmark.triangle", value: L10n.text("worktree.prunable"), color: palette.danger)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(theme == .softGlass ? palette.surface.opacity(0.14) : palette.surface)
    }

    private func agentWorkspace(_ worktree: GitWorktreeRecord, palette: AppPalette) -> some View {
        let run = model.worktreeAgentRuns[worktree.id]
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(gattoSymbol: "sparkles")
                    .foregroundStyle(palette.accent)
                Text(L10n.text("worktree.agent.title"))
                    .font(font(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink)
                if let run {
                    WorktreeAgentStateBadge(state: run.state, theme: theme)
                }
                Spacer()
                Picker("", selection: $model.worktreeAgentMode) {
                    Text(L10n.text("codex.mode.analyze")).tag(CodexRunMode.analyze)
                    Text(L10n.text("codex.mode.edit")).tag(CodexRunMode.edit)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 154)
                .disabled(run?.state == .running)
            }
            .padding(.horizontal, 16)
            .frame(height: 46)

            Rectangle().fill(palette.divider).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let run {
                        WorktreeAgentResult(run: run, theme: theme)
                    } else {
                        Text(L10n.text("worktree.agent.empty"))
                            .font(font(size: 12, weight: .medium))
                            .foregroundStyle(palette.mutedInk)
                            .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
                    }
                }
                .padding(16)
            }

            Rectangle().fill(palette.divider).frame(height: 1)

            VStack(spacing: 9) {
                TextEditor(text: $model.worktreeAgentPrompt)
                    .font(font(size: 12, weight: .regular))
                    .foregroundStyle(palette.ink)
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(minHeight: 74, maxHeight: 104)
                    .background(palette.raisedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous)
                            .stroke(palette.divider, lineWidth: 1)
                    }
                    .disabled(run?.state == .running)

                HStack {
                    Text(worktree.path.lastPathComponent)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                        .lineLimit(1)
                    Spacer()
                    if run?.state == .running {
                        Button(L10n.text("worktree.agent.stop")) {
                            model.cancelWorktreeAgent(worktree)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    } else {
                        Button {
                            model.runWorktreeAgent()
                        } label: {
                            GattoLabel(L10n.text("worktree.agent.run"), systemImage: "paperplane.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(model.worktreeAgentPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(14)
            .background(theme == .softGlass ? palette.surface.opacity(0.12) : palette.surface)
        }
    }

    private func font(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: theme == .console ? .monospaced : .default)
    }
}

private struct WorktreeRow: View {
    let worktree: GitWorktreeRecord
    let run: GitWorktreeAgentRun?
    let selected: Bool
    let theme: AppVisualTheme
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(gattoSymbol: worktree.isMain ? "house.fill" : "arrow.triangle.branch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? palette.primary : palette.mutedInk)
                        .frame(width: 17)
                    Text(worktree.branch ?? L10n.text("worktree.detached"))
                        .font(.system(size: 11.5, weight: .semibold, design: theme == .console ? .monospaced : .default))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let run {
                        WorktreeAgentDot(state: run.state)
                    }
                }
                HStack(spacing: 8) {
                    Text(worktree.path.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    if worktree.changesCount > 0 {
                        GattoLabel("\(worktree.changesCount)", systemImage: "circle.fill")
                            .foregroundStyle(palette.warning)
                    }
                    if worktree.aheadCount > 0 { Text("↑\(worktree.aheadCount)") }
                    if worktree.behindCount > 0 { Text("↓\(worktree.behindCount)") }
                }
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.subtleInk)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(selected ? palette.primarySoft : (hovering ? palette.raisedSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(selected ? palette.primary : Color.clear)
                    .frame(width: theme == .console ? 2 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct WorktreeMetric: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        GattoLabel(value, systemImage: icon)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
    }
}

private struct WorktreeAgentDot: View {
    let state: GitWorktreeAgentState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        Circle()
            .fill(color(palette))
            .frame(width: 7, height: 7)
            .accessibilityLabel(L10n.text("worktree.agent.state.\(state.key)"))
    }

    private func color(_ palette: AppPalette) -> Color {
        switch state {
        case .running: palette.accent
        case .completed: palette.success
        case .failed: palette.danger
        case .cancelled: palette.subtleInk
        }
    }
}

private struct WorktreeAgentStateBadge: View {
    let state: GitWorktreeAgentState
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 5) {
            if state == .running { ConsoleBreathingLight(isBusy: true) }
            Text(L10n.text("worktree.agent.state.\(state.key)"))
        }
        .font(.system(size: 9.5, weight: .semibold, design: theme == .console ? .monospaced : .default))
        .foregroundStyle(color(palette))
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(background(palette))
        .clipShape(Capsule())
    }

    private func color(_ palette: AppPalette) -> Color {
        switch state {
        case .running: palette.warning
        case .completed: palette.success
        case .failed: palette.danger
        case .cancelled: palette.mutedInk
        }
    }

    private func background(_ palette: AppPalette) -> Color {
        switch state {
        case .running: palette.warningSoft
        case .completed: palette.successSoft
        case .failed: palette.dangerSoft
        case .cancelled: palette.raisedSurface
        }
    }
}

private struct WorktreeAgentResult: View {
    let run: GitWorktreeAgentRun
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("worktree.agent.request"))
                    .font(.system(size: 10, weight: .semibold, design: theme == .console ? .monospaced : .default))
                    .foregroundStyle(palette.subtleInk)
                Text(run.prompt)
                    .font(.system(size: 12.5, weight: .medium, design: theme == .console ? .monospaced : .default))
                    .foregroundStyle(palette.ink)
                    .textSelection(.enabled)
            }

            if run.state == .running {
                HStack(spacing: 8) {
                    ConsoleBreathingLight(isBusy: true)
                    Text(L10n.text("worktree.agent.running"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.mutedInk)
                }
                .padding(.vertical, 12)
            } else if let response = run.response {
                Text(attributed(response))
                    .font(.system(size: 12.5, design: theme == .console ? .monospaced : .default))
                    .foregroundStyle(palette.ink)
                    .textSelection(.enabled)
            } else if let error = run.error {
                GattoLabel(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.danger)
                    .textSelection(.enabled)
            }

            if let operation = run.operation {
                HStack(spacing: 12) {
                    GattoLabel(L10n.format("worktree.agent.commands", operation.commandCount), systemImage: "terminal")
                    GattoLabel(L10n.format("worktree.agent.files", operation.fileChangeCount), systemImage: "doc.badge.gearshape")
                    Spacer()
                    Text(operation.completedAt.formatted(date: .omitted, time: .shortened))
                }
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.subtleInk)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attributed(_ value: String) -> AttributedString {
        (try? AttributedString(markdown: value)) ?? AttributedString(value)
    }
}

private extension GitWorktreeAgentState {
    var key: String {
        switch self {
        case .running: "running"
        case .completed: "completed"
        case .failed: "failed"
        case .cancelled: "cancelled"
        }
    }
}
