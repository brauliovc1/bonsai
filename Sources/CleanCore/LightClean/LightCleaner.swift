import Foundation

/// Deletes light-clean candidates (PLAN §4.2). Manual only: auto mode never calls this.
///
/// Right before each folder is deleted, every condition the finder checked is checked again (name, ignored,
/// tracks nothing, not a symlink, no other checkout inside), and then, last, a fresh process index: a
/// process with its working folder anywhere in the worktree stops the clean. `FileManager.removeItem`
/// deletes symlinks inside a folder without following them. One `lightClean` log entry lists what was
/// deleted and what was refused. Nothing here can be restored.
public struct LightCleaner: Sendable {
    public var git: Git
    public var log: RemovalLog
    public var nestedSearch: NestedCheckoutSearch
    public var cursorWorktreesDirectory: URL
    public var now: @Sendable () -> Date
    /// A fresh process index for each folder (lsof by default).
    public var captureCwdIndex: @Sendable () async -> ProcessCwdIndex
    /// Test seam: the free space of the worktree's volume (default: read from the volume).
    var freeSpace: FreeSpaceProbe?
    /// Test seam: runs after a candidate's re-check, before the process index is taken.
    var afterRecheck: @Sendable (LightCleanCandidate) async -> Void = { _ in }

    public init(git: Git, environment: CleanEnvironment) {
        self.git = git
        self.log = RemovalLog(environment: environment)
        self.nestedSearch = NestedCheckoutSearch()
        self.cursorWorktreesDirectory = environment.cursorWorktreesDirectory
        self.now = environment.now
        let lsof = environment.tools.lsof
        self.captureCwdIndex = { await ProcessCwdIndex.capture(lsof: lsof) }
    }

    /// Deletes the candidates that still pass. Throws, deleting nothing, when the worktree is gone or no
    /// longer registered, or when a process is inside before the first folder goes. A process found later
    /// stops the clean there: the rest are refused and what was deleted is logged.
    ///
    /// `knownWorktrees`: every registered worktree of every scanned repo (the caller's scan); a fresh
    /// listing of this worktree's own repo is added.
    public func clean(
        _ worktree: Worktree,
        candidates: [LightCleanCandidate],
        knownWorktrees: [Worktree] = []
    ) async throws -> LightCleanResult {
        let (fresh, siblings) = try await reread(worktree)
        var result = LightCleanResult(worktree: fresh, deleted: [], refused: [], failed: [], entry: nil, warnings: [], logged: true)
        let queue = candidates.uniqued()
        guard !queue.isEmpty else { return result }

        let check = LightCleanCheck(git: git, nestedSearch: nestedSearch)
        let known = knownWorktrees + siblings
        let probe = freeSpace ?? .volume(containing: fresh.url)
        let before = probe.availableBytes()

        for (position, candidate) in queue.enumerated() {
            if let why = Self.foreignReason(candidate, in: fresh) {
                result.refused.append(Self.skip(candidate, .notACandidate(why)))
                continue
            }
            let verdict = await check.verdict(for: candidate.relativePath, in: fresh.url, knownWorktrees: known)
            if let reason = verdict.reason {
                result.refused.append(Self.skip(candidate, reason))
                continue
            }
            await afterRecheck(candidate)
            if let reason = Self.inUseReason(await captureCwdIndex(), worktree: fresh.url) {
                if result.deleted.isEmpty && result.failed.isEmpty { throw Self.error(for: reason) }
                result.refused += queue[position...].map { Self.skip($0, reason) }
                break
            }
            let current = LightCleanCandidate(
                worktreePath: candidate.worktreePath,
                relativePath: candidate.relativePath,
                name: candidate.name,
                estimatedBytes: candidate.estimatedBytes,
                packageClones: verdict.packageClones
            )
            do {
                try FileManager.default.removeItem(at: fresh.url.appending(path: candidate.relativePath, directoryHint: .isDirectory))
                result.deleted.append(current)
            } catch {
                result.failed.append(LightCleanResult.Failure(candidate: current, message: error.localizedDescription))
            }
        }
        guard !result.deleted.isEmpty || !result.failed.isEmpty else { return result }

        let after = probe.availableBytes()
        let estimates = result.deleted.compactMap(\.estimatedBytes)
        let entry = RemovalLogEntry(
            date: now(),
            mode: .manual,
            action: .lightClean,
            repoPath: fresh.repoPath,
            path: fresh.path,
            branch: fresh.branch,
            headSha: fresh.head,
            kind: fresh.kind,
            estimatedBytes: estimates.isEmpty ? nil : estimates.reduce(0, +),
            freedBytes: before.flatMap { before in after.map { max(0, $0 - before) } },
            notes: Self.logNotes(result)
        )
        result.entry = entry
        do {
            try log.append(entry)
        } catch {
            result.logged = false
            result.warnings.append("the light clean was not logged: \(error)")
        }
        return result
    }

