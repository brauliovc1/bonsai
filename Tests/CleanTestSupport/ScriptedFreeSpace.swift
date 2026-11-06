import CleanCore
import Foundation

/// A `FreeSpaceProbe` that answers from a list: the first call gets the first value, the second the
/// second, and so on; the last value repeats. nil entries stand for an unreadable volume.
public final class ScriptedFreeSpace: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: [Int64?]
    private var last: Int64?

    public init(_ values: [Int64?]) {
        remaining = values
    }

    public var probe: FreeSpaceProbe {
        FreeSpaceProbe { [self] in
            lock.withLock {
                if !remaining.isEmpty { last = remaining.removeFirst() }
                return last
            }
        }
    }
}
