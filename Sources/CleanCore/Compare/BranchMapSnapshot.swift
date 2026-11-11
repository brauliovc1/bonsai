import Foundation

public struct BranchMapSnapshot: Sendable, Codable {
    public let base: String
    public let baseSHA: String
    public let entries: [BranchMapEntry]
    public var mergedCount: Int { entries.count { $0.metrics.isMerged } }
    public var farBehindCount: Int { entries.count { ($0.metrics.behind ?? 0) > 100 } }
    public var maximumDistance: Int {
        entries.flatMap { [$0.metrics.behind ?? 0, $0.metrics.ahead ?? 0] }.max() ?? 0
    }
    public var summary: String {
        "\(entries.count) branches · \(mergedCount) merged into \(base) · \(farBehindCount) more than 100 behind"
    }
}
