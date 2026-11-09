import CleanAppModel
import CleanCore
import SwiftUI

/// The details panel at the right of the Worktrees screen: one selected worktree in full, a summary for
/// several, a hint for none. Its actions go through the screen's existing flows (the remove and light-clean
/// sheets, Finder, Terminal, the pasteboard); it adds no way of its own to delete anything.
struct WorktreeDetailsView: View {
    let model: WorktreesModel

    var body: some View {
        switch model.detailsSelection {
        case .none:
            ContentUnavailableView(
                "No Selection", systemImage: "sidebar.trailing",
                description: Text("Select a worktree to see its commits, remotes, idle signals and status.")
            )
        case .one(let row):
            ScrollView {
                WorktreeDetailsContent(model: model, row: row)
                    .padding(14)
            }
            .task(id: row.detailsKey) { await model.details.load(for: row) }
        case .several(let summary):
            SelectionSummaryView(model: model, summary: summary)
        }
    }
}

/// One worktree: where it is, what it is, its history, size, idle time, status, and the actions.
struct WorktreeDetailsContent: View {
    let model: WorktreesModel
    let row: WorktreeRow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            DetailsSection("Repo and branch") { RepoBranchDetails(row: row, state: model.details.state(for: row)) }
            DetailsSection("Recent commits") { RecentCommitsDetails(row: row, state: model.details.state(for: row)) }
            DetailsSection("Size") {
                DetailLine("Folder", DisplayText.bytes(row.sizeBytes))
                DetailLine("Dependencies", row.dependencies == .measuring ? "measuring…" : row.dependencyText)
            }
            DetailsSection("Idle") { IdleDetails(row: row) }
            DetailsSection("Status") { StatusDetails(row: row) }
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.url.lastPathComponent).font(.title3.weight(.semibold)).lineLimit(1)
                Badge(kind: row.kind)
            }
            HStack(alignment: .top, spacing: 6) {
                Text(row.path)
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

    private var actions: some View {
        let openable = row.isOpenableFolder
        return VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Button("Reveal in Finder") { FolderActions.reveal([row.url]) }.disabled(!openable)
                Button("Open in Terminal") { FolderActions.openInTerminal([row.url]) }.disabled(!openable)
            }
            HStack {
                Button("Copy Path") { FolderActions.copy([row.path]) }
                Button("Light clean…") { Task { await model.beginLightClean([row.id]) } }
                    .disabled(model.app.isCleaningUp)
                Button("Remove…") { Task { await model.beginRemoval([row.id]) } }
                    .disabled(model.app.isCleaningUp)
            }
        }
        .controlSize(.small)
    }
}

/// Several rows selected: how many, how big, how many can go; the screen's Remove… and Light clean….
struct SelectionSummaryView: View {
    let model: WorktreesModel
    let summary: WorktreeSelectionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.title).font(.title3.weight(.semibold))
            Text(summary.sizeText).monospacedDigit()
            Text(summary.removableText).foregroundStyle(.secondary)
            HStack {
                Button("Light clean…") { Task { await model.beginLightClean() } }
                Button("Remove…") { Task { await model.beginRemoval() } }
            }
            .controlSize(.small)
            .disabled(model.app.isCleaningUp)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A titled block of the details panel.
struct DetailsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
    }
}

/// "Label    value", the value selectable.
struct DetailLine: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(.secondary).frame(width: 92, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
        }
        .font(.callout)
    }
}
