import SwiftUI

/// The top of a screen: a large title, one line under it, and the screen's primary action (or number) on the
/// right.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

#Preview("Page header") {
    PageHeader(title: "21.9 GB free of 460 GB", subtitle: "Macintosh HD") {
        Text("Bonsai can free about 140.2 GB").font(.title3.weight(.semibold)).foregroundStyle(Palette.green)
    }
    .padding()
    .frame(width: 760)
}
