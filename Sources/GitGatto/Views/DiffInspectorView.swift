import SwiftUI

struct DiffInspectorView: View {
    let change: WorkingTreeChange?
    let document: DiffDocument?
    let previewURL: URL?

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @State private var presentation: Presentation = .preview

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                if let change {
                    ZStack {
                        RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous)
                            .fill(palette.primarySoft)
                        Image(gattoSymbol: changeIcon(for: change.path))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(palette.primary)
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(URL(fileURLWithPath: change.path).lastPathComponent)
                            .font(.system(size: 13.5, weight: .semibold, design: theme == .console ? .monospaced : .default))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Text(change.path)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(palette.subtleInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if previewURL != nil {
                        Picker("", selection: $presentation) {
                            Text(L10n.text("media.preview")).tag(Presentation.preview)
                            Text(L10n.text("media.changes")).tag(Presentation.changes)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                    if let document {
                        HStack(spacing: 8) {
                            Text("+\(document.lines.filter { $0.kind.isAddition }.count)")
                                .foregroundStyle(palette.success)
                            Text("−\(document.lines.filter { $0.kind.isDeletion }.count)")
                                .foregroundStyle(palette.danger)
                        }
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    }
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
            .frame(height: 62)
            .background(theme == .softGlass ? palette.surface.opacity(0.15) : palette.surface)

            Rectangle()
                .fill(palette.divider)
                .frame(height: 1)

            if change == nil {
                InspectorEmptyState(
                    image: "doc.text.magnifyingglass",
                    titleKey: "diff.empty.title",
                    bodyKey: "diff.empty.body"
                )
            } else if presentation == .preview,
                      let previewURL,
                      let change {
                RepositoryMediaPreview(
                    url: previewURL,
                    fileName: change.path
                )
            } else if let document {
                DiffCodeView(document: document)
            } else {
                GattoLoadingState(text: L10n.text("loading.generic"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.background)
            }
        }
        .background(palette.background)
        .onChange(of: change?.id) { _, _ in
            presentation = .preview
        }
    }

    private enum Presentation: Hashable {
        case preview
        case changes
    }

    private func changeIcon(for path: String) -> String {
        switch RepositoryMediaKind(fileName: path) {
        case .image, .svg: "photo"
        case .video: "play.circle"
        case nil: "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct DiffCodeView: View {
    let document: DiffDocument
    var onSelectLine: ((DiffLine) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }

    var body: some View {
        let palette = AppPalette(colorScheme)
        if document.lines.isEmpty {
            InspectorEmptyState(
                image: "text.alignleft",
                titleKey: "diff.no_content.title",
                bodyKey: "diff.no_content.body"
            )
        } else {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(document.lines) { line in
                                DiffLineView(
                                    line: line,
                                    fileName: document.path,
                                    theme: theme,
                                    onSelect: onSelectLine
                                )
                            }
                        }
                        .frame(
                            minWidth: proxy.size.width,
                            minHeight: proxy.size.height,
                            alignment: .topLeading
                        )
                    }
                    .defaultScrollAnchor(.topLeading)
                }

                Rectangle().fill(palette.divider).frame(height: 1)
                DiffSurfaceStatusBar(document: document, theme: theme)
            }
            .background(theme == .softGlass ? palette.background.opacity(0.22) : palette.background)
        }
    }
}

private struct DiffLineView: View {
    let line: DiffLine
    let fileName: String
    let theme: AppVisualTheme
    let onSelect: ((DiffLine) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 0) {
            Text(statusSymbol)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(statusColor(palette))
                .frame(width: 24)
                .frame(maxHeight: .infinity)
                .background(gutterBackground(palette))
            Text(line.oldLineNumber.map(String.init) ?? "")
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 9)
                .frame(maxHeight: .infinity)
                .background(gutterBackground(palette))
            Text(line.newLineNumber.map(String.init) ?? "")
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 9)
                .frame(maxHeight: .infinity)
                .background(gutterBackground(palette))

