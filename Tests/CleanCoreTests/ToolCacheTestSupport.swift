@testable import CleanCore
import CleanTestSupport
import Foundation

/// A free-space reading that grows by 1 MiB on every read, so each cleaned entry measures 1 MiB freed.
final class GrowingFreeSpace: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 10_000_000_000

    var probe: FreeSpaceProbe {
        FreeSpaceProbe { [self] in
            lock.withLock {
                value += 1_048_576
                return value
            }
        }
    }
}

extension ToolCacheWorld {
    func scanner() -> ToolCacheScanner {
        ToolCacheScanner(environment: environment, processes: processes.source)
    }

    func cleaner(freeSpace: FreeSpaceProbe? = GrowingFreeSpace().probe) -> ToolCacheCleaner {
        var cleaner = ToolCacheCleaner(environment: environment, processes: processes.source)
        cleaner.freeSpace = freeSpace
        return cleaner
    }

    func logEntries() throws -> [RemovalLogEntry] {
        try RemovalLog(environment: environment).entries()
    }
}

extension ToolCacheReport {
    /// The finding for `id`; fails the test with a clear message when the scan has none.
    func require(_ id: String) throws -> ToolCacheFinding {
        guard let finding = finding(id: id) else { throw ToolCacheTestError(description: "the scan has no \(id)") }
        return finding
    }

    /// The findings for `ids`, in that order.
    func require(_ ids: [String]) throws -> [ToolCacheFinding] {
        try ids.map(require)
    }
}

struct ToolCacheTestError: Error, CustomStringConvertible {
    var description: String
}
