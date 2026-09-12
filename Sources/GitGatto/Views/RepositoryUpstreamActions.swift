import SwiftUI

struct RepositoryUpstreamActions: View {
    @ObservedObject var model: WorkspaceViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { content }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 10) { content }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette(colorScheme).surface)
        .disabled(model.activeOperation != nil)
    }

    @ViewBuilder private var content: some View {
        Text(L10n.text("repository.upstream.missing")).font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        Button(L10n.text("repository.upstream.agent")) {
            model.presentRepositoryCreation(folder: model.snapshot?.rootURL, usingAgent: true)
        }.buttonStyle(PrimaryButtonStyle())
        Button(L10n.text("repository.upstream.manual")) {
            model.presentRepositoryCreation(folder: model.snapshot?.rootURL)
        }.buttonStyle(SecondaryButtonStyle())
    }
}
