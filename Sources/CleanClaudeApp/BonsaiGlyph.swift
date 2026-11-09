import CoreGraphics

/// The bonsai silhouette: three foliage pads on a curved trunk in a pot, on a 64 x 64 grid with y going
/// down. The menu-bar label fills it in one colour; the app icon (Resources/Icon/MakeIcon.swift, which
/// compiles this file too) colours the parts. CoreGraphics only, so both can use it.
enum BonsaiGlyph {
    static let grid: CGFloat = 64

    /// Rim and body of the pot.
    static func pot() -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: 13, y: 44, width: 38, height: 4.5), cornerWidth: 1.5, cornerHeight: 1.5)
        path.addLines(between: [
            CGPoint(x: 16, y: 48), CGPoint(x: 48, y: 48), CGPoint(x: 44.5, y: 56.5), CGPoint(x: 19.5, y: 56.5),
        ])
        path.closeSubpath()
        return path
    }

    /// The trunk (thicker at the base), its root flare and the two branches, as filled outlines.
    static func trunk() -> CGPath {
        let lower = CGMutablePath()
        lower.move(to: CGPoint(x: 31, y: 44.5))
        lower.addCurve(to: CGPoint(x: 29.5, y: 28.5), control1: CGPoint(x: 24, y: 37), control2: CGPoint(x: 23, y: 32))
        let upper = CGMutablePath()
        upper.move(to: CGPoint(x: 29.5, y: 28.5))
        upper.addCurve(to: CGPoint(x: 32.5, y: 15), control1: CGPoint(x: 35, y: 25.5), control2: CGPoint(x: 37, y: 21))
        let left = CGMutablePath()
        left.move(to: CGPoint(x: 27, y: 32.5))
        left.addQuadCurve(to: CGPoint(x: 16, y: 30), control: CGPoint(x: 21, y: 30.5))
        let right = CGMutablePath()
        right.move(to: CGPoint(x: 34, y: 24.5))
        right.addQuadCurve(to: CGPoint(x: 45, y: 22.5), control: CGPoint(x: 40, y: 22))
        let flare = CGMutablePath()
        flare.addLines(between: [CGPoint(x: 24.5, y: 44.5), CGPoint(x: 37.5, y: 44.5), CGPoint(x: 30.5, y: 37.5)])
        flare.closeSubpath()

        let path = CGMutablePath()
        for (stroke, width) in [(lower, 6.0), (upper, 4.4), (left, 2.8), (right, 2.6)] as [(CGPath, CGFloat)] {
            path.addPath(stroke.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 4))
        }
        path.addPath(flare)
        return path
    }

    /// The three pads, top first; each a cloud of ellipses.
    static func foliage() -> [CGPath] {
        [
            cloud([(32, 12.5, 12, 6.5), (23.5, 14, 5, 5), (40.5, 13.5, 5.5, 5.5), (32, 8, 5, 5)]),
            cloud([(15, 28, 9.5, 5), (9, 29.5, 4, 4), (19, 25.5, 4.5, 4.5)]),
            cloud([(47.5, 20.5, 9, 4.8), (53, 22, 3.8, 3.8), (44, 18, 4.2, 4.2)]),
        ]
    }

    /// Every part as one shape, overlaps merged, for a one-colour fill that may be translucent.
    static func silhouette() -> CGPath {
        var result = pot().union(trunk())
        for pad in foliage() { result = result.union(pad) }
        return result
    }

    /// Ellipses given as (center x, center y, radius x, radius y), merged.
    private static func cloud(_ ellipses: [(CGFloat, CGFloat, CGFloat, CGFloat)]) -> CGPath {
        ellipses.map { x, y, rx, ry in
            CGPath(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2), transform: nil)
        }
        .reduce(CGMutablePath() as CGPath) { $0.isEmpty ? $1 : $0.union($1) }
    }
}
