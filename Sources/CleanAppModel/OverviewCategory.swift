/// One card the Overview can show (PLAN §8.3): one per clean-up screen of the sidebar, with that screen's name,
/// icon and parts of the "can free" total, so a card's number is its screen's badge and its button opens it.
public enum OverviewCategory: String, CaseIterable, Identifiable, Sendable {
    case worktrees
    case projectFolders
    case toolCaches
    case dockerSimulators
    case derivedData

    public var id: String { rawValue }

    /// The screen it stands for and opens.
    public var section: SidebarSection {
        switch self {
        case .worktrees: .worktrees
        case .projectFolders: .projects
        case .toolCaches: .caches
        case .dockerSimulators: .dockerSimulators
        case .derivedData: .derivedData
        }
    }

    /// The screen's parts: the card adds up exactly what the screen's badge does.
    public var parts: [ReclaimSummary.Part] { section.reclaimParts }
    public var title: String { section.title }
    public var systemImage: String { section.systemImage }

    /// "Worktrees", "Worktrees or Docker & Simulators", "Worktrees, Tool caches or Xcode DerivedData".
    public static func names(_ categories: [OverviewCategory]) -> String {
        let titles = categories.map(\.title)
        guard titles.count > 1 else { return titles.first ?? "" }
        return titles.dropLast().joined(separator: ", ") + " or " + (titles.last ?? "")
    }
}
