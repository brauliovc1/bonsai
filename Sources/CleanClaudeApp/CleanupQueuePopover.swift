import CleanAppModel
import SwiftUI

struct CleanupQueuePopover: View {
    let queue: CleanupQueue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cleanup queue").font(.headline)
            if queue.pending.isEmpty { NothingLine(text: "Everything is finished.") }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(queue.pending + Array(queue.tasks.filter { !$0.isPending }.reversed())) { task in
                        HStack {
                            Button {
                                dismiss()
                                queue.selectedTask = task
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title).fontWeight(.medium)
                                    Text(task.isPending ? (task.state == .running ? task.progressText : "Queued · \(task.countText)") : task.summary)
                                        .font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let reason = task.waitingReason { Text(reason).font(.caption).foregroundStyle(Palette.blue) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if task.state == .running {
                                Button(task.stopRequested ? "Stopping…" : "Stop after this item") { queue.stop(task) }
                                    .disabled(task.stopRequested)
                            } else if task.isPending {
                                Button("Cancel task") { queue.cancel(task) }
                            }
                        }
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .padding(16)
        .frame(width: 480)
    }
}
