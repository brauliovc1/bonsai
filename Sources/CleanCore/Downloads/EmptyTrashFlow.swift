import Foundation

/// The app provides Finder's Apple Event implementation. Tests always provide a fake.
public protocol TrashEmptier: Sendable {
    func empty() async throws
}

public enum TrashEmptyError: Error, LocalizedError, Sendable {
    case automationDenied
    case failed(String)
    public static let automationMessage = "Allow Bonsai to control Finder in System Settings › Privacy & Security › Automation"
    public var errorDescription: String? {
        switch self {
        case .automationDenied: Self.automationMessage
        case .failed(let message): message
        }
    }
}

public struct EmptyTrashResult: Sendable {
    public let entry: RemovalLogEntry
    public let warnings: [String]
}

public struct EmptyTrashFlow: Sendable {
    public var emptier: any TrashEmptier
    public var log: RemovalLog
    public var home: URL
    public var freeSpace: FreeSpaceProbe
    public var now: @Sendable () -> Date

    public init(emptier: any TrashEmptier, log: RemovalLog, home: URL,
                freeSpace: FreeSpaceProbe? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.emptier = emptier; self.log = log; self.home = home
        self.freeSpace = freeSpace ?? .volume(containing: home)
        self.now = now
    }

    /// Call under the cleanup queue's guard and lock. False cannot send an Apple Event or write a log.
    public func run(confirmed: Bool, expected: TrashFingerprint? = nil) async throws -> EmptyTrashResult? {
        guard confirmed else { return nil }
        let confirmedContents: TrashFingerprint
        if let expected { confirmedContents = expected }
        else { confirmedContents = await TrashFingerprint.capture(home: home) }
        guard await TrashFingerprint.capture(home: home) == confirmedContents else {
            throw DownloadsError("The Trash changed since you confirmed. Review its contents and try again.")
        }
        let before = freeSpace.availableBytes()
        try await emptier.empty()
        let after = freeSpace.availableBytes()
        let freed = before.flatMap { start in after.map { max(0, $0 - start) } }
        let entry = RemovalLogEntry(date: now(), mode: .manual, action: .trashEmptied,
            repoPath: home.path, path: home.appending(path: ".Trash").path,
            freedBytes: freed, notes: ["Finder emptied the Trash after confirmation."])
        var warnings: [String] = []
        do { try log.append(entry) }
        catch { warnings.append("The Trash was emptied, but its history could not be written: \(error.localizedDescription)") }
        return EmptyTrashResult(entry: entry, warnings: warnings)
    }
}