    /// One line per folder: deleted, refused (with the reason) or failed.
    static func logNotes(_ result: LightCleanResult) -> [String] {
        let deleted = result.deleted.map { candidate in
            "deleted \(candidate.relativePath)"
                + (candidate.packageClones.isEmpty ? "" : " (package clones: \(candidate.packageClones.joined(separator: ", ")))")
        }
        let refused = result.refused.map { "refused \($0.relativePath): \($0.reason.sentence)" }
        let failed = result.failed.map { "failed \($0.candidate.relativePath): \($0.message)" }
        return deleted + refused + failed
    }

    /// Why a candidate does not belong to this worktree's light clean, or nil when it does.
    static func foreignReason(_ candidate: LightCleanCandidate, in worktree: Worktree) -> String? {
        guard CanonicalPath.same(URL(fileURLWithPath: candidate.worktreePath), worktree.url) else {
            return "it was found in \(candidate.worktreePath)"
        }
        let parts = candidate.relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard (1...LightCleanWalk.maxDepth).contains(parts.count),
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0 == ".git" })
        else { return "\(candidate.relativePath) is not a folder 1 to \(LightCleanWalk.maxDepth) levels down" }
        guard parts.last.map(String.init) == candidate.name, RegenerableNames.isRegenerableFolder(candidate.name) else {
            return "\(candidate.name) is not a regenerable folder name"
        }
        return nil
    }

    /// What stops a clean of `worktree` under this process index: a process inside, or no index at all.
    public static func inUseReason(_ index: ProcessCwdIndex, worktree: URL) -> LightCleanSkipReason? {
        guard index.isAvailable else { return .inUseUnknown(index.failure ?? "lsof unavailable") }
        let processes = index.processes(inside: worktree)
        return processes.isEmpty ? nil : .inUse(processes)
    }

    private static func error(for reason: LightCleanSkipReason) -> LightCleanError {
        switch reason {
        case .inUse(let processes): .inUse(processes)
        case .inUseUnknown(let why): .inUseUnknown(why)
        default: .unavailable(reason.sentence)
        }
    }

    private static func skip(_ candidate: LightCleanCandidate, _ reason: LightCleanSkipReason) -> LightCleanSkip {
        LightCleanSkip(relativePath: candidate.relativePath, name: candidate.name, reason: reason)
    }

    /// The worktree's record as git lists it now, plus the repo's other worktrees.
    private func reread(_ worktree: Worktree) async throws -> (Worktree, [Worktree]) {
        let listing: [Worktree]
        do {
            listing = try await WorktreeScanner(git: git, cursorWorktreesDirectory: cursorWorktreesDirectory)
                .worktrees(in: worktree.repoURL)
        } catch {
            throw LightCleanError.unavailable("its repo could not be listed: \(error)")
        }
        guard let fresh = listing.first(where: { CanonicalPath.same($0.url, worktree.url) }) else {
            throw LightCleanError.notRegistered(path: worktree.path)
        }
        if fresh.isBare { throw LightCleanError.unavailable("a bare repo has no working folder") }
        if fresh.isPrunable || DirectoryEntries.kind(ofItemAt: fresh.path) != .directory {
            throw LightCleanError.unavailable("the folder is missing")
        }
        return (fresh, listing)
    }
}
