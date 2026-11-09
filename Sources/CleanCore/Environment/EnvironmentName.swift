/// Bonsai's own environment variables (PLAN §10.2). Each is read under its `BONSAI_*` name first and its old
/// `CLEAN_CLAUDE_*` name second, so scripts written for clean-claude keep working; the new name wins. An empty
/// value counts as unset. `CLAUDE_CONFIG_DIR` is Claude's own and is not one of these.
public enum EnvironmentName: String, CaseIterable, Sendable {
    /// The settings folder (development and tests): replaces `~/Library/Application Support/Bonsai`.
    case settingsDirectory = "BONSAI_SETTINGS_DIR"
    /// Colon-separated folders to scan instead of the settings' (development).
    case scanRoots = "BONSAI_SCAN_ROOTS"

    public var name: String { rawValue }

    /// The name before the rename: `CLEAN_CLAUDE_SETTINGS_DIR`, `CLEAN_CLAUDE_SCAN_ROOTS`.
    public var oldName: String { "CLEAN_CLAUDE_" + rawValue.dropFirst("BONSAI_".count) }

    /// The value under the new name, else under the old one; nil when neither is set to something.
    public func value(in variables: [String: String]) -> String? {
        for key in [name, oldName] {
            if let value = variables[key], !value.isEmpty { return value }
        }
        return nil
    }
}
