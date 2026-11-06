/// One word for a worktree's verdict: the STATUS column of `scan`.
public enum WorktreeStatus: Sendable, Hashable {
    /// Auto mode would remove it.
    case autoReady
    /// Can be removed by hand, not by auto mode.
    case safe
    /// Can't be removed; the reason is the first blocker that is not "in use".
    case blocked(SafetyReason)
    /// Only blocked because a process has its working folder inside.
    case inUse

    public var label: String {
        switch self {
        case .autoReady: "AUTO-READY"
        case .safe: "SAFE"
        case .blocked(let reason): "BLOCKED: \(reason.label)"
        case .inUse: "IN USE"
        }
    }

    /// The `--status` filter group: `auto-ready`, `safe` or `blocked` (in use counts as blocked).
    public var group: String {
        switch self {
        case .autoReady: "auto-ready"
        case .safe: "safe"
        case .blocked, .inUse: "blocked"
        }
    }
}
