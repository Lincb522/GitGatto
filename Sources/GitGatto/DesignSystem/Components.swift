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
    @State private var startedAt = Date.now

    var body: some View {
        let palette = AppPalette(colorScheme)
        let theme = AppVisualTheme.resolved(themeRaw)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let elapsed = reduceMotion ? 0 : max(0, context.date.timeIntervalSince(startedAt))
            let cycleDuration = 2.4
            let phase = elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
            let cycle = Int(elapsed / cycleDuration)
            octocatWink(
                phase: phase,
                cycle: cycle,
                palette: palette,
                theme: theme
            )
        }
        .frame(width: size, height: size)
        .onAppear { startedAt = .now }
        .accessibilityHidden(true)
    }

    private func octocatWink(
        phase: Double,
        cycle: Int,
        palette: AppPalette,
        theme: AppVisualTheme
    ) -> some View {
        let baseSize: CGFloat = 200
        let lineWidth: CGFloat = size < 24 ? 11 : 7
        let activeColor = theme == .console ? palette.accent : palette.primary
        let trackColor: Color
        if theme == .softGlass {
            trackColor = colorScheme == .dark
                ? Color.white.opacity(0.30)
                : palette.ink.opacity(0.34)
        } else {
            trackColor = palette.mutedInk.opacity(theme == .console ? 0.34 : 0.28)
        }
        let wink = winkAmount(for: phase)
        let winksLeft = cycle.isMultiple(of: 2)
        let headColor = colorScheme == .dark
            ? Color.white.opacity(0.90)
            : palette.ink.opacity(0.88)
        let eyeColor = colorScheme == .dark
            ? Color.black.opacity(0.88)
            : Color.white.opacity(0.98)

        return ZStack {
            GattoOctocatShape()
                .stroke(
                    trackColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .scaleEffect(1.35)

            travellingStroke(phase: phase, lineWidth: lineWidth, color: activeColor)

            GattoOctocatHeadShape()
                .fill(headColor)
                .scaleEffect(0.3925)
                .offset(x: 3)

            GattoOctocatLeftEyeShape()
                .fill(eyeColor)
                .scaleEffect(0.3925)
                .offset(y: -19)
                .scaleEffect(x: 1, y: winksLeft ? 1 - wink * 0.88 : 1)

            GattoOctocatRightEyeShape()
                .fill(eyeColor)
                .scaleEffect(0.3925)
                .offset(y: -19)
                .scaleEffect(x: 1, y: winksLeft ? 1 : 1 - wink * 0.88)
        }
        .frame(width: baseSize, height: baseSize)
        .scaleEffect(size / baseSize)
        .frame(width: size, height: size)
        .shadow(
            color: theme == .console ? activeColor.opacity(0.20) : .clear,
            radius: size * 0.16
        )
    }

    @ViewBuilder
    private func travellingStroke(phase: Double, lineWidth: CGFloat, color: Color) -> some View {
        let head = min(1, max(0, phase * 1.18))
        let tail = head - 0.24
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

        if tail >= 0 {
            GattoOctocatShape()
                .trim(from: tail, to: head)
                .stroke(color, style: style)
                .scaleEffect(1.35)
        } else {
            GattoOctocatShape()
                .trim(from: 0, to: head)
                .stroke(color, style: style)
                .scaleEffect(1.35)
            GattoOctocatShape()
                .trim(from: 1 + tail, to: 1)
                .stroke(color, style: style)
                .scaleEffect(1.35)
        }
    }

    private func winkAmount(for phase: Double) -> CGFloat {
        guard !reduceMotion, phase >= 0.68, phase <= 0.90 else { return 0 }
        let normalized = (phase - 0.68) / 0.22
        return CGFloat(sin(normalized * .pi))
    }
}

