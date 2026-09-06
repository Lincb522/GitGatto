import AppKit
import SwiftUI

struct LumenColorSettingsView: View {
    let store: LumenColorStore
    @State private var draft: LumenColorSettings
    @State private var appearance: LumenColorAppearance
    @State private var group: LumenColorGroup = .background
    @State private var error: String?
    @State private var showsResetConfirmation = false
    @State private var editorRevision = 0
    @State private var invalidRoles: Set<LumenColorRole> = []

    init(store: LumenColorStore, appearance: ColorScheme) {
        self.store = store
        _draft = State(initialValue: store.settings)
        _appearance = State(initialValue: LumenColorAppearance(appearance))
    }

    var body: some View {
        let colors = draft.resolved(appearance.scheme)
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("lumen.settings.title"))
                .font(.system(size: 14, weight: .semibold))
            Text(L10n.text("lumen.settings.preview_hint"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(LumenColorPreset.allCases) { preset in
                    presetButton(preset)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack { appearancePicker; Spacer(); resetButton }
                VStack(alignment: .leading, spacing: 10) { appearancePicker; resetButton }
            }

            LumenColorPreview(colors: colors, scheme: appearance.scheme)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                .accessibilityLabel(L10n.text("lumen.settings.preview"))

            Picker(L10n.text("lumen.settings.region"), selection: $group) {
                ForEach(LumenColorGroup.allCases) { group in
                    Text(L10n.text("lumen.group.\(group.rawValue)")).tag(group)
                }
            }
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 16)], alignment: .leading, spacing: 14) {
                ForEach(group.roles) { role in
                    LumenColorEditorRow(
                        role: role,
                        color: colors[role],
                        isCustomized: draft.override(role, appearance: appearance) != nil,
                        resetColor: resetColor(role),
                        update: { hex in draft.set(hex, for: role, appearance: appearance) },
                        invalidChanged: { invalid in
                            if invalid { invalidRoles.insert(role) } else { invalidRoles.remove(role) }
                        }
                    )
                    .id("\(draft.preset.rawValue).\(appearance.rawValue).\(role.rawValue).\(editorRevision)")
                }
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
                    .accessibilityIdentifier("lumen.save.error")
            }
            HStack(spacing: 12) {
                Button(L10n.text("lumen.settings.apply")) {
                    do {
                        try store.apply(draft)
                        error = nil
                    } catch {
                        self.error = L10n.text("lumen.settings.save_error")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft == store.settings || !invalidRoles.isEmpty)
                .accessibilityIdentifier("lumen.apply")
                Button(L10n.text("lumen.settings.discard")) {
                    draft = store.settings
                    editorRevision += 1
                    invalidRoles.removeAll()
                    error = nil
                }
                .disabled(draft == store.settings && invalidRoles.isEmpty)
                .accessibilityIdentifier("lumen.discard")
                Spacer(minLength: 0)
                if draft == store.settings, invalidRoles.isEmpty {
                    Text(L10n.text("lumen.settings.applied"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        // Keep the editor readable even when the draft contains low-contrast text or surfaces.
        .foregroundStyle(Color.primary)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .tint(Color.accentColor)
        .onChange(of: draft.preset) { _, _ in invalidRoles.removeAll() }
        .onChange(of: appearance) { _, _ in invalidRoles.removeAll() }
        .onChange(of: group) { _, _ in invalidRoles.removeAll() }
        .onChange(of: store.settings) { _, settings in draft = settings }
        .confirmationDialog(L10n.text("lumen.settings.reset_confirm"), isPresented: $showsResetConfirmation) {
            Button(L10n.text("lumen.settings.reset")) {
                draft.reset(appearance)
                editorRevision += 1
                invalidRoles.removeAll()
            }
        }
    }

    private func resetColor(_ role: LumenColorRole) -> Color {
        var original = draft
        original.set(nil, for: role, appearance: appearance)
        return original.resolved(appearance.scheme)[role]
    }

    private var appearancePicker: some View {
        Picker(L10n.text("lumen.settings.edit_appearance"), selection: $appearance) {
            ForEach(LumenColorAppearance.allCases) { appearance in
                Text(L10n.text("appearance.\(appearance.rawValue)")).tag(appearance)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 210)
        .accessibilityIdentifier("lumen.appearance")
    }

    private var resetButton: some View {
        Button(L10n.text("lumen.settings.reset")) { showsResetConfirmation = true }
            .disabled(!LumenColorRole.allCases.contains { draft.override($0, appearance: appearance) != nil })
    }

    private func presetButton(_ preset: LumenColorPreset) -> some View {
        var candidate = draft
        candidate.preset = preset
        let colors = candidate.resolved(appearance.scheme)
        return Button { draft.preset = preset } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    ForEach([LumenColorRole.background, .ambientLeading, .ambientTrailing, .primary, .ink]) { role in
                        RoundedRectangle(cornerRadius: 4).fill(colors[role])
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.gray.opacity(0.2)))
                            .frame(height: 20)
                    }
                }
                HStack {
                    Text(L10n.text(preset.titleKey)).font(.system(size: 12, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 2)
                    Image(systemName: "checkmark.circle.fill")
                        .opacity(draft.preset == preset ? 1 : 0)
                        .accessibilityHidden(true)
                }
            }
            .padding(10)
            .contentShape(Rectangle())
            .background(.primary.opacity(draft.preset == preset ? 0.07 : 0.02), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(draft.preset == preset ? Color.accentColor : Color.gray.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(draft.preset == preset ? .isSelected : [])
        .accessibilityIdentifier("lumen.preset.\(preset.rawValue)")
    }
}

struct LumenColorEditorRow: View {
    let role: LumenColorRole
    let color: Color
    let isCustomized: Bool
    let resetColor: Color
    let update: (String?) -> Void
    let invalidChanged: (Bool) -> Void
    @State private var hex: String
    @State private var isInvalid = false
    @FocusState private var editsHex: Bool

    init(role: LumenColorRole, color: Color, isCustomized: Bool, resetColor: Color, update: @escaping (String?) -> Void,
         invalidChanged: @escaping (Bool) -> Void) {
        self.role = role
        self.color = color
        self.isCustomized = isCustomized
        self.resetColor = resetColor
        self.update = update
        self.invalidChanged = invalidChanged
        _hex = State(initialValue: LumenRGBA(color)?.hex ?? "#00000000")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ColorPicker(L10n.text(role.titleKey), selection: Binding(
                get: { color },
                set: { value in
                    guard let rgba = LumenRGBA(value) else { return }
                    hex = rgba.hex
                    setInvalid(false)
                    update(rgba.hex)
                }
            ), supportsOpacity: true)
            .font(.system(size: 12))
            .accessibilityIdentifier("lumen.color.\(role.rawValue)")
            HStack(spacing: 8) {
                TextField("#RRGGBBAA", text: Binding(
                    get: { hex },
                    set: { text in
                        guard text != hex else { return }
                        hex = text
                        let value = LumenRGBA(hex: text)
                        setInvalid(value == nil)
                        if let value { update(value.hex) }
                    }
                ))
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L10n.text(role.titleKey) + " HEX")
                    .accessibilityIdentifier("lumen.hex.\(role.rawValue)")
                    .focused($editsHex)
                    .onSubmit { editsHex = false }
                Button {
                    hex = LumenRGBA(resetColor)?.hex ?? hex
                    update(nil)
                    setInvalid(false)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!isCustomized && !isInvalid)
                .help(L10n.text("lumen.settings.reset_color"))
                .accessibilityLabel(L10n.text("lumen.settings.reset_color") + " · " + L10n.text(role.titleKey))
            }
            if isInvalid {
                Text(L10n.text("lumen.settings.hex_error"))
                    .font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: color) { _, value in
            if !editsHex {
                hex = LumenRGBA(value)?.hex ?? hex
                setInvalid(false)
            }
        }
        .onChange(of: editsHex) { _, focused in
            if !focused, !isInvalid { hex = LumenRGBA(color)?.hex ?? hex }
        }
    }

    private func setInvalid(_ invalid: Bool) {
        isInvalid = invalid
        invalidChanged(invalid)
    }
}

struct LumenColorPreview: View {
    let colors: LumenResolvedColors
    let scheme: ColorScheme

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let radius = max(proxy.size.width, proxy.size.height)
                colors[.background]
                RadialGradient(colors: colors.ambientStops[0], center: UnitPoint(x: 0.02, y: 0.24), startRadius: 0, endRadius: radius * 0.82)
                RadialGradient(colors: colors.ambientStops[1], center: UnitPoint(x: 0.96, y: 0.36), startRadius: 0, endRadius: radius * 0.82)
                RadialGradient(colors: [.clear, .clear, colors[.vignette]], center: UnitPoint(x: 0.5, y: 0.44),
                    startRadius: min(proxy.size.width, proxy.size.height) * 0.2, endRadius: radius * 0.72)
                LinearGradient(colors: [colors[.backdropTop], .clear, colors[.backdropBottom]], startPoint: .top, endPoint: .bottom)
            }
            VStack(spacing: 0) {
                HStack {
                    Text("GitGatto").font(.system(size: 13, weight: .semibold)).foregroundStyle(colors[.ink])
                    Spacer()
                    Text("main").font(.system(size: 11, design: .monospaced)).foregroundStyle(colors[.primary])
                        .padding(.horizontal, 10).padding(.vertical, 4).background(colors[.primarySoft], in: Capsule())
                }
                .padding(12).background(colors[.chrome])
                .overlay(alignment: .bottom) { Rectangle().fill(colors[.chromeBorder]).frame(height: 1) }
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.text("nav.github"), systemImage: "square.grid.2x2")
                        Label(L10n.text("nav.changes"), systemImage: "doc.on.doc")
                    }
                    .font(.system(size: 11)).foregroundStyle(colors[.mutedInk])
                    .padding(10).frame(maxHeight: .infinity, alignment: .top).background(colors[.sidebar])
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("README.md").font(.system(size: 12, weight: .medium)).foregroundStyle(colors[.ink])
                                .padding(4).background(colors[.raisedSurface], in: RoundedRectangle(cornerRadius: 4))
                            Text("↗").foregroundStyle(colors[.accent]).padding(4).background(colors[.accentSoft], in: Circle())
                            Spacer()
                            Text(L10n.text("lumen.color.primary"))
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(colors[.onPrimary])
                                .padding(.horizontal, 10).padding(.vertical, 5).background(colors[.primary], in: RoundedRectangle(cornerRadius: 6))
                        }
                        Rectangle().fill(colors[.divider]).frame(height: 1)
                        HStack(spacing: 10) {
                            ForEach([LumenColorRole.success, .warning, .danger]) { role in
                                Label(L10n.text(role.titleKey), systemImage: role == .success ? "checkmark.circle" : "exclamationmark.triangle")
                                    .font(.system(size: 10)).foregroundStyle(colors[role])
                                    .padding(.horizontal, 4).padding(.vertical, 3)
                                    .background(colors[role == .success ? .successSoft : (role == .warning ? .warningSoft : .dangerSoft)], in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        RoundedRectangle(cornerRadius: 3).fill(colors[.subtleInk].opacity(0.3)).frame(height: 4)
                            .padding(4).background(colors[.inset], in: RoundedRectangle(cornerRadius: 4))
                    }
                    .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(colors[.surface], in: RoundedRectangle(cornerRadius: 8))
                    .padding(4)
                    .background(colors[.panel], in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors[.divider]))
                }
                .padding(8)
            }
        }
        .environment(\.colorScheme, scheme)
        .allowsHitTesting(false)
    }
}
