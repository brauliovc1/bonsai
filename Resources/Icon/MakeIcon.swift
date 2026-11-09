import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws Bonsai's app icon: the menu-bar glyph's silhouette (Sources/CleanClaudeApp/BonsaiGlyph.swift) in
// colour on a macOS rounded square. `make icon` builds and runs it, then turns the PNGs into
// Resources/AppIcon.icns with iconutil:
//
//   swiftc -swift-version 6 -parse-as-library -o build/icon/make-icon \
//       Resources/Icon/MakeIcon.swift Sources/CleanClaudeApp/BonsaiGlyph.swift
//   build/icon/make-icon build/icon/AppIcon.iconset
//   iconutil -c icns -o Resources/AppIcon.icns build/icon/AppIcon.iconset
//
// Every size is drawn from the shapes, not scaled down from the largest.

@main
enum MakeIcon {
    /// iconutil's file names and their pixel sizes.
    static let files: [(name: String, pixels: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]

    static func main() throws {
        guard let folder = CommandLine.arguments.dropFirst().first else {
            FileHandle.standardError.write(Data("usage: make-icon <folder.iconset>\n".utf8))
            exit(2)
        }
        let output = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for file in files {
            let image = try draw(pixels: file.pixels)
            try writePNG(image, to: output.appending(path: "\(file.name).png"))
        }
        print("wrote \(files.count) images to \(output.path)")
    }

    static func draw(pixels: Int) throws -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw IconError.context }
        let scale = CGFloat(pixels) / 1024
        // A 1024-point canvas with y going down, like the glyph's grid.
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: scale, y: -scale)
        let small = pixels <= 32
        IconArt(context: context, detailed: !small).draw()
        guard let image = context.makeImage() else { throw IconError.context }
        return image
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw IconError.write(url.path) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw IconError.write(url.path) }
    }

    enum IconError: Error {
        case context
        case write(String)
    }
}

/// The picture on a 1024 canvas (y down): Apple's macOS grid puts the 824-point rounded square 100 points in.
struct IconArt {
    let context: CGContext
    /// Shadows and the small highlights; left out at 16 and 32 pixels, where they only blur the shape.
    let detailed: Bool

    static let body = CGRect(x: 100, y: 100, width: 824, height: 824)

    func draw() {
        let square = Self.squircle(in: Self.body)
        if detailed {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 12), blur: 24, color: color(0x000000, 0.28))
            context.addPath(square)
            context.setFillColor(color(0xF6E9D2))
            context.fillPath()
            context.restoreGState()
        }
        context.saveGState()
        context.addPath(square)
        context.clip()
        gradient([color(0xFFF7E8), color(0xF1DDBB)], from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))
        drawTree()
        context.restoreGState()
    }

    private func drawTree() {
        // The glyph's 64 grid, its shape centred in the square with room around it.
        context.saveGState()
        // A little larger at 16 and 32 pixels, where every pixel of the shape counts.
        let unit: CGFloat = detailed ? 11.4 : 12.6
        context.translateBy(x: 512 - 31 * unit, y: 530 - 30 * unit)
        context.scaleBy(x: unit, y: unit)

        if detailed {
            fill(CGPath(ellipseIn: CGRect(x: 13, y: 55.2, width: 38, height: 4), transform: nil), color(0x7A5530, 0.22))
        }
        // Back to front: pot, soil, trunk (its foot hidden behind the rim), rim, foliage.
        let pot = BonsaiGlyph.pot()
        shaded(pot, base: color(0x2E4A66), light: color(0x4A7096), shift: CGSize(width: -0.8, height: -0.9))
        if detailed {
            fill(CGPath(ellipseIn: CGRect(x: 17, y: 43.2, width: 30, height: 2), transform: nil), color(0x3B2A1E))
        }
        clipped(to: CGPath(rect: CGRect(x: 0, y: 0, width: BonsaiGlyph.grid, height: 46), transform: nil)) {
            shaded(BonsaiGlyph.trunk(), base: color(0x4F3424), light: color(0x86603F), shift: CGSize(width: -0.7, height: -0.4))
        }
        fill(CGPath(roundedRect: CGRect(x: 13, y: 44, width: 38, height: 4.5), cornerWidth: 1.5, cornerHeight: 1.5,
                    transform: nil), color(0x5A82A8))

        for pad in BonsaiGlyph.foliage() {
            shaded(pad, base: color(0x2C7438), light: color(0x5BAE4C), shift: CGSize(width: -0.9, height: -1.4))
            if detailed {
                clipped(to: pad) {
                    var move = CGAffineTransform(translationX: -2.4, y: -3.0)
                    fill(pad.copy(using: &move) ?? pad, color(0x9AD983, 0.55))
                }
            }
        }
        context.restoreGState()
    }

    /// The base colour, then the lighter colour shifted up-left inside the shape: lit from the top left.
    private func shaded(_ path: CGPath, base: CGColor, light: CGColor, shift: CGSize) {
        fill(path, base)
        clipped(to: path) {
            var move = CGAffineTransform(translationX: shift.width, y: shift.height)
            fill(path.copy(using: &move) ?? path, light)
        }
    }

    private func clipped(to path: CGPath, _ body: () -> Void) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        body()
        context.restoreGState()
    }

    private func fill(_ path: CGPath, _ fillColor: CGColor) {
        context.addPath(path)
        context.setFillColor(fillColor)
        context.fillPath()
    }

    private func gradient(_ colors: [CGColor], from start: CGPoint, to end: CGPoint) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil) else { return }
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
    }

    private func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
        )
    }

    /// A superellipse (|x|^5 + |y|^5 = 1), close to the continuous corners of macOS icons.
    static func squircle(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let steps = 720
        let exponent = 2.0 / 5.0
        for step in 0..<steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let cosine = cos(angle), sine = sin(angle)
            let x = rect.midX + rect.width / 2 * CGFloat(copysign(pow(abs(cosine), exponent), cosine))
            let y = rect.midY + rect.height / 2 * CGFloat(copysign(pow(abs(sine), exponent), sine))
            if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}
