import CleanCore
import Foundation

/// Repo text stays plain and escaped in every branch-map presentation.
enum BranchHistoryText {
    static func plain(_ text: String) -> String { DiffText.decode(Data(text.utf8)) }
    static func name(_ ref: String) -> String {
        for prefix in ["refs/heads/", "refs/remotes/", "refs/tags/"] where ref.hasPrefix(prefix) { return plain(String(ref.dropFirst(prefix.count))) }
        return plain(ref)
    }
    static func commit(_ commit: BranchHistoryCommit) -> String {
        "\(commit.shortSHA) · \(plain(commit.subject)) · \(commit.date.formatted(date: .abbreviated, time: .shortened))"
    }
    static func counts(_ entry: BranchMapEntry) -> String {
        "\(entry.metrics.behind ?? 0) behind · \(entry.metrics.ahead ?? 0) ahead"
    }
    static func icon(_ kind: BranchMapEntry.Kind) -> String {
        switch kind {
        case .claude: "sparkles"
        case .cursor: "cursorarrow"
        case .worktree: "folder.badge.gearshape"
        case .remote: "network"
        case .branch: "arrow.triangle.branch"
        }
    }
}
