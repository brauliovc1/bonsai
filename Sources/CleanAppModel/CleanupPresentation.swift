import CleanCore
import Foundation

/// Shared wording for confirmations and measured cleanup reports.
public enum CleanupPresentation {
    public static let busyReason = "another Bonsai cleanup is running"
    public static func title(_ action: String, count: Int, noun: String, plural: String? = nil, bytes: Int64?) -> String {
        title(action, count: count, noun: noun, plural: plural, sizes: [bytes])
    }

    public static func title(_ action: String, count: Int, noun: String, plural: String? = nil, sizes: [Int64?]) -> String {
        guard count > 0 else { return "Nothing to " + action.lowercased() }
        let what = count == 1 ? noun : (plural ?? noun + "s")
        return "\(action) \(count) \(what) (\(estimate(sizes)))?"
    }

    /// Keep missing measurements distinct from known zero and partially measured totals.
    public static func estimate(_ sizes: [Int64?]) -> String {
        let known = sizes.compactMap { $0 }
        guard !known.isEmpty || sizes.isEmpty else { return "size unknown" }
        let amount = DisplayText.bytes(known.reduce(0, +))
        return known.count == sizes.count ? amount : "at least " + amount
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
