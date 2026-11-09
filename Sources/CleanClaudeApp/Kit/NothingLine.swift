import SwiftUI

/// The one line that stands for every category with nothing to do: "Nothing to clean in Xcode DerivedData or
/// Simulators." Empty categories collapse into it instead of showing as rows of zeros.
struct NothingLine: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "checkmark.circle").foregroundStyle(Palette.green)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Nothing line") {
    NothingLine(text: "Nothing to clean in Xcode DerivedData or Simulators.")
        .padding()
        .frame(width: 600)
}
