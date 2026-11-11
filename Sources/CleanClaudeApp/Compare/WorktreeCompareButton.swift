import CleanAppModel
import SwiftUI

struct WorktreeCompareButton: View {
    let model: WorktreesModel
    let row: WorktreeRow
    @State private var base = "base branch"

    var body: some View {
        Button("Compare with \(base)…") { model.openCompare(row) }
            .disabled(!row.isOpenableFolder || model.onCompare == nil)
            .task(id: row.worktree.repoPath) { base = await model.compareBase(for: row.worktree.repoPath) }
    }
}
