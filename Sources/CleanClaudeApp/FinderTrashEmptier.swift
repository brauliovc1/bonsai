import AppKit
import CleanCore

/// This is constructed only by the app. Tests and render harnesses receive a fake or the unavailable default.
struct FinderTrashEmptier: TrashEmptier {
    private static let worker = DispatchQueue(label: "bonsai.finder-trash", qos: .userInitiated)

    func empty() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            Self.worker.async {
                // Each script is created, executed and released on this one serial worker. Never block
                // the main actor or a cooperative pool thread while Finder is handling its contents.
                autoreleasepool {
                    do { try Self.askFinder(); continuation.resume() }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }
    }

    private static func askFinder() throws {
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
