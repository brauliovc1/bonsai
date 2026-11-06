import CleanAppModel
import CleanCore
import SwiftUI

/// Repo, branch, kind, a size and the path: the top of every worktree entry in a sheet.
struct WorktreeHeader: View {
    let repoName: String
    let branchText: String
    let kind: WorktreeKind
    let path: String
    /// Shown at the right when there is one.
    var sizeText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(repoName).fontWeight(.semibold)
                Text(branchText)
                Badge(kind: kind)
                Spacer()
                if let sizeText {
                    Text(sizeText).monospacedDigit()
                }
            }
            Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
