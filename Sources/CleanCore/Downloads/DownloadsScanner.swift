import Foundation

public struct DownloadsScanner: Sendable {
    public static let extensions: Set<String> = ["dmg", "pkg", "mpkg", "zip", "xip", "ipa", "iso", "tar", "tgz", "gz", "bz2", "xz", "7z", "rar"]
    public var home: URL
    public var now: @Sendable () -> Date
    public var addedDate: @Sendable (URL) -> Date?
    public var attachedImages: AttachedImages

    public init(home: URL, now: @escaping @Sendable () -> Date = { Date() },
                attachedImages: AttachedImages = .live(),
                addedDate: @escaping @Sendable (URL) -> Date? = DownloadsScanner.dateAdded) {
        self.home = home
        self.now = now
        self.attachedImages = attachedImages
        self.addedDate = addedDate
    }

    public static func dateAdded(_ url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return values?.addedToDirectoryDate ?? values?.creationDate
    }

    public var directory: URL { home.resolvingSymlinksInPath().appending(path: "Downloads") }

    public func scan() async -> DownloadsReport {
        let root = directory
        guard DirectoryEntries.kind(ofItemAt: root.path) == .directory else {
            return DownloadsReport(files: [], warnings: ["Downloads is missing or is not a regular folder."])
        }
        let children: [URL]
        do { children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) }
        catch { return DownloadsReport(files: [], warnings: ["Could not read Downloads: \(error.localizedDescription)"]) }
        let attached = try? await attachedImages.paths()
        let cutoff = now().addingTimeInterval(-30 * 24 * 60 * 60)
        let files = children.compactMap { url -> DownloadFile? in
            guard Self.extensions.contains(url.pathExtension.lowercased()),
                  let identity = DownloadIdentity.read(url), let added = addedDate(url), added <= cutoff
            else { return nil }
            let reason: String?
            if url.pathExtension.lowercased() == "dmg" {
                if let attached { reason = attached.contains(url.resolvingSymlinksInPath().path) ? "Disk image is attached" : nil }
                else { reason = "Could not check whether this disk image is attached" }
            } else { reason = nil }
            return DownloadFile(path: url.path, addedAt: added, identity: identity, skipReason: reason)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return DownloadsReport(files: files, warnings: attached == nil ? ["Could not check attached disk images. Disk images will stay in Downloads."] : [])
    }
}
