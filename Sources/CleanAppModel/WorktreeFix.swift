/// The one action the details panel offers for a worktree: the one that does the job, or that fixes what stops
/// it (`WorktreeStatusText.fix(for:)`). Every destructive one opens its existing confirmation sheet.
public enum WorktreeFix: String, Sendable, Hashable, CaseIterable {
    case remove
    case prune
    case cleanDependencies
    case openInTerminal
    case showInFinder
    case refresh
    /// Nothing the app can do (a record that belongs to another repo's folder).
    case none

    public var title: String {
        switch self {
        case .remove: "Remove…"
        case .prune: "Prune missing folders…"
        case .cleanDependencies: "Clean dependencies…"
        case .openInTerminal: "Open in Terminal"
        case .showInFinder: "Show in Finder"
        case .refresh: "Refresh"
        case .none: ""
        }
    }
}
