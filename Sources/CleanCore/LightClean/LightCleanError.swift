/// Why `LightCleaner.clean` deleted nothing at all.
public enum LightCleanError: Error, Sendable, Hashable, CustomStringConvertible {
    /// The path is no longer a worktree of its repo.
    case notRegistered(path: String)
    /// The worktree can't be light-cleaned now: bare, folder gone, or its repo can't be listed.
    case unavailable(String)
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
        case .inUse(let processes):
            return "light clean refused: " + LightCleanSkipReason.inUse(processes).sentence
        case .inUseUnknown(let why):
            return "light clean refused: " + LightCleanSkipReason.inUseUnknown(why).sentence
        }
    }
}
