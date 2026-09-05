import SwiftUI

struct ChangesWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @AppStorage("workspace.changes.navigator.width") private var navigatorWidth = 300.0

    @ViewBuilder
    var body: some View {
        let palette = AppPalette(colorScheme)
        GeometryReader { proxy in
            if let operationState = model.repositoryOperationState {
                if AppVisualTheme.resolved(themeRaw) == .standard {
                    ConflictResolutionWorkspaceView(model: model, state: operationState)
                } else if AppVisualTheme.resolved(themeRaw) == .softGlass {
                    ConflictResolutionWorkspaceView(model: model, state: operationState)
                } else if AppVisualTheme.resolved(themeRaw) == .emerald {
                    ConflictResolutionWorkspaceView(model: model, state: operationState)
                } else if AppVisualTheme.resolved(themeRaw) == .folio {
                    ConflictResolutionWorkspaceView(model: model, state: operationState)
                } else {
                    ConflictResolutionWorkspaceView(model: model, state: operationState)
                        .appConsolePanel()
                        .padding(8)
                        .background(palette.background)
                }
            } else if AppVisualTheme.resolved(themeRaw) == .standard {
                HStack(spacing: 0) {
                    ChangeNavigator(model: model)
                        .frame(width: min(380, max(310, proxy.size.width * 0.36)))
                    Rectangle().fill(palette.divider).frame(width: 1)
                    DiffInspectorView(
                        change: model.selectedChange,
                        document: model.diffDocument,
                        previewURL: model.selectedChangePreviewURL
                    )
                }
            } else if AppVisualTheme.resolved(themeRaw) == .softGlass {
                HStack(spacing: 0) {
                    ChangeNavigator(model: model)
                        .frame(width: min(380, max(310, proxy.size.width * 0.36)))
                    Rectangle().fill(palette.divider).frame(width: 1)
                    DiffInspectorView(
                        change: model.selectedChange,
                        document: model.diffDocument,
                        previewURL: model.selectedChangePreviewURL
                    )
                }
            } else if AppVisualTheme.resolved(themeRaw) == .emerald {
                HorizontalResizableSplitView(
                    primaryWidth: Binding(
                        get: { proxy.size.width - navigatorWidth - 7 },
                        set: { navigatorWidth = proxy.size.width - $0 - 7 }
                    ),
                    minimumPrimaryWidth: 370,
                    maximumPrimaryWidth: max(370, proxy.size.width - 287),
                    minimumSecondaryWidth: 280,
                    separatorWidth: 7
                ) {
                    DiffInspectorView(change: model.selectedChange, document: model.diffDocument, previewURL: model.selectedChangePreviewURL)
                } secondary: {
                    ChangeNavigator(model: model, showsTitle: false)
                        .overlay(alignment: .leading) { Rectangle().fill(palette.divider).frame(width: 1) }
                }
            } else if AppVisualTheme.resolved(themeRaw) == .folio {
                folioWorkspace(palette: palette, width: proxy.size.width)
            } else if AppVisualTheme.resolved(themeRaw) == .console {
                HorizontalResizableSplitView(
                    primaryWidth: $navigatorWidth,
                    minimumPrimaryWidth: 270,
                    maximumPrimaryWidth: 380,
                    minimumSecondaryWidth: 365,
                    separatorWidth: 5
                ) {
                    ChangeNavigator(model: model, showsTitle: false)
                } secondary: {
                    DiffInspectorView(change: model.selectedChange, document: model.diffDocument, previewURL: model.selectedChangePreviewURL)
                }
            } else {
                HStack(spacing: 8) {
                    ChangeNavigator(model: model)
                        .frame(width: min(390, max(315, proxy.size.width * 0.35)))
                        .appConsolePanel()
                    DiffInspectorView(
                        change: model.selectedChange,
                        document: model.diffDocument,
                        previewURL: model.selectedChangePreviewURL
                    )
                        .appConsolePanel()
                }
                .padding(8)
                .background(palette.background)
            }
        }
    }
    private func folioWorkspace(palette: AppPalette, width: CGFloat) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    SearchField(text: $model.searchText, placeholderKey: "search.changes")
                        .frame(maxWidth: 280)
                    CountBadge(count: model.snapshot?.changes.count ?? 0, emphasized: false)
                    Spacer(minLength: 8)
                    Menu {
                        Button(L10n.text("action.stage_all")) {
                            Task { await model.stage(model.filteredChanges.filter { !$0.isStaged }) }
                        }
                        .disabled(model.filteredChanges.allSatisfy(\.isStaged))
                        Button(L10n.text("action.unstage_all")) {
                            Task { await model.unstage(model.filteredChanges.filter(\.isStaged)) }
                        }
                        .disabled(!model.filteredChanges.contains(where: \.isStaged))
                    } label: {
                        Color.clear.frame(width: 32, height: 32)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 32, height: 32)
                    .overlay {
                        GattoIcon(symbol: "ellipsis", size: 18)
                            .foregroundStyle(palette.mutedInk)
                            .allowsHitTesting(false)
                    }
                    .help(L10n.text("changes.title"))
                    .accessibilityLabel(L10n.text("changes.title"))
                    .disabled(model.activeOperation != nil)
                }
                if !model.filteredChanges.isEmpty {
                    ScrollViewReader { scroll in
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 8) {
                                ForEach(model.filteredChanges) { change in
                                    ChangeRow(model: model, change: change, isSelected: model.selectedChange?.id == change.id) {
                                        model.selectChange(change)
                                    } toggleStage: {
                                        Task {
                                            if change.isStaged { await model.unstage([change]) }
                                            else { await model.stage([change]) }
                                        }
                                    }
                                    .frame(width: 300)
                                    .help(change.path)
                                    .accessibilityAddTraits(model.selectedChange?.id == change.id ? .isSelected : [])
                                    .background(palette.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                    .accessibilityValue(L10n.text(change.isStaged ? "changes.staged_single" : "changes.unstaged_single"))
                                    .id(change.id)
                                }
                            }
                        }
                        .scrollIndicators(.visible)
                        .onChange(of: model.selectedChange?.id) { _, id in
                            if let id { scroll.scrollTo(id, anchor: .center) }
                        }
                    }
                    .frame(height: 58)
                }
            }
            .padding(.top, 8)

            HorizontalResizableSplitView(
                primaryWidth: Binding(
                    get: { width - navigatorWidth - 14 },
                    set: { navigatorWidth = width - $0 - 14 }
                ),
                minimumPrimaryWidth: 370,
                maximumPrimaryWidth: max(370, width - 254),
                minimumSecondaryWidth: 240,
                separatorWidth: 14
            ) {
                Group {
                    if model.snapshot?.changes.isEmpty == true {
                        ChangesEmptyState()
                    } else {
                        DiffInspectorView(change: model.selectedChange, document: model.diffDocument, previewURL: model.selectedChangePreviewURL)
                    }
                }
                .folioSurface(.panel, cornerRadius: 14)
            } secondary: {
                ScrollView {
                    CommitComposer(model: model, isInspector: true)
                }
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

}

