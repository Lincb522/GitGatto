import SwiftUI

struct FlatAgentResolveButton: View {
    let title: String
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var startedAt = Date.now

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { context in
                let elapsed = reduceMotion ? 0 : context.date.timeIntervalSince(startedAt)
                HStack(spacing: 8) {
                    Image(gattoSymbol: "sparkles")
                        .font(.system(size: 12.5, weight: .semibold))
                        .opacity(reduceMotion ? 1 : 0.64 + 0.36 * wave(elapsed * 1.7))

                    HStack(spacing: 0) {
                        ForEach(Array(title.enumerated()), id: \.offset) { index, character in
                            Text(String(character))
                                .opacity(letterOpacity(index: index, elapsed: elapsed))
                                .offset(y: letterOffset(index: index, elapsed: elapsed))
                        }
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background {
                    RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                        .fill(palette.primary.opacity(isHovering ? 0.88 : 1))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(isHovering ? 0.34 : 0.16), lineWidth: 1)
                }
            }
        }
        .buttonStyle(FlatMotionButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.48 : 1)
        .onHover { isHovering = $0 }
        .onAppear { startedAt = .now }
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel(title)
    }

    private func wave(_ value: Double) -> Double {
        (sin(value * .pi * 2) + 1) / 2
    }

    private func letterOpacity(index: Int, elapsed: TimeInterval) -> Double {
        guard !reduceMotion else { return 1 }
        return 0.56 + 0.44 * wave(elapsed / 2 - Double(index) * 0.08)
    }

    private func letterOffset(index: Int, elapsed: TimeInterval) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return -0.8 * wave(elapsed / 2 - Double(index) * 0.08)
    }
}

private struct FlatMotionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ReadmeRewriteMotionLabel: View {
    let title: String
    let isActive: Bool
    var completionID: UUID? = nil
    var showsInitialCompletion = false
    var systemImage: String? = nil
    var showsCancelIndicator = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var isShowingCompletion = false
    @State private var lastCompletionID: UUID?

    private var isOpen: Bool {
        isHovering || isActive || isShowingCompletion
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        let cornerRadius = AppThemeLayout.controlCornerRadius
        HStack(spacing: 0) {
            ZStack {
                if isShowingCompletion {
                    SubmissionCheckmark()
                        .foregroundStyle(Color.white)
                        .transition(.scale(scale: 0.72).combined(with: .opacity))
                } else if let systemImage {
                    TranslationMotionGlyph(
                        symbol: systemImage,
                        isActive: isActive,
                        tint: isOpen ? Color.white : palette.primary
                    )
                        .transition(.opacity)
                } else if !isActive {
                    GattoIcon(symbol: "ai.writing", size: 23)
                        .foregroundStyle(isOpen ? Color.white : palette.primary)
                        .scaleEffect(isOpen && !reduceMotion ? 1.04 : 1)
                        .rotationEffect(.degrees(isOpen && !reduceMotion ? -1.5 : 0))
                        .transition(.opacity)
                } else {
                    ReadmeFolderMotionGlyph(isOpen: isOpen, isWriting: isActive)
                        .scaleEffect(0.64)
                        .transition(.opacity)
                }
            }
            .frame(width: 34, height: 34)
            .background(isOpen ? palette.primary.opacity(0.80) : palette.primarySoft)
            .clipped()

            Text(isShowingCompletion ? L10n.text("downloads.state.completed") : title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isOpen ? Color.white : palette.ink)
                .lineLimit(1)
                .padding(.leading, 11)
                .padding(.trailing, 8)

            if let trailingSymbol {
                GattoIcon(symbol: trailingSymbol, size: isActive ? 18 : 14)
                    .foregroundStyle(isOpen ? Color.white.opacity(0.78) : palette.subtleInk)
                    .offset(x: isOpen && !reduceMotion ? 2 : 0)
                    .padding(.trailing, 11)
            } else {
                Color.clear.frame(width: 8)
            }
        }
        .frame(height: 34)
        .background(isOpen ? palette.primary : palette.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(isOpen ? palette.primary : palette.divider, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeInOut(duration: 0.4)) {
                    isHovering = hovering
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: isActive)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isShowingCompletion)
        .onAppear {
            lastCompletionID = showsInitialCompletion && !isActive ? completionID : nil
        }
        .task(id: completionID) {
            guard let completionID, completionID != lastCompletionID, !isActive else { return }
            lastCompletionID = completionID
            isShowingCompletion = true
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 500 : 950))
            guard !Task.isCancelled else { return }
            isShowingCompletion = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isShowingCompletion ? L10n.text("downloads.state.completed") : title)
    }

    private var trailingSymbol: String? {
        if isActive {
            return showsCancelIndicator ? "xmark" : nil
        }
        return "chevron.right"
    }
}

