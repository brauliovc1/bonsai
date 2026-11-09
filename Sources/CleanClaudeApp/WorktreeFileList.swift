import CleanAppModel
import SwiftUI

/// Every file of a list (unsaved changes, or what Remove anyway deletes) in a box of its own height, up to a limit,
/// then scrolling; rows are made only as they show, so thousands of files stay quick.
struct WorktreeFileList: View {
    let files: [WorktreeFileRow]
    var maxHeight: CGFloat = 260

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(files) { file in
                    WorktreeFileRowView(file: file)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: min(CGFloat(files.count) * WorktreeFileRowView.height + 8, maxHeight))
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.stroke))
    }
}

/// One file: its state in a plain word, the path relative to the worktree (middle-truncated; in full in the
/// tooltip), and Show in Finder, Open and Copy path. A deleted file offers Copy path only.
struct WorktreeFileRowView: View {
    static let height: CGFloat = 26
    let file: WorktreeFileRow

    var body: some View {
        HStack(spacing: 8) {
            Text(file.word)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(file.path)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !file.isGone {
                Button { FileActions.reveal(file.url) } label: { Image(systemName: "folder") }
                    .help("Show in Finder")
                Button { FileActions.open(file.url) } label: { Image(systemName: "arrow.up.forward.square") }
                    .help("Open (scripts open as text, apps only in Finder)")
            }
            Button { FolderActions.copy([file.fullPath]) } label: { Image(systemName: "doc.on.doc") }
                .help("Copy path")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .help([file.word + (file.detail.map { " " + $0 } ?? ""), file.fullPath].joined(separator: "\n"))
    }
}
