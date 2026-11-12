import CleanAppModel
import SwiftUI

struct WorktreeCompareButton: View {
    let model: WorktreesModel
    let row: WorktreeRow
    @State private var base = "base branch"

    var body: some View {
        Button { model.openCompare(row) } label: {
            Text("Compare with \(base)…")
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
            .help("Compare with \(base)…")
            .disabled(!row.isOpenableFolder || model.onCompare == nil)
            .task(id: row.worktree.repoPath) { base = await model.compareBase(for: row.worktree.repoPath) }
    }
}
