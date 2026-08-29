import SwiftUI

struct ConflictResolutionWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    let state: RepositoryOperationState

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSource: ConflictSource = .ours
    @State private var isConfirmingAbort = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            operationHeader(palette: palette)
            Rectangle().fill(palette.divider).frame(height: 1)

            GeometryReader { proxy in
                if state.conflictedPaths.isEmpty {
                    resolvedState(palette: palette)
                } else {
                    HStack(spacing: 0) {
                        conflictList(palette: palette)
                            .frame(width: min(250, max(196, proxy.size.width * 0.21)))
                        Rectangle().fill(palette.divider).frame(width: 1)
                        conflictEditor(compact: proxy.size.width < 920, palette: palette)
                    }
                }
            }

            Rectangle().fill(palette.divider).frame(height: 1)
            operationControls(palette: palette)
        }
        .background(palette.surface)
        .confirmationDialog(
            L10n.text("conflict.abort.confirm.title"),
            isPresented: $isConfirmingAbort,
            titleVisibility: .visible
        ) {
            Button(L10n.text("conflict.abort.confirm.action"), role: .destructive) {
                Task { await model.abortRepositoryOperation() }
            }
            Button(L10n.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("conflict.abort.confirm.message"))
        }
    }

    private func operationHeader(palette: AppPalette) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.warning.opacity(0.13))
                Image(gattoSymbol: "arrow.triangle.branch")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.warning)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(L10n.text("conflict.title"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text(L10n.text(operationTitleKey))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.warning)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(palette.warning.opacity(0.11))
                        .clipShape(Capsule())
                }
                if let progress = state.progress {
                    HStack(spacing: 8) {
                        ProgressView(value: Double(progress.current), total: Double(progress.total))
                            .progressViewStyle(.linear)
                            .tint(palette.warning)
                            .frame(width: 126)
                        Text(L10n.format("conflict.progress", progress.current, progress.total))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.subtleInk)
                    }
                }
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(state.conflictedPaths.isEmpty ? palette.success : palette.warning)
                    .frame(width: 7, height: 7)
                Text(L10n.format("conflict.remaining", state.conflictedPaths.count))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.ink)
            }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(palette.raisedSurface)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .frame(height: 70)
    }

    private func conflictList(palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("conflict.files"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
                CountBadge(count: state.conflictedPaths.count, emphasized: false)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)

            Rectangle().fill(palette.divider).frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(state.conflictedPaths, id: \.self) { path in
                        Button {
                            model.selectConflict(path: path)
                        } label: {
                            HStack(spacing: 9) {
                                Image(gattoSymbol: "exclamationmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(palette.warning)
                                    .frame(width: 24, height: 24)
                                    .background(palette.warning.opacity(model.selectedConflictPath == path ? 0.15 : 0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(palette.ink)
                                        .lineLimit(1)
                                    Text((path as NSString).deletingLastPathComponent.isEmpty
                                         ? L10n.text("path.repository_root")
                                         : (path as NSString).deletingLastPathComponent)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(palette.subtleInk)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 11)
                            .frame(height: 48)
                            .contentShape(Rectangle())
                            .background(model.selectedConflictPath == path ? palette.warning.opacity(0.09) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
        .background(palette.raisedSurface.opacity(0.28))
    }

    @ViewBuilder
    private func conflictEditor(compact: Bool, palette: AppPalette) -> some View {
        if model.isLoadingConflictDocument {
            GattoLoadingState(text: L10n.text("conflict.loading"))
        } else if let document = model.conflictDocument {
            VStack(spacing: 0) {
                resolutionToolbar(document: document, palette: palette)
                Rectangle().fill(palette.divider).frame(height: 1)

                if document.isBinary {
                    binaryState(palette: palette)
                } else if compact {
                    compactEditor(document: document, palette: palette)
                } else {
                    fullEditor(document: document, palette: palette)
                }
            }
        }
    }

    private func resolutionToolbar(document: ConflictFileDocument, palette: AppPalette) -> some View {
        HStack(spacing: 10) {
            Image(gattoSymbol: "doc.text")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.primary)
                .frame(width: 28, height: 28)
                .background(palette.primarySoft)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: document.path).lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text(document.path)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(palette.subtleInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(L10n.text("conflict.workspace.mode"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.subtleInk)
        }
        .padding(.horizontal, 13)
        .frame(height: 52)
    }

    private func fullEditor(document: ConflictFileDocument, palette: AppPalette) -> some View {
        HStack(spacing: 0) {
            sourceEditor(document: document, palette: palette)
                .frame(maxWidth: .infinity)
            ZStack {
                Rectangle().fill(palette.divider).frame(width: 1)
                Image(gattoSymbol: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(palette.subtleInk)
                    .frame(width: 22, height: 22)
                    .background(palette.surface)
                    .clipShape(Circle())
                    .overlay { Circle().stroke(palette.divider, lineWidth: 1) }
            }
            .frame(width: 1)
            resultEditor(palette: palette)
                .frame(maxWidth: .infinity)
        }
    }

    private func compactEditor(document: ConflictFileDocument, palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            sourceEditor(document: document, palette: palette)
                .frame(maxHeight: .infinity)
            Rectangle().fill(palette.divider).frame(height: 1)
            resultEditor(palette: palette)
                .frame(maxHeight: .infinity)
        }
    }

    private func sourceEditor(document: ConflictFileDocument, palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(L10n.text("conflict.source.title"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
                Picker("", selection: $selectedSource) {
                    ForEach(ConflictSource.allCases) { source in
                        Text(L10n.text(source.titleKey)).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 270)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            Rectangle().fill(palette.divider).frame(height: 1)

            ConflictSourcePane(
                titleKey: selectedSource.titleKey,
                text: selectedSource.text(in: document),
                fileName: document.path,
                palette: palette,
                showsHeader: false
            )

            Rectangle().fill(palette.divider).frame(height: 1)

            HStack {
                GattoLabel(L10n.text(selectedSource.titleKey), systemImage: selectedSource.symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.mutedInk)
                Spacer()
                if selectedSource != .base {
                    Button {
                        Task {
                            await model.acceptConflictSide(selectedSource == .ours ? .ours : .theirs)
                        }
                    } label: {
                        GattoLabel(
                            L10n.text(
                                selectedSource == .ours
                                    ? "conflict.action.accept_ours"
                                    : "conflict.action.accept_theirs"
                            ),
                            systemImage: "arrow.right"
                        )
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.activeOperation != nil)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultEditor(palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("conflict.side.result"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
                GattoLabel(
                    L10n.text(
                        model.conflictResolutionContainsMarkers
                            ? "conflict.markers_remaining"
                            : "conflict.result.ready"
                    ),
                    systemImage: model.conflictResolutionContainsMarkers
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.circle.fill"
                )
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(model.conflictResolutionContainsMarkers ? palette.warning : palette.success)
                .padding(.horizontal, 8)
                .frame(height: 23)
                .background(
                    (model.conflictResolutionContainsMarkers ? palette.warning : palette.success).opacity(0.10)
                )
                .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            Rectangle().fill(palette.divider).frame(height: 1)

            CodeTextEditorView(
                text: $model.conflictResolutionText,
                fileName: model.selectedConflictPath ?? "conflict.txt"
            )

            Rectangle().fill(palette.divider).frame(height: 1)

            HStack(spacing: 12) {
                GattoLabel(
                    CodeSyntax.languageName(for: model.selectedConflictPath ?? "conflict.txt"),
                    systemImage: "curlybraces.square"
                )
                Text("UTF-8")
                Text("LF")
                Text(
                    L10n.format(
                        "code_surface.lines",
                        model.conflictResolutionText.split(
                            separator: "\n",
                            omittingEmptySubsequences: false
                        ).count
                    )
                )
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                Spacer()
                Button(L10n.text("conflict.action.mark_resolved")) {
                    Task { await model.saveConflictResolution() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.conflictResolutionContainsMarkers || model.activeOperation != nil)
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(palette.subtleInk)
            .padding(.horizontal, 12)
            .frame(height: 48)
        }
    }

    private func binaryState(palette: AppPalette) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(palette.raisedSurface).frame(width: 62, height: 62)
                Image(gattoSymbol: "doc.badge.gearshape")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(palette.mutedInk)
            }
            Text(L10n.text("conflict.binary.title"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text(L10n.text("conflict.binary.body"))
                .font(.system(size: 11.5))
                .foregroundStyle(palette.subtleInk)
            HStack(spacing: 10) {
                Button(L10n.text("conflict.action.accept_ours")) {
                    Task { await model.acceptConflictSide(.ours) }
                }
                .buttonStyle(SecondaryButtonStyle())
                Button(L10n.text("conflict.action.accept_theirs")) {
                    Task { await model.acceptConflictSide(.theirs) }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resolvedState(palette: AppPalette) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(palette.successSoft).frame(width: 68, height: 68)
                Image(gattoSymbol: "checkmark")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(palette.success)
            }
            Text(L10n.text("conflict.all_resolved"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func operationControls(palette: AppPalette) -> some View {
        HStack(spacing: 8) {
            Button(role: .destructive) {
                isConfirmingAbort = true
            } label: {
                GattoLabel(L10n.text("conflict.action.abort"), systemImage: "xmark")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!state.kind.supportsAbort || model.activeOperation != nil)

            Spacer()

            if state.kind.supportsSkip {
                Button {
                    Task { await model.skipRepositoryOperation() }
                } label: {
                    Text(L10n.text("conflict.action.skip"))
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.activeOperation != nil)
            }

            Button {
                Task { await model.continueRepositoryOperation() }
            } label: {
                HStack(spacing: 6) {
                    if model.activeOperation == .continueConflictOperation {
                        ProgressView().controlSize(.small)
                    }
                    Text(L10n.text("conflict.action.continue"))
                    Image(gattoSymbol: "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!state.canContinue || model.activeOperation != nil)
            .opacity(!state.canContinue || model.activeOperation != nil ? 0.45 : 1)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
    }

    private var operationTitleKey: String {
        switch state.kind {
        case .merge: "conflict.operation.merge"
        case .rebase: "conflict.operation.rebase"
        case .cherryPick: "conflict.operation.cherry_pick"
        case .revert: "conflict.operation.revert"
        case .unknown: "conflict.operation.unknown"
        }
    }

}

private struct ConflictSourcePane: View {
    let titleKey: String
    let text: String?
    let fileName: String
    let palette: AppPalette
    var showsHeader = true

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HStack {
                    Text(L10n.text(titleKey))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.mutedInk)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                Rectangle().fill(palette.divider).frame(height: 1)
            }
            if let text {
                CodeDocumentView(
                    content: text,
                    fileName: fileName,
                    showsStatusBar: false
                )
            } else {
                Text(L10n.text("conflict.side.missing"))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.subtleInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private enum ConflictSource: String, CaseIterable, Identifiable {
    case base
    case ours
    case theirs

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .base: "conflict.side.base"
        case .ours: "conflict.side.ours"
        case .theirs: "conflict.side.theirs"
        }
    }

    var symbol: String {
        switch self {
        case .base: "circle.dashed"
        case .ours: "arrow.turn.up.left"
        case .theirs: "arrow.turn.up.right"
        }
    }

    func text(in document: ConflictFileDocument) -> String? {
        switch self {
        case .base: document.base
        case .ours: document.ours
        case .theirs: document.theirs
        }
    }
}
