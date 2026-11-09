import Foundation

/// PLAN §4.1 "Package copies" (added 11-09): a nested repo at `SourcePackages/checkouts/<x>`,
/// `SourcePackages/repositories/<x>`, `.build/checkouts/<x>` or `.build/repositories/<x>` that sits inside a
/// §4.2 folder git ignores and tracks nothing in (for `.build`, that folder itself) is a package manager's copy.
/// Xcode and SwiftPM fetch it again, so it counts as build output whatever git says about it, broken copies
/// included (Flutter's `build/ios/SourcePackages` checkouts whose mirror lost its objects, seen on 11-09).
///
/// Decided from the path and from git's ignore and tracked checks on the build folder, asked from outside the
/// copy (`IgnoredOutputCheck`): git never runs inside a copy. Light clean uses the same rule.
struct PackageCopyRule: Sendable {
    var git: Git
    /// The checkout whose git answers; paths are relative to it.
    var worktree: URL

    /// The build folders that make a repo at `relative` a package copy when git ignores one of them and tracks
    /// nothing in it, outermost first: the `.build` folder itself, or each §4.2 folder above `SourcePackages`.
    /// Empty when the path is not a package manager's.
    static func outputFolders(for relative: String) -> [String] {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let count = parts.count
        guard count >= 3, ["checkouts", "repositories"].contains(parts[count - 2]) else { return [] }
        switch parts[count - 3] {
        case ".build":
            return [parts[..<(count - 2)].joined(separator: "/")]
        case "SourcePackages":
            return (0..<(count - 3)).filter { RegenerableNames.isRegenerableFolder(parts[$0]) }
                .map { parts[...$0].joined(separator: "/") }
        default:
            return []
        }
    }

    /// The repos among `relativePaths` that are package copies. Each build folder is asked about once.
    func copies(among relativePaths: [String]) async -> Set<String> {
        let check = IgnoredOutputCheck(git: git)
        var isOutput: [String: Bool] = [:]
        var copies: Set<String> = []
        for relative in relativePaths {
            for folder in Self.outputFolders(for: relative) {
                if isOutput[folder] == nil {
                    let parts = folder.split(separator: "/").map(String.init)
                    let parent = parts.dropLast().reduce(worktree) { $0.appending(path: $1, directoryHint: .isDirectory) }
                    isOutput[folder] = await check.reason(name: parts.last ?? folder, parent: parent, worktree: worktree) == nil
                }
                if isOutput[folder] == true {
                    copies.insert(relative)
                    break
                }
            }
        }
        return copies
    }
}
