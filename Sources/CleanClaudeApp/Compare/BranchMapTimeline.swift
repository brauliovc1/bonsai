import CleanAppModel
import CleanCore
import SwiftUI

struct BranchMapTimeline: View {
    let model: BranchMapModel
    var search = ""
    private let rowHeight: CGFloat = 34
    private let heading: CGFloat = 32

    var body: some View {
        let rows = model.rows.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        let timeline = model.timeline
        let dates = model.rows.compactMap { $0.metrics.tip?.date } + timeline.values.compactMap { $0.fork?.date }
        let first = dates.min() ?? Date(), last = dates.max() ?? Date()
        let start = first.addingTimeInterval(-86400), end = max(last, first).addingTimeInterval(86400)
        let height = heading + CGFloat(rows.count) * rowHeight + 26
        HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Base: \(BranchHistoryText.name(model.snapshot?.base ?? ""))")
                        .font(.caption.weight(.medium)).lineLimit(2).frame(height: heading, alignment: .topLeading)
                    ForEach(rows) { entry in
                        Button { Task { await model.pick(entry.ref, showHistory: false) } } label: {
                            Label(BranchHistoryText.plain(entry.name), systemImage: BranchHistoryText.icon(entry.kind))
                                .font(.callout).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).frame(height: rowHeight)
                            .background(model.selectedRef == entry.ref ? Palette.tint(.blue) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            .help(BranchHistoryText.plain(entry.name)).id(entry.ref)
                    }
                }.frame(width: 170, alignment: .leading)
                GeometryReader { geometry in
                    let green = Palette.green, grey = Palette.grey
                    ZStack(alignment: .topLeading) {
                        Canvas { context, size in
                            var base = Path(); base.move(to: CGPoint(x: 0, y: 16)); base.addLine(to: CGPoint(x: size.width, y: 16))
                            context.stroke(base, with: .color(grey.opacity(0.6)), lineWidth: 2)
                            for (index, entry) in rows.enumerated() {
                                let laneY = heading + CGFloat(index) * rowHeight
                                if model.selectedRef == entry.ref {
                                    context.fill(Path(CGRect(x: 0, y: laneY, width: size.width, height: rowHeight)), with: .color(Palette.tint(.blue)))
                                }
                                var guide = Path(); guide.move(to: CGPoint(x: 0, y: laneY + rowHeight / 2)); guide.addLine(to: CGPoint(x: size.width, y: laneY + rowHeight / 2))
                                context.stroke(guide, with: .color(grey.opacity(0.12)), lineWidth: 1)
                                guard let tip = entry.metrics.tip,
                                      let fork = timeline[entry.ref]?.fork,
                                      let parent = model.timelineParent(for: entry.ref) else { continue }
                                let y = heading + CGFloat(index) * rowHeight + rowHeight / 2
                                let forkX = Self.x(fork.date, width: size.width, start: start, end: end)
                                let tipX = Self.x(tip.date, width: size.width, start: start, end: end)
                                let parentY: CGFloat
                                switch parent {
                                case .base: parentY = 16
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
                            Button { Task { await model.pick(entry.ref, showHistory: false) } } label: {
                                Color.clear.frame(width: geometry.size.width, height: rowHeight).contentShape(Rectangle())
                            }.buttonStyle(.plain).position(x: geometry.size.width / 2, y: y)
                                .help(tooltip(entry, data: data))
                            if let fork = data?.fork {
                                Image(systemName: "diamond.fill").font(.system(size: 7)).foregroundStyle(grey)
                                    .position(x: Self.x(fork.date, width: geometry.size.width, start: start, end: end), y: y)
                                    .help("Fork: " + BranchHistoryText.commit(fork))
                            }
                            if let tip = entry.metrics.tip {
                                Circle().fill(green).frame(width: 7, height: 7)
                                    .position(x: Self.x(tip.date, width: geometry.size.width, start: start, end: end), y: y)
                                    .help(BranchHistoryText.commit(tip) + "\n" + BranchHistoryText.counts(entry))
                                    .onTapGesture { Task { await model.pick(entry.ref, showHistory: false) } }
                            }
                            ForEach(data?.commits ?? []) { commit in
                                Circle().fill(green).frame(width: 5, height: 5)
                                    .position(x: Self.x(commit.date, width: geometry.size.width, start: start, end: end), y: y)
                                    .help(BranchHistoryText.commit(commit))
                                    .onTapGesture { Task { await model.pick(entry.ref, showHistory: false) } }
                            }
                            if let data, data.commitCount > data.commits.count {
                                Text("+\(data.commitCount - data.commits.count) more").font(.caption2).foregroundStyle(.secondary)
                                    .position(x: geometry.size.width - 48, y: y - 11)
                            }
                        }

                    }
                }.frame(minWidth: 160, maxWidth: .infinity, minHeight: height, maxHeight: height)
        }.frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
    }

    nonisolated private static func x(_ date: Date, width: CGFloat, start: Date, end: Date) -> CGFloat {
        let fraction = min(1, max(0, date.timeIntervalSince(start) / max(1, end.timeIntervalSince(start))))
        return 12 + CGFloat(fraction) * max(1, width - 24)
    }
    private func tooltip(_ entry: BranchMapEntry, data: BranchTimelineEntry?) -> String {
        var text = BranchHistoryText.plain(entry.name) + "\n" + BranchHistoryText.counts(entry)
        if let fork = data?.fork { text += "\nFork: " + BranchHistoryText.commit(fork) }
        if model.family?.origins[entry.ref]?.isCertain == false { text += "\nParent inferred from shared commit history." }
        if let data, data.problem == nil, data.fork != nil { text += "\n\(data.commitCount) commits since this fork" }
        if let problem = data?.problem ?? entry.metrics.problem { text += "\n" + BranchHistoryText.plain(problem) }
        return text
    }
}

/// The date scale stays visible while branch lanes scroll below it.
struct BranchTimelineAxis: View {
    let model: BranchMapModel
    var body: some View {
        let dates = model.rows.compactMap { $0.metrics.tip?.date } + model.timeline.values.compactMap { $0.fork?.date }
        let first = (dates.min() ?? Date()).addingTimeInterval(-86400)
        let last = (dates.max() ?? Date()).addingTimeInterval(86400)
        HStack(spacing: 12) {
            Text("◇ Fork · ● Commit").frame(width: 170, alignment: .leading)
            HStack {
                Text(first, format: .dateTime.month(.abbreviated).day().year())
                Spacer(minLength: 0)
                Text(last, format: .dateTime.month(.abbreviated).day().year())
            }.padding(.horizontal, 12)
        }.font(.caption).foregroundStyle(.secondary)
            .help("Dates span the shared timeline. Parent edges may be inferred from shared commit history; hover a lane for its source.")
    }
}
