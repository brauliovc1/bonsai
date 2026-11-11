import CleanAppModel
import SwiftUI

/// A locked row remains an entry point to its task, rather than opening another confirmation.
struct QueuedItemStatus: View {
    let queue: CleanupQueue
    let resource: String

    var body: some View {
        if let words = queue.status(for: resource) {
            Button { queue.open(resource) } label: { StatusChip(words: words) }
                .buttonStyle(.plain)
                .help(CleanupQueue.lockedHelp)
        }
    }
}
