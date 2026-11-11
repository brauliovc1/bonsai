import CleanAppModel
import SwiftUI

/// The light-clean sheet after it ran: each folder deleted, refused (with why) or failed, and the space freed,
/// measured from the disk.
struct LightCleanReportView: View {
    let report: LightCleanReport
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeading(title: report.headline, subtitle: report.summary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if report.deletedCount > 0 { Text("Done").font(.headline) }
                    ForEach(report.outcomes.filter { $0.deletedCount > 0 }) { outcome in
                        OutcomeView(outcome: outcome, showDeleted: true)
                    }
                    if report.outcomes.contains(where: { $0.error != nil || $0.folders.contains { !$0.isDeleted } }) {
                        Text("Skipped").font(.headline).padding(.top, 4)
                    }
                    ForEach(report.outcomes.filter { $0.error != nil || $0.folders.contains { !$0.isDeleted } }) { outcome in
                        OutcomeView(outcome: outcome, showDeleted: false)
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
    let showDeleted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SheetItemHeader(title: outcome.item.repoName, detail: outcome.item.branchText, path: outcome.item.worktree.path)
            if !showDeleted, let error = outcome.error {
                Label("Nothing was deleted: \(error)", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(Palette.orange)
            }
            ForEach(outcome.folders.filter { $0.isDeleted == showDeleted }) { folder in
                FolderResultView(folder: folder)
            }
            ForEach(showDeleted || outcome.deletedCount == 0 ? outcome.warnings : [], id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Palette.orange)
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
        case .refused(let why): "Left alone: \(why)"
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
        case .deleted: Palette.green
        case .refused: Palette.orange
        case .failed: Palette.orange
        }
    }

    private var detailColor: Color {
        switch folder.status {
        case .deleted: .secondary
        case .refused: Palette.orange
        case .failed: Palette.orange
        }
    }
}
