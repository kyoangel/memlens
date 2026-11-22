import AppKit

/// Draws the menu bar icon: a memory chip (menu bar foreground color) with a
/// colored lens in the middle (the only pressure signal).
///
/// Not a template image: a template image is flattened to one color, which would
/// lose the lens color. The chip color is resolved inside the drawing handler, so
/// AppKit applies the appearance of whatever is drawing it (the menu bar).
public enum StatusIconRenderer {
    public static let size = NSSize(width: 16, height: 16)

    public static func lensColor(for level: PressureLevel) -> NSColor {
        switch level {
        case .normal: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    public static func image(for level: PressureLevel) -> NSImage {
        let lens = lensColor(for: level)
        let image = NSImage(size: size, flipped: true) { _ in
            drawChip(color: .labelColor)
            drawLens(color: lens)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawChip(color: NSColor) {
        color.setStroke()

        let body = NSBezierPath(
            roundedRect: NSRect(x: 3, y: 3, width: 10, height: 10), xRadius: 2, yRadius: 2)
        body.lineWidth = 1.4
        body.stroke()

        let pins = NSBezierPath()
        pins.lineWidth = 1.2
        pins.lineCapStyle = .round
        for c in [6.0, 10.0] {
            pins.move(to: NSPoint(x: c, y: 1)); pins.line(to: NSPoint(x: c, y: 3))     // top
            pins.move(to: NSPoint(x: c, y: 13)); pins.line(to: NSPoint(x: c, y: 15))   // bottom
            pins.move(to: NSPoint(x: 1, y: c)); pins.line(to: NSPoint(x: 3, y: c))     // left
            pins.move(to: NSPoint(x: 13, y: c)); pins.line(to: NSPoint(x: 15, y: c))   // right
        }
        pins.stroke()
    }

    private static func drawLens(color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: circle(cx: 8, cy: 8, r: 2.6)).fill()
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: circle(cx: 8.9, cy: 7.1, r: 0.7)).fill()
    }

    private static func circle(cx: CGFloat, cy: CGFloat, r: CGFloat) -> NSRect {
        NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
    }
}
