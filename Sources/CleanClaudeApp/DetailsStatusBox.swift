import CleanAppModel
import CleanCore
import SwiftUI

/// The top of the details panel: the status chip and its notes, the status in one plain sentence, and the one
/// action that does the job or fixes what stops it. For a repo folder, Remove… is there but disabled, and says
/// why (PLAN §8.5). A blocked worktree whose blockers Bonsai can all list gets "Remove anyway…" next to its fix
/// (PLAN §4.8); one that also has a blocker Remove anyway never overrides says what to do instead.
struct DetailsStatusBox: View {
    let model: WorktreesModel
    let row: WorktreeRow

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                if model.app.cleanupQueue.task(for: row.path) != nil {
                    QueuedItemStatus(queue: model.app.cleanupQueue, resource: row.path)
                } else { StatusChip(words: row.chip) }
                if let notes = row.notesText {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Text(row.explanation)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                fixButton
                if row.worktree.isMain {
                    Button("Remove…") {}
                        .disabled(true)
                        .help(WorktreeStatusText.repoFolderSentence)
                }
                if row.offersRemoveAnyway {
                    Button(RemoveAnywayText.actionTitle, role: .destructive) { Task { await model.beginRemoveAnyway() } }
                        .foregroundStyle(Palette.red)
                        .disabled(!model.canRemoveAnyway || model.removeAnywayRow?.id != row.id)
                        .help(model.removeAnywayHelp)
                }
            }
            if let instead = row.removeAnywayUnavailableText {
                Label(instead, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.stroke))
    }

    @ViewBuilder
    private var fixButton: some View {
        let busy = model.app.cleanupQueue.task(for: row.path) != nil
        switch row.fix {
        case .remove:
            Button(WorktreeFix.remove.title, role: .destructive) { Task { await model.beginRemoval([row.id]) } }
                .buttonStyle(.borderedProminent)
                .tint(Palette.red)
                .disabled(busy || !row.canRemove)
                .help(busy ? CleanupQueue.lockedHelp : "Remove this worktree (you confirm first). Its branch is kept.")
        case .prune:
            Button(WorktreeFix.prune.title) { Task { await model.beginPrune() } }
                .disabled(busy)
        case .cleanDependencies:
            Button(WorktreeFix.cleanDependencies.title) { Task { await model.beginLightClean([row.id]) } }
                .buttonStyle(.borderedProminent)
                .disabled(busy || row.dependencies == .measured(nil))
                .help(busy ? CleanupQueue.lockedHelp : row.dependencies == .measured(nil)
                    ? "No dependency or build folders to clean here."
                    : "Delete the dependency and build folders here (you confirm first).")
        case .openInTerminal:
            Button(WorktreeFix.openInTerminal.title) { FolderActions.openInTerminal([row.url]) }
                .disabled(!row.isOpenableFolder)
        case .showInFinder:
            Button(WorktreeFix.showInFinder.title) { FolderActions.reveal([row.url]) }
                .disabled(!row.isOpenableFolder)
        case .refresh:
            Button(WorktreeFix.refresh.title) { model.app.requestRefresh() }
                .disabled(model.app.isScanning)
        case .none:
            EmptyView()
        }
    }
}
