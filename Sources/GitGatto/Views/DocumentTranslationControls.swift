import SwiftUI

struct DocumentTranslationControls: View {
    let activeTarget: CodexTranslationTarget?
    let availableTargets: [CodexTranslationTarget]
    let preferredTarget: CodexTranslationTarget
    let isTranslating: Bool
    let isDisabled: Bool
    let error: String?
    let completionID: UUID?
    let showOriginal: () -> Void
    let showTranslation: (CodexTranslationTarget) -> Void
    let translate: (CodexTranslationTarget) -> Void
    let cancel: () -> Void
    var progressTitle: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Button(L10n.text("github.readme.original"), action: showOriginal)
                ForEach(availableTargets) { target in
                    Button(L10n.text("codex.translate.\(target.rawValue)")) { showTranslation(target) }
                }
            } label: {
                Text(activeTarget.map { L10n.text("codex.translate.short.\($0.rawValue)") }
                    ?? L10n.text("github.readme.original"))
            }
            .disabled(isDisabled)
            if isTranslating {
                Button(action: cancel) {
                    DocumentTranslationActionLabel(title: L10n.text("codex.action.translate"),
                        activeTitle: progressTitle ?? L10n.text("codex.status.translating"), isActive: true,
                        completionID: completionID, showsCancelIndicator: true)
                }
                .buttonStyle(.plain)
            } else {
                if error != nil {
                    Button(L10n.text("action.retry")) { translate(preferredTarget) }
                        .buttonStyle(SecondaryButtonStyle()).disabled(isDisabled)
                }
                Menu {
                    ForEach(CodexTranslationTarget.allCases) { target in
                        Button(L10n.text("codex.translate.\(target.rawValue)")) { translate(target) }
                    }
                } label: {
                    DocumentTranslationActionLabel(title: L10n.text("codex.action.translate"),
                        activeTitle: L10n.text("codex.status.translating"), isActive: false,
                        completionID: completionID, showsInitialCompletion: true)
                }
                .disabled(isDisabled)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
