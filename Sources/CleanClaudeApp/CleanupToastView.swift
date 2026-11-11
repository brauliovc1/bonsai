import CleanAppModel
import SwiftUI

struct CleanupToastView: View {
    let toast: CleanupToast
    let queue: CleanupQueue

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.needsReview ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.needsReview ? Palette.orange : Palette.green)
            Text(toast.text).fontWeight(.medium).monospacedDigit()
            Spacer()
            Button(toast.actionTitle) { queue.selectedTask = toast.task }
            Button { queue.dismissToast(toast.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).help("Dismiss cleanup result")
        }
        .font(.callout)
        .padding(12)
        .background(Palette.tint(toast.needsReview ? .orange : .green), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.stroke))
    }
}
