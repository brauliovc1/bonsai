import AppKit
import CleanCore

/// This is constructed only by the app. Tests and render harnesses receive a fake or the unavailable default.
@MainActor
struct FinderTrashEmptier: TrashEmptier {
    func empty() async throws {
        guard let script = NSAppleScript(source: "tell application \"Finder\" to empty trash") else {
            throw TrashEmptyError.failed("Could not prepare the request to Finder.")
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -1743 {
                throw TrashEmptyError.automationDenied
            }
            throw TrashEmptyError.failed(error[NSAppleScript.errorMessage] as? String ?? "Finder could not empty the Trash.")
        }
    }
}
