import Foundation

public enum BranchMapLayout {
    public enum Sort: String, CaseIterable, Sendable, Codable { case closest, recent, name }

    /// Both halves share this scale, so a branch three commits away stays visible beside one 300 away.
    public static func fraction(_ distance: Int, maximum: Int) -> Double {
        guard distance > 0 else { return 0 }
        return min(1, log1p(Double(distance)) / log1p(Double(max(1, maximum))))
    }

    public static func sorted(_ entries: [BranchMapEntry], by sort: Sort) -> [BranchMapEntry] {
        entries.sorted { lhs, rhs in
            switch sort {
            case .closest:
                let left = distance(lhs), right = distance(rhs)
                if left != right { return left < right }
            case .recent:
                let left = lhs.metrics.tip?.date ?? .distantPast, right = rhs.metrics.tip?.date ?? .distantPast
                if left != right { return left > right }
            case .name: break
            }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.ref < rhs.ref : order == .orderedAscending
        }
    }

    private static func distance(_ entry: BranchMapEntry) -> UInt64 {
        guard entry.metrics.problem == nil, let ahead = entry.metrics.ahead, let behind = entry.metrics.behind else { return .max }
        return UInt64(max(0, ahead)) + UInt64(max(0, behind))
    }
}
