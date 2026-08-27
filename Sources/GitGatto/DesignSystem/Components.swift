import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let palette = AppPalette(colorScheme)
        if AppVisualTheme.resolved(themeRaw) == .standard {
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(palette.primary.opacity(configuration.isPressed ? 0.78 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        } else {
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background {
                    RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                        .fill(palette.primary.opacity(configuration.isPressed ? 0.78 : 0.94))
                }
                .clipShape(RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: palette.primary.opacity(configuration.isPressed ? 0.08 : 0.20), radius: 6, y: 3)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let palette = AppPalette(colorScheme)
        if AppVisualTheme.resolved(themeRaw) == .standard {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(configuration.isPressed ? palette.divider : palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.divider, lineWidth: 1)
                }
        } else {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 13)
                .frame(height: 32)
                .background {
                    RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                        .fill(configuration.isPressed ? palette.divider : palette.raisedSurface)
                }
                .clipShape(RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.66), lineWidth: 1)
                }
        }
    }
}

struct ToolbarIconButton: View {
    let systemName: String
    let helpKey: String
    var isActive = false
    var isDisabled = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var rotation = 0.0

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isDisabled ? palette.subtleInk : (isActive ? palette.primary : palette.mutedInk))
                .rotationEffect(.degrees(rotation))
                .frame(width: 32, height: 32)
                .background(isHovering && !isDisabled ? palette.raisedSurface : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovering = $0 }
        .onAppear { updateAnimation() }
        .onChange(of: isActive) { _, _ in updateAnimation() }
        .onChange(of: reduceMotion) { _, _ in updateAnimation() }
        .help(L10n.text(helpKey))
    }

    private func updateAnimation() {
        guard isActive, !reduceMotion else {
            withAnimation(.easeOut(duration: 0.16)) { rotation = 0 }
            return
        }
        rotation = 0
        withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

struct CountBadge: View {
    let count: Int
    var emphasized = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        Text("\(count)")
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(emphasized ? palette.primary : palette.mutedInk)
            .padding(.horizontal, 6)
            .frame(minWidth: 21, minHeight: 19)
            .background(emphasized ? palette.primarySoft : palette.raisedSurface.opacity(0.78))
            .clipShape(Capsule())
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholderKey: String

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            TextField(L10n.text(placeholderKey), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.ink)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.subtleInk)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: AppVisualTheme.resolved(themeRaw) == .standard ? 30 : 34)
        .background {
            if AppVisualTheme.resolved(themeRaw) == .standard {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.raisedSurface)
            } else {
                RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                    .fill(palette.raisedSurface.opacity(0.68))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                .stroke(
                    AppVisualTheme.resolved(themeRaw) == .standard
                        ? palette.divider
                        : Color.white.opacity(colorScheme == .dark ? 0.09 : 0.62),
                    lineWidth: 1
                )
        }
    }
}

struct SectionLabel: View {
    let titleKey: String
    var count: Int?
    var actionTitleKey: String?
    var action: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 8) {
            Text(L10n.text(titleKey))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.mutedInk)
            if let count {
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.subtleInk)
            }
            Spacer()
            if let actionTitleKey, let action {
                Button(L10n.text(actionTitleKey), action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.primary)
            }
        }
        .frame(height: 30)
    }
}

struct OperationToast: View {
    let notice: OperationNotice

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(palette.success)
            Text(notice.message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(palette.ink)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .appGlassPanel(cornerRadius: 12)
        .frame(maxWidth: 420)
    }
}

struct RepositoryOperationBanner: View {
    let operation: OperationKind

    @Environment(\.colorScheme) private var colorScheme

    private var titleKey: String {
        switch operation {
        case .pull: "sync.progress.pull"
        case .push: "sync.progress.push"
        case .commitAndPush: "sync.progress.commit_push"
        default: "sync.progress.working"
        }
    }

    private var direction: SyncActivityGlyph.Direction {
        operation == .pull ? .down : .up
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 10) {
            SyncActivityGlyph(direction: direction, size: 14)
            Text(L10n.text(titleKey))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .appGlassPanel(cornerRadius: 12)
        .accessibilityLabel(L10n.text(titleKey))
    }
}

struct SyncActivityGlyph: View {
    enum Direction {
        case up
        case down
    }

    let direction: Direction
    var size: CGFloat = 13

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isMoving = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Image(systemName: direction == .up ? "arrow.up" : "arrow.down")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(palette.primary)
            .frame(width: size + 10, height: size + 10)
            .background(palette.primarySoft)
            .clipShape(Circle())
            .offset(y: reduceMotion ? 0 : (isMoving ? movement : -movement))
            .opacity(reduceMotion ? 1 : (isMoving ? 1 : 0.62))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.58).repeatForever(autoreverses: true)) {
                    isMoving = true
                }
            }
    }

    private var movement: CGFloat {
        direction == .up ? -1.8 : 1.8
    }
}
