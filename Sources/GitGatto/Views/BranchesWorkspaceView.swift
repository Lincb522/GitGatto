import SwiftUI

struct BranchesWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @State private var selectedTool: RepositoryTool = .branches

    var body: some View {
        let palette = AppPalette(colorScheme)
        GeometryReader { proxy in
            let navigatorWidth = min(400, max(320, proxy.size.width * 0.35))
            let content = HStack(spacing: panelSpacing) {
                RepositoryToolNavigator(model: model, selectedTool: $selectedTool)
                    .frame(width: navigatorWidth)
                    .modifier(ToolPanelModifier(theme: theme, elevated: true))
                RepositoryToolInspector(model: model, selectedTool: selectedTool)
                    .modifier(ToolPanelModifier(theme: theme, elevated: false))
            }
            .padding(contentPadding)

            if theme == .standard {
                content
                    .padding(0)
            } else {
                content
                    .background(palette.background)
            }
        }
        .task {
            model.refreshGitTools()
        }
    }

    private var theme: AppVisualTheme {
        AppVisualTheme.resolved(themeRaw)
    }

    private var panelSpacing: CGFloat {
        theme == .standard ? 0 : (theme == .console ? 8 : 10)
    }

    private var contentPadding: CGFloat {
        theme == .standard ? 0 : (theme == .console ? 8 : 10)
    }
}

private enum RepositoryTool: String, CaseIterable, Identifiable {
    case branches
    case tags
    case remotes
    case recovery

    var id: String {
        rawValue
    }

    var titleKey: String {
        switch self {
        case .branches: "git_tools.tab.branches"
        case .tags: "git_tools.tab.tags"
        case .remotes: "git_tools.tab.remotes"
        case .recovery: "git_tools.tab.recovery"
        }
    }

    var symbol: String {
        switch self {
        case .branches: "arrow.triangle.branch"
        case .tags: "tag"
        case .remotes: "globe"
        case .recovery: "clock.arrow.circlepath"
        }
    }
}

private struct ToolPanelModifier: ViewModifier {
    let theme: AppVisualTheme
    let elevated: Bool

    func body(content: Content) -> some View {
        switch theme {
        case .standard:
            content
        case .softGlass:
            content.appGlassPanel(cornerRadius: 14, elevated: elevated)
        case .emerald:
            content.emeraldSurface(elevated ? .elevated : .panel, cornerRadius: 16)
        case .folio:
            content.folioSurface(elevated ? .elevated : .panel, cornerRadius: 16)
        case .lumen:
            content.lumenSurface(elevated ? .chrome : .inset, cornerRadius: 14)
        case .console:
            content.appConsolePanel()
        }
    }
}

private struct RepositoryToolNavigator: View {
    @ObservedObject var model: WorkspaceViewModel
    @Binding var selectedTool: RepositoryTool
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingCreate = false

    private var branches: [BranchRecord] {
        filter(model.snapshot?.branches ?? []) { $0.name }
    }

    private var tags: [GitTagRecord] {
        filter(model.gitReferenceSnapshot.tags) { "\($0.name) \($0.subject) \($0.shortHash)" }
    }

    private var remotes: [GitRemoteRecord] {
        filter(model.gitReferenceSnapshot.remotes) { "\($0.name) \($0.fetchURL) \($0.pushURL)" }
    }

