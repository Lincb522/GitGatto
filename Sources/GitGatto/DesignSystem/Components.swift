import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let palette = AppPalette(colorScheme)
        switch AppVisualTheme.resolved(themeRaw) {
        case .standard:
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(palette.primary.opacity(configuration.isPressed ? 0.78 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        case .softGlass:
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
        case .console:
            configuration.label
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.background)
                .padding(.horizontal, 13)
                .frame(height: 30)
                .background(palette.accent.opacity(configuration.isPressed ? 0.72 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(palette.accent, lineWidth: 1)
                }
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let palette = AppPalette(colorScheme)
        switch AppVisualTheme.resolved(themeRaw) {
        case .standard:
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
        case .softGlass:
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
        case .console:
            configuration.label
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(configuration.isPressed ? palette.accent : palette.ink)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(configuration.isPressed ? palette.accentSoft : palette.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(configuration.isPressed ? palette.accent : palette.divider, lineWidth: 1)
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
            Image(gattoSymbol: systemName)
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
        let theme = AppVisualTheme.resolved(themeRaw)
        HStack(spacing: 7) {
            Image(gattoSymbol: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.subtleInk)
            TextField(L10n.text(placeholderKey), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: theme == .console ? 11.5 : 12.5, design: theme == .console ? .monospaced : .default))
                .foregroundStyle(palette.ink)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(gattoSymbol: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.subtleInk)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: theme == .softGlass ? 34 : 30)
        .background {
            switch theme {
            case .standard:
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.raisedSurface)
            case .softGlass:
                RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                    .fill(palette.raisedSurface.opacity(0.68))
            case .console:
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.background)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                .stroke(
                    theme == .softGlass
                        ? Color.white.opacity(colorScheme == .dark ? 0.09 : 0.62)
                        : palette.divider,
                    lineWidth: 1
                )
        }
    }
}

struct ConsoleBreathingLight: View {
    var isBusy = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        let color = isBusy ? palette.warning : palette.success
        ZStack {
            Circle()
                .stroke(color.opacity(0.62), lineWidth: 1)
                .frame(width: 8, height: 8)
                .scaleEffect(reduceMotion ? 1 : (isPulsing ? 2.25 : 1))
                .opacity(reduceMotion ? 0 : (isPulsing ? 0 : 0.72))
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.72), radius: 5)
        }
        .frame(width: 18, height: 18)
        .onAppear { updateAnimation() }
        .onChange(of: isBusy) { _, _ in updateAnimation() }
        .onChange(of: reduceMotion) { _, _ in updateAnimation() }
        .accessibilityHidden(true)
    }

    private func updateAnimation() {
        isPulsing = false
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 1.45).repeatForever(autoreverses: false)) {
            isPulsing = true
        }
    }
}

struct GattoLoadingGlyph: View {
    var size: CGFloat = 20

    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = AppPalette(colorScheme)
        let theme = AppVisualTheme.resolved(themeRaw)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let phase = reduceMotion
                ? 0.14
                : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.92) / 0.92

            switch theme {
            case .standard:
                orbitGlyph(phase: phase, track: palette.primarySoft.opacity(0.84))
            case .softGlass:
                orbitGlyph(phase: phase, track: Color.white.opacity(colorScheme == .dark ? 0.14 : 0.70))
                    .padding(size * 0.10)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle().stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.74), lineWidth: 1)
                    }
            case .console:
                consoleGlyph(phase: phase)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func orbitGlyph(phase: Double, track: Color) -> some View {
        let lineWidth = max(1.8, size * 0.105)
        return ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0.04, to: 0.34)
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(phase * 360))
            Circle()
                .fill(.tint)
                .frame(width: lineWidth * 1.35, height: lineWidth * 1.35)
                .offset(y: -(size - lineWidth) * 0.5)
                .rotationEffect(.degrees(phase * 360))
        }
        .padding(lineWidth * 0.72)
    }

    private func consoleGlyph(phase: Double) -> some View {
        HStack(alignment: .center, spacing: size * 0.09) {
            ForEach(0..<3, id: \.self) { index in
                let wave = (sin((phase * .pi * 2) - Double(index) * 0.9) + 1) * 0.5
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(.tint)
                    .frame(width: size * 0.18, height: size * (0.30 + wave * 0.48))
                    .opacity(reduceMotion ? 0.82 : 0.42 + wave * 0.58)
            }
        }
        .frame(width: size, height: size)
    }
}

struct GattoLoadingState: View {
    var text: String? = nil
    var size: CGFloat = 28

    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        let theme = AppVisualTheme.resolved(themeRaw)
        VStack(spacing: 11) {
            GattoLoadingGlyph(size: size)
            if let text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 11.5, weight: .medium, design: theme == .console ? .monospaced : .default))
                    .foregroundStyle(theme == .console ? palette.accent : palette.mutedInk)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text ?? L10n.text("loading.generic"))
    }
}

struct GattoProgressViewStyle: ProgressViewStyle {
    @AppStorage(AppStyleDefaults.themeKey) private var themeRaw = AppVisualTheme.standard.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlSize) private var controlSize

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let palette = AppPalette(colorScheme)
        let theme = AppVisualTheme.resolved(themeRaw)
        if let fraction = configuration.fractionCompleted {
            VStack(alignment: .leading, spacing: 6) {
                configuration.label
                    .font(.system(size: 10.5, weight: .medium, design: theme == .console ? .monospaced : .default))
                    .foregroundStyle(palette.mutedInk)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.divider)
                        Capsule()
                            .fill(.tint)
                            .frame(width: proxy.size.width * min(1, max(0, fraction)))
                    }
                }
                .frame(height: theme == .console ? 3 : 4)
            }
        } else {
            HStack(spacing: controlSize == .small || controlSize == .mini ? 6 : 9) {
                GattoLoadingGlyph(size: controlSize == .small || controlSize == .mini ? 15 : 20)
                configuration.label
                    .font(.system(size: 11.5, weight: .medium, design: theme == .console ? .monospaced : .default))
                    .foregroundStyle(theme == .console ? palette.accent : palette.mutedInk)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.text("loading.generic"))
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
            Image(gattoSymbol: "checkmark.circle.fill")
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
        Image(gattoSymbol: direction == .up ? "arrow.up" : "arrow.down")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(palette.primary)
            .frame(width: size + 4, height: size + 4)
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
