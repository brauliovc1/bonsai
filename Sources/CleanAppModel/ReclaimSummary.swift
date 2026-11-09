import Foundation

/// What Bonsai can free (PLAN §8.6): the one total behind the Overview's "Bonsai can free about X" and cards, the
/// sidebar's badges and the menu window's "Ready to clean". Each byte is counted once: Project folders leave out
/// the checkouts that are ready-to-remove worktrees (Worktrees counts those whole, dependencies and all).
public struct ReclaimSummary: Equatable, Sendable {
    /// One part of the total, from the screen that frees it.
    public enum Part: String, CaseIterable, Sendable, Identifiable {
        /// Linked worktrees a removal by hand accepts.
        case worktrees
        /// Project folders idle at least the threshold with nothing running inside, not a removable worktree.
        case projectFolders
        /// Tool caches that are ready to clean.
        case toolCaches
        /// What `docker system prune -f` can free at most.
        case docker
        /// Orphaned Xcode DerivedData.
        case derivedData
        /// Unavailable simulators.
        case simulators

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .worktrees: "Worktrees"
            case .projectFolders: "Project folders"
            case .toolCaches: "Tool caches"
            case .docker: "Docker"
            case .derivedData: "Xcode DerivedData"
            case .simulators: "Simulators"
            }
        }
    }

    /// What is known about one part.
    public enum State: Equatable, Sendable {
        /// Its screen hasn't looked yet.
        case notMeasured
        case measuring
        /// It can't be counted now; the sentence says why ("Docker isn't running, so it isn't counted.").
        case unavailable(String)
        case measured(bytes: Int64, count: Int)
    }

    public let states: [Part: State]

    public init(_ states: [Part: State]) {
        self.states = states
    }

    public func state(_ part: Part) -> State { states[part] ?? .notMeasured }

    /// The part's bytes when measured, else 0.
    public func bytes(_ part: Part) -> Int64 {
        if case .measured(let bytes, _) = state(part) { return max(0, bytes) }
        return 0
    }

    /// How many items make up the part (worktrees, projects, caches, folders, devices); 0 when not measured.
    public func count(_ part: Part) -> Int {
        if case .measured(_, let count) = state(part) { return count }
        return 0
    }

    public func bytes(_ parts: [Part]) -> Int64 { parts.map(bytes).reduce(0, +) }

    /// Every measured part added up.
    public var totalBytes: Int64 { bytes(Part.allCases) }

    /// Parts with something to free, largest first (ties in `Part` order).
    public var nonZeroParts: [Part] {
        Part.allCases.filter { bytes($0) > 0 }.sorted { bytes($0) > bytes($1) }
    }

    /// Parts measured with nothing to free.
    public var emptyParts: [Part] {
        Part.allCases.filter { if case .measured(let bytes, _) = state($0) { bytes <= 0 } else { false } }
    }

    /// Parts that can't be counted now, with why.
    public var unavailable: [(part: Part, reason: String)] {
        Part.allCases.compactMap { part in
            if case .unavailable(let reason) = state(part) { return (part, reason) }
            return nil
        }
    }

    /// Parts not measured yet, or being measured: the total may still grow.
    public var pendingParts: [Part] {
        Part.allCases.filter { part in
            switch state(part) {
            case .notMeasured, .measuring: true
            case .unavailable, .measured: false
            }
        }
    }

    /// The menu window's tooltip: one line per part with something to free (zero parts left out), then what is
    /// still being measured.
    public var partsHelp: String {
        var lines = nonZeroParts.map { "\($0.title): \(DisplayText.bytes(bytes($0)))" }
        if lines.isEmpty { lines.append(pendingParts.isEmpty ? "Nothing to clean right now." : "Nothing found yet.") }
        if !pendingParts.isEmpty {
            lines.append("Not measured yet: " + pendingParts.map(\.title).joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    /// "Worktrees", "Worktrees or Docker", "Worktrees, Docker or Simulators".
    public static func names(_ parts: [Part]) -> String {
        let titles = parts.map(\.title)
        guard titles.count > 1 else { return titles.first ?? "" }
        return titles.dropLast().joined(separator: ", ") + " or " + (titles.last ?? "")
    }
}