private struct TranslationMotionGlyph: View {
    let symbol: String
    let isActive: Bool
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date.now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isActive || reduceMotion)) { context in
            let elapsed = reduceMotion ? 0 : context.date.timeIntervalSince(startedAt)
            GattoIcon(symbol: symbol, size: 21)
                .foregroundStyle(tint)
                .rotation3DEffect(
                    .degrees(isActive && !reduceMotion ? sin(elapsed * 3.8) * 9 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.42
                )
                .offset(y: isActive && !reduceMotion ? sin(elapsed * 5.2) * 0.8 : 0)
        }
        .frame(width: 26, height: 28)
        .onAppear { startedAt = .now }
        .accessibilityHidden(true)
    }
}

private struct ReadmeFolderMotionGlyph: View {
    let isOpen: Bool
    let isWriting: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var startedAt = Date.now

    var body: some View {
        let palette = AppPalette(colorScheme)
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isWriting || reduceMotion)) { context in
            let elapsed = reduceMotion ? 0 : context.date.timeIntervalSince(startedAt)
            let pencilTravel = isWriting ? CGFloat(sin(elapsed * 8) * 1.4) : 0

            ZStack {
                ReadmeFolderBackShape()
                    .fill(isOpen ? Color.white.opacity(0.62) : palette.primary.opacity(0.46))
                    .frame(width: 23, height: 27)

                RoundedRectangle(cornerRadius: 1.4, style: .continuous)
                    .fill(Color.white.opacity(0.68))
                    .frame(width: 18, height: 22)
                    .offset(x: isOpen ? 2 : 0, y: isOpen ? -3 : 0)

                ReadmePaperSheet(lineColor: isOpen ? palette.primary : palette.subtleInk)
                    .frame(width: 18, height: 22)
                    .offset(x: isOpen ? -1 : 0, y: isOpen ? -1 : 0)

                ReadmeFolderFrontShape()
                    .fill(isOpen ? Color.white.opacity(0.90) : palette.primary)
                    .frame(width: 23, height: 20)
                    .rotation3DEffect(
                        .degrees(isOpen && !reduceMotion ? -58 : 0),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .leading,
                        perspective: 0.45
                    )
                    .offset(x: isOpen && !reduceMotion ? -9 : 0, y: 4)

                ReadmePencilGlyph(tint: isOpen ? Color.white : palette.primary)
                    .offset(
                        x: isOpen ? 11 + pencilTravel : 34,
                        y: isOpen ? -5 - pencilTravel : -5
                    )
                    .opacity(isOpen ? 1 : 0)
            }
            .frame(width: 46, height: 34)
        }
        .onAppear { startedAt = .now }
        .accessibilityHidden(true)
    }
}

private struct ReadmeFolderBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.minY + 3))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + 3))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.minY + 7))
        path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.minY + 7))
        path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.maxY - 1))
        path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.maxY - 1))
        path.closeSubpath()
        return path
    }
}

private struct ReadmeFolderFrontShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.maxY - 1))
        path.addLine(to: CGPoint(x: rect.minX + 3, y: rect.maxY - 1))
        path.closeSubpath()
        return path
    }
}

private struct ReadmePaperSheet: View {
    let lineColor: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1.4, style: .continuous)
                .fill(Color.white)
            VStack(alignment: .leading, spacing: 2.5) {
                Capsule().fill(lineColor.opacity(0.58)).frame(width: 11, height: 1)
                Capsule().fill(lineColor.opacity(0.44)).frame(width: 8, height: 1)
                Capsule().fill(lineColor.opacity(0.44)).frame(width: 11, height: 1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 3)
            .padding(.top, 4)
        }
    }
}

