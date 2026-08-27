import SwiftUI

struct BranchesWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue

    @ViewBuilder
    var body: some View {
        let palette = AppPalette(colorScheme)
        GeometryReader { proxy in
            if AppVisualTheme.resolved(themeRaw) == .standard {
                HStack(spacing: 0) {
                    BranchNavigator(model: model)
                        .frame(width: min(380, max(310, proxy.size.width * 0.36)))
                    Rectangle().fill(palette.divider).frame(width: 1)
                    BranchInspector(branch: model.selectedBranch)
                }
            } else {
                HStack(spacing: 10) {
                    BranchNavigator(model: model)
                        .frame(width: min(380, max(310, proxy.size.width * 0.36)))
                        .appGlassPanel(cornerRadius: 14, elevated: false)
                    BranchInspector(branch: model.selectedBranch)
                        .appGlassPanel(cornerRadius: 14, elevated: false)
                }
                .padding(10)
            }
        }
    }
}

private struct BranchNavigator: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("branches.title"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
                CountBadge(count: model.snapshot?.branches.count ?? 0, emphasized: true)
            }
            .padding(.horizontal, 15)
            .frame(height: 64)

            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionLabel(titleKey: "branches.local", count: model.snapshot?.branches.count ?? 0)
                        .padding(.horizontal, 15)

                    ForEach(model.snapshot?.branches ?? []) { branch in
                        BranchRow(
                            branch: branch,
                            isSelected: model.selectedBranch?.id == branch.id
                        ) {
                            model.selectedBranch = branch
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .background(palette.surface)
    }
}

private struct BranchRow: View {
    let branch: BranchRecord
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(branch.isCurrent ? palette.primary : palette.subtleInk)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(branch.name)
                        .font(.system(size: 12, weight: branch.isCurrent ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Text(branch.shortHash)
                            .font(.system(size: 10, design: .monospaced))
                        if let upstream = branch.upstream {
                            Circle()
                                .fill(palette.subtleInk)
                                .frame(width: 2.5, height: 2.5)
                            Text(upstream)
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(palette.subtleInk)
                }

                Spacer(minLength: 8)
                if branch.isCurrent {
                    Text(L10n.text("branches.current"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(palette.primary)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(palette.primarySoft)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .contentShape(Rectangle())
            .background(isSelected ? palette.primarySoft : (isHovering ? palette.raisedSurface.opacity(0.72) : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct BranchInspector: View {
    let branch: BranchRecord?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("branches.detail.title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(palette.surface)

            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)

            if let branch {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(branch.isCurrent ? palette.primarySoft : palette.accentSoft)
                                .frame(width: 46, height: 46)
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(branch.isCurrent ? palette.primary : palette.accent)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(branch.name)
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                .foregroundStyle(palette.ink)
                            if branch.isCurrent {
                                Text(L10n.text("branches.checked_out"))
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(palette.primary)
                            }
                        }
                    }

                    VStack(spacing: 0) {
                        BranchMetadataRow(labelKey: "branches.latest_commit", value: branch.shortHash, monospaced: true)
                        Rectangle().fill(palette.divider).frame(height: 1)
                        BranchMetadataRow(labelKey: "branches.upstream", value: branch.upstream ?? L10n.text("branches.no_upstream"), monospaced: branch.upstream != nil)
                        Rectangle().fill(palette.divider).frame(height: 1)
                        BranchMetadataRow(labelKey: "branches.status", value: branch.isCurrent ? L10n.text("branches.active") : L10n.text("branches.inactive"), monospaced: false)
                    }
                    .background(palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(palette.divider, lineWidth: 1)
                    }

                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                InspectorEmptyState(
                    image: "arrow.triangle.branch",
                    titleKey: "branches.empty.title",
                    bodyKey: "branches.empty.body"
                )
            }
        }
        .background(palette.background)
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
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: monospaced ? .monospaced : .default))
                .foregroundStyle(palette.ink)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }
}