private struct ChangeNavigator: View {
    @ObservedObject var model: WorkspaceViewModel
    var showsTitle = true
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue

    private var staged: [WorkingTreeChange] {
        model.filteredChanges.filter(\.isStaged)
    }

    private var unstaged: [WorkingTreeChange] {
        model.filteredChanges.filter { !$0.isStaged }
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                if showsTitle {
                    HStack {
                        Text(L10n.text("changes.title"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.ink)
                        Spacer()
                        CountBadge(count: model.snapshot?.changes.count ?? 0, emphasized: true)
                    }
                }
                SearchField(text: $model.searchText, placeholderKey: "search.changes")
            }
            .padding(.horizontal, 15)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)

            if model.snapshot?.changes.isEmpty == true {
                ChangesEmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        if !staged.isEmpty {
                            SectionLabel(
                                titleKey: "changes.staged",
                                count: staged.count,
                                actionTitleKey: "action.unstage_all",
                                isActionLoading: staged.contains { model.pendingStagePaths.contains($0.path) },
                                isActionDisabled: model.activeOperation != nil
                            ) {
                                Task { await model.unstage(staged) }
                            }
                            .padding(.horizontal, 15)

                            ForEach(staged) { change in
                                ChangeRow(
                                    model: model,
                                    change: change,
                                    isSelected: model.selectedChange?.id == change.id
                                ) {
                                    model.selectChange(change)
                                } toggleStage: {
                                    Task { await model.unstage([change]) }
                                }
                            }
                        }

                        if !unstaged.isEmpty {
                            SectionLabel(
                                titleKey: "changes.unstaged",
                                count: unstaged.count,
                                actionTitleKey: "action.stage_all",
                                isActionLoading: unstaged.contains { model.pendingStagePaths.contains($0.path) },
                                isActionDisabled: model.activeOperation != nil
                            ) {
                                Task { await model.stage(unstaged) }
                            }
                            .padding(.horizontal, 15)
                            .padding(.top, staged.isEmpty ? 0 : 8)

                            ForEach(unstaged) { change in
                                ChangeRow(
                                    model: model,
                                    change: change,
                                    isSelected: model.selectedChange?.id == change.id
                                ) {
                                    model.selectChange(change)
                                } toggleStage: {
                                    Task { await model.stage([change]) }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 10)
                }
            }

            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)