// Octocat geometry © 2021 Shubham Singh, adapted from SwiftUI-Animations under Apache-2.0.
// Animation timing, rendering scale, colors, and reduced-motion behavior were changed for GitGatto.
private struct GattoOctocatShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cX = rect.midX
        let cY = rect.midY
        var path = Path()

        path.move(to: CGPoint(x: cX + 24.07, y: cY + 77.5))
        path.addLine(to: CGPoint(x: cX + 24.07, y: cY + 52.94))
        path.addLine(to: CGPoint(x: cX + 24.06, y: cY + 53.12))
        path.addCurve(
            to: CGPoint(x: cX + 18.14, y: cY + 36.4),
            control1: CGPoint(x: cX + 24.6, y: cY + 46.95),
            control2: CGPoint(x: cX + 22.44, y: cY + 40.85)
        )
        path.addCurve(
            to: CGPoint(x: cX + 58.99, y: cY - 8.06),
            control1: CGPoint(x: cX + 38.04, y: cY + 34.15),
            control2: CGPoint(x: cX + 58.99, y: cY + 26.6)
        )
        path.addLine(to: CGPoint(x: cX + 58.99, y: cY - 8.06))
        path.addCurve(
            to: CGPoint(x: cX + 49.3, y: cY - 32.04),
            control1: CGPoint(x: cX + 58.99, y: cY - 17),
            control2: CGPoint(x: cX + 55.52, y: cY - 25.6)
        )
        path.addLine(to: CGPoint(x: cX + 49.56, y: cY - 32.1))
        path.addCurve(
            to: CGPoint(x: cX + 48.72, y: cY - 56.2),
            control1: CGPoint(x: cX + 52.41, y: cY - 39.94),
            control2: CGPoint(x: cX + 52.11, y: cY - 48.58)
        )
        path.addCurve(
            to: CGPoint(x: cX + 24.08, y: cY - 46.4),
            control1: CGPoint(x: cX + 48.9, y: cY - 55.79),
            control2: CGPoint(x: cX + 41.41, y: cY - 58.02)
        )
        path.addLine(to: CGPoint(x: cX + 23.84, y: cY - 46.46))
        path.addCurve(
            to: CGPoint(x: cX - 20.12, y: cY - 46.46),
            control1: CGPoint(x: cX + 9.44, y: cY - 50.32),
            control2: CGPoint(x: cX - 5.72, y: cY - 50.32)
        )
        path.addCurve(
            to: CGPoint(x: cX - 45.17, y: cY - 55.79),
            control1: CGPoint(x: cX - 37.69, y: cY - 58.01),
            control2: CGPoint(x: cX - 45.11, y: cY - 55.79)
        )
        path.addLine(to: CGPoint(x: cX - 45.22, y: cY - 55.69))
        path.addCurve(
            to: CGPoint(x: cX - 45.64, y: cY - 31.58),
            control1: CGPoint(x: cX - 48.48, y: cY - 48.01),
            control2: CGPoint(x: cX - 48.63, y: cY - 39.37)
        )
        path.addLine(to: CGPoint(x: cX - 45.58, y: cY - 32.04))
        path.addCurve(
            to: CGPoint(x: cX - 55.27, y: cY - 8.05),
            control1: CGPoint(x: cX - 51.79, y: cY - 25.6),
            control2: CGPoint(x: cX - 55.27, y: cY - 17)
        )
        path.addCurve(
            to: CGPoint(x: cX - 14.39, y: cY + 36.56),
            control1: CGPoint(x: cX - 55.27, y: cY + 26.53),
            control2: CGPoint(x: cX - 34.32, y: cY + 34.09)
        )
        path.addLine(to: CGPoint(x: cX - 14.4, y: cY + 36.58))
        path.addCurve(
            to: CGPoint(x: cX - 20.36, y: cY + 52.93),
            control1: CGPoint(x: cX - 18.62, y: cY + 40.94),
            control2: CGPoint(x: cX - 20.78, y: cY + 46.88)
        )
        path.addLine(to: CGPoint(x: cX - 20.36, y: cY + 77.5))
        path.move(to: CGPoint(x: cX - 20.36, y: cY + 58.46))
        path.addCurve(
            to: CGPoint(x: cX - 64.79, y: cY + 39.42),
            control1: CGPoint(x: cX - 52.09, y: cY + 67.98),
            control2: CGPoint(x: cX - 52.09, y: cY + 42.59)
        )
        return path
    }
}