private struct ReadmePencilGlyph: View {
    let tint: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(tint)
                .frame(width: 5, height: 19)
            Rectangle()
                .fill(tint.opacity(0.48))
                .frame(width: 5, height: 4)
                .offset(y: -5)
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 5, y: 0))
                path.addLine(to: CGPoint(x: 2.5, y: 5))
                path.closeSubpath()
            }
            .fill(tint.opacity(0.72))
            .frame(width: 5, height: 5)
            .offset(y: 5)
        }
        .frame(width: 6, height: 24)
        .rotationEffect(.degrees(35))
    }
}

struct CloneActionButton: View {
    let title: String
    let activeTitle: String
    let systemImage: String
    var compact = false
    let isActive: Bool
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    private var width: CGFloat { compact ? 170 : 192 }
    private var height: CGFloat { compact ? 34 : 40 }
    private var isExpanded: Bool { isActive }
    private var leadingPlateWidth: CGFloat {
        isExpanded ? width - 6 : (compact ? 36 : 42)
    }

    var body: some View {
        let palette = AppPalette(colorScheme)
        let cornerRadius = AppThemeLayout.controlCornerRadius

        Button(action: action) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.raisedSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(palette.divider, lineWidth: 1)
                    }

                Text(title)
                    .font(.system(size: compact ? 10.5 : 11.5, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .offset(x: compact ? 8 : 10)

                RoundedRectangle(
                    cornerRadius: max(3, cornerRadius - 2),
                    style: .continuous
                )
                .fill(isExpanded ? palette.primary : palette.primarySoft)
                .frame(width: leadingPlateWidth, height: height - 6)
                .overlay {
                    if isActive {
                        HStack(spacing: 7) {
                            CloneActivityGlyph(systemImage: systemImage, tint: Color.white)
                            Text(activeTitle)
                                .lineLimit(1)
                        }
                        .font(.system(size: compact ? 10 : 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                    } else {
                        Image(gattoSymbol: systemImage)
                            .font(.system(size: compact ? 11.5 : 13, weight: .bold))
                            .foregroundStyle(isExpanded ? Color.white : palette.primary)
                    }
                }
                .overlay {
                    if isActive {
                        CloneProgressBorder(
                            tint: Color.white.opacity(0.92),
                            cornerRadius: max(3, cornerRadius - 2)
                        )
                    }
                }
                .padding(.leading, 3)
            }
            .frame(width: width, height: height)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.44 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: isActive)
        .help(isActive ? L10n.text("github.action.cancel") : title)
        .accessibilityLabel(isActive ? activeTitle : title)
    }
}

struct CloneActivityGlyph: View {
    let systemImage: String
    let tint: Color
    var travelsUp = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date.now

    @ViewBuilder
    var body: some View {
        if reduceMotion {
            glyph(offset: 0, opacity: 1)
                .frame(width: 16, height: 16)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                let elapsed = context.date.timeIntervalSince(startedAt)
                let progress = (elapsed / 1.8 + 0.12).truncatingRemainder(dividingBy: 1)
                ZStack {
                    travelingGlyph(progress: progress)
                    travelingGlyph(progress: (progress + 0.5).truncatingRemainder(dividingBy: 1))
                }
            }
            .frame(width: 16, height: 16)
            .clipped()
            .onAppear { startedAt = .now }
        }
    }

    private func travelingGlyph(progress: Double) -> some View {
        let eased = progress * progress * (3 - 2 * progress)
        let visibility = pow(max(0, sin(progress * .pi)), 3)
        let direction: CGFloat = travelsUp ? -1 : 1
        let offset = CGFloat(eased * 2 - 1) * 5.5 * direction
        return glyph(offset: offset, opacity: visibility)
    }

    private func glyph(offset: CGFloat, opacity: Double) -> some View {
        Image(gattoSymbol: systemImage)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(tint)
            .offset(y: offset)
            .opacity(opacity)
    }
}

