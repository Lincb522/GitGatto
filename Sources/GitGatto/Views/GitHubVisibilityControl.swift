import SwiftUI

struct GitHubVisibilityControl: View {
    let fullName: String
    var changed: (GitHubVisibilityState) -> Void = { _ in }
    @StateObject private var model: GitHubVisibilityViewModel
    @Environment(\.colorScheme) private var colorScheme

    init(fullName: String, model: GitHubVisibilityViewModel = GitHubVisibilityViewModel(),
         changed: @escaping (GitHubVisibilityState) -> Void = { _ in }) {
        self.fullName = fullName
        self.changed = changed
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { controls }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) { controls }
            }
            if let error = model.error { IntelligenceInlineError(report: error) }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: fullName) { await model.load(fullName) }
        .task(id: model.actionID) {
            if let value = await model.performChange() { changed(value) }
        }
        .alert(L10n.text("repository.create.visibility"), isPresented: $model.showsConfirmation) {
            Button(L10n.text("action.cancel"), role: .cancel) {}
            Button(L10n.text("repository.upstream.continue"), action: model.confirmChange)
        } message: { Text(model.confirmationText) }
    }

    @ViewBuilder private var controls: some View {
        if model.isBusy { ProgressView().controlSize(.small) }
        if let state = model.state {
            GattoLabel(L10n.text(state.isPrivate ? "repository.create.private" : "repository.create.public"),
                       systemImage: state.isPrivate ? "lock" : "globe")
            if state.canChange {
                Button(L10n.text(state.isPrivate ? "repository.visibility.make_public" : "repository.visibility.make_private"), action: model.requestChange)
                    .buttonStyle(SecondaryButtonStyle()).disabled(model.isBusy)
            } else {
                Text(L10n.text("repository.visibility.error.permission"))
                    .foregroundStyle(AppPalette(colorScheme).mutedInk).fixedSize(horizontal: false, vertical: true)
            }
        }
        if model.error != nil {
            Button(L10n.text("action.retry")) { Task { await model.load(fullName, force: true) } }.disabled(model.isBusy)
        }
    }
}
