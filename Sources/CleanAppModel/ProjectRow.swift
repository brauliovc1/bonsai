import CleanCore
import Foundation

/// One row of the Project folders table: a checkout's light-clean folders from the last projects scan, with
/// the texts and sort keys the table shows.
public struct ProjectRow: Identifiable, Hashable, Sendable {
    public let project: ProjectFolders
    /// Against the idle threshold the row was made with.
    public let status: ProjectStatus
    /// The folder with "~" for the home folder.
    public let folderText: String

    public init(project: ProjectFolders, threshold: Int, home: URL?) {
        self.project = project
        self.status = project.status(threshold: threshold)
        self.folderText = home.map { TildePath.abbreviate(project.worktree.path, home: $0) } ?? project.worktree.path
    }

    public typealias ID = String
    public var id: ID { project.id }
    public var worktree: Worktree { project.worktree }
    public var path: String { worktree.path }
    public var url: URL { worktree.url }
    public var kind: WorktreeKind { worktree.kind }
    public var repoName: String { DisplayText.repoName(worktree.repoPath) }

    /// The checkout's folder name.
    public var name: String { url.lastPathComponent }
    /// The repo, when it isn't the folder's own name ("Nexus" next to "Nexus-a13").
    public var repoText: String? { repoName == name ? nil : repoName }

    public var idleDays: Int? { project.idleDays }
    /// "45d", or "unknown" when the idle clock couldn't tell.
    public var idleText: String { idleDays.map { "\($0)d" } ?? "unknown" }

    /// "node_modules, .next": each folder name once, in path order.
    public var foldersText: String {
        var names: [String] = []
        for folder in project.folders where !names.contains(folder.name) { names.append(folder.name) }
        return names.joined(separator: ", ")
    }

    /// Every folder with its size, for the tooltip.
    public var foldersHelp: String {
        project.folders.map { "\($0.relativePath): \(DisplayText.bytes($0.bytes))" }.joined(separator: "\n")
    }

    public var sizeBytes: Int64 { project.totalBytes }
    public var sizeText: String { DisplayText.bytes(sizeBytes) + (project.hasUnknownSizes ? "+" : "") }

    public var statusText: String { statusWords.text }

    public var statusWords: StatusWords {
        switch status {
        case .ready: StatusWords("Ready to clean", .green, symbol: "checkmark.circle")
        case .recent(let days): StatusWords("Worked here \(days) \(days == 1 ? "day" : "days") ago", .blue, symbol: "clock")
        case .idleUnknown: StatusWords("Couldn't check", .grey, symbol: "questionmark.circle")
        case .blocked(.inUse(let processes)), .usedElsewhere(let processes):
            StatusWords("Open in " + Set(processes.map(\.command)).sorted().joined(separator: ", "), .blue, symbol: "macwindow")
        case .blocked:
            StatusWords("Couldn't check", .grey, symbol: "questionmark.circle")
        }
    }

    /// The status sentence, then the folders left alone with why, for the Status cell's tooltip.
    public var statusHelp: String {
        var lines = [status.sentence]
        lines += project.skipped.map { "\($0.relativePath) is left alone: \(CleanupPresentation.reason($0.reason))" }
        lines += project.unreadable.map { "\($0) couldn't be read; nothing below it was looked at." }
        return lines.joined(separator: "\n")
    }

    /// Below the threshold: "You worked here N days ago; it will need a reinstall."
    public var recentNote: String? {
        if case .recent(let days) = status { return ProjectStatus.recentNote(days: days) }
        return nil
    }

    /// Picked by "Select all idle": idle known and at least the threshold, nothing stopping a clean.
    public var isReady: Bool { status.isReady }

    // MARK: - Sort keys (unknown values sort first)

    public var nameSortKey: String { name.lowercased() }
    public var idleSortKey: Int { idleDays ?? -1 }
    public var statusSortKey: Int {
        switch status {
        case .ready: 0
        case .recent: 1
        case .idleUnknown: 2
        case .blocked, .usedElsewhere: 3
        }
    }
}