struct CloneProgressBorder: View {
    let tint: Color
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let radius = min(cornerRadius, min(proxy.size.width, proxy.size.height) / 2)
            let perimeter = max(
                1,
                2 * (proxy.size.width + proxy.size.height - 4 * radius) + 2 * .pi * radius
            )
            let segment = max(24, perimeter * 0.24)

            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 1.2)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(
                            tint,
                            style: StrokeStyle(
                                lineWidth: 1.8,
                                lineCap: .round,
                                dash: [segment, max(1, perimeter - segment)],
                                dashPhase: reduceMotion ? -perimeter * 0.38 : phase
                            )
                        )
                }
                .onAppear { updateAnimation(perimeter: perimeter) }
                .onChange(of: reduceMotion) { _, _ in updateAnimation(perimeter: perimeter) }
        }
        .padding(1)
    }

    private func updateAnimation(perimeter: CGFloat) {
        phase = 0
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
            phase = -perimeter
        }
    }
}

struct CircularDownloadIndicator: View {
    let state: AppDownloadState
    let progress: Double
    var size: CGFloat = 38

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var startedAt = Date.now

    var body: some View {
        let palette = AppPalette(colorScheme)
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isMoving || reduceMotion)) { context in
            let elapsed = reduceMotion ? 0 : max(0, context.date.timeIntervalSince(startedAt))
            let wavePhase = elapsed.truncatingRemainder(dividingBy: 1.8) / 1.8

            ZStack {
                Circle()
                    .fill(palette.raisedSurface)

                if showsLiquid {
                    ZStack {
                        DownloadWaveShape(progress: displayedProgress, phase: wavePhase)
                            .fill(palette.primary.opacity(0.92))
                        DownloadWaveShape(progress: displayedProgress, phase: wavePhase + 0.34)
                            .fill(palette.primary.opacity(0.58))
                    }
                    .clipShape(Circle().inset(by: size * 0.075))
                }

                Circle()
                    .stroke(palette.primary.opacity(0.24), lineWidth: ringWidth)

                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        ringColor(palette),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                centerContent(palette)
            }
        }
        .frame(width: size, height: size)
        .onAppear { startedAt = .now }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("downloads.state.\(state.rawValue)"))
        .accessibilityValue(state == .downloading ? "\(Int(displayedProgress * 100))%" : "")
    }

    private var displayedProgress: Double {
        min(1, max(0, progress))
    }

    private var ringProgress: Double {
        switch state {
        case .completed, .installing, .installed:
            1
        case .queued:
            0.03
        default:
            displayedProgress
        }
    }

    private var showsLiquid: Bool {
        switch state {
        case .queued, .downloading, .paused, .completed:
            true
        case .failed, .cancelled, .installing, .installed:
            false
        }
    }

    private var isMoving: Bool {
        state == .downloading || state == .installing
    }

    private var ringWidth: CGFloat {
        max(1.5, size * 0.075)
    }

    private func ringColor(_ palette: AppPalette) -> Color {
        switch state {
        case .failed, .cancelled:
            palette.danger
        case .completed, .installed:
            palette.success
        case .paused:
            palette.warning
        default:
            palette.primary
        }
    }

    @ViewBuilder
    private func centerContent(_ palette: AppPalette) -> some View {
        switch state {
        case .queued:
            Image(gattoSymbol: "arrow.down")
                .font(.system(size: size * 0.28, weight: .bold))
                .foregroundStyle(palette.primary)
        case .downloading:
            Text("\(Int(displayedProgress * 100))")
                .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(displayedProgress > 0.48 ? Color.white : palette.ink)
                .contentTransition(.numericText())
        case .paused:
            Image(gattoSymbol: "pause")
                .font(.system(size: size * 0.24, weight: .bold))
                .foregroundStyle(palette.warning)
        case .completed:
            Image(gattoSymbol: "checkmark")
                .font(.system(size: size * 0.27, weight: .bold))
                .foregroundStyle(Color.white)
                .transition(.scale.combined(with: .opacity))
        case .installed:
            Image(gattoSymbol: "checkmark.seal.fill")
                .font(.system(size: size * 0.27, weight: .bold))
                .foregroundStyle(palette.success)
                .transition(.scale.combined(with: .opacity))
        case .failed:
            Image(gattoSymbol: "exclamationmark")
                .font(.system(size: size * 0.28, weight: .bold))
                .foregroundStyle(palette.danger)
        case .cancelled:
            Image(gattoSymbol: "xmark")
                .font(.system(size: size * 0.24, weight: .bold))
                .foregroundStyle(palette.danger)
        case .installing:
            Image(gattoSymbol: "arrow.down.app")
                .font(.system(size: size * 0.25, weight: .bold))
                .foregroundStyle(palette.primary)
                .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating)
        }
    }
}

