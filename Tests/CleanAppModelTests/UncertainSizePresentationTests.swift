@testable import CleanAppModel
@testable import CleanCore
import Foundation
import Testing

@Suite("Uncertain cleanup sizes")
struct UncertainSizePresentationTests {
    static let samples: [[Int64?]] = [[nil], [nil, nil, nil], [1_000_000, nil], [0, nil], [0], [1_000_000, 2_000_000], []]

    @Test(arguments: samples) func everyConfirmationPreservesMissingMeasurements(_ sizes: [Int64?]) {
        let count = sizes.count
        let expected = sizes.isEmpty ? DisplayText.bytes(0) : sizes.allSatisfy { $0 == nil } ? "size unknown"
            : (sizes.contains(nil) ? "at least " : "") + DisplayText.bytes(sizes.compactMap { $0 }.reduce(0, +))
        #expect(CleanupPresentation.estimate(sizes) == expected)
        let removal = PresentationFixtures.removal(count, sizeAt: { sizes[$0] })
        let derived = PresentationFixtures.derivedData(count, sizeAt: { sizes[$0] })
        let caches = PresentationFixtures.caches(count, sizeAt: { sizes[$0] })
        let dependencies = PresentationFixtures.dependencies(count, sizeAt: { sizes[$0] })
        let projects = PresentationFixtures.projects(count, sizeAt: { sizes[$0] })
        let simulators = PresentationFixtures.simulators(count, sizeAt: { sizes[$0] })
        let summaries = [removal.estimatedSizeText, derived.estimatedSizeText, caches.estimatedSizeText,
                         dependencies.estimatedSizeText, projects.estimatedSizeText, simulators.estimatedSizeText]
        #expect(summaries.allSatisfy { $0 == expected })
        if count > 0 {
            for title in [removal.title, derived.title, caches.title, dependencies.title, projects.title, simulators.title] {
                #expect(title.hasSuffix("(\(expected))?"), "\(title) must preserve \(expected)")
            }
            #expect(projects.summary.contains(expected))
        }
        #expect(removal.allowed.count == count)
        #expect(dependencies.folderCount == count)
        #expect(projects.folderCount == count)
        #expect(simulators.devices.count == count)
        #expect(removal.estimatedTotalBytes == sizes.compactMap { $0 }.reduce(0, +))
    }

    @Test func blockedAndChangedItemsDoNotInflateTheDisplayedLowerBound() {
        var blocked = PresentationFixtures.removal(1, sizeAt: { _ in nil }).items[0].assessment
        blocked.safety = SafetyReport(blockers: [.uncommitted(count: 1)], notes: [], autoBlockers: [])
        let removal = RemovalConfirmation(items: PresentationFixtures.removal(1).items + [.init(assessment: blocked)])
        #expect(removal.estimatedSizeText == DisplayText.bytes(1_000_000))
        #expect(removal.allowed.count == 1)
        let changed = ProjectsConfirmation.Item(lightClean: PresentationFixtures.dependencies(2, sizeAt: { _ in nil }).items[1],
            idle: .idle(days: 1), threshold: 30, rebuildLines: [], wasAutoPicked: true)
        var projects = ProjectsConfirmation(items: PresentationFixtures.projects(1).items + [changed])
        #expect(projects.estimatedSizeText == DisplayText.bytes(1_000_000))
        projects.included.insert(changed.id)
        #expect(projects.estimatedSizeText == "at least \(DisplayText.bytes(1_000_000))")
        #expect(projects.folderCount == 2)
    }

    @Test func dockerDistinguishesUnreadableUsageFromAReportedZero() {
        let unreadable = DockerPruneConfirmation(report: DockerReport(state: .running, daemonOperatingSystem: "Docker Desktop", usageFailure: "unreadable"), commandLine: nil)
        #expect(unreadable.isAllowed)
        #expect(unreadable.title == "Clean up Docker (size unknown)?")
        #expect(!unreadable.hasSizeEstimate)
        let zero = DockerPruneConfirmation(report: DockerReport(state: .running, daemonOperatingSystem: "Docker Desktop"), commandLine: nil)
        #expect(zero.title == "Clean up Docker (up to \(DisplayText.bytes(0)))?")
        #expect(zero.hasSizeEstimate)
    }

    @Test(arguments: samples) @MainActor func queuedBatchAndSelectionKeepTheSameUncertainty(_ sizes: [Int64?]) {
        let expected = CleanupPresentation.estimate(sizes)
        let total = sizes.compactMap { $0 }.reduce(0, +)
        let task = CleanupTask(title: "Simulators", unit: "commands", items: [CleanupItem(name: "Simulators", resources: [], estimatedBytes: total, sizeEstimates: sizes)])
        #expect(task.estimatedSizeText == expected)
        #expect(task.hasCompleteEstimate == sizes.allSatisfy { $0 != nil })
        #expect(task.estimatedBytes == total)
        let rows = PresentationFixtures.removal(sizes.count, sizeAt: { sizes[$0] }).items.enumerated().map {
            WorktreeRow(assessment: $0.element.assessment, scanOrder: $0.offset)
        }
        #expect(WorktreeSelectionSummary(rows: rows).estimatedSizeText == expected)
        let project = ProjectFolders(worktree: PresentationFixtures.worktree(0), idle: .idle(days: 40),
            folders: sizes.enumerated().map { index, size in
                let candidate = LightCleanCandidate(worktreePath: "/tmp/presentation", relativePath: "folder-\(index)", name: "folder-\(index)", estimatedBytes: size, packageClones: [])
                return ProjectFolders.Folder(candidate: candidate, bytes: size)
            })
        let row = ProjectRow(project: project, threshold: 30, home: nil)
        #expect(row.sizeText == expected)
        #expect(row.measuredSizeBytes == (sizes.contains { $0 != nil } ? total : nil))
    }
}
