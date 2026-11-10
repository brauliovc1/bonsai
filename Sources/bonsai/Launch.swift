import CleanCore

/// The environment every command uses: the live one, after the settings folder's move (PLAN §10.2), which runs
/// once per run, the first time a command needs it. Its notice goes to stderr, once.
enum Launch {
    static let environment: CleanEnvironment = {
        let (environment, notice) = CleanEnvironment.launch()
        if let notice { StandardError.write("note: \(notice)") }
        return environment
    }()
}
