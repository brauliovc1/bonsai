import Foundation

/// Successes disappear; refusals, failures, stopped tasks and log warnings stay until dismissed.
@MainActor
public struct CleanupToast: Identifiable {
    public let id = UUID()
    public let task: CleanupTask
    public var needsReview: Bool { task.hasProblems || task.state == .stopped }
    public var text: String { task.summary }
    public var actionTitle: String { needsReview ? "Review" : "Details" }
}