private struct GattoOctocatHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cX = rect.midX
        let cY = rect.midY
        var path = Path()

        path.move(to: CGPoint(x: cX - 41.87, y: cY - 63.23))
        path.addCurve(to: CGPoint(x: cX + 43.23, y: cY - 63.46), control1: CGPoint(x: cX - 7.92, y: cY - 60.68), control2: CGPoint(x: cX + 7.6, y: cY - 60.73))
        path.addCurve(to: CGPoint(x: cX + 87.78, y: cY - 63.5), control1: CGPoint(x: cX + 57.7, y: cY - 64.55), control2: CGPoint(x: cX + 81.18, y: cY - 64.59))
        path.addCurve(to: CGPoint(x: cX + 122, y: cY - 46.71), control1: CGPoint(x: cX + 103.39, y: cY - 61), control2: CGPoint(x: cX + 112.85, y: cY - 56.31))
        path.addLine(to: CGPoint(x: cX + 122.28, y: cY - 46.42))
        path.addCurve(to: CGPoint(x: cX + 139.09, y: cY - 14.8), control1: CGPoint(x: cX + 130.74, y: cY - 37.66), control2: CGPoint(x: cX + 136.56, y: cY - 26.71))
        path.addCurve(to: CGPoint(x: cX + 139.75, y: cY + 13.04), control1: CGPoint(x: cX + 140.43, y: cY - 8.71), control2: CGPoint(x: cX + 140.7, y: cY + 4.67))
        path.addCurve(to: CGPoint(x: cX + 119.68, y: cY + 58.59), control1: CGPoint(x: cX + 137.38, y: cY + 33.15), control2: CGPoint(x: cX + 131.33, y: cY + 46.94))
        path.addCurve(to: CGPoint(x: cX + 46.64, y: cY + 85.85), control1: CGPoint(x: cX + 104.53, y: cY + 73.75), control2: CGPoint(x: cX + 81.32, y: cY + 82.44))
        path.addCurve(to: CGPoint(x: cX, y: cY + 87.63), control1: CGPoint(x: cX + 32.08, y: cY + 87.31), control2: CGPoint(x: cX + 23.53, y: cY + 87.63))
        path.addCurve(to: CGPoint(x: cX - 47.87, y: cY + 85.85), control1: CGPoint(x: cX - 23.71, y: cY + 87.63), control2: CGPoint(x: cX - 33.54, y: cY + 87.26))
        path.addCurve(to: CGPoint(x: cX - 141.76, y: cY + 12.5), control1: CGPoint(x: cX - 108.09, y: cY + 79.8), control2: CGPoint(x: cX - 136.94, y: cY + 57.27))
        path.addCurve(to: CGPoint(x: cX - 140.94, y: cY - 15.4), control1: CGPoint(x: cX - 142.58, y: cY + 5.04), control2: CGPoint(x: cX - 142.12, y: cY - 10.34))
        path.addLine(to: CGPoint(x: cX - 140.89, y: cY - 15.61))
        path.addCurve(to: CGPoint(x: cX - 131.37, y: cY - 37.52), control1: CGPoint(x: cX - 139.09, y: cY - 23.44), control2: CGPoint(x: cX - 135.86, y: cY - 30.86))
        path.addCurve(to: CGPoint(x: cX - 113.96, y: cY - 55.13), control1: CGPoint(x: cX - 127.56, y: cY - 43.34), control2: CGPoint(x: cX - 118.87, y: cY - 52.13))
        path.addCurve(to: CGPoint(x: cX - 87.24, y: cY - 63.82), control1: CGPoint(x: cX - 106.72, y: cY - 59.59), control2: CGPoint(x: cX - 97.85, y: cY - 62.5))
        path.addCurve(to: CGPoint(x: cX - 41.87, y: cY - 63.23), control1: CGPoint(x: cX - 80.1, y: cY - 64.73), control2: CGPoint(x: cX - 58.35, y: cY - 64.46))
        path.closeSubpath()
        return path
    }
}

private struct GattoOctocatLeftEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cX = rect.midX
        let cY = rect.midY
        var path = Path()
        path.move(to: CGPoint(x: cX - 66.13, y: cY - 14.34))
        path.addCurve(to: CGPoint(x: cX - 80.6, y: cY + 7.17), control1: CGPoint(x: cX - 73.81, y: cY - 13.04), control2: CGPoint(x: cX - 79.51, y: cY - 4.54))
        path.addCurve(to: CGPoint(x: cX - 69.38, y: cY + 34.62), control1: CGPoint(x: cX - 81.76, y: cY + 19.57), control2: CGPoint(x: cX - 77.08, y: cY + 30.95))
        path.addCurve(to: CGPoint(x: cX - 63.92, y: cY + 35.56), control1: CGPoint(x: cX - 67.53, y: cY + 35.5), control2: CGPoint(x: cX - 67.2, y: cY + 35.56))
        path.addCurve(to: CGPoint(x: cX - 58.4, y: cY + 34.56), control1: CGPoint(x: cX - 60.58, y: cY + 35.56), control2: CGPoint(x: cX - 60.34, y: cY + 35.5))
        path.addCurve(to: CGPoint(x: cX - 54.4, y: cY - 10.21), control1: CGPoint(x: cX - 45.63, y: cY + 28.34), control2: CGPoint(x: cX - 43.2, y: cY + 1.07))
        path.addLine(to: CGPoint(x: cX - 54.34, y: cY - 10.15))
        path.addCurve(to: CGPoint(x: cX - 61.29, y: cY - 14.16), control1: CGPoint(x: cX - 56.18, y: cY - 12.19), control2: CGPoint(x: cX - 58.61, y: cY - 13.59))
        path.addLine(to: CGPoint(x: cX - 61.33, y: cY - 14.16))
        path.addCurve(to: CGPoint(x: cX - 66, y: cY - 14.37), control1: CGPoint(x: cX - 62.84, y: cY - 14.63), control2: CGPoint(x: cX - 64.45, y: cY - 14.7))
        path.closeSubpath()
        return path
    }
}

