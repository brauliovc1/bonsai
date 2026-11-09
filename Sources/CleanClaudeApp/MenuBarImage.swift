import AppKit
import CleanAppModel

/// The menu-bar label as one image: the bonsai glyph and, after it, a thin rounded bar filled to the part
/// of the disk in use.
///
/// A MenuBarExtra label is drawn as a template image unless its image says otherwise, and a template has no
/// colour. So in the normal state the image is a template (the menu bar tints it for its light or dark
/// look); below the low-space warning it is not, and the drawing picks its own ink: the label colour of
/// the appearance it is drawn in (the drawing handler runs at draw time, in the status item's appearance)
/// with the fill in system orange, or red under half the warning.
enum MenuBarImage {
    static let glyphSize: CGFloat = 16
    static let gap: CGFloat = 3
    static let barSize = CGSize(width: 28, height: 6)
    static let size = NSSize(width: glyphSize + gap + barSize.width, height: glyphSize)

    static func make(fraction: Double, level: MenuBarModel.Level, description: String) -> NSImage {
        let isTemplate = level == .normal || level == .unknown
        let fill = min(max(fraction, 0), 1)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let ink = isTemplate ? CGColor(gray: 0, alpha: 1) : NSColor.labelColor.cgColor
            draw(in: context, ink: ink, fillColor: fillColor(level) ?? ink, fill: fill)
            return true
        }
        image.isTemplate = isTemplate
        image.accessibilityDescription = description
        return image
    }

    /// nil = the ink colour.
    private static func fillColor(_ level: MenuBarModel.Level) -> CGColor? {
        switch level {
        case .unknown, .normal: nil
        case .low: NSColor.systemOrange.cgColor
        case .veryLow: NSColor.systemRed.cgColor
        }
    }

    /// Glyph at the left, bar centred on the right, in a flipped context of `size`.
    private static func draw(in context: CGContext, ink: CGColor, fillColor: CGColor, fill: Double) {
        context.saveGState()
        let scale = glyphSize / BonsaiGlyph.grid
        context.scaleBy(x: scale, y: scale)
        context.addPath(BonsaiGlyph.silhouette())
        context.setFillColor(ink)
        context.fillPath()
        context.restoreGState()

        let bar = CGRect(
            x: glyphSize + gap, y: (glyphSize - barSize.height) / 2, width: barSize.width, height: barSize.height
        )
        let radius = barSize.height / 2
        let track = CGPath(roundedRect: bar, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.saveGState()
        context.addPath(track)
        context.clip()
        context.setFillColor(ink.copy(alpha: ink.alpha * 0.2) ?? ink)
        context.fill(bar)
        context.setFillColor(fillColor)
        context.fill(CGRect(x: bar.minX, y: bar.minY, width: bar.width * fill, height: bar.height))
        context.restoreGState()

        let outline = CGPath(
            roundedRect: bar.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius - 0.5, cornerHeight: radius - 0.5,
            transform: nil
        )
        context.addPath(outline)
        context.setStrokeColor(ink.copy(alpha: ink.alpha * 0.6) ?? ink)
        context.setLineWidth(1)
        context.strokePath()
    }
}
