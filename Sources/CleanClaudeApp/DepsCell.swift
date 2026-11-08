import CleanAppModel
import SwiftUI

/// The Deps cell: a spinner while this row is being measured, else the size light clean could delete.
struct DepsCell: View {
    let row: WorktreeRow

    var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            if row.dependencies.isMeasuring {
                ProgressView().controlSize(.mini)
            } else {
                Text(row.dependencyText).monospacedDigit()
            }
        }
        .help("What light clean could delete here: node_modules, build output and other regenerable folders")
    }
}