private struct DownloadWaveShape: Shape {
    let progress: Double
    let phase: Double

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(1, max(0, progress))
        let surfaceY = rect.maxY - rect.height * clampedProgress
        let amplitude = min(rect.height * 0.055, 2.4)
        let phaseRadians = phase * .pi * 2
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: surfaceY))

        let steps = max(16, Int(rect.width.rounded(.up)))
        for index in 0...steps {
            let ratio = CGFloat(index) / CGFloat(steps)
            let x = rect.minX + rect.width * ratio
            let y = surfaceY + sin(Double(ratio) * .pi * 2 + phaseRadians) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct SubmitMotionLabel: View {
    let title: String
    let activeTitle: String
    let systemImage: String
    let isActive: Bool
    var completionID: UUID?
    var shortcut: String?
    var expandsWhenIdle = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingCompletion = false

    var body: some View {
        ZStack {
            if isShowingCompletion {
                SubmissionCheckmark()
                    .transition(.scale(scale: 0.65).combined(with: .opacity))
            } else if isActive {
                SubmissionOrbitGlyph()
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
            } else {
                HStack(spacing: 8) {
                    Image(gattoSymbol: systemImage)
                        .frame(width: 16, height: 16)
                    Text(title)
                        .lineLimit(1)
                    if expandsWhenIdle {
                        Spacer(minLength: 8)
                    }
                    if let shortcut {
                        Text(shortcut)
                            .font(.system(size: 10.5, weight: .medium))
                            .opacity(0.75)
                    }
                }
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .frame(
            minWidth: isActive || isShowingCompletion ? 18 : nil,
            maxWidth: expandsWhenIdle && !isActive && !isShowingCompletion ? .infinity : nil,
            minHeight: 18
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78),
            value: isActive
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.72),
            value: isShowingCompletion
        )
        .task(id: completionID) {
            guard completionID != nil, !isActive else { return }
            isShowingCompletion = true
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 450 : 850))
            guard !Task.isCancelled else { return }
            isShowingCompletion = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isActive ? activeTitle : title)
        .accessibilityValue(isShowingCompletion ? L10n.text("downloads.state.completed") : "")
    }
}

private struct SubmissionOrbitGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date.now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let angle = reduceMotion
                ? 0
                : context.date.timeIntervalSince(startedAt).truncatingRemainder(dividingBy: 0.92) / 0.92 * 360
            ZStack {
                Circle()
                    .stroke(lineWidth: 1.4)
                    .opacity(0.32)
                Circle()
                    .trim(from: 0.05, to: 0.36)
                    .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                Circle()
                    .fill()
                    .frame(width: 4.5, height: 4.5)
                    .offset(y: -8)
            }
            .rotationEffect(.degrees(angle))
        }
        .frame(width: 18, height: 18)
        .onAppear { startedAt = .now }
    }
}

private struct SubmissionCheckmark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawn = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 1.5)
                .opacity(0.45)
            SubmissionCheckmarkShape()
                .trim(from: 0, to: isDrawn ? 1 : 0)
                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .padding(4.5)
        }
        .frame(width: 18, height: 18)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
                isDrawn = true
            }
        }
    }
}

private struct SubmissionCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

struct GitHubStarActionButton: View {
    let title: String
    let starCount: Int
    let isStarred: Bool
    let isUpdating: Bool
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        let cornerRadius = AppThemeLayout.controlCornerRadius
        let highlightedStar = OKLCHColor(0.90, 0.15, 92).color

