import Foundation

/// One "Reclaimable" row of the Overview: what could be freed, and the screen that frees it.
public struct OverviewRow: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case autoReadyWorktrees, safeWorktrees, lightClean, orphanedDerivedData, docker, simulators
    }

    public let kind: Kind
    public let title: String
    /// Under the title: how many items, or why there is no number.
    public let detail: String
    /// nil when there is no number yet (not scanned, not running, not installed).
    public let bytes: Int64?
    /// What the row's button opens.
    public let destination: SidebarSection

    public var id: Kind { kind }
    public var sizeText: String { DisplayText.bytes(bytes) }
    public var buttonTitle: String { "Show" }
}
