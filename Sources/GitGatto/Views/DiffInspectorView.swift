import SwiftUI

struct DiffInspectorView: View {
    let change: WorkingTreeChange?
    let document: DiffDocument?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let change {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(URL(fileURLWithPath: change.path).lastPathComponent)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Text(change.path)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(palette.subtleInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(L10n.text(change.isStaged ? "changes.staged_single" : "changes.unstaged_single"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(change.isStaged ? palette.success : palette.primary)
                        .padding(.horizontal, 8)
                        .frame(height: 23)
                        .background(change.isStaged ? palette.successSoft : palette.primarySoft)
                        .clipShape(Capsule())
                } else {
                    Text(L10n.text("diff.title"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(palette.surface)

            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)

            if change == nil {
                InspectorEmptyState(
                    image: "doc.text.magnifyingglass",
                    titleKey: "diff.empty.title",
                    bodyKey: "diff.empty.body"
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
                .background(palette.background)
            }
        }
        .background(palette.background)
    }
}

struct DiffCodeView: View {
    let document: DiffDocument
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        if document.lines.isEmpty {
            InspectorEmptyState(
                image: "text.alignleft",
                titleKey: "diff.no_content.title",
                bodyKey: "diff.no_content.body"
            )
        } else {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(document.lines) { line in
                            DiffLineView(line: line)
                        }
                    }
                    .frame(
                        minWidth: max(760, proxy.size.width),
                        minHeight: proxy.size.height,
                        alignment: .topLeading
                    )
                }
                .background(palette.background)
            }
        }
    }
}

private struct DiffLineView: View {
    let line: DiffLine
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 0) {
            Text(line.oldLineNumber.map(String.init) ?? "")
                .frame(width: 42, alignment: .trailing)
            Text(line.newLineNumber.map(String.init) ?? "")
                .frame(width: 42, alignment: .trailing)

            Rectangle()
                .fill(separatorColor(palette))
                .frame(width: 1)
                .padding(.leading, 10)

            Text(line.text.isEmpty ? " " : line.text)
                .padding(.leading, 12)
                .padding(.trailing, 18)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.system(size: 11.5, weight: fontWeight, design: .monospaced))
        .foregroundStyle(foregroundColor(palette))
        .frame(height: line.kind == .hunk ? 28 : 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor(palette))
    }

    private var fontWeight: Font.Weight {
        line.kind == .hunk || line.kind == .header ? .medium : .regular
    }

    private func backgroundColor(_ palette: AppPalette) -> Color {
        switch line.kind {
        case .addition: palette.successSoft.opacity(0.82)
        case .deletion: palette.dangerSoft.opacity(0.82)
        case .hunk: palette.accentSoft
        default: palette.background
        }
    }

    private func foregroundColor(_ palette: AppPalette) -> Color {
        switch line.kind {
        case .addition: palette.success
        case .deletion: palette.danger
        case .hunk: palette.accent
        case .header: palette.subtleInk
        case .context: palette.mutedInk
        }
    }

    private func separatorColor(_ palette: AppPalette) -> Color {
        switch line.kind {
        case .addition: palette.success.opacity(0.28)
        case .deletion: palette.danger.opacity(0.28)
        case .hunk: palette.accent.opacity(0.28)
        default: palette.divider
        }
    }
}

struct InspectorEmptyState: View {
    let image: String
    let titleKey: String
    let bodyKey: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 10) {
            Image(systemName: image)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            Text(L10n.text(titleKey))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text(L10n.text(bodyKey))
                .font(.system(size: 11.5))
                .foregroundStyle(palette.mutedInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
    }
}
