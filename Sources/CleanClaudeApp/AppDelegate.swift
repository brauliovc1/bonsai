import AppKit
import CleanAppModel

/// Quit waits for a cleanup in progress: the removal running finishes and is logged, the rest of the run is
/// left alone, then the app quits. Without this, `git worktree remove` would finish deleting after the app
/// exited, with nothing logged and no Restore.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the App at launch.
    static var app: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let app = Self.app else { return .terminateNow }
        guard app.isCleaningUp || app.cleanupQueue.hasPending else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = app.cleanupQueue.quitMessage
        alert.informativeText = "The current item will finish and be logged before Bonsai quits."
        alert.addButton(withTitle: "Quit after current item")
        alert.addButton(withTitle: "Keep cleaning")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        Task {
            await app.prepareToQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
