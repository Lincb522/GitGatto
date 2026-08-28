import SwiftUI

struct UpdateActionButton: View {
    let state: AppUpdateState
    var isEnabled = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue

    private var displayedState: AppUpdateState {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--update-button-state"),
           arguments.indices.contains(index + 1) {
            switch arguments[index + 1] {
            case "checking": return .checking
            case "available": return .updateAvailable(version: "0.16.0", build: "16000")
            case "current": return .current
            default: break
            }
        }
#endif
        return state
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                UpdateActionGlyph(
                    state: displayedState,
                    color: foregroundColor,
                    reduceMotion: reduceMotion
                )

                Text(L10n.text(titleKey))
                    .lineLimit(1)
                    .id(titleKey)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            .animation(
                .spring(response: 0.28, dampingFraction: 0.84),
                value: displayedState
            )
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!isEnabled || displayedState == .checking)
        .opacity(!isEnabled ? 0.58 : 1)
        .accessibilityLabel(L10n.text(titleKey))
    }

    private var foregroundColor: Color {
        let palette = AppPalette(colorScheme)
        return AppVisualTheme.resolved(themeRaw) == .console ? palette.background : .white
    }

    private var titleKey: String {
        switch displayedState {
        case .checking: "update.action.checking"
        case .updateAvailable: "update.action.install"
        case .current: "update.action.check_again"
        default: "update.check"
        }
    }
}

private struct UpdateActionGlyph: View {
    let state: AppUpdateState
    let color: Color
    let reduceMotion: Bool

    private var isContinuouslyAnimated: Bool {
        state == .checking || isUpdateAvailable
    }

    private var isUpdateAvailable: Bool {
        if case .updateAvailable = state { return true }
        return false
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 45.0,
                paused: reduceMotion || !isContinuouslyAnimated
            )
        ) { timeline in
            glyph(at: timeline.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: 18, height: 18)
    }

    @ViewBuilder
    private func glyph(at time: TimeInterval) -> some View {
        switch state {
        case .checking:
            ZStack {
                Circle()
                    .stroke(color.opacity(0.24), lineWidth: 1.5)
                Circle()
                    .trim(from: 0.06, to: 0.68)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(reduceMotion ? 0 : time * 470))
            }
            .frame(width: 16, height: 16)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))

        case .updateAvailable:
            let wave = reduceMotion ? 0.5 : (sin(time * .pi * 2 / 1.05) + 1) / 2
            ZStack {
                Circle()
                    .stroke(color.opacity(0.34), lineWidth: 1)
                    .scaleEffect(1 + wave * 0.28)
                    .opacity(0.72 - wave * 0.48)
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                    .offset(y: wave * 2 - 1)
            }
            .frame(width: 17, height: 17)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))

        case .current:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .transition(.opacity.combined(with: .scale(scale: 0.90)))

        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))

        case .configurationRequired, .ready:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
    }
}
