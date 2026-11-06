/// The verdict for one worktree (PLAN §4.1), with the manual and auto columns computed separately.
public struct SafetyReport: Sendable, Hashable {
    /// Reasons that block every removal (and therefore auto mode too). Ordered most important first.
    public var blockers: [SafetyReason]
    /// Reasons that don't block a removal by hand but are shown with it. Some of them keep auto mode away.
    public var notes: [SafetyReason]
    /// Every reason that keeps auto mode away: all blockers plus the notes that block auto.
    public var autoBlockers: [SafetyReason]
    public var manualAllowed: Bool
    public var autoEligible: Bool

    public init(blockers: [SafetyReason], notes: [SafetyReason], autoBlockers: [SafetyReason]) {
        self.blockers = blockers
        self.notes = notes
        self.autoBlockers = autoBlockers
        self.manualAllowed = blockers.isEmpty
        self.autoEligible = blockers.isEmpty && autoBlockers.isEmpty
    }

    public var status: WorktreeStatus {
        if autoEligible { return .autoReady }
        if manualAllowed { return .safe }
        if let first = blockers.first(where: { !$0.isInUse }) { return .blocked(first) }
        return .inUse
    }

    /// The reasons that block auto mode only (not removal by hand).
    public var autoOnlyBlockers: [SafetyReason] {
        autoBlockers.filter { !blockers.contains($0) }
    }
}
