import CleanAppModel
import CleanCore
import SwiftUI

struct BranchHistoryCard: View {
    let model: BranchMapModel
    let openWorktree: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: BranchHistoryText.name(model.selectedBranch ?? "Branch history"), subtitle: "Branch history · read-only")
            if model.isLoadingHistory { ProgressView("Reading branch history…").frame(maxWidth: .infinity).padding() }
            if let problem = model.historyProblem { ProblemBanner(text: BranchHistoryText.plain(problem)) }
            if let history = model.history {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        GroupedSection(title: "Cut from") {
                            if let parent = history.origin.parent {
                                HStack {
                                    Text(history.origin.isCertain ? "Cut from" : "Probably cut from")
                                    branchButton(parent)
                                    if let date = history.origin.date { Text(date, format: .dateTime.month(.abbreviated).day().year()) }
                                }.font(.callout)
                            } else { Text("The parent branch is unknown.").font(.callout) }
                            Text(BranchHistoryText.plain(history.origin.reason)).font(.callout).foregroundStyle(.secondary)
                            Text(history.origin.source == .reflog ? "Source: this Mac's local reflog. Reflogs expire." : "Source: shared commit history. This is an inference.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        GroupedSection(title: "Fork point") {
                            if let fork = history.forkPoint {
                                Text(BranchHistoryText.commit(fork)).font(.callout).textSelection(.enabled)
                                Text(forkSource(history.forkSource)).font(.caption).foregroundStyle(.secondary)
                            } else { Text("No common fork point could be found.").font(.callout) }
                        }
                        GroupedSection(title: "Merged") { mergeText(history) }
                        GroupedSection(title: "Branch family") {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(Array(history.parentChain.branches.reversed().enumerated()), id: \.offset) { index, branch in
                                    HStack(spacing: 8) {
                                        if index > 0 { Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary) }
                                        branchButton(branch)
                                    }.padding(.leading, CGFloat(index) * 10)
                                }
                            }
                            if let cycle = history.parentChain.cycleAt {
                                Label("A parent cycle returns to \(BranchHistoryText.name(cycle)).", systemImage: "exclamationmark.triangle")
                                    .font(.callout).foregroundStyle(Palette.orange)
                            }
                            if history.children.isEmpty { Text("No branches cut from this one were found.").font(.callout).foregroundStyle(.secondary) }
                            else {
                                Text("Branches cut from it").font(.callout.weight(.medium))
                                ForEach(history.children, id: \.self) { branchButton($0) }
                            }
                        }
                        GroupedSection(title: "Upstream and worktree") {
                            Text(BranchHistoryText.plain(history.upstream.summary)).font(.callout)
                            if let upstream = history.upstream.ref { Text(BranchHistoryText.name(upstream)).font(.callout).foregroundStyle(.secondary) }
                            if let path = history.worktree {
                                Button { openWorktree(path) } label: { Label("Show in Worktrees", systemImage: "folder") }
                                Text(BranchHistoryText.plain(path)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                        ForEach(history.problems, id: \.self) { ProblemBanner(text: BranchHistoryText.plain($0)) }
                    }.padding(.trailing, 4)
                }.frame(maxHeight: 520)
            }
        }.padding(18).frame(width: 600)
    }

    private func branchButton(_ ref: String) -> some View {
        Button(BranchHistoryText.name(ref)) { Task { await model.pick(ref) } }.buttonStyle(.link)
    }
    @ViewBuilder private func mergeText(_ history: BranchLineage) -> some View {
        switch history.merged.state {
        case .mergeCommit:
            if let commit = history.merged.commit {
                Text("Into \(BranchHistoryText.name(history.base)) on \(commit.date.formatted(date: .abbreviated, time: .omitted))").font(.callout)
                Text("\(commit.shortSHA) · \(BranchHistoryText.plain(commit.subject))").font(.callout).textSelection(.enabled)
            }
        case .changesInBase:
            Text("Its changes are already in \(BranchHistoryText.name(history.base)) (squashed or rebased).").font(.callout)
            Text("The integration date is unknown.").font(.caption).foregroundStyle(.secondary)
        case .notMerged: Text("Not merged into \(BranchHistoryText.name(history.base)).").font(.callout)
        case .unavailable:
            Text("Can't check this merge.").font(.callout)
            if let detail = history.merged.detail { Text(BranchHistoryText.plain(detail)).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func forkSource(_ source: BranchLineage.ForkSource) -> String {
        switch source {
        case .parentReflog: "Source: the parent's reflog (Git fork point)."
        case .mergeBase: "Source: the shared merge base."
        case .creationRecord: "Source: the commit recorded when this branch was created."
        case .unavailable: "The fork point is unavailable."
        }
    }
}
