import Foundation

/// Reads the free space of one volume, so a cleanup can report what it really freed (PLAN §3: measured
/// with `volumeAvailableCapacityKey` before and after, not added up from `du`).
public struct FreeSpaceProbe: Sendable {
    public var availableBytes: @Sendable () -> Int64?

    public init(_ availableBytes: @escaping @Sendable () -> Int64?) {
        self.availableBytes = availableBytes
    }

    /// Free space on the volume that holds `url`. nil when the volume cannot be read.
    public static func volume(containing url: URL) -> FreeSpaceProbe {
        let path = url.path
        return FreeSpaceProbe {
            // A fresh URL each time: URL caches resource values, which would hide the change.
            let fresh = URL(fileURLWithPath: path)
            guard let values = try? fresh.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
                  let available = values.volumeAvailableCapacity
            else { return nil }
            return Int64(available)
        }
    }
}
