import CleanAppModel
import SwiftUI

/// A repo's header in the Worktrees list: the repo folder itself, never a row and never removable (PLAN §8.4).
/// "aitiu0  repo folder 120 MB · 2 worktrees, 3.7 GB · last commit 10 weeks ago", with "Clean dependencies…"
/// when the folder has dependency or build folders and "Remove all N" when the group has worktrees that can go.
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
            Text(group.name)
                .font(.headline)
                .lineLimit(1)
                .layoutPriority(1)
            Text(group.headerDetail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .monospacedDigit()
            Spacer(minLength: 8)
            if let bytes = group.dependencyBytes {
                Button("Clean dependencies…") { Task { await model.cleanDependencies(of: group) } }
                    .help("Delete the repo folder's dependency and build folders (\(DisplayText.bytes(bytes))); you confirm first.")
                    .disabled(model.app.isCleaningUp)
            }
            let removable = group.removableRows
            if !removable.isEmpty {
                Button("Remove all \(removable.count)") { Task { await model.removeAll(in: group) } }
                    .help(removeAllHelp(removable))
                    .disabled(model.app.isCleaningUp)
            }
        }
        .controlSize(.small)
        .padding(.vertical, 4)
        .help("\(group.folderText)\n\(WorktreeStatusText.repoFolderSentence)")
    }

    private func removeAllHelp(_ rows: [WorktreeRow]) -> String {
        let bytes = rows.compactMap(\.sizeBytes).reduce(0, +)
        let what = rows.count == 1 ? "the worktree" : "the \(rows.count) worktrees"
        return "Remove \(what) shown here that can be removed (\(DisplayText.bytes(bytes))); you confirm first. "
            + "The repo folder stays."
    }
}
