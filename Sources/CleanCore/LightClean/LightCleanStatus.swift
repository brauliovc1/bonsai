import Foundation

/// The worktree's `git status --porcelain=v1 -z --untracked-files=all`, read once per worktree (and again
/// before each delete): light clean refuses a folder with any entry under it (PLAN §4.2). Paths are matched
/// case-insensitively and in one Unicode form, like APFS matches names.
struct LightCleanStatus: Sendable, Hashable {
    /// Every path git listed (both sides of a rename), as git printed it.
    var paths: [String]

    static func read(git: Git, worktree: URL) async throws -> LightCleanStatus {
        let output = try await git.git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], in: worktree)
        return LightCleanStatus(paths: parse(output))
    }

    /// `XY path\0` per entry; a rename or copy (`R`/`C`) is followed by its source path.
    static func parse(_ data: Data) -> [String] {
        let fields = data.split(separator: 0)
        var paths: [String] = []
        var index = fields.startIndex
        while index < fields.endIndex {
            let field = fields[index]
            let codes = field.prefix(2)
            paths.append(String(decoding: field.dropFirst(3), as: UTF8.self))
            if codes.contains(UInt8(ascii: "R")) || codes.contains(UInt8(ascii: "C")), index + 1 < fields.endIndex {
                paths.append(String(decoding: fields[index + 1], as: UTF8.self))
                index += 2
            } else {
                index += 1
            }
        }
        return paths
    }

    /// The listed paths that are `relative` or inside it.
    func paths(under relative: String) -> [String] {
        let folder = Self.key(relative)
        return paths.filter { path in
            let key = Self.key(path.hasSuffix("/") ? String(path.dropLast()) : path)
            return key == folder || key.hasPrefix(folder + "/")
        }
    }

    /// One Unicode form, case folded.
    static func key(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: nil)
    }
}
