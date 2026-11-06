import ArgumentParser
import CleanCore
import Foundation

struct AutoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auto",
        abstract: "Print what auto mode would remove, notify about and skip, with reasons.",
        discussion: "Without --yes nothing is changed. --yes runs the plan now, ignoring the report-only window "
            + "because a person asked for it; every removal is checked again right before it runs."
    )

    @OptionGroup var rootOptions: RootOptions

    @Flag(help: "Run the plan now. Without it nothing is changed.")
    var yes = false

    func run() async throws {
        let context = try CommandContext.load()
        let git = try context.requireGit()
        let scan = try await context.scan(rootOptions, includeSizes: false)
        let settings = context.settings
        let now = context.environment.now()

        var assessments = await context.assessor(git: git).assess(scan)
        var plan = AutoPlanner.plan(assessments, settings: settings, now: now)
        // Measure only what the plan acts on.
        let sizes = await context.sizes(of: (plan.remove + plan.notifyLocalWork).map(\.worktree))
        assessments = assessments.map { var row = $0; row.estimatedBytes = sizes[row.worktree.path]; return row }
        plan = AutoPlanner.plan(assessments, settings: settings, now: now)

        let text = AutoPlanText(plan: plan, settings: settings, paths: context.paths(for: scan), now: now)
        print(text.render())

        guard yes else {
            print("Dry run: nothing was removed. --yes runs this plan now (and ignores the report-only window).")
            return
        }
        if !settings.autoEnabled {
            print("Auto mode is off in the settings; running once because you asked.")
        }
        let remover = Remover(git: git, settings: settings, environment: context.environment)
        let outcome = await AutoRunner(remover: remover)
            .run(plan, ignoringReportOnly: true, knownWorktrees: scan.worktrees)
        print(text.render(outcome))
        saveSummary(outcome.summary(date: context.environment.now()), context: context)
        if !outcome.failed.isEmpty { throw ExitCode.failure }
    }

    /// Records the run as `lastAutoRun`, re-reading the settings first so nothing else is overwritten.
    private func saveSummary(_ summary: AutoRunSummary, context: CommandContext) {
        let store = SettingsStore(environment: context.environment)
        do {
            var settings = try store.load()
            settings.lastAutoRun = summary
            try store.save(settings)
        } catch {
            StandardError.write("warning: could not record the run in \(store.fileURL.path): \(error)")
        }
    }
}
