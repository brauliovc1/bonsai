import CleanAppModel
import SwiftUI

/// Shared by the main window and menu window. Progress belongs to the app even while both are hidden.
struct CleanupActivityView: View {
    @Bindable var queue: CleanupQueue
    var compact = false
    @State private var showsQueue = false

    var body: some View {
        if let text = queue.activityText {
            HStack(spacing: 8) {
                Button { queue.selectedTask = queue.current } label: {
                    Label(text, systemImage: "scissors")
                        .lineLimit(compact ? 3 : 1)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Open cleanup progress")
                Button { showsQueue.toggle() } label: {
                    Image(systemName: "list.bullet")
                }
                .buttonStyle(.borderless)
                .help("Show cleanup queue")
                .popover(isPresented: $showsQueue) { CleanupQueuePopover(queue: queue) }
            }
            .font(.callout)
            .monospacedDigit()
            .padding(10)
            .background(Palette.tint(.blue), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
