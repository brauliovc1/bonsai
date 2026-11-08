import CleanCore
import Foundation
import Observation

/// The Xcode DerivedData screen: the folders of the located root with their state, and "Delete orphaned…".
/// Any row can be selected (arrow keys move through read-only rows like through the others), but only
/// orphaned ones count toward "Delete orphaned…". The root is the one `DerivedDataLocator` finds; the app
/// has no custom-location input. Deleting goes only through `DerivedDataCleaner`, after a fresh scan, and
/// only for the orphans the sheet listed (`DerivedDataModel+Delete`).
@MainActor
@Observable
public final class DerivedDataModel {
    public let app: AppModel
    /// How `defaults` is run (tests pass a scripted runner).
    @ObservationIgnored let runner: CommandRunner
    @ObservationIgnored private let loop = ScanLoop()

    public private(set) var report: DerivedDataReport?
    public private(set) var isScanning = false
    public private(set) var lastScanAt: Date?
    public var sortOrder = [KeyPathComparator(\DerivedDataRow.sizeSortKey, order: .reverse)]
    /// The selected rows, read-only ones included; see `selectedOrphans`.
    public var selection: Set<DerivedDataRow.ID> = []

    // Delete sheet (DerivedDataModel+Delete).
    public var isShowingDeleteSheet = false
    public internal(set) var isPreparingDelete = false
    public internal(set) var confirmation: DerivedDataConfirmation?
    public internal(set) var isDeleting = false
    public internal(set) var deletesDone = 0
    public internal(set) var cleanupReport: DerivedDataCleanupReport?
    @ObservationIgnored var deleteSheetToken = 0

    public init(app: AppModel, runner: CommandRunner = .live) {
        self.app = app
        self.runner = runner
    }

    // MARK: - Rows

    public var allRows: [DerivedDataRow] {
        (report?.entries ?? []).map(DerivedDataRow.init)
    }

    public var rows: [DerivedDataRow] {
        allRows.sorted(using: sortOrder + [KeyPathComparator(\DerivedDataRow.name)])
    }

    public var selectableIDs: Set<DerivedDataRow.ID> {
        Set(allRows.filter(\.isSelectable).map(\.id))
    }

    public var selectedRows: [DerivedDataRow] { rows.filter { selection.contains($0.id) } }
    /// The selected rows "Delete orphaned…" is about: the orphaned ones.
    public var selectedOrphans: [DerivedDataRow] { selectedRows.filter(\.isSelectable) }

    public var orphanRows: [DerivedDataRow] { allRows.filter(\.isSelectable) }
    public var orphanBytes: Int64 { orphanRows.compactMap(\.bytes).reduce(0, +) }
    public var totalBytes: Int64 { report?.totalBytes ?? 0 }

    /// A refused root (`/`, the home folder, a folder above it, not a folder): shown as an error, and
    /// nothing can be deleted.
    public var refusal: String? { report?.refusal }
    public var root: String? { report?.root }
    public var warnings: [String] { report?.warnings ?? [] }
    /// Xcode has no DerivedData folder yet (or it is gone).
    public var rootMissing: Bool { report.map { !$0.rootExists && $0.refusal == nil } ?? false }
    /// "Delete orphaned…" is offered when the root is accepted and an orphaned row is selected.
    public var canDelete: Bool { refusal == nil && !selectedOrphans.isEmpty && !app.isCleaningUp }

    // MARK: - Scanning

    /// Scans the root now, or once more after the running scan; returns when that scan is done.
    public func refresh() async {
        await loop.run { [self] in
            isScanning = true
            report = await DerivedDataScanner.scan(environment: app.environment, runner: runner)
            selection.formIntersection(allRows.map(\.id))
            lastScanAt = app.environment.now()
            isScanning = false
        }
    }

    /// The first scan, when the screen first appears.
    public func loadIfNeeded() async {
        if report == nil { await refresh() }
    }
}
