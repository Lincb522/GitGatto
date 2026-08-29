import SwiftUI

struct StashWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue

    var body: some View {
        let palette = AppPalette(colorScheme)
        GeometryReader { proxy in
            if AppVisualTheme.resolved(themeRaw) == .standard {
                content(proxy: proxy, spacing: 0)
            } else if AppVisualTheme.resolved(themeRaw) == .softGlass {
                content(proxy: proxy, spacing: 10)
                    .padding(10)
            } else {
                content(proxy: proxy, spacing: 8)
                    .padding(8)
                    .background(palette.background)
            }
        }
    }

    @ViewBuilder
    private func content(proxy: GeometryProxy, spacing: CGFloat) -> some View {
        let theme = AppVisualTheme.resolved(themeRaw)
        VStack(spacing: spacing) {
            StashCommandBar(model: model)
                .modifier(StashPanelModifier(theme: theme))
            if theme == .standard {
                Rectangle().fill(AppPalette(colorScheme).divider).frame(height: 1)
            }
            HStack(spacing: spacing) {
                StashNavigator(model: model)
                    .frame(width: min(390, max(320, proxy.size.width * 0.35)))
                    .modifier(StashPanelModifier(theme: theme))
                if theme == .standard {
                    Rectangle().fill(AppPalette(colorScheme).divider).frame(width: 1)
                }
                StashInspector(model: model)
                    .modifier(StashPanelModifier(theme: theme))
            }
        }
    }
}

private struct StashCommandBar: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.primarySoft)
                Image(gattoSymbol: "archivebox.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.primary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("stash.title"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text(L10n.text("stash.command.current_changes"))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
            }

            Rectangle().fill(palette.divider).frame(width: 1, height: 30)

            HStack(spacing: 8) {
                Image(gattoSymbol: "text.cursor")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.subtleInk)
                TextField(L10n.text("stash.message.placeholder"), text: $model.stashMessage)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.ink)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: 360)
            .frame(height: 34)
            .background(palette.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(palette.divider, lineWidth: 1)
            }

            Toggle(L10n.text("stash.include_untracked"), isOn: $model.stashIncludesUntracked)
                .toggleStyle(.checkbox)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.mutedInk)

            Spacer(minLength: 8)

            Button {
                Task { await model.saveStash() }
            } label: {
                HStack(spacing: 6) {
                    if model.activeOperation == .stashSave {
                        ProgressView().controlSize(.small)
                    }
                    Text(L10n.text("stash.action.save"))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(
                model.snapshot?.changes.isEmpty != false
                    || model.activeOperation != nil
                    || model.repositoryOperationState != nil
            )
        }
        .padding(.horizontal, 15)
        .frame(height: 64)
        .background(palette.surface)
    }
}

private struct StashPanelModifier: ViewModifier {
    let theme: AppVisualTheme

    @ViewBuilder
    func body(content: Content) -> some View {
        switch theme {
        case .standard:
            content
        case .softGlass:
            content.appGlassPanel(cornerRadius: 14, elevated: false)
        case .console:
            content.appConsolePanel()
        }
    }
}

