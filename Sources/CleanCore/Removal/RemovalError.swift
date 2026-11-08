/// Why `Remover.remove` removed nothing.
public enum RemovalError: Error, Sendable, CustomStringConvertible {
    /// The path is no longer a worktree of its repo.
    case notRegistered(path: String)
    /// The re-check right before removal said no.
    case refused(mode: RemovalMode, report: SafetyReport)
    /// `git worktree remove` refused; nothing was logged.
    case gitFailed(stderr: String)
    /// `git worktree remove` didn't finish in time and was stopped; nothing was logged, and part of the folder
    /// may already be gone.
    case interrupted(path: String)
    /// The caller's last check, right before git, said not to go on; nothing was touched or logged.
    case stopped(RemovalStop)

    public var description: String {
        switch self {
        case .notRegistered(let path):
            return "\(path) is no longer a worktree of its repo"
        case .refused(let mode, let report):
            let reasons = mode == .manual ? report.blockers : report.autoBlockers
            return "refused (\(mode.rawValue)): " + reasons.map(\.sentence).joined(separator: " ")
        case .gitFailed(let stderr):
            return "git refused: " + stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        case .interrupted:
            return "interrupted; the folder may be partly removed"
        case .stopped(let stop):
            return stop.sentence
        }
    }
}
