import Foundation

/// Deletes light-clean candidates (PLAN §4.2). Manual only: auto mode never calls this.
///
/// For each folder, in this order: every condition the finder checked is checked again (name, tracks
/// nothing, ignored, nothing in `git status`, not a symlink, no checkout with local work inside); then a
/// fresh process index: a process with its working folder anywhere in the worktree stops the clean; then,
/// right before `FileManager.removeItem`, every path component from the worktree root to the folder is
/// lstat'ed again (no symlink, and the folder is the same file the checks saw). `removeItem` deletes
/// symlinks inside a folder without following them. Each deleted folder gets its own `lightClean` log
/// entry, written right after its delete. Nothing here can be restored.
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
        self.captureCwdIndex = { await ProcessCwdIndex.capture(in: environment) }
    }

    /// Deletes the candidates that still pass. Throws, deleting nothing, when the worktree is gone or no
    /// longer registered, or when a process is inside before the first folder goes. A process found later
    /// stops the clean there: the rest are refused.
    ///
    /// `knownWorktrees`: every registered worktree of every scanned repo (the caller's scan); a fresh
    /// listing of this worktree's own repo is added.
    ///
    /// The folder must still be this repo's worktree (`SafetyCheck.identityBlocker`: its `.git` leads back to
    /// this repo), checked here and again right before each delete. `expectation`: what the person
    /// confirmed; when given, a fresh record with another repo, branch or HEAD is refused.
    public func clean(
        _ worktree: Worktree,
        candidates: [LightCleanCandidate],
        knownWorktrees: [Worktree] = [],
        expectation: LightCleanExpectation? = nil
    ) async throws -> LightCleanResult {
        let (fresh, siblings) = try await reread(worktree)
        let identity = SafetyCheck(git: git)
        if let blocker = await identity.identityBlocker(of: fresh) { throw LightCleanError.wrongFolder(blocker.sentence) }
        if let expectation {
            let changes = expectation.changes(fresh: fresh)
            guard changes.isEmpty else { throw LightCleanError.changed(path: fresh.path, changes: changes) }
        }
        var result = LightCleanResult(
            worktree: fresh, deleted: [], refused: [], failed: [], entries: [], warnings: [], freedBytes: nil, logged: true
        )
        let queue = candidates.uniqued()
        let check = LightCleanCheck(git: git, nestedSearch: nestedSearch)
        let known = knownWorktrees + siblings
        let probe = freeSpace ?? .volume(containing: fresh.url)
        var freed: [Int64?] = []

        for (position, candidate) in queue.enumerated() {
            if let why = Self.foreignReason(candidate, in: fresh) {
                result.refused.append(Self.skip(candidate, .notACandidate(why)))
                continue
            }
            let verdict: LightCleanCheck.Verdict
            do {
                let status = try await LightCleanStatus.read(git: git, worktree: fresh.url)
                verdict = await check.verdict(for: candidate.relativePath, in: fresh.url, status: status, knownWorktrees: known)
            } catch {
                result.refused.append(Self.skip(candidate, .gitError("git status failed: \(error)")))
                continue
            }
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
            if let blocker = await identity.identityBlocker(of: fresh) {
                let reason = LightCleanSkipReason.wrongFolder(blocker.sentence)
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
            let target = fresh.url.appending(path: candidate.relativePath, directoryHint: .isDirectory)
            let before = probe.availableBytes()
            // Nothing runs between this last lstat of the path and removeItem.
            if let reason = Self.changedSinceCheck(candidate.relativePath, in: fresh.path, identity: verdict.identity) {
                result.refused.append(Self.skip(candidate, reason))
                continue
            }
            var failure: String?
            do {
                try FileManager.default.removeItem(at: target)
            } catch {
                failure = error.localizedDescription
            }
            let after = probe.availableBytes()
            let bytes = before.flatMap { before in after.map { max(0, $0 - before) } }
            freed.append(bytes)
            if let failure {
                result.failed.append(LightCleanResult.Failure(candidate: current, message: failure))
            } else {
                result.deleted.append(current)
            }
            record(entry(for: current, in: fresh, failure: failure, freedBytes: bytes), in: &result)
        }
        if !freed.isEmpty, freed.allSatisfy({ $0 != nil }) {
            result.freedBytes = freed.compactMap { $0 }.reduce(0, +)
        }
        return result
    }

    /// The re-check right before `removeItem`: every component from the worktree root to the folder is
    /// still a real folder, and the folder is the same file (device and inode) the checks looked at.
    static func changedSinceCheck(_ relative: String, in root: String, identity: FileIdentity?) -> LightCleanSkipReason? {
        if let problem = LightCleanCheck.pathProblem(relative, in: root) { return problem }
        guard let identity, FileIdentity.of(root + "/" + relative) == identity else {
            return .notACandidate("it was replaced after it was checked")
        }
        return nil
    }

    /// One entry per folder: `path` is the folder, `repoPath`, branch and HEAD are the worktree's.
    private func entry(for candidate: LightCleanCandidate, in worktree: Worktree, failure: String?, freedBytes: Int64?) -> RemovalLogEntry {
        var notes = [failure.map { "failed to delete \(candidate.relativePath) from \(worktree.path): \($0)" }
            ?? "deleted \(candidate.relativePath) from \(worktree.path)"]
        if !candidate.packageClones.isEmpty {
            notes.append("package clones: " + candidate.packageClones.joined(separator: ", "))
        }
        return RemovalLogEntry(
            date: now(),
            mode: .manual,
            action: .lightClean,
            repoPath: worktree.repoPath,
            path: worktree.path + "/" + candidate.relativePath,
            branch: worktree.branch,
            headSha: worktree.head,
            kind: worktree.kind,
            estimatedBytes: candidate.estimatedBytes,
            freedBytes: freedBytes,
            notes: notes
        )
    }

    private func record(_ entry: RemovalLogEntry, in result: inout LightCleanResult) {
        result.entries.append(entry)
        do {
            try log.append(entry)
        } catch {
            result.logged = false
            result.warnings.append("\(entry.path) was not logged: \(error)")
        }
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
        case .wrongFolder(let why): .wrongFolder(why)
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
