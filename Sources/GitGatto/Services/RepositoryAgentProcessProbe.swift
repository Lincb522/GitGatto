import Darwin
import Foundation

enum RepositoryAgentProcessProbe {
    private static let agentNames = [
        "codex", "claude", "gemini", "cursor", "copilot", "aider",
        "opencode", "amp", "goose", "continue", "zed-agent",
    ]

    struct Observation: Equatable {
        let processID: Int32
        let executable: String
        let workingDirectory: String
    }

    static func matchingAgents(for repositoryURL: URL) -> [RepositoryActivityAgent] {
        guard let repository = canonicalPath(repositoryURL.path),
              let processIDs = processIDs() else { return [] }
        var matches: [RepositoryActivityAgent] = []
        for pid in processIDs {
            guard !Task.isCancelled else { return [] }
            guard let executable = executablePath(for: pid),
                  let name = agentName(for: executable),
                  let observation = observation(for: pid),
                  observation.executable == executable,
                  contains(repository: repository, directory: observation.workingDirectory)
            else { continue }
            matches.append(RepositoryActivityAgent(processID: pid, name: name))
        }
        return matches.sorted { $0.processID < $1.processID }
    }

    static func agentName(for executable: String) -> String? {
        let name = executable.split(separator: "/").last?.lowercased() ?? ""
        return agentNames.first { candidate in
            guard name.hasPrefix(candidate) else { return false }
            let suffix = name.dropFirst(candidate.count)
            return suffix.isEmpty || suffix.first == "-" || suffix.first == "_" || suffix.first == " "
        }
    }

    static func observation(for pid: Int32) -> Observation? {
        guard pid > 0, let before = identity(for: pid),
              let executable = executablePath(for: pid) else { return nil }
        var paths = proc_vnodepathinfo()
        let size = Int32(MemoryLayout.size(ofValue: paths))
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &paths, size) == size,
              let directory = withUnsafeBytes(of: &paths.pvi_cdir.vip_path, { bytes in
                  String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8)
              }), directory.hasPrefix("/"),
              let after = identity(for: pid),
              before.pbi_start_tvsec == after.pbi_start_tvsec,
              before.pbi_start_tvusec == after.pbi_start_tvusec,
              executablePath(for: pid) == executable else { return nil }
        // Never combine a reused PID or an exec transition with another process's directory.
        return Observation(processID: pid, executable: executable, workingDirectory: directory)
    }

    static func contains(repository: String, directory: String) -> Bool {
        directory == repository || directory.hasPrefix(repository == "/" ? "/" : repository + "/")
    }

    private static func canonicalPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(validatingCString: resolved)
    }

    private static func identity(for pid: Int32) -> proc_bsdinfo? {
        var value = proc_bsdinfo()
        let size = Int32(MemoryLayout.size(ofValue: value))
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &value, size) == size,
              value.pbi_pid == UInt32(pid) else { return nil }
        return value
    }

    private static func executablePath(for pid: Int32) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is an unimportable C expression macro (4 * MAXPATHLEN).
        var bytes = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &bytes, UInt32(bytes.count)) > 0 else { return nil }
        return String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8)
    }

    private static func processIDs() -> [Int32]? {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return nil }
        var capacity = Int(count) + 128
        // A full buffer may omit another candidate. Retry a bounded number of times;
        // incomplete enumeration must not turn an ambiguous attribution into a unique one.
        for _ in 0..<3 {
            guard !Task.isCancelled,
                  capacity <= Int(Int32.max) / MemoryLayout<Int32>.stride else { return nil }
            var values = [Int32](repeating: 0, count: capacity)
            let actual = proc_listallpids(&values, Int32(capacity * MemoryLayout<Int32>.stride))
            guard actual > 0 else { return nil }
            if Int(actual) < capacity { return Array(Set(values.prefix(Int(actual)).filter { $0 > 0 })) }
            capacity *= 2
        }
        return nil
    }
}
