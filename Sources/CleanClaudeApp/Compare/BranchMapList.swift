import CleanAppModel
import CleanCore
import SwiftUI

struct BranchMapList: View {
    let model: BranchMapModel
    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(model.rows) { entry in
                Button { Task { await model.pick(entry.ref) } } label: {
                    HStack(spacing: 12) {
                        Label(BranchHistoryText.plain(entry.name), systemImage: BranchHistoryText.icon(entry.kind))
                            .lineLimit(1).truncationMode(.middle).frame(minWidth: 130, maxWidth: 220, alignment: .leading)
                            .help(BranchHistoryText.plain(entry.name))
                        BranchDistanceBar(ahead: entry.metrics.ahead ?? 0, behind: entry.metrics.behind ?? 0, maximum: model.snapshot?.maximumDistance ?? 0)
                            .frame(minWidth: 70, maxWidth: .infinity)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(entry.metrics.behind ?? 0) behind").foregroundStyle(.secondary)
                            Text("\(entry.metrics.ahead ?? 0) ahead").foregroundStyle(Palette.green)
                        }.font(.caption).monospacedDigit().frame(width: 78, alignment: .trailing)
                        if let date = entry.metrics.tip?.date {
                            Text(date, format: .dateTime.month(.abbreviated).day().year())
                                .font(.caption).foregroundStyle(.secondary).frame(width: 88, alignment: .trailing)
                        }
                        Group {
                            if let problem = entry.metrics.problem {
                                StatusChip(words: StatusWords("Couldn't check", .grey, symbol: "questionmark.circle"))
                                    .help(BranchHistoryText.plain(problem))
                            } else if entry.metrics.isMerged { StatusChip(words: StatusWords("Merged", .grey, symbol: "checkmark")) }
                            else { Text("").frame(width: 62) }
                        }
                    }.padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider()
            }
        }
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
