import CleanCore
import Foundation

/// What happened to one confirmed tool-cache entry.
public struct CachesCleanOutcome: Identifiable, Sendable {
    public enum Status: Sendable, Hashable {
        /// `failures`: what couldn't be removed (the rest went). `freedBytes`: free space after minus before.
        case cleaned(removed: Int, freedBytes: Int64?, failures: [String])
        /// The check right before it said no (an owner started, a folder became a link…); nothing was touched.
        case refused(String)
        /// Its cleaning started and nothing could be removed.
        case failed([String])
    }

    public let item: CachesConfirmation.Item
    public let status: Status

    public var id: String { item.id }
    public var isCleaned: Bool {
        if case .cleaned = status { return true }
        return false
    }
}

/// The Tool caches sheet's second page.
public struct CachesCleanReport: Sendable {
    public let outcomes: [CachesCleanOutcome]
    /// Measured from the volume around each entry, summed; nil when nothing was cleaned or it couldn't be read.
    public let measuredFreedBytes: Int64?
    /// Things that went wrong after cleaning (a log entry not written).
    public let warnings: [String]

    public static let empty = CachesCleanReport(outcomes: [], measuredFreedBytes: nil, warnings: [])

    init(outcomes: [CachesCleanOutcome], measuredFreedBytes: Int64?, warnings: [String]) {
        self.outcomes = outcomes
        self.measuredFreedBytes = measuredFreedBytes
        self.warnings = warnings
    }

    /// `result` nil: another cleanup held the guard, so nothing ran (`busy` says why).
    init(items: [CachesConfirmation.Item], result: ToolCacheCleanResult?, busy: String) {
        guard let result else {
            self.init(
                outcomes: items.map { CachesCleanOutcome(item: $0, status: .refused("\(busy); nothing was deleted")) },
                measuredFreedBytes: nil, warnings: []
            )
            return
        }
        let outcomes = items.map { item -> CachesCleanOutcome in
            if let cleaned = result.cleaned.first(where: { $0.id == item.id }) {
                let status: CachesCleanOutcome.Status = cleaned.isFailure
                    ? .failed(cleaned.failures)
                    : .cleaned(removed: cleaned.removedCount, freedBytes: cleaned.freedBytes, failures: cleaned.failures)
                return CachesCleanOutcome(item: item, status: status)
            }
            let reason = result.refused.first { $0.id == item.id }?.reason ?? "it was not reached"
            return CachesCleanOutcome(item: item, status: .refused(reason))
        }
        self.init(outcomes: outcomes, measuredFreedBytes: result.freedBytes, warnings: result.warnings)
    }

    public var cleanedCount: Int { outcomes.filter(\.isCleaned).count }
    public var notCleanedCount: Int { outcomes.count - cleanedCount }

    /// "Cleaned 2 items, freed 1.2 GB." plus what was left alone, if anything.
    public var summary: String {
        var text = "Nothing was cleaned."
        if cleanedCount > 0 {
            text = "Cleaned \(Self.items(cleanedCount))" + (measuredFreedBytes.map { ", freed \(DisplayText.bytes($0))" } ?? "") + "."
        }
        if notCleanedCount > 0 {
            text += " \(Self.items(notCleanedCount)) \(notCleanedCount == 1 ? "was" : "were") left alone."
        }
        return text
    }

    private static func items(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
    public var headline: String { CleanupPresentation.headline(measuredFreedBytes) }

}
