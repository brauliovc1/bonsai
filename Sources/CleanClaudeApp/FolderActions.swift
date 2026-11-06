import AppKit

/// Finder, Terminal and pasteboard actions on folders. They take URLs and hand them to NSWorkspace, so
/// paths reach Finder and Terminal exactly as stored (no command line in between).
enum FolderActions {
    static func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func openInTerminal(_ urls: [URL]) {
        guard !urls.isEmpty,
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    /// One path per line.
    static func copy(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
    }

    /// True when something is at `url` (a missing worktree folder can't be revealed or opened).
    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
