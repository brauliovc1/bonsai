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

    /// The trunk (tapering from the root flare up into the top pad) and the two branches, as one outline.
    static func trunk() -> CGPath {
        let trunk = tapered(
            [
                [CGPoint(x: 31, y: 45), CGPoint(x: 24, y: 37.5), CGPoint(x: 23, y: 32), CGPoint(x: 29.5, y: 28.5)],
                [CGPoint(x: 29.5, y: 28.5), CGPoint(x: 35, y: 25.5), CGPoint(x: 37, y: 21), CGPoint(x: 32.5, y: 14)],
            ],
            from: 6.4, to: 3.4
        )
        let left = tapered(
            [[CGPoint(x: 26.5, y: 32.8), CGPoint(x: 23, y: 31), CGPoint(x: 19.5, y: 30.2), CGPoint(x: 15, y: 30)]],
            from: 3, to: 1.6
        )
        let right = tapered(
            [[CGPoint(x: 33.5, y: 25), CGPoint(x: 37, y: 22.8), CGPoint(x: 40.5, y: 22.2), CGPoint(x: 46, y: 22.5)]],
            from: 2.8, to: 1.5
        )
        // The root flare: concave sides from the pot's soil into the trunk.
        let flare = CGMutablePath()
        flare.move(to: CGPoint(x: 22.5, y: 44.8))
        flare.addQuadCurve(to: CGPoint(x: 25.4, y: 40.4), control: CGPoint(x: 25.6, y: 43.9))
        flare.addLine(to: CGPoint(x: 30.6, y: 40.4))
        flare.addQuadCurve(to: CGPoint(x: 38.5, y: 44.8), control: CGPoint(x: 32.4, y: 43.9))
        flare.closeSubpath()
        return trunk.union(left).union(right).union(flare)
    }

    /// A filled outline along a chain of cubic Béziers (each [start, control 1, control 2, end]) whose
    /// width goes from `start` to `end`, with round ends.
    private static func tapered(_ curves: [[CGPoint]], from start: CGFloat, to end: CGFloat) -> CGPath {
        let steps = 24
        var points: [CGPoint] = []
        for curve in curves {
            for step in 0...steps where !(step == 0 && !points.isEmpty) {
                let t = CGFloat(step) / CGFloat(steps)
                let u = 1 - t
                let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                points.append(CGPoint(
                    x: a * curve[0].x + b * curve[1].x + c * curve[2].x + d * curve[3].x,
                    y: a * curve[0].y + b * curve[1].y + c * curve[2].y + d * curve[3].y
                ))
            }
        }
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for (index, point) in points.enumerated() {
            let previous = points[max(index - 1, 0)], next = points[min(index + 1, points.count - 1)]
            let dx = next.x - previous.x, dy = next.y - previous.y
            let length = max((dx * dx + dy * dy).squareRoot(), 0.0001)
            let half = (start + (end - start) * CGFloat(index) / CGFloat(points.count - 1)) / 2
            let normal = CGPoint(x: -dy / length * half, y: dx / length * half)
            left.append(CGPoint(x: point.x + normal.x, y: point.y + normal.y))
            right.append(CGPoint(x: point.x - normal.x, y: point.y - normal.y))
        }
        let outline = CGMutablePath()
        outline.addLines(between: left + right.reversed())
        outline.closeSubpath()
        let caps = CGMutablePath()
        for (point, width) in [(points[0], start), (points[points.count - 1], end)] {
            caps.addEllipse(in: CGRect(x: point.x - width / 2, y: point.y - width / 2, width: width, height: width))
        }
        return outline.union(caps)
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
