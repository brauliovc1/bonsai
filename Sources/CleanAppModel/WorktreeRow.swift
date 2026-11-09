import CleanCore
import Foundation

/// One row of the Worktrees table: a worktree and its verdict from the last scan, with the texts and sort
/// keys the table shows.
public struct WorktreeRow: Identifiable, Hashable, Sendable {
    /// How a status is drawn: one badge color per group.
    public enum Tone: Sendable, Hashable {
        case autoReady, safe, blocked, inUse
    }

    public let assessment: WorktreeAssessment
    /// Position in the scan (each repo's main checkout first); the last sort key, so ties keep it.
    public let scanOrder: Int
    /// The Deps column: what light clean could delete here (not part of the safety verdict).
    public let dependencies: DependencySize
    /// The commit HEAD points at, from the scan (`ScanResult.lastCommits`).
    public let lastCommit: CommitSummary?
    /// The repo's remotes, "origin" first, URLs without credentials.
    public let remotes: [GitRemote]
    /// The folder with "~" for the home folder.
    public let folderText: String
    /// The main repo folder with "~".
    public let repoFolderText: String
    /// When the row was made, for "3d ago".
    public let now: Date
    /// Its folder is being measured again after a cleanup touched it: the size shows "Measuring…".
    public let isMeasuringSize: Bool

    public init(
        assessment: WorktreeAssessment,
        scanOrder: Int,
        dependencies: DependencySize = .notMeasured,
        lastCommit: CommitSummary? = nil,
        remotes: [GitRemote] = [],
        home: URL? = nil,
        now: Date = Date(),
        isMeasuringSize: Bool = false
    ) {
        self.assessment = assessment
        self.scanOrder = scanOrder
        self.dependencies = dependencies
        self.lastCommit = lastCommit
        self.remotes = remotes
        let worktree = assessment.worktree
        self.folderText = home.map { TildePath.abbreviate(worktree.path, home: $0) } ?? worktree.path
        self.repoFolderText = home.map { TildePath.abbreviate(worktree.repoPath, home: $0) } ?? worktree.repoPath
        self.now = now
        self.isMeasuringSize = isMeasuringSize
    }

    /// Repo and path together: two repos can list the same folder (one repo's stale record and another
    /// repo's real worktree), and they must stay two rows.
    public struct ID: Hashable, Sendable {
        public var repoPath: String
        public var path: String

        public init(_ worktree: Worktree) {
            repoPath = worktree.repoPath
            path = worktree.path
        }

        public init(repoPath: String, path: String) {
            self.repoPath = repoPath
            self.path = path
        }
    }

    public var id: ID { ID(worktree) }
    public var worktree: Worktree { assessment.worktree }
    public var path: String { worktree.path }
    public var url: URL { worktree.url }

    public var repoName: String { DisplayText.repoName(worktree.repoPath) }
    public var branchText: String { DisplayText.branch(of: worktree) }
    public var kind: WorktreeKind { worktree.kind }
    public var kindText: String { worktree.kind.rawValue }
    public var sizeBytes: Int64? { assessment.estimatedBytes }
    public var sizeText: String { DisplayText.bytes(sizeBytes) }
    public var dependencyBytes: Int64? { dependencies.bytes }
    /// "–" when not measured yet, measuring, or nothing to clean; the view draws a spinner while measuring.
    public var dependencyText: String { DisplayText.bytes(dependencyBytes) }
    public var idleDays: Int? { assessment.idle.idleDays }
    public var idleText: String { DisplayText.idle(assessment) }
    /// The last-activity column: "45 days ago".
    public var activityText: String { DisplayText.activity(assessment) }

    /// The second line of a row: the folder inside the repo (".claude/worktrees/tidy-otter"), else with "~".
    public var locationText: String {
        // git and the folder walk can name the same folder through /private/var and /var.
        func plain(_ path: String) -> String { path.hasPrefix("/private/") ? String(path.dropFirst(8)) : path }
        let path = plain(worktree.path)
        let repo = plain(worktree.repoPath).hasSuffix("/") ? plain(worktree.repoPath) : plain(worktree.repoPath) + "/"
        return path.hasPrefix(repo) ? String(path.dropFirst(repo.count)) : folderText
    }

