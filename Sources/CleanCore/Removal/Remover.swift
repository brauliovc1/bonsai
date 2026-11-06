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

    public func remove(_ worktree: Worktree, mode: RemovalMode, estimatedBytes: Int64?) async throws -> RemovalResult {
        let (fresh, siblings) = try await reread(worktree, mode: mode)
        let assessment = await assessor.assess(fresh, knownWorktrees: siblings, cwdIndex: await captureCwdIndex())
        let safety = assessment.safety
        let allowed = mode == .manual ? safety.manualAllowed : safety.autoEligible
        guard allowed else { throw RemovalError.refused(mode: mode, report: safety) }

        let volumeFolder = fresh.url.deletingLastPathComponent()
        let freeBefore = Self.availableCapacity(at: volumeFolder)

        await beforeGitRemove()
        do {
            try await git.git(["worktree", "remove", fresh.path], in: fresh.repoURL)
        } catch let error as GitError {
            throw RemovalError.gitFailed(stderr: error.timedOut ? "git timed out" : error.stderr)
        }

        var warnings: [String] = []
        if Self.itemExists(at: fresh.path) {
            warnings.append("git reported success but \(fresh.path) still exists")
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
