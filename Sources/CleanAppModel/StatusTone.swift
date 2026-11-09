/// What a color means in the app (PLAN §8.1). The app's palette draws each one in light and dark; nothing is
/// colored for decoration.
public enum StatusTone: String, Sendable, Hashable, CaseIterable {
    /// Can be freed, ready.
    case green
    /// Needs your attention: local work, low space.
    case orange
    /// In use, information.
    case blue
    /// Destructive buttons and very low space only.
    case red
    /// Neutral.
    case grey
}
