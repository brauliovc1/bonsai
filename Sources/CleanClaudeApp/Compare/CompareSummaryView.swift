import CleanAppModel
import CleanCore
import SwiftUI

struct CompareSummaryView: View {
    let snapshot: CompareSnapshot
    @State private var showsDetails = false

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    Text("\(snapshot.range.commits.count) commits · \(snapshot.files.count) files").font(.headline)
                    Text("+\(snapshot.additions)").foregroundStyle(Palette.green)
                    Text("−\(snapshot.deletions)").foregroundStyle(Palette.red)
                }.monospacedDigit()
                Text("\(snapshot.range.ahead) ahead · \(snapshot.range.behind) behind \(baseLabel)")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if snapshot.range.compare.isWorktree {
                    Text("Merge check uses committed changes").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button { showsDetails.toggle() } label: {
                StatusChip(words: StatusWords(snapshot.merge.message(base: baseLabel), tone, symbol: icon))
            }.buttonStyle(.plain)
                .popover(isPresented: $showsDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(snapshot.merge.message(base: baseLabel)).font(.headline)
                        ForEach(snapshot.merge.files, id: \.self) { Text($0).font(.system(.body, design: .monospaced)) }
                        if let detail = snapshot.merge.detail { Text(detail).textSelection(.enabled) }
                        if snapshot.range.compare.isWorktree { Text("The merge check uses committed changes. Unsaved files are shown in Files.").foregroundStyle(.secondary) }
                    }.padding(18).frame(maxWidth: 440)
                }
        }.padding(.horizontal, 18).padding(.bottom, 16)
    }
    private var baseLabel: String {
        let name = snapshot.range.base
        for prefix in ["refs/heads/", "refs/remotes/", "refs/tags/"] where name.hasPrefix(prefix) {
            return String(name.dropFirst(prefix.count))
        }
        return name
    }
    private var tone: CleanAppModel.StatusTone {
        switch snapshot.merge.state { case .clean: .green; case .conflicts: .orange; case .unavailable: .grey }
    }
    private var icon: String {
        switch snapshot.merge.state { case .clean: "checkmark.circle"; case .conflicts: "exclamationmark.triangle"; case .unavailable: "questionmark.circle" }
    }
}
