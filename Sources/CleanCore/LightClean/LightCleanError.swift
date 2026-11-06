/// Why `LightCleaner.clean` deleted nothing at all.
public enum LightCleanError: Error, Sendable, Hashable, CustomStringConvertible {
    /// The path is no longer a worktree of its repo.
    case notRegistered(path: String)
    /// The worktree can't be light-cleaned now: bare, folder gone, or its repo can't be listed.
    case unavailable(String)
    /// The folder is not this repo's worktree (any more): a stale record, or a `.git` git can't read.
    case wrongFolder(String)
    /// The worktree is not the one that was confirmed (another branch, HEAD or repo now).
    case changed(path: String, changes: [String])
    /// A process has its working folder inside the worktree.
    case inUse([ProcessCwdIndex.Entry])
    /// Running processes could not be checked, so nothing is deleted.
    case inUseUnknown(String)

    public var description: String {
        switch self {
        case .notRegistered(let path):
            return "\(path) is no longer a worktree of its repo"
        case .unavailable(let why):
            return "light clean refused: \(why)"
        case .wrongFolder(let why):
            return "light clean refused: " + LightCleanSkipReason.wrongFolder(why).sentence
        case .changed(let path, let changes):
            return "\(path) changed since it was listed, so nothing was deleted; review it again. "
                + changes.joined(separator: " ")
        case .inUse(let processes):
            return "light clean refused: " + LightCleanSkipReason.inUse(processes).sentence
        case .inUseUnknown(let why):
            return "light clean refused: " + LightCleanSkipReason.inUseUnknown(why).sentence
        }
    }
}
