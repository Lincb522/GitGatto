import AppKit
import SwiftUI

struct HistoryWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue

    @ViewBuilder
    var body: some View {
        let palette = AppPalette(colorScheme)
        let selectedNode = model.commitGraph.nodes.first { $0.hash == model.selectedCommit?.hash }
        GeometryReader { proxy in
            if AppVisualTheme.resolved(themeRaw) == .standard {
                HStack(spacing: 0) {
                    CommitNavigator(model: model)
                        .frame(width: min(480, max(350, proxy.size.width * 0.44)))
                    Rectangle().fill(palette.divider).frame(width: 1)
                    CommitInspector(
                        model: model,
                        node: selectedNode
                    )
                }
            } else if AppVisualTheme.resolved(themeRaw) == .softGlass {
                HStack(spacing: 10) {
                    CommitNavigator(model: model)
                        .frame(width: min(470, max(350, proxy.size.width * 0.44)))
                        .appGlassPanel(cornerRadius: 14, elevated: false)
                    CommitInspector(
                        model: model,
                        node: selectedNode
                    )
                        .appGlassPanel(cornerRadius: 14, elevated: false)
                }
                .padding(10)
            } else if AppVisualTheme.resolved(themeRaw) == .emerald {
                HStack(spacing: 10) {
                    CommitNavigator(model: model)
                        .frame(width: min(470, max(350, proxy.size.width * 0.44)))
                        .emeraldSurface(.elevated, cornerRadius: 16)
                    CommitInspector(model: model, node: selectedNode)
                        .emeraldSurface(.panel, cornerRadius: 16)
                }
                .padding(10)
            } else if AppVisualTheme.resolved(themeRaw) == .folio {
                HStack(spacing: 10) {
                    CommitNavigator(model: model)
                        .frame(width: min(470, max(350, proxy.size.width * 0.44)))
                        .folioSurface(.elevated, cornerRadius: 16)
                    CommitInspector(model: model, node: selectedNode)
                        .folioSurface(.panel, cornerRadius: 16)
                }
                .padding(10)
            } else {
                HStack(spacing: 8) {
                    CommitNavigator(model: model)
                        .frame(width: min(480, max(350, proxy.size.width * 0.43)))
                        .appConsolePanel()
                    CommitInspector(
                        model: model,
                        node: selectedNode
                    )
                        .appConsolePanel()
                }
                .padding(8)
                .background(palette.background)
            }
        }
    }
}

