import CleanCore
import Foundation
import Observation

/// The Worktrees screen (PLAN §8.4): the linked worktrees of the shared scan, grouped by repo under a header
/// that is the repo's main checkout (`WorktreesModel+Groups`), the "Can remove / Needs attention / All" filter
/// and search (`+Filter`), selection and what Remove… may do with it (`+Actions`), the details panel
/// (`details`), the dependency sizes (`+Dependencies`), and the remove, prune and clean-dependencies flows
/// (`+Remove`, `+RemoveAnyway`, `+Prune`, `+LightClean`). Removal goes only through `Remover` (manual mode), prune
/// only through `Pruner`, cleaning dependencies only through `LightCleaner`. A main checkout is never offered for
/// removal.
@MainActor
@Observable
public final class WorktreesModel {
    public let app: AppModel

    /// The order inside each group (groups stay in repo name order): biggest first.
    public var sortOrder = [KeyPathComparator(\WorktreeRow.sizeSortKey, order: .reverse)]
    /// The segmented filter; "Can remove" when the screen opens.
    public var filter: Filter = .canRemove
    public var searchText = ""
    /// Selected rows and repo headers (a header selects its main checkout's row, for the details panel; it is
    /// never part of a removal). Selecting exactly one opens the details panel.
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

    // Remove anyway sheet (WorktreesModel+RemoveAnyway, PLAN §4.8): one worktree at a time.
    public var isShowingRemoveAnywaySheet = false
    public internal(set) var isPreparingRemoveAnyway = false
    public internal(set) var removeAnywayConfirmation: RemoveAnywayConfirmation?
    /// The fresh look found it can't be removed anyway (or no longer needs to be): why, and what to do.
    public internal(set) var removeAnywayRefusal: String?
    /// The sheet's checkbox: "I understand these are deleted for good".
    public var removeAnywayUnderstood = false
    public internal(set) var isRemovingAnyway = false
    public internal(set) var removeAnywayOutcome: RemoveAnywayOutcome?
    @ObservationIgnored var removeAnywaySheetToken = 0

    // Dependency sizes (WorktreesModel+Dependencies).
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
        // Cleanups elsewhere (Project folders) change these checkouts' dependency folders too.
        app.whenCheckoutsChange { [weak self] paths in await self?.checkoutsChanged(paths) }
    }

    // MARK: - Rows

    /// Every worktree of the last scan, main checkouts included, in scan order.
    public var allRows: [WorktreeRow] {
        let scan = app.scan
        let home = app.environment.homeDirectory
        let measuring = app.measuringSizes
        // The scan's time, not the clock's: rows stay equal between scans, so the list doesn't redraw every
        // row each time it asks for them ("45 days ago" is as of the last scan).
        let now = app.lastScanAt ?? app.environment.now()
        return app.assessments.enumerated().map { order, assessment in
            let worktree = assessment.worktree
            return WorktreeRow(
                assessment: assessment,
                scanOrder: order,
                dependencies: dependencySizes[WorktreeRow.ID(worktree)] ?? .notMeasured,
                lastCommit: scan?.lastCommit(of: worktree),
                remotes: scan?.remotes(of: worktree) ?? [],
                home: home,
                now: now,
                isMeasuringSize: measuring.contains(worktree.path)
            )
        }
    }

    /// Every linked worktree of the last scan (the rows the filter chooses from).
    public var linkedRows: [WorktreeRow] { allRows.filter { !$0.worktree.isMain } }

    /// The linked worktrees shown (filtered and searched), in list order: group by group. Rows of collapsed
    /// groups are included. Never a main checkout.
    public var rows: [WorktreeRow] {
        groups.flatMap(\.rows)
    }

    /// The shown worktrees that are selected (repo headers are not among them).
    public var selectedRows: [WorktreeRow] {
        rows.filter { selection.contains($0.id) }
    }

    /// The repo headers that are selected, as their main checkouts' rows.
    public var selectedRepos: [WorktreeRow] {
        groups.compactMap(\.main).filter { selection.contains($0.id) }
    }

    /// Every worktree whose folder is gone, shown or not ("Prune missing folders…" covers their repos).
    public var missingFolderRows: [WorktreeRow] {
        linkedRows.filter(\.isMissingFolder)
    }

    /// The More menu's tooltip for Prune when there is nothing to prune; nil when there is.
    public var pruneDisabledReason: String? {
        if !missingFolderRows.isEmpty { return app.isCleaningUp ? app.busySentence : nil }
        return "No worktree's folder is missing, so there is nothing to prune."
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
