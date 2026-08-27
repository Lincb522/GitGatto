import AppKit

@MainActor
final class GitGattoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        localizeMainMenu()
        AppIconAssets.updateApplicationIcon()
#if DEBUG
        writeMenuSnapshotIfRequested()
#endif
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        localizeMainMenu()
        AppIconAssets.updateApplicationIcon()
    }

    private func localizeMainMenu() {
        guard let menu = NSApp.mainMenu else { return }
        for item in menu.items {
            guard let key = MenuTitleLocalizer.key(for: item.title) else { continue }
            item.title = L10n.text(key)
        }
    }

#if DEBUG
    private func writeMenuSnapshotIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--menu-snapshot"),
              arguments.indices.contains(flagIndex + 1) else { return }
        let path = arguments[flagIndex + 1]

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            localizeMainMenu()
            guard let menu = NSApp.mainMenu else {
                NSApp.terminate(nil)
                return
            }

            let lines = menu.items.flatMap { item -> [String] in
                let children: [String] = item.submenu?.items
                    .filter { !$0.isSeparatorItem && !$0.title.isEmpty }
                    .map { child in
                        let shortcut = child.keyEquivalent.isEmpty ? "" : " [\(child.keyEquivalentModifierMask.rawValue)+\(child.keyEquivalent)]"
                        return "  \(child.title)\(shortcut)"
                    } ?? []
                return [item.title] + children
            }
            try? (lines.joined(separator: "\n") + "\n").write(
                toFile: path,
                atomically: true,
                encoding: .utf8
            )
            NSApp.terminate(nil)
        }
    }
#endif
}

enum MenuTitleLocalizer {
    private static let recognizedTitles: [String: String] = [
        "File": "menu.file",
        "文件": "menu.file",
        "Edit": "menu.edit",
        "编辑": "menu.edit",
        "View": "menu.view",
        "显示": "menu.view",
        "Repository": "menu.repository",
        "仓库": "menu.repository",
        "Window": "menu.window",
        "窗口": "menu.window",
        "Help": "menu.help",
        "帮助": "menu.help"
    ]

    static func key(for title: String) -> String? {
        recognizedTitles[title]
    }
}