        Button(action: action) {
            HStack(spacing: 8) {
                GattoIcon(symbol: "github", size: 30)

                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Rectangle()
                    .fill(Color.white.opacity(0.24))
                    .frame(width: 1, height: 14)

                HStack(spacing: 4) {
                    StarMotionIcon(
                        isStarred: isStarred,
                        isUpdating: false,
                        iconSize: 30,
                        inactiveTint: isHovering ? highlightedStar : Color.white.opacity(0.74),
                        activeTint: highlightedStar
                    )
                    Text(GitHubNumberFormatter.string(starCount))
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 13)
            .frame(minWidth: 136)
            .frame(height: 40)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(palette.primary.opacity(isHovering ? 0.91 : 1))

                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.white.opacity(0.16))
                            .frame(width: 10, height: geometry.size.height * 2.2)
                            .rotationEffect(.degrees(12))
                            .offset(
                                x: isHovering && !reduceMotion
                                    ? -geometry.size.width - 28
                                    : geometry.size.width + 28,
                                y: -geometry.size.height * 0.62
                            )
                            .animation(
                                reduceMotion
                                    ? nil
                                    : isHovering
                                        ? .timingCurve(0.23, 1, 0.32, 1, duration: 0.75)
                                        : .easeOut(duration: 0.16),
                                value: isHovering
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(isHovering ? 0.30 : 0.16), lineWidth: 1)
                    if isUpdating {
                        CloneProgressBorder(
                            tint: Color.white.opacity(0.94),
                            cornerRadius: cornerRadius
                        )
                    }
                }
                .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius + 2, style: .continuous)
                    .stroke(palette.primary.opacity(isHovering ? 0.34 : 0), lineWidth: 2)
                    .padding(-3)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .buttonStyle(FlatMotionButtonStyle())
        .disabled(isDisabled)
        .allowsHitTesting(!isUpdating)
        .opacity(isDisabled && !isUpdating ? 0.48 : 1)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

struct AnimatedStarToolbarButton: View {
    let isStarred: Bool
    let isUpdating: Bool
    let helpKey: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            StarMotionIcon(isStarred: isStarred, isUpdating: isUpdating)
                .foregroundStyle(isStarred ? palette.warning : palette.mutedInk)
                .frame(width: 32, height: 32)
                .background(isHovering && !isUpdating ? palette.raisedSurface : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: AppThemeLayout.controlCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isUpdating)
        .onHover { isHovering = $0 }
        .help(L10n.text(helpKey))
    }
}

private struct StarMotionIcon: View {
    let isStarred: Bool
    let isUpdating: Bool
    var iconSize: CGFloat = 13
    var inactiveTint: Color? = nil
    var activeTint: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var animationID: UUID?
    @State private var burstProgress: CGFloat = 1
    @State private var isBursting = false
    @State private var starScale: CGFloat = 1
    @State private var startedAt = Date.now

