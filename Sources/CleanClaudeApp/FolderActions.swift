import AppKit
import CleanAppModel

/// Finder, Terminal and pasteboard actions on folders. They take URLs and hand them to NSWorkspace, so
/// paths reach Finder and Terminal exactly as stored (no command line in between). Only real folders
/// (`FolderCheck.isRealDirectory`) are revealed or opened: Terminal runs a file it is asked to open.
enum FolderActions {
    static func reveal(_ urls: [URL]) {
        let folders = urls.filter(FolderCheck.isRealDirectory)
        guard !folders.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(folders)
    }

    static func openInTerminal(_ urls: [URL]) {
        let folders = urls.filter(FolderCheck.isRealDirectory)
        guard !folders.isEmpty,
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        else { return }
        NSWorkspace.shared.open(folders, withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    /// One path per line.
    static func copy(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
    }
}
