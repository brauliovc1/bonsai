import Foundation

/// Reads Xcode's settings with `defaults read com.apple.dt.Xcode <key>`. Read-only: nothing here writes
/// a default.
public struct LiveXcodePreferences: XcodePreferences {
    public static let customLocationArguments = ["read", "com.apple.dt.Xcode", "IDECustomDerivedDataLocation"]

    /// `/usr/bin/defaults`; nil = treat every setting as not set.
    public var defaults: URL?
    public var runner: CommandRunner

    public init(defaults: URL?, runner: CommandRunner = .live) {
        self.defaults = defaults
        self.runner = runner
    }

    public init(environment: CleanEnvironment, runner: CommandRunner = .live) {
        self.init(defaults: environment.tools.defaults, runner: runner)
    }

    /// A non-zero exit (the key is not set), a timeout or an empty value all mean "not set".
    public func customDerivedDataLocation() async -> String? {
        guard let defaults,
              let result = try? await runner.run(defaults, Self.customLocationArguments, timeout: .seconds(10)),
              result.succeeded
        else { return nil }
        let value = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
