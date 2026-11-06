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
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeLocalizedNameKey]
        let values = try? probe.resourceValues(forKeys: keys)
        freeBytes = values?.volumeAvailableCapacity.map(Int64.init)
        totalBytes = values?.volumeTotalCapacity.map(Int64.init)
        volumeName = values?.volumeLocalizedName
    }
}
