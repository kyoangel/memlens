import AppKit
import Testing
@testable import MemLensCore

@MainActor
@Suite struct StatusIconRendererTests {
    /// Renders the icon at 4x into an RGBA bitmap under the given appearance.
    private func render(_ level: PressureLevel, _ name: NSAppearance.Name) throws -> NSBitmapImageRep {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = StatusIconRenderer.size
        let appearance = try #require(NSAppearance(named: name))
        let image = StatusIconRenderer.image(for: level)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appearance.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(origin: .zero, size: StatusIconRenderer.size))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Pixel at a point given in icon points, y-down (same as the spec geometry).
    private func pixel(_ rep: NSBitmapImageRep, x: CGFloat, y: CGFloat) throws -> NSColor {
        let color = try #require(rep.colorAt(x: Int(x * 4), y: Int(y * 4)))
        return try #require(color.usingColorSpace(.deviceRGB))
    }

    private func resolved(_ color: NSColor, _ name: NSAppearance.Name) throws -> NSColor {
        var out: NSColor?
        try #require(NSAppearance(named: name)).performAsCurrentDrawingAppearance {
            out = color.usingColorSpace(.deviceRGB)
        }
        return try #require(out)
    }

    private func close(_ a: NSColor, _ b: NSColor, tolerance: CGFloat = 0.08) -> Bool {
        abs(a.redComponent - b.redComponent) < tolerance
            && abs(a.greenComponent - b.greenComponent) < tolerance
            && abs(a.blueComponent - b.blueComponent) < tolerance
    }

    @Test func imageIsSixteenPointsAndNotTemplate() {
        let image = StatusIconRenderer.image(for: .normal)
        #expect(image.size == NSSize(width: 16, height: 16))
        #expect(image.isTemplate == false)
    }

    @Test func lensColorsMatchPressure() {
        #expect(StatusIconRenderer.lensColor(for: .normal) == .systemGreen)
        #expect(StatusIconRenderer.lensColor(for: .warning) == .systemOrange)
        #expect(StatusIconRenderer.lensColor(for: .critical) == .systemRed)
    }

    @Test(arguments: [PressureLevel.normal, .warning, .critical])
    func lensCenterIsPressureColor(level: PressureLevel) throws {
        for name in [NSAppearance.Name.darkAqua, .aqua] {
            let rep = try render(level, name)
            // (7, 9) is inside the lens (r 2.6 around 8,8) and away from the glint.
            let got = try pixel(rep, x: 7, y: 9)
            let want = try resolved(StatusIconRenderer.lensColor(for: level), name)
            #expect(close(got, want), "level \(level) under \(name.rawValue): got \(got)")
        }
    }

    @Test func chipOutlineFollowsAppearance() throws {
        // (3.1, 8) sits on the chip's left edge stroke (x 2.3...3.7).
        let dark = try pixel(try render(.normal, .darkAqua), x: 3.1, y: 8)
        #expect(dark.alphaComponent > 0.5)
        #expect(dark.redComponent > 0.85 && dark.greenComponent > 0.85 && dark.blueComponent > 0.85)

        let light = try pixel(try render(.normal, .aqua), x: 3.1, y: 8)
        #expect(light.alphaComponent > 0.5)
        #expect(light.redComponent < 0.2 && light.greenComponent < 0.2 && light.blueComponent < 0.2)
    }

    @Test func chipDoesNotChangeWithPressure() throws {
        let normal = try pixel(try render(.normal, .darkAqua), x: 3.1, y: 8)
        let critical = try pixel(try render(.critical, .darkAqua), x: 3.1, y: 8)
        #expect(close(normal, critical, tolerance: 0.02))
    }

    @Test func cornerOutsideChipIsTransparent() throws {
        let corner = try pixel(try render(.critical, .darkAqua), x: 0.5, y: 0.5)
        #expect(corner.alphaComponent < 0.05)
    }
}
