import CleanAppModel
import SwiftUI

/// One captured preview, followed by one explicit cleanup confirmation.
struct QuickCleanSheet: View {
    @Bindable var model: QuickCleanModel

    var body: some View {
        Group {
            if let preview = model.preview {
                QuickCleanPreviewView(preview: preview, canConfirm: model.canConfirm, problem: model.problem,
                                      disabledReason: model.confirmationDisabledReason,
                                      refresh: { Task { await model.begin() } },
                                      confirm: { _ = model.confirm() }, cancel: { model.dismiss() })
            } else {
                QuickCleanStatusView(isPreparing: model.isPreparing, problem: model.problem,
                                     retry: { Task { await model.begin() } }, cancel: { model.dismiss() })
            }
        }
        .frame(width: 740)
        .frame(minHeight: 360, idealHeight: 620, maxHeight: 720)
    }
}
