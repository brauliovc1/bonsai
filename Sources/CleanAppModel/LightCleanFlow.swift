import CleanCore
import Foundation

/// The light-clean steps the Worktrees and Project folders screens share (P6's sheet pattern): a fresh look at
/// the chosen checkouts when the sheet opens, and the deletes of exactly the folders that look listed, one
/// checkout at a time through `LightCleaner` with a `LightCleanExpectation`. The caller holds the cleanup guard.
@MainActor
struct LightCleanFlow {
    /// How many checkouts the sheet looks at together.
    static let lookConcurrency = 4

    let app: AppModel

    /// git's current record of each worktree (nil when git no longer lists it), the repos' full listings, and
    /// why a repo could not be listed.
    func freshRecords(of chosen: [Worktree], git: Git) async -> (records: [Worktree?], listings: [String: [Worktree]], failures: [String: String]) {
        let scanner = WorktreeScanner(git: git, cursorWorktreesDirectory: app.environment.cursorWorktreesDirectory)
        var listings: [String: [Worktree]] = [:]
        var failures: [String: String] = [:]
        for repo in Set(chosen.map(\.repoPath)) {
            do {
                listings[repo] = try await scanner.worktrees(in: URL(fileURLWithPath: repo, isDirectory: true))
            } catch {
                failures[repo] = "\(error)"
            }
        }
        let records: [Worktree?] = chosen.map { worktree in
            listings[worktree.repoPath]?.first { CanonicalPath.same($0.url, worktree.url) }
        }
        return (records, listings, failures)
    }

    /// One sheet item per worktree, in order, from a fresh look: git's current record of it, whether the folder
    /// is still that repo's worktree (a stale record lists nothing), a process index taken now, and
    /// `LightCleanFinder` run again. Listed folders are the ones `clean` deletes; the rest is shown with its
    /// reasons and left alone.
    func look(at chosen: [Worktree]) async -> [LightCleanConfirmation.Item] {
        guard !chosen.isEmpty else { return [] }
        guard let git = app.git else {
            return chosen.map { LightCleanConfirmation.Item(worktree: $0, findings: nil, blocker: "git not found") }
        }

        let (records, listings, failures) = await freshRecords(of: chosen, git: git)
        let known = (app.scan?.worktrees ?? []) + listings.values.flatMap { $0 }
        let index = await ProcessCwdIndex.capture(lsof: app.environment.tools.lsof)
        let finder = LightCleanFinder(git: git, du: app.environment.tools.du)
        let safety = SafetyCheck(git: git)

        // Everything the look needs is decided here; the finder runs for the worktrees that can be looked at.
        let jobs = zip(chosen, records).map { chosen, record -> (worktree: Worktree, record: Worktree?, why: String?) in
            guard let record else {
                let why = failures[chosen.repoPath].map { "git could not list the repo's worktrees: \($0)" }
                    ?? "git no longer lists it as a worktree of \(DisplayText.repoName(chosen.repoPath)); refresh the list"
                return (chosen, nil, why)
            }
            return (chosen, record, LightCleaner.inUseReason(index, worktree: record.url)?.sentence)
        }
        return await BoundedConcurrency.map(jobs, limit: Self.lookConcurrency) { job in
            guard let record = job.record else {
                return LightCleanConfirmation.Item(worktree: job.worktree, findings: nil, blocker: job.why ?? "")
            }
            if let blocker = await safety.identityBlocker(of: record) {
                return LightCleanConfirmation.Item(worktree: record, findings: nil, blocker: blocker.sentence)
            }
            let findings = await finder.candidates(in: record, knownWorktrees: known)
            return LightCleanConfirmation.Item(worktree: record, findings: findings, blocker: job.why)
        }
    }

    /// Deletes the listed folders, one worktree at a time, through `LightCleaner`, which checks each folder again
    /// right before it deletes it, and refuses a worktree that is no longer this repo's or whose branch or HEAD
    /// is not what the sheet showed. A folder that changed since the sheet listed it is refused with its reason,
    /// and nothing the sheet didn't list is touched. `onEach` runs after each worktree.
    func clean(_ items: [LightCleanConfirmation.Item], onEach: () -> Void = {}) async -> [LightCleanOutcome] {
        guard let git = app.git else {
            return items.map { LightCleanOutcome(item: $0, error: "git not found") }
        }
        let cleaner = LightCleaner(git: git, environment: app.environment)
        let known = app.scan?.worktrees ?? []
        var outcomes: [LightCleanOutcome] = []
        for item in items {
            // Quitting: the worktree in progress finishes, the rest are left alone.
            if app.isQuitting {
                outcomes.append(LightCleanOutcome(item: item, error: "the app is quitting; nothing was deleted"))
                onEach()
                continue
            }
            do {
                let result = try await cleaner.clean(
                    item.worktree,
                    candidates: item.candidates,
                    knownWorktrees: known,
                    expectation: LightCleanExpectation(worktree: item.worktree)
                )
                outcomes.append(LightCleanOutcome(item: item, result: result))
            } catch {
                outcomes.append(LightCleanOutcome(item: item, error: "\(error)"))
            }
            onEach()
        }
        return outcomes
    }
}
