import AppKit
import CleanAppModel
import SwiftUI

/// The Overview's last row: whether auto clean is on, what it does or when it runs next, and a button to its
/// settings ("Turn on…" opens them on the auto mode tab).
struct AutoCleanRow: View {
    let line: AutoCleanLine
    let settings: SettingsModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title).fontWeight(.medium)
                Text(line.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if line.isRunning {
                ProgressView().controlSize(.small)
            }
            Button(line.buttonTitle) {
                settings.selectedTab = .autoMode
                openSettings()
                // The app has no Dock icon until a window opens; bring Settings forward.
                NSApp.activate()
            }
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.stroke))
    }
}
