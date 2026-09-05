import SwiftUI

struct RepositoryIntelligenceWorkspaceView: View {
    @ObservedObject var model: RepositoryIntelligenceViewModel
    @ObservedObject var workspaceModel: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue

    private var theme: AppVisualTheme { AppVisualTheme.resolved(themeRaw) }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            header(palette: palette)
            Rectangle().fill(palette.divider).frame(height: 1)

            Group {
                switch model.selectedTab {
                case .intent:
                    ChangeIntentWorkspace(model: model, workspaceModel: workspaceModel)
                case .provenance:
                    CodeProvenanceWorkspace(model: model, selectedPath: workspaceModel.selectedChange?.path)
                case .capsules:
                    ReproductionCapsuleWorkspace(model: model)
                case .activity:
                    RepositoryActivityWorkspace(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme == .standard ? palette.background : Color.clear)
        .overlay(alignment: .top) {
            if let notice = model.notice {
                IntelligenceNotice(text: notice) { model.dismissNotice() }
                    .padding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task(id: workspaceModel.snapshot?.rootURL.standardizedFileURL.path) {
            guard let repositoryURL = workspaceModel.snapshot?.rootURL else { return }
            model.load(repositoryURL: repositoryURL)
        }
        .task(id: model.selectedTab) {
            guard model.selectedTab == .activity else { return }
            while !Task.isCancelled {
                await model.refreshActivity()
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.notice)
    }

    private func header(palette: AppPalette) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                GattoIcon(symbol: "point.3.connected.trianglepath.dotted", size: 22)
                    .foregroundStyle(palette.primary)
                Text(L10n.text("intelligence.title"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.ink)
            }

            Spacer(minLength: 12)

            HStack(spacing: 3) {
                ForEach(RepositoryIntelligenceTab.allCases) { tab in
                    Button {
                        model.selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(gattoSymbol: tab.symbol)
                                .font(.system(size: 12.5, weight: .semibold))
                            Text(L10n.text(tab.titleKey))
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(model.selectedTab == tab ? palette.primary : palette.mutedInk)
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(model.selectedTab == tab ? palette.primarySoft : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(3)
            .background(palette.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(palette.divider, lineWidth: 1)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(palette.surface.opacity(theme == .softGlass ? 0.32 : 1))
    }
}

private struct ChangeIntentWorkspace: View {
    @ObservedObject var model: RepositoryIntelligenceViewModel
    @ObservedObject var workspaceModel: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsApplyConfirmation = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Group {
            if model.isLoadingIntentPlan, model.intentPlan == nil {
                GattoLoadingState(text: L10n.text("intelligence.intent.loading"))
            } else if let error = model.intentError, model.intentPlan == nil {
                IntelligenceErrorState(message: error) {
                    Task { await model.refreshIntentPlan() }
                }
            } else if let plan = model.intentPlan {
                HSplitView {
                    intentNavigator(plan: plan, palette: palette)
                        .frame(minWidth: 285, idealWidth: 330, maxWidth: 390)
                    intentInspector(plan: plan, palette: palette)
                        .frame(minWidth: 430)
                }
            } else if let result = model.intentApplyResult {
                resultView(result, palette: palette)
            } else {
                InspectorEmptyState(
                    image: "checkmark.circle",
                    titleKey: "intelligence.intent.empty.title",
                    bodyKey: "intelligence.intent.empty.body"
                )
            }
        }
        .alert(L10n.text("intelligence.intent.confirm.title"), isPresented: $showsApplyConfirmation) {
            Button(L10n.text("action.cancel"), role: .cancel) {}
            Button(L10n.text("intelligence.intent.apply")) {
                Task {
                    if await model.applyIntentPlan() {
                        await workspaceModel.refresh()
                    }
                }
            }
        } message: {
            Text(L10n.format("intelligence.intent.confirm.body", model.intentPlan?.groups.count ?? 0))
        }
    }

    private func intentNavigator(plan: ChangeIntentPlan, palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("intelligence.intent.title"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text(L10n.format("intelligence.intent.summary", plan.units.count, plan.groups.count))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.subtleInk)
                }
                Spacer()
                ToolbarIconButton(
                    systemName: "arrow.clockwise",
                    helpKey: "action.refresh",
                    isActive: model.isLoadingIntentPlan,
                    isDisabled: model.isApplyingIntentPlan
                ) {
                    Task { await model.refreshIntentPlan() }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            Rectangle().fill(palette.divider).frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(plan.groups.enumerated()), id: \.element.id) { index, group in
                        IntentGroupCard(
                            group: group,
                            index: index,
                            total: plan.groups.count,
                            units: group.unitIDs.compactMap { id in plan.units.first { $0.id == id } },
                            selectedUnitID: model.selectedIntentUnitID,
                            onSelectGroup: { model.selectedIntentGroupID = group.id },
                            onSelectUnit: { id in
                                model.selectedIntentGroupID = group.id
                                model.selectedIntentUnitID = id
                            },
                            onMoveUnit: { unitID, target in model.moveIntentUnit(unitID, to: target) },
                            groupTargets: plan.groups,
                            onMoveGroup: { offset in model.moveIntentGroup(group.id, offset: offset) },
                            onRemove: { model.removeIntentGroup(group.id) }
                        )
                    }
                }
                .padding(12)
            }

            Rectangle().fill(palette.divider).frame(height: 1)
            HStack(spacing: 8) {
                Button {
                    model.addIntentGroup()
                } label: {
                    HStack(spacing: 6) {
                        Image(gattoSymbol: "plus")
                        Text(L10n.text("intelligence.intent.add_group"))
                    }
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button {
                    if model.isRefiningIntentPlan {
                        model.cancelIntentAgent()
                    } else {
                        model.refineIntentPlanWithAgent()
                    }
                } label: {
                    HStack(spacing: 7) {
                        if model.isRefiningIntentPlan {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(gattoSymbol: "sparkles")
                        }
                        Text(L10n.text(model.isRefiningIntentPlan ? "action.cancel" : "intelligence.intent.agent"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isApplyingIntentPlan)
            }
            .padding(12)
        }
        .intelligencePanel(elevated: true)
    }

    private func intentInspector(plan: ChangeIntentPlan, palette: AppPalette) -> some View {
        VStack(spacing: 0) {
            if let group = model.selectedIntentGroup {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        TextField(
                            L10n.text("intelligence.intent.group_title"),
                            text: binding(for: group.id, keyPath: \.title)
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.ink)

                        Picker("", selection: kindBinding(for: group)) {
                            ForEach(ChangeIntentKind.allCases) { kind in
                                Text(L10n.text(kind.titleKey)).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 145)
                    }

                    TextField(
                        L10n.text("intelligence.intent.commit_message"),
                        text: binding(for: group.id, keyPath: \.commitMessage)
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced))

                    HStack(spacing: 8) {
                        Image(gattoSymbol: "checkmark.shield")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.primary)
                        TextField(
                            L10n.text("intelligence.intent.verify_placeholder"),
                            text: $model.verificationCommand
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, design: .monospaced))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(palette.raisedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(palette.divider) }
                }
                .padding(14)

                Rectangle().fill(palette.divider).frame(height: 1)

                if let unit = model.selectedIntentUnit, let patch = unit.patch {
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(unit.path)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(palette.ink)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(unit.hunkHeader ?? L10n.text("intelligence.intent.whole_file"))
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(palette.subtleInk)
                            }
                            Spacer()
                            ChangeCountBadge(added: unit.addedLineCount, deleted: unit.deletedLineCount)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                        Rectangle().fill(palette.divider).frame(height: 1)
                        DiffCodeView(document: GitParsers.diff(from: patch, path: unit.path))
                    }
                } else if let unit = model.selectedIntentUnit {
                    InspectorEmptyState(
                        image: "doc",
                        titleKey: "intelligence.intent.whole_file.title",
                        bodyKey: "intelligence.intent.whole_file.body"
                    )
                    .overlay(alignment: .top) {
                        Text(unit.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.mutedInk)
                            .padding(.top, 18)
                    }
                } else {
                    InspectorEmptyState(
                        image: "doc-text-magnifyingglass",
                        titleKey: "intelligence.intent.select.title",
                        bodyKey: "intelligence.intent.select.body"
                    )
                }

                Rectangle().fill(palette.divider).frame(height: 1)
                HStack(spacing: 10) {
                    if let error = model.intentError {
                        Image(gattoSymbol: "exclamationmark.triangle.fill")
                            .foregroundStyle(palette.danger)
                        Text(error)
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.danger)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button(L10n.text("intelligence.intent.apply")) {
                        showsApplyConfirmation = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isApplyingIntentPlan || plan.groups.contains(where: { $0.unitIDs.isEmpty }))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 56)
            } else {
                InspectorEmptyState(
                    image: "doc-text-magnifyingglass",
                    titleKey: "intelligence.intent.select.title",
                    bodyKey: "intelligence.intent.select.body"
                )
            }
        }
        .intelligencePanel(elevated: false)
    }

    private func resultView(_ result: ChangeIntentApplyResult, palette: AppPalette) -> some View {
        VStack(spacing: 16) {
            Image(gattoSymbol: "checkmark.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(palette.success)
            Text(L10n.text("intelligence.intent.result.title"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text(L10n.format("intelligence.intent.result.body", result.commitHashes.count))
                .font(.system(size: 12.5))
                .foregroundStyle(palette.mutedInk)
            HStack(spacing: 8) {
                ForEach(result.commitHashes, id: \.self) { hash in
                    Text(String(hash.prefix(8)))
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(palette.raisedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            Button(L10n.text("intelligence.intent.refresh")) {
                Task { await model.refreshIntentPlan() }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func binding(
        for groupID: UUID,
        keyPath: WritableKeyPath<ChangeIntentGroup, String>
    ) -> Binding<String> {
        Binding(
            get: { model.intentPlan?.groups.first(where: { $0.id == groupID })?[keyPath: keyPath] ?? "" },
            set: { value in
                if keyPath == \.title {
                    model.updateIntentGroup(groupID, title: value)
                } else {
                    model.updateIntentGroup(groupID, message: value)
                }
            }
        )
    }

    private func kindBinding(for group: ChangeIntentGroup) -> Binding<ChangeIntentKind> {
        Binding(
            get: { model.intentPlan?.groups.first(where: { $0.id == group.id })?.kind ?? group.kind },
            set: { model.updateIntentGroup(group.id, kind: $0) }
        )
    }
}

private struct IntentGroupCard: View {
    let group: ChangeIntentGroup
    let index: Int
    let total: Int
    let units: [ChangeIntentUnit]
    let selectedUnitID: String?
    let onSelectGroup: () -> Void
    let onSelectUnit: (String) -> Void
    let onMoveUnit: (String, UUID) -> Void
    let groupTargets: [ChangeIntentGroup]
    let onMoveGroup: (Int) -> Void
    let onRemove: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Text(String(index + 1))
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primary)
                    .frame(width: 24, height: 24)
                    .background(palette.primarySoft)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(group.commitMessage)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                        .lineLimit(1)
                }
                Spacer()
                Button { onMoveGroup(-1) } label: {
                    Image(gattoSymbol: "chevron.compact.up").frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                Button { onMoveGroup(1) } label: {
                    Image(gattoSymbol: "chevron.compact.down").frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(index == total - 1)
                Button(role: .destructive, action: onRemove) {
                    Image(gattoSymbol: "trash").frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(total == 1)
            }
            .padding(.horizontal, 10)
            .frame(height: 48)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelectGroup)

            if units.isEmpty {
                Text(L10n.text("intelligence.intent.group_empty"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.subtleInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            } else {
                ForEach(units) { unit in
                    Button { onSelectUnit(unit.id) } label: {
                        HStack(spacing: 8) {
                            Image(gattoSymbol: unit.kind == .hunk ? "curlybraces.square" : "doc")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(selectedUnitID == unit.id ? palette.primary : palette.subtleInk)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(URL(fileURLWithPath: unit.path).lastPathComponent)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(palette.ink)
                                    .lineLimit(1)
                                Text(unit.hunkHeader ?? unit.path)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(palette.subtleInk)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            ChangeCountBadge(added: unit.addedLineCount, deleted: unit.deletedLineCount)
                            Menu {
                                ForEach(groupTargets.filter { $0.id != group.id }) { target in
                                    Button(target.title) { onMoveUnit(unit.id, target.id) }
                                }
                            } label: {
                                Image(gattoSymbol: "arrow.right")
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 44)
                        .background(selectedUnitID == unit.id ? palette.primarySoft : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(palette.surface.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(palette.divider) }
    }
}

private struct CodeProvenanceWorkspace: View {
    @ObservedObject var model: RepositoryIntelligenceViewModel
    let selectedPath: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(gattoSymbol: "doc-text-magnifyingglass")
                        .foregroundStyle(palette.primary)
                    TextField(L10n.text("intelligence.provenance.path"), text: $model.provenancePath)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(palette.divider) }

                TextField(L10n.text("intelligence.provenance.line"), text: $model.provenanceLine)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Button {
                    Task { await model.traceProvenance() }
                } label: {
                    HStack(spacing: 7) {
                        if model.isTracingProvenance { ProgressView().controlSize(.small) }
                        Text(L10n.text("intelligence.provenance.trace"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isTracingProvenance || model.provenancePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
            Rectangle().fill(palette.divider).frame(height: 1)

            if let error = model.provenanceError {
                IntelligenceErrorState(message: error) {
                    Task { await model.traceProvenance() }
                }
            } else if model.isTracingProvenance, model.provenanceReport == nil {
                GattoLoadingState(text: L10n.text("intelligence.provenance.loading"))
            } else if let report = model.provenanceReport {
                provenanceReport(report, palette: palette)
            } else {
                InspectorEmptyState(
                    image: "doc-text-magnifyingglass",
                    titleKey: "intelligence.provenance.empty.title",
                    bodyKey: "intelligence.provenance.empty.body"
                )
            }
        }
        .intelligencePanel(elevated: false)
        .onAppear {
            if model.provenancePath.isEmpty, let selectedPath {
                model.provenancePath = selectedPath
            }
        }
        .onChange(of: selectedPath) { _, path in
            if model.provenancePath.isEmpty, let path { model.provenancePath = path }
        }
    }

    private func provenanceReport(_ report: CodeProvenanceReport, palette: AppPalette) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ProvenanceChainView(report: report)

                IntelligenceCard(titleKey: "intelligence.provenance.commit", symbol: "history.file") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(report.commit.subject)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.ink)
                        if !report.commit.body.isEmpty {
                            Text(report.commit.body)
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.mutedInk)
                                .textSelection(.enabled)
                        }
                        HStack(spacing: 12) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(palette.accent)
                                    .frame(width: 5, height: 5)
                                Text(report.commit.shortHash)
                            }
                            Text(report.commit.author)
                            if let date = report.commit.authoredAt {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                        if let source = report.sourceText {
                            Text(source)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(palette.ink)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(palette.background)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .textSelection(.enabled)
                        }
                    }
                }

                if let pull = report.pullRequest {
                    IntelligenceCard(titleKey: "intelligence.provenance.pull_request", symbol: "git.pull.request") {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("#\(pull.number)  \(pull.title)")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(palette.ink)
                            Text("\(pull.author) · \(pull.state)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(palette.subtleInk)
                            if !pull.body.isEmpty {
                                Text(pull.body)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(palette.mutedInk)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    IntelligenceCard(titleKey: "intelligence.provenance.issues", symbol: "record.circle") {
                        ProvenanceItemsList(
                            emptyKey: "intelligence.provenance.issues.empty",
                            items: report.issues.map { "#\($0.number)  \($0.title) · \($0.state)" }
                        )
                    }
                    IntelligenceCard(titleKey: "intelligence.provenance.reviews", symbol: "checkmark.seal") {
                        ProvenanceItemsList(
                            emptyKey: "intelligence.provenance.reviews.empty",
                            items: report.reviews.map { "\($0.author) · \($0.state)\($0.body.isEmpty ? "" : " — \($0.body)")" }
                        )
                    }
                }

                IntelligenceCard(titleKey: "intelligence.provenance.checks", symbol: "checkmark.shield") {
                    ProvenanceItemsList(
                        emptyKey: "intelligence.provenance.checks.empty",
                        items: report.checks.map { "\($0.name) · \($0.conclusion ?? $0.status)" }
                    )
                }

                if let reason = report.remoteUnavailableReason {
                    HStack(alignment: .top, spacing: 8) {
                        Image(gattoSymbol: "info.circle")
                        Text(reason)
                            .textSelection(.enabled)
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.subtleInk)
                    .padding(.horizontal, 4)
                }
            }
            .padding(14)
        }
    }
}

private struct ProvenanceChainView: View {
    let report: CodeProvenanceReport
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 8) {
            node(
                symbol: "curlybraces.square",
                eyebrow: L10n.text("intelligence.provenance.chain.line"),
                value: "\(URL(fileURLWithPath: report.filePath).lastPathComponent):\(report.line)",
                palette: palette
            )
            connector(palette)
            node(
                symbol: "history.file",
                eyebrow: L10n.text("intelligence.provenance.chain.commit"),
                value: report.commit.shortHash,
                palette: palette
            )
            connector(palette)
            node(
                symbol: "git.pull.request",
                eyebrow: L10n.text("intelligence.provenance.chain.pull"),
                value: report.pullRequest.map { "#\($0.number)" } ?? "—",
                palette: palette
            )
            connector(palette)
            node(
                symbol: "checkmark.shield",
                eyebrow: L10n.text("intelligence.provenance.chain.evidence"),
                value: L10n.format(
                    "intelligence.provenance.chain.evidence.value",
                    report.issues.count + report.reviews.count + report.checks.count
                ),
                palette: palette
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(palette.primarySoft.opacity(0.36))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(palette.primary.opacity(0.16)) }
    }

    private func node(
        symbol: String,
        eyebrow: String,
        value: String,
        palette: AppPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(gattoSymbol: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(eyebrow)
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(palette.subtleInk)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func connector(_ palette: AppPalette) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(palette.divider).frame(width: 15, height: 1)
            Image(gattoSymbol: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(palette.subtleInk)
        }
        .fixedSize()
    }
}

private struct ReproductionCapsuleWorkspace: View {
    @ObservedObject var model: RepositoryIntelligenceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmsRestore = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("intelligence.capsule.title"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.ink)
                        Text(L10n.format("intelligence.capsule.count", model.capsules.count))
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.subtleInk)
                    }
                    Spacer()
                    ToolbarIconButton(systemName: "arrow.clockwise", helpKey: "action.refresh") {
                        Task { await model.refreshCapsules() }
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 58)
                Rectangle().fill(palette.divider).frame(height: 1)

                if model.capsules.isEmpty {
                    InspectorEmptyState(
                        image: "shippingbox",
                        titleKey: "intelligence.capsule.empty.title",
                        bodyKey: "intelligence.capsule.empty.body"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(model.capsules) { capsule in
                                CapsuleRow(
                                    capsule: capsule,
                                    isSelected: model.selectedCapsuleID == capsule.id
                                ) { model.selectedCapsuleID = capsule.id }
                            }
                        }
                        .padding(10)
                    }
                }

                Rectangle().fill(palette.divider).frame(height: 1)
                HStack(spacing: 8) {
                    Button(L10n.text("intelligence.capsule.import")) {
                        Task { await model.chooseCapsuleImport() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button(L10n.text("intelligence.capsule.export")) {
                        Task { await model.chooseCapsuleExportDestination() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(12)
            }
            .frame(minWidth: 290, idealWidth: 330, maxWidth: 380)
            .intelligencePanel(elevated: true)

            capsuleDetail(palette: palette)
                .frame(minWidth: 430)
                .intelligencePanel(elevated: false)
        }
        .alert(L10n.text("intelligence.capsule.restore.confirm.title"), isPresented: $confirmsRestore) {
            Button(L10n.text("action.cancel"), role: .cancel) {}
            Button(L10n.text("intelligence.capsule.restore")) {
                Task { await model.restoreSelectedCapsule() }
            }
        } message: {
            Text(L10n.text("intelligence.capsule.restore.confirm.body"))
        }
    }

    @ViewBuilder
    private func capsuleDetail(palette: AppPalette) -> some View {
        if let capsule = model.selectedCapsule {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        GattoIcon(symbol: "shippingbox", size: 30)
                            .foregroundStyle(palette.primary)
                            .frame(width: 48, height: 48)
                            .background(palette.primarySoft)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(capsule.manifest.repositoryName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(palette.ink)
                            Text(capsule.manifest.createdAt.formatted(date: .abbreviated, time: .standard))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(palette.subtleInk)
                        }
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        CapsuleMetric(titleKey: "intelligence.capsule.files", value: "\(capsule.manifest.changedPaths.count)")
                        CapsuleMetric(titleKey: "intelligence.capsule.base", value: String(capsule.manifest.baseSHA.prefix(8)))
                        CapsuleMetric(titleKey: "intelligence.capsule.branch", value: capsule.manifest.branchName ?? "—")
                    }

                    if let command = capsule.manifest.failingCommand {
                        IntelligenceCard(titleKey: "intelligence.capsule.command", symbol: "terminal") {
                            Text(command)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    if let output = capsule.manifest.failureOutput {
                        IntelligenceCard(titleKey: "intelligence.capsule.output", symbol: "exclamationmark") {
                            ScrollView(.horizontal) {
                                Text(output)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 180)
                        }
                    }

                    IntelligenceCard(titleKey: "intelligence.capsule.environment", symbol: "wrench.and.screwdriver") {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(capsule.manifest.tools) { tool in
                                HStack(alignment: .top) {
                                    Text(tool.name).fontWeight(.semibold).frame(width: 72, alignment: .leading)
                                    Text(tool.version).textSelection(.enabled)
                                }
                            }
                        }
                        .font(.system(size: 10.5, design: .monospaced))
                    }

                    if !capsule.manifest.omittedPaths.isEmpty {
                        IntelligenceCard(titleKey: "intelligence.capsule.omitted", symbol: "eye.slash") {
                            Text(capsule.manifest.omittedPaths.joined(separator: "\n"))
                                .font(.system(size: 10.5, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }

                    if let error = model.capsuleError {
                        IntelligenceInlineError(message: error)
                    }
                    if let url = model.restoredCapsuleURL {
                        HStack {
                            Image(gattoSymbol: "checkmark.circle.fill").foregroundStyle(palette.success)
                            Text(L10n.format("intelligence.capsule.restored_at", url.path))
                                .font(.system(size: 10.5, design: .monospaced))
                                .lineLimit(2)
                            Spacer()
                            Button(L10n.text("intelligence.capsule.reveal")) { model.revealRestoredCapsule() }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }

                    HStack(spacing: 8) {
                        Button(L10n.text("intelligence.capsule.restore")) { confirmsRestore = true }
                            .buttonStyle(PrimaryButtonStyle())
                        Button(L10n.text("intelligence.capsule.delete"), role: .destructive) {
                            Task { await model.deleteSelectedCapsule() }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        Spacer()
                    }
                }
                .padding(16)
            }
        } else {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("intelligence.capsule.capture.title"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    TextField(L10n.text("intelligence.capsule.command.placeholder"), text: $model.capsuleFailingCommand)
                        .textFieldStyle(.roundedBorder)
                    TextEditor(text: $model.capsuleFailureOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 160)
                        .background(palette.raisedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 9).stroke(palette.divider) }
                        .overlay(alignment: .topLeading) {
                            if model.capsuleFailureOutput.isEmpty {
                                Text(L10n.text("intelligence.capsule.output.placeholder"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.subtleInk)
                                    .padding(14)
                                    .allowsHitTesting(false)
                            }
                        }
                    if let error = model.capsuleError { IntelligenceInlineError(message: error) }
                    HStack {
                        Spacer()
                        Button(L10n.text("intelligence.capsule.export")) {
                            Task { await model.chooseCapsuleExportDestination() }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(16)
                Spacer()
            }
        }
    }
}

private struct RepositoryActivityWorkspace: View {
    @ObservedObject var model: RepositoryIntelligenceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmsClear = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("intelligence.activity.title"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.ink)
                        Text(L10n.format("intelligence.activity.count", model.activityEvents.count))
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.subtleInk)
                    }
                    Spacer()
                    ToolbarIconButton(
                        systemName: "arrow.clockwise",
                        helpKey: "action.refresh",
                        isActive: model.isLoadingActivity
                    ) { Task { await model.refreshActivity() } }
                }
                .padding(.horizontal, 14)
                .frame(height: 58)
                Rectangle().fill(palette.divider).frame(height: 1)

                if model.activityEvents.isEmpty {
                    InspectorEmptyState(
                        image: "history.file",
                        titleKey: "intelligence.activity.empty.title",
                        bodyKey: "intelligence.activity.empty.body"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(model.activityEvents) { event in
                                ActivityEventRow(
                                    event: event,
                                    isSelected: model.selectedActivityEventID == event.id
                                ) { model.selectedActivityEventID = event.id }
                            }
                        }
                        .padding(10)
                    }
                }

                Rectangle().fill(palette.divider).frame(height: 1)
                HStack {
                    Button(L10n.text("intelligence.activity.clear"), role: .destructive) {
                        confirmsClear = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.activityEvents.isEmpty)
                    Spacer()
                }
                .padding(12)
            }
            .frame(minWidth: 320, idealWidth: 370, maxWidth: 430)
            .intelligencePanel(elevated: true)

            activityDetail(palette: palette)
                .frame(minWidth: 410)
                .intelligencePanel(elevated: false)
        }
        .alert(L10n.text("intelligence.activity.clear.confirm.title"), isPresented: $confirmsClear) {
            Button(L10n.text("action.cancel"), role: .cancel) {}
            Button(L10n.text("intelligence.activity.clear"), role: .destructive) {
                Task { await model.clearActivity() }
            }
        } message: {
            Text(L10n.text("intelligence.activity.clear.confirm.body"))
        }
    }

    @ViewBuilder
    private func activityDetail(palette: AppPalette) -> some View {
        if let event = model.selectedActivityEvent {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(gattoSymbol: confidenceSymbol(event.confidence))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(confidenceColor(event.confidence, palette: palette))
                            .frame(width: 44, height: 44)
                            .background(confidenceColor(event.confidence, palette: palette).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text(event.confidence.titleKey))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.ink)
                            Text(event.occurredAt.formatted(date: .abbreviated, time: .standard))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(palette.subtleInk)
                        }
                    }

                    Text(L10n.text("intelligence.activity.disclaimer"))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.mutedInk)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.primarySoft.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    HStack(spacing: 10) {
                        CapsuleMetric(
                            titleKey: "intelligence.activity.branch",
                            value: event.branch ?? "—"
                        )
                        CapsuleMetric(
                            titleKey: "intelligence.activity.commit",
                            value: event.headSHA.map { String($0.prefix(8)) } ?? "—"
                        )
                        CapsuleMetric(
                            titleKey: "intelligence.activity.files",
                            value: "\(event.changedPaths.count)"
                        )
                    }

                    IntelligenceCard(titleKey: "intelligence.activity.candidates", symbol: "person.2") {
                        if event.candidates.isEmpty {
                            Text(L10n.text("intelligence.activity.candidates.empty"))
                                .foregroundStyle(palette.subtleInk)
                        } else {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(event.candidates) { agent in
                                    HStack {
                                        Text(agent.name).fontWeight(.semibold)
                                        Spacer()
                                        Text("PID \(agent.processID)")
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundStyle(palette.subtleInk)
                                    }
                                }
                            }
                        }
                    }

                    IntelligenceCard(titleKey: "intelligence.activity.changed_files", symbol: "doc.on.doc") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(event.changedPaths, id: \.self) { path in
                                HStack(spacing: 7) {
                                    Image(gattoSymbol: event.deletedPaths.contains(path) ? "trash" : "doc")
                                        .foregroundStyle(event.deletedPaths.contains(path) ? palette.danger : palette.subtleInk)
                                    Text(path)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    if let error = model.activityError { IntelligenceInlineError(message: error) }
                }
                .padding(16)
            }
        } else {
            InspectorEmptyState(
                image: "history.file",
                titleKey: "intelligence.activity.select.title",
                bodyKey: "intelligence.activity.select.body"
            )
        }
    }

    private func confidenceSymbol(_ confidence: RepositoryActivityConfidence) -> String {
        switch confidence {
        case .high: "checkmark.shield"
        case .medium: "info.circle"
        case .ambiguous: "person.2"
        case .unknown: "person.crop.circle.badge.questionmark"
        }
    }

    private func confidenceColor(_ confidence: RepositoryActivityConfidence, palette: AppPalette) -> Color {
        switch confidence {
        case .high: palette.success
        case .medium: palette.warning
        case .ambiguous: palette.primary
        case .unknown: palette.subtleInk
        }
    }
}

private struct ActivityEventRow: View {
    let event: RepositoryActivityEvent
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 9) {
                Circle()
                    .fill(event.refChanged ? palette.primary : palette.warning)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 3) {
                    Text(eventSummary)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(event.occurredAt.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                }
                Spacer()
                Text(L10n.text(event.confidence.titleKey))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.primary : palette.mutedInk)
            }
            .padding(.horizontal, 10)
            .frame(height: 48)
            .background(isSelected ? palette.primarySoft : palette.raisedSurface.opacity(0.44))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var eventSummary: String {
        if event.refChanged, let sha = event.headSHA {
            return L10n.format("intelligence.activity.event.commit", String(sha.prefix(8)))
        }
        return L10n.format("intelligence.activity.event.files", event.changedPaths.count)
    }
}

private struct CapsuleRow: View {
    let capsule: ReproductionCapsule
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 9) {
                Image(gattoSymbol: "shippingbox")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.primary : palette.mutedInk)
                    .frame(width: 30, height: 30)
                    .background(isSelected ? palette.primarySoft : palette.raisedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(capsule.manifest.repositoryName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text(capsule.manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(palette.subtleInk)
                }
                Spacer()
                CountBadge(count: capsule.manifest.changedPaths.count, emphasized: isSelected)
            }
            .padding(.horizontal, 9)
            .frame(height: 50)
            .background(isSelected ? palette.primarySoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CapsuleMetric: View {
    let titleKey: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text(titleKey))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(palette.divider) }
    }
}

private struct IntelligenceCard<Content: View>: View {
    let titleKey: String
    let symbol: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(titleKey: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.titleKey = titleKey
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(gattoSymbol: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.primary)
                Text(L10n.text(titleKey))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.ink)
            }
            content
                .foregroundStyle(palette.mutedInk)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.raisedSurface.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(palette.divider) }
    }
}

