import SwiftUI

struct AIAPIConfigurationEditor: View {
    @Binding var configuration: AIAPIConfiguration
    @Environment(\.colorScheme) private var colorScheme
    @State private var keyInput = ""
    @State private var hasKey = false
    @State private var error: String?
    @State private var models: [String] = []
    @State private var resultKey: String?
    @State private var testing = false
    @State private var requestID: UUID?
    @State private var requestTask: Task<Void, Never>?
    private let client = AIAPIClient()

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
            if !models.isEmpty {
                Menu(L10n.text("ai.api.chooseModel")) {
                    ForEach(models, id: \.self) { model in
                        Button(model) { configuration.model = model }
                    }
                }.menuStyle(.borderlessButton)
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
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { testActions }
                VStack(alignment: .leading, spacing: 10) { testActions }
            }
            Text(L10n.text("ai.api.testHelp")).font(.caption).foregroundStyle(palette.subtleInk)
                .fixedSize(horizontal: false, vertical: true)
            if let resultKey {
                Text(L10n.text(resultKey)).font(.caption).foregroundStyle(palette.success)
                    .fixedSize(horizontal: false, vertical: true)
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
        .onChange(of: configuration) { previous, next in
            requestTask?.cancel(); requestTask = nil; requestID = nil
            testing = false; resultKey = nil; error = nil
            if previous.credentialAccount != next.credentialAccount { models = [] }
        }
        .onDisappear { requestTask?.cancel(); requestTask = nil; requestID = nil; testing = false }
        .task(id: configuration.credentialAccount) {
            keyInput = ""
            error = nil
            hasKey = AIAPICredentialStore.contains(configuration)
        }
    }

    @ViewBuilder private var testActions: some View {
        if testing {
            ProgressView().controlSize(.small)
            Button(L10n.text("action.cancel")) {
                requestTask?.cancel(); requestTask = nil; requestID = nil; testing = false
            }.buttonStyle(SecondaryButtonStyle())
        } else {
            Button(L10n.text("ai.api.loadModels")) { test(.models) }.buttonStyle(SecondaryButtonStyle())
            Button(L10n.text("ai.api.testChat")) { test(.chat) }.buttonStyle(SecondaryButtonStyle())
            Button(L10n.text("ai.api.testTools")) { test(.tools) }.buttonStyle(SecondaryButtonStyle())
        }
    }

    private enum Check { case models, chat, tools }

    private func test(_ check: Check) {
        let id = UUID()
        let input = configuration
        requestID = id; testing = true; resultKey = nil; error = nil
        requestTask = Task { @MainActor in
            defer { if requestID == id { testing = false; requestTask = nil } }
            do {
                switch check {
                case .models:
                    let values = try await client.models(input)
                    guard requestID == id, !Task.isCancelled else { return }
                    models = values
                    resultKey = values.isEmpty ? "ai.api.noModels" : "ai.api.catalogOnly"
                case .chat, .tools:
                    try await client.testConnection(input, tools: check == .tools)
                    guard requestID == id, !Task.isCancelled else { return }
                    resultKey = check == .tools ? "ai.api.toolsVerified" : "ai.api.chatVerified"
                }
            } catch is CancellationError { }
            catch {
                if requestID == id, !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    @ViewBuilder private var keyActions: some View {
        Button(L10n.text("ai.api.key.save")) {
            do {
                try AIAPICredentialStore.save(keyInput, for: configuration)
                keyInput = ""
                hasKey = true
                error = nil
                resultKey = nil
                requestTask?.cancel(); requestID = nil; testing = false
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
