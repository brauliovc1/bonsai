import AppKit
import CleanCore

/// The app's half of "is Cursor running" (PLAN §4.6): NSWorkspace lists an application with Cursor's bundle id.
/// ps finds Cursor by its executable path; this also catches a copy installed under another name.
enum CursorAppProbe {
    @Sendable static func isRunning() async -> Bool {
        await MainActor.run {
            !NSRunningApplication.runningApplications(withBundleIdentifier: ToolCacheCatalog.cursorBundleID).isEmpty
        }
    }
}
