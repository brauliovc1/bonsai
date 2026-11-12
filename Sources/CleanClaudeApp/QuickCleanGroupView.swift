import CleanAppModel
import SwiftUI

/// Category summaries stay visible; exact paths and per-item notes expand inside the sheet's scroll area.
struct QuickCleanGroupView: View {
    let group: QuickCleanGroup
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if group.items.isEmpty {
                header.padding(.leading, 18)
            } else {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        if !group.detail.isEmpty {
                            Text(group.detail).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(group.items) { item in
                            itemRow(item)
                            if item.id != group.items.last?.id { Divider() }
                        }
                    }.padding(.top, 8).padding(.leading, 4)
                } label: { header }
            }
            if group.id == .docker && !group.items.isEmpty {
                dockerScope.padding(.leading, 18)
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(group.title).font(.callout.weight(.medium)).fixedSize()
                Text(countText).font(.callout).foregroundStyle(.secondary).fixedSize()
                Spacer(minLength: 8)
                amount
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title).font(.callout.weight(.medium))
                    Text(countText).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                amount
            }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }

    @ViewBuilder
    private var amount: some View {
        if !group.items.isEmpty { Text(groupSizeText).font(.callout).monospacedDigit().fixedSize() }
    }

    private var groupSizeText: String {
        let amount = CleanupPresentation.estimate(group.items.map(\.estimatedBytes))
        return group.id == .docker && group.unknownSizeCount == 0 ? "up to " + amount : amount
    }

    private func itemSizeText(_ item: QuickCleanItem) -> String {
        let amount = CleanupPresentation.estimate([item.estimatedBytes])
        return group.id == .docker && item.estimatedBytes != nil ? "up to " + amount : amount
    }

    private var countText: String {
        if group.items.isEmpty { return "0 eligible" }
        let count = group.items.count
        switch group.id {
        case .worktrees: return "Remove \(count)"
        case .projects, .derivedData: return "Delete \(count) \(count == 1 ? "folder" : "folders")"
        case .toolCaches: return "Clean \(count)"
        case .docker: return "Run 1 command"
        case .simulators: return "Delete \(count) \(count == 1 ? "device" : "devices")"
        case .downloads: return "Move \(count) to Trash"
        }
    }

    private var dockerScope: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("docker system prune -f").font(.system(.caption, design: .monospaced))
            Text("Docker chooses unused data when it runs. Volumes, tagged images and running containers stay; space may return later.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func itemRow(_ item: QuickCleanItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title).font(.callout.weight(.medium))
                Spacer(minLength: 8)
                Text(itemSizeText(item)).font(.callout).monospacedDigit()
            }
            if !item.detail.isEmpty {
                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(paths(of: item), id: \.self) { path in
                Text(path).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
    }

    private func paths(of item: QuickCleanItem) -> [String] {
        var paths = item.paths
        if let path = item.path, !paths.contains(path) { paths.insert(path, at: 0) }
        return paths
    }
}
