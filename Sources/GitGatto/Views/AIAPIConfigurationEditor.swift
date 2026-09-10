import SwiftUI

struct AIAPIConfigurationEditor: View {
    @Binding var configuration: AIAPIConfiguration
    @Environment(\.colorScheme) private var colorScheme
    @State private var keyInput = ""
    @State private var hasKey = false
    @State private var error: String?

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(alignment: .leading, spacing: 14) {
            input("ai.api.url") {
                TextField("https://example.com/v1", text: $configuration.baseURL)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityLabel(L10n.text("ai.api.url"))
            }
            input("ai.api.model") {
                TextField(L10n.text("ai.api.model.placeholder"), text: $configuration.model)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityLabel(L10n.text("ai.api.model"))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key").font(.system(size: 11.5, weight: .medium)).foregroundStyle(palette.mutedInk)
                SecureField(L10n.text(hasKey ? "ai.api.key.saved" : "ai.api.key.placeholder"), text: $keyInput)
                    .environment(\.layoutDirection, .leftToRight)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("API Key")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { keyActions }
                    VStack(alignment: .leading, spacing: 10) { keyActions }
                }
            }
            Text(L10n.text("ai.api.help"))
                .font(.system(size: 10.5)).foregroundStyle(palette.subtleInk)
                .fixedSize(horizontal: false, vertical: true)
            if let error {
                Text(error).font(.system(size: 11.5)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(error)
            }
        }
        .task(id: configuration.credentialAccount) {
            keyInput = ""
            error = nil
            hasKey = AIAPICredentialStore.contains(configuration)
        }
    }

    @ViewBuilder private var keyActions: some View {
        Button(L10n.text("ai.api.key.save")) {
            do {
                try AIAPICredentialStore.save(keyInput, for: configuration)
                keyInput = ""
                hasKey = true
                error = nil
            } catch { self.error = error.localizedDescription }
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if hasKey {
            Button(L10n.text("ai.api.key.remove")) {
                do {
                    try AIAPICredentialStore.delete(configuration)
                    hasKey = false
                    error = nil
                } catch { self.error = error.localizedDescription }
            }
            .buttonStyle(SecondaryButtonStyle())
            Text(L10n.text("ai.api.key.saved"))
                .font(.system(size: 10.5)).foregroundStyle(AppPalette(colorScheme).mutedInk)
        }
    }

    private func input<Content: View>(_ key: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text(key)).font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AppPalette(colorScheme).mutedInk)
            content().textFieldStyle(.roundedBorder)
        }
    }
}
