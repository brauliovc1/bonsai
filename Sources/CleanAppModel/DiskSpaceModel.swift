import Foundation
import Observation

/// Free and total bytes of the volume that holds the first scan root. `AppModel` refreshes it after every
/// scan and every cleanup.
@MainActor
@Observable
public final class DiskSpaceModel {
    /// The folder whose volume is measured.
    public private(set) var folder: URL?
    public private(set) var freeBytes: Int64?
    public private(set) var totalBytes: Int64?
    /// The volume's name in Finder ("Macintosh HD").
    public private(set) var volumeName: String?

    /// What one reading of a volume found.
    struct Reading: Sendable {
        var free: Int64?
        var total: Int64?
        var name: String?
    }

    /// Test seam: reads the volume holding a folder that exists.
    @ObservationIgnored var read: @Sendable (URL) -> Reading = { DiskSpaceModel.readVolume($0) }

    public init(folder: URL? = nil) {
        self.folder = folder
        refresh()
    }

    /// 0...1, nil when unknown.
    public var usedFraction: Double? {
        guard let freeBytes, let totalBytes, totalBytes > 0 else { return nil }
        return Double(totalBytes - freeBytes) / Double(totalBytes)
    }

    /// Measures the volume holding `folder` from now on.
    public func point(at folder: URL) {
        guard folder != self.folder else { return }
        self.folder = folder
        refresh()
    }

    public func refresh() {
        guard let folder else {
            freeBytes = nil
            totalBytes = nil
            volumeName = nil
            return
        }
        // A fresh URL each time (URL caches resource values), from the nearest folder that exists.
        var probe = URL(fileURLWithPath: folder.path, isDirectory: true)
        while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" {
            probe = probe.deletingLastPathComponent()
        }
        let reading = read(probe)
        freeBytes = reading.free
        totalBytes = reading.total
        volumeName = reading.name
    }

    nonisolated static func readVolume(_ folder: URL) -> Reading {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeLocalizedNameKey]
        let values = try? folder.resourceValues(forKeys: keys)
        return Reading(
            free: values?.volumeAvailableCapacity.map(Int64.init),
            total: values?.volumeTotalCapacity.map(Int64.init),
            name: values?.volumeLocalizedName
        )
    }
}