private struct ProvenanceItemsList: View {
    let emptyKey: String
    let items: [String]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        if items.isEmpty {
            Text(L10n.text(emptyKey))
                .font(.system(size: 10.5))
                .foregroundStyle(palette.subtleInk)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.mutedInk)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct ChangeCountBadge: View {
    let added: Int
    let deleted: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 4) {
            Text("+\(added)").foregroundStyle(palette.success)
            Text("−\(deleted)").foregroundStyle(palette.danger)
        }
        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
    }
}

private struct IntelligenceInlineError: View {
    let message: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(alignment: .top, spacing: 8) {
            Image(gattoSymbol: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.danger)
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.danger)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.danger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct IntelligenceErrorState: View {
    let message: String
    let retry: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 12) {
            Image(gattoSymbol: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(palette.danger)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(palette.mutedInk)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 560)
            Button(L10n.text("action.retry"), action: retry)
                .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct IntelligenceNotice: View {
    let text: String
    let dismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 9) {
            Image(gattoSymbol: "checkmark.circle.fill")
                .foregroundStyle(palette.success)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.ink)
            Button(action: dismiss) {
                Image(gattoSymbol: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay { Capsule().stroke(palette.divider) }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

private extension RepositoryIntelligenceTab {
    var titleKey: String { "intelligence.tab.\(rawValue)" }

    var symbol: String {
        switch self {
        case .intent: "point.3.connected.trianglepath.dotted"
        case .provenance: "doc.text.magnifyingglass"
        case .capsules: "shippingbox"
        case .activity: "history.file"
        }
    }
}

private extension ChangeIntentKind {
    var titleKey: String { "intelligence.intent.kind.\(rawValue)" }
}

private extension RepositoryActivityConfidence {
    var titleKey: String { "intelligence.activity.confidence.\(rawValue)" }
}

private struct IntelligencePanelModifier: ViewModifier {
    let elevated: Bool
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppStyleDefaults.defaultTheme.rawValue

    func body(content: Content) -> some View {
        switch AppVisualTheme.resolved(themeRaw) {
        case .standard:
            content
        case .softGlass:
            content.appGlassPanel(cornerRadius: 14, elevated: elevated)
        case .emerald:
            content.emeraldSurface(elevated ? .elevated : .panel, cornerRadius: 16)
        case .folio:
            content.folioSurface(elevated ? .elevated : .panel, cornerRadius: 16)
        case .lumen:
            content.lumenSurface(elevated ? .chrome : .inset, cornerRadius: 14)
        case .console:
            content.appConsolePanel()
        }
    }
}

private extension View {
    func intelligencePanel(elevated: Bool) -> some View {
        modifier(IntelligencePanelModifier(elevated: elevated))
    }
}
