import CleanAppModel
import CleanCore
import SwiftUI

/// The strip under the Project folders table: scan state, checkouts that couldn't be checked, the Claude/Cursor
/// worktrees left out (with a button to Worktrees), and the ready-to-clean and overall totals.
struct ProjectsFooter: View {
    let model: ProjectsModel
    let showWorktrees: () -> Void
    @State private var showingProblems = false

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
            if !model.problems.isEmpty {
                Button("\(DisplayText.folders(model.problems.count)) couldn't be checked") { showingProblems = true }
                    .buttonStyle(.link)
                    .foregroundStyle(Color.orange)
                    .help(model.problems.joined(separator: "\n"))
                    .popover(isPresented: $showingProblems) { problemList }
            }
            if let leftOut = model.leftOutText {
                Button(action: showWorktrees) {
                    Text(leftOut).lineLimit(1).truncationMode(.tail)
                }
                .buttonStyle(.link)
                .foregroundStyle(Color.accentColor)
                .help("Claude and Cursor worktrees are better removed whole on the Worktrees screen")
            }
            Spacer()
            Text("Ready to clean: \(DisplayText.bytes(model.idleTotal.bytes)) in \(DisplayText.projects(model.idleTotal.count))")
                .monospacedDigit()
                .help("The projects Select all idle picks: idle \(model.threshold) days or more, nothing running in them")
            Text("All: \(DisplayText.bytes(model.allTotal.bytes)) in \(DisplayText.projects(model.allTotal.count))")
                .monospacedDigit()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var problemList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.problems, id: \.self) { problem in
                    Text(problem).textSelection(.enabled)
                }
            }
            .padding(12)
        }
        .frame(width: 460)
        .frame(maxHeight: 300)
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
