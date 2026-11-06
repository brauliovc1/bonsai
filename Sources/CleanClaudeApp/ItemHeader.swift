import CleanAppModel
import SwiftUI

/// Repo, branch, estimated size and path.
struct ItemHeader: View {
    let item: RemovalConfirmation.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.repoName).fontWeight(.semibold)
                Text(item.branchText)
                Badge(kind: item.worktree.kind)
                Spacer()
                Text(DisplayText.bytes(item.estimatedBytes)).monospacedDigit()
            }
            Text(item.worktree.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
