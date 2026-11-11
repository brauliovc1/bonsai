import SwiftUI

/// All confirmations and reports share the page kit's heading and spacing.
struct SheetHeading: View {
    let title: String
    var subtitle: String?
    var body: some View {
        PageHeader(title: title, subtitle: subtitle)
    }
}
