import SwiftUI

struct GlobalCommandPalette: View {
    @ObservedObject var model: WorkspaceViewModel
    let openSettings: () -> Void
    let openScanner: () -> Void
    let openHelp: () -> Void
    let dismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let palette = AppPalette(colorScheme)
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(gattoSymbol: "command")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.primary)
                TextField(L10n.text("command_palette.placeholder"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .focused($isSearchFocused)
                    .onSubmit { runSelected() }
                Text("⌘K")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.subtleInk)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(palette.raisedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            Rectangle().fill(palette.divider).frame(height: 1)

            if filteredCommands.isEmpty {
                VStack(spacing: 8) {
                    Image(gattoSymbol: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundStyle(palette.subtleInk)
                    Text(L10n.text("command_palette.empty"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.mutedInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                                CommandPaletteRow(
                                    command: command,
                                    isSelected: selectedIndex == index
                                ) {
                                    command.action()
                                    dismiss()
                                }
                                .id(command.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedIndex) { _, index in
                        guard filteredCommands.indices.contains(index) else { return }
                        reader.scrollTo(filteredCommands[index].id, anchor: .center)
                    }
                }
            }

            Rectangle().fill(palette.divider).frame(height: 1)
            HStack(spacing: 14) {
                Label(L10n.text("command_palette.hint.navigate"), systemImage: "arrow.up.arrow.down")
                Label(L10n.text("command_palette.hint.run"), systemImage: "return")
                Spacer()
                Text(L10n.format("command_palette.count", filteredCommands.count))
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(palette.subtleInk)
            .padding(.horizontal, 14)
            .frame(height: 34)
        }
        .frame(width: 650, height: 510)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(palette.divider) }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.16), radius: 28, y: 14)
        .onAppear { isSearchFocused = true }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(max(0, filteredCommands.count - 1), selectedIndex + 1)
            return .handled
        }
        .onExitCommand(perform: dismiss)
    }

    private var filteredCommands: [CommandPaletteItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return commands }
        let tokens = needle.lowercased().split(whereSeparator: \Character.isWhitespace).map(String.init)
        return commands.filter { command in
            let haystack = ([command.title, command.subtitle] + command.keywords)
                .joined(separator: " ").lowercased()
            return tokens.allSatisfy(haystack.contains)
        }
    }

    private var commands: [CommandPaletteItem] {
        var values = WorkspaceSection.allCases.map { section in
            CommandPaletteItem(
                id: "section.\(section.rawValue)",
                title: L10n.text("nav.\(section.rawValue)"),
                subtitle: L10n.text("command_palette.group.navigate"),
                symbol: section.symbol,
                keywords: [section.rawValue, "navigate", "workspace"],
                action: { model.selectedSection = section }
            )
        }

        values += model.localRepositories.map { repositoryURL in
            CommandPaletteItem(
                id: "repository.\(repositoryURL.standardizedFileURL.path)",
                title: repositoryURL.lastPathComponent,
                subtitle: L10n.text("command_palette.group.repositories"),
                symbol: "folder",
                keywords: [repositoryURL.path, "repository", "repo"],
                action: { Task { await model.openRepository(repositoryURL) } }
            )
        }

        if let snapshot = model.snapshot {
            values += snapshot.branches.filter { !$0.isCurrent }.map { branch in
                CommandPaletteItem(
                    id: "branch.\(branch.name)",
                    title: branch.name,
                    subtitle: L10n.text("command_palette.group.branches"),
                    symbol: "arrow.triangle.branch",
                    keywords: [branch.upstream ?? "", "checkout", "switch", "branch"],
                    action: { Task { await model.switchBranch(to: branch.name) } }
                )
            }

            values.append(contentsOf: repositoryActions(snapshot: snapshot))
        }

        values.append(
            CommandPaletteItem(
                id: "commit-search",
                title: L10n.text("commit_search.title"),
                subtitle: L10n.text("command_palette.group.git"),
                symbol: "magnifyingglass",
                keywords: ["commit", "history", "sha", "author", "search"],
                action: {
                    Task { @MainActor in
                        model.selectedSection = .history
                        try? await Task.sleep(for: .milliseconds(120))
                        NotificationCenter.default.post(name: .gitGattoShowCommitSearch, object: nil)
                    }
                }
            )
        )

        values += [
            CommandPaletteItem(
                id: "scanner",
                title: L10n.text("repository.scan.open"),
                subtitle: L10n.text("command_palette.group.application"),
                symbol: "folder.badge.plus",
                keywords: ["scan", "repository", "add"],
                action: openScanner
            ),
            CommandPaletteItem(
                id: "settings",
                title: L10n.text("settings.open"),
                subtitle: L10n.text("command_palette.group.application"),
                symbol: "gearshape",
                keywords: ["preferences", "configuration"],
                action: openSettings
            ),
            CommandPaletteItem(
                id: "help",
                title: L10n.text("help.menu.guide"),
                subtitle: L10n.text("command_palette.group.application"),
                symbol: "questionmark.circle",
                keywords: ["guide", "documentation"],
                action: openHelp
            )
        ]
        return values
    }

    private func repositoryActions(snapshot: RepositorySnapshot) -> [CommandPaletteItem] {
        var values = [
            CommandPaletteItem(
                id: "refresh",
                title: L10n.text("action.refresh"),
                subtitle: L10n.text("command_palette.group.git"),
                symbol: "arrow.clockwise",
                keywords: ["reload", "status"],
                action: { Task { await model.refresh() } }
            ),
            CommandPaletteItem(
                id: "pull",
                title: L10n.text("action.pull"),
                subtitle: L10n.text("command_palette.group.git"),
                symbol: "arrow.down",
                keywords: ["fetch", "remote"],
                action: { Task { await model.pull() } }
            ),
            CommandPaletteItem(
                id: "push",
                title: L10n.text("action.push"),
                subtitle: L10n.text("command_palette.group.git"),
                symbol: "arrow.up",
                keywords: ["publish", "remote"],
                action: { Task { await model.push() } }
            )
        ]
        if !snapshot.unstagedChanges.isEmpty {
            values.append(
                CommandPaletteItem(
                    id: "stage-all",
                    title: L10n.text("action.stage_all"),
                    subtitle: L10n.text("command_palette.group.git"),
                    symbol: "plus.rectangle.on.folder",
                    keywords: ["add", "stage", "changes"],
                    action: { Task { await model.stage(snapshot.unstagedChanges) } }
                )
            )
        }
        return values
    }

    private func runSelected() {
        guard filteredCommands.indices.contains(selectedIndex) else { return }
        filteredCommands[selectedIndex].action()
        dismiss()
    }
}

