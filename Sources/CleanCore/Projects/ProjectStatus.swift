/// Where a project stands for a bulk light clean (PLAN §4.5), from its idle days and the process check.
public enum ProjectStatus: Sendable, Hashable {
    /// Idle at least the threshold and nothing stops a clean: "Select all idle" picks it.
    case ready
    /// Worked on fewer days ago than the threshold; can still be cleaned when picked by hand.
    case recent(days: Int)
    /// The idle clock couldn't tell (§4.3); shown, never picked by "Select all idle".
    case idleUnknown
    /// A process has its working folder inside, or processes couldn't be checked: nothing is cleaned now.
    case blocked(LightCleanSkipReason)

    public init(idleDays: Int?, blocker: LightCleanSkipReason?, threshold: Int) {
        if let blocker {
            self = .blocked(blocker)
        } else if let idleDays {
            self = idleDays >= threshold ? .ready : .recent(days: idleDays)
        } else {
            self = .idleUnknown
        }
    }

    /// For the Status column: "Ready", "Recent", "Idle unknown", "In use (node)".
    public var label: String {
        switch self {
        case .ready: "Ready"
        case .recent: "Recent"
        case .idleUnknown: "Idle unknown"
        case .blocked(let reason): reason.label.prefix(1).uppercased() + reason.label.dropFirst()
        }
    }

    /// One plain sentence for tooltips and the CLI.
    public var sentence: String {
        switch self {
        case .ready: "Idle long enough; nothing is running inside."
        case .recent(let days): Self.recentNote(days: days)
        case .idleUnknown: "Bonsai couldn't tell when you last worked here, so Select all idle leaves it out."
        case .blocked(let reason): reason.sentence
        }
    }

    public var isReady: Bool { self == .ready }

    public var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }

    /// "You worked here 3 days ago; it will need a reinstall."
    public static func recentNote(days: Int) -> String {
        let ago = switch days {
        case 0: "today"
        case 1: "1 day ago"
        default: "\(days) days ago"
        }
        return "You worked here \(ago); it will need a reinstall."
    }
}
