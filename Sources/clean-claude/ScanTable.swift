import CleanCore
import Foundation

/// The `scan` table: REPO, BRANCH, KIND, SIZE, PATH, then a one-line summary.
struct ScanTable {
    let result: ScanResult
    let homeDirectory: URL
    let showSizes: Bool

    func render() -> String {
        let roots = result.roots.map { URL(fileURLWithPath: $0, isDirectory: true) }
        var rows: [[String]] = [header]
        for worktree in result.worktrees {
            var row = [
                worktree.repoURL.lastPathComponent,
                worktree.branch ?? (worktree.isBare ? "(bare)" : "(detached)"),
                worktree.kind.rawValue,
            ]
            if showSizes {
                row.append(result.size(of: worktree).map(ByteFormatting.string) ?? "-")
            }
            row.append(displayPath(worktree, roots: roots))
            rows.append(row)
        }
        return (alignedLines(rows) + [summary]).joined(separator: "\n")
    }

    private var header: [String] {
        showSizes ? ["REPO", "BRANCH", "KIND", "SIZE", "PATH"] : ["REPO", "BRANCH", "KIND", "PATH"]
    }

    /// Pads every column but the last; SIZE is right-aligned.
    private func alignedLines(_ rows: [[String]]) -> [String] {
        let columnCount = header.count
        let widths = (0..<columnCount).map { column in rows.map { $0[column].count }.max() ?? 0 }
        let sizeColumn = showSizes ? 3 : nil
        return rows.map { row in
            row.enumerated().map { column, cell in
                if column == columnCount - 1 { return cell }
                let padding = String(repeating: " ", count: widths[column] - cell.count)
                return column == sizeColumn ? padding + cell : cell + padding
            }.joined(separator: "  ")
        }
    }

    /// Relative to the most specific root that contains it; otherwise absolute, with `~` for the home folder.
    private func displayPath(_ worktree: Worktree, roots: [URL]) -> String {
        let relative = roots
            .compactMap { CanonicalPath.relativePath(of: worktree.url, to: $0) }
            .min { $0.count < $1.count }
        if let relative { return relative }
        if let underHome = CanonicalPath.relativePath(of: worktree.url, to: homeDirectory), underHome != "." {
            return "~/" + underHome
        }
        return worktree.path
    }

    private var summary: String {
        let linked = result.worktrees.filter { !$0.isMain }.count
        var line = "\(result.worktrees.count) worktrees (\(linked) linked) in \(result.repos.count) repos"
        if showSizes {
            let total = result.sizes.values.reduce(0, +)
            line += ", \(ByteFormatting.string(total)) total (estimate)"
        }
        line += String(format: ", %.1f s", result.duration)
        return line
    }
}
