import SwiftUI

struct DiffInspectorView: View {
    let change: WorkingTreeChange?
    let document: DiffDocument?
    let previewURL: URL?
    var onStageSelection: ((Set<UUID>, DiffDocument, WorkingTreeChange) -> Void)? = nil
    var onPlanSelection: ((Set<UUID>, DiffDocument, WorkingTreeChange) -> Void)? = nil
    var isEditingIndex = false
    @State private var selectedLineIDs: Set<UUID> = []

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @State private var presentation: Presentation = .preview

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let compactHeader = [.console, .emerald, .folio].contains(theme) && proxy.size.width < 540
                HStack(spacing: theme == .console ? 8 : 11) {
                    if let change {
                        if !compactHeader {
                            ZStack {
                                RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous)
                                    .fill(palette.primarySoft)
                                Image(gattoSymbol: changeIcon(for: change.path), pointSize: 12.5)
                                    .foregroundStyle(palette.primary)
                            }
                            .frame(width: theme == .console ? 24 : 34, height: theme == .console ? 24 : 34)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(URL(fileURLWithPath: change.path).lastPathComponent)
                                .font(.system(size: theme == .folio ? 16 : (theme == .console ? 11.5 : 13.5), weight: .semibold, design: theme == .console ? .monospaced : .default))
                                .foregroundStyle(palette.ink)
                                .lineLimit(1)
                            if theme != .console {
                                Text(change.path)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(palette.subtleInk)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer()
                        if previewURL != nil {
                            Picker("", selection: $presentation) {
                                Text(L10n.text("media.preview")).tag(Presentation.preview)
                                Text(L10n.text("media.changes")).tag(Presentation.changes)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: compactHeader ? 115 : 150)
                        }
                        if let document, !compactHeader {
                            HStack(spacing: 8) {
                                Text("+\(document.additionCount)")
                                    .foregroundStyle(palette.success)
                                Text("−\(document.deletionCount)")
                                    .foregroundStyle(palette.danger)
                            }
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        }
                        if compactHeader {
                            GattoIcon(symbol: change.isStaged ? "checkmark.circle" : "circle", size: 17)
                                .foregroundStyle(change.isStaged ? palette.success : palette.mutedInk)
                                .help(L10n.text(change.isStaged ? "changes.staged_single" : "changes.unstaged_single"))
                                .accessibilityLabel(L10n.text(change.isStaged ? "changes.staged_single" : "changes.unstaged_single"))
                        } else {
                            Text(L10n.text(change.isStaged ? "changes.staged_single" : "changes.unstaged_single"))
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(change.isStaged ? palette.success : palette.primary)
                                .padding(.horizontal, 8)
                                .frame(height: 23)
                                .background(change.isStaged ? palette.successSoft : palette.primarySoft)
                                .clipShape(Capsule())
                        }
                    } else {
                        Text(L10n.text("diff.title"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.ink)
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: theme == .console ? 38 : (theme == .folio ? 74 : (theme == .emerald ? 78 : 62)))
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
                if let change, onStageSelection != nil, PartialDiffPatch.supports(document) {
                    DiffSelectionActions(count: selectedLineIDs.count, isStaged: change.isStaged,
                        isBusy: isEditingIndex, onStage: { onStageSelection?(selectedLineIDs, document, change) },
                        onPlan: onPlanSelection.map { action in { action(selectedLineIDs, document, change) } })
                    DiffCodeView(document: document, selectedLineIDs: selectedLineIDs, onToggleLine: { line in
                        guard !isEditingIndex else { return }
                        if line.kind == .hunk, let start = document.lines.firstIndex(where: { $0.id == line.id }) {
                            let following = document.lines.dropFirst(start + 1).prefix { $0.kind != .hunk }
                            let ids = Set(following.filter { $0.kind == .addition || $0.kind == .deletion }.map(\.id))
                            if ids.isSubset(of: selectedLineIDs) { selectedLineIDs.subtract(ids) }
                            else { selectedLineIDs.formUnion(ids) }
                        } else if !selectedLineIDs.insert(line.id).inserted { selectedLineIDs.remove(line.id) }
                    })
                    .disabled(isEditingIndex)
                } else { DiffCodeView(document: document) }
            } else {
                GattoLoadingState(text: L10n.text("loading.generic"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme == .folio ? palette.surface : palette.background)
            }
        }
        .background(theme == .folio ? palette.surface : palette.background)
        .onChange(of: document?.lines.first?.id) { _, _ in selectedLineIDs = [] }
        .onChange(of: document?.sourceText) { _, _ in selectedLineIDs = [] }
        .onChange(of: change?.id) { _, _ in
            presentation = .preview
            selectedLineIDs = []
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
    var selectedLineIDs: Set<UUID> = []
    var onToggleLine: ((DiffLine) -> Void)? = nil
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
                                    palette: palette,
                                    onSelect: onSelectLine,
                                    isSelected: selectedLineIDs.contains(line.id),
                                    onToggle: onToggleLine
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
            .background(theme == .softGlass ? palette.background.opacity(0.22) : (theme == .folio ? palette.surface : palette.background))
        }
    }
}

private struct DiffLineView: View {
    let line: DiffLine
    let fileName: String
    let theme: AppVisualTheme
    let palette: AppPalette
    let onSelect: ((DiffLine) -> Void)?
    var isSelected = false
    var onToggle: ((DiffLine) -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            if let onToggle, [.addition, .deletion, .hunk].contains(line.kind) {
                Button { onToggle(line) } label: {
                    Image(gattoSymbol: line.kind == .hunk ? "square.stack.3d.up" : (isSelected ? "checkmark.square.fill" : "square"))
                        .foregroundStyle(isSelected ? palette.primary : palette.subtleInk)
                        .frame(width: 28, height: 22)
                }.buttonStyle(.plain)
                    .accessibilityLabel(L10n.text(line.kind == .hunk ? "diff.partial.hunk" : "diff.partial.line"))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else if onToggle != nil { Color.clear.frame(width: 28) }
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
                        palette: palette,
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
        case .emerald, .folio, .lumen: palette.background.opacity(0.72)
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
            Text("+\(document.additionCount)")
                .foregroundStyle(palette.success)
            Text("−\(document.deletionCount)")
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
            Image(gattoSymbol: image, pointSize: 25)
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

struct DiffSelectionActions: View {
    let count: Int
    let isStaged: Bool
    let isBusy: Bool
    let onStage: () -> Void
    let onPlan: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summary
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actions }.fixedSize()
                VStack(alignment: .leading, spacing: 10) { actions }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(10)
    }

    private var summary: some View {
        Text(L10n.format("diff.partial.selected", count)).font(.caption).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var actions: some View {
        if let onPlan {
            Button(L10n.text("diff.partial.plan"), action: onPlan)
                .buttonStyle(SecondaryButtonStyle()).disabled(count == 0 || isBusy)
        }
        Button(L10n.text(isStaged ? "diff.partial.unstage" : "diff.partial.stage"), action: onStage)
            .buttonStyle(PrimaryButtonStyle()).disabled(count == 0 || isBusy)
    }
}
