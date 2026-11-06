import CleanCore
import Foundation
import Observation

/// The app's shared state: environment, settings, the last scan with `WorktreeAssessor`'s verdict for
/// every worktree (the same one `clean-claude scan` prints), the removal log and the disk space.
///
/// Feature models (`WorktreesModel`, `RemovalsModel`, and the ones later phases add) take an `AppModel`,
/// read from it, and call `cleanupFinished()` after they change anything on disk.
///
/// One scan at a time: a refresh asked for during a scan doesn't start a second one, it asks for exactly
/// one more scan after the running one, however often it is asked.
@MainActor
@Observable
public final class AppModel {
    public let environment: CleanEnvironment
    /// git for assessing and cleaning up; nil when none was found.
    public let git: Git?
    public let disk = DiskSpaceModel()

    public private(set) var settings = Settings()
    /// The roots of the last scan.
    public private(set) var roots: [URL] = []
    public private(set) var scan: ScanResult?
    /// One per worktree of `scan`, in scan order (each repo's main checkout first).
    public private(set) var assessments: [WorktreeAssessment] = []
    /// `removals.jsonl`, in file order.
    public private(set) var logEntries: [RemovalLogEntry] = []
    public private(set) var logError: String?
    /// Why the last scan found nothing to show: settings unreadable, git missing.
    public private(set) var problem: String?
    public private(set) var isScanning = false
    public private(set) var progress: ScanProgress?
    public private(set) var lastScanAt: Date?
    /// Scans finished since launch.
    public private(set) var scanCount = 0
    /// A removal, prune or restore is running; the others wait their turn (their buttons are disabled).
    public private(set) var isCleaningUp = false

    private var scanTask: Task<Void, Never>?
    private var rescanRequested = false

    /// `git`: tests pass the fixture's isolated git; the app uses the one the environment resolved.
    public init(environment: CleanEnvironment, git: Git? = nil) {
        self.environment = environment
        self.git = git ?? WorktreeAssessor.git(for: environment)
    }

    /// Scan issues (missing roots, unreadable folders, du failures).
    public var issues: [ScanIssue] { scan?.issues ?? [] }

    /// Estimated bytes of every SAFE and AUTO-READY worktree.
    public var reclaimableBytes: Int64 {
        assessments.reduce(0) { total, assessment in
            switch assessment.status {
            case .autoReady, .safe: total + (assessment.estimatedBytes ?? 0)
            case .blocked, .inUse: total
            }
        }
    }

    // MARK: - Scanning

    /// Scans now, or once more after the running scan; returns when that scan is done.
    public func refresh() async {
        requestRefresh()
        await scanTask?.value
    }

    /// Starts a scan, or asks for one more after the running one. Doesn't wait.
    public func requestRefresh() {
        if scanTask != nil {
            rescanRequested = true
            return
        }
        isScanning = true
        scanTask = Task { await self.runScans() }
    }

    private func runScans() async {
        repeat {
            rescanRequested = false
            await scanOnce()
        } while rescanRequested
        scanTask = nil
        isScanning = false
        progress = nil
    }

    private func scanOnce() async {
        let loaded: Settings
        do {
            loaded = try SettingsStore(environment: environment).load()
        } catch {
            // Like the CLI: a broken settings file stops everything rather than falling back to defaults.
            show(problem: "\(error)")
            return
        }
        settings = loaded
        roots = Scanner.resolveRoots(explicit: [], environment: environment, settings: loaded)
        disk.point(at: roots.first ?? environment.homeDirectory)

        let result = await Scanner(environment: environment, settings: loaded).scan { [weak self] step in
            Task { @MainActor in self?.receive(step) }
        }
        guard let git else {
            show(problem: "git not found (install the Xcode Command Line Tools or Homebrew git)")
            scan = result
            return
        }
        let verdicts = await WorktreeAssessor(git: git, settings: loaded, environment: environment).assess(result)
        scan = result
        assessments = verdicts
        problem = nil
        lastScanAt = environment.now()
        scanCount += 1
        reloadLog()
        disk.refresh()
    }

    private func receive(_ step: ScanProgress) {
        guard isScanning, step != .finished else { return }
        progress = step
    }

    private func show(problem text: String) {
        problem = text
        scan = nil
        assessments = []
        lastScanAt = environment.now()
        scanCount += 1
    }

    // MARK: - After a cleanup

    /// Re-reads the log and the free space, then scans again (always a fresh scan, also when one was
    /// running when the cleanup ended).
    public func cleanupFinished() async {
        reloadLog()
        disk.refresh()
        await refresh()
    }

    public func reloadLog() {
        let log = RemovalLog(environment: environment)
        do {
            logEntries = try log.entries()
            logError = nil
        } catch {
            logError = "cannot read \(log.fileURL.path): \(error)"
        }
    }

    /// Runs `body` unless another cleanup is running (then returns nil without running it).
    func cleaningUp<T>(_ body: () async -> T) async -> T? {
        guard !isCleaningUp else { return nil }
        isCleaningUp = true
        defer { isCleaningUp = false }
        return await body()
    }
}
