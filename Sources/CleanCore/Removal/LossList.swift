/// PLAN §4.8: everything "Remove anyway" deletes for good, and the notes listed with it, read from one
/// inspection by `RemoveAnyway.verdict`. The confirmation sheet shows it, the re-check right before the delete
/// builds a fresh one and compares it with the confirmed one entry by entry, and the log keeps it.
public struct LossList: Sendable, Hashable {
    public enum Category: String, Sendable, Hashable, CaseIterable {
        case uncommittedFiles, hiddenEdits, reposWithLocalWork, unreadableRepos, submodules, unpushedCommits,
             unreachableCommits, ignoredFiles, commitsOnBranch, stashes, claudeSession

        /// Deleted with the worktree, for good. The others are listed too: kept (branch commits, stashes), or
        /// the Claude session that can't continue.
        public var isLost: Bool {
            switch self {
            case .commitsOnBranch, .stashes, .claudeSession: false
            default: true
            }
        }

        public var title: String {
            switch self {
            case .uncommittedFiles: "Uncommitted or untracked files"
            case .hiddenEdits: "Hidden local edits"
            case .reposWithLocalWork: "Repos inside with local work"
            case .unreadableRepos: "Repos inside git couldn't read"
            case .submodules: "Submodules"
            case .unpushedCommits: "Commits on no branch or remote"
            case .unreachableCommits: "Commits only in this worktree's history"
            case .ignoredFiles: "Ignored files that aren't build output"
            case .commitsOnBranch: "Commits not pushed (the branch keeps them)"
            case .stashes: "Stashes (kept: they belong to the repo)"
            case .claudeSession: "Claude session"
            }
        }

        /// "3 uncommitted files", for the one-line summary.
        func counted(_ count: Int) -> String {
            let (one, many) = switch self {
            case .uncommittedFiles: ("uncommitted file", "uncommitted files")
            case .hiddenEdits: ("hidden edit", "hidden edits")
            case .reposWithLocalWork: ("repo with local work", "repos with local work")
            case .unreadableRepos: ("repo git couldn't read", "repos git couldn't read")
            case .submodules: ("submodule", "submodules")
            case .unpushedCommits: ("commit on no branch", "commits on no branch")
            case .unreachableCommits: ("unreachable commit", "unreachable commits")
            case .ignoredFiles: ("ignored file", "ignored files")
            case .commitsOnBranch: ("commit not pushed", "commits not pushed")
            case .stashes: ("stash", "stashes")
            case .claudeSession: ("Claude session", "Claude sessions")
            }
            return "\(count) \(count == 1 ? one : many)"
        }
    }

    public struct Entry: Sendable, Hashable {
        /// A path (relative to the worktree), a repo, a short sha, or a sentence.
        public var text: String
        /// What git or the check says about it: "untracked", "renamed from a.txt", what a repo holds.
        public var detail: String?
        /// What identifies it beyond the text: git's two status letters, a commit's full sha.
        public var key: String?
        /// lstat of the path when it was read: an edit since then makes the entry differ.
        public var stamp: FileStamp?

        public init(text: String, detail: String? = nil, key: String? = nil, stamp: FileStamp? = nil) {
            self.text = text
            self.detail = detail
            self.key = key
            self.stamp = stamp
        }
    }

    public struct Section: Sendable, Hashable {
        public var category: Category
        public var entries: [Entry]

        public init(category: Category, entries: [Entry]) {
            self.category = category
            self.entries = entries
        }
    }

    /// In `Category` order; no empty section.
    public var sections: [Section]

    public init(sections: [Section]) {
        self.sections = sections.filter { !$0.entries.isEmpty }
    }

    public var lostSections: [Section] { sections.filter(\.category.isLost) }
    public var entryCount: Int { sections.reduce(0) { $0 + $1.entries.count } }

    public func entries(_ category: Category) -> [Entry] {
        sections.first { $0.category == category }?.entries ?? []
    }
}
