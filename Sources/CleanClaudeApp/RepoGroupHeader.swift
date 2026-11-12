import CleanAppModel
import SwiftUI

/// A repo's header in the Worktrees list: the repo folder itself, never a row and never removable (PLAN §8.4).
/// Its compact summary keeps the name readable; available cleanup actions are in More.
/// The chevron collapses the group.
struct RepoGroupHeader: View {
    let model: WorktreesModel
    let group: WorktreeGroup

    var body: some View {
        let expanded = model.isExpanded(group.repoPath)
        HStack(spacing: 8) {
            Button { model.toggleExpanded(group.repoPath) } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(expanded ? "Hide this repo's worktrees" : "Show this repo's worktrees")
            .accessibilityLabel(expanded ? "Collapse \(group.name)" : "Expand \(group.name)")
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(.headline).lineLimit(1).truncationMode(.middle)
                Text(group.headerDetail).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).monospacedDigit()
            }.frame(maxWidth: .infinity, alignment: .leading)
            if group.dependencyBytes != nil || !group.removableRows.isEmpty {
                Menu("More") {
            if let bytes = group.dependencyBytes {
                Button("Clean dependencies…") { Task { await model.cleanDependencies(of: group) } }
                    .disabled(model.app.cleanupQueue.task(for: group.repoPath) != nil)
                    .help(model.app.cleanupQueue.task(for: group.repoPath) != nil ? CleanupQueue.lockedHelp
                        : "Delete the repo folder's dependency and build folders (\(DisplayText.bytes(bytes))); you confirm first.")
            }
            let removable = group.removableRows
            if !removable.isEmpty {
                Button("Remove all \(removable.count)") { Task { await model.removeAll(in: group) } }
                    .disabled(removable.allSatisfy { model.app.cleanupQueue.task(for: $0.path) != nil })
                    .help(removable.allSatisfy { model.app.cleanupQueue.task(for: $0.path) != nil }
                        ? CleanupQueue.lockedHelp : removeAllHelp(removable))
            }
                }.fixedSize()
            }
        }
        .controlSize(.small)
        .padding(.vertical, 4)
        .help("\(group.folderText)\n\(WorktreeStatusText.repoFolderSentence)")
    }

    private func removeAllHelp(_ rows: [WorktreeRow]) -> String {
        let amount = CleanupPresentation.estimate(rows.map(\.sizeBytes))
        let what = rows.count == 1 ? "the worktree" : "the \(rows.count) worktrees"
        return "Remove \(what) shown here that can be removed (\(amount)); you confirm first. "
            + "The repo folder stays."
    }
}
