import CleanAppModel
import SwiftUI

/// The light-clean sheet after it ran: each folder deleted, refused (with why) or failed, and the space freed,
/// measured from the disk.
struct LightCleanReportView: View {
    let report: LightCleanReport
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(report.summary)
                .font(.title2.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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
            Text(LightCleanConfirmation.nextTimeLine)
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
    let outcome: LightCleanOutcome

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WorktreeHeader(
                repoName: outcome.item.repoName, branchText: outcome.item.branchText, kind: outcome.item.worktree.kind,
                path: outcome.item.worktree.path, sizeText: outcome.freedBytes.map { "freed \(DisplayText.bytes($0))" }
            )
            if let error = outcome.error {
                Label("Nothing was deleted: \(error)", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
            ForEach(outcome.folders) { folder in
                FolderResultView(folder: folder)
            }
            ForEach(outcome.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FolderResultView: View {
    let folder: LightCleanOutcome.Folder

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.relativePath)
                Text(detail).font(.callout).foregroundStyle(detailColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detail: String {
        switch folder.status {
        case .deleted(let freed):
            "Deleted. Freed \(DisplayText.bytes(freed)) (estimate \(DisplayText.bytes(folder.estimatedBytes)))."
        case .refused(let why): "Refused, left alone: \(why)"
        case .failed(let message): "Failed: \(message)"
        }
    }

    private var icon: String {
        switch folder.status {
        case .deleted: "checkmark.circle.fill"
        case .refused: "arrow.triangle.2.circlepath.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch folder.status {
        case .deleted: .green
        case .refused: .orange
        case .failed: .red
        }
    }

    private var detailColor: Color {
        switch folder.status {
        case .deleted: .secondary
        case .refused: .orange
        case .failed: .red
        }
    }
}
