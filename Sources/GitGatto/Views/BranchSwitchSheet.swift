import SwiftUI

struct BranchSwitchSheet: View {
    @ObservedObject var workspace: WorkspaceViewModel
    @ObservedObject var tools: ProjectToolsViewModel
    let request: BranchSwitchRequest
    let openScenes: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var preview: WorkSceneSwitchPreview?
    @State private var error: String?
    @State private var busy = false
    @State private var finished = false
    @State private var savedScene: WorkScene?
    @State private var attempt = 0

    var body: some View {
        BranchSwitchContent(preview: preview, error: error, busy: busy, finished: finished,
            savedScene: savedScene, confirm: { Task { await apply() } }, retry: { attempt += 1 },
            close: { dismiss() }, openScenes: openScenes)
        .frame(minWidth: 460, idealWidth: 620, maxWidth: 800, minHeight: 460, idealHeight: 560, maxHeight: 740)
        .interactiveDismissDisabled(busy)
        .task(id: attempt) {
            guard !finished, savedScene == nil else { return }
            preview = nil; error = nil
            do {
                let loaded = try await tools.scenes.previewSwitch(to: request.targetBranch, repository: request.repository)
                try Task.checkCancellation()
                preview = loaded
            } catch is CancellationError { }
            catch { self.error = ProjectCommandOutput.redact(error.localizedDescription) }
        }
    }

    private func apply() async {
        guard let preview, !busy, !finished, savedScene == nil else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            savedScene = try await workspace.saveSceneAndSwitch(preview, using: tools.scenes)
            finished = true
            if savedScene == nil { dismiss() }
        } catch let failure as WorkSceneSwitchFailure {
            savedScene = failure.scene
            error = ProjectCommandOutput.redact(failure.localizedDescription)
        } catch {
            self.error = ProjectCommandOutput.redact(error.localizedDescription)
            self.preview = nil
        }
    }
}

struct BranchSwitchContent: View {
    let preview: WorkSceneSwitchPreview?
    let error: String?
    let busy: Bool
    let finished: Bool
    let savedScene: WorkScene?
    let confirm: () -> Void
    let retry: () -> Void
    let close: () -> Void
    let openScenes: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("branches.quick_switch")).font(.headline).padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let preview {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { branchNames(preview, vertical: false) }
                            VStack(alignment: .leading, spacing: 8) { branchNames(preview, vertical: true) }
                        }.font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        Text(preview.repository.path).font(.caption).foregroundStyle(palette.mutedInk).textSelection(.enabled)
                        if finished {
                            Label { Text(L10n.text("notice.branch_switched")) } icon: { Image(gattoSymbol: "checkmark.circle") }
                                .foregroundStyle(palette.success)
                        } else if savedScene == nil, !preview.changes.isEmpty {
                            Text(L10n.text("branches.scene.scope")).font(.callout).foregroundStyle(palette.mutedInk)
                            Text(L10n.format("branches.scene.files", preview.changes.count)).font(.subheadline.weight(.semibold))
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(preview.changes) { change in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("\(change.indexStatus.rawValue)\(change.workTreeStatus.rawValue)")
                                            .font(.system(.caption, design: .monospaced)).foregroundStyle(palette.mutedInk)
                                        Text(change.originalPath.map { $0 + " → " + change.path } ?? change.path)
                                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        } else if savedScene == nil { Text(L10n.text("branches.scene.clean")).foregroundStyle(palette.mutedInk) }
                    } else if error == nil {
                        ProgressView().controlSize(.small).accessibilityLabel(L10n.text("action.refresh"))
                    }
                    if let error {
                        Text(error).font(.callout).foregroundStyle(palette.warning).textSelection(.enabled)
                        if savedScene == nil { Button(L10n.text("action.refresh"), action: retry).buttonStyle(SecondaryButtonStyle()) }
                    }
                    if let savedScene {
                        if error == nil { Text(L10n.format("branches.scene.saved", savedScene.branch)).font(.callout) }
                        Button(L10n.text("tools.scenes"), action: openScenes).buttonStyle(SecondaryButtonStyle())
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack { Spacer(); actions }
                VStack(alignment: .trailing, spacing: 10) { actions }.frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(16)
        }.foregroundStyle(palette.ink).background(palette.background)
    }

    @ViewBuilder private func branchNames(_ preview: WorkSceneSwitchPreview, vertical: Bool) -> some View {
        Text(preview.branch)
        Image(gattoSymbol: vertical ? "arrow.down" : layoutDirection == .rightToLeft ? "arrow.left" : "arrow.right")
        Text(preview.targetBranch).fontWeight(.semibold)
    }

    @ViewBuilder private var actions: some View {
        Button(L10n.text(finished || savedScene != nil ? "action.close" : "action.cancel"), action: close)
            .buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction).disabled(busy)
        if !finished, savedScene == nil {
            Button(action: confirm) {
                HStack {
                    if busy { ProgressView().controlSize(.small) }
                    Text(L10n.text(preview?.changes.isEmpty == false ? "branches.scene.saveSwitch" : "branches.quick_switch"))
                }
            }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                .disabled(preview == nil || error != nil || busy)
        }
    }
}
