import AppKit
import SwiftUI

struct RegressionInvestigationWorkspaceView: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue
    @State private var showsComposer = false
    @State private var showsCleanupConfirmation = false
    @State private var showsPublishConfirmation = false
    @State private var showsQuickGuide = false

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            commandBar(palette)
            Rectangle().fill(palette.divider).frame(height: 1)
            if model.currentRepositoryRegressionInvestigations.isEmpty || showsComposer {
                setupWorkspace(palette)
            } else {
                GeometryReader { proxy in
                    if proxy.size.width < 820 {
                        VStack(spacing: 0) {
                            compactInvestigationPicker(palette)
                            Rectangle().fill(palette.divider).frame(height: 1)
                            if let investigation = model.selectedRegressionInvestigation {
                                investigationDetail(investigation, palette: palette)
                            }
                        }
                    } else {
                        HSplitView {
                            investigationList(palette)
                                .frame(minWidth: 250, idealWidth: 286, maxWidth: 340)
                            if let investigation = model.selectedRegressionInvestigation {
                                investigationDetail(investigation, palette: palette)
                                    .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                }
            }
        }
        .background(theme == .softGlass ? Color.clear : palette.background)
        .task(id: model.snapshot?.rootURL.standardizedFileURL.path) {
            if let investigation = model.currentRepositoryRegressionInvestigations.first {
                model.selectRegressionInvestigation(investigation)
                showsComposer = false
            } else {
                showsComposer = true
            }
#if DEBUG
            if ProcessInfo.processInfo.environment["GITGATTO_QUICK_GUIDE_PREVIEW"] == "regression" {
                try? await Task.sleep(for: .milliseconds(250))
                showsQuickGuide = true
            }
#endif
        }
        .confirmationDialog(
            L10n.text("regression.cleanup.confirm.title"),
            isPresented: $showsCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.text("regression.action.cleanup"), role: .destructive) {
                model.cleanupRegressionInvestigation()
            }
            Button(L10n.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("regression.cleanup.confirm.message"))
        }
        .confirmationDialog(
            L10n.text("regression.publish.confirm.title"),
            isPresented: $showsPublishConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.text("regression.action.publish")) {
                model.publishRegressionFix()
            }
            Button(L10n.text("action.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("regression.publish.confirm.message"))
        }
    }

    private func commandBar(_ palette: AppPalette) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                GattoIcon(symbol: "record.circle", size: 18)
                    .foregroundStyle(palette.accent)
                Text(L10n.text("regression.title"))
                    .font(font(15, weight: .semibold))
                    .foregroundStyle(palette.ink)
                if !model.currentRepositoryRegressionInvestigations.isEmpty {
                    CountBadge(count: model.currentRepositoryRegressionInvestigations.count, emphasized: false)
                }
            }
            Spacer()
            Button {
                showsQuickGuide = true
            } label: {
                GattoLabel(L10n.text("workspace.guide.open"), systemImage: "info.circle")
            }
            .buttonStyle(SecondaryButtonStyle())
            .sheet(isPresented: $showsQuickGuide) {
                WorkspaceQuickGuideSheet(guide: .regression)
            }
            if let investigation = model.selectedRegressionInvestigation, !showsComposer {
                statusBadge(investigation.status, palette: palette)
                if investigation.status == .running {
                    Button {
                        model.pauseRegressionInvestigation()
                    } label: {
                        GattoLabel(L10n.text("regression.action.pause"), systemImage: "pause")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else if investigation.status.canResume {
                    Button {
                        model.resumeRegressionInvestigation()
                    } label: {
                        GattoLabel(L10n.text("regression.action.resume"), systemImage: "play.circle")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            Button {
                showsComposer.toggle()
            } label: {
                GattoLabel(
                    L10n.text(showsComposer ? "regression.action.history" : "regression.action.new"),
                    systemImage: showsComposer ? "clock.arrow.circlepath" : "plus"
                )
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(
                showsComposer && model.currentRepositoryRegressionInvestigations.isEmpty
                    || model.activeRegressionInvestigationID != nil
            )
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .background(theme == .softGlass ? palette.surface.opacity(0.16) : palette.surface)
    }

    private func setupWorkspace(_ palette: AppPalette) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(palette.accentSoft)
                        GattoIcon(symbol: "stethoscope", size: 30)
                            .foregroundStyle(palette.accent)
                    }
                    .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.text("regression.setup.title"))
                            .font(font(20, weight: .bold))
                            .foregroundStyle(palette.ink)
                        Text(model.repositoryName ?? "")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.subtleInk)
                    }
                    Spacer()
                    isolationBadge(palette)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Picker("", selection: $model.regressionMode) {
                        Text(L10n.text("regression.mode.automatic"))
                            .tag(RegressionInvestigationMode.automatic)
                        Text(L10n.text("regression.mode.manual"))
                            .tag(RegressionInvestigationMode.manual)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 310)

                    HStack(spacing: 12) {
                        field(
                            L10n.text("regression.field.good"),
                            placeholder: L10n.text("regression.field.good.placeholder"),
                            text: $model.regressionGoodRevision,
                            palette: palette
                        )
                        field(
                            L10n.text("regression.field.bad"),
                            placeholder: L10n.text("regression.field.bad.placeholder"),
                            text: $model.regressionBadRevision,
                            palette: palette
                        )
                    }

                    VStack(alignment: .leading, spacing: 7) {
                            Text(L10n.text("regression.field.command"))
                                .font(font(11, weight: .semibold))
                                .foregroundStyle(palette.mutedInk)
                            TextField(
                                L10n.text("regression.field.command.placeholder"),
                                text: $model.regressionVerificationCommand
                            )
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .background(palette.raisedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                                    .stroke(palette.divider, lineWidth: 1)
                            }
                    }

                    HStack {
                        Label {
                            Text(L10n.text("regression.setup.isolation"))
                        } icon: {
                            GattoIcon(symbol: "checkmark.shield", size: 15)
                        }
                        .font(font(10.5, weight: .medium))
                        .foregroundStyle(palette.mutedInk)
                        Spacer()
                        Button {
                            model.startRegressionInvestigation()
                        } label: {
                            if model.activeRegressionInvestigationID != nil {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text(L10n.text("regression.status.preparing"))
                                }
                            } else {
                                GattoLabel(L10n.text("regression.action.start"), systemImage: "play.circle")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canStartInvestigation)
                    }
                }
                .padding(18)
                .regressionSurface(theme: theme, palette: palette, level: .panel)
            }
            .frame(maxWidth: 760)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    private func investigationList(_ palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("regression.history.title"))
                    .font(font(11.5, weight: .semibold))
                    .foregroundStyle(palette.mutedInk)
                Spacer()
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            Rectangle().fill(palette.divider).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(model.currentRepositoryRegressionInvestigations) { investigation in
                        Button {
                            model.selectRegressionInvestigation(investigation)
                        } label: {
                            investigationRow(investigation, palette: palette)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if investigation.workspacePath != nil {
                                Button(L10n.text("regression.action.reveal")) {
                                    model.selectRegressionInvestigation(investigation)
                                    model.revealRegressionWorkspace()
                                }
                            } else {
                                Button(L10n.text("regression.action.delete"), role: .destructive) {
                                    model.selectRegressionInvestigation(investigation)
                                    model.deleteRegressionInvestigationEvidence()
                                }
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
        .background(theme == .softGlass ? palette.surface.opacity(0.10) : palette.surface)
    }

    private func compactInvestigationPicker(_ palette: AppPalette) -> some View {
        HStack(spacing: 10) {
            Text(L10n.text("regression.history.title"))
                .font(font(11, weight: .semibold))
                .foregroundStyle(palette.mutedInk)
            Picker(
                "",
                selection: Binding(
                    get: { model.selectedRegressionInvestigation?.id },
                    set: { id in
                        guard let id,
                              let investigation = model.currentRepositoryRegressionInvestigations.first(where: {
                                  $0.id == id
                              }) else { return }
                        model.selectRegressionInvestigation(investigation)
                    }
                )
            ) {
                ForEach(model.currentRepositoryRegressionInvestigations) { investigation in
                    Text(investigation.culprit?.subject ?? L10n.text("regression.history.in_progress"))
                        .tag(Optional(investigation.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 360)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(theme == .softGlass ? palette.surface.opacity(0.10) : palette.surface)
    }

    private func investigationRow(
        _ investigation: RegressionInvestigation,
        palette: AppPalette
    ) -> some View {
        let selected = model.selectedRegressionInvestigation?.id == investigation.id
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(gattoSymbol: statusIcon(investigation.status))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(statusColor(investigation.status, palette: palette))
                    .frame(width: 28, height: 28)
                    .background(statusColor(investigation.status, palette: palette).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(investigation.culprit?.subject ?? L10n.text("regression.history.in_progress"))
                        .font(font(11.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text("\(investigation.goodRevision) … \(investigation.badRevision)")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
            }
            ProgressView(value: investigation.estimatedProgress)
                .tint(statusColor(investigation.status, palette: palette))
            HStack {
                Text(L10n.text("regression.status.\(investigation.status.rawValue)"))
                Spacer()
                Text(investigation.updatedAt, style: .relative)
            }
            .font(font(9.5, weight: .medium))
            .foregroundStyle(palette.subtleInk)
        }
        .padding(11)
        .background(selected ? palette.accentSoft : palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? palette.accent.opacity(0.44) : palette.divider, lineWidth: 1)
        }
    }

    private func investigationDetail(
        _ investigation: RegressionInvestigation,
        palette: AppPalette
    ) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                investigationHeader(investigation, palette: palette)
                progressPanel(investigation, palette: palette)
                if investigation.status == .awaitingManualVerdict,
                   let current = investigation.currentCommit {
                    manualVerdictPanel(current, palette: palette)
                }
                if let culprit = investigation.culprit {
                    culpritPanel(culprit, investigation: investigation, palette: palette)
                }
                if investigation.fixBranch != nil || investigation.agentSummary != nil {
                    fixPanel(investigation, palette: palette)
                }
                if !investigation.probes.isEmpty {
                    evidenceTimeline(investigation, palette: palette)
                }
                if let error = investigation.errorMessage, !error.isEmpty {
                    errorPanel(error, palette: palette)
                }
            }
            .padding(16)
        }
        .background(theme == .softGlass ? Color.clear : palette.background)
    }

    private func investigationHeader(
        _ investigation: RegressionInvestigation,
        palette: AppPalette
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    statusBadge(investigation.status, palette: palette)
                    isolationBadge(palette)
                }
                Text("\(investigation.goodRevision) → \(investigation.badRevision)")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.ink)
                if let path = investigation.workspacePath {
                    Text(path)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            if investigation.workspacePath != nil {
                Button(L10n.text("regression.action.reveal")) {
                    model.revealRegressionWorkspace()
                }
                .buttonStyle(SecondaryButtonStyle())
                Button {
                    showsCleanupConfirmation = true
                } label: {
                    Image(gattoSymbol: "trash")
                        .foregroundStyle(palette.danger)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(model.activeRegressionInvestigationID != nil)
                .help(L10n.text("regression.action.cleanup"))
            } else {
                Button(L10n.text("regression.action.delete"), role: .destructive) {
                    model.deleteRegressionInvestigationEvidence()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(16)
        .regressionSurface(theme: theme, palette: palette, level: .elevated)
    }

    private func progressPanel(
        _ investigation: RegressionInvestigation,
        palette: AppPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 18) {
                metric(
                    L10n.text("regression.metric.candidates"),
                    value: "\(investigation.candidateCount)",
                    icon: "arrow.triangle.branch",
                    palette: palette
                )
                metric(
                    L10n.text("regression.metric.probes"),
                    value: "\(investigation.completedProbeCount)",
                    icon: "checkmark.circle",
                    palette: palette
                )
                if let current = investigation.currentCommit, investigation.culprit == nil {
                    metric(
                        L10n.text("regression.metric.current"),
                        value: current.shortSHA,
                        icon: "record.circle",
                        palette: palette
                    )
                }
                Spacer()
                if investigation.status == .running || investigation.status == .verifyingFix {
                    GattoLoadingGlyph(size: 25)
                }
            }
            ProgressView(value: investigation.estimatedProgress)
                .tint(palette.accent)
        }
        .padding(16)
        .regressionSurface(theme: theme, palette: palette, level: .panel)
    }

    private func manualVerdictPanel(
        _ commit: RegressionCommitEvidence,
        palette: AppPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("regression.manual.title", icon: "text.cursor", palette: palette)
            commitLine(commit, palette: palette)
            HStack(spacing: 9) {
                Button(L10n.text("regression.verdict.good")) {
                    model.recordRegressionVerdict(.good)
                }
                .buttonStyle(SecondaryButtonStyle())
                Button(L10n.text("regression.verdict.bad")) {
                    model.recordRegressionVerdict(.bad)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(L10n.text("regression.verdict.skipped")) {
                    model.recordRegressionVerdict(.skipped)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(16)
        .regressionSurface(theme: theme, palette: palette, level: .elevated)
    }

    private func culpritPanel(
        _ culprit: RegressionCommitEvidence,
        investigation: RegressionInvestigation,
        palette: AppPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionTitle("regression.culprit.title", icon: "doc.text.magnifyingglass", palette: palette)
                Spacer()
                Text(culprit.shortSHA)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.danger)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(palette.dangerSoft)
                    .clipShape(Capsule())
            }
            commitLine(culprit, palette: palette)
            if let summary = investigation.culpritSummary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.mutedInk)
                    .textSelection(.enabled)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.raisedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous))
            }
            HStack {
                if model.regressionAgentIsRunning {
                    Button {
                        model.cancelRegressionAgent()
                    } label: {
                        GattoLabel(L10n.text("action.cancel"), systemImage: "xmark")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button {
                        model.repairRegressionWithAgent()
                    } label: {
                        GattoLabel(L10n.text("regression.action.agent_fix"), systemImage: "sparkles")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(
                        model.codexAvailability.state != .available
                            || model.activeRegressionInvestigationID != nil
                            || !(investigation.status == .culpritFound || investigation.status == .fixReady)
                    )
                }
                Spacer()
            }
        }
        .padding(16)
        .regressionSurface(theme: theme, palette: palette, level: .elevated)
    }

    private func fixPanel(
        _ investigation: RegressionInvestigation,
        palette: AppPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionTitle("regression.fix.title", icon: "checkmark.shield", palette: palette)
                Spacer()
                if let branch = investigation.fixBranch {
                    Text(branch)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                }
            }
            if investigation.status == .agentFixing || investigation.status == .verifyingFix {
                HStack(spacing: 9) {
                    GattoLoadingGlyph(size: 28)
                    Text(L10n.text("regression.status.\(investigation.status.rawValue)"))
                        .font(font(11.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                }
            }
            if let summary = investigation.agentSummary, !summary.isEmpty {
                Text(summary)
                    .font(font(11, weight: .regular))
                    .foregroundStyle(palette.mutedInk)
                    .textSelection(.enabled)
            }
            if let verification = investigation.fixVerification {
                DisclosureGroup {
                    if !verification.output.isEmpty {
                        Text(verification.output)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(palette.mutedInk)
                            .textSelection(.enabled)
                            .padding(.top, 9)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(gattoSymbol: verification.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(verification.passed ? palette.success : palette.danger)
                        Text(L10n.text(
                            verification.passed
                                ? "regression.verification.passed"
                                : "regression.verification.failed"
                        ))
                        Text(L10n.format("regression.duration", verification.duration))
                            .foregroundStyle(palette.subtleInk)
                    }
                    .font(font(10.5, weight: .semibold))
                }
                .padding(10)
                .background(verification.passed ? palette.successSoft : palette.dangerSoft)
                .clipShape(RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous))
            }

            if investigation.fixVerification?.passed == true,
               investigation.status != .completed {
                TextField(L10n.text("regression.publish.title.placeholder"), text: $model.regressionFixTitle)
                    .textFieldStyle(.plain)
                    .font(font(11.5, weight: .medium))
                    .padding(.horizontal, 11)
                    .frame(height: 36)
                    .background(palette.raisedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                            .stroke(palette.divider, lineWidth: 1)
                    }
                TextField(
                    L10n.text("regression.publish.body.placeholder"),
                    text: $model.regressionFixBody,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(font(10.5, weight: .regular))
                .lineLimit(2...5)
                .padding(10)
                .background(palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                        .stroke(palette.divider, lineWidth: 1)
                }
                HStack {
                    if investigation.mode == .automatic {
                        Button {
                            model.verifyRegressionFix()
                        } label: {
                            GattoLabel(L10n.text("regression.action.verify_again"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    } else {
                        Button(L10n.text("regression.verification.failed")) {
                            model.recordManualRegressionFixVerification(passed: false)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    Spacer()
                    Button {
                        showsPublishConfirmation = true
                    } label: {
                        GattoLabel(L10n.text("regression.action.publish"), systemImage: "git.pull.request")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(
                        model.regressionFixTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || model.activeRegressionInvestigationID != nil
                    )
                }
            } else if investigation.fixBranch != nil,
                      investigation.status != .agentFixing,
                      investigation.status != .verifyingFix,
                      investigation.status != .completed {
                HStack(spacing: 9) {
                    if investigation.mode == .automatic {
                        Button {
                            model.verifyRegressionFix()
                        } label: {
                            GattoLabel(L10n.text("regression.action.verify"), systemImage: "play.circle")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    } else {
                        Button(L10n.text("regression.verification.failed")) {
                            model.recordManualRegressionFixVerification(passed: false)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        Button(L10n.text("regression.verification.passed")) {
                            model.recordManualRegressionFixVerification(passed: true)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .disabled(model.activeRegressionInvestigationID != nil)
            }

            if investigation.status == .completed {
                HStack(spacing: 8) {
                    Image(gattoSymbol: "checkmark.circle.fill")
                        .foregroundStyle(palette.success)
                    if let commit = investigation.fixCommitSHA {
                        Text(String(commit.prefix(8)))
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    }
                    if let url = investigation.pullRequestURL {
                        Button(L10n.text("regression.action.open_pr")) {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
        .padding(16)
        .regressionSurface(theme: theme, palette: palette, level: .panel)
    }

    private func evidenceTimeline(
        _ investigation: RegressionInvestigation,
        palette: AppPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("regression.evidence.title", icon: "clock.arrow.circlepath", palette: palette)
            ForEach(Array(investigation.probes.enumerated()), id: \.element.id) { index, probe in
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(verdictColor(probe.verdict, palette: palette))
                            .frame(width: 9, height: 9)
                        if index < investigation.probes.count - 1 {
                            Rectangle()
                                .fill(palette.divider)
                                .frame(width: 1, height: 50)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(probe.commit.shortSHA)
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            Text(probe.commit.subject)
                                .font(font(11, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Text(L10n.text("regression.verdict.\(probe.verdict.rawValue)"))
                                .foregroundStyle(verdictColor(probe.verdict, palette: palette))
                            if probe.exitCode != nil {
                                Text(L10n.format("regression.duration", probe.duration))
                                    .foregroundStyle(palette.subtleInk)
                            }
                        }
                        .foregroundStyle(palette.ink)
                        .font(font(9.5, weight: .semibold))
                        if !probe.output.isEmpty {
                            DisclosureGroup(L10n.text("regression.evidence.output")) {
                                Text(probe.output)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(palette.mutedInk)
                                    .textSelection(.enabled)
                                    .padding(.top, 6)
                            }
                            .font(font(9.5, weight: .medium))
                            .foregroundStyle(palette.subtleInk)
                        }
                    }
                }
            }
        }
        .padding(16)
        .regressionSurface(theme: theme, palette: palette, level: .panel)
    }

    private func errorPanel(_ error: String, palette: AppPalette) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(gattoSymbol: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.danger)
            Text(error)
                .font(font(10.5, weight: .medium))
                .foregroundStyle(palette.danger)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(13)
        .background(palette.dangerSoft)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func field(
        _ title: String,
        placeholder: String,
        text: Binding<String>,
        palette: AppPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(font(11, weight: .semibold))
                .foregroundStyle(palette.mutedInk)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
                        .stroke(palette.divider, lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity)
    }

    private func metric(
        _ title: String,
        value: String,
        icon: String,
        palette: AppPalette
    ) -> some View {
        HStack(spacing: 8) {
            Image(gattoSymbol: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.ink)
                Text(title)
                    .font(font(9, weight: .medium))
                    .foregroundStyle(palette.subtleInk)
            }
        }
    }

    private func commitLine(_ commit: RegressionCommitEvidence, palette: AppPalette) -> some View {
        HStack(spacing: 10) {
            Text(commit.shortSHA)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.subject)
                    .font(font(12, weight: .semibold))
                    .foregroundStyle(palette.ink)
                HStack(spacing: 6) {
                    Text(commit.author)
                    if let authoredAt = commit.authoredAt {
                        Text("·")
                        Text(authoredAt, style: .date)
                    }
                }
                .font(font(9.5, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            }
            Spacer()
        }
    }

    private func sectionTitle(_ key: String, icon: String, palette: AppPalette) -> some View {
        HStack(spacing: 7) {
            Image(gattoSymbol: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.accent)
            Text(L10n.text(key))
                .font(font(12.5, weight: .semibold))
                .foregroundStyle(palette.ink)
        }
    }

    private func statusBadge(
        _ status: RegressionInvestigationStatus,
        palette: AppPalette
    ) -> some View {
        HStack(spacing: 6) {
            if status == .running || status == .agentFixing || status == .verifyingFix || status == .publishing {
                ProgressView().controlSize(.mini)
            } else {
                Image(gattoSymbol: statusIcon(status))
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(L10n.text("regression.status.\(status.rawValue)"))
                .font(font(9.5, weight: .semibold))
        }
        .foregroundStyle(statusColor(status, palette: palette))
        .padding(.horizontal, 9)
        .frame(height: 25)
        .background(statusColor(status, palette: palette).opacity(0.12))
        .clipShape(Capsule())
    }

    private func isolationBadge(_ palette: AppPalette) -> some View {
        HStack(spacing: 5) {
            Image(gattoSymbol: "checkmark.shield")
                .font(.system(size: 10.5, weight: .semibold))
            Text(L10n.text("regression.isolated"))
                .font(font(9.5, weight: .semibold))
        }
        .foregroundStyle(palette.success)
        .padding(.horizontal, 9)
        .frame(height: 25)
        .background(palette.successSoft)
        .clipShape(Capsule())
    }

    private func statusIcon(_ status: RegressionInvestigationStatus) -> String {
        switch status {
        case .preparing, .running, .agentFixing, .verifyingFix, .publishing: "record.circle"
        case .awaitingManualVerdict: "text.cursor"
        case .paused: "pause"
        case .culpritFound: "doc.text.magnifyingglass"
        case .fixReady: "hammer"
        case .fixVerified, .completed: "checkmark.circle.fill"
        case .inconclusive: "circle.dashed"
        case .failed: "xmark.circle.fill"
        case .cancelled: "xmark"
        }
    }

    private func statusColor(
        _ status: RegressionInvestigationStatus,
        palette: AppPalette
    ) -> Color {
        switch status {
        case .completed, .fixVerified: palette.success
        case .failed: palette.danger
        case .culpritFound, .inconclusive: palette.warning
        case .cancelled, .paused: palette.subtleInk
        default: palette.accent
        }
    }

    private func verdictColor(_ verdict: RegressionVerdict, palette: AppPalette) -> Color {
        switch verdict {
        case .good: palette.success
        case .bad: palette.danger
        case .skipped: palette.warning
        }
    }

    private var canStartInvestigation: Bool {
        !model.regressionGoodRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.regressionBadRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (model.regressionMode == .manual
                || !model.regressionVerificationCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && model.activeRegressionInvestigationID == nil
    }

    private var controlCornerRadius: CGFloat { theme == .console ? 4 : 9 }

    private func font(_ size: CGFloat, weight: Font.Weight) -> Font {
        theme == .console
            ? .system(size: size, weight: weight, design: .monospaced)
            : .system(size: size, weight: weight)
    }
}

private enum RegressionSurfaceLevel {
    case panel
    case elevated
}

private extension View {
    @ViewBuilder
    func regressionSurface(
        theme: AppVisualTheme,
        palette: AppPalette,
        level: RegressionSurfaceLevel
    ) -> some View {
        switch theme {
        case .emerald:
            emeraldSurface(level == .elevated ? .elevated : .panel, cornerRadius: 16)
        case .folio:
            folioSurface(level == .elevated ? .elevated : .panel, cornerRadius: 16)
        default:
            background(theme == .softGlass ? palette.surface.opacity(0.14) : palette.surface)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: theme == .console ? 5 : 14,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: theme == .console ? 5 : 14,
                        style: .continuous
                    )
                    .stroke(palette.divider, lineWidth: 1)
                }
        }
    }
}
