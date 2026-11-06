import Foundation

/// A folder light clean may delete (PLAN §4.2). Only `LightCleanFinder` makes these (the initializer is
/// internal), and `LightCleaner` checks every condition again right before deleting one.
public struct LightCleanCandidate: Sendable, Hashable, Encodable {
    /// The worktree it was found in, as git printed it.
    public let worktreePath: String
    /// Relative to the worktree: `node_modules`, `packages/a/node_modules`.
    public let relativePath: String
    /// The folder's own name, one of `RegenerableNames.folders`.
    public let name: String
    /// `du -skx` estimate; nil when sizes were not asked for or `du` failed.
    public let estimatedBytes: Int64?
    /// Clones with no local work inside (package checkouts, fetched again on the next build); they go
    /// with the folder.
    public let packageClones: [String]

    public var path: String { worktreePath + "/" + relativePath }
    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}
