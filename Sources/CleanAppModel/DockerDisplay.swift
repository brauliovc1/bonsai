import CleanCore
import Foundation

/// One line of the `docker system df` table, as the screen shows it.
public struct DockerUsageLine: Identifiable, Sendable, Hashable {
    public let type: String
    public let countText: String
    public let sizeText: String
    public let reclaimableText: String

    public init(_ row: DockerUsageRow) {
        type = row.type
        countText = "\(row.total) (\(row.active) active)"
        sizeText = DisplayText.bytes(row.sizeBytes)
        reclaimableText = DisplayText.bytes(row.reclaimableBytes)
    }

    public var id: String { type }
}

/// One installed simulator runtime, read-only.
public struct SimulatorRuntimeLine: Identifiable, Sendable, Hashable {
    public let name: String
    public let sizeText: String
    public let kindText: String

    public init(_ runtime: SimulatorRuntime) {
        name = runtime.displayName
        sizeText = DisplayText.bytes(runtime.sizeBytes)
        kindText = runtime.kind ?? "–"
        id = runtime.id
    }

    public let id: String
}