    private var reflog: [GitReflogRecord] {
        filter(model.gitReferenceSnapshot.reflog) { "\($0.selector) \($0.subject) \($0.shortHash)" }
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Text(L10n.text("git_tools.title"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    if model.isLoadingGitTools {
                        ProgressView().controlSize(.small)
                    }
                    Button {
                        model.refreshGitTools()
                    } label: {
                        Image(gattoSymbol: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.text("action.refresh"))
                    Button {
                        showingCreate = true
                    } label: {
                        Image(gattoSymbol: "plus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedTool == .recovery || model.activeOperation != nil)
                    .help(L10n.text("git_tools.action.create"))
                }

                    Picker("", selection: $selectedTool) {
                        ForEach(RepositoryTool.allCases) { tool in
                            Label {
                                Text(L10n.text(tool.titleKey))
                            } icon: {
                                Image(gattoSymbol: tool.symbol)
                            }
                            .tag(tool)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    Image(gattoSymbol: "magnifyingglass")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.subtleInk)
                    TextField(L10n.text("git_tools.search.placeholder"), text: $model.gitToolsSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                }
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(palette.divider, lineWidth: 1)
                }
            }
            .padding(14)
            .background(palette.surface)

            Rectangle().fill(palette.divider).frame(height: 1)

            if let error = model.gitToolsError {
                HStack(alignment: .top, spacing: 8) {
                    Image(gattoSymbol: "exclamationmark.triangle.fill")
                    Text(error).lineLimit(3)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(palette.warning)
                .padding(12)
                Rectangle().fill(palette.divider).frame(height: 1)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionLabel(titleKey: selectedTool.titleKey, count: itemCount)
                        .padding(.horizontal, 15)
                    switch selectedTool {
                    case .branches:
                        ForEach(branches) { branch in
                            BranchToolRow(branch: branch, isSelected: model.selectedBranch?.id == branch.id) {
                                model.selectedBranch = branch
                            }
                        }
                    case .tags:
                        ForEach(tags) { tag in
                            TagToolRow(tag: tag, isSelected: model.selectedTag?.id == tag.id) {
                                model.selectedTag = tag
                            }
                        }
                    case .remotes:
                        ForEach(remotes) { remote in
                            RemoteToolRow(remote: remote, isSelected: model.selectedRemote?.id == remote.id) {
                                model.selectedRemote = remote
                            }
                        }
                    case .recovery:
                        ForEach(reflog) { entry in
                            ReflogToolRow(entry: entry, isSelected: model.selectedReflogEntry?.id == entry.id) {
                                model.selectedReflogEntry = entry
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .overlay {
                if itemCount == 0, !model.isLoadingGitTools {
                    InspectorEmptyState(
                        image: selectedTool.symbol,
                        titleKey: "git_tools.empty.title",
                        bodyKey: "git_tools.empty.body"
                    )
                }
            }
        }
        .background(palette.surface)
        .sheet(isPresented: $showingCreate) {
            switch selectedTool {
            case .branches:
                CreateBranchSheet(model: model, isPresented: $showingCreate)
            case .tags:
                CreateTagSheet(model: model, isPresented: $showingCreate)
            case .remotes:
                EditRemoteSheet(model: model, remote: nil, isPresented: $showingCreate)
            case .recovery:
                EmptyView()
            }
        }
        .onChange(of: selectedTool) { _, _ in
            model.gitToolsSearchText = ""
        }
    }

    private var itemCount: Int {
        switch selectedTool {
        case .branches: branches.count
        case .tags: tags.count
        case .remotes: remotes.count
        case .recovery: reflog.count
        }
    }

    private func filter<T>(_ values: [T], text: (T) -> String) -> [T] {
        let query = model.gitToolsSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return values }
        return values.filter { text($0).localizedCaseInsensitiveContains(query) }
    }
}

private struct BranchToolRow: View {
    let branch: BranchRecord
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(gattoSymbol: "arrow.triangle.branch")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(branch.isCurrent ? palette.primary : palette.subtleInk)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(branch.name)
                        .font(.system(size: 12, weight: branch.isCurrent ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(branch.upstream ?? branch.shortHash)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if branch.isCurrent {
                    Text(L10n.text("branches.current"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.primary)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(palette.primarySoft)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .contentShape(Rectangle())
            .background(isSelected ? palette.primarySoft : (isHovering ? palette.raisedSurface.opacity(0.72) : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct TagToolRow: View {
    let tag: GitTagRecord
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(gattoSymbol: "tag")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tag.name)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(tag.subject.isEmpty ? tag.shortHash : tag.subject)
                        .font(.system(size: 9.5))
                        .foregroundStyle(palette.subtleInk)
                        .lineLimit(1)
                }
                Spacer()
                if tag.isAnnotated {
                    Text(L10n.text("git_tools.tag.annotated"))
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .contentShape(Rectangle())
            .background(isSelected ? palette.primarySoft : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

private struct RemoteToolRow: View {
    let remote: GitRemoteRecord
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(gattoSymbol: "globe")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.primary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(remote.name)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.ink)
                    Text(remote.fetchURL)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            .contentShape(Rectangle())
            .background(isSelected ? palette.primarySoft : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

private struct ReflogToolRow: View {
    let entry: GitReflogRecord
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(gattoSymbol: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.warning)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.subject)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Text(entry.shortHash)
                        Text(entry.selector)
                        Text(entry.createdAt.formatted(.relative(presentation: .named)))
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(palette.subtleInk)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            .contentShape(Rectangle())
            .background(isSelected ? palette.primarySoft : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

private struct RepositoryToolInspector: View {
    @ObservedObject var model: WorkspaceViewModel
    let selectedTool: RepositoryTool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(gattoSymbol: selectedTool.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.primary)
                Text(L10n.text(selectedTool.titleKey))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(palette.surface)
            Rectangle().fill(palette.divider).frame(height: 1)

            switch selectedTool {
            case .branches:
                BranchInspector(model: model, branch: model.selectedBranch)
            case .tags:
                TagInspector(model: model, tag: model.selectedTag)
            case .remotes:
                RemoteInspector(model: model, remote: model.selectedRemote)
            case .recovery:
                ReflogInspector(model: model, entry: model.selectedReflogEntry)
            }
        }
        .background(palette.background)
    }
}

private struct BranchInspector: View {
    @ObservedObject var model: WorkspaceViewModel
    let branch: BranchRecord?
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingRename = false
    @State private var showingUpstream = false
    @State private var showingDelete = false
    @State private var showingCleanup = false
    @State private var isConfirmingMerge = false
    @State private var isConfirmingRebase = false
    @State private var rename = ""
    @State private var upstream = ""

    var body: some View {
        let palette = AppPalette(colorScheme)
        if let branch {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        toolHero(symbol: "arrow.triangle.branch", color: branch.isCurrent ? palette.primary : palette.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(branch.name)
                                .font(.system(size: 19, weight: .semibold, design: .monospaced))
                                .foregroundStyle(palette.ink)
                            Text(branch.isCurrent ? L10n.text("branches.checked_out") : L10n.text("branches.inactive"))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(branch.isCurrent ? palette.primary : palette.mutedInk)
                        }
                        Spacer()
                        Menu {
                            Button(L10n.text("git_tools.branch.rename")) {
                                rename = branch.name
                                showingRename = true
                            }
                            Button(L10n.text("git_tools.branch.upstream")) {
                                upstream = branch.upstream ?? ""
                                showingUpstream = true
                            }
                            Divider()
                            Button(L10n.text("git_tools.branch.cleanup")) { showingCleanup = true }
                            if !branch.isCurrent {
                                Button(L10n.text("action.delete"), role: .destructive) { showingDelete = true }
                            }
                        } label: {
                            Label {
                                Text(L10n.text("action.more"))
                            } icon: {
                                Image(gattoSymbol: "slider.horizontal.3")
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    metadataCard(rows: [
                        ("branches.latest_commit", branch.shortHash, true),
                        ("branches.upstream", branch.upstream ?? L10n.text("branches.no_upstream"), branch.upstream != nil),
                        ("branches.status", branch.isCurrent ? L10n.text("branches.active") : L10n.text("branches.inactive"), false),
                    ])

                    if !branch.isCurrent {
                        HStack(spacing: 10) {
                            Button(L10n.text("branches.quick_switch")) {
                                Task { await model.switchBranch(to: branch.name) }
                            }
                            .buttonStyle(.borderedProminent)
                            Button(L10n.text("branches.action.merge")) { isConfirmingMerge = true }
                            Button(L10n.text("branches.action.rebase")) { isConfirmingRebase = true }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(model.activeOperation != nil || model.repositoryOperationState != nil)
            .sheet(isPresented: $showingRename) {
                SimpleValueSheet(
                    titleKey: "git_tools.branch.rename",
                    fieldKey: "git_tools.branch.name",
                    value: $rename,
                    isPresented: $showingRename
                ) {
                    await model.renameBranch(branch, to: rename)
                }
            }
            .sheet(isPresented: $showingUpstream) {
                SimpleValueSheet(
                    titleKey: "git_tools.branch.upstream",
                    fieldKey: "git_tools.branch.upstream_placeholder",
                    value: $upstream,
                    isPresented: $showingUpstream,
                    allowsEmpty: true
                ) {
                    await model.setUpstream(upstream.isEmpty ? nil : upstream, for: branch)
                }
            }
            .confirmationDialog(L10n.text("git_tools.branch.delete_confirm"), isPresented: $showingDelete) {
                Button(L10n.text("git_tools.branch.delete_safe"), role: .destructive) {
                    Task { await model.deleteBranch(branch, force: false) }
                }
                Button(L10n.text("git_tools.branch.delete_force"), role: .destructive) {
                    Task { await model.deleteBranch(branch, force: true) }
                }
                Button(L10n.text("action.cancel"), role: .cancel) {}
            }
            .confirmationDialog(L10n.text("git_tools.branch.cleanup_confirm"), isPresented: $showingCleanup) {
                Button(L10n.text("git_tools.branch.cleanup"), role: .destructive) {
                    Task { await model.cleanupMergedBranches() }
                }
                Button(L10n.text("action.cancel"), role: .cancel) {}
            }
            .confirmationDialog(L10n.format("branches.merge.confirm.title", branch.name), isPresented: $isConfirmingMerge) {
                Button(L10n.text("branches.action.merge")) { Task { await model.merge(branch: branch.name) } }
                Button(L10n.text("action.cancel"), role: .cancel) {}
            }
            .confirmationDialog(L10n.format("branches.rebase.confirm.title", branch.name), isPresented: $isConfirmingRebase) {
                Button(L10n.text("branches.action.rebase"), role: .destructive) {
                    Task { await model.rebaseCurrentBranch(onto: branch.name) }
                }
                Button(L10n.text("action.cancel"), role: .cancel) {}
            }
        } else {
            InspectorEmptyState(image: "arrow.triangle.branch", titleKey: "branches.empty.title", bodyKey: "branches.empty.body")
        }
    }

    private func toolHero(symbol: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.12))
            Image(gattoSymbol: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(color)
        }
        .frame(width: 50, height: 50)
    }

    private func metadataCard(rows: [(String, String, Bool)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                BranchMetadataRow(labelKey: row.0, value: row.1, monospaced: row.2)
                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
        .background(AppPalette(colorScheme).surface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(AppPalette(colorScheme).divider) }
    }
}

private struct TagInspector: View {
    @ObservedObject var model: WorkspaceViewModel
    let tag: GitTagRecord?
    @Environment(\.colorScheme) private var colorScheme
    @State private var remoteName = ""
    @State private var confirmingDelete = false
    @State private var confirmingRemoteDelete = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        if let tag {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12).fill(palette.accentSoft)
                            Image(gattoSymbol: "tag").font(.system(size: 20, weight: .semibold)).foregroundStyle(palette.accent)
                        }.frame(width: 50, height: 50)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(tag.name).font(.system(size: 19, weight: .semibold, design: .monospaced))
                            Text(tag.isAnnotated ? L10n.text("git_tools.tag.annotated") : L10n.text("git_tools.tag.lightweight"))
                                .font(.system(size: 11.5)).foregroundStyle(palette.mutedInk)
                        }
                        Spacer()
                    }
                    VStack(spacing: 0) {
                        BranchMetadataRow(labelKey: "git_tools.tag.commit", value: tag.shortHash, monospaced: true)
                        Divider()
                        BranchMetadataRow(labelKey: "git_tools.tag.subject", value: tag.subject.isEmpty ? "—" : tag.subject, monospaced: false)
                        Divider()
                        BranchMetadataRow(labelKey: "git_tools.tag.creator", value: tag.creator ?? "—", monospaced: false)
                    }
                    .background(palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay { RoundedRectangle(cornerRadius: 11).stroke(palette.divider) }

                    if !model.gitReferenceSnapshot.remotes.isEmpty {
                        HStack(spacing: 10) {
                            Picker(L10n.text("git_tools.remote.title"), selection: $remoteName) {
                                ForEach(model.gitReferenceSnapshot.remotes) { remote in
                                    Text(remote.name).tag(remote.name)
                                }
                            }
                            .frame(maxWidth: 220)
                            Button(L10n.text("git_tools.tag.push")) {
                                Task { await model.pushTag(tag, to: resolvedRemote) }
                            }
                            .buttonStyle(.borderedProminent)
                            Button(L10n.text("git_tools.tag.delete_remote"), role: .destructive) {
                                confirmingRemoteDelete = true
                            }
                        }
                    }
                    Button(L10n.text("git_tools.tag.delete_local"), role: .destructive) {
                        confirmingDelete = true
                    }
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(model.activeOperation != nil)
            .onAppear {
                if remoteName.isEmpty {
                    remoteName = model.gitReferenceSnapshot.remotes.first?.name ?? ""
                }
            }
            .confirmationDialog(L10n.text("git_tools.tag.delete_confirm"), isPresented: $confirmingDelete) {
                Button(L10n.text("action.delete"), role: .destructive) { Task { await model.deleteTag(tag) } }
                Button(L10n.text("action.cancel"), role: .cancel) {}
            }
            .confirmationDialog(L10n.text("git_tools.tag.delete_remote_confirm"), isPresented: $confirmingRemoteDelete) {
                Button(L10n.text("action.delete"), role: .destructive) {
                    Task { await model.deleteRemoteTag(tag, from: resolvedRemote) }
                }
                Button(L10n.text("action.cancel"), role: .cancel) {}
            }
        } else {
            InspectorEmptyState(image: "tag", titleKey: "git_tools.tag.empty", bodyKey: "git_tools.empty.body")
        }
    }

    private var resolvedRemote: String {
        remoteName.isEmpty ? model.gitReferenceSnapshot.remotes.first?.name ?? "" : remoteName
    }
}

private struct RemoteInspector: View {
    @ObservedObject var model: WorkspaceViewModel
    let remote: GitRemoteRecord?
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingEdit = false
    @State private var confirmingDelete = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        if let remote {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12).fill(palette.primarySoft)
                            Image(gattoSymbol: "globe").font(.system(size: 20, weight: .semibold)).foregroundStyle(palette.primary)
                        }.frame(width: 50, height: 50)
                        Text(remote.name).font(.system(size: 19, weight: .semibold, design: .monospaced))
                        Spacer()
                        Button(L10n.text("action.edit")) { showingEdit = true }
                    }
                    VStack(spacing: 0) {
                        BranchMetadataRow(labelKey: "git_tools.remote.fetch_url", value: remote.fetchURL, monospaced: true)
                        Divider()
                        BranchMetadataRow(labelKey: "git_tools.remote.push_url", value: remote.pushURL, monospaced: true)
                    }
                    .background(palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay { RoundedRectangle(cornerRadius: 11).stroke(palette.divider) }
                    HStack(spacing: 10) {
                        Button(L10n.text("git_tools.remote.fetch")) { Task { await model.fetchRemote(remote, prunes: false) } }
                            .buttonStyle(.borderedProminent)
                        Button(L10n.text("git_tools.remote.fetch_prune")) { Task { await model.fetchRemote(remote, prunes: true) } }
                        Button(L10n.text("git_tools.remote.test")) { Task { await model.testRemote(remote) } }
                        Button(L10n.text("action.delete"), role: .destructive) { confirmingDelete = true }
                    }
                }
                .padding(24)
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(model.activeOperation != nil)
            .sheet(isPresented: $showingEdit) {
                EditRemoteSheet(model: model, remote: remote, isPresented: $showingEdit)
            }
            .confirmationDialog(L10n.text("git_tools.remote.delete_confirm"), isPresented: $confirmingDelete) {
                Button(L10n.text("action.delete"), role: .destructive) { Task { await model.deleteRemote(remote) } }
                Button(L10n.text("action.cancel"), role: .cancel) {}
            }
        } else {
            InspectorEmptyState(image: "globe", titleKey: "git_tools.remote.empty", bodyKey: "git_tools.empty.body")
        }
    }
}

private struct ReflogInspector: View {
    @ObservedObject var model: WorkspaceViewModel
    let entry: GitReflogRecord?
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingRestore = false
    @State private var branchName = ""

    var body: some View {
        let palette = AppPalette(colorScheme)
        if let entry {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12).fill(palette.warning.opacity(0.12))
                            Image(gattoSymbol: "clock.arrow.circlepath").font(.system(size: 20, weight: .semibold)).foregroundStyle(palette.warning)
                        }.frame(width: 50, height: 50)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.subject).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                            Text(entry.selector).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.mutedInk)
                        }
                        Spacer()
                    }
                    VStack(spacing: 0) {
                        BranchMetadataRow(labelKey: "git_tools.reflog.commit", value: entry.shortHash, monospaced: true)
                        Divider()
                        BranchMetadataRow(labelKey: "git_tools.reflog.time", value: entry.createdAt.formatted(date: .abbreviated, time: .standard), monospaced: false)
                    }
                    .background(palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay { RoundedRectangle(cornerRadius: 11).stroke(palette.divider) }
                    Text(L10n.text("git_tools.reflog.restore_explanation"))
                        .font(.system(size: 11.5)).foregroundStyle(palette.mutedInk)
                    Button(L10n.text("git_tools.reflog.restore")) {
                        branchName = "recovered-\(entry.shortHash)"
                        showingRestore = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .sheet(isPresented: $showingRestore) {
                SimpleValueSheet(
                    titleKey: "git_tools.reflog.restore",
                    fieldKey: "git_tools.branch.name",
                    value: $branchName,
                    isPresented: $showingRestore
                ) {
                    await model.restoreReflogEntry(entry, as: branchName)
                }
            }
        } else {
            InspectorEmptyState(image: "clock.arrow.circlepath", titleKey: "git_tools.reflog.empty", bodyKey: "git_tools.empty.body")
        }
    }
}

private struct CreateBranchSheet: View {
    @ObservedObject var model: WorkspaceViewModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var startPoint = "HEAD"
    @State private var checksOut = true

    var body: some View {
        GitToolForm(titleKey: "git_tools.branch.create", isPresented: $isPresented, canSubmit: !name.isEmpty) {
            Form {
                TextField(L10n.text("git_tools.branch.name"), text: $name)
                TextField(L10n.text("git_tools.branch.start_point"), text: $startPoint)
                Toggle(L10n.text("git_tools.branch.checkout_after_create"), isOn: $checksOut)
            }
            .formStyle(.grouped)
        } action: {
            await model.createBranch(named: name, from: startPoint, checksOut: checksOut)
        }
    }
}

private struct CreateTagSheet: View {
    @ObservedObject var model: WorkspaceViewModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var revision = "HEAD"
    @State private var message = ""
    @State private var signed = false

    var body: some View {
        GitToolForm(titleKey: "git_tools.tag.create", isPresented: $isPresented, canSubmit: !name.isEmpty) {
            Form {
                TextField(L10n.text("git_tools.tag.name"), text: $name)
                TextField(L10n.text("git_tools.tag.revision"), text: $revision)
                TextField(L10n.text("git_tools.tag.message"), text: $message)
                Toggle(L10n.text("git_tools.tag.signed"), isOn: $signed)
            }
            .formStyle(.grouped)
        } action: {
            await model.createTag(named: name, revision: revision, message: message.isEmpty ? nil : message, signed: signed)
        }
    }
}

private struct EditRemoteSheet: View {
    @ObservedObject var model: WorkspaceViewModel
    let remote: GitRemoteRecord?
    @Binding var isPresented: Bool
    @State private var name: String
    @State private var fetchURL: String
    @State private var pushURL: String

    init(model: WorkspaceViewModel, remote: GitRemoteRecord?, isPresented: Binding<Bool>) {
        self.model = model
        self.remote = remote
        _isPresented = isPresented
        _name = State(initialValue: remote?.name ?? "")
        _fetchURL = State(initialValue: remote?.fetchURL ?? "")
        _pushURL = State(initialValue: remote?.pushURL ?? "")
    }

    var body: some View {
        GitToolForm(
            titleKey: remote == nil ? "git_tools.remote.add" : "git_tools.remote.edit",
            isPresented: $isPresented,
            canSubmit: !name.isEmpty && !fetchURL.isEmpty
        ) {
            Form {
                TextField(L10n.text("git_tools.remote.name"), text: $name)
                TextField(L10n.text("git_tools.remote.fetch_url"), text: $fetchURL)
                TextField(L10n.text("git_tools.remote.push_url"), text: $pushURL)
            }
            .formStyle(.grouped)
        } action: {
            if let remote {
                await model.updateRemote(remote, name: name, fetchURL: fetchURL, pushURL: pushURL.isEmpty ? fetchURL : pushURL)
            } else {
                await model.addRemote(named: name, fetchURL: fetchURL, pushURL: pushURL.isEmpty ? nil : pushURL)
            }
        }
    }
}

private struct SimpleValueSheet: View {
    let titleKey: String
    let fieldKey: String
    @Binding var value: String
    @Binding var isPresented: Bool
    var allowsEmpty = false
    let action: () async -> Void

    var body: some View {
        GitToolForm(titleKey: titleKey, isPresented: $isPresented, canSubmit: allowsEmpty || !value.isEmpty) {
            TextField(L10n.text(fieldKey), text: $value)
                .textFieldStyle(.roundedBorder)
                .padding(20)
        } action: { await action() }
    }
}

private struct GitToolForm<Content: View>: View {
    let titleKey: String
    @Binding var isPresented: Bool
    let canSubmit: Bool
    @ViewBuilder let content: Content
    let action: () async -> Void
    @State private var submitting = false

    init(
        titleKey: String,
        isPresented: Binding<Bool>,
        canSubmit: Bool,
        @ViewBuilder content: () -> Content,
        action: @escaping () async -> Void
    ) {
        self.titleKey = titleKey
        _isPresented = isPresented
        self.canSubmit = canSubmit
        self.content = content()
        self.action = action
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text(titleKey)).font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .padding(18)
            Divider()
            content
            Divider()
            HStack {
                Spacer()
                Button(L10n.text("action.cancel")) { isPresented = false }
                Button(L10n.text("action.confirm")) {
                    submitting = true
                    Task {
                        await action()
                        submitting = false
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || submitting)
            }
            .padding(16)
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct BranchMetadataRow: View {
    let labelKey: String
    let value: String
    let monospaced: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 14) {
            Text(L10n.text(labelKey))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.mutedInk)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: monospaced ? .monospaced : .default))
                .foregroundStyle(palette.ink)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
    }
}
