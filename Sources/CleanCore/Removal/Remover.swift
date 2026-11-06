import Foundation

/// Removes one worktree the safe way (PLAN §4.1): re-reads its state, re-runs `SafetyCheck`, then runs
/// `git -C <repo> worktree remove <path>`, never with `--force`. The branch is never deleted.
///
/// This is the only code that removes a worktree folder.
public struct Remover: Sendable {
    public var git: Git
    public var assessor: WorktreeAssessor
    public var log: RemovalLog
    public var cursorWorktreesDirectory: URL
    public var now: @Sendable () -> Date
    /// A fresh process index for the re-check (lsof by default).
    public var captureCwdIndex: @Sendable () async -> ProcessCwdIndex
    /// Test seam: runs after the git and disk checks, before the process index is taken.
    var afterInspection: @Sendable () async -> Void = {}
    /// Test seam: runs after the re-check, right before `git worktree remove`.
    var beforeGitRemove: @Sendable () async -> Void = {}

    public init(git: Git, settings: Settings, environment: CleanEnvironment) {
        self.git = git
        self.assessor = WorktreeAssessor(git: git, settings: settings, environment: environment)
        self.log = RemovalLog(environment: environment)
        self.cursorWorktreesDirectory = environment.cursorWorktreesDirectory
        self.now = environment.now
        let lsof = environment.tools.lsof
        self.captureCwdIndex = { await ProcessCwdIndex.capture(lsof: lsof) }
    }

    /// `knownWorktrees`: every registered worktree of every scanned repo (the caller's scan). They are
    /// checked for nesting together with a fresh listing of this worktree's own repo.
    ///
    /// `expectation`: what the person confirmed. When given, the removal is refused with
    /// `RemovalExpectation.Mismatch` if the fresh state differs from it in any way that matters.
    public func remove(
        _ worktree: Worktree,
        mode: RemovalMode,
        estimatedBytes: Int64?,
        knownWorktrees: [Worktree] = [],
        expectation: RemovalExpectation? = nil
    ) async throws -> RemovalResult {
        let (fresh, siblings) = try await reread(worktree, mode: mode)
        // The slow checks first; the process index last, right before git runs, so a process that moved
        // into the folder during the walks is still caught.
        let idle = fresh.isMain || fresh.isBare ? IdleReport.unknown : await assessor.idleClock.report(for: fresh)
        let state = await assessor.safetyCheck.state(of: fresh, knownWorktrees: knownWorktrees + siblings)
        await afterInspection()
        let safety = SafetyCheck.evaluate(
            worktree: fresh,
            state: state,
            idle: idle,
            settings: assessor.settings,
            cwdIndex: await captureCwdIndex()
        )
        if let expectation {
            let changes = expectation.changes(fresh: fresh, safety: safety, idle: idle)
            guard changes.isEmpty else { throw RemovalExpectation.Mismatch(path: fresh.path, changes: changes) }
        }
        let allowed = mode == .manual ? safety.manualAllowed : safety.autoEligible
        guard allowed else { throw RemovalError.refused(mode: mode, report: safety) }

        let volumeFolder = fresh.url.deletingLastPathComponent()
        let freeBefore = Self.availableCapacity(at: volumeFolder)

        await beforeGitRemove()
        let (arguments, directory) = Self.removeCommand(for: fresh)
        do {
            try await git.git(arguments, in: directory)
        } catch let error as GitError {
            throw RemovalError.gitFailed(stderr: error.timedOut ? "git timed out" : error.stderr)
        }

        var warnings: [String] = []
        if Self.itemExists(at: fresh.path) {
            warnings.append("git reported success but \(fresh.path) still exists")
        }
        if let still = try? await WorktreeScanner(git: git, cursorWorktreesDirectory: cursorWorktreesDirectory)
            .worktrees(in: fresh.repoURL), still.contains(where: { CanonicalPath.same($0.url, fresh.url) }) {
            warnings.append("git reported success but \(fresh.path) is still registered")
        }
        if let branch = fresh.branch, !(await branchExists(branch, in: fresh.repoURL)) {
            warnings.append("branch \(branch) no longer exists")
        }
        let freeAfter = Self.availableCapacity(at: volumeFolder)
        let freed = freeBefore.flatMap { before in freeAfter.map { max(0, $0 - before) } }

        var entry = RemovalLogEntry(
            date: now(),
            mode: mode,
            action: .worktreeRemove,
            repoPath: fresh.repoPath,
            path: fresh.path,
            branch: fresh.branch,
            headSha: fresh.head,
            kind: fresh.kind,
            estimatedBytes: estimatedBytes,
            freedBytes: freed,
            notes: Self.logNotes(safety) + warnings
        )
        var logged = true
        do {
            try log.append(entry)
        } catch {
            logged = false
            warnings.append("the removal was not logged: \(error)")
            entry.notes.append("not logged")
        }
        return RemovalResult(entry: entry, safety: safety, warnings: warnings, logged: logged)
    }

    /// `git -C <repo> worktree remove <path>` (PLAN §4.1). For a path with non-ASCII characters git runs
    /// inside the worktree instead and removes `.`: Foundation's `Process` hands arguments to git
    /// decomposed ("é" as "e" + U+0301), and git can't always turn them back (it gives up on paths with an
    /// emoji), so it would not find a worktree registered composed. From inside, git takes the path from
    /// `getcwd`, which returns the folder's name exactly as it is stored. git's own checks (dirty, locked,
    /// main checkout) are the same either way.
    static func removeCommand(for worktree: Worktree) -> (arguments: [String], directory: URL) {
        if worktree.path.utf8.allSatisfy({ $0 < 0x80 }) {
            return (["worktree", "remove", worktree.path], worktree.repoURL)
        }
        return (["worktree", "remove", "."], worktree.url)
    }

    /// The worktree's porcelain record as git lists it now, plus the repo's other worktrees.
    private func reread(_ worktree: Worktree, mode: RemovalMode) async throws -> (Worktree, [Worktree]) {
        let listing: [Worktree]
        do {
            listing = try await WorktreeScanner(git: git, cursorWorktreesDirectory: cursorWorktreesDirectory)
                .worktrees(in: worktree.repoURL)
        } catch {
            let report = SafetyReport(blockers: [.gitError("\(error)")], notes: [], autoBlockers: [.gitError("\(error)")])
            throw RemovalError.refused(mode: mode, report: report)
        }
        guard let fresh = listing.first(where: { CanonicalPath.same($0.url, worktree.url) }) else {
            throw RemovalError.notRegistered(path: worktree.path)
        }
        return (fresh, listing)
    }

    private func branchExists(_ branch: String, in repo: URL) async -> Bool {
        let result = try? await git.result(["rev-parse", "--verify", "--quiet", "refs/heads/\(branch)"], in: repo)
        return result?.succeeded == true
    }

    /// The notes that were accepted with this removal, in full (every ignored file, not just five).
    static func logNotes(_ safety: SafetyReport) -> [String] {
        safety.notes.map { note in
            if case .ignoredUserFiles(let paths) = note {
                return "Deleted ignored files: " + paths.joined(separator: ", ")
            }
            return note.sentence
        }
    }

    static func availableCapacity(at folder: URL) -> Int64? {
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    /// True when anything is at `path`, including a dangling symlink.
    static func itemExists(at path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)) != nil
    }
}
