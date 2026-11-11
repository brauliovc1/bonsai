import CleanAppModel
import CleanCore
import SwiftUI

struct BranchMapTimeline: View {
    let model: BranchMapModel
    private let rowHeight: CGFloat = 34
    private let heading: CGFloat = 40

    var body: some View {
        let rows = model.rows
        let timeline = model.timeline
        let dates = rows.compactMap { $0.metrics.tip?.date } + timeline.values.compactMap { $0.fork?.date }
        let first = dates.min() ?? Date(), last = dates.max() ?? Date()
        let start = first.addingTimeInterval(-86400), end = max(last, first).addingTimeInterval(86400)
        let height = heading + CGFloat(rows.count) * rowHeight + 26
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Base: \(BranchHistoryText.name(model.snapshot?.base ?? ""))")
                        .font(.caption.weight(.medium)).lineLimit(1).frame(height: heading, alignment: .topLeading)
                    ForEach(rows) { entry in
                        Button { Task { await model.pick(entry.ref) } } label: {
                            Label(BranchHistoryText.plain(entry.name), systemImage: BranchHistoryText.icon(entry.kind))
                                .font(.callout).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).frame(height: rowHeight).help(BranchHistoryText.plain(entry.name))
                    }
                }.frame(width: 170, alignment: .leading)
                GeometryReader { geometry in
                    let green = Palette.green, grey = Palette.grey
                    ZStack(alignment: .topLeading) {
                        Canvas { context, size in
                            var base = Path(); base.move(to: CGPoint(x: 0, y: 20)); base.addLine(to: CGPoint(x: size.width, y: 20))
                            context.stroke(base, with: .color(grey.opacity(0.6)), lineWidth: 2)
                            for (index, entry) in rows.enumerated() {
                                guard let tip = entry.metrics.tip,
                                      let fork = timeline[entry.ref]?.fork,
                                      let parent = model.timelineParent(for: entry.ref) else { continue }
                                let y = heading + CGFloat(index) * rowHeight + rowHeight / 2
                                let forkX = Self.x(fork.date, width: size.width, start: start, end: end)
                                let tipX = Self.x(tip.date, width: size.width, start: start, end: end)
                                let parentY: CGFloat
                                switch parent {
                                case .base: parentY = 20
                                case .branch(let ref):
                                    guard let parentIndex = rows.firstIndex(where: { $0.ref == ref }) else { continue }
                                    parentY = heading + CGFloat(parentIndex) * rowHeight + rowHeight / 2
                                }
                                var path = Path(); path.move(to: CGPoint(x: forkX, y: parentY))
                                path.addLine(to: CGPoint(x: forkX, y: y)); path.addLine(to: CGPoint(x: tipX, y: y))
                                context.stroke(path, with: .color(entry.metrics.problem == nil ? green.opacity(0.7) : grey), lineWidth: 1.5)
                            }
                        }
                        ForEach(Array(rows.enumerated()), id: \.element.ref) { index, entry in
                            let y = heading + CGFloat(index) * rowHeight + rowHeight / 2
                            let data = timeline[entry.ref]
                            Button { Task { await model.pick(entry.ref) } } label: {
                                Color.clear.frame(width: geometry.size.width, height: rowHeight).contentShape(Rectangle())
                            }.buttonStyle(.plain).position(x: geometry.size.width / 2, y: y)
                                .help(tooltip(entry, data: data))
                            if let tip = entry.metrics.tip {
                                Circle().fill(green).frame(width: 7, height: 7)
                                    .position(x: Self.x(tip.date, width: geometry.size.width, start: start, end: end), y: y)
                                    .help(BranchHistoryText.commit(tip) + "\n" + BranchHistoryText.counts(entry))
                                    .onTapGesture { Task { await model.pick(entry.ref) } }
                            }
                            ForEach(data?.commits ?? []) { commit in
                                Circle().fill(green).frame(width: 5, height: 5)
                                    .position(x: Self.x(commit.date, width: geometry.size.width, start: start, end: end), y: y)
                                    .help(BranchHistoryText.commit(commit))
                                    .onTapGesture { Task { await model.pick(entry.ref) } }
                            }
                            if let data, data.commitCount > data.commits.count {
                                Text("+\(data.commitCount - data.commits.count) more").font(.caption2).foregroundStyle(.secondary)
                                    .position(x: geometry.size.width - 48, y: y - 11)
                            }
                        }
                        HStack {
                            Text(start, format: .dateTime.month(.abbreviated).day().year())
                            Spacer()
                            Text(end, format: .dateTime.month(.abbreviated).day().year())
                        }.font(.caption2).foregroundStyle(.secondary).position(x: geometry.size.width / 2, y: height - 8)
                    }
                }.frame(minWidth: 480, minHeight: height, maxHeight: height)
            }.frame(minWidth: 680, minHeight: height, alignment: .topLeading)
        }
    }

    nonisolated private static func x(_ date: Date, width: CGFloat, start: Date, end: Date) -> CGFloat {
        let fraction = min(1, max(0, date.timeIntervalSince(start) / max(1, end.timeIntervalSince(start))))
        return 12 + CGFloat(fraction) * max(1, width - 24)
    }
    private func tooltip(_ entry: BranchMapEntry, data: BranchTimelineEntry?) -> String {
        var text = BranchHistoryText.plain(entry.name) + "\n" + BranchHistoryText.counts(entry)
        if let fork = data?.fork { text += "\nFork: " + BranchHistoryText.commit(fork) }
        if let data, data.problem == nil, data.fork != nil { text += "\n\(data.commitCount) commits since this fork" }
        if let problem = data?.problem ?? entry.metrics.problem { text += "\n" + BranchHistoryText.plain(problem) }
        return text
    }
}
