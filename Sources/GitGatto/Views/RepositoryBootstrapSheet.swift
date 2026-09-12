import SwiftUI

struct RepositoryBootstrapSheet: View {
    @ObservedObject var workspace: WorkspaceViewModel
    @StateObject private var model: RepositoryBootstrapViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let openRepository: (URL, Bool) -> Void

    init(workspace: WorkspaceViewModel, model: RepositoryBootstrapViewModel = RepositoryBootstrapViewModel(),
         openRepository: @escaping (URL, Bool) -> Void) {
        self.workspace = workspace
        self._model = StateObject(wrappedValue: model)
        self.openRepository = openRepository
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text(model.inspection?.isRepository == true ? "repository.upstream.title" : "repository.create.title")).font(.title2.weight(.semibold)).padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("repository.create.folder")).font(.headline)
                        if let folder = model.folder {
                            Text(folder.path).font(.caption).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(L10n.text("repository.create.choose"), action: model.chooseFolder)
                            .buttonStyle(SecondaryButtonStyle()).disabled(model.isRunning || model.result != nil)
                    }
                    if model.isInspecting { ProgressView(L10n.text("loading.generic")) }
                    if let inspection = model.inspection, model.result == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            if !inspection.hasHEAD { Text(L10n.text("repository.create.files_note")).font(.callout).foregroundStyle(palette.mutedInk) }
                            if inspection.hasHEAD {
                                Text(L10n.text("repository.create.existing_note")).font(.callout).foregroundStyle(palette.mutedInk)
                            }
                            DisclosureGroup(L10n.text("repository.upstream.manual"), isExpanded: $model.manualOptions) {
                                field("repository.create.branch", text: $model.branch).disabled(inspection.isRepository)
                                if !inspection.hasHEAD {
                                    Toggle(L10n.text("repository.create.identity"), isOn: $model.customIdentity)
                                    if model.customIdentity {
                                        field("repository.create.author", text: $model.authorName)
                                        field("repository.create.email", text: $model.authorEmail)
                                    }
                                }
                                Divider()
                                Toggle(L10n.text("repository.create.remote"), isOn: $model.createRemote)
                                if model.createRemote {
                                    if let account = model.account {
                                        Text("GitHub · \(account.login)").font(.callout)
                                    }
                                    if model.isCheckingAccount { ProgressView().controlSize(.small) }
                                    Button(L10n.text("repository.create.refresh_account")) { model.accountRefreshID = UUID() }
                                        .disabled(model.isCheckingAccount)
                                    Button(L10n.text("github.action.login")) { workspace.beginGitHubLogin() }
                                        .buttonStyle(SecondaryButtonStyle())
                                    field("repository.upstream.owner", text: $model.owner)
                                    field("repository.create.name", text: $model.name)
                                    Picker(L10n.text("repository.create.visibility"), selection: $model.isPrivate) {
                                        Text(L10n.text("repository.create.private")).tag(true)
                                        Text(L10n.text("repository.create.public")).tag(false)
                                    }.pickerStyle(.segmented)
                                    Toggle(L10n.text("repository.create.existing"), isOn: $model.connectExisting)
                                    Toggle(L10n.text(inspection.canPushInitialCommit ? "repository.create.push" : "repository.upstream.push_history"), isOn: $model.pushInitialCommit)
                                }
                            }
                        }
                        .disabled(model.isRunning)
                    }
                    if !model.manualOptions, model.result == nil {
                        Text("GitHub · \(model.owner.isEmpty ? model.account?.login ?? "—" : model.owner) / \(model.name)")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text(L10n.text(model.isPrivate ? "repository.create.private" : "repository.create.public"))
                        if model.isCheckingAccount { ProgressView(L10n.text("loading.generic")) }
                        if model.account == nil, !model.isCheckingAccount {
                            Button(L10n.text("github.action.login")) { workspace.beginGitHubLogin() }
                            Button(L10n.text("repository.create.refresh_account")) { model.accountRefreshID = UUID() }
                        }
                    }
                    if !model.steps.isEmpty {
                        ForEach(RepositoryBootstrapStep.allCases) { step in
                            if let state = model.steps[step] {
                                HStack(alignment: .top, spacing: 10) {
                                    if case .running = state, model.isRunning { ProgressView().controlSize(.small) }
                                    else { Image(gattoSymbol: symbol(state)).foregroundStyle(model.error != nil && isRunning(state) ? palette.danger : palette.primary) }
                                    Text(L10n.text(step.titleKey)).font(.callout).fixedSize(horizontal: false, vertical: true)
                                    if case .skipped = state { Text("—").foregroundStyle(palette.mutedInk) }
                                }
                            }
                        }
                    }
                    if model.createRemote, let error = model.accountError { IntelligenceInlineError(report: error) }
                    if let error = model.error { IntelligenceInlineError(report: error) }
                    if let result = model.result {
                        GattoLabel(L10n.text("repository.create.success"), systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(palette.success)
                        if let remote = result.remote { Link(remote.fullName, destination: remote.webURL) }
                        Text(L10n.text("repository.upstream.preserved")).font(.callout).foregroundStyle(palette.mutedInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack { footer }
                VStack(alignment: .leading, spacing: 10) { footer }
            }
            .padding(16)
        }
        .frame(minWidth: 380, idealWidth: 560, minHeight: 460, idealHeight: 660)
        .background(palette.surface)
        .interactiveDismissDisabled(model.isRunning)
        .onChange(of: model.createRemote) { _, enabled in if enabled { model.accountRefreshID = UUID() } }
        .task(id: model.accountRefreshID) { await model.refreshAccount(); model.startAutomaticAgentIfReady() }
        .task(id: model.folder) { await model.inspectFolder(); await model.refreshAccount(); model.startAutomaticAgentIfReady() }
        .task(id: model.runID) {
            await model.performRequest()
            if let result = model.result { await workspace.repositoryConfigurationCompleted(in: result.folder) }
        }
        .alert(L10n.text("repository.upstream.confirm"), isPresented: $model.showsConfirmation) {
            Button(L10n.text("action.cancel"), role: .cancel, action: model.cancelConfirmation)
            Button(L10n.text("repository.upstream.continue"), action: model.confirmRequest)
        } message: { Text(model.confirmationText) }
    }

    @ViewBuilder private var footer: some View {
        Button(L10n.text(model.result == nil ? "action.cancel" : "action.close")) { dismiss() }.disabled(model.isRunning)
            .buttonStyle(SecondaryButtonStyle())
        if let result = model.result {
            Button(L10n.text("repository.create.agent")) { openRepository(result.folder, true) }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(workspace.codexAvailability.state != .available || workspace.isCodexRunning)
            Button(L10n.text("action.open_repository")) { openRepository(result.folder, false) }
                .buttonStyle(PrimaryButtonStyle())
        } else {
            if model.manualOptions {
                Button(L10n.text("repository.upstream.manual_execute")) { model.requestCreate() }
                    .buttonStyle(SecondaryButtonStyle()).disabled(!model.canCreate)
            }
            Button(L10n.text("repository.upstream.agent")) { model.requestCreate(usingAgent: true) }
                .buttonStyle(PrimaryButtonStyle()).disabled(!model.canRunAgent)
        }
    }

    private func field(_ key: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text(key)).font(.caption).foregroundStyle(AppPalette(colorScheme).mutedInk)
            TextField(L10n.text(key), text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func isRunning(_ state: RepositoryBootstrapEvent.State) -> Bool { if case .running = state { true } else { false } }
    private func symbol(_ state: RepositoryBootstrapEvent.State) -> String {
        switch state {
        case .complete: "checkmark.circle.fill"
        case .skipped: "minus.circle"
        case .running: "exclamationmark.triangle.fill"
        }
    }
}