private struct GattoOctocatRightEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cX = rect.midX
        let cY = rect.midY
        var path = Path()
        path.move(to: CGPoint(x: cX + 66.87, y: cY - 14.34))
        path.addCurve(to: CGPoint(x: cX + 52.4, y: cY + 7.17), control1: CGPoint(x: cX + 59.19, y: cY - 13.04), control2: CGPoint(x: cX + 53.49, y: cY - 4.54))
        path.addCurve(to: CGPoint(x: cX + 63.62, y: cY + 34.62), control1: CGPoint(x: cX + 51.24, y: cY + 19.57), control2: CGPoint(x: cX + 55.92, y: cY + 30.95))
        path.addCurve(to: CGPoint(x: cX + 69.08, y: cY + 35.56), control1: CGPoint(x: cX + 65.47, y: cY + 35.5), control2: CGPoint(x: cX + 65.8, y: cY + 35.56))
        path.addCurve(to: CGPoint(x: cX + 74.6, y: cY + 34.56), control1: CGPoint(x: cX + 72.42, y: cY + 35.56), control2: CGPoint(x: cX + 72.66, y: cY + 35.5))
        path.addCurve(to: CGPoint(x: cX + 78.6, y: cY - 10.21), control1: CGPoint(x: cX + 87.37, y: cY + 28.34), control2: CGPoint(x: cX + 89.8, y: cY + 1.07))
        path.addLine(to: CGPoint(x: cX + 78.66, y: cY - 10.15))
        path.addCurve(to: CGPoint(x: cX + 71.71, y: cY - 14.16), control1: CGPoint(x: cX + 76.82, y: cY - 12.19), control2: CGPoint(x: cX + 74.39, y: cY - 13.59))
        path.addLine(to: CGPoint(x: cX + 71.67, y: cY - 14.16))
        path.addCurve(to: CGPoint(x: cX + 67, y: cY - 14.37), control1: CGPoint(x: cX + 70.16, y: cY - 14.63), control2: CGPoint(x: cX + 68.55, y: cY - 14.7))
        path.closeSubpath()
        return path
    }
}

struct GattoLoadingState: View {
    var text: String? = nil
    var size: CGFloat = 52

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
    var isActionLoading = false
    var isActionDisabled = false
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
                Button(action: action) {
                    HStack(spacing: 6) {
                        if isActionLoading {
                            GattoLoadingGlyph(size: 13)
                        }
                        Text(L10n.text(actionTitleKey))
                    }
                }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.primary)
                    .disabled(isActionDisabled)
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
            Image(gattoSymbol: notice.tone == .attention ? "arrow.up.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.tone == .attention ? palette.warning : palette.success)
            Text(notice.message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(palette.ink)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(notice.tone == .attention ? palette.warningSoft.opacity(0.72) : Color.clear)
        }
        .appGlassPanel(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: 420)
    }
}

enum TaskButtonActivityKind: Equatable {
    case pull
    case push
    case clone
    case translation
    case readmeWriting

    fileprivate var symbol: String {
        switch self {
        case .pull, .clone: "arrow.down"
        case .push: "arrow.up"
        case .translation: "ai.translation"
        case .readmeWriting: "pencil"
        }
    }

    fileprivate var travel: (start: CGSize, end: CGSize) {
        switch self {
        case .pull, .clone, .translation:
            (CGSize(width: 0, height: -19), CGSize(width: 0, height: 19))
        case .push:
            (CGSize(width: 0, height: 19), CGSize(width: 0, height: -19))
        case .readmeWriting:
            (CGSize(width: -19, height: 5), CGSize(width: 19, height: -5))
        }
    }
}

private enum TaskButtonPhase: Hashable {
    case idle
    case active
    case completed
}

struct TaskActionLabel: View {
    let title: String
    let activeTitle: String
    let systemImage: String
    let activity: TaskButtonActivityKind
    let isActive: Bool
    var completionID: UUID? = nil
    var showsInitialCompletion = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: TaskButtonPhase?
    @State private var lastCompletionID: UUID?

