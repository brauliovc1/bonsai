import CleanAppModel
import SwiftUI

/// A name, optional detail, path and estimated size shared by sheet entries.
struct SheetItemHeader: View {
    let title: String
    var detail: String?
    let path: String
    var bytes: Int64?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).fontWeight(.semibold)
                if let detail { Text(detail).foregroundStyle(.secondary) }
                Spacer(minLength: 8)
                if let bytes { SizeText(bytes: bytes) }
            }
            Text(path).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).help(path).textSelection(.enabled)
        }
    }
}
