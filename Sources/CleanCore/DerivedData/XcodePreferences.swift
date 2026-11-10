/// Xcode's own settings that Bonsai reads. Tests pass a fake; `LiveXcodePreferences` runs `defaults`.
public protocol XcodePreferences: Sendable {
    /// `IDECustomDerivedDataLocation` as Xcode stored it, or nil when it is not set.
    func customDerivedDataLocation() async -> String?
}
