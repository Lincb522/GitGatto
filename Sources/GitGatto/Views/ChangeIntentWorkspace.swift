import SwiftUI

struct ChangeIntentWorkspace: View {
    @ObservedObject var model: RepositoryIntelligenceViewModel
    @ObservedObject var workspaceModel: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsApplyConfirmation = false
    @State private var showsRefreshConfirmation = false
    @State private var preview: ChangeIntentFile?

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            if let selection = model.intentSelection {
                ChangeIntentSelectionBanner(selection: selection, isBusy: model.isIntentBusy) {
                    Task { await model.useAllIntentChanges() }
                }
                Divider().overlay(palette.divider)
            }
            if model.isLoadingIntentPlan, model.intentPlan == nil {
                GattoLoadingState(text: L10n.text("intelligence.intent.loading"))
            } else if let result = model.intentApplyResult {
                resultView(result, palette: palette)
            } else if let plan = model.intentPlan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        composer(plan: plan, palette: palette)
                        if let error = model.intentError { IntelligenceInlineError(message: error) }
                        LazyVStack(spacing: 12) {
                            ForEach(Array(plan.groups.enumerated()), id: \.element.id) { index, group in
                                ChangeIntentCommitCard(model: model, plan: plan, group: group,
                                    index: index, onPreview: { preview = $0 })
                            }
                        }
                        DisclosureGroup(L10n.text("intelligence.intent.advanced")) {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField(L10n.text("intelligence.intent.verify_placeholder"), text: $model.verificationCommand)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel(L10n.text("intelligence.intent.verify_placeholder"))
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 10) { manualActions }
                                    VStack(alignment: .leading, spacing: 10) { manualActions }
                                }
                            }.padding(.top, 10)
                        }
                        .font(.system(size: 12))
                        .disabled(model.isIntentBusy)
                    }
                    .padding(20)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                Divider().overlay(palette.divider)
                footer(plan: plan, palette: palette)
            } else if let error = model.intentError {
                IntelligenceErrorState(message: error) { Task { await model.refreshIntentPlan() } }
            } else {
                VStack(spacing: 14) {
                    InspectorEmptyState(image: "checkmark.circle", titleKey: "intelligence.intent.empty.title",
                        bodyKey: "intelligence.intent.empty.body")
                    Button(L10n.text("action.refresh")) { Task { await model.refreshIntentPlan() } }
                        .buttonStyle(SecondaryButtonStyle())
                }.padding(20)
            }
        }
        .intelligencePanel(elevated: false)
        .alert(L10n.text("intelligence.intent.confirm.title"), isPresented: $showsApplyConfirmation) {
            Button(L10n.text("action.cancel"), role: .cancel) {}
            Button(L10n.text("intelligence.intent.apply")) {
                Task { if await model.applyIntentPlan() { await workspaceModel.refresh() } }
            }
        } message: {
            Text(L10n.format("intelligence.intent.confirm.body", model.intentPlan?.groups.count ?? 0))
        }
        .alert(L10n.text("intelligence.intent.refresh_confirm"), isPresented: $showsRefreshConfirmation) {
            Button(L10n.text("action.cancel"), role: .cancel) {}
            Button(L10n.text("action.refresh")) { Task { await model.refreshIntentPlan() } }
        } message: { Text(L10n.text("intelligence.intent.refresh_confirm.body")) }
        .sheet(item: $preview) { file in ChangeIntentPatchPreview(file: file) }
    }

    private func composer(plan: ChangeIntentPlan, palette: AppPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.format("intelligence.intent.summary", plan.fileCount, plan.groups.count))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                ToolbarIconButton(systemName: "arrow.clockwise", helpKey: "action.refresh",
                    isActive: model.isLoadingIntentPlan, isDisabled: model.isIntentBusy) {
                    if model.intentPlanReady { showsRefreshConfirmation = true }
                    else { Task { await model.refreshIntentPlan() } }
                }
            }
            TextField(L10n.text("intelligence.intent.instruction"), text: $model.intentInstruction, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(L10n.text("intelligence.intent.instruction"))
                .disabled(model.isIntentBusy)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { modePicker; Spacer(minLength: 0); planningAction }
                VStack(alignment: .leading, spacing: 12) { modePicker; planningAction }
            }
            if model.isRefiningIntentPlan {
                HStack(spacing: 6) {
                    Image(gattoSymbol: "doc.text.magnifyingglass")
                    Text(L10n.text("intelligence.intent.planning"))
                }
                    .font(.system(size: 11.5)).foregroundStyle(palette.mutedInk)
            } else if !model.intentPlanReady {
                Text(L10n.text("intelligence.intent.draft_hint"))
                    .font(.system(size: 11.5)).foregroundStyle(palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var modePicker: some View {
        Picker(L10n.text("intelligence.intent.split_mode"), selection: $model.intentSplitMode) {
            ForEach(ChangeIntentSplitMode.allCases) { mode in
                Text(L10n.text("intelligence.intent.split.\(mode.rawValue)")).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .disabled(model.isIntentBusy)
        .accessibilityLabel(L10n.text("intelligence.intent.split_mode"))
    }

    @ViewBuilder private var planningAction: some View {
        if model.isRefiningIntentPlan {
            Button(L10n.text("action.cancel")) { model.cancelIntentAgent() }
                .buttonStyle(SecondaryButtonStyle())
        } else if model.intentPlanReady {
            Button(L10n.text("intelligence.intent.replan")) { model.refineIntentPlanWithAgent() }
                .buttonStyle(SecondaryButtonStyle()).disabled(model.isIntentBusy)
        } else {
            Button(L10n.text("intelligence.intent.agent")) { model.refineIntentPlanWithAgent() }
                .buttonStyle(PrimaryButtonStyle()).disabled(model.isIntentBusy)
        }
    }

    @ViewBuilder private var manualActions: some View {
        Button(L10n.text("intelligence.intent.add_group")) { model.addIntentGroup() }
            .buttonStyle(SecondaryButtonStyle())
        Button(L10n.text("intelligence.intent.merge_all")) { model.mergeIntentGroups() }
            .buttonStyle(SecondaryButtonStyle()).disabled((model.intentPlan?.groups.count ?? 0) < 2)
    }

    private func footer(plan: ChangeIntentPlan, palette: AppPalette) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { executionState(plan: plan); Spacer(minLength: 8); createAction }
            VStack(alignment: .leading, spacing: 12) { executionState(plan: plan); createAction }
        }
        .font(.system(size: 11.5)).foregroundStyle(palette.mutedInk)
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    @ViewBuilder private func executionState(plan: ChangeIntentPlan) -> some View {
        if model.isApplyingIntentPlan {
            HStack { ProgressView().controlSize(.small); Text(L10n.text("intelligence.intent.applying")) }
        } else {
            Text(L10n.text(plan.canApply ? "intelligence.intent.local_only" : "intelligence.intent.incomplete"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var createAction: some View {
        if model.intentPlanReady {
            Button(L10n.text("intelligence.intent.apply")) { showsApplyConfirmation = true }
                .buttonStyle(PrimaryButtonStyle()).disabled(!model.canApplyIntentPlan)
        } else {
            Button(L10n.text("intelligence.intent.apply")) { showsApplyConfirmation = true }
                .buttonStyle(SecondaryButtonStyle()).disabled(!model.canApplyIntentPlan)
        }
    }

    private func resultView(_ result: ChangeIntentApplyResult, palette: AppPalette) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(gattoSymbol: "checkmark.circle")
                    Text(L10n.text("intelligence.intent.result.title"))
                }
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.success)
                Text(L10n.format("intelligence.intent.result.body", result.commitHashes.count))
                    .font(.system(size: 12.5)).foregroundStyle(palette.mutedInk)
                ForEach(result.commitHashes, id: \.self) { hash in
                    Text(String(hash.prefix(10))).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }
                Button(L10n.text("intelligence.intent.refresh")) { Task { await model.refreshIntentPlan() } }
                    .buttonStyle(SecondaryButtonStyle())
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ChangeIntentCommitCard: View {
    @ObservedObject var model: RepositoryIntelligenceViewModel
    let plan: ChangeIntentPlan
    let group: ChangeIntentGroup
    let index: Int
    let onPreview: (ChangeIntentFile) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var expanded = false
    @State private var editing = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        let files = plan.files(in: group)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(String(index + 1)).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.primary).frame(minWidth: 18)
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(group.commitMessage).font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(palette.mutedInk).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Menu {
                    Button(L10n.text("intelligence.intent.move_up")) { model.moveIntentGroup(group.id, offset: -1) }.disabled(index == 0)
                    Button(L10n.text("intelligence.intent.move_down")) { model.moveIntentGroup(group.id, offset: 1) }.disabled(index == plan.groups.count - 1)
                    Button(L10n.text("intelligence.intent.merge_group")) { model.removeIntentGroup(group.id) }.disabled(plan.groups.count < 2)
                } label: { Color.clear.frame(width: 28, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(width: 28, height: 28)
                .overlay {
                    GattoIcon(symbol: "arrow.up.arrow.down", size: 18)
                        .foregroundStyle(palette.mutedInk).allowsHitTesting(false)
                }
                .accessibilityLabel(L10n.text("intelligence.intent.commit_actions"))
                .help(L10n.text("intelligence.intent.commit_actions"))
                .disabled(model.isIntentBusy)
            }
            ForEach(expanded ? files : Array(files.prefix(3))) { file in
                HStack(spacing: 8) {
                    Button { onPreview(file) } label: {
                        HStack(spacing: 8) {
                            Image(gattoSymbol: "doc").foregroundStyle(palette.subtleInk)
                            Text(file.path).font(.system(size: 11.5)).foregroundStyle(palette.ink)
                                .lineLimit(2).truncationMode(.middle).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            ChangeCountBadge(added: file.added, deleted: file.deleted)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).help(file.path)
                    if editing { fileMenu(file) }
                }
            }
            if files.count > 3 {
                Button(L10n.text(expanded ? "intelligence.intent.files_less" : "intelligence.intent.files_more")) { expanded.toggle() }
                    .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(palette.primary)
            }
            DisclosureGroup(L10n.text("intelligence.intent.edit"), isExpanded: $editing) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(L10n.text("intelligence.intent.group_title"), text: textBinding(\.title))
                        .accessibilityLabel(L10n.text("intelligence.intent.group_title"))
                    TextField(L10n.text("intelligence.intent.commit_message"), text: textBinding(\.commitMessage), axis: .vertical)
                        .lineLimit(1...4).accessibilityLabel(L10n.text("intelligence.intent.commit_message"))
                    Picker(L10n.text("intelligence.intent.category"), selection: Binding(get: { group.kind }, set: { model.updateIntentGroup(group.id, kind: $0) })) {
                        ForEach(ChangeIntentKind.allCases) { kind in Text(L10n.text("intelligence.intent.kind.\(kind.rawValue)")).tag(kind) }
                    }
                    if files.isEmpty { Text(L10n.text("intelligence.intent.group_empty")).foregroundStyle(palette.danger) }
                    ForEach(files.filter { $0.units.count > 1 }) { file in
                        DisclosureGroup(file.path) {
                            ForEach(file.units) { unit in
                                HStack {
                                    Button(unit.hunkHeader ?? unit.path) { onPreview(ChangeIntentFile(path: unit.path, units: [unit])) }
                                        .buttonStyle(.plain).font(.system(size: 10.5, design: .monospaced))
                                    Spacer(minLength: 4)
                                    moveMenu(unitIDs: [unit.id])
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }.textFieldStyle(.roundedBorder).padding(.top, 10)
            }
            .font(.system(size: 11.5)).disabled(model.isIntentBusy)
        }
        .padding(14)
        .background(palette.surface.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(palette.divider) }
        .onAppear { expandNewGroup() }
        .onChange(of: model.selectedIntentGroupID) { _, _ in expandNewGroup() }
    }

    private func expandNewGroup() {
        if group.unitIDs.isEmpty, model.selectedIntentGroupID == group.id { editing = true }
    }

    private func fileMenu(_ file: ChangeIntentFile) -> some View { moveMenu(unitIDs: file.units.map(\.id)) }

    private func moveMenu(unitIDs: [String]) -> some View {
        Menu(L10n.text("intelligence.intent.move_changes")) {
            ForEach(plan.groups.filter { $0.id != group.id }) { target in
                Button(target.title) { for id in unitIDs { model.moveIntentUnit(id, to: target.id) } }
            }
            Button(L10n.text("intelligence.intent.split_file")) { model.splitIntentUnits(unitIDs) }
        }.fixedSize().disabled(model.isIntentBusy)
    }

    private func textBinding(_ keyPath: WritableKeyPath<ChangeIntentGroup, String>) -> Binding<String> {
        Binding(get: { model.intentPlan?.groups.first { $0.id == group.id }?[keyPath: keyPath] ?? "" }, set: {
            if keyPath == \.title { model.updateIntentGroup(group.id, title: $0) }
            else { model.updateIntentGroup(group.id, message: $0) }
        })
    }
}

struct ChangeIntentPatchPreview: View {
    let file: ChangeIntentFile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(file.path).font(.system(size: 13, weight: .semibold)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(L10n.text("action.close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(16)
            Divider()
            if file.units.contains(where: { $0.patch != nil }) {
                DiffCodeView(document: GitParsers.diff(from: file.units.compactMap(\.patch).joined(), path: file.path))
            } else if let preview = file.units.first?.contextPreview {
                ScrollView([.horizontal, .vertical]) {
                    Text(preview).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(16)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                InspectorEmptyState(image: "doc", titleKey: "intelligence.intent.whole_file.title", bodyKey: "intelligence.intent.whole_file.body")
            }
        }
        .frame(minWidth: 440, idealWidth: 740, minHeight: 360, idealHeight: 540)
        .background(AppPalette(colorScheme).background)
    }
}

struct ChangeIntentSelectionBanner: View {
    let selection: ChangeIntentSelection
    let isBusy: Bool
    let showAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { detail; allButton }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.format("intelligence.intent.selection.scope", selection.lineCount))
                .font(.system(size: 12, weight: .semibold))
            Text(selection.path).font(.system(size: 11, design: .monospaced)).lineLimit(2).truncationMode(.middle)
            Text(L10n.text("intelligence.intent.selection.retained"))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var allButton: some View {
        Button(L10n.text("intelligence.intent.selection.all"), action: showAll)
            .buttonStyle(SecondaryButtonStyle()).disabled(isBusy)
    }
}
