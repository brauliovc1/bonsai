import CleanAppModel
import CleanCore
import SwiftUI

struct CompareCommitsView: View {
    let model: CompareModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                Button("All changes") { Task { await model.selectCommit(nil) } }.padding(12)
                ForEach(model.snapshot?.range.commits ?? []) { commit in
                    Button { Task { await model.selectCommit(commit.sha) } } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(DiffText.decode(Data(commit.subject.utf8))).font(.callout.weight(.medium)).lineLimit(3)
                            Text("\(commit.author) · \(DisplayText.timeAgo(commit.date, now: model.app.environment.now()))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(String(commit.sha.prefix(8))).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }.buttonStyle(.plain)
                        .background(model.selectedCommit == commit.sha ? Palette.tint(.blue) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
            }.padding(4)
        }
    }
}
