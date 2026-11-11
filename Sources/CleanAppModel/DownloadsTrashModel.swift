import CleanCore
import Foundation
import Observation

@MainActor
@Observable
public final class DownloadsTrashModel {
    public let app: AppModel
    @ObservationIgnored let runner: CommandRunner
    @ObservationIgnored let trashOperation: TrashOperation
    @ObservationIgnored let emptier: any TrashEmptier
    @ObservationIgnored let loop = ScanLoop()
    @ObservationIgnored var dateAdded: @Sendable (URL) -> Date?
    public internal(set) var listing: DownloadsListing?
    public private(set) var isScanning = false
    public var selection: Set<String> = []
    public var moveConfirmation: DownloadsConfirmation?
    public var isShowingEmptySheet = false
    public private(set) var isPreparingEmptyTrash = false
    public private(set) var emptyTrashProblem: String?
    @ObservationIgnored var confirmedTrash: (info: TrashInfo, fingerprint: TrashFingerprint)?
    public internal(set) var automationDenied = false

    public init(app: AppModel, runner: CommandRunner = .live, trash: TrashOperation = .live,
                emptier: any TrashEmptier = UnavailableTrashEmptier(),
                dateAdded: @escaping @Sendable (URL) -> Date? = DownloadsScanner.dateAdded) {
        self.app = app; self.runner = runner; self.trashOperation = trash; self.emptier = emptier
        self.dateAdded = dateAdded
    }

    public var files: [DownloadFile] { listing?.downloads.files ?? [] }
    public var eligible: [DownloadFile] { listing?.downloads.eligible ?? [] }
    public var readyBytes: Int64 { listing?.downloads.bytes ?? 0 }
    public var selected: [DownloadFile] {
        eligible.filter { selection.contains($0.id) && app.cleanupQueue.task(for: $0.path) == nil }
    }
    public var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.bytes } }
    public var warnings: [String] { (listing?.downloads.warnings ?? []) + (listing?.timeMachine.warnings ?? []) + [emptyTrashProblem].compactMap { $0 } }
    public var trash: TrashInfo? { listing?.trash }
    public var snapshots: LocalSnapshots? { listing?.timeMachine }
    public var emptyConfirmation: String {
        guard let info = confirmedTrash?.info ?? trash, let count = info.count, let bytes = info.bytes else {
            return "Permanently delete everything in the Trash? This can't be undone."
        }
        return "Permanently delete \(count) \(count == 1 ? "item" : "items") (\(DisplayText.bytes(bytes)))? This can't be undone."
    }
    public var canEmptyTrash: Bool { listing != nil && trash?.count != 0 && !isPreparingEmptyTrash && !app.isQuitting && app.cleanupQueue.task(for: "trash") == nil }

    public func setSelected(_ file: DownloadFile, _ value: Bool) {
        if value, eligible.contains(file), app.cleanupQueue.task(for: file.path) == nil { selection.insert(file.id) }
        else { selection.remove(file.id) }
    }

    public func selectAllReady() {
        selection = Set(eligible.filter { app.cleanupQueue.task(for: $0.path) == nil }.map(\.id))
    }

    public func prepareMove() {
        guard !selected.isEmpty, !app.isQuitting else { return }
        moveConfirmation = DownloadsConfirmation(files: selected)
    }

    public func prepareEmptyTrash() async {
        guard canEmptyTrash else { return }
        isPreparingEmptyTrash = true
        defer { isPreparingEmptyTrash = false }
        emptyTrashProblem = nil
        let before = await TrashFingerprint.capture(home: app.environment.homeDirectory)
        let info = await TrashInfo.read(home: app.environment.homeDirectory, runner: runner)
        let after = await TrashFingerprint.capture(home: app.environment.homeDirectory)
        guard before == after else {
            emptyTrashProblem = "The Trash changed while it was being checked. Refresh and try again."
            return
        }
        guard !app.isQuitting else { return }
        confirmedTrash = (info, after)
        isShowingEmptySheet = true
    }

    var scanner: DownloadsScanner {
        DownloadsScanner(home: app.environment.homeDirectory, now: app.environment.now,
                         attachedImages: .live(runner: runner), addedDate: dateAdded)
    }

    public func refresh() async {
        await loop.run { [self] in
            isScanning = true
            async let downloads = scanner.scan()
            async let trash = TrashInfo.read(home: app.environment.homeDirectory, runner: runner)
            async let snapshots = LocalSnapshots.read(home: app.environment.homeDirectory, runner: runner)
            listing = await DownloadsListing(downloads: downloads, trash: trash, timeMachine: snapshots)
            selection.formIntersection(eligible.map(\.id))
            isScanning = false
        }
    }

    public func loadIfNeeded() async { if listing == nil { await refresh() } }
}

public struct DownloadsConfirmation: Sendable, Identifiable {
    public let id = UUID()
    public let files: [DownloadFile]
    public var bytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
    public var title: String { "Move \(files.count) \(files.count == 1 ? "file" : "files") (\(DisplayText.bytes(bytes))) to Trash?" }
    public var buttonTitle: String { "Move \(files.count) \(files.count == 1 ? "file" : "files") to Trash" }
    public init(files: [DownloadFile]) { self.files = files }
}

/// ScreenModels is safe in tests and render tools unless the app explicitly supplies Finder's implementation.
public struct UnavailableTrashEmptier: TrashEmptier {
    public init() {}
    public func empty() async throws { throw TrashEmptyError.failed("Empty Trash is available only in the Bonsai app.") }
}
