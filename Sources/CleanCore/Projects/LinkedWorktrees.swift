import Foundation

/// The linked worktrees whose work can depend on a main checkout's light-clean folders: every linked worktree of
/// its repo wherever it lives (a sibling's or a Cursor worktree's `node_modules` can be a symlink into the main
/// checkout), and any linked worktree inside it (node resolves modules up into the main checkout's folders). A
/// main checkout counts as used while any of them is: for its idle days and for "a process works there".
public enum LinkedWorktrees {
    /// For a main checkout, those worktrees (not bare, not prunable); empty for any other checkout.
    public static func of(_ main: Worktree, in known: [Worktree]) -> [Worktree] {
        guard main.isMain else { return [] }
        var seen: Set<String> = []
        return known.filter { worktree in
            guard !worktree.isMain, !worktree.isBare, !worktree.isPrunable else { return false }
            let related = worktree.repoPath == main.repoPath || CanonicalPath.same(worktree.repoURL, main.repoURL)
                || CanonicalPath.isInside(worktree.url, directory: main.url)
            return related && seen.insert(worktree.repoPath + "\u{0}" + worktree.path).inserted
        }
    }

    /// The processes with their working folder in one of them, once per pid.
    public static func processes(of main: Worktree, in known: [Worktree], index: ProcessCwdIndex) -> [ProcessCwdIndex.Entry] {
        var pids: Set<Int32> = []
        return of(main, in: known)
            .flatMap { index.processes(inside: $0.url) }
            .filter { pids.insert($0.pid).inserted }
    }

    /// "A process works in another worktree of this repo, which may use these folders: node (pid 7) in …".
    public static func sentence(_ processes: [ProcessCwdIndex.Entry]) -> String {
        let listed = processes.prefix(5).map { "\($0.description) in \($0.cwd)" }.joined(separator: ", ")
        let more = processes.count > 5 ? " and \(processes.count - 5) more" : ""
        return "A process works in another worktree of this repo, which may use these folders: \(listed)\(more)."
    }
}
