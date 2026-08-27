import SwiftUI

struct HistoryWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue

    @ViewBuilder
    var body: some View {
        let palette = AppPalette(colorScheme)
        GeometryReader { proxy in
            if AppVisualTheme.resolved(themeRaw) == .standard {
                HStack(spacing: 0) {
                    CommitNavigator(model: model)
                        .frame(width: min(410, max(330, proxy.size.width * 0.39)))
                    Rectangle().fill(palette.divider).frame(width: 1)
                    CommitInspector(commit: model.selectedCommit, document: model.commitDiffDocument)
                }
            } else {
                HStack(spacing: 10) {
                    CommitNavigator(model: model)
                        .frame(width: min(410, max(330, proxy.size.width * 0.39)))
                        .appGlassPanel(cornerRadius: 14, elevated: false)
                    CommitInspector(commit: model.selectedCommit, document: model.commitDiffDocument)
                        .appGlassPanel(cornerRadius: 14, elevated: false)
                }
                .padding(10)
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
            VStack(spacing: 12) {
                HStack {
                    Text(L10n.text("history.title"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    Text(L10n.format("history.commit_count", model.snapshot?.commits.count ?? 0))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.subtleInk)
                }
                SearchField(text: $model.searchText, placeholderKey: "search.history")
            }
            .padding(.horizontal, 15)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)

            if model.filteredCommits.isEmpty {
                InspectorEmptyState(
                    image: "clock.arrow.circlepath",
                    titleKey: "history.empty.title",
                    bodyKey: "history.empty.body"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.filteredCommits.enumerated()), id: \.element.id) { index, commit in
                            CommitRow(
                                commit: commit,
                                isSelected: model.selectedCommit?.id == commit.id,
                                isFirst: index == 0,
                                isLast: index == model.filteredCommits.count - 1
                            ) {
                                model.selectCommit(commit)
                            }
                        }
                    }
                }
            }
        }
        .background(palette.surface)
    }
}

private struct CommitRow: View {
    let commit: CommitRecord
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 0) {
                ZStack {
                    if !isFirst {
                        Rectangle()
                            .fill(palette.divider)
                            .frame(width: 1, height: 27)
                            .offset(y: -20)
                    }
                    if !isLast {
                        Rectangle()
                            .fill(palette.divider)
                            .frame(width: 1, height: 27)
                            .offset(y: 20)
                    }
                    Circle()
                        .fill(isSelected ? palette.primary : palette.raisedSurface)
                        .frame(width: 10, height: 10)
                        .overlay {
                            Circle()
                                .stroke(isSelected ? palette.primary : palette.subtleInk, lineWidth: 1.5)
                        }
                }
                .frame(width: 38)

                VStack(alignment: .leading, spacing: 6) {
                    Text(commit.subject)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(palette.ink)
                        .lineLimit(2)

                    HStack(spacing: 7) {
                        Text(commit.shortHash)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.primary)
                        Text(commit.author)
                            .lineLimit(1)
                        Circle()
                            .fill(palette.subtleInk)
                            .frame(width: 2.5, height: 2.5)
                        Text(commit.date.formatted(.relative(presentation: .named)))
                            .lineLimit(1)
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.subtleInk)
                }
                Spacer(minLength: 8)
            }
            .padding(.trailing, 14)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
            .background(isSelected ? palette.primarySoft : (isHovering ? palette.raisedSurface.opacity(0.72) : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct CommitInspector: View {
    let commit: CommitRecord?
    let document: DiffDocument?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            if let commit {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(commit.subject)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(2)
                        Spacer()
                        Text(commit.shortHash)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.primary)
                            .padding(.horizontal, 8)
                            .frame(height: 23)
                            .background(palette.primarySoft)
                            .clipShape(Capsule())
                    }
                    HStack(spacing: 8) {
                        Label(commit.author, systemImage: "person.crop.circle")
                        Circle()
                            .fill(palette.subtleInk)
                            .frame(width: 3, height: 3)
                        Text(commit.date.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.mutedInk)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                VStack {
                    ProgressView()
                        .controlSize(.small)
                        .tint(palette.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(palette.background)
    }
}
