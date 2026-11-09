import CleanAppModel
import CleanCore
import SwiftUI

/// One worktree in the list (PLAN §8.4): its kind icon, two lines (branch or name; the folder inside the repo or
/// with "~", cut in the middle), last activity, size and status chip with its notes. The activity column is the
/// first to go in a narrow window.
struct WorktreeListRow: View {
    let row: WorktreeRow
    let showsActivity: Bool

    var body: some View {
        HStack(spacing: 10) {
            KindIcon(kind: row.kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.branchText)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.locationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
            VStack(alignment: .leading, spacing: 2) {
                StatusChip(words: row.chip)
                if let notes = row.notesText {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(width: WorktreeColumns.status, alignment: .leading)
            .help(row.reasonsHelp)
        }
        .padding(.leading, WorktreeColumns.indent)
        .padding(.vertical, 3)
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
