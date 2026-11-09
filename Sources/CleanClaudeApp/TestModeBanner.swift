import CleanAppModel
import SwiftUI

/// A slim strip saying the app scans only the folders in BONSAI_SCAN_ROOTS (a demo world), so its
/// repos aren't taken for the Mac's own. A long folder is cut in the middle; the words around it stay.
struct TestModeBanner: View {
    let app: AppModel

    var body: some View {
        if let folders = app.testModeFolders, let text = app.testModeText {
            HStack(spacing: 6) {
                Image(systemName: "testtube.2").foregroundStyle(.orange)
                TestModeSentence(folders: folders, suffix: " (BONSAI_SCAN_ROOTS)")
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.orange.opacity(0.12), ignoresSafeAreaEdges: [])
            .help(text)
        }
    }
}

/// "Test mode: scanning only <folders><suffix>" on one line, the folders giving way first.
struct TestModeSentence: View {
    let folders: String
    var suffix = ""

    var body: some View {
        HStack(spacing: 0) {
            Text("Test mode: ").fontWeight(.semibold)
            Text("scanning only ")
            Text(folders).truncationMode(.middle).layoutPriority(-1)
            if !suffix.isEmpty { Text(suffix).foregroundStyle(.secondary) }
        }
        .lineLimit(1)
    }
}
