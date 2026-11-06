import Foundation

/// Path comparison that sees through symlinks (`/tmp` vs `/private/tmp`, `/var/folders` vs
/// `/private/var/folders`).
///
/// `realpath(3)` is applied to the longest prefix that exists, and the missing rest is appended, so paths
/// of deleted folders (prunable worktrees) still compare correctly. Foundation's `standardizedFileURL` and
/// `resolvingSymlinksInPath` are not used because they strip `/private` only when the result exists.
public enum CanonicalPath {
    public static func resolve(_ url: URL) -> String {
        resolve(url.path)
    }

    public static func resolve(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardized.path
        var head = standardized
        var missing: [String] = []
        while true {
            if let real = realpath(head, nil) {
                defer { free(real) }
                let base = String(cString: real)
                guard !missing.isEmpty else { return base }
                let rest = missing.reversed().joined(separator: "/")
                return base == "/" ? "/" + rest : base + "/" + rest
            }
            let parent = (head as NSString).deletingLastPathComponent
            guard !parent.isEmpty, parent != head else { return standardized }
            missing.append((head as NSString).lastPathComponent)
            head = parent
        }
    }

    public static func same(_ lhs: URL, _ rhs: URL) -> Bool {
        resolve(lhs) == resolve(rhs)
    }

    /// The path of `url` relative to `directory`: `"."` when they are the same folder, nil when `url`
    /// is not inside `directory`.
    public static func relativePath(of url: URL, to directory: URL) -> String? {
        let path = resolve(url)
        let base = resolve(directory)
        if path == base { return "." }
        let prefix = base == "/" ? "/" : base + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }

    /// True when `url` is strictly inside `directory`.
    public static func isInside(_ url: URL, directory: URL) -> Bool {
        guard let relative = relativePath(of: url, to: directory) else { return false }
        return relative != "."
    }
}
