import CleanCore
import CleanTestSupport
import Foundation

/// `fixture-world <folder>`: builds `DemoWorld` in an empty folder inside the temp dir, then runs the
/// assessment `clean-claude scan` runs (default settings) and exits 1 when any worktree didn't get the
/// status it was built for. Dev tool only; it never touches anything outside `<folder>`.
@main
struct FixtureWorld {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let temp = FileManager.default.temporaryDirectory.path
        guard arguments.count == 1, let argument = arguments.first, !argument.hasPrefix("-") else {
            fail("usage: fixture-world <folder>\n  <folder>: empty or new, inside \(temp)", code: 2)
        }
        let folder = URL(fileURLWithPath: argument, isDirectory: true).standardized
        if let problem = DemoWorld.problem(withTarget: folder) {
            fail("error: \(problem)", code: 2)
        }

        let world: DemoWorld
        do {
            world = try await DemoWorld.build(in: folder)
        } catch {
            fail("error: building the demo world failed: \(error)", code: 1)
        }
        printBuilt(world)
        let matched = await check(world)
        print("")
        print("Run the app against it:")
        print("  CLEAN_CLAUDE_SETTINGS_DIR=$(mktemp -d) CLEAN_CLAUDE_SCAN_ROOTS=\"\(folder.path)\" make run")
        exit(matched ? 0 : 1)
    }

    private static func printBuilt(_ world: DemoWorld) {
        print("Built a demo world in \(world.folder.path)")
        print("  repos (bare remotes in remotes/): " + world.repos.map(world.relativePath).joined(separator: ", "))
        let width = world.items.map { world.relativePath($0.url).count }.max() ?? 0
        for item in world.items {
            print("  " + pad(world.relativePath(item.url), width) + "  " + item.purpose)
        }
    }

    /// Scans the world like `clean-claude scan` and compares each verdict with what was built.
    private static func check(_ world: DemoWorld) async -> Bool {
        let environment = CleanEnvironment.live()
        let settings = Settings()
        let scan = await Scanner(environment: environment, settings: settings).scan(roots: [world.folder])
        for issue in scan.issues {
            print("warning: \(issue)")
        }
        guard let git = WorktreeAssessor.git(for: environment) else {
            print("error: git not found")
            return false
        }
        let assessments = await WorktreeAssessor(git: git, settings: settings, environment: environment).assess(scan)

        print("")
        print("Assessment (as `clean-claude scan`, default settings: idle threshold \(settings.idleThresholdDays) days):")
        let rows = assessments.map { assessment -> [String] in
            let idle = assessment.idle.idleDays.map { "\($0)d" } ?? (assessment.worktree.isMain ? "main" : "-")
            let size = assessment.estimatedBytes.map(ByteFormatting.string) ?? "-"
            let check: String
            if assessment.worktree.isMain {
                check = ""
            } else if let item = world.item(for: assessment.worktree) {
                check = item.mismatch(assessment).map { "MISMATCH: \($0)" } ?? "ok"
            } else {
                check = "MISMATCH: not built by fixture-world"
            }
            return [world.relativePath(assessment.worktree.url), idle, size, assessment.status.label, check]
        }
        let header = ["PATH", "IDLE", "SIZE", "STATUS", "CHECK"]
        let widths = header.indices.map { column in ([header] + rows).map { $0[column].count }.max() ?? 0 }
        for row in [header] + rows {
            let line = row.indices.map { pad(row[$0], widths[$0]) }.joined(separator: "  ")
            print("  " + line.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression))
        }

        var problems = rows.filter { $0[4].hasPrefix("MISMATCH") }.count
        for item in world.items where !assessments.contains(where: { CanonicalPath.same($0.worktree.url, item.url) }) {
            print("  MISMATCH: \(world.relativePath(item.url)) was not found by the scan")
            problems += 1
        }
        if problems == 0 {
            print("All \(world.items.count) worktrees have the status they were built for.")
        } else {
            print("\(problems) of \(world.items.count) worktrees do not have the intended status.")
        }
        return problems == 0
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    private static func fail(_ message: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(code)
    }
}