private struct CommitNavigator: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingComparison = false
    @State private var showingReorder = false
    @State private var showingCommitSearch = false
    @StateObject private var commitSearchModel = GitCommitSearchViewModel()

    private var reorderableCommits: [CommitRecord] {
        guard let snapshot = model.snapshot else { return [] }
        let count = snapshot.upstreamName == nil
            ? max(0, snapshot.commits.count - 1)
            : min(snapshot.aheadCount, snapshot.commits.count)
        return Array(snapshot.commits.prefix(count).reversed())
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            VStack(spacing: 11) {
                HStack {
                    HStack(spacing: 9) {
                        Image(gattoSymbol: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.primary)
                            .frame(width: 28, height: 28)
                            .background(palette.primarySoft)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text(L10n.text("history.title"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.ink)
                    }
                    Spacer()
                    Button {
                        showingCommitSearch = true
                    } label: {
                        Label {
                            Text(L10n.text("commit_search.title"))
                        } icon: {
                            Image(gattoSymbol: "magnifyingglass")
                        }
                    }
                    .buttonStyle(.borderless)
                    Button {
                        model.refreshGitTools()
                        showingComparison = true
                    } label: {
                        Label {
                            Text(L10n.text("git_tools.compare.action"))
                        } icon: {
                            Image(gattoSymbol: "arrow.left.arrow.right")
                        }
                    }
                    .buttonStyle(.borderless)
                    if reorderableCommits.count >= 2 {
                        Button {
                            showingReorder = true
                        } label: {
                            Label {
                                Text(L10n.text("git_tools.commit.reorder"))
                            } icon: {
                                Image(gattoSymbol: "arrow.up.arrow.down")
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    CountBadge(count: model.commitGraph.nodes.count, emphasized: false)
                }
                SearchField(text: $model.searchText, placeholderKey: "search.history")
            }
            .padding(.horizontal, 15)
            .padding(.top, 13)
            .padding(.bottom, 11)

            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)

            if model.filteredCommitGraphNodes.isEmpty {
                InspectorEmptyState(
                    image: "clock.arrow.circlepath",
                    titleKey: "history.empty.title",
                    bodyKey: "history.empty.body"
                )
            } else {
                CommitGraphList(
                    nodes: model.filteredCommitGraphNodes,
                    laneCount: model.commitGraph.laneCount,
                    showsConnections: model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    selectedHash: model.selectedCommit?.hash
                ) { node in
                    model.selectGraphCommit(node)
                }
            }
        }
        .background(palette.surface)
        .sheet(isPresented: $showingComparison) {
            ReferenceComparisonSheet(model: model, isPresented: $showingComparison)
        }
        .sheet(isPresented: $showingReorder) {
            ReorderCommitsSheet(
                model: model,
                commits: reorderableCommits,
                isPresented: $showingReorder
            )
        }
        .sheet(isPresented: $showingCommitSearch) {
            GitCommitSearchSheet(
                searchModel: commitSearchModel,
                repositoryURL: model.snapshot?.rootURL,
                selectCommit: { model.selectCommit($0) }
            )
            .frame(minWidth: 880, minHeight: 660)
        }
        .onReceive(NotificationCenter.default.publisher(for: .gitGattoShowCommitSearch)) { _ in
            showingCommitSearch = true
        }
    }
}

private struct CommitGraphList: View {
    let nodes: [CommitGraphNode]
    let laneCount: Int
    let showsConnections: Bool
    let selectedHash: String?
    let select: (CommitGraphNode) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let rowHeight: CGFloat = 66
    private let laneWidth: CGFloat = 17
    private let graphInset: CGFloat = 16

    private var graphWidth: CGFloat {
        min(126, max(48, graphInset * 2 + CGFloat(max(1, laneCount)) * laneWidth))
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        ScrollView {
            ZStack(alignment: .topLeading) {
                if showsConnections {
                    CommitGraphEdges(
                        nodes: nodes,
                        rowHeight: rowHeight,
                        laneWidth: laneWidth,
                        graphInset: graphInset,
                        palette: palette
                    )
                }
                LazyVStack(spacing: 0) {
                    ForEach(nodes) { node in
                        CommitGraphRow(
                            node: node,
                            graphWidth: graphWidth,
                            laneWidth: laneWidth,
                            graphInset: graphInset,
                            isSelected: selectedHash == node.hash,
                            action: { select(node) }
                        )
                        .frame(height: rowHeight)
                    }
                }
            }
            .frame(height: CGFloat(nodes.count) * rowHeight, alignment: .top)
        }
    }
}

private struct CommitGraphEdges: View {
    let nodes: [CommitGraphNode]
    let rowHeight: CGFloat
    let laneWidth: CGFloat
    let graphInset: CGFloat
    let palette: AppPalette

    var body: some View {
        Canvas { context, _ in
            let positions = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.hash, $0.offset) })
            let lanes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.hash, $0.lane) })
            for (row, node) in nodes.enumerated() {
                let start = point(lane: node.lane, row: row)
                for parentHash in node.parentHashes {
                    guard let parentRow = positions[parentHash], let parentLane = lanes[parentHash] else { continue }
                    let end = point(lane: parentLane, row: parentRow)
                    let middleY = (start.y + end.y) / 2
                    var path = Path()
                    path.move(to: start)
                    path.addCurve(
                        to: end,
                        control1: CGPoint(x: start.x, y: middleY),
                        control2: CGPoint(x: end.x, y: middleY)
                    )
                    context.stroke(
                        path,
                        with: .color(color(for: parentLane)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func point(lane: Int, row: Int) -> CGPoint {
        CGPoint(
            x: graphInset + CGFloat(lane) * laneWidth + laneWidth / 2,
            y: CGFloat(row) * rowHeight + rowHeight / 2
        )
    }

    private func color(for lane: Int) -> Color {
        switch lane % 4 {
        case 0: palette.primary
        case 1: palette.accent
        case 2: palette.success
        default: palette.warning
        }
    }
}

private struct CommitGraphRow: View {
    let node: CommitGraphNode
    let graphWidth: CGFloat
    let laneWidth: CGFloat
    let graphInset: CGFloat
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Circle()
                        .fill(isSelected ? palette.primary : palette.surface)
                        .frame(width: node.parentHashes.count > 1 ? 12 : 10, height: node.parentHashes.count > 1 ? 12 : 10)
                        .overlay {
                            Circle()
                                .stroke(isSelected ? palette.primary : laneColor(palette), lineWidth: 2)
                        }
                        .offset(x: graphInset + CGFloat(node.lane) * laneWidth + laneWidth / 2 - 5)
                }
                .frame(width: graphWidth, height: 66, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(node.subject)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        ForEach(Array(node.references.prefix(2)), id: \.self) { reference in
                            Text(reference)
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(palette.primary)
                                .padding(.horizontal, 6)
                                .frame(height: 18)
                                .background(palette.primarySoft)
                                .clipShape(Capsule())
                        }
                    }
                    HStack(spacing: 7) {
                        Text(node.shortHash)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.primary)
                        Text(node.author).lineLimit(1)
                        Circle().fill(palette.subtleInk).frame(width: 2.5, height: 2.5)
                        Text(node.date.formatted(.relative(presentation: .named))).lineLimit(1)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(palette.subtleInk)
                }
                Spacer(minLength: 8)
            }
            .padding(.trailing, 12)
            .contentShape(Rectangle())
            .background(isSelected ? palette.primarySoft : (isHovering ? palette.raisedSurface.opacity(0.72) : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private func laneColor(_ palette: AppPalette) -> Color {
        switch node.lane % 4 {
        case 0: palette.primary
        case 1: palette.accent
        case 2: palette.success
        default: palette.warning
        }
    }
}

private struct CommitInspector: View {
    @ObservedObject var model: WorkspaceViewModel
    let node: CommitGraphNode?

    @Environment(\.colorScheme) private var colorScheme
    @State private var presentation: Presentation = .preview

    private var commit: CommitRecord? { model.selectedCommit }
    private var document: DiffDocument? { model.commitDiffDocument }

    private var diffStats: (files: Int, additions: Int, deletions: Int) {
        guard let document else { return (0, 0, 0) }
        return (
            document.fileCount,
            document.additionCount,
            document.deletionCount
        )
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            if let commit {
                ViewThatFits(in: .horizontal) {
                    wideHeader(commit: commit, palette: palette)
                        .fixedSize(horizontal: true, vertical: false)
                    compactHeader(commit: commit, palette: palette)
                }
                .background(palette.surface)
            } else {
                HStack {
                    Text(L10n.text("history.detail.title"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(palette.surface)
            }

            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)

            if !model.commitMediaItems.isEmpty {
                HStack(spacing: 10) {
                    Picker("", selection: $presentation) {
                        Text(L10n.text("media.preview")).tag(Presentation.preview)
                        Text(L10n.text("media.changes")).tag(Presentation.changes)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)

                    if presentation == .preview {
                        Menu {
                            ForEach(model.commitMediaItems) { item in
                                Button(item.path) {
                                    model.selectCommitMediaItem(item)
                                }
                            }
                        } label: {
                            HStack(spacing: 7) {
                                GattoIcon(
                                    symbol: model.selectedCommitMediaItem?.kind == .video
                                        ? "play.circle"
                                        : "photo",
                                    size: 14
                                )
                                Text(model.selectedCommitMediaItem?.path ?? "")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                GattoIcon(symbol: "chevron.down", size: 10)
                            }
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        }
                        .menuStyle(.borderlessButton)
                        .frame(maxWidth: 360, alignment: .leading)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(palette.surface)
                Rectangle().fill(palette.divider).frame(height: 1)
            }

            if commit == nil {
                InspectorEmptyState(
                    image: "clock.arrow.circlepath",
                    titleKey: "history.detail.empty.title",
                    bodyKey: "history.detail.empty.body"
                )
            } else if presentation == .preview,
                      let item = model.selectedCommitMediaItem,
                      let previewURL = model.commitMediaPreviewURL {
                RepositoryMediaPreview(url: previewURL, fileName: item.path)
            } else if let document {
                DiffCodeView(document: document)
            } else {
                VStack(alignment: .leading, spacing: 11) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(palette.raisedSurface)
                        .frame(width: 360, height: 12)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(palette.raisedSurface)
                        .frame(width: 280, height: 10)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(palette.raisedSurface)
                        .frame(width: 320, height: 10)
                    Spacer()
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(palette.background)
        .onChange(of: commit?.id) { _, _ in
            presentation = .preview
        }
    }

    private enum Presentation: Hashable {
        case preview
        case changes
    }

    private func wideHeader(commit: CommitRecord, palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            commitIcon(palette: palette)
            commitTitle(commit: commit, palette: palette)
            Spacer(minLength: 14)
            references(palette: palette)
            metrics(palette: palette)
            hashBadge(commit: commit, palette: palette)
            CommitActionsMenu(model: model, commit: commit)
        }
        .padding(.horizontal, 16)
        .frame(height: 76)
    }

    private func compactHeader(commit: CommitRecord, palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                commitIcon(palette: palette)
                Text(commit.subject)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                hashBadge(commit: commit, palette: palette)
                CommitActionsMenu(model: model, commit: commit)
            }
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Text(commit.author).lineLimit(1)
                    Circle().fill(palette.subtleInk).frame(width: 2.5, height: 2.5)
                    Text(commit.date.formatted(date: .abbreviated, time: .shortened))
                        .lineLimit(1)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(palette.subtleInk)
                Spacer(minLength: 8)
                metrics(palette: palette)
            }
            references(palette: palette)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private func commitIcon(palette: AppPalette) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.primarySoft)
            Image(gattoSymbol: node?.parentHashes.count ?? 0 > 1
                  ? "arrow.triangle.merge"
                  : "point.3.filled.connected.trianglepath.dotted")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.primary)
        }
        .frame(width: 38, height: 38)
    }

    private func commitTitle(commit: CommitRecord, palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(commit.subject)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            HStack(spacing: 7) {
                Text(commit.author).lineLimit(1)
                Circle().fill(palette.subtleInk).frame(width: 2.5, height: 2.5)
                Text(commit.date.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.system(size: 9.5))
            .foregroundStyle(palette.subtleInk)
        }
    }

    @ViewBuilder
    private func references(palette: AppPalette) -> some View {
        if let node, !node.references.isEmpty {
            HStack(spacing: 5) {
                ForEach(Array(node.references.prefix(2)), id: \.self) { reference in
                    Text(reference)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.primary)
                        .padding(.horizontal, 6)
                        .frame(height: 21)
                        .background(palette.primarySoft)
                        .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func metrics(palette: AppPalette) -> some View {
        if document != nil {
            HStack(spacing: 5) {
                CommitMetric(value: diffStats.files, symbol: "doc.on.doc", color: palette.mutedInk)
                CommitMetric(value: diffStats.additions, prefix: "+", color: palette.success)
                CommitMetric(value: diffStats.deletions, prefix: "−", color: palette.danger)
            }
        }
    }

    private func hashBadge(commit: CommitRecord, palette: AppPalette) -> some View {
        Text(commit.shortHash)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(palette.primary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(palette.primarySoft)
            .clipShape(Capsule())
    }
}

private struct ReorderCommitsSheet: View {
    @ObservedObject var model: WorkspaceViewModel
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var order: [CommitRecord]

    init(model: WorkspaceViewModel, commits: [CommitRecord], isPresented: Binding<Bool>) {
        self.model = model
        _isPresented = isPresented
        _order = State(initialValue: commits)
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("git_tools.commit.reorder"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(L10n.text("git_tools.commit.reorder_body"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.mutedInk)
                }
                Spacer()
            }
            .padding(18)
            Divider()
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(order.enumerated()), id: \.element.id) { index, commit in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(palette.primary)
                                .frame(width: 24, height: 24)
                                .background(palette.primarySoft)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(commit.subject)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Text(commit.shortHash)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(palette.subtleInk)
                            }
                            Spacer()
                            Button {
                                order.swapAt(index, index - 1)
                            } label: {
                                Image(gattoSymbol: "chevron.compact.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            Button {
                                order.swapAt(index, index + 1)
                            } label: {
                                Image(gattoSymbol: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == order.count - 1)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 58)
                        .background(palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(palette.divider) }
                    }
                }
                .padding(16)
            }
            Divider()
            HStack {
                Spacer()
                Button(L10n.text("action.cancel")) { isPresented = false }
                Button(L10n.text("git_tools.commit.apply_order")) {
                    let commits = order
                    isPresented = false
                    Task { await model.reorderCommits(commits) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 620, height: 560)
        .background(palette.background)
    }
}

private struct ReferenceComparisonSheet: View {
    @ObservedObject var model: WorkspaceViewModel
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(gattoSymbol: "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.primary)
                Text(L10n.text("git_tools.compare.title"))
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(L10n.text("action.close")) { isPresented = false }
            }
            .padding(18)
            Divider()

            HStack(spacing: 12) {
                revisionField(titleKey: "git_tools.compare.base", value: $model.comparisonBaseRevision)
                Image(gattoSymbol: "arrow.right")
                    .foregroundStyle(palette.subtleInk)
                revisionField(titleKey: "git_tools.compare.target", value: $model.comparisonTargetRevision)
                Picker("", selection: $model.comparisonMode) {
                    Text(L10n.text("git_tools.compare.direct")).tag(GitComparisonMode.direct)
                    Text(L10n.text("git_tools.compare.common_ancestor")).tag(GitComparisonMode.commonAncestor)
                }
                .labelsHidden()
                .frame(width: 190)
                Button(L10n.text("git_tools.compare.action")) {
                    model.compareReferences()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isLoadingComparison)
            }
            .padding(16)
            Divider()

            Group {
                if model.isLoadingComparison {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(L10n.text("git_tools.compare.loading"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.mutedInk)
                    }
                } else if let document = model.comparisonDocument {
                    DiffCodeView(document: document)
                } else {
                    InspectorEmptyState(
                        image: "arrow.left.arrow.right",
                        titleKey: "git_tools.compare.empty",
                        bodyKey: "git_tools.compare.empty_body"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, minHeight: 640)
        .background(palette.background)
    }

    private func revisionField(titleKey: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(titleKey))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(AppPalette(colorScheme).mutedInk)
            ComboBox(value: value, options: model.gitReferenceSnapshot.references.map(\.revision))
        }
        .frame(maxWidth: 250)
    }
}

private struct ComboBox: NSViewRepresentable {
    @Binding var value: String
    let options: [String]

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeNSView(context: Context) -> NSComboBox {
        let view = NSComboBox()
        view.isEditable = true
        view.completes = true
        view.delegate = context.coordinator
        view.addItems(withObjectValues: options)
        view.stringValue = value
        return view
    }

    func updateNSView(_ view: NSComboBox, context: Context) {
        if view.objectValues as? [String] != options {
            view.removeAllItems()
            view.addItems(withObjectValues: options)
        }
        if view.stringValue != value { view.stringValue = value }
    }

    final class Coordinator: NSObject, NSComboBoxDelegate, NSControlTextEditingDelegate {
        @Binding var value: String

        init(value: Binding<String>) { _value = value }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            value = comboBox.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            value = comboBox.stringValue
        }
    }
}

private struct CommitActionsMenu: View {
    @ObservedObject var model: WorkspaceViewModel
    let commit: CommitRecord
    @State private var pendingAction: PendingAction?
    @State private var showingMessageEditor = false
    @State private var message = ""

    private var isHead: Bool { model.snapshot?.commits.first?.hash == commit.hash }

    var body: some View {
        Menu {
            Button(L10n.text("git_tools.commit.copy_hash")) { model.copyCommitHash(commit) }
            Divider()
            if isHead {
                Button(L10n.text("git_tools.commit.amend")) {
                    message = commit.subject
                    pendingAction = .amend
                    showingMessageEditor = true
                }
            }
            Button(L10n.text("git_tools.commit.reword")) {
                message = commit.subject
                pendingAction = .reword
                showingMessageEditor = true
            }
            Menu(L10n.text("git_tools.commit.organize")) {
                Button(L10n.text("git_tools.commit.squash")) { pendingAction = .squash }
                Button(L10n.text("git_tools.commit.fixup")) { pendingAction = .fixup }
                Button(L10n.text("git_tools.commit.split")) { pendingAction = .split }
                Button(L10n.text("git_tools.commit.drop"), role: .destructive) { pendingAction = .drop }
            }
            Divider()
            Button(L10n.text("git_tools.commit.cherry_pick")) { pendingAction = .cherryPick }
            Button(L10n.text("git_tools.commit.revert")) { pendingAction = .revert }
            Menu(L10n.text("git_tools.commit.reset")) {
                Button(L10n.text("git_tools.commit.reset_soft")) { pendingAction = .resetSoft }
                Button(L10n.text("git_tools.commit.reset_mixed")) { pendingAction = .resetMixed }
                Button(L10n.text("git_tools.commit.reset_hard"), role: .destructive) { pendingAction = .resetHard }
            }
        } label: {
            Image(gattoSymbol: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.activeOperation != nil || model.repositoryOperationState != nil)
        .sheet(isPresented: $showingMessageEditor, onDismiss: {
            if pendingAction == .amend || pendingAction == .reword {
                pendingAction = nil
            }
        }) {
            VStack(spacing: 0) {
                HStack {
                    Text(L10n.text(pendingAction == .amend ? "git_tools.commit.amend" : "git_tools.commit.reword"))
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                }
                .padding(18)
                Divider()
                TextEditor(text: $message)
                    .font(.system(size: 12.5))
                    .frame(minHeight: 120)
                    .padding(16)
                Divider()
                HStack {
                    Spacer()
                    Button(L10n.text("action.cancel")) {
                        pendingAction = nil
                        showingMessageEditor = false
                    }
                    Button(L10n.text("action.confirm")) {
                        let action = pendingAction
                        pendingAction = nil
                        showingMessageEditor = false
                        Task {
                            if action == .amend {
                                await model.amendHead(message: message)
                            } else {
                                await model.rewriteCommit(commit, mode: .reword, message: message)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(16)
            }
            .frame(width: 520)
        }
        .confirmationDialog(
            L10n.text(pendingAction?.confirmationTitleKey ?? "git_tools.commit.confirm"),
            isPresented: Binding(
                get: { pendingAction != nil && !showingMessageEditor },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                Button(L10n.text("action.confirm"), role: pendingAction.isDestructive ? .destructive : nil) {
                    Task { await run(pendingAction) }
                }
            }
            Button(L10n.text("action.cancel"), role: .cancel) { pendingAction = nil }
        } message: {
            Text(L10n.text(pendingAction?.confirmationBodyKey ?? "git_tools.commit.confirm_body"))
        }
    }

    private func run(_ action: PendingAction) async {
        pendingAction = nil
        switch action {
        case .squash: await model.rewriteCommit(commit, mode: .squash)
        case .fixup: await model.rewriteCommit(commit, mode: .fixup)
        case .drop: await model.rewriteCommit(commit, mode: .drop)
        case .split: await model.rewriteCommit(commit, mode: .split)
        case .cherryPick: await model.cherryPick(commit)
        case .revert: await model.revertCommit(commit)
        case .resetSoft: await model.reset(to: commit, mode: .soft)
        case .resetMixed: await model.reset(to: commit, mode: .mixed)
        case .resetHard: await model.reset(to: commit, mode: .hard)
        case .amend, .reword: break
        }
    }

    private enum PendingAction: Equatable {
        case amend, reword, squash, fixup, drop, split, cherryPick, revert, resetSoft, resetMixed, resetHard

        var isDestructive: Bool {
            switch self {
            case .drop, .split, .resetHard: true
            default: false
            }
        }

        var confirmationTitleKey: String {
            switch self {
            case .squash: "git_tools.commit.squash_confirm"
            case .fixup: "git_tools.commit.fixup_confirm"
            case .drop: "git_tools.commit.drop_confirm"
            case .split: "git_tools.commit.split_confirm"
            case .cherryPick: "git_tools.commit.cherry_pick_confirm"
            case .revert: "git_tools.commit.revert_confirm"
            case .resetSoft, .resetMixed, .resetHard: "git_tools.commit.reset_confirm"
            case .amend, .reword: "git_tools.commit.confirm"
            }
        }

        var confirmationBodyKey: String {
            switch self {
            case .split: "git_tools.commit.split_body"
            case .resetHard: "git_tools.commit.reset_hard_body"
            default: "git_tools.commit.rewrite_body"
            }
        }
    }
}

private struct CommitMetric: View {
    let value: Int
    var prefix = ""
    var symbol: String?
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(gattoSymbol: symbol)
                    .font(.system(size: 8.5, weight: .semibold))
            }
            Text("\(prefix)\(value)")
        }
        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .frame(height: 23)
        .background(color.opacity(0.09))
        .clipShape(Capsule())
    }
}
