import CleanAppModel
import CleanCore
import SwiftUI

/// The first column: on a group header the open/close chevron, the repo name and how many projects; on a
/// project, indented under it, its folder name and the repo when that differs.
struct ProjectNameCell: View {
    let item: ProjectTableItem
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        switch item {
        case .group(let group):
            HStack(spacing: 4) {
                Button(action: toggle) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(isExpanded ? "Hide this repo's projects" : "Show this repo's projects")
                .accessibilityLabel(isExpanded ? "Collapse \(group.name)" : "Expand \(group.name)")
                Text(group.name).fontWeight(.semibold).layoutPriority(1)
                Text(group.countText).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .help(group.folderText)
        case .project(let row):
            HStack(spacing: 6) {
                Text(row.name).layoutPriority(1)
                if let repo = row.repoText {
                    Text(repo).foregroundStyle(.secondary)
                }
                if row.kind != .main {
                    Badge(kind: row.kind)
                }
            }
            .lineLimit(1)
            .padding(.leading, 18)
            .help(row.folderText)
        }
    }
}

/// A project's folders added up, or the group's total.
struct ProjectSizeCell: View {
    let item: ProjectTableItem

    var body: some View {
        switch item {
        case .group(let group):
            Text(group.sizeText)
                .monospacedDigit()
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .help("The shown projects together")
        case .project(let row):
            Text(row.sizeText)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .help(row.foldersHelp)
        }
    }
}

/// Ready / Recent / Idle unknown / In use, with the reinstall note for a recent project; the reason and the
/// folders left alone on hover.
struct ProjectStatusCell: View {
    let row: ProjectRow

    var body: some View {
        HStack(spacing: 6) {
            Badge(text: row.statusText, color: color)
            if let note = row.recentNote {
                Text(note)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if !row.project.skipped.isEmpty {
                Text("\(DisplayText.folders(row.project.skipped.count)) left alone")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .help(row.statusHelp)
    }

    private var color: Color {
        switch row.status {
        case .ready: .green
        case .recent: .blue
        case .idleUnknown: .secondary
        case .blocked, .usedElsewhere: .purple
        }
    }
}
