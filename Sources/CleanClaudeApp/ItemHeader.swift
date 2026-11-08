import CleanAppModel
import SwiftUI

/// Repo, branch, estimated size and path of one removal item.
struct ItemHeader: View {
    let item: RemovalConfirmation.Item

    var body: some View {
        WorktreeHeader(
            repoName: item.repoName,
            branchText: item.branchText,
            kind: item.worktree.kind,
            path: item.worktree.path,
            sizeText: DisplayText.bytes(item.estimatedBytes)
        )
    }
}
