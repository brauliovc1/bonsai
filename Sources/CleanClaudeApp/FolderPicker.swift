import AppKit

/// The system's open panel, for choosing scan roots: folders only, several at once.
@MainActor
enum FolderPicker {
    /// The folders the user picked, or none when they cancelled.
    static func chooseFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Add"
        panel.message = "Choose folders that hold your git repos."
        return panel.runModal() == .OK ? panel.urls : []
    }
}
