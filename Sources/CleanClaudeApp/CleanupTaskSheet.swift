import CleanAppModel
import SwiftUI

/// The same sheet stays live while a queued task starts, progresses, stops or finishes.
struct CleanupTaskSheet: View {
    @Bindable var task: CleanupTask
    let queue: CleanupQueue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: task.isPending ? task.title : CleanupPresentation.headline(task.measuredFreedBytes), subtitle: subtitle)
            if task.state == .running || !task.isPending {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: Double(task.completedCount), total: Double(max(1, task.items.count)))
                        .tint(task.hasProblems ? Palette.orange : Palette.green)
                    HStack {
                        Text("\(task.completedCount) of \(task.items.count) \(task.unit) finished")
                        Spacer()
                        Text("\(DisplayText.bytes(task.measuredFreedBytes)) freed · estimate: \(task.estimatedSizeText)")
                    }
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    if task.hasCompleteEstimate {
                        ProgressView(value: Double(min(task.measuredFreedBytes ?? 0, task.estimatedBytes)),
                                 total: Double(max(1, task.estimatedBytes)))
                        .tint(Palette.green)
                        .accessibilityLabel("Measured space freed compared with the estimate")
                    }
                }
            }
            if let reason = task.waitingReason, task.isPending {
                Label(reason + " Bonsai will try again shortly.", systemImage: "clock")
                    .font(.callout).foregroundStyle(Palette.blue)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(displayItems) { item in
                        CleanupProgressRow(item: item)
                        Divider()
                    }
                }
            }
            .frame(minHeight: 150, maxHeight: 380)
            HStack {
                if task.state == .running {
                    Button(task.stopRequested ? "Stopping after this item…" : "Stop after this item") { queue.stop(task) }
                        .disabled(task.stopRequested)
                } else if task.isPending {
                    Button("Cancel task") { queue.cancel(task) }
                }
                Spacer()
                Button(task.isPending ? "Hide" : "Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                Button("Hide") { dismiss() }.keyboardShortcut(.cancelAction).hidden().frame(width: 0)
            }
        }
        .padding(24)
        .frame(width: 720)
    }

    private var displayItems: [CleanupItem] {
        task.isPending ? task.items : task.items.filter { $0.state == .done } + task.items.filter { $0.state != .done }
    }

    private var subtitle: String {
        switch task.state {
        case .queued, .waiting:
            return "Place \(queue.place(of: task) ?? 1) in the queue · \(task.countText) · estimate: \(task.estimatedSizeText)"
        case .running: return task.stopRequested ? "Finishing the current item; the rest will be left alone." : "You can hide this and keep working."
        default: return task.summary
        }
    }
}
