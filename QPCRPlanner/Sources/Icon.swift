import AppKit

// App icon: amplification curves on a white panel, on the same navy tile as the ICC Plate Planner.

private func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

private func withShadow(_ color: NSColor, blur: CGFloat, dy: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowColor = color
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: dy)
    s.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func makeIcon(_ path: String) {
    let n = 1024
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Tile
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
    withShadow(rgb(0x000000, 0.35), blur: 30, dy: -14) { rgb(0x1E4A83).setFill(); tile.fill() }
    NSGradient(colors: [rgb(0x163C70), rgb(0x1E4A83), rgb(0x4A78B8), rgb(0xA9C0E2)], atLocations: [0, 0.3, 0.72, 1], colorSpace: .sRGB)?.draw(in: tile, angle: 50)
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(colors: [rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0)])?
        .draw(fromCenter: NSPoint(x: 360, y: 820), radius: 0, toCenter: NSPoint(x: 360, y: 820), radius: 520, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // Panel
    let panelRect = NSRect(x: 182, y: 262, width: 660, height: 500)
    let panel = NSBezierPath(roundedRect: panelRect, xRadius: 54, yRadius: 54)
    withShadow(rgb(0x0B2247, 0.5), blur: 36, dy: -18) { NSColor.white.setFill(); panel.fill() }
    NSGradient(colors: [rgb(0xE8EEF6), rgb(0xFFFFFF)])?.draw(in: panel, angle: 90)

    // Plot area
    let x0: CGFloat = 262, x1: CGFloat = 782, y0: CGFloat = 342, y1: CGFloat = 692
    let axes = NSBezierPath()
    axes.move(to: NSPoint(x: x0, y: y1)); axes.line(to: NSPoint(x: x0, y: y0)); axes.line(to: NSPoint(x: x1, y: y0))
    axes.lineWidth = 12; axes.lineCapStyle = .round; axes.lineJoinStyle = .round
    rgb(0x1E4A83).setStroke(); axes.stroke()

    // threshold
    let thr = NSBezierPath()
    thr.move(to: NSPoint(x: x0 + 20, y: y0 + 105)); thr.line(to: NSPoint(x: x1, y: y0 + 105))
    thr.lineWidth = 6
    thr.setLineDash([18, 16], count: 2, phase: 0)
    rgb(0x8FA3BF).setStroke(); thr.stroke()

    // amplification curves (sigmoids rising at different cycles)
    let curves: [(UInt32, CGFloat, CGFloat)] = [(0x2FA84F, 0.34, 0.96), (0xE2483D, 0.50, 0.88), (0x2F6FE0, 0.66, 0.78), (0xF2A900, 0.80, 0.62)]
    for (color, mid, height) in curves {
        let p = NSBezierPath()
        let steps = 80
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let s = 1 / (1 + exp(-(t - mid) * 16))
            let pt = NSPoint(x: x0 + 22 + t * (x1 - x0 - 30), y: y0 + 22 + s * height * (y1 - y0 - 40))
            if i == 0 { p.move(to: pt) } else { p.line(to: pt) }
        }
        p.lineWidth = 17; p.lineCapStyle = .round; p.lineJoinStyle = .round
        withShadow(rgb(color, 0.35), blur: 10, dy: 0) { rgb(color).setStroke(); p.stroke() }
    }

    NSGraphicsContext.restoreGraphicsState()
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
