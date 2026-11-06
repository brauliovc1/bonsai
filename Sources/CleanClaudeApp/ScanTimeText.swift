import CleanAppModel
import SwiftUI

/// "Last scan: 3 minutes ago", or what the running scan is doing.
struct ScanTimeText: View {
    let app: AppModel

    var body: some View {
        if app.isScanning {
            Text(DisplayText.progress(app.progress))
        } else if let date = app.lastScanAt {
            TimelineView(.everyMinute) { _ in
                Text("Last scan: \(date, format: .relative(presentation: .named))")
            }
        } else {
            Text("Not scanned yet")
        }
    }
}
