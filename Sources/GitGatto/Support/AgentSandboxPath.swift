import Darwin
import Foundation

enum AgentSandboxPath {
    static func canonical(_ url: URL) -> String {
        // Foundation keeps /var aliases on macOS; Seatbelt matches the kernel's /private/var
        // path. Resolve an existing ancestor for rules covering files not created yet.
        var ancestor = url.standardizedFileURL.resolvingSymlinksInPath()
        var suffix: [String] = []
        while true {
            if let resolved = realpath(ancestor.path, nil) {
                defer { free(resolved) }
                return suffix.reversed().reduce(String(cString: resolved)) { path, component in
                    (path as NSString).appendingPathComponent(component)
                }
            }
            guard ancestor.path != "/" else { return url.standardizedFileURL.path }
            suffix.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
    }
}