            Rectangle()
                .fill(separatorColor(palette))
                .frame(width: 1)

            Group {
                if line.kind.isCode {
                    SyntaxHighlightedCodeLine(
                        text: codeText,
                        fileName: fileName,
                        highlightsSyntax: true
                    )
                } else {
                    Text(line.text.isEmpty ? " " : line.text)
                        .foregroundStyle(foregroundColor(palette))
                        .textSelection(.enabled)
                }
            }
                .padding(.leading, 14)
                .padding(.trailing, 18)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.system(size: theme == .console ? 10.5 : 11.5, weight: fontWeight, design: .monospaced))
        .foregroundStyle(palette.subtleInk)
        .frame(height: line.kind == .hunk ? 28 : 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? hoverColor(palette) : backgroundColor(palette))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            onSelect?(line)
        }
    }

    private var codeText: String {
        guard !line.text.isEmpty else { return " " }
        switch line.kind {
        case .addition where line.text.first == "+":
            return String(line.text.dropFirst())
        case .deletion where line.text.first == "-":
            return String(line.text.dropFirst())
        case .context where line.text.first == " ":
            return String(line.text.dropFirst())
        default:
            return line.text
        }
    }

    private var statusSymbol: String {
        switch line.kind {
        case .addition: "+"
        case .deletion: "−"
        case .hunk: "@"
        case .header: "·"
        case .context: ""
        }
    }

    private var fontWeight: Font.Weight {
        line.kind == .hunk || line.kind == .header ? .medium : .regular
    }

    private func backgroundColor(_ palette: AppPalette) -> Color {
        switch line.kind {
        case .addition: palette.successSoft.opacity(0.82)
        case .deletion: palette.dangerSoft.opacity(0.82)
        case .hunk: palette.accentSoft.opacity(0.82)
        case .header: palette.raisedSurface.opacity(0.58)
        default: Color.clear
        }
    }

    private func hoverColor(_ palette: AppPalette) -> Color {
        switch line.kind {
        case .addition: palette.successSoft
        case .deletion: palette.dangerSoft
        case .hunk: palette.accentSoft
        default: palette.primarySoft.opacity(0.42)
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

    private func statusColor(_ palette: AppPalette) -> Color {
        switch line.kind {
        case .addition: palette.success
        case .deletion: palette.danger
        case .hunk: palette.accent
        default: palette.subtleInk
        }
    }

    private func gutterBackground(_ palette: AppPalette) -> Color {
        switch theme {
        case .standard: palette.sidebar.opacity(0.62)
        case .emerald, .folio: palette.background.opacity(0.72)
        case .softGlass: palette.sidebar.opacity(0.20)
        case .console: palette.sidebar.opacity(0.76)
        }
    }
}

private struct DiffSurfaceStatusBar: View {
    let document: DiffDocument
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 12) {
            GattoLabel(CodeSyntax.languageName(for: document.path), systemImage: "arrow.left.arrow.right.square")
            Spacer()
            Text("+\(document.lines.filter { $0.kind.isAddition }.count)")
                .foregroundStyle(palette.success)
            Text("−\(document.lines.filter { $0.kind.isDeletion }.count)")
                .foregroundStyle(palette.danger)
            Text(L10n.format("code_surface.lines", document.lines.count))
        }
        .font(.system(size: 9.5, weight: .medium, design: theme == .console ? .monospaced : .default))
        .foregroundStyle(palette.subtleInk)
        .padding(.horizontal, 12)
        .frame(height: 29)
        .background(theme == .softGlass ? palette.surface.opacity(0.16) : palette.surface)
    }
}

private extension DiffLineKind {
    var isAddition: Bool { if case .addition = self { true } else { false } }
    var isDeletion: Bool { if case .deletion = self { true } else { false } }
    var isCode: Bool {
        switch self {
        case .context, .addition, .deletion: true
        case .header, .hunk: false
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
            Image(gattoSymbol: image)
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
