import AppKit
import CleanAppModel

/// Finder, open and pasteboard actions on one file of a worktree's file list. Read-only: nothing here changes,
/// discards or checks out a file. "Open" never runs anything (`FileOpening`).
enum FileActions {
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func open(_ url: URL) {
        switch FileOpening.way(for: url) {
        case .defaultApp:
            NSWorkspace.shared.open(url)
        case .asText:
            guard let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
                reveal(url)
                return
            }
            NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
        case .finderOnly:
            // No Open is offered for these; if asked anyway, Finder only shows it.
            reveal(url)
        }
    }
}
