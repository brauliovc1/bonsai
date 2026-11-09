import CleanCore
import Foundation
import Observation

/// The Worktrees screen: rows from the shared scan grouped by repo (`WorktreesModel+Groups`), sorting,
/// filters, selection, the details panel (`details`), the Deps column (`WorktreesModel+Dependencies`), and
/// the remove, prune and light-clean flows (`WorktreesModel+Remove`, `+Prune`, `+LightClean`). Removal goes
/// only through `Remover` (manual mode), prune only through `Pruner`, light clean only through `LightCleaner`.
@MainActor
@Observable
public final class WorktreesModel {
    /// The `--status` groups of `clean-claude scan` (IN USE counts as blocked).
    public enum StatusFilter: String, CaseIterable, Sendable, Identifiable {
        case autoReady = "auto-ready"
        case safe
        case blocked

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .autoReady: "Auto-ready"
            case .safe: "Safe"
            case .blocked: "Blocked or in use"
            }
        }
    }

    public static let idleChoices = [7, 30, 90]

    public let app: AppModel

    public var sortOrder = [KeyPathComparator(\WorktreeRow.repoName)]
    public var kindFilter: WorktreeKind?
    public var statusFilter: StatusFilter?
    /// Only rows idle at least this many days (idle unknown is left out).
    public var minimumIdleDays: Int?
    public var searchText = ""
    /// Selecting exactly one row opens the details panel.
    public var selection: Set<WorktreeRow.ID> = [] {
        didSet {
            if selection.count == 1, selection != oldValue { isShowingDetails = true }
        }
    }
    /// Repos whose group is collapsed (by repo path).
    public internal(set) var collapsedRepos: Set<String> = []
    /// The details panel on the right.
    public var isShowingDetails = false
    /// What the details panel loads only when it opens: recent commits, upstream.
    public let details: WorktreeDetailsModel

    // Removal sheet (WorktreesModel+Remove).
    public var isShowingRemovalSheet = false
    /// The selected items are being looked at afresh before the sheet shows them.
    public internal(set) var isPreparingRemoval = false
    public internal(set) var confirmation: RemovalConfirmation?
    public internal(set) var isRemoving = false
    public internal(set) var removalsDone = 0
    /// Set when the confirmed removals are done; the sheet then shows it.
    public internal(set) var report: RemovalReport?
    @ObservationIgnored var removalSheetToken = 0
    /// Test seams: the volume a folder is on, and a volume's free bytes.
    @ObservationIgnored var volumeOf: (URL) -> URL? = WorktreesModel.volume(of:)
    @ObservationIgnored var freeBytes: (URL) -> Int64? = { FreeSpaceProbe.volume(containing: $0).availableBytes() }

    // Deps column (WorktreesModel+Dependencies).
    public internal(set) var dependencySizes: [WorktreeRow.ID: DependencySize] = [:]
    /// Sizes are being measured (one run at a time).
    public internal(set) var isMeasuringDependencies = false
    /// Measured, or started, at least once: the screen measures on first appearance only.
    public internal(set) var hasRequestedDependencies = false

    // Light clean sheet (WorktreesModel+LightClean).
    public var isShowingLightCleanSheet = false
    /// The selected worktrees are being looked at afresh before the sheet shows them.
    public internal(set) var isPreparingLightClean = false
    public internal(set) var lightCleanConfirmation: LightCleanConfirmation?
    public internal(set) var isLightCleaning = false
    public internal(set) var lightCleansDone = 0
    /// Set when the confirmed folders are done; the sheet then shows it.
    public internal(set) var lightCleanReport: LightCleanReport?
    @ObservationIgnored var lightCleanSheetToken = 0

    // Prune sheet (WorktreesModel+Prune).
    public var isShowingPruneSheet = false
    public internal(set) var isPreparingPrune = false
    public internal(set) var prunePlan: PrunePlan?
    public internal(set) var isPruning = false
    /// Set when a prune is done; the sheet then shows it.
    public internal(set) var pruneOutcomes: [PruneOutcome]?
    @ObservationIgnored var pruneSheetToken = 0

    public init(app: AppModel) {
        self.app = app
        self.details = WorktreeDetailsModel(git: app.git)
    }

    // MARK: - Rows

    /// Every worktree of the last scan, in scan order.
    public var allRows: [WorktreeRow] {
        let scan = app.scan
        let home = app.environment.homeDirectory
        let now = app.environment.now()
        return app.assessments.enumerated().map { order, assessment in
            let worktree = assessment.worktree
            return WorktreeRow(
                assessment: assessment,
                scanOrder: order,
                dependencies: dependencySizes[WorktreeRow.ID(worktree)] ?? .notMeasured,
                lastCommit: scan?.lastCommit(of: worktree),
                remotes: scan?.remotes(of: worktree) ?? [],
                home: home,
                now: now
            )
        }
    }

    /// The rows shown (filtered and searched), in the order the table shows them: group by group, each
    /// group sorted with the main checkout first. Rows of collapsed groups are included.
    public var rows: [WorktreeRow] {
        groups.flatMap(\.rows)
    }

    /// The shown rows that are selected.
    public var selectedRows: [WorktreeRow] {
        rows.filter { selection.contains($0.id) }
    }

    /// Shown rows whose folder is gone ("Clean up missing folders" covers their repos).
    public var missingFolderRows: [WorktreeRow] {
        rows.filter(\.isMissingFolder)
    }

    public var hasActiveFilters: Bool {
        kindFilter != nil || statusFilter != nil || minimumIdleDays != nil
    }

    public func clearFilters() {
        kindFilter = nil
        statusFilter = nil
        minimumIdleDays = nil
    }

    func matches(_ row: WorktreeRow) -> Bool {
        if let kindFilter, row.kind != kindFilter { return false }
        if let statusFilter, row.status.group != statusFilter.rawValue { return false }
        if let minimumIdleDays {
            guard let days = row.idleDays, days >= minimumIdleDays else { return false }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return row.searchableTexts.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    /// The root of the volume holding `url` (or its nearest existing parent).
    nonisolated static func volume(of url: URL) -> URL? {
        var probe = URL(fileURLWithPath: url.path, isDirectory: true)
        while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" {
            probe = probe.deletingLastPathComponent()
        }
        return (try? probe.resourceValues(forKeys: [.volumeURLKey]))?.volume
    }
}
