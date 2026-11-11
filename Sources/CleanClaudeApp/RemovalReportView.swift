import CleanAppModel
import SwiftUI

/// The removal sheet after it ran: each item's result and the space freed, measured from the disk.
struct RemovalReportView: View {
    let report: RemovalReport
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeading(title: report.headline, subtitle: report.summary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if report.outcomes.contains(where: \.removed) { Text("Done").font(.headline) }
                    ForEach(report.outcomes.filter(\.removed)) { outcome in
                        OutcomeView(outcome: outcome)
                    }
                    if report.outcomes.contains(where: { !$0.removed }) { Text("Skipped").font(.headline).padding(.top, 4) }
                    ForEach(report.outcomes.filter { !$0.removed }) { outcome in
                        OutcomeView(outcome: outcome)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Text("Freed space is measured from the disk, so it can be lower than the estimate "
                + "(files shared with other folders stay until the last copy goes).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(RemovalConfirmation.keptLine)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct OutcomeView: View {
    let outcome: RemovalOutcome

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(outcome.removed ? Palette.green : Palette.orange)
            VStack(alignment: .leading, spacing: 3) {
                SheetItemHeader(title: outcome.item.repoName, detail: outcome.item.branchText, path: outcome.item.worktree.path, bytes: outcome.item.estimatedBytes)
                if outcome.removed {
                    Text("Removed. Freed \(DisplayText.bytes(outcome.freedBytes)) "
                        + "(estimate \(DisplayText.bytes(outcome.item.estimatedBytes))).")
                } else if let error = outcome.error {
                    Text(outcome.changedSinceConfirmed ? error : "Not removed: \(error)")
                        .foregroundStyle(Palette.orange)
                }
                ForEach(outcome.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Palette.orange)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var icon: String {
        if outcome.removed { return "checkmark.circle.fill" }
        return outcome.changedSinceConfirmed ? "arrow.triangle.2.circlepath.circle.fill" : "xmark.octagon.fill"
    }
}
