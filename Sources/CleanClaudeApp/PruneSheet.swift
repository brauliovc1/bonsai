import CleanAppModel
import CleanCore
import SwiftUI

/// "Clean up missing folders": lists, per repo with a missing folder among the shown rows, every record
/// `git worktree prune` would clear, and clears only those. Afterwards, what happened per repo.
struct PruneSheet: View {
    let model: WorktreesModel

    var body: some View {
        Group {
            if let outcomes = model.pruneOutcomes {
                results(outcomes)
            } else if let plan = model.prunePlan {
                confirmPage(plan)
            } else {
                SheetProgress(text: "Reading what git would clear…") { model.dismissPrune() }
            }
        }
        .padding(20)
        .frame(width: 600)
        .frame(minHeight: 260, idealHeight: 400, maxHeight: 640)
        .interactiveDismissDisabled(model.isPruning)
    }

    private func confirmPage(_ plan: PrunePlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeading(title: plan.title)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.repos) { repo in
                        RepoPlanView(repo: repo)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Text("git forgets these worktrees (git worktree prune); their folders are already gone. "
                + "Branches are kept. Only the records listed here are cleared.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if model.isPruning {
                    ProgressView().controlSize(.small)
                    Text("Clearing…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { model.dismissPrune() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isPruning)
                if plan.entryCount > 0 {
                    Button(plan.buttonTitle, role: .destructive) { model.queuePrune(plan) }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.red)
                        .disabled(model.isPruning)
                }
            }
        }
    }

    private func results(_ outcomes: [PruneOutcome]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeading(title: "Cleared missing folder records")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(outcomes) { outcome in
                        Label(outcome.summary, systemImage: outcome.pruned.isEmpty ? "xmark.octagon" : "checkmark.circle")
                            .foregroundStyle(outcome.pruned.isEmpty ? Palette.orange : Palette.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Done") { model.dismissPrune() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// One repo of the plan: its records, or why it is left alone.
private struct RepoPlanView: View {
    let repo: PrunePlan.Repo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(repo.repoName).fontWeight(.semibold)
            ForEach(repo.entries, id: \.self) { entry in
                Label(PrunePlan.describe(entry), systemImage: "folder.badge.questionmark")
                    .textSelection(.enabled)
            }
            ForEach(repo.refusals, id: \.self) { refusal in
                Label("Left alone: \(refusal)", systemImage: "nosign").foregroundStyle(.secondary)
            }
            if let error = repo.error {
                Label("Left alone: \(error)", systemImage: "exclamationmark.triangle").foregroundStyle(Palette.orange)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
