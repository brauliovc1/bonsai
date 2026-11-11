@testable import CleanAppModel
@testable import CleanCore
import Foundation
import Testing

@Suite("Cleanup presentation")
struct CleanupPresentationTests {
    @Test(arguments: [0, 1, 3]) func confirmationTitlesAndButtons(_ count: Int) {
        let bytes: Int64 = Int64(count) * 1_000_000
        let amount = DisplayText.bytes(bytes)
        let remove = PresentationFixtures.removal(count)
        #expect(remove.title == (count == 0 ? "Nothing to remove" : "Remove \(count) \(count == 1 ? "worktree" : "worktrees") (\(amount))?"))
        #expect(remove.removeButtonTitle == "Remove \(count)")
        let light = PresentationFixtures.dependencies(count)
        #expect(light.title == (count == 0 ? "Nothing to clean" : "Clean \(count) \(count == 1 ? "dependency folder" : "dependency folders") (\(amount))?"))
        #expect(light.deleteButtonTitle == "Clean \(count)")
        let projects = PresentationFixtures.projects(count)
        #expect(projects.title == (count == 0 ? "Nothing to clean" : "Clean \(count) \(count == 1 ? "project" : "projects") (\(amount))?"))
        #expect(projects.deleteButtonTitle == "Clean \(count)")
        let derived = PresentationFixtures.derivedData(count)
        #expect(derived.title == (count == 0 ? "Nothing to delete" : "Delete \(count) \(count == 1 ? "folder" : "folders") (\(amount))?"))
        #expect(derived.deleteButtonTitle == "Delete \(count)")
        let caches = PresentationFixtures.caches(count)
        #expect(caches.title == (count == 0 ? "Nothing to clean" : "Clean \(count) \(count == 1 ? "cache" : "caches") (\(amount))?"))
        #expect(caches.cleanButtonTitle == "Clean \(count)")
        let simulators = PresentationFixtures.simulators(count)
        #expect(simulators.title == (count == 0 ? "Nothing to delete" : "Delete \(count) \(count == 1 ? "simulator" : "simulators") (\(amount))?"))
        #expect(simulators.buttonTitle == "Delete \(count)")
    }

    @Test(arguments: [0, 1, 3]) func pruneAndDockerLabels(_ count: Int) {
        let entries = (0..<count).map { index in
            Pruner.Entry(name: "gone-\(index)", reason: "folder gone", path: "/tmp/presentation/gone-\(index)", branch: "old", head: "abc")
        }
        let plan = PrunePlan(repos: [PrunePlan.Repo(repoPath: "/tmp/presentation/repo", entries: entries, refusals: [], error: nil)])
        #expect(plan.title == (count == 0 ? "Nothing to clear" : "Clear \(count) missing folder \(count == 1 ? "record" : "records")?"))
        #expect(plan.buttonTitle == "Clear \(count) \(count == 1 ? "record" : "records")")
        let bytes: Int64 = Int64(count) * 1_000_000
        let docker = DockerPruneConfirmation(report: DockerReport(state: .running, daemonOperatingSystem: "Docker Desktop", usage: [DockerUsageRow(type: "Images", total: count, active: 0, sizeBytes: bytes, reclaimableBytes: bytes)]), commandLine: nil)
        #expect(docker.title == "Clean up Docker (up to \(DisplayText.bytes(bytes)))?")
        #expect(docker.buttonTitle == "Clean up Docker")
    }

    @Test func reportHeadlinesKeepMeasurementAndUnknownSeparate() {
        let expected = "Freed \(DisplayText.bytes(2_400_000))"
        #expect(RemovalReport(outcomes: [], measuredFreedBytes: 2_400_000).headline == expected)
        #expect(DerivedDataCleanupReport(outcomes: [], measuredFreedBytes: 2_400_000, warnings: []).headline == expected)
        #expect(CachesCleanReport(outcomes: [], measuredFreedBytes: 2_400_000, warnings: []).headline == expected)
        #expect(LightCleanReport(outcomes: []).headline == "Freed space unavailable")
        let command = CleanupCommandReport(kind: .dockerPrune, command: DockerPruneConfirmation.command, result: CleanupCommandResult(exitCode: 0, output: "", freedBytes: 2_400_000), error: nil)
        #expect(command.headline == expected)
        #expect(CleanupPresentation.headline(0) == "Freed \(DisplayText.bytes(0))")
    }

    @Test func dependencyRefusalsAndHistoryUsePlainWords() {
        #expect(CleanupPresentation.reason(.symlink) == "It is a symbolic link. Bonsai leaves links alone.")
        #expect(!CleanupPresentation.reason(.notACandidate("changed")).contains("light-clean"))
        #expect(CleanupPresentation.error(LightCleanError.unavailable("folder gone")) == "Couldn't clean dependencies: folder gone")
        #expect(RemovalLogRow(entry: PresentationFixtures.entry(action: .lightClean)).actionText == "Cleaned dependencies")
    }

    @Test func appStringLiteralsUsePlainWords() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let pattern = #""[^"\n]*(SAFE|AUTO-READY|BLOCKED|light clean|Light clean|main checkout|clean-claude)[^"\n]*""#
        let regex = try NSRegularExpression(pattern: pattern)
        for folder in ["Sources/CleanClaudeApp", "Sources/CleanAppModel"] {
            let files = FileManager.default.enumerator(at: root.appending(path: folder), includingPropertiesForKeys: nil)!
            for case let file as URL in files where file.pathExtension == "swift" {
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
                for line in lines where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    #expect(regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) == nil, "\(file.lastPathComponent): \(line)")
                }
            }
        }
    }
}
