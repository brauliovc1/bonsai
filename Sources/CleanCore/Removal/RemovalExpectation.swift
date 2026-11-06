import Foundation

/// What the person confirmed for one worktree: git's record of it and the verdict they were shown. Given to
/// `Remover`, it refuses when the fresh state differs, so nothing is removed that wasn't shown: another
/// worktree now at the same path, HEAD moved, a new blocker, or a note that wasn't on the confirmation
/// (a new ignored file, more local-only commits, another stash, other package clones).
public struct RemovalExpectation: Sendable, Hashable {
    public var repoPath: String
    public var path: String
    public var branch: String?
    public var head: String?
    public var kind: WorktreeKind
    public var safety: SafetyReport
    /// The newest activity the idle clock saw at confirmation. Activity after it means the worktree was used
    /// since; time passing alone changes nothing.
    public var newestActivity: Date?

    public init(assessment: WorktreeAssessment) {
        repoPath = assessment.worktree.repoPath
        path = assessment.worktree.path
        branch = assessment.worktree.branch
        head = assessment.worktree.head
        kind = assessment.worktree.kind
        safety = assessment.safety
        newestActivity = assessment.idle.newest
    }

    /// What differs from the confirmation, one sentence each; empty when nothing does.
    public func changes(fresh worktree: Worktree, safety fresh: SafetyReport, idle: IdleReport) -> [String] {
        var changes: [String] = []
        if !CanonicalPath.same(worktree.repoURL, URL(fileURLWithPath: repoPath, isDirectory: true)) {
            changes.append("It is now listed by \(worktree.repoPath), not \(repoPath).")
        }
        if worktree.branch != branch {
            changes.append("The branch is now \(Self.name(worktree.branch)) (was \(Self.name(branch))).")
        }
        if worktree.head != head {
            changes.append("HEAD moved from \(Self.short(head)) to \(Self.short(worktree.head)).")
        }
        if worktree.kind != kind {
            changes.append("Its kind is now \(worktree.kind.rawValue) (was \(kind.rawValue)).")
        }
        for reason in fresh.blockers where !safety.blockers.contains(reason) {
            changes.append("New: \(reason.sentence)")
        }
        // Associated values compare exactly: other ignored files, counts or clone lists are a change.
        for note in fresh.notes where !Self.isIdleNote(note) && !safety.notes.contains(note) {
            changes.append("New: \(note.sentence)")
        }
        if let now = idle.newest, let then = newestActivity, now > then {
            let signal = idle.newestSignal.map { " (\($0.label))" } ?? ""
            changes.append("It was used since\(signal).")
        }
        return changes
    }

    /// Thrown by `Remover` when `changes` is not empty; nothing was removed.
    public struct Mismatch: Error, Sendable, CustomStringConvertible {
        public var path: String
        public var changes: [String]

        public var description: String {
            "\(path) changed since it was confirmed, so nothing was removed; review it again. "
                + changes.joined(separator: " ")
        }
    }

    /// Idle notes move with the clock; `newestActivity` covers real activity.
    private static func isIdleNote(_ note: SafetyReason) -> Bool {
        switch note {
        case .recentlyActive, .idleUnknown: true
        default: false
        }
    }

    static func name(_ branch: String?) -> String {
        branch ?? "detached"
    }

    static func short(_ sha: String?) -> String {
        sha.map { String($0.prefix(12)) } ?? "none"
    }
}
