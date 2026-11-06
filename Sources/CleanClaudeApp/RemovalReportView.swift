import CleanAppModel
import SwiftUI

/// The removal sheet after it ran: each item's result and the space freed, measured from the disk.
struct RemovalReportView: View {
    let report: RemovalReport
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(report.summary)
                .font(.title2.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(report.outcomes) { outcome in
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
            Image(systemName: outcome.removed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(outcome.removed ? .green : .red)
            VStack(alignment: .leading, spacing: 3) {
                ItemHeader(item: outcome.item)
                if outcome.removed {
                    Text("Removed. Freed \(DisplayText.bytes(outcome.freedBytes)) "
                        + "(estimate \(DisplayText.bytes(outcome.item.estimatedBytes))).")
                } else if let error = outcome.error {
                    Text("Not removed: \(error)")
                        .foregroundStyle(.red)
                }
                ForEach(outcome.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
