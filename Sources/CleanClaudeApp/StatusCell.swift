import CleanAppModel
import SwiftUI

/// The Status cell: badge, the blocking reason or the processes inside, and every reason on hover.
struct StatusCell: View {
    let row: WorktreeRow

    var body: some View {
        HStack(spacing: 6) {
            Badge(tone: row.tone, text: row.badgeText)
            if let detail = row.statusDetail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .help(row.reasonsHelp)
    }
}
