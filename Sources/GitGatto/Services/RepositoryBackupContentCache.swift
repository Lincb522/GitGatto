import Darwin
import Foundation

/// Retains verified equality only; Git status, history and destructive-change checks still run.
final class RepositoryBackupContentCache: @unchecked Sendable {
    private struct Stamp: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let mode: mode_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init?(_ url: URL) {
            var value = stat()
            // Do not memoize symlink targets, directories or missing/inaccessible files.
            guard lstat(url.path, &value) == 0, value.st_mode & S_IFMT == S_IFREG else { return nil }
            device = value.st_dev
            inode = value.st_ino
            size = value.st_size
            mode = value.st_mode
            modifiedSeconds = value.st_mtimespec.tv_sec
            modifiedNanoseconds = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec
            changedNanoseconds = value.st_ctimespec.tv_nsec
        }
    }

    private final class Entry: NSObject {
        let left: Stamp
        let right: Stamp
        init(left: Stamp, right: Stamp) { self.left = left; self.right = right }
    }

    // NSCache synchronizes access and evicts under memory pressure. No file contents are retained.
    private let entries = NSCache<NSString, Entry>()

    init() { entries.countLimit = 4_096 }

    func contentsEqual(
        _ left: URL,
        _ right: URL,
        compare: (String, String) -> Bool = { FileManager.default.contentsEqual(atPath: $0, andPath: $1) }
    ) -> Bool {
        let key = (left.path + "\0" + right.path) as NSString
        guard let leftStamp = Stamp(left), let rightStamp = Stamp(right) else {
            entries.removeObject(forKey: key)
            return compare(left.path, right.path)
        }
        if let entry = entries.object(forKey: key), entry.left == leftStamp, entry.right == rightStamp {
            return true
        }
        entries.removeObject(forKey: key)
        let equal = compare(left.path, right.path)
        // Re-stat both sides so a write during comparison cannot validate a later cache hit.
        // ctime also invalidates same-size writes whose mtime was restored by an editor/tool.
        if equal, Stamp(left) == leftStamp, Stamp(right) == rightStamp {
            entries.setObject(Entry(left: leftStamp, right: rightStamp), forKey: key)
        }
        return equal
    }
}
