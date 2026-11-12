import CleanAppModel
import CleanCore
import SwiftUI

struct BranchMapList: View {
    let model: BranchMapModel
    var search = ""
    @State private var showsDate = true

    var body: some View {
        // Map rows use exact geometry for native target reveal, including the last row in a short viewport.
        VStack(spacing: 0) {
            ForEach(model.rows.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { entry in
                Button { Task { await model.pick(entry.ref, showHistory: false) } } label: {
                    HStack(spacing: 10) {
                        Label(BranchHistoryText.plain(entry.name), systemImage: BranchHistoryText.icon(entry.kind))
                            .lineLimit(1).truncationMode(.middle).frame(minWidth: 120, maxWidth: 220, alignment: .leading)
                            .help(BranchHistoryText.plain(entry.name))
                        if let ahead = entry.metrics.ahead, let behind = entry.metrics.behind, entry.metrics.problem == nil {
                            BranchDistanceBar(ahead: ahead, behind: behind, maximum: model.snapshot?.maximumDistance ?? 0)
                                .frame(minWidth: 70, maxWidth: .infinity)
                        } else { Text("Unknown").font(.caption).foregroundStyle(.secondary).frame(minWidth: 70, maxWidth: .infinity) }
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(entry.metrics.behind.map { "\($0) behind" } ?? "Behind unknown").foregroundStyle(.secondary)
                            Text(entry.metrics.ahead.map { "\($0) ahead" } ?? "Ahead unknown").foregroundStyle(entry.metrics.problem == nil ? Palette.green : .secondary)
                        }.font(.caption).monospacedDigit().frame(width: 88, alignment: .trailing)
                        if showsDate {
                            Text(entry.metrics.tip?.date.formatted(.dateTime.month(.abbreviated).day().year()) ?? "Unknown")
                                .font(.caption).foregroundStyle(.secondary).frame(width: 88, alignment: .trailing)
                        }
                        Text(entry.ref == model.baseRef ? "Base" : entry.metrics.problem != nil ? "Unknown" : entry.metrics.isMerged ? "Merged" : "")
                            .font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                    }.padding(.horizontal, 6).padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .background(model.selectedRef == entry.ref ? Palette.tint(.blue) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .id(entry.ref)
                    .contextMenu { Button("History…") { Task { await model.pick(entry.ref) } } }
                Divider()
            }
        }
        .scrollTargetLayout()
        .onGeometryChange(for: Bool.self) { $0.size.width >= 740 } action: { showsDate = $0 }
    }
}

/// Its scale labels stay visible when the selected branch is far down the list.
struct BranchMapListAxis: View {
    @State private var showsDate = true
    var body: some View {
        HStack(spacing: 10) {
            Text("Branch").frame(minWidth: 120, maxWidth: 220, alignment: .leading)
            HStack { Text("Behind base"); Spacer(); Text("Ahead") }.frame(minWidth: 70, maxWidth: .infinity)
            Text("Commits").frame(width: 88, alignment: .trailing)
            if showsDate { Text("Last commit").frame(width: 88, alignment: .trailing) }
            Text("State").frame(width: 60, alignment: .trailing)
        }.font(.caption).foregroundStyle(.secondary).padding(.vertical, 7)
            .help("Branch distances use one shared logarithmic scale; exact counts are shown beside it.")
            .padding(.horizontal, 6)
            .onGeometryChange(for: Bool.self) { $0.size.width >= 740 } action: { showsDate = $0 }
    }
}

private struct BranchDistanceBar: View {
    let ahead: Int
    let behind: Int
    let maximum: Int
    var body: some View {
        GeometryReader { geometry in
            let half = geometry.size.width / 2
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3).fill(Palette.grey.opacity(0.45))
                    .frame(width: half * BranchMapLayout.fraction(behind, maximum: maximum), height: 8)
                    .frame(width: half, alignment: .trailing)
                RoundedRectangle(cornerRadius: 3).fill(Palette.green)
                    .frame(width: half * BranchMapLayout.fraction(ahead, maximum: maximum), height: 8)
                    .frame(width: half, alignment: .leading)
            }.frame(height: geometry.size.height)
            Rectangle().fill(Palette.grey.opacity(0.6)).frame(width: 1, height: 14).position(x: half, y: geometry.size.height / 2)
        }.frame(height: 18)
            .accessibilityElement(children: .ignore).accessibilityLabel("\(behind) behind, \(ahead) ahead on a shared logarithmic scale")
    }
}
