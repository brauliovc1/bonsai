import Foundation

/// One entry of `git status --porcelain=v1 -z --untracked-files=all`: the two status letters and the path
/// (relative to the worktree), with the source of a rename or copy.
public struct GitStatusEntry: Sendable, Hashable {
    /// git's two letters: "??" untracked, " M" changed, "M " staged, "A " added, "D " deleted, "UU" conflict...
    public var code: String
    public var path: String
    /// A rename's or copy's original path.
    public var from: String?

    /// What happened to the file, in one plain word (the app's file list, the Remove anyway list and its log).
    public enum Change: String, Sendable, Hashable {
        case modified = "Modified", new = "New", deleted = "Deleted", renamed = "Renamed", copied = "Copied",
             conflict = "Conflict"
    }

    /// From git's two letters: untracked or added = new; a rename or copy in the index; deleted on either side;
    /// both sides changed or a merge left it unmerged = conflict; anything else (changed, type changed) = modified.
    public var change: Change {
        let letters = Array(code)
        let index = letters.first ?? " "
        let tree = letters.count > 1 ? letters[1] : " "
        if code == "??" { return .new }
        if letters.contains("U") || code == "AA" || code == "DD" { return .conflict }
        if index == "R" { return .renamed }
        if index == "C" { return .copied }
        if index == "D" || tree == "D" { return .deleted }
        if index == "A" { return .new }
        return .modified
    }

    /// "Modified", "Renamed from old.txt".
    public var changeText: String {
        guard let from, change == .renamed || change == .copied else { return change.rawValue }
        return "\(change.rawValue) from \(from)"
    }

    public init(code: String, path: String, from: String? = nil) {
        self.code = code
        self.path = path
        self.from = from
    }

    /// The entries of `status --porcelain=v1 -z`. A rename or copy (`R`/`C`) is followed by its source path,
    /// which is not a separate entry.
    public static func parse(_ data: Data) -> [GitStatusEntry] {
        let fields = data.split(separator: 0)
        var entries: [GitStatusEntry] = []
        var index = fields.startIndex
        while index < fields.endIndex {
            let field = fields[index]
            let code = String(decoding: field.prefix(2), as: UTF8.self)
            let path = String(decoding: field.dropFirst(3), as: UTF8.self)
            let renamed = code.contains("R") || code.contains("C")
            let from = renamed && index + 1 < fields.endIndex
                ? String(decoding: fields[index + 1], as: UTF8.self) : nil
            entries.append(GitStatusEntry(code: code, path: path, from: from))
            index += renamed ? 2 : 1
        }
        return entries
    }
}
