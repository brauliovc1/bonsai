import CleanAppModel
import CleanCore
import SwiftUI

/// The first column: the repo name and how many worktrees on a group header, the branch on a worktree.
struct WorktreeNameCell: View {
    let item: WorktreeTableItem

    var body: some View {
        switch item {
        case .group(let group):
            HStack(spacing: 6) {
                Text(group.name).fontWeight(.semibold)
                Text(group.countText).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .help(group.folderText)
        case .worktree(let row):
            Text(row.branchText).lineLimit(1).help(row.path)
        }
    }
}

/// A worktree's last commit: the subject and "3d ago", the whole message on hover. On a group header, the
/// repo's remote.
struct LastCommitCell: View {
    let item: WorktreeTableItem

    var body: some View {
        switch item {
        case .group(let group):
            Label(group.remoteText ?? "No remote", systemImage: "network")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(group.remotesHelp)
        case .worktree(let row):
            HStack(spacing: 6) {
                Text(row.lastCommitText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(row.lastCommitAgoText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .help(row.lastCommitHelp)
        }
    }
}

/// The folder with "~", cut in the middle when long; the full path on hover.
struct FolderCell: View {
    let item: WorktreeTableItem

    var body: some View {
        Text(item.folderText)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(item.row == nil ? .secondary : .primary)
            .help(path)
    }

    private var path: String {
        switch item {
        case .group(let group): group.repoPath
        case .worktree(let row): row.path
        }
    }
}

/// A worktree's size, or the group's total.
struct SizeCell: View {
    let item: WorktreeTableItem

    var body: some View {
        switch item {
        case .group(let group):
            Text(group.sizeText)
                .monospacedDigit()
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .help("The shown worktrees together")
        case .worktree(let row):
            Text(row.sizeText).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
