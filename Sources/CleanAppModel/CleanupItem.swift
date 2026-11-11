import Foundation

/// A confirmed unit of work. Its result keeps measurements, refusals and logging failures together.
public struct CleanupItemResult: Sendable, Equatable {
    public enum State: Sendable { case cleaned, refused, failed }
    public let state: State
    public let freedBytes: Int64?
    public let detail: String
    public let warnings: [String]

    public init(_ state: State, freedBytes: Int64? = nil, detail: String = "", warnings: [String] = []) {
        self.state = state
        self.freedBytes = freedBytes
        self.detail = detail
        self.warnings = warnings
    }
}

/// One row of a cleanup task. Operations live only in the queue, and are discarded when the task ends.
public struct CleanupItem: Identifiable, Sendable {
    public enum State: Sendable { case waiting, running, done, refused, failed, stopped }
    public let id: UUID
    public let name: String
    public let resources: [String]
    public let estimatedBytes: Int64?
    public internal(set) var state: State = .waiting
    public internal(set) var result: CleanupItemResult?

    public init(name: String, resources: [String], estimatedBytes: Int64? = nil) {
        id = UUID()
        self.name = name
        // Keep the spelling as well as its destination: a symlink changed while waiting must not unlock
        // the originally confirmed path or permit another submission of that same item.
        self.resources = resources.flatMap { [$0, CleanupQueue.canonicalResource($0)] }
        self.estimatedBytes = estimatedBytes
    }
}

@MainActor
struct CleanupWork {
    let item: CleanupItem
    let run: @MainActor () async -> CleanupItemResult

    init(_ item: CleanupItem, run: @escaping @MainActor () async -> CleanupItemResult) {
        self.item = item
        self.run = run
    }
}