    var body: some View {
        let visiblePhase = phase ?? (isActive ? .active : .idle)
        ZStack(alignment: .leading) {
            sizingPanel(title).hidden()
            sizingPanel(activeTitle).hidden()
            sizingPanel(L10n.text("downloads.state.completed")).hidden()

            Group {
                switch visiblePhase {
                case .idle:
                    idlePanel
                case .active:
                    activePanel
                case .completed:
                    completedPanel
                }
            }
            .id(visiblePhase)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                )
            )
        }
        .frame(height: 26)
        .fixedSize(horizontal: true, vertical: false)
        .mask(Rectangle())
        .overlay(alignment: .bottom) {
            if visiblePhase == .active {
                TaskActivityTrack()
                    .padding(.horizontal, 2)
                    .padding(.bottom, 1)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: visiblePhase)
        .onAppear {
            phase = isActive ? .active : .idle
            lastCompletionID = showsInitialCompletion && !isActive ? nil : completionID
        }
        .task(id: isActive) {
            if isActive {
                setPhase(.active)
            } else if phase == .active {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, !isActive, phase == .active else { return }
                setPhase(.idle)
            }
        }
        .task(id: completionID) {
            guard let completionID, completionID != lastCompletionID else { return }
            lastCompletionID = completionID
            setPhase(.completed)
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 500 : 950))
            guard !Task.isCancelled, !isActive else { return }
            setPhase(.idle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(visiblePhase == .active ? activeTitle : title)
    }

    private var idlePanel: some View {
        HStack(spacing: 7) {
            Image(gattoSymbol: systemImage)
                .frame(width: 18, height: 18)
            Text(title)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }

    private func sizingPanel(_ value: String) -> some View {
        HStack(spacing: 7) {
            Color.clear.frame(width: 18, height: 18)
            Text(value).lineLimit(1)
        }
        .padding(.vertical, 3)
    }

    private var activePanel: some View {
        HStack(spacing: 7) {
            TaskActivityGlyph(kind: activity)
            Text(activeTitle)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }

    private var completedPanel: some View {
        HStack(spacing: 7) {
            TaskCompletionGlyph()
            Text(L10n.text("downloads.state.completed"))
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }

    private func setPhase(_ newPhase: TaskButtonPhase) {
        guard phase != newPhase else { return }
        if reduceMotion {
            phase = newPhase
        } else {
            withAnimation(.easeOut(duration: 0.35)) {
                phase = newPhase
            }
        }
    }
}

private struct TaskActivityGlyph: View {
    let kind: TaskButtonActivityKind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAtEnd = false

    var body: some View {
        let travel = kind.travel
        ZStack {
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .opacity(0.46)

            Image(gattoSymbol: kind.symbol)
                .font(.system(size: 10.5, weight: .bold))
                .offset(
                    x: reduceMotion ? 0 : (isAtEnd ? travel.end.width : travel.start.width),
                    y: reduceMotion ? 0 : (isAtEnd ? travel.end.height : travel.start.height)
                )
                .mask(Circle().frame(width: 18, height: 18))
        }
        .frame(width: 18, height: 18)
        .onAppear { updateAnimation() }
        .onChange(of: reduceMotion) { _, _ in updateAnimation() }
    }

    private func updateAnimation() {
        isAtEnd = false
        guard !reduceMotion else { return }
        withAnimation(.easeIn(duration: 0.52).repeatForever(autoreverses: false)) {
            isAtEnd = true
        }
    }
}

private struct TaskCompletionGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawn = false

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: isDrawn ? 1 : 0)
                .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            TaskCompletionCheckmark()
                .trim(from: 0, to: isDrawn ? 1 : 0)
                .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .padding(4.6)
        }
        .frame(width: 18, height: 18)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.42)) {
                isDrawn = true
            }
        }
    }
}

private struct TaskCompletionCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

private struct TaskActivityTrack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAtEnd = false

    var body: some View {
        GeometryReader { proxy in
            let segmentWidth = max(12, proxy.size.width * 0.34)
            ZStack(alignment: .leading) {
                Capsule()
                    .opacity(0.13)
                Capsule()
                    .frame(width: segmentWidth)
                    .offset(x: reduceMotion ? (proxy.size.width - segmentWidth) / 2 : (isAtEnd ? proxy.size.width : -segmentWidth))
            }
            .clipShape(Capsule())
        }
        .frame(height: 2)
        .onAppear { updateAnimation() }
        .onChange(of: reduceMotion) { _, _ in updateAnimation() }
    }

    private func updateAnimation() {
        isAtEnd = false
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 0.78).repeatForever(autoreverses: false)) {
            isAtEnd = true
        }
    }
}
