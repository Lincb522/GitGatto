import SwiftUI

struct HistoryWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue

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
                        node: selectedNode,
                        commit: model.selectedCommit,
                        document: model.commitDiffDocument
                    )
                }
            } else if AppVisualTheme.resolved(themeRaw) == .softGlass {
                HStack(spacing: 10) {
                    CommitNavigator(model: model)
                        .frame(width: min(470, max(350, proxy.size.width * 0.44)))
                        .appGlassPanel(cornerRadius: 14, elevated: false)
                    CommitInspector(
                        node: selectedNode,
                        commit: model.selectedCommit,
                        document: model.commitDiffDocument
                    )
                        .appGlassPanel(cornerRadius: 14, elevated: false)
                }
                .padding(10)
            } else {
                HStack(spacing: 8) {
                    CommitNavigator(model: model)
                        .frame(width: min(480, max(350, proxy.size.width * 0.43)))
                        .appConsolePanel()
                    CommitInspector(
                        node: selectedNode,
                        commit: model.selectedCommit,
                        document: model.commitDiffDocument
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
    let node: CommitGraphNode?
    let commit: CommitRecord?
    let document: DiffDocument?

    @Environment(\.colorScheme) private var colorScheme

    private var diffStats: (files: Int, additions: Int, deletions: Int) {
        guard let document else { return (0, 0, 0) }
        return (
            document.lines.filter { $0.text.hasPrefix("diff --git ") }.count,
            document.lines.filter { $0.kind == .addition }.count,
            document.lines.filter { $0.kind == .deletion }.count
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

            if commit == nil {
                InspectorEmptyState(
                    image: "clock.arrow.circlepath",
                    titleKey: "history.detail.empty.title",
                    bodyKey: "history.detail.empty.body"
                )
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
    }

    private func wideHeader(commit: CommitRecord, palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            commitIcon(palette: palette)
            commitTitle(commit: commit, palette: palette)
            Spacer(minLength: 14)
            references(palette: palette)
            metrics(palette: palette)
            hashBadge(commit: commit, palette: palette)
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
