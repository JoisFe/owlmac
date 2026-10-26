import AppKit

enum OwlFace {
    case asleep    // eyes shut, dimmed — nothing keeps the Mac awake
    case watching  // heavy-lidded — auto-detect is on, waiting for work
    case awake     // big amber eyes — sleep is blocked
    case blink     // one frame of a blink while awake
}

/// Draws the owl. All geometry lives in a 20×18 design space with y pointing down.
enum OwlIcon {
    static let amber = NSColor(srgbRed: 1.0, green: 0.71, blue: 0.13, alpha: 1)
    private static let pupil = NSColor(srgbRed: 0.08, green: 0.07, blue: 0.14, alpha: 1)
    private static let canvas = NSSize(width: 20, height: 18)
    private static let eyeCenters = [NSPoint(x: 6.8, y: 8.6), NSPoint(x: 13.2, y: 8.6)]

    private static var cache: [OwlFace: NSImage] = [:]

    // MARK: Menu bar

    /// Redraws itself whenever the menu bar flips between light and dark.
    static func statusImage(_ face: OwlFace) -> NSImage {
        if let cached = cache[face] { return cached }
        let image = NSImage(size: canvas, flipped: true) { _ in
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let ink = dark ? NSColor.white : NSColor.black
            draw(face, ink: face == .asleep ? ink.withAlphaComponent(0.5) : ink)
            return true
        }
        image.accessibilityDescription = switch face {
        case .asleep: "OwlMac: 잠자는 중"
        case .watching: "OwlMac: 지켜보는 중"
        case .awake, .blink: "OwlMac: 깨어 있음"
        }
        cache[face] = image
        return image
    }

    /// Fills the owl silhouette with `ink`; eyes and beak are holes so the background shows through.
    static func draw(_ face: OwlFace, ink: NSColor) {
        let shape = bodyPath()
        shape.windingRule = .evenOdd
        for center in eyeCenters {
            switch face {
            case .asleep, .blink: shape.append(closedEye(at: center))
            case .watching: shape.append(sleepyEye(at: center))
            case .awake: shape.append(circle(center, 3.15))
            }
        }
        shape.append(beak())
        ink.setFill()
        shape.fill()

        guard face == .awake else { return }
        for center in eyeCenters {
            amber.setFill()
            circle(center, 2.55).fill()
            pupil.setFill()
            circle(NSPoint(x: center.x, y: center.y + 0.25), 1.2).fill()
        }
    }

    private static func bodyPath() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 4, y: 1.5))  // left ear tuft
        p.curve(to: NSPoint(x: 16, y: 1.5), controlPoint1: NSPoint(x: 8, y: 4.5), controlPoint2: NSPoint(x: 12, y: 4.5))
        p.curve(to: NSPoint(x: 17, y: 11), controlPoint1: NSPoint(x: 17.2, y: 4), controlPoint2: NSPoint(x: 17.4, y: 7.5))
        p.curve(to: NSPoint(x: 10, y: 17.5), controlPoint1: NSPoint(x: 16.6, y: 15), controlPoint2: NSPoint(x: 13.5, y: 17.5))
        p.curve(to: NSPoint(x: 3, y: 11), controlPoint1: NSPoint(x: 6.5, y: 17.5), controlPoint2: NSPoint(x: 3.4, y: 15))
        p.curve(to: NSPoint(x: 4, y: 1.5), controlPoint1: NSPoint(x: 2.6, y: 7.5), controlPoint2: NSPoint(x: 2.8, y: 4))
        p.close()
        return p
    }

    /// A smiling crescent: ︶
    private static func closedEye(at c: NSPoint) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x - 2.5, y: c.y))
        p.curve(to: NSPoint(x: c.x + 2.5, y: c.y),
                controlPoint1: NSPoint(x: c.x - 1.5, y: c.y + 2.3), controlPoint2: NSPoint(x: c.x + 1.5, y: c.y + 2.3))
        p.curve(to: NSPoint(x: c.x - 2.5, y: c.y),
                controlPoint1: NSPoint(x: c.x + 1.5, y: c.y + 1.1), controlPoint2: NSPoint(x: c.x - 1.5, y: c.y + 1.1))
        p.close()
        return p
    }

    /// Lower half of the eye with the pupil peeking out under a flat lid.
    private static func sleepyEye(at c: NSPoint) -> NSBezierPath {
        let r: CGFloat = 2.9
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x - r, y: c.y - 0.2))
        p.line(to: NSPoint(x: c.x + r, y: c.y - 0.2))
        p.appendArc(withCenter: NSPoint(x: c.x, y: c.y - 0.2), radius: r, startAngle: 0, endAngle: 180, clockwise: false)
        p.close()
        p.append(circle(NSPoint(x: c.x, y: c.y + 1.2), 1.1))  // nested inside the hole → filled again
        return p
    }

    private static func beak() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 9.1, y: 11.4))
        p.line(to: NSPoint(x: 10.9, y: 11.4))
        p.line(to: NSPoint(x: 10, y: 13.2))
        p.close()
        return p
    }

    private static func circle(_ c: NSPoint, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    // MARK: App icon

    /// Writes a macOS .iconset folder (feed it to `iconutil -c icns`).
    static func writeIconset(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                let png = appIcon(pixels: base * scale).representation(using: .png, properties: [:])!
                try png.write(to: dir.appendingPathComponent(name))
            }
        }
    }

    /// A night-sky tile with a moon, a branch, and the wide-awake owl.
    private static func appIcon(pixels: Int) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: 1024, height: 1024)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        let flip = NSAffineTransform()
        flip.translateX(by: 0, yBy: 1024)
        flip.scaleX(by: 1, yBy: -1)
        flip.concat()

        let cream = NSColor(srgbRed: 0.96, green: 0.91, blue: 0.83, alpha: 1)

        // Tile
        let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
        NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.21, blue: 0.42, alpha: 1),
                   ending: NSColor(srgbRed: 0.07, green: 0.08, blue: 0.17, alpha: 1))!.draw(in: tile, angle: 90)
        tile.addClip()

        // Stars
        cream.withAlphaComponent(0.75).setFill()
        for (x, y, r) in [(220.0, 230.0, 7.0), (310, 170, 4), (420, 250, 5), (180, 380, 4), (860, 420, 5), (820, 560, 3.5)] {
            circle(NSPoint(x: x, y: y), r).fill()
        }

        // Crescent moon: the big disc minus an offset disc
        NSGraphicsContext.saveGraphicsState()
        let bite = NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024))
        bite.append(circle(NSPoint(x: 778, y: 222), 66))
        bite.windingRule = .evenOdd
        bite.addClip()
        amber.withAlphaComponent(0.95).setFill()
        circle(NSPoint(x: 740, y: 255), 78).fill()
        NSGraphicsContext.restoreGraphicsState()

        // Branch
        NSColor(srgbRed: 0.55, green: 0.36, blue: 0.24, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 150, y: 772, width: 724, height: 30), xRadius: 15, yRadius: 15).fill()

        // Owl, scaled up from the 20×18 menu bar design
        NSGraphicsContext.saveGraphicsState()
        let place = NSAffineTransform()
        place.translateX(by: 512 - 10 * 27, yBy: 300)
        place.scale(by: 27)
        place.concat()
        draw(.awake, ink: cream)
        NSGraphicsContext.restoreGraphicsState()

        // Feet gripping the branch
        cream.setFill()
        for x in [452.0, 572.0] {
            NSBezierPath(roundedRect: NSRect(x: x - 22, y: 764, width: 44, height: 22), xRadius: 11, yRadius: 11).fill()
        }
        return rep
    }
}
