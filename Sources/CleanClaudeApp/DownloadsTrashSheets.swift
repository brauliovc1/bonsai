import CleanAppModel
import SwiftUI

struct DownloadsMoveSheet: View {
    @Bindable var model: DownloadsTrashModel
    let confirmation: DownloadsConfirmation

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeading(title: confirmation.title)
            Text("You can put these files back from Recently removed while they remain in the Trash. Space is freed only when you empty the Trash.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(confirmation.files) { file in
                        HStack {
                            Text(file.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(DisplayText.bytes(file.bytes)).monospacedDigit()
                        }.font(.callout)
                    }
                }
            }.frame(maxHeight: 240)
            HStack {
                Spacer()
                Button("Cancel") { model.moveConfirmation = nil }.keyboardShortcut(.cancelAction)
                Button(confirmation.buttonTitle) { model.queueMove(confirmation) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 600)
    }
}

struct EmptyTrashSheet: View {
    @Bindable var model: DownloadsTrashModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeading(title: "Empty Trash?")
            Text(model.emptyConfirmation).font(.callout)
            Text("Finder handles this request. Files emptied from the Trash cannot be put back with Bonsai.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { model.isShowingEmptySheet = false }.keyboardShortcut(.cancelAction)
                Button("Empty Trash", role: .destructive) { model.confirmEmptyTrash() }
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 600)
    }
}
