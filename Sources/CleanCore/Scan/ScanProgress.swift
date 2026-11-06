/// Where a running scan is, reported through `Scanner.scan(progress:)`.
public enum ScanProgress: Sendable, Equatable {
    case discoveringRepos(roots: Int)
    case listingWorktrees(completed: Int, total: Int)
    case measuringSizes(completed: Int, total: Int)
    case finished
}
