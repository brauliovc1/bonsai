import CleanCore
import Foundation
import Observation

/// The Tool caches screen (PLAN §4.6): package-manager caches and Cursor's data, by section, with sizes and
/// whether each can be cleaned now. Only ready rows count toward "Clean selected…". Cleaning goes only through
/// `ToolCacheCleaner`, after a fresh scan, for the entries the sheet listed, inside the app's cleanup guard and
/// `cleanup.lock` (`CachesModel+Clean`).
@MainActor
@Observable
public final class CachesModel {
    /// The line at the top of the Cursor section while Cursor runs.
    public static let cursorRunningLine = "Quit Cursor to clean its data."

    public let app: AppModel
    /// Where process lists come from: ps, plus NSWorkspace for Cursor in the app; scripted in tests.
    @ObservationIgnored let processes: ProcessSource
    @ObservationIgnored private let loop = ScanLoop()

    public internal(set) var report: ToolCacheReport?
    public private(set) var isScanning = false
    public private(set) var lastScanAt: Date?
    /// The selected rows' ids; only ready rows can be selected (`setSelected`).
    public var selection: Set<CacheRow.ID> = []

    // Clean sheet (CachesModel+Clean).
    public var isShowingCleanSheet = false
    public internal(set) var isPreparingClean = false
    public internal(set) var confirmation: CachesConfirmation?
    public internal(set) var isCleaning = false
    public internal(set) var cleanReport: CachesCleanReport?
    @ObservationIgnored var sheetToken = 0

    public init(app: AppModel, processes: ProcessSource = .live()) {
        self.app = app
        self.processes = processes
    }

    // MARK: - Rows

    public var allRows: [CacheRow] {
        (report?.findings ?? []).map { CacheRow(finding: $0, home: app.environment.homeDirectory) }
    }

    /// One section's rows in catalog order: for Cursor, the cleanable entries before the display-only ones.
    public func rows(in section: ToolCacheEntry.Section) -> [CacheRow] {
        allRows.filter { $0.finding.entry.section == section }
    }

    public var readyRows: [CacheRow] { allRows.filter(\.isSelectable) }
    public var readyBytes: Int64 { readyRows.compactMap(\.bytes).reduce(0, +) }
    public var totalBytes: Int64 { allRows.compactMap(\.bytes).reduce(0, +) }

    /// The selected rows that can be cleaned.
    public var selectedRows: [CacheRow] { readyRows.filter { selection.contains($0.id) } }
    public var selectedBytes: Int64 { selectedRows.compactMap(\.bytes).reduce(0, +) }
    public var canClean: Bool { !selectedRows.isEmpty && !app.isCleaningUp && !isCleaning }

    /// "Quit Cursor to clean its data." while Cursor runs; nil otherwise.
    public var cursorRunningLine: String? { report?.cursorRunning == true ? Self.cursorRunningLine : nil }
    public var warnings: [String] { report?.warnings ?? [] }

    public func isSelected(_ id: CacheRow.ID) -> Bool {
        selection.contains(id)
    }

    /// Selects or deselects one row; a row that can't be cleaned is never selected.
    public func setSelected(_ id: CacheRow.ID, _ selected: Bool) {
        if selected, readyRows.contains(where: { $0.id == id }) {
            selection.insert(id)
        } else {
            selection.remove(id)
        }
    }

    public func selectAllReady() {
        selection = Set(readyRows.map(\.id))
    }

    // MARK: - Scanning

    /// Scans now, or once more after the running scan; returns when that scan is done.
    public func refresh() async {
        await loop.run { [self] in
            isScanning = true
            show(await scanner.scan())
            isScanning = false
        }
    }

    /// The first scan, when the screen (or the Overview) first appears.
    public func loadIfNeeded() async {
        if report == nil { await refresh() }
    }

    var scanner: ToolCacheScanner {
        ToolCacheScanner(environment: app.environment, processes: processes)
    }

    /// Shows a scan's report; a selected row that is no longer ready drops out of the selection.
    func show(_ fresh: ToolCacheReport) {
        report = fresh
        selection.formIntersection(fresh.ready.map(\.id))
        lastScanAt = app.environment.now()
    }
}
