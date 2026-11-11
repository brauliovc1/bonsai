import CleanCore
import Foundation
import Observation

/// Which sidebar screen the main window shows. The window opens on the Overview; its rows jump elsewhere
/// through `show(_:)`.
@MainActor
@Observable
public final class NavigationModel {
    public struct CompareRequest: Hashable, Sendable {
        public let repo: String
        public let base: String?
        public let compare: CompareSelection?
        public let id = UUID()
    }
    public var compareRequest: CompareRequest?
    public var section: SidebarSection?

    public init(section: SidebarSection? = .overview) {
        self.section = section
    }

    public func openCompare(repo: String, base: String? = nil, compare: CompareSelection? = nil) {
        compareRequest = CompareRequest(repo: repo, base: base, compare: compare)
        section = .compare
    }

    public func show(_ section: SidebarSection) {
        self.section = section
    }
}
