import SwiftUI
import AppKit

struct RepositoryIdentitiesPanel: View {
    @ObservedObject var workspace: WorkspaceViewModel
    @ObservedObject var tools: ProjectToolsViewModel
    let confirm: ProjectToolConfirmation
    @State private var profile = RepositoryIdentityProfile(title: "", name: "", email: "")
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("tools.identity.help")).font(.callout).foregroundStyle(.secondary)
            Text(L10n.text("tools.identity.effective")).font(.headline)
            ForEach(tools.identityValues) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(item.key).font(.system(size: 12, design: .monospaced)); Spacer(); Text(item.value.isEmpty ? "—" : item.value).textSelection(.enabled) }
                    Text(item.origin).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Button(L10n.text("tools.reload")) { Task { await tools.load(repository: workspace.snapshot?.rootURL, tool: .identities) } }
            Divider()
            ForEach(tools.state.profiles) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(item.title).font(.headline); Spacer(); Button(L10n.text("tools.edit")) { profile = item } }
                    Text(item.name + " <" + item.email + ">").font(.callout).textSelection(.enabled)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading) {
                        Button(L10n.text("tools.identity.bindRepository")) { bind(item, directory: false) }
                        Button(L10n.text("tools.identity.bindDirectory")) { bind(item, directory: true) }
                        Button(L10n.text("tools.delete"), role: .destructive) { confirm(L10n.text("tools.identity.deleteConfirm")) { await tools.action { try await tools.identities.delete(item) } } }
                    }.disabled(tools.busy || workspace.snapshot == nil)
                    ForEach(tools.state.bindings.filter { $0.profileID == item.id }) { binding in
                        HStack {
                            Text(binding.path).font(.caption).textSelection(.enabled)
                            Spacer()
                            Button(L10n.text("tools.identity.unbind")) { confirm(L10n.text("tools.identity.unbindConfirm") + "\n" + binding.path) {
                                await tools.action { try await tools.identities.unbind(binding) }; await tools.load(repository: workspace.snapshot?.rootURL, tool: .identities)
                            } }
                        }
                    }
                }.padding(.vertical, 8)
                Divider()
            }
            Text(L10n.text("tools.identity.profile")).font(.headline)
            TextField(L10n.text("tools.name"), text: $profile.title)
            TextField(L10n.text("tools.identity.author"), text: $profile.name)
            TextField(L10n.text("tools.identity.email"), text: $profile.email)
            Toggle(L10n.text("tools.identity.sign"), isOn: $profile.signCommits)
            if profile.signCommits {
                Picker(L10n.text("tools.identity.format"), selection: $profile.signingFormat) { Text("OpenPGP").tag("openpgp"); Text("SSH").tag("ssh"); Text("X.509").tag("x509") }
                TextField(L10n.text("tools.identity.key"), text: $profile.signingKey)
                Text(L10n.text("tools.identity.keyHelp")).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(L10n.text("tools.save")) { let value = profile; confirm(L10n.text("tools.identity.saveConfirm")) {
                    await tools.action { try await tools.identities.save(value) }; await tools.load(repository: workspace.snapshot?.rootURL, tool: .identities)
                } }.disabled(profile.title.isEmpty || profile.name.isEmpty || profile.email.isEmpty || tools.busy)
                Button(L10n.text("tools.new")) { profile = RepositoryIdentityProfile(title: "", name: "", email: "") }
            }
        }.textFieldStyle(.roundedBorder)
    }
    private func bind(_ value: RepositoryIdentityProfile, directory: Bool) {
        guard let root = workspace.snapshot?.rootURL else { return }
        if directory {
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.directoryURL = root.deletingLastPathComponent()
            panel.begin { response in if response == .OK, let url = panel.url { apply(value, target: url, directory: true, root: root) } }
        } else { apply(value, target: root, directory: false, root: root) }
    }
    private func apply(_ profile: RepositoryIdentityProfile, target: URL, directory: Bool, root: URL) {
        confirm(L10n.text(directory ? "tools.identity.directoryConfirm" : "tools.identity.repositoryConfirm") + "\n" + target.path + "\n" + profile.name + " <" + profile.email + ">") {
            await tools.action { try await workspace.performProjectToolMutation(.compare) { try await tools.identities.bind(profile, to: target, directory: directory, repository: root) } }
            await tools.load(repository: root, tool: .identities)
        }
    }
}