    var body: some View {
        let palette = AppPalette(colorScheme)
        let containerSize = max(18, iconSize)
        ZStack {
            if isBursting {
                Circle()
                    .stroke(palette.warning.opacity(1 - burstProgress), lineWidth: 1)
                    .frame(width: 15, height: 15)
                    .scaleEffect(0.65 + burstProgress * 0.9)

                ForEach(0..<8, id: \.self) { index in
                    let angle = Angle.degrees(Double(index) * 45)
                    Capsule(style: .continuous)
                        .fill(
                            index.isMultiple(of: 2)
                                ? (activeTint ?? palette.warning)
                                : (inactiveTint ?? palette.primary)
                        )
                        .frame(width: 2, height: 4.5)
                        .rotationEffect(angle)
                        .offset(
                            x: cos(angle.radians) * burstProgress * 12,
                            y: sin(angle.radians) * burstProgress * 12
                        )
                        .scaleEffect(1 - burstProgress * 0.55)
                        .opacity(1 - burstProgress)
                }
            }

            GattoIcon(symbol: isStarred ? "star.fill" : "star", size: iconSize)
                .foregroundStyle(
                    isStarred
                        ? (activeTint ?? palette.warning)
                        : (inactiveTint ?? Color.primary)
                )
                .scaleEffect(starScale)
                .contentTransition(.symbolEffect(.replace))

            if isUpdating {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
                    let angle = reduceMotion
                        ? 0
                        : context.date.timeIntervalSince(startedAt).truncatingRemainder(dividingBy: 0.85) / 0.85 * 360
                    Circle()
                        .trim(from: 0.08, to: 0.34)
                        .stroke(style: StrokeStyle(lineWidth: 1.35, lineCap: .round))
                        .frame(width: containerSize + 1, height: containerSize + 1)
                        .rotationEffect(.degrees(angle))
                }
            }
        }
        .frame(width: containerSize, height: containerSize)
        .onAppear { startedAt = .now }
        .onChange(of: isStarred) { oldValue, newValue in
            guard !oldValue, newValue, !reduceMotion else { return }
            animationID = UUID()
        }
        .task(id: animationID) {
            guard animationID != nil else { return }
            isBursting = true
            burstProgress = 0
            starScale = 0.72
            withAnimation(.spring(response: 0.22, dampingFraction: 0.46)) {
                starScale = 1.28
            }
            withAnimation(.easeOut(duration: 0.58)) {
                burstProgress = 1
            }
            try? await Task.sleep(for: .milliseconds(190))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) {
                starScale = 1
            }
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            isBursting = false
        }
    }
}

struct AddSelectionMotionLabel: View {
    let title: String
    let selectedCount: Int
    let completionID: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var lastSelectedCount = 0
    @State private var isGathering = false
    @State private var isShowingCompletion = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        HStack(spacing: 8) {
            ZStack {
                if isShowingCompletion {
                    SubmissionCheckmark()
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                } else {
                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(index.isMultiple(of: 2) ? palette.primary : palette.accent)
                            .frame(width: 4.5, height: 4.5)
                            .offset(tileOffset(index))
                            .rotationEffect(.degrees(isGathering ? 43 : 0))
                            .scaleEffect(isGathering ? 0.35 : (lastSelectedCount > 0 ? 1 : 0.55))
                            .opacity(lastSelectedCount > 0 ? 0.9 : 0)
                    }

                    Image(gattoSymbol: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(isGathering ? 45 : 0))
                        .scaleEffect(isGathering ? 1.16 : 1)
                }
            }
            .frame(width: 18, height: 18)

            Text(title)
                .lineLimit(1)

            if selectedCount > 0, !isShowingCompletion {
                Text("\(selectedCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .frame(height: 17)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
                    .contentTransition(.numericText())
            }
        }
        .onAppear { lastSelectedCount = selectedCount }
        .onChange(of: selectedCount) { _, newValue in
            if newValue > 0 { lastSelectedCount = newValue }
        }
        .task(id: completionID) {
            guard completionID != nil else { return }
            if reduceMotion {
                isShowingCompletion = true
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                isShowingCompletion = false
                isGathering = false
                return
            }

            withAnimation(.spring(response: 0.30, dampingFraction: 0.74)) {
                isGathering = true
            }
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.70)) {
                isShowingCompletion = true
            }
            try? await Task.sleep(for: .milliseconds(720))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                isShowingCompletion = false
                isGathering = false
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(selectedCount > 0 ? "\(selectedCount)" : "")
    }

    private func tileOffset(_ index: Int) -> CGSize {
        guard !isGathering else { return .zero }
        return switch index {
        case 0: CGSize(width: -5.5, height: -5.5)
        case 1: CGSize(width: 5.5, height: -5.5)
        case 2: CGSize(width: -5.5, height: 5.5)
        default: CGSize(width: 5.5, height: 5.5)
        }
    }
}

enum ConnectivityMotionState: Equatable {
    case checking
    case available
    case unavailable
}

struct ConnectivityMotionGlyph: View {
    let state: ConnectivityMotionState
    var size: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var startedAt = Date.now
    @State private var connectionPulse: CGFloat = 1

