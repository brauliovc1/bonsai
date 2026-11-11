import CleanCore
import Foundation

/// Shared wording for confirmations and measured cleanup reports.
public enum CleanupPresentation {
    public static let busyReason = "another Bonsai cleanup is running"
    public static func title(_ action: String, count: Int, noun: String, plural: String? = nil, bytes: Int64?) -> String {
        guard count > 0 else { return "Nothing to " + action.lowercased() }
        let what = count == 1 ? noun : (plural ?? noun + "s")
        return "\(action) \(count) \(what) (\(DisplayText.bytes(bytes)))?"
    }

    public static func button(_ action: String, count: Int) -> String { "\(action) \(count)" }

    public static func headline(_ bytes: Int64?) -> String {
        bytes.map { "Freed \(DisplayText.bytes($0))" } ?? "Freed space unavailable"
    }
    public static func reason(_ reason: LightCleanSkipReason) -> String {
        switch reason {
        case .symlink: "It is a symbolic link. Bonsai leaves links alone."
        case .notACandidate(let why): "It isn't a dependency or build folder Bonsai can clean here: \(why)."
        default: reason.sentence
        }
    }

    static func error(_ error: any Error) -> String {
        guard let error = error as? LightCleanError else { return "\(error)" }
        switch error {
        case .unavailable(let why): return "Couldn't clean dependencies: \(why)"
        case .wrongFolder(let why): return reason(.wrongFolder(why))
        case .inUse(let processes): return reason(.inUse(processes))
        case .inUseUnknown(let why): return reason(.inUseUnknown(why))
        case .changed, .notRegistered: return error.description
        }
    }

}