private struct StashNavigator: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("stash.title"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
                CountBadge(count: model.stashes.count, emphasized: true)
            }
            .padding(.horizontal, 15)
            .frame(height: 52)

            Rectangle().fill(palette.divider).frame(height: 1)

            if model.stashes.isEmpty {
                InspectorEmptyState(
                    image: "archivebox",
                    titleKey: "stash.empty.title",
                    bodyKey: "stash.empty.body"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(model.stashes) { stash in
                            StashRow(
                                stash: stash,
                                isSelected: model.selectedStash?.id == stash.id
                            ) {
                                model.selectStash(stash)
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(palette.surface)
    }

}

private struct StashRow: View {
    let stash: StashRecord
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var title: String {
        guard let separator = stash.summary.firstIndex(of: ":") else { return stash.summary }
        return stash.summary[stash.summary.index(after: separator)...]
            .trimmingCharacters(in: .whitespaces)
    }

    private var context: String? {
        guard let separator = stash.summary.firstIndex(of: ":") else { return nil }
        return String(stash.summary[..<separator])
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(gattoSymbol: "archivebox.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? palette.primary : palette.subtleInk)
                    .frame(width: 22, height: 22)
                    .background(isSelected ? palette.primarySoft : palette.raisedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        if let context {
                            Text(context)
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(palette.primary)
                                .padding(.horizontal, 5)
                                .frame(height: 17)
                                .background(palette.primarySoft)
                                .clipShape(Capsule())
                        }
                    }
                    HStack(spacing: 7) {
                        Text(stash.reference)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        Circle().fill(palette.subtleInk).frame(width: 2.5, height: 2.5)
                        Text(stash.createdAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                            .lineLimit(1)
                    }
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.subtleInk)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 54)
            .contentShape(Rectangle())
            .background(isSelected ? palette.primarySoft : (isHovering ? palette.raisedSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct StashInspector: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isConfirmingDrop = false

    private var diffStats: (files: Int, additions: Int, deletions: Int) {
        guard let lines = model.stashDiffDocument?.lines else { return (0, 0, 0) }
        return (
            lines.filter { $0.text.hasPrefix("diff --git ") }.count,
            lines.filter { $0.kind == .addition }.count,
            lines.filter { $0.kind == .deletion }.count
        )
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            if let stash = model.selectedStash {
                ViewThatFits(in: .horizontal) {
                    wideHeader(stash: stash, palette: palette)
                        .fixedSize(horizontal: true, vertical: false)
                    compactHeader(stash: stash, palette: palette)
                }
                .disabled(model.activeOperation != nil || model.repositoryOperationState != nil)
                .background(palette.surface)

                Rectangle().fill(palette.divider).frame(height: 1)

                if model.isLoadingStashDiff {
                    GattoLoadingState(text: L10n.text("loading.generic"))
                        .background(palette.background)
                } else if let document = model.stashDiffDocument {
                    DiffCodeView(document: document)
                } else {
                    InspectorEmptyState(
                        image: "doc.text.magnifyingglass",
                        titleKey: "stash.diff.empty.title",
                        bodyKey: "stash.diff.empty.body"
                    )
                }
            } else {
                InspectorEmptyState(
                    image: "archivebox",
                    titleKey: "stash.selection.empty.title",
                    bodyKey: "stash.selection.empty.body"
                )
            }
        }
        .background(palette.background)
        .confirmationDialog(
            L10n.text("stash.drop.confirm.title"),
            isPresented: $isConfirmingDrop,
            titleVisibility: .visible
        ) {
            Button(L10n.text("stash.action.drop"), role: .destructive) {
                Task { await model.dropSelectedStash() }
            }
            Button(L10n.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("stash.drop.confirm.message"))
        }
    }

    private func wideHeader(stash: StashRecord, palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            stashIdentity(stash: stash, palette: palette)
            Spacer(minLength: 16)
            stashMetrics(palette: palette)
            stashActions
        }
        .padding(.horizontal, 15)
        .frame(height: 76)
    }

    private func compactHeader(stash: StashRecord, palette: AppPalette) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                stashIdentity(stash: stash, palette: palette)
                Spacer(minLength: 8)
                stashMetrics(palette: palette)
            }
            HStack {
                Spacer()
                stashActions
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private func stashIdentity(stash: StashRecord, palette: AppPalette) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.primarySoft)
                Image(gattoSymbol: "archivebox.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.primary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(stash.summary)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Text(stash.reference)
                    Circle().fill(palette.subtleInk).frame(width: 2.5, height: 2.5)
                    Text(String(stash.hash.prefix(8)))
                    Circle().fill(palette.subtleInk).frame(width: 2.5, height: 2.5)
                    Text(stash.createdAt.formatted(.relative(presentation: .named)))
                }
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(palette.subtleInk)
                .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func stashMetrics(palette: AppPalette) -> some View {
        if model.stashDiffDocument != nil {
            HStack(spacing: 5) {
                StashMetric(value: diffStats.files, symbol: "doc.on.doc", color: palette.mutedInk)
                StashMetric(value: diffStats.additions, prefix: "+", color: palette.success)
                StashMetric(value: diffStats.deletions, prefix: "−", color: palette.danger)
            }
        }
    }

    private var stashActions: some View {
        HStack(spacing: 7) {
            Button {
                Task { await model.applySelectedStash() }
            } label: {
                GattoLabel(L10n.text("stash.action.apply"), systemImage: "arrow.down.to.line")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                Task { await model.popSelectedStash() }
            } label: {
                GattoLabel(L10n.text("stash.action.pop"), systemImage: "archivebox")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button(role: .destructive) {
                isConfirmingDrop = true
            } label: {
                Image(gattoSymbol: "trash")
            }
            .help(L10n.text("stash.action.drop"))
        }
    }
}

private struct StashMetric: View {
    let value: Int
    var prefix = ""
    var symbol: String?
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(gattoSymbol: symbol).font(.system(size: 8.5, weight: .semibold))
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
