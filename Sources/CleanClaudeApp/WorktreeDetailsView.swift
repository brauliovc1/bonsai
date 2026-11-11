import CleanAppModel
import CleanCore
import SwiftUI

/// The details panel at the right of the Worktrees screen: one selected worktree or repo folder in full, a
/// summary for several, a hint for none. Its actions go through the screen's existing flows (the remove, prune
/// and clean sheets, Finder, Terminal, the pasteboard); it adds no way of its own to delete anything.
struct WorktreeDetailsView: View {
    let model: WorktreesModel

    var body: some View {
        switch model.detailsSelection {
        case .none:
            EmptyState(
                systemImage: "sidebar.trailing", headline: "No selection",
                line: "Select a worktree to see what it holds and whether it can be removed."
            )
            .frame(maxHeight: .infinity)
        case .one(let row):
            ScrollView {
                WorktreeDetailsContent(model: model, row: row)
                    .padding(16)
            }
            .task(id: row.detailsKey) { await model.details.load(for: row) }
        case .several(let summary):
            SelectionSummaryView(model: model, summary: summary)
        }
    }
}

/// One worktree or repo folder: what it is, its status in one plain sentence with the one action that does the
/// job or fixes what stops it, every unsaved file, then where it is, its history, size, activity and everything
/// Bonsai found.
struct WorktreeDetailsContent: View {
    let model: WorktreesModel
    let row: WorktreeRow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            DetailsStatusBox(model: model, row: row)
            if row.kind == .claude {
                Label(SafetyReason.claudeSessionWarning, systemImage: "exclamationmark.bubble")
                    .font(.callout)
                    .foregroundStyle(Palette.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Palette.tint(.orange), in: RoundedRectangle(cornerRadius: 8))
            }
            let unsaved = row.worktree.isMain ? [] : row.unsavedFiles
            if !unsaved.isEmpty {
                // Read-only: Bonsai never discards or checks out anything here; the list is new with each scan.
                DetailsSection("Unsaved changes (\(unsaved.count))") { WorktreeFileList(files: unsaved) }
            }
            DetailsSection("Repo and branch") { RepoBranchDetails(row: row, state: model.details.state(for: row)) }
            DetailsSection("Recent commits") { RecentCommitsDetails(row: row, state: model.details.state(for: row)) }
            DetailsSection("Size") {
                DetailRow("Folder") { SizeText(bytes: row.sizeBytes, isMeasuring: row.isMeasuringSize) }
                DetailRow("Dependencies") { dependencies }
            }
            if !row.worktree.isMain {
                DetailsSection("Activity") { IdleDetails(row: row) }
            }
            if !row.worktree.isMain, row.reasons.contains(where: { $0 != .claudeSession }) {
                DetailsSection("What Bonsai found") { ReasonsDetails(row: row) }
            }
            secondaryActions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                KindIcon(kind: row.kind)
                Text(row.worktree.isMain ? row.repoName : row.url.lastPathComponent)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(alignment: .top, spacing: 6) {
                Text(row.folderText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(4)
                Button { FolderActions.copy([row.path]) } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy the full path")
            }
        }
    }

    @ViewBuilder
    private var dependencies: some View {
        switch row.dependencies {
        case .measuring:
            SizeText(bytes: nil, isMeasuring: true)
        case .notMeasured:
            Text("Not measured yet").foregroundStyle(.secondary)
        case .measured(let bytes):
            Text(bytes.map(DisplayText.bytes) ?? "None to clean")
                .monospacedDigit()
                .foregroundStyle(bytes == nil ? .secondary : .primary)
        }
    }

    private var secondaryActions: some View {
        let openable = row.isOpenableFolder
        return HStack(spacing: 14) {
            Button("Show in Finder") { FolderActions.reveal([row.url]) }.disabled(!openable)
            Button("Open in Terminal") { FolderActions.openInTerminal([row.url]) }.disabled(!openable)
            Button("Copy path") { FolderActions.copy([row.path]) }
            if row.fix != .cleanDependencies, openable, !row.isStaleRecord {
                Button("Clean dependencies…") { Task { await model.beginLightClean([row.id]) } }
                    .disabled(model.app.cleanupQueue.task(for: row.path) != nil)
                    .help(model.app.cleanupQueue.task(for: row.path) != nil ? CleanupQueue.lockedHelp : "Clean dependency folders after confirmation.")
            }
        }
        .buttonStyle(.link)
        .font(.callout)
    }
}

/// Several selected: how many, how big, how many can go, and Remove… for those.
struct SelectionSummaryView: View {
    let model: WorktreesModel
    let summary: WorktreeSelectionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.title).font(.title3.weight(.semibold))
            Text(summary.sizeText).monospacedDigit()
            Text(summary.removableText).foregroundStyle(.secondary)
            HStack {
                Button(summary.removableCount > 0 ? "Remove \(summary.removableCount)…" : "Remove…", role: .destructive) {
                    Task { await model.removeSelection() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.red)
                .disabled(!model.canRemoveSelection)
                .help(model.removeDisabledReason ?? "Remove the selected worktrees that can be removed (you confirm first)")
                Button("Clean dependencies…") { Task { await model.beginLightClean() } }
                    .disabled(!model.canCleanDependencies)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
