import Foundation

/// One entry of `git status --porcelain=v1 -z --untracked-files=all`: the two status letters and the path
/// (relative to the worktree), with the source of a rename or copy.
public struct GitStatusEntry: Sendable, Hashable {
    /// git's two letters: "??" untracked, " M" changed, "M " staged, "A " added, "D " deleted, "UU" conflict...
    public var code: String
    public var path: String
    /// A rename's or copy's original path.
    public var from: String?

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