            CommitComposer(model: model)
        }
        .background(palette.surface)
    }
}

private struct ChangeRow: View {
    @ObservedObject var model: WorkspaceViewModel
    let change: WorkingTreeChange
    let isSelected: Bool
    let select: () -> Void
    let toggleStage: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var isConsole: Bool { AppStyleDefaults.theme == .console }
    @State private var isHovering = false
    @State private var isConfirmingDiscard = false

    private var fileName: String {
        URL(fileURLWithPath: change.path).lastPathComponent
    }

    private var parentPath: String {
        parentRelativePath.isEmpty ? L10n.text("path.repository_root") : parentRelativePath
    }

    private var parentRelativePath: String {
        (change.path as NSString).deletingLastPathComponent
    }

    private var fileExtension: String {
        (change.path as NSString).pathExtension
    }

    private var folderPaths: [String] {
        let components = parentRelativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return [] }
        return components.indices.reversed().map { index in
            components[...index].joined(separator: "/")
        }
    }

    private var isUpdatingStage: Bool {
        model.pendingStagePaths.contains(change.path)
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: select) {
            HStack(spacing: 10) {
                Text(change.primaryStatus.rawValue)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor(change.primaryStatus, palette: palette))
                    .frame(width: 22, height: 22)
                    .background(statusColor(change.primaryStatus, palette: palette).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(fileName)
                        .font(.system(size: isConsole ? 11.5 : 12.5, weight: isSelected ? .semibold : .medium, design: isConsole ? .monospaced : .default))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(AppStyleDefaults.theme == .folio ? L10n.text(change.isStaged ? "changes.staged_single" : "changes.unstaged_single") + " · " + parentPath : parentPath)
                        .font(.system(size: isConsole ? 9.5 : 10.5, design: isConsole ? .monospaced : .default))
                        .foregroundStyle(palette.subtleInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                if isHovering || isSelected || isUpdatingStage || AppStyleDefaults.theme == .folio {
                    Button(action: toggleStage) {
                        Group {
                            if isUpdatingStage {
                                GattoLoadingGlyph(size: 14)
                            } else {
                                Image(gattoSymbol: change.isStaged ? "minus" : "plus")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(palette.primary)
                            }
                        }
                        .frame(width: 24, height: 24)
                        .background(palette.raisedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isUpdatingStage)
                    .help(L10n.text(change.isStaged ? "action.unstage" : "action.stage"))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: isConsole ? 40 : 48)
            .contentShape(Rectangle())
            .background(isSelected ? palette.primarySoft : (isHovering ? palette.raisedSurface.opacity(0.75) : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button {
                toggleStage()
            } label: {
                GattoLabel(
                    L10n.text(change.isStaged ? "action.unstage" : "action.stage"),
                    systemImage: change.isStaged ? "minus.circle" : "plus.circle"
                )
            }
            .disabled(model.activeOperation != nil)

            Divider()

            Button(role: .destructive) {
                if model.appPreferences.confirmDiscardChanges {
                    isConfirmingDiscard = true
                } else {
                    Task { await model.discard(change) }
                }
            } label: {
                GattoLabel(L10n.text("action.discard_changes"), systemImage: "arrow.uturn.backward")
            }
            .disabled(model.activeOperation != nil)

            Divider()

            Button {
                Task { await model.ignore(change, scope: .file) }
            } label: {
                GattoLabel(L10n.text("action.ignore_file"), systemImage: "eye.slash")
            }
            .disabled(model.activeOperation != nil)

            Menu {
                ForEach(folderPaths, id: \.self) { folderPath in
                    Button(folderPath) {
                        Task { await model.ignore(change, scope: .folder(folderPath)) }
                    }
                }
            } label: {
                GattoLabel(L10n.text("action.ignore_folder"), systemImage: "folder.badge.minus")
            }
            .disabled(folderPaths.isEmpty || model.activeOperation != nil)

            Button {
                Task { await model.ignore(change, scope: .fileExtension) }
            } label: {
                GattoLabel(
                    L10n.format("action.ignore_extension", fileExtension),
                    systemImage: "doc.badge.minus"
                )
            }
            .disabled(fileExtension.isEmpty || model.activeOperation != nil)

            Divider()

            Button {
                model.copyAbsolutePath(for: change)
            } label: {
                GattoLabel(L10n.text("action.copy_path"), systemImage: "doc.on.doc")
            }

            Button {
                model.copyRelativePath(for: change)
            } label: {
                GattoLabel(L10n.text("action.copy_relative_path"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }

            Divider()

            Button {
                model.revealInFinder(change)
            } label: {
                GattoLabel(L10n.text("action.reveal_finder"), systemImage: "folder")
            }

            Button {
                model.openInXcode(change)
            } label: {
                GattoLabel(L10n.text("action.open_xcode"), systemImage: "hammer")
            }
            .disabled(!model.canOpenInXcode)

            Button {
                model.openWithDefaultApplication(change)
            } label: {
                GattoLabel(L10n.text("action.open_default"), systemImage: "arrow.up.forward.app")
            }
        }
        .confirmationDialog(
            L10n.text("discard.confirm.title"),
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button(L10n.text("discard.confirm.action"), role: .destructive) {
                Task { await model.discard(change) }
            }
            Button(L10n.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.format("discard.confirm.message", change.path))
        }
    }

    private func statusColor(_ status: GitFileStatus, palette: AppPalette) -> Color {
        switch status {
        case .added, .untracked: palette.success
        case .deleted: palette.danger
        case .renamed, .copied: palette.accent
        case .conflicted: palette.warning
        default: palette.primary
        }
    }
}

private struct CommitComposer: View {
    @ObservedObject var model: WorkspaceViewModel
    var isInspector = false
    @Environment(\.colorScheme) private var colorScheme

    private var canCommit: Bool {
        !model.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && model.snapshot?.stagedChanges.isEmpty == false
            && model.activeOperation == nil
    }

    private var canDraft: Bool {
        model.snapshot?.changes.isEmpty == false
            && model.codexAvailability.state == .available
            && !model.isCodexRunning
            && model.activeOperation == nil
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.text("commit.title"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.mutedInk)
                Spacer()
                Text(L10n.format("commit.staged_count", model.snapshot?.stagedChanges.count ?? 0))
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.subtleInk)
            }

            ZStack(alignment: .topLeading) {
                if model.commitMessage.isEmpty {
                    Text(L10n.text("commit.placeholder"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.subtleInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.commitMessage)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
            }
                .frame(height: isInspector ? 172 : 68)
                .background(palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.divider, lineWidth: 1)
                }

            if isInspector {
                VStack(alignment: .leading, spacing: 8) {
                    draftButton
                    draftDetail
                }
            } else if [.console, .emerald].contains(AppStyleDefaults.theme) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        draftButton.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 8)
                        draftDetail.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        draftButton
                        draftDetail
                    }
                }
            } else {
                HStack(spacing: 8) {
                    draftButton
                    Spacer()
                    draftDetail
                }
            }

            Button {
                Task { await model.commit() }
            } label: {
                SubmitMotionLabel(
                    title: L10n.text("action.commit"),
                    activeTitle: L10n.text("codex.status.committing"),
                    systemImage: "checkmark.circle.fill",
                    isActive: model.activeOperation == .commit,
                    completionID: model.notice?.message == L10n.text("notice.committed")
                        ? model.notice?.id
                        : nil,
                    shortcut: "⌘↩",
                    expandsWhenIdle: true
                )
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canCommit)
            .opacity(canCommit || model.activeOperation == .commit ? 1 : 0.45)
        }
        .padding(14)
        .background(palette.surface)
    }
    private var draftButton: some View {
        Button {
            model.draftCommitMessageForComposer()
        } label: {
            HStack(spacing: 7) {
                if model.isDraftingCommitMessage {
                    GattoLoadingGlyph(size: 16)
                } else {
                    Image(gattoSymbol: "sparkles")
                        .frame(width: 16, height: 16)
                }
                Text(L10n.text(model.isDraftingCommitMessage
                    ? "codex.status.drafting_commit"
                    : "commit.agent_draft"))
                    .lineLimit([AppVisualTheme.console, .emerald, .folio].contains(AppStyleDefaults.theme) ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11.5, weight: .semibold))
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(!canDraft)
    }

    private var draftDetail: some View {
        Text(L10n.text("commit.draft_detail.\(model.appPreferences.commitDraftDetail.rawValue)"))
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(AppPalette(colorScheme).subtleInk)
    }

}

private struct ChangesEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 10) {
            Spacer()
            Image(gattoSymbol: "checkmark.circle")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(palette.success)
            Text(L10n.text("changes.empty.title"))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text(L10n.text("changes.empty.body"))
                .font(.system(size: 11.5))
                .foregroundStyle(palette.mutedInk)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
