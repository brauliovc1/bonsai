import CleanAppModel
import CleanCore
import SwiftUI

/// One worktree in the list (PLAN §8.4): its kind icon, two lines (branch or name; the folder inside the repo or
/// with "~", cut in the middle), last activity, size and status chip with its notes. The activity column is the
/// first to go in a narrow window. In the flat list (no repo headers) the second line starts with the repo's name.
struct WorktreeListRow: View {
    let row: WorktreeRow
    let showsActivity: Bool
    var showsRepo = false
    var queue: CleanupQueue?

    var body: some View {
        HStack(spacing: 10) {
            KindIcon(kind: row.kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.branchText)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                (showsRepo ? Text("\(Text(row.repoName).fontWeight(.semibold)) · \(row.locationText)") : Text(row.locationText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !showsActivity { status }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(row.path)
            if showsActivity {
                Text(row.activityText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: WorktreeColumns.activity, alignment: .trailing)
            }
            SizeText(bytes: row.sizeBytes, isMeasuring: row.isMeasuringSize)
                .frame(width: WorktreeColumns.size, alignment: .trailing)
            if showsActivity { status.frame(width: WorktreeColumns.status, alignment: .leading) }
        }
        .padding(.leading, showsRepo ? 0 : WorktreeColumns.indent)
        .padding(.vertical, 3)
    }
    private var status: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let queue, queue.task(for: row.path) != nil { QueuedItemStatus(queue: queue, resource: row.path) }
            else { StatusChip(words: row.chip, wraps: !showsActivity) }
            if let notes = row.notesText {
                Text(notes).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(showsActivity ? 1 : nil).fixedSize(horizontal: false, vertical: true)
            }
        }.help(row.reasonsHelp)
    }

}

/// The widths the rows and their headers share, and the narrowest list that still shows the activity column.
enum WorktreeColumns {
    static let indent: CGFloat = 22
    static let activity: CGFloat = 96
    static let size: CGFloat = 86
    static let status: CGFloat = 200
    static let activityMinimumListWidth: CGFloat = 700
}

/// The worktree's kind as an icon: Claude's sparkle, Cursor's pointer, a plain branch; its name on hover.
struct KindIcon: View {
    let kind: WorktreeKind

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(width: 20)
            .help(name)
            .accessibilityLabel(name)
    }

    private var symbol: String {
        switch kind {
        case .main: "folder.fill"
        case .claude: "sparkle"
        case .cursor: "cursorarrow.rays"
        case .sibling, .other: "arrow.triangle.branch"
        }
    }

    private var name: String {
        switch kind {
        case .main: "The repo folder"
        case .claude: "Claude worktree"
        case .cursor: "Cursor worktree"
        case .sibling: "Worktree next to the repo"
        case .other: "Worktree"
        }
    }
}