    public var status: WorktreeStatus { assessment.status }
    /// Exactly what `clean-claude scan` prints in its STATUS column.
    public var statusLabel: String { status.label }

    public var tone: Tone {
        switch status {
        case .autoReady: .autoReady
        case .safe: .safe
        case .blocked: .blocked
        case .inUse: .inUse
        }
    }

    /// The status chip, in the app's words (PLAN §8.4).
    public var chip: StatusWords { WorktreeStatusText.chip(for: assessment) }
    /// Under "Needs attention": the orange chips.
    public var needsAttention: Bool { WorktreeStatusText.needsAttention(assessment) }
    /// The quiet notes next to the chip ("1 commit not pushed · Claude session"); nil without any.
    public var notesText: String? {
        let notes = WorktreeStatusText.notes(for: assessment)
        return notes.isEmpty ? nil : notes.joined(separator: " · ")
    }
    /// The status in one plain sentence, and the one action that does the job or fixes what stops it.
    public var explanation: String { WorktreeStatusText.explanation(for: assessment) }
    public var fix: WorktreeFix { WorktreeStatusText.fix(for: assessment) }

    /// The processes that have their working folder inside.
    public var processes: [ProcessCwdIndex.Entry] {
        assessment.safety.blockers.flatMap { reason -> [ProcessCwdIndex.Entry] in
            if case .inUse(let entries) = reason { return entries }
            return []
        }
    }

    /// Every reason, as P2 words them: blockers first, then notes.
    public var reasons: [SafetyReason] { assessment.safety.blockers + assessment.safety.notes }

    /// For the chip's tooltip: one line per reason, in the app's words.
    public var reasonsHelp: String {
        guard !reasons.isEmpty else { return explanation }
        return reasons.map { "\(WorktreeStatusText.words(for: $0).text): \(WorktreeStatusText.sentence(for: $0))" }
            .joined(separator: "\n")
    }

    public var canRemove: Bool { assessment.safety.manualAllowed }
    /// Blocked, and every blocker is one Remove anyway (PLAN §4.8) can list exactly: the details panel offers it.
    public var offersRemoveAnyway: Bool { assessment.removeAnyway.lossList != nil }
    /// For a blocked row that holds something Remove anyway could list, but also a blocker it never overrides:
    /// "Remove anyway isn't available: <what to do instead>". nil otherwise (its explanation already says it).
    public var removeAnywayUnavailableText: String? {
        guard case .unavailable(let reason) = assessment.removeAnyway else { return nil }
        let overridable = assessment.safety.blockers.contains { RemoveAnyway.isOverridable($0, isBlocker: true) }
        guard overridable else { return nil }
        return "Remove anyway isn't available: " + RemoveAnywayText.instead(for: reason)
    }
    /// git still lists it but its folder is gone: `git worktree prune` clears the record.
    public var isMissingFolder: Bool { assessment.safety.blockers.contains(.missingFolder) }
    /// git's record belongs to another repo's folder: nothing is read from, or done to, that folder as this row.
    public var isStaleRecord: Bool { staleRecordReason != nil }
    public var staleRecordReason: SafetyReason? {
        assessment.safety.blockers.first { if case .staleRecord = $0 { true } else { false } }
    }
    /// Reveal in Finder and Open in Terminal only for a real folder (not a file, not a symlink).
    public var isOpenableFolder: Bool { FolderCheck.isRealDirectory(url) }

    // MARK: - Sort keys (unknown values sort first)

    public var sizeSortKey: Int64 { sizeBytes ?? -1 }
    public var dependencySortKey: Int64 { dependencyBytes ?? -1 }
    public var idleSortKey: Int { idleDays ?? -1 }
    public var statusSortKey: Int {
        switch tone {
        case .autoReady: 0
        case .safe: 1
        case .inUse: 2
        case .blocked: 3
        }
    }
}
