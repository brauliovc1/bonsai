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
    /// The cleanup running is an auto-mode run (from its fresh scan to its last removal).
    public private(set) var isAutoRunning = false
    /// Quit was asked for: running cleanups stop before their next item, new ones don't start.
    public private(set) var isQuitting = false
    /// Why the last cleanup that didn't start was refused, when it wasn't this app's own cleanup.
    private var lastRefusal: String?

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
    /// running when the cleanup ended). `rescanWorktrees: false` for a cleanup that doesn't touch
    /// worktrees (DerivedData, Docker, Simulators): the log and the free space are re-read, nothing is scanned.
    public func cleanupFinished(rescanWorktrees: Bool = true) async {
        reloadLog()
        disk.refresh()
        if rescanWorktrees { await refresh() }
    }

    /// Re-reads `settings.json` after a settings screen saved it, without scanning. A file that can't be
    /// read leaves the settings as they were (the next scan reports it).
    public func reloadSettings() {
        if let loaded = try? SettingsStore(environment: environment).load() { settings = loaded }
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

    /// Why a cleanup can't start now, for refusals: "Auto mode is running" while an auto-mode run holds the
    /// guard, "another cleanup is still running" for this app's own, and `CleanupLock.busyMessage` when
    /// another app instance or the CLI holds `cleanup.lock`.
    public var busyReason: String {
        if isAutoRunning { return "Auto mode is running" }
        if isCleaningUp { return "another cleanup is still running" }
        return lastRefusal ?? "another cleanup is still running"
    }

    /// `busyReason` as a sentence of its own.
    public var busySentence: String {
        busyReason.prefix(1).uppercased() + busyReason.dropFirst() + "."
    }

    /// Runs `body` holding the in-app guard and `cleanup.lock` (across processes, PLAN §3), or returns nil
    /// without running it when another cleanup holds either, or the app is quitting. `byAutoMode`: the body
    /// is an auto-mode run, so refusals say "Auto mode is running".
    func cleaningUp<T>(byAutoMode: Bool = false, _ body: () async -> T) async -> T? {
        guard !isCleaningUp else { return nil }
        guard !isQuitting else {
            lastRefusal = "the app is quitting"
            return nil
        }
        let lock: FileLock
        do {
            guard let taken = try CleanupLock.tryAcquire(environment: environment) else {
                lastRefusal = CleanupLock.busyMessage
                return nil
            }
            lock = taken
        } catch {
            lastRefusal = "the cleanup lock can't be taken: \(error)"
            return nil
        }
        lastRefusal = nil
        isCleaningUp = true
        isAutoRunning = byAutoMode
        defer {
            lock.release()
            isCleaningUp = false
            isAutoRunning = false
        }
        return await body()
    }

    /// Quit asked for: running cleanups stop before their next item, nothing new starts. Returns once no
    /// cleanup runs, so the removal in progress finishes and logs first.
    public func prepareToQuit() async {
        isQuitting = true
        while isCleaningUp {
            try? await Task.sleep(for: .milliseconds(50), tolerance: nil, clock: SuspendingClock())
        }
    }
}
