import Foundation
import Observation

/// The live progress and final report for exactly the items a person confirmed.
@MainActor
@Observable
public final class CleanupTask: Identifiable {
    public enum State: Sendable { case queued, waiting, running, done, stopped, cancelled, failed }
    public let id = UUID()
    public let title: String
    public let unit: String
    public internal(set) var state: State = .queued
    public internal(set) var items: [CleanupItem]
    public internal(set) var stopRequested = false
    public internal(set) var waitingReason: String?

    init(title: String, unit: String, items: [CleanupItem]) {
        self.title = title
        self.unit = unit
        self.items = items
    }

    public var isPending: Bool { [.queued, .waiting, .running].contains(state) }
    public var completedCount: Int { items.count { ![.waiting, .running].contains($0.state) } }
    public var cleanedCount: Int { items.count { $0.result?.state == .cleaned } }
    public var problemCount: Int { items.count { $0.state == .refused || $0.state == .failed } }
    public var hasProblems: Bool {
        problemCount > 0 || items.contains { $0.result?.warnings.isEmpty == false }
    }
    public var estimatedBytes: Int64 { items.compactMap(\.estimatedBytes).reduce(0, +) }
    public var measuredFreedBytes: Int64? {
        let measured = items.compactMap { $0.result?.freedBytes }
        return measured.isEmpty ? nil : measured.reduce(0, +)
    }
    public var countText: String { "\(items.count) \(items.count == 1 ? String(unit.dropLast()) : unit)" }
    public var summary: String {
        if state == .cancelled { return "Task cancelled · nothing cleaned" }
        if state == .stopped { return "\(cleanedCount) cleaned · \(items.count - cleanedCount) left alone" }
        if hasProblems {
            return problemCount > 0 ? "\(cleanedCount) cleaned, \(problemCount) couldn't be" : "\(cleanedCount) cleaned · review warnings"
        }
        let freed = measuredFreedBytes.map { "Freed \(DisplayText.bytes($0))" } ?? "Cleaned \(cleanedCount)"
        return "\(freed) · \(countText)"
    }
    public var progressText: String {
        let freed = measuredFreedBytes.map { " · \(DisplayText.bytes($0)) freed" } ?? ""
        let position = min(items.count, completedCount + (items.contains { $0.state == .running } ? 1 : 0))
        return "Cleaning \(title) · \(position) of \(items.count) \(unit)\(freed)"
    }
}
