import CleanCore
import Foundation

/// Sizes after a cleanup (PLAN §8.5): the checkouts a cleanup touched are measured again at once, just those,
/// and removed worktrees leave the rows at once, so no row shows what a cleanup already freed while the next
/// full scan runs (minutes on a Mac with many worktrees). A scan that was already running when the cleanup
/// happened ends with these applied again (`CleanupFacts`), so it can't bring the old numbers back.
extension AppModel {
    /// After a cleanup touched these checkouts: their rows show "Measuring…" from now (also while the screens'
    /// observers look at them) until their folders are measured again.
    func measureAgain(_ touched: [Worktree]) async {
        let paths = Set(touched.map(\.path))
        measuringSizes.formUnion(paths)
        defer { measuringSizes.subtract(paths) }
        for observer in checkoutObservers { await observer(paths) }
        await remeasureSizes(of: touched)
    }

    /// Measures these checkouts' folders again with `du` (as the scan does) and puts the new sizes into the scan
    /// and the verdicts, so every screen and the totals read them. Their rows show "Measuring…" meanwhile. A main
    /// checkout's size leaves out the linked worktrees inside it, as in the scan.
    public func remeasureSizes(of worktrees: [Worktree]) async {
        let known = Set(assessments.map(\.worktree.path))
        let targets = Self.unique(worktrees.filter { known.contains($0.path) })
        guard !targets.isEmpty, let du = environment.tools.du else { return }
        let generation = scanGeneration
        let paths = Set(targets.map(\.path))
        measuringSizes.formUnion(paths)
        defer { measuringSizes.subtract(paths) }
        let measured = await DirectorySizer(du: du).sizes(of: targets.map(\.url)).sizes
        let sizes = Self.sizes(measured: measured, paths: targets.map(\.path), before: scan?.sizes ?? [:],
                               worktrees: assessments.map(\.worktree))
        cleanupFacts.measured(sizes, generation: generation)
        apply(sizes)
    }

    /// The new size of each path in `paths`: what `du` measured (nil when the folder is gone), for a main checkout
    /// minus the linked worktrees inside it, at their new size when they were measured too, else at their size
    /// from `before`. It reads only `measured` and `before`, so the order of `paths` doesn't matter.
    nonisolated static func sizes(
        measured: [String: Int64],
        paths: [String],
        before: [String: Int64],
        worktrees: [Worktree]
    ) -> [String: Int64?] {
        let measuredPaths = Set(paths)
        var result: [String: Int64?] = [:]
        for path in paths {
            guard let bytes = measured[path] else {
                result[path] = .some(nil)
                continue
            }
            guard let main = worktrees.first(where: { $0.path == path && $0.isMain }) else {
                result[path] = bytes
                continue
            }
            let nested = worktrees.filter { !$0.isMain && CanonicalPath.isInside($0.url, directory: main.url) }
            let nestedBytes = nested.compactMap { measuredPaths.contains($0.path) ? measured[$0.path] : before[$0.path] }
            result[path] = max(0, bytes - nestedBytes.reduce(0, +))
        }
        return result
    }

    /// Writes sizes into the scan and the verdicts as they are now (a scan may have ended meanwhile).
    private func apply(_ sizes: [String: Int64?]) {
        guard !sizes.isEmpty else { return }
        for (path, bytes) in sizes { scan?.sizes[path] = bytes }
        for index in assessments.indices {
            if let bytes = sizes[assessments[index].worktree.path] { assessments[index].estimatedBytes = bytes }
        }
    }

    /// Runs `action` with the paths of the checkouts a cleanup changed (after a clean of their dependency
    /// folders), so a screen that keeps its own sizes of them measures again.
    public func whenCheckoutsChange(_ action: @escaping @MainActor (Set<String>) async -> Void) {
        checkoutObservers.append(action)
    }

    /// Takes worktrees a removal took away out of the scan and the verdicts (matched by repo and folder).
    func forget(_ removed: [Worktree]) {
        guard !removed.isEmpty else { return }
        cleanupFacts.removed(removed, generation: scanGeneration)
        drop(Set(removed.map(CleanupFacts.Key.init)))
    }

    private func drop(_ gone: Set<CleanupFacts.Key>) {
        guard !gone.isEmpty else { return }
        assessments.removeAll { gone.contains(CleanupFacts.Key($0.worktree)) }
        scan?.worktrees.removeAll { gone.contains(CleanupFacts.Key($0)) }
    }

    /// A scan of `generation` has just set the scan and the verdicts: what cleanups found out while it (or an
    /// earlier scan) ran is applied again, the rest is forgotten. A size applied again may itself be out of date
    /// (the folder could have grown again since, and this scan may have measured that), so one more scan is
    /// asked for: it begins later, keeps none of these facts, and so asks for nothing more.
    func scanFinished(generation: Int) {
        cleanupFacts.keepUnseen(byScan: generation)
        drop(Set(cleanupFacts.removed.keys))
        guard !cleanupFacts.sizes.isEmpty else { return }
        apply(cleanupFacts.sizes.mapValues(\.bytes))
        requestRefresh()
    }

    private static func unique(_ worktrees: [Worktree]) -> [Worktree] {
        var seen: Set<String> = []
        return worktrees.filter { seen.insert($0.path).inserted }
    }
}
