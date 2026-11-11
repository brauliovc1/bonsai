import Foundation

/// A bounded registration snapshot that matched a completed source listing.
/// The final check is synchronous, so no new async work follows an owner's or device's last check.
struct QuickCleanSourceTicket: Sendable {
    let fence: QuickCleanSourceFence
    let snapshot: QuickCleanSourceSnapshot

    func problemNow() -> String? {
        do {
            guard try QuickCleanSourceSnapshot.capture(fence) == snapshot else {
                return "Source locations changed during the last safety check; nothing was cleaned. Refresh Quick clean."
            }
            return nil
        } catch { return "Source locations could not be verified at cleanup: \(error)" }
    }
}

struct QuickCleanSourceValidation: Sendable {
    let problem: String?
    let ticket: QuickCleanSourceTicket?
    static func refused(_ reason: String) -> Self { Self(problem: reason, ticket: nil) }
    func problemNow() -> String? {
        if let problem { return problem }
        guard let ticket else { return "Source locations could not be verified." }
        return ticket.problemNow()
    }
}
