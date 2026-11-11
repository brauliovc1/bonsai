/// The same read-only values shown by the app and `downloads --json`.
public struct DownloadsListing: Sendable, Codable, Hashable {
    public let downloads: DownloadsReport
    public let trash: TrashInfo
    public let timeMachine: LocalSnapshots

    public init(downloads: DownloadsReport, trash: TrashInfo, timeMachine: LocalSnapshots) {
        self.downloads = downloads; self.trash = trash; self.timeMachine = timeMachine
    }
}
