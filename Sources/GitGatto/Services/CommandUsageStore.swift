import Combine
import Foundation

@MainActor
final class CommandUsageStore: ObservableObject {
    static let shared = CommandUsageStore()
    @Published private(set) var pinned: [String]
    @Published private(set) var recent: [String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pinned = defaults.stringArray(forKey: "commandPalette.pinned") ?? []
        recent = defaults.stringArray(forKey: "commandPalette.recent") ?? []
    }

    func togglePin(_ id: String) {
        if pinned.contains(id) { pinned.removeAll { $0 == id } }
        else { pinned.append(id) }
        defaults.set(pinned, forKey: "commandPalette.pinned")
    }

    func record(_ id: String) {
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        recent = Array(recent.prefix(20))
        defaults.set(recent, forKey: "commandPalette.recent")
    }

    func orderedIDs(_ available: [String]) -> [String] {
        let allowed = Set(available)
        var seen = Set<String>()
        return (pinned + recent + available).filter { allowed.contains($0) && seen.insert($0).inserted }
    }
}

enum CommandSearchIndex {
    static func matches(_ query: String, text: [String]) -> Bool {
        let normalize: (String) -> String = {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        }
        let content = normalize(text.joined(separator: " "))
        return normalize(query).split(whereSeparator: \.isWhitespace).allSatisfy { content.contains($0) }
    }
}
