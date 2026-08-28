import SwiftUI

struct GitHubActionsCenterView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue
    @State private var inAppBrowserPage: InAppBrowserPage?

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            workflowBar(palette)
            Rectangle().fill(palette.divider).frame(height: 1)

            if model.isLoadingGitHubActions, model.githubActionRuns.isEmpty {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L10n.text("github.actions.loading"))
                        .font(font(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.mutedInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.githubActionRuns.isEmpty {
                emptyState(palette)
            } else {
                GeometryReader { proxy in
                    let listWidth = min(max(280, proxy.size.width * 0.36), 360)
                    HStack(spacing: 0) {
                        runList(palette)
                            .frame(width: listWidth)
                        Rectangle().fill(palette.divider).frame(width: 1)
                        runDetail(palette)
                    }
                }
            }
        }
        .sheet(item: $inAppBrowserPage) { page in
            InAppBrowserSheet(url: page.url, persistent: page.persistent)
                .frame(minWidth: 820, minHeight: 640)
        }
        .onAppear {
            if model.githubActionRuns.isEmpty {
                model.refreshGitHubActions()
            }
        }
    }

    private func workflowBar(_ palette: AppPalette) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(gattoSymbol: "play.circle.fill")
                    .foregroundStyle(palette.accent)
                Text(L10n.text("github.actions.title"))
                    .font(font(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    workflowButton(nil, title: L10n.text("github.actions.workflow.all"), palette: palette)
                    ForEach(model.githubActionWorkflows) { workflow in
                        workflowButton(workflow, title: workflow.name, palette: palette)
                    }
                }
            }

            Spacer(minLength: 8)

            if let error = model.githubActionsError {
                Image(gattoSymbol: "exclamationmark.triangle.fill")
                    .foregroundStyle(palette.danger)
                    .help(error)
            }
            ToolbarIconButton(
                systemName: "arrow.clockwise",
                helpKey: "action.refresh",
                isActive: model.isLoadingGitHubActions,
                isDisabled: model.isLoadingGitHubActions
            ) {
                model.refreshGitHubActions()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(theme == .softGlass ? palette.surface.opacity(0.12) : palette.surface)
    }

    private func workflowButton(
        _ workflow: GitHubActionsWorkflow?,
        title: String,
        palette: AppPalette
    ) -> some View {
        let selected = model.selectedGitHubActionWorkflow?.id == workflow?.id
        return Button {
            model.selectGitHubActionWorkflow(workflow)
        } label: {
            Text(title)
                .font(font(size: 10.5, weight: .semibold))
                .foregroundStyle(selected ? palette.primary : palette.mutedInk)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(selected ? palette.primarySoft : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: theme == .console ? 4 : 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func runList(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("github.actions.runs"))
                    .font(font(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.mutedInk)
                Spacer()
                Text("\(model.displayedGitHubActionRuns.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.subtleInk)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            Rectangle().fill(palette.divider).frame(height: 1)

            ScrollView {
                LazyVStack(spacing: theme == .console ? 2 : 4) {
                    ForEach(model.displayedGitHubActionRuns) { run in
                        GitHubActionsRunRow(
                            run: run,
                            selected: model.selectedGitHubActionRun?.id == run.id,
                            theme: theme
                        ) {
                            model.selectGitHubActionRun(run)
                        }
                    }
                }
                .padding(7)
            }
        }
        .background(theme == .softGlass ? palette.sidebar.opacity(0.14) : palette.sidebar)
    }

    @ViewBuilder
    private func runDetail(_ palette: AppPalette) -> some View {
        if let run = model.selectedGitHubActionRun {
            VStack(spacing: 0) {
                runHeader(run, palette: palette)
                Rectangle().fill(palette.divider).frame(height: 1)

                if model.isLoadingGitHubActionDetail, model.githubActionRunDetail == nil {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(L10n.text("github.actions.detail.loading"))
                            .font(font(size: 11.5, weight: .medium))
                            .foregroundStyle(palette.mutedInk)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let detail = model.githubActionRunDetail {
                    detailContent(detail, palette: palette)
                } else if let error = model.githubActionsError {
                    errorState(error, palette: palette)
                }
            }
        } else {
            VStack(spacing: 9) {
                Image(gattoSymbol: "play.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(palette.subtleInk)
                Text(L10n.text("github.actions.selection.empty"))
                    .font(font(size: 12, weight: .medium))
                    .foregroundStyle(palette.mutedInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func runHeader(_ run: GitHubActionsRun, palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            CheckStateGlyph(status: run.status, conclusion: run.conclusion)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(run.displayTitle)
                        .font(font(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text("#\(run.runNumber)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                }
                HStack(spacing: 7) {
                    Text(run.name)
                    Text("·")
                    Text(run.branch ?? L10n.text("github.actions.branch.unknown"))
                    Text("·")
                    Text(run.event)
                    Text("·")
                    Text(run.actor)
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.subtleInk)
                .lineLimit(1)
            }
            Spacer(minLength: 8)

            Button {
                inAppBrowserPage = InAppBrowserPage(url: run.webURL, persistent: true)
            } label: {
                Image(gattoSymbol: "arrow.up.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.primary)
            .help(L10n.text("github.review.open_github"))

            if isActive(run.status) {
                Button(L10n.text("github.actions.action.cancel"), role: .destructive) {
                    model.cancelSelectedGitHubAction()
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.activeGitHubOperation != nil)
            } else {
                Menu {
                    Button(L10n.text("github.actions.action.rerun_all")) {
                        model.rerunSelectedGitHubAction(failedOnly: false)
                    }
                    if run.conclusion == "failure" {
                        Button(L10n.text("github.actions.action.rerun_failed")) {
                            model.rerunSelectedGitHubAction(failedOnly: true)
                        }
                    }
                } label: {
                    GattoLabel(L10n.text("github.actions.action.rerun"), systemImage: "arrow.clockwise")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.activeGitHubOperation != nil)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(theme == .softGlass ? palette.surface.opacity(0.14) : palette.surface)
    }

    private func detailContent(_ detail: GitHubActionsRunDetail, palette: AppPalette) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionTitle("github.actions.jobs", count: detail.jobs.count, palette: palette)
                    ForEach(detail.jobs) { job in
                        GitHubActionsJobView(job: job, theme: theme)
                    }
                }

                if !detail.artifacts.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionTitle("github.actions.artifacts", count: detail.artifacts.count, palette: palette)
                        ForEach(detail.artifacts) { artifact in
                            HStack(spacing: 10) {
                                Image(gattoSymbol: "shippingbox")
                                    .foregroundStyle(palette.accent)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(artifact.name)
                                        .font(font(size: 11.5, weight: .medium))
                                        .foregroundStyle(palette.ink)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(artifact.sizeInBytes), countStyle: .file))
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(palette.subtleInk)
                                }
                                Spacer()
                                if artifact.isExpired {
                                    Text(L10n.text("github.actions.artifact.expired"))
                                        .font(font(size: 9.5, weight: .semibold))
                                        .foregroundStyle(palette.subtleInk)
                                } else {
                                    Button(L10n.text("github.actions.action.download")) {
                                        model.chooseActionArtifactDestination(artifact)
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                    .disabled(model.activeGitHubOperation != nil)
                                }
                            }
                            .padding(.horizontal, 11)
                            .frame(minHeight: 52)
                            Rectangle().fill(palette.divider).frame(height: 1).padding(.leading, 42)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("github.actions.log", count: nil, palette: palette)
                    if let log = detail.log, !log.isEmpty {
                        CodeDocumentView(
                            content: log,
                            fileName: "workflow.log",
                            syntaxHighlighting: false
                        )
                        .frame(height: 286)
                        .clipShape(RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous)
                                .stroke(palette.divider, lineWidth: 1)
                        }
                    } else if let error = detail.logError {
                        GattoLabel(error, systemImage: "exclamationmark.triangle.fill")
                            .font(font(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.warning)
                            .textSelection(.enabled)
                    } else {
                        Text(L10n.text("github.actions.log.empty"))
                            .font(font(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.subtleInk)
                    }
                }
            }
            .padding(16)
        }
    }

    private func sectionTitle(_ key: String, count: Int?, palette: AppPalette) -> some View {
        HStack(spacing: 7) {
            Text(L10n.text(key))
                .font(font(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.mutedInk)
            if let count {
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.subtleInk)
            }
            Spacer()
        }
        .frame(height: 32)
    }

    private func emptyState(_ palette: AppPalette) -> some View {
        VStack(spacing: 11) {
            Image(gattoSymbol: "play.circle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            Text(L10n.text("github.actions.empty"))
                .font(font(size: 12.5, weight: .medium))
                .foregroundStyle(palette.mutedInk)
            if let error = model.githubActionsError {
                Text(error)
                    .font(font(size: 10.5, weight: .regular))
                    .foregroundStyle(palette.danger)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ error: String, palette: AppPalette) -> some View {
        VStack(spacing: 11) {
            Image(gattoSymbol: "exclamationmark.triangle.fill")
                .font(.system(size: 21))
                .foregroundStyle(palette.danger)
            Text(error)
                .font(font(size: 11.5, weight: .medium))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Button(L10n.text("github.action.retry")) {
                model.selectGitHubActionRun(model.selectedGitHubActionRun)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func isActive(_ status: String) -> Bool {
        ["queued", "in_progress", "waiting", "requested", "pending"].contains(status.lowercased())
    }

    private func font(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: theme == .console ? .monospaced : .default)
    }
}

private struct GitHubActionsRunRow: View {
    let run: GitHubActionsRun
    let selected: Bool
    let theme: AppVisualTheme
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                CheckStateGlyph(status: run.status, conclusion: run.conclusion)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 5) {
                    Text(run.displayTitle)
                        .font(.system(size: 11.5, weight: .semibold, design: theme == .console ? .monospaced : .default))
                        .foregroundStyle(palette.ink)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text("#\(run.runNumber)")
                        if let branch = run.branch { Text(branch) }
                        Text(run.updatedAt.formatted(.relative(presentation: .numeric)))
                    }
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.subtleInk)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? palette.primarySoft : (hovering ? palette.raisedSurface : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: theme == .console ? 4 : 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct GitHubActionsJobView: View {
    let job: GitHubActionsJob
    let theme: AppVisualTheme
    @Environment(\.colorScheme) private var colorScheme
    @State private var expanded = true

    var body: some View {
        let palette = AppPalette(colorScheme)
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 0) {
                ForEach(job.steps) { step in
                    HStack(spacing: 9) {
                        CheckStateGlyph(status: step.status, conclusion: step.conclusion)
                            .scaleEffect(0.78)
                        Text(step.name)
                            .font(.system(size: 10.5, weight: .medium, design: theme == .console ? .monospaced : .default))
                            .foregroundStyle(palette.ink)
                        Spacer()
                        Text(L10n.text("github.actions.status.\((step.conclusion ?? step.status).lowercased())"))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(palette.subtleInk)
                    }
                    .padding(.leading, 25)
                    .padding(.trailing, 10)
                    .frame(height: 32)
                }
            }
        } label: {
            HStack(spacing: 9) {
                CheckStateGlyph(status: job.status, conclusion: job.conclusion)
                Text(job.name)
                    .font(.system(size: 11.5, weight: .semibold, design: theme == .console ? .monospaced : .default))
                    .foregroundStyle(palette.ink)
                Spacer()
                Text(L10n.text("github.actions.status.\((job.conclusion ?? job.status).lowercased())"))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(palette.subtleInk)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.divider).frame(height: 1)
        }
    }
}
