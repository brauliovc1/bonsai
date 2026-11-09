import CleanCore
import Foundation

/// Sizes after a cleanup (PLAN §8.5): the checkouts a cleanup touched are measured again at once, just those,
/// and removed worktrees leave the rows at once, so no row shows what a cleanup already freed while the next
/// full scan runs (minutes on a Mac with many worktrees).
extension AppModel {
    /// Measures these checkouts' folders again with `du` (as the scan does) and puts the new sizes into the scan
    /// and the verdicts, so every screen and the totals read them. Their rows show "Measuring…" meanwhile. A main
    /// checkout's size leaves out the linked worktrees inside it, as in the scan.
    public func remeasureSizes(of worktrees: [Worktree]) async {
        let known = Set(assessments.map(\.worktree.path))
        let targets = Self.unique(worktrees.filter { known.contains($0.path) })
        guard !targets.isEmpty, let du = environment.tools.du else { return }
        let paths = Set(targets.map(\.path))
        measuringSizes.formUnion(paths)
        defer { measuringSizes.subtract(paths) }
        let measured = await DirectorySizer(du: du).sizes(of: targets.map(\.url)).sizes
        applySizes(measured, measuredPaths: paths)
    }

    /// Writes measured sizes into the scan and the verdicts as they are now (a scan may have ended meanwhile; its
    /// rows get the newer number too). A folder that is gone gets no size.
    private func applySizes(_ measured: [String: Int64], measuredPaths: Set<String>) {
        let worktrees = assessments.map(\.worktree)
        var sizes = scan?.sizes ?? [:]
        for path in measuredPaths {
            guard var bytes = measured[path] else {
                sizes[path] = nil
                continue
            }
            if let main = worktrees.first(where: { $0.path == path && $0.isMain }) {
                let nested = worktrees.filter { !$0.isMain && CanonicalPath.isInside($0.url, directory: main.url) }
                bytes = max(0, bytes - nested.compactMap { sizes[$0.path] }.reduce(0, +))
            }
            sizes[path] = bytes
        }
        scan?.sizes = sizes
        for index in assessments.indices where measuredPaths.contains(assessments[index].worktree.path) {
            assessments[index].estimatedBytes = sizes[assessments[index].worktree.path]
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
        let gone = Set(removed.map { WorktreeKey(repoPath: $0.repoPath, path: $0.path) })
        func isGone(_ worktree: Worktree) -> Bool {
            gone.contains(WorktreeKey(repoPath: worktree.repoPath, path: worktree.path))
        }
        assessments.removeAll { isGone($0.worktree) }
        scan?.worktrees.removeAll(where: isGone)
    }

    private struct WorktreeKey: Hashable {
        var repoPath: String
        var path: String
    }

    private static func unique(_ worktrees: [Worktree]) -> [Worktree] {
        var seen: Set<String> = []
        return worktrees.filter { seen.insert($0.path).inserted }
    }
}
