/// Why a removal that passed every check was stopped right before git ran: the run it belonged to was
/// stopped. Nothing is touched or logged.
public enum RemovalStop: String, Sendable, Codable, Hashable {
    /// Auto mode was turned off during the run.
    case turnedOff
    /// The rules the plan was made with changed: the Claude setting, the idle threshold, or the report-only
    /// window (auto mode turned off and on again).
    case rulesChanged
    /// The app is quitting: it finishes the removal in progress, then stops.
    case quitting

    public var sentence: String {
        switch self {
        case .turnedOff: "Auto mode was turned off, so the run stopped."
        case .rulesChanged: "The rules changed, so the run stopped."
        case .quitting: "The app quit, so the run stopped."
        }
    }
}
