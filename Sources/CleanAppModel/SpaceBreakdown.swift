/// The Overview's bar (PLAN §8.3): the disk as used space, the part of it Bonsai can free (green, inside used),
/// and free space, each as a fraction of the disk, with the legend's texts.
public struct SpaceBreakdown: Equatable, Sendable {
    public let totalBytes: Int64
    public let freeBytes: Int64
    /// What Bonsai can free, at most the used space.
    public let canFreeBytes: Int64

    /// nil when the disk's size or free space is unknown.
    public init?(free: Int64?, total: Int64?, canFree: Int64) {
        guard let free, let total, total > 0 else { return nil }
        totalBytes = total
        freeBytes = min(max(free, 0), total)
        canFreeBytes = min(max(canFree, 0), total - freeBytes)
    }

    public var usedBytes: Int64 { totalBytes - freeBytes }

    /// Used space that stays after everything Bonsai can free is freed.
    public var usedFraction: Double { Double(usedBytes - canFreeBytes) / Double(totalBytes) }
    public var canFreeFraction: Double { Double(canFreeBytes) / Double(totalBytes) }
    public var freeFraction: Double { Double(freeBytes) / Double(totalBytes) }

    public var usedText: String { "Used \(DisplayText.bytes(usedBytes))" }
    public var canFreeText: String { "Can free \(DisplayText.bytes(canFreeBytes))" }
    public var freeText: String { "Free \(DisplayText.bytes(freeBytes))" }
}
