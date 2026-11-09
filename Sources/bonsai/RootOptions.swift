import ArgumentParser

/// `--root`, shared by every command that scans.
struct RootOptions: ParsableArguments {
    @Option(
        name: .customLong("root"),
        help: ArgumentHelp(
            "A folder to scan (repeatable). Default: $BONSAI_SCAN_ROOTS, else the settings' scan roots, "
                + "else ~/Documents/GitHub.",
            valueName: "path"
        )
    )
    var roots: [String] = []
}