private struct CommandPaletteItem {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let keywords: [String]
    let action: () -> Void
}

private struct CommandPaletteRow: View {
    let command: CommandPaletteItem
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        let palette = AppPalette(colorScheme)
        Button(action: action) {
            HStack(spacing: 12) {
                Image(gattoSymbol: command.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.primary : palette.mutedInk)
                    .frame(width: 32, height: 32)
                    .background(isSelected ? palette.primarySoft : palette.raisedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(command.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text(command.subtitle)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(palette.subtleInk)
                }
                Spacer()
                if isSelected {
                    Image(gattoSymbol: "return")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.subtleInk)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 48)
            .background(isSelected || isHovering ? palette.primarySoft.opacity(isSelected ? 1 : 0.55) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private extension WorkspaceSection {
    var symbol: String {
        switch self {
        case .changes: "square.3.layers.3d"
        case .intelligence: "point.3.connected.trianglepath.dotted"
        case .stash: "archivebox"
        case .history: "clock.arrow.circlepath"
        case .timeMachine: "doc.badge.clock"
        case .recovery: "lifepreserver"
        case .branches: "arrow.triangle.branch"
        case .worktrees: "rectangle.split.2x1"
        case .diagnostics: "stethoscope"
        case .regression: "scope"
        case .github: "square.grid.2x2"
        case .marketplace: "bag"
        case .goals: "target"
        case .codex: "sparkles"
        }
    }
}