    var body: some View {
        let palette = AppPalette(colorScheme)
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: state != .checking || reduceMotion)) { context in
            let elapsed = reduceMotion ? 0 : context.date.timeIntervalSince(startedAt)
            ZStack {
                ForEach(0..<3, id: \.self) { level in
                    ConnectivityArc(level: level)
                        .stroke(
                            signalColor(palette),
                            style: StrokeStyle(
                                lineWidth: max(1.15, size * 0.095),
                                lineCap: .round
                            )
                        )
                        .offset(y: searchingOffset(level: level, elapsed: elapsed))
                        .opacity(state == .unavailable ? 0.48 : 1)
                }

                Circle()
                    .fill(signalColor(palette))
                    .frame(width: max(2.4, size * 0.18), height: max(2.4, size * 0.18))
                    .offset(y: size * 0.31 + searchingOffset(level: 3, elapsed: elapsed))

                if state == .available {
                    Circle()
                        .stroke(palette.success.opacity((2 - connectionPulse) * 0.48), lineWidth: 1)
                        .frame(width: size, height: size)
                        .scaleEffect(connectionPulse)
                } else if state == .unavailable {
                    Capsule()
                        .fill(palette.subtleInk)
                        .frame(width: size * 0.82, height: max(1.2, size * 0.09))
                        .rotationEffect(.degrees(-44))
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { startedAt = .now }
        .onChange(of: state) { _, newValue in
            guard newValue == .available, !reduceMotion else {
                connectionPulse = 1
                return
            }
            connectionPulse = 0.72
            withAnimation(.easeOut(duration: 0.55)) {
                connectionPulse = 1.75
            }
        }
        .accessibilityHidden(true)
    }

    private func signalColor(_ palette: AppPalette) -> Color {
        switch state {
        case .checking: palette.primary
        case .available: palette.success
        case .unavailable: palette.subtleInk
        }
    }

    private func searchingOffset(level: Int, elapsed: TimeInterval) -> CGFloat {
        guard state == .checking, !reduceMotion else { return 0 }
        return sin(elapsed * 8.2 - Double(level) * 0.82) * min(1.45, size * 0.09)
    }
}

private struct ConnectivityArc: Shape {
    let level: Int

    func path(in rect: CGRect) -> Path {
        let radius = rect.width * (0.24 + CGFloat(level) * 0.16)
        let center = CGPoint(x: rect.midX, y: rect.maxY * 0.84)
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(218),
            endAngle: .degrees(322),
            clockwise: false
        )
        return path
    }
}

struct ComposerToolsButton: View {
    let isExpanded: Bool
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            Image(gattoSymbol: "plus")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(isExpanded ? palette.primary : palette.mutedInk)
                .rotationEffect(.degrees(isExpanded ? 45 : 0))
                .scaleEffect(isExpanded ? 1.08 : 1)
                .frame(width: 32, height: 32)
                .background(isExpanded ? palette.primarySoft : palette.raisedSurface)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(isExpanded ? palette.primary.opacity(0.34) : palette.divider, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.48 : 1)
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.70),
            value: isExpanded
        )
        .help(L10n.text("codex.action.skills"))
    }
}

struct DocumentTranslationActionLabel: View {
    let title: String
    let activeTitle: String
    let isActive: Bool
    var completionID: UUID? = nil
    var showsInitialCompletion = false
    var showsCancelIndicator = false

    var body: some View {
        ReadmeRewriteMotionLabel(
            title: isActive ? activeTitle : title,
            isActive: isActive,
            completionID: completionID,
            showsInitialCompletion: showsInitialCompletion,
            systemImage: "ai.translation",
            showsCancelIndicator: showsCancelIndicator
        )
    }
}

struct MotionLabelMenu<Content: View, Label: View>: View {
    let accessibilityLabel: String
    var isDisabled = false
    @ViewBuilder let content: () -> Content
    @ViewBuilder let label: () -> Label

    var body: some View {
        label()
            .fixedSize()
            .overlay {
                GeometryReader { geometry in
                    Menu {
                        content()
                    } label: {
                        Color.clear
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .accessibilityLabel(accessibilityLabel)
                }
            }
            .disabled(isDisabled)
    }
}
