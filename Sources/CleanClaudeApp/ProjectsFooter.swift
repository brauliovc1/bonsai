import CleanAppModel
import CleanCore
import SwiftUI

/// The strip under the Project folders table: scan state, the Claude/Cursor worktrees left out (with a button
/// to Worktrees), and the idle and overall totals.
struct ProjectsFooter: View {
    let model: ProjectsModel
    let showWorktrees: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if model.isScanning {
                ProgressView().controlSize(.small)
                Text(Self.progressText(model))
            } else if let date = model.lastScanAt {
                TimelineView(.everyMinute) { _ in
                    Text("Measured \(date, format: .relative(presentation: .named))")
                }
            }
            if let leftOut = model.leftOutText {
                Button(leftOut, action: showWorktrees)
                    .buttonStyle(.link)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .help("Claude and Cursor worktrees are better removed whole on the Worktrees screen")
            }
            Spacer()
            Text("Idle \(model.threshold)+ days: \(DisplayText.bytes(model.idleTotal.bytes)) in \(DisplayText.projects(model.idleTotal.count))")
                .monospacedDigit()
            Text("All: \(DisplayText.bytes(model.allTotal.bytes)) in \(DisplayText.projects(model.allTotal.count))")
                .monospacedDigit()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// What a running scan is doing.
    static func progressText(_ model: ProjectsModel) -> String {
        switch model.progress {
        case .looking(let completed, let total): "Looking at checkouts (\(completed) of \(total))…"
        case .measuring(let completed, let total): "Measuring folders (\(completed) of \(total))…"
        case nil: model.app.isScanning ? DisplayText.progress(model.app.progress) : "Looking at checkouts…"
        }
    }
}
