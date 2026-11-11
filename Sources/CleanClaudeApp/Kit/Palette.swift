import AppKit
import CleanAppModel
import CleanCore
import SwiftUI

/// The app's colors (PLAN §8.1), each with a light and a dark value, so text stays readable on both. Color only
/// means something: green can be freed or is ready, orange needs your attention, blue is in use or information,
/// red is for destructive buttons and very low space only, grey is neutral.
enum Palette {
    static let green = color(.green)
    static let orange = color(.orange)
    static let blue = color(.blue)
    static let red = color(.red)
    static let grey = color(.grey)

    /// A card's or a panel's quiet background, a little lighter than the window in dark mode.
    static let surface = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0, alpha: 0.035)
    })

    /// The hairline around a card.
    static let stroke = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.08)
    })

    static func color(_ tone: StatusTone) -> Color {
        Color(nsColor: nsColor(tone, alpha: 1, darkAlpha: 1))
    }

    /// The soft fill behind a chip or an icon of that tone.
    static func tint(_ tone: StatusTone) -> Color {
        Color(nsColor: nsColor(tone, alpha: 0.13, darkAlpha: 0.22))
    }

    /// A bar's fill by the menu bar's level rule: the accent color normally, orange low, red very low.
    static func level(_ level: MenuBarModel.Level) -> Color {
        switch level {
        case .low: orange
        case .veryLow: red
        case .normal, .unknown: .accentColor
        }
    }

    static func diffTint(added: Bool, strong: Bool = false) -> NSColor {
        nsColor(added ? .green : .red, alpha: strong ? 0.28 : 0.09, darkAlpha: strong ? 0.35 : 0.12)
    }

    static func syntax(_ kind: SyntaxHighlighter.Kind) -> NSColor {
        switch kind {
        case .comment: nsColor(.grey, alpha: 1, darkAlpha: 1)
        case .string: nsColor(.green, alpha: 1, darkAlpha: 1)
        case .number: nsColor(.orange, alpha: 1, darkAlpha: 1)
        case .keyword: nsColor(.blue, alpha: 1, darkAlpha: 1)
        case .type: .systemPurple
        case .plain: .labelColor
        }
    }

    private typealias RGB = (red: Double, green: Double, blue: Double)

    /// Light and dark values: darker in light mode and brighter in dark mode than the system colors, so words in
    /// them read on the window's background.
    private static func values(_ tone: StatusTone) -> (light: RGB, dark: RGB) {
        switch tone {
        case .green: ((0.13, 0.55, 0.27), (0.36, 0.80, 0.47))
        case .orange: ((0.80, 0.42, 0.00), (1.00, 0.64, 0.25))
        case .blue: ((0.00, 0.40, 0.82), (0.40, 0.67, 1.00))
        case .red: ((0.78, 0.17, 0.15), (1.00, 0.42, 0.38))
        case .grey: ((0.40, 0.40, 0.43), (0.66, 0.66, 0.70))
        }
    }

    private static func nsColor(_ tone: StatusTone, alpha: Double, darkAlpha: Double) -> NSColor {
        let pair = values(tone)
        return NSColor(name: nil) { appearance in
            let dark = isDark(appearance)
            let rgb = dark ? pair.dark : pair.light
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: dark ? darkAlpha : alpha)
        }
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
