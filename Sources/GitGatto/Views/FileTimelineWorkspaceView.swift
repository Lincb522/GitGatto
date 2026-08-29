import SwiftUI

struct FileTimelineWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue
    @State private var confirmsRestore = false

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            commandBar(palette)
            Rectangle().fill(palette.divider).frame(height: 1)
            GeometryReader { proxy in
                let fileWidth = min(272, max(200, proxy.size.width * 0.25))
                let revisionWidth = min(310, max(232, proxy.size.width * 0.28))
                HStack(spacing: 0) {
                    fileNavigator(palette)
                        .frame(width: fileWidth)
                    Rectangle().fill(palette.divider).frame(width: 1)
                    revisionTimeline(palette)
                        .frame(width: revisionWidth)
                    Rectangle().fill(palette.divider).frame(width: 1)
                    fileInspector(palette)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(theme == .softGlass ? Color.clear : palette.background)
        .task(id: model.snapshot?.rootURL.standardizedFileURL.path) {
            if model.repositoryFiles.isEmpty, model.snapshot != nil {
                model.refreshRepositoryFiles()
            }
        }
        .confirmationDialog(
            L10n.text("file_timeline.restore.confirm.title"),
            isPresented: $confirmsRestore,
            titleVisibility: .visible
        ) {
            Button(L10n.text("file_timeline.restore.action"), role: .destructive) {
                Task { await model.restoreSelectedFileRevision() }
            }
            Button(L10n.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(
                L10n.format(
                    "file_timeline.restore.confirm.message",
                    model.selectedFileRevision?.shortHash ?? ""
                )
            )
        }
    }

    private func commandBar(_ palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            Text(L10n.text("file_timeline.title"))
                .font(font(size: 15, weight: .semibold))
                .foregroundStyle(palette.ink)
            if !model.repositoryFiles.isEmpty {
                CountBadge(count: model.repositoryFiles.count)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Image(gattoSymbol: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
                TextField(L10n.text("file_timeline.search"), text: $model.fileTimelineQuery)
                    .textFieldStyle(.plain)
                    .font(font(size: 11.5, weight: .regular))
            }
            .padding(.horizontal, 10)
            .frame(width: 240, height: 32)
            .background(palette.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous)
                    .stroke(palette.divider, lineWidth: 1)
            }
            ToolbarIconButton(
                systemName: "arrow.clockwise",
                helpKey: "action.refresh",
                isActive: model.isLoadingRepositoryFiles,
                isDisabled: model.isLoadingRepositoryFiles
            ) {
                model.refreshRepositoryFiles()
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .background(theme == .softGlass ? palette.surface.opacity(0.16) : palette.surface)
    }

    private func fileNavigator(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("file_timeline.files"))
                    .font(font(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.mutedInk)
                Spacer()
                Text("\(model.filteredRepositoryFiles.count)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.subtleInk)
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            Rectangle().fill(palette.divider).frame(height: 1)

            if model.isLoadingRepositoryFiles, model.repositoryFiles.isEmpty {
                GattoLoadingState(text: L10n.text("loading.generic"))
            } else if model.filteredRepositoryFiles.isEmpty {
                timelineEmpty("doc", key: "file_timeline.files.empty", palette: palette)
            } else {
                ScrollView {
                    LazyVStack(spacing: theme == .console ? 1 : 2) {
                        ForEach(model.filteredRepositoryFiles) { file in
                            FileTimelineFileRow(
                                file: file,
                                selected: model.selectedRepositoryFile?.id == file.id,
                                theme: theme
                            ) {
                                model.selectRepositoryFile(file)
                            }
                        }
                    }
                    .padding(7)
                }
            }
        }
        .background(theme == .softGlass ? palette.sidebar.opacity(0.14) : palette.sidebar)
    }

    private func revisionTimeline(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("file_timeline.versions"))
                    .font(font(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.mutedInk)
                Spacer()
                if !model.fileRevisions.isEmpty {
                    Text(L10n.format("file_timeline.version_count", model.fileRevisions.count))
                        .font(font(size: 9.5, weight: .medium))
                        .foregroundStyle(palette.subtleInk)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            Rectangle().fill(palette.divider).frame(height: 1)

            if model.selectedRepositoryFile == nil {
                timelineEmpty("clock", key: "file_timeline.select_file", palette: palette)
            } else if model.isLoadingFileTimeline, model.fileRevisions.isEmpty {
                GattoLoadingState(text: L10n.text("loading.generic"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        FileTimelineCurrentRow(
                            selected: model.selectedFileRevision == nil,
                            theme: theme
                        ) {
                            model.selectFileRevision(nil)
                        }
                        ForEach(model.fileRevisions) { revision in
                            FileTimelineRevisionRow(
                                revision: revision,
                                selected: model.selectedFileRevision?.id == revision.id,
                                theme: theme
                            ) {
                                model.selectFileRevision(revision)
                            }
                        }
                    }
                    .padding(.vertical, 7)
                }
            }
        }
        .background(theme == .softGlass ? palette.surface.opacity(0.10) : palette.surface)
    }

    @ViewBuilder
    private func fileInspector(_ palette: AppPalette) -> some View {
        if let file = model.selectedRepositoryFile {
            VStack(spacing: 0) {
                fileHeader(file, palette: palette)
                Rectangle().fill(palette.divider).frame(height: 1)
                if model.isLoadingFileTimeline, model.fileVersionDocument == nil {
                    GattoLoadingState(text: L10n.text("loading.generic"))
                } else {
                    detailContent(palette)
                }
            }
        } else {
            timelineEmpty("history.file", key: "file_timeline.select_file", palette: palette)
        }
    }

    private func fileHeader(_ file: RepositoryFileRecord, palette: AppPalette) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous)
                        .fill(palette.primarySoft)
                    Image(gattoSymbol: FileTimelineFileRow.icon(for: file.fileExtension))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.primary)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(font(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(model.fileVersionDocument?.path ?? file.path)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if let revision = model.selectedFileRevision {
                    Button {
                        model.copySelectedFileRevisionHash()
                    } label: {
                        Text(revision.shortHash)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.primary)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(palette.primarySoft)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.text("file_timeline.copy_hash"))
                    Button(L10n.text("file_timeline.restore.action")) {
                        confirmsRestore = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            HStack {
                Picker("", selection: $model.fileTimelineDetailMode) {
                    ForEach(FileTimelineDetailMode.allCases) { mode in
                        Text(L10n.text("file_timeline.mode.\(mode.rawValue)"))
                            .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 270)
                if let revision = model.selectedFileRevision {
                    Text(revision.subject)
                        .font(font(size: 9.5, weight: .semibold))
                        .foregroundStyle(palette.mutedInk)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(revision.author)
                    Text("·")
                    Text(revision.date.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Spacer()
                    Text(L10n.text("file_timeline.working_copy"))
                }
            }
            .font(font(size: 9.5, weight: .medium))
            .foregroundStyle(palette.subtleInk)
        }
        .padding(.horizontal, 14)
        .frame(height: 88)
        .background(theme == .softGlass ? palette.surface.opacity(0.14) : palette.surface)
    }

    @ViewBuilder
    private func detailContent(_ palette: AppPalette) -> some View {
        switch model.fileTimelineDetailMode {
        case .content:
            if let document = model.fileVersionDocument {
                if let previewURL = document.previewURL,
                   RepositoryMediaKind(fileName: document.path) != nil {
                    RepositoryMediaPreview(
                        url: previewURL,
                        fileName: document.path,
                        svgSource: document.content
                    )
                } else if document.isBinary {
                    timelineEmpty("doc.badge.ellipsis", key: "file_timeline.binary", palette: palette)
                } else {
                    CodeDocumentView(
                        content: document.content ?? "",
                        fileName: document.path
                    )
                }
            } else {
                timelineEmpty("doc.text", key: "file_timeline.content.empty", palette: palette)
            }
        case .changes:
            if let document = model.fileVersionDocument, !document.diff.lines.isEmpty {
                DiffCodeView(document: document.diff)
            } else {
                timelineEmpty("checkmark", key: "file_timeline.changes.empty", palette: palette)
            }
        case .blame:
            if model.fileBlameLines.isEmpty {
                timelineEmpty("person.text.rectangle", key: "file_timeline.blame.empty", palette: palette)
            } else {
                FileBlameView(
                    lines: model.fileBlameLines,
                    revisions: model.fileRevisions,
                    theme: theme,
                    selectRevision: model.selectFileRevision
                )
            }
        }
    }

    private func timelineEmpty(_ image: String, key: String, palette: AppPalette) -> some View {
        VStack(spacing: 8) {
            Image(gattoSymbol: image)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            Text(L10n.text(key))
                .font(font(size: 11.5, weight: .medium))
                .foregroundStyle(palette.mutedInk)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func font(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: theme == .console ? .monospaced : .default)
    }
}

private struct FileTimelineFileRow: View {
    let file: RepositoryFileRecord
    let selected: Bool
    let theme: AppVisualTheme
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 9) {
                Image(gattoSymbol: Self.icon(for: file.fileExtension))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(selected ? palette.primary : palette.mutedInk)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(.system(size: 11.5, weight: selected ? .semibold : .medium, design: theme == .console ? .monospaced : .default))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(file.directory.isEmpty ? L10n.text("file_timeline.repository_root") : file.directory)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 9)
            .frame(height: 46)
            .background(selected ? palette.primarySoft : (hovering ? palette.raisedSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: theme == .console ? 4 : 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static func icon(for extensionName: String) -> String {
        if let kind = RepositoryMediaKind(fileName: "file.\(extensionName)") {
            return kind == .video ? "play.circle" : "photo"
        }
        switch extensionName {
        case "swift", "m", "mm", "c", "h", "cpp", "rs", "go", "py", "js", "ts", "tsx", "jsx":
            return "chevron.left.forwardslash.chevron.right"
        case "md", "txt", "rst": return "doc.richtext"
        case "json", "yml", "yaml", "toml", "plist": return "gearshape"
        default: return "doc"
        }
    }
}

private struct FileTimelineCurrentRow: View {
    let selected: Bool
    let theme: AppVisualTheme
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(palette.primary).frame(width: 9, height: 9)
                    Circle().stroke(palette.primarySoft, lineWidth: 4).frame(width: 17, height: 17)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("file_timeline.working_copy"))
                        .font(.system(size: 11.5, weight: .semibold, design: theme == .console ? .monospaced : .default))
                        .foregroundStyle(palette.ink)
                    Text(L10n.text("file_timeline.current_state"))
                        .font(.system(size: 9.5, design: theme == .console ? .monospaced : .default))
                        .foregroundStyle(palette.subtleInk)
                }
                Spacer()
            }
            .padding(.horizontal, 13)
            .frame(height: 52)
            .background(selected ? palette.primarySoft : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct FileTimelineRevisionRow: View {
    let revision: FileRevisionRecord
    let selected: Bool
    let theme: AppVisualTheme
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 0) {
                    Rectangle().fill(palette.divider).frame(width: 1, height: 12)
                    Circle()
                        .fill(selected ? palette.primary : palette.raisedSurface)
                        .overlay { Circle().stroke(selected ? palette.primary : palette.subtleInk, lineWidth: 1) }
                        .frame(width: 9, height: 9)
                    Rectangle().fill(palette.divider).frame(width: 1, height: 42)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(revision.subject)
                        .font(.system(size: 11.5, weight: selected ? .semibold : .medium, design: theme == .console ? .monospaced : .default))
                        .foregroundStyle(palette.ink)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(revision.shortHash)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(selected ? palette.primary : palette.mutedInk)
                        Text(revision.author).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(revision.date.formatted(.relative(presentation: .named)))
                    }
                    .font(.system(size: 9, design: theme == .console ? .monospaced : .default))
                    .foregroundStyle(palette.subtleInk)
                }
                .padding(.vertical, 10)
                Spacer(minLength: 2)
            }
            .padding(.horizontal, 13)
            .background(selected ? palette.primarySoft : (hovering ? palette.raisedSurface.opacity(0.72) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct FileBlameView: View {
    let lines: [FileBlameLine]
    let revisions: [FileRevisionRecord]
    let theme: AppVisualTheme
    let selectRevision: (FileRevisionRecord?) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        let startsGroup = index == 0 || lines[index - 1].commitHash != line.commitHash
                        HStack(alignment: .top, spacing: 0) {
                            Group {
                                if startsGroup {
                                    Button {
                                        selectRevision(revisions.first { $0.hash == line.commitHash })
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 5) {
                                                Circle()
                                                    .fill(color(for: line.commitHash, palette: palette))
                                                    .frame(width: 6, height: 6)
                                                Text(line.isUncommitted ? L10n.text("file_timeline.uncommitted") : line.shortHash)
                                                    .fontWeight(.semibold)
                                            }
                                            Text(line.author).lineLimit(1)
                                            Text(line.summary).lineLimit(1)
                                        }
                                        .foregroundStyle(line.isUncommitted ? palette.warning : palette.mutedInk)
                                        .frame(width: 158, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help(line.authorEmail)
                                } else {
                                    Color.clear.frame(width: 158, height: 20)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, startsGroup ? 5 : 0)
                            .background(palette.sidebar.opacity(0.52))

                            Text("\(line.finalLineNumber)")
                                .foregroundStyle(palette.subtleInk)
                                .frame(width: 46, alignment: .trailing)
                                .padding(.trailing, 11)
                                .padding(.top, startsGroup ? 5 : 0)
                            SyntaxHighlightedCodeLine(
                                text: line.text,
                                fileName: line.sourcePath
                            )
                                .padding(.leading, 11)
                                .padding(.top, startsGroup ? 5 : 0)
                        }
                        .font(.system(size: 10.5, design: .monospaced))
                        .frame(minHeight: startsGroup ? 44 : 21, alignment: .top)
                        .fixedSize(horizontal: true, vertical: false)
                        .background(index.isMultiple(of: 2) ? palette.surface.opacity(0.16) : Color.clear)
                    }
                }
                .frame(
                    minWidth: proxy.size.width,
                    minHeight: proxy.size.height,
                    alignment: .topLeading
                )
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.topLeading)
        }
        .background(theme == .softGlass ? palette.background.opacity(0.18) : palette.background)
    }

    private func color(for hash: String, palette: AppPalette) -> Color {
        guard let value = Int(hash.prefix(2), radix: 16) else { return palette.warning }
        return switch value % 4 {
        case 0: palette.primary
        case 1: palette.accent
        case 2: palette.success
        default: palette.warning
        }
    }
}
