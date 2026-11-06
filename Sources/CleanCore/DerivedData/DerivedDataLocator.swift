import Foundation

/// Where Xcode keeps DerivedData (PLAN §4.4): `IDECustomDerivedDataLocation` when it is set, else
/// `<home>/Library/Developer/Xcode/DerivedData`.
public struct DerivedDataLocator: Sendable {
    public struct Location: Sendable, Hashable {
        public var root: URL
        /// The root came from Xcode's custom-location setting.
        public var isCustom: Bool
        /// Something to tell the user (a setting that could not be used).
        public var note: String?
        /// Why this root must not be listed or cleaned (`/`, the home folder, a folder above it, not a
        /// folder): an error to show. nil normally.
        public var refusal: String?
    }

    public var preferences: any XcodePreferences
    public var homeDirectory: URL

    public init(preferences: any XcodePreferences, homeDirectory: URL) {
        self.preferences = preferences
        self.homeDirectory = homeDirectory
    }

    public init(environment: CleanEnvironment, runner: CommandRunner = .live) {
        self.init(preferences: LiveXcodePreferences(environment: environment, runner: runner), homeDirectory: environment.homeDirectory)
    }

    public var defaultRoot: URL {
        homeDirectory.appending(path: "Library/Developer/Xcode/DerivedData", directoryHint: .isDirectory)
    }

    /// A leading `~` is expanded against the home folder. A relative value (Xcode's "relative to the
    /// workspace" style keeps DerivedData next to each project) has no single root, so the default folder
    /// is used and the note says so.
    public func locate() async -> Location {
        var location = await unchecked()
        location.refusal = DerivedDataRootCheck.refusal(root: location.root, home: homeDirectory)
        return location
    }

    private func unchecked() async -> Location {
        guard let value = await preferences.customDerivedDataLocation() else {
            return Location(root: defaultRoot, isCustom: false)
        }
        guard value.hasPrefix("/") || value == "~" || value.hasPrefix("~/") else {
            return Location(
                root: defaultRoot,
                isCustom: false,
                note: "Xcode's DerivedData location \"\(value)\" is relative to each project; only \(defaultRoot.path) is listed"
            )
        }
        return Location(root: CleanEnvironment.expand(value, home: homeDirectory), isCustom: true)
    }
}
