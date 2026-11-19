import AppKit

// Draws the app icon: a white multi-well plate on a tile in the department's navy-to-pale-blue banner colours, with wells glowing in
// immunofluorescence colours (488 green, 594 red, DAPI blue).

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
    let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: 186, yRadius: 186)
    withShadow(rgb(0x000000, 0.35), blur: 30, dy: -14) { rgb(0x1E4A83).setFill(); tile.fill() }
    NSGradient(colors: [rgb(0x163C70), rgb(0x1E4A83), rgb(0x4A78B8), rgb(0xA9C0E2)], atLocations: [0, 0.3, 0.72, 1], colorSpace: .sRGB)?.draw(in: tile, angle: 50)

    // Soft light bloom, top-left
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(colors: [rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0)])?
        .draw(fromCenter: NSPoint(x: 360, y: 820), radius: 0, toCenter: NSPoint(x: 360, y: 820), radius: 520, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // Plate
    let plateRect = NSRect(x: 182, y: 282, width: 660, height: 460)
    let plate = NSBezierPath(roundedRect: plateRect, xRadius: 54, yRadius: 54)
    withShadow(rgb(0x0B2247, 0.5), blur: 36, dy: -18) { NSColor.white.setFill(); plate.fill() }
    NSGradient(colors: [rgb(0xE8EEF6), rgb(0xFFFFFF)])?.draw(in: plate, angle: 90)
    rgb(0xFFFFFF, 0.9).setStroke(); plate.lineWidth = 3; plate.stroke()

    // Wells
    let cols = 6, rows = 4
    let d: CGFloat = 78
    let gapX = (plateRect.width - 2 * 46 - CGFloat(cols) * d) / CGFloat(cols - 1)
    let gapY = (plateRect.height - 2 * 44 - CGFloat(rows) * d) / CGFloat(rows - 1)
    let green: (UInt32, UInt32) = (0xB9FFB0, 0x1FAE4E)
    let red: (UInt32, UInt32) = (0xFFC1A8, 0xE23A3A)
    let blue: (UInt32, UInt32) = (0xBFD8FF, 0x2F66DD)
    for r in 0..<rows {
        for c in 0..<cols {
            let x = plateRect.minX + 46 + CGFloat(c) * (d + gapX)
            let y = plateRect.maxY - 44 - d - CGFloat(r) * (d + gapY)
            let well = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: d, height: d))
            var dye: (UInt32, UInt32)? = nil
            if r == 1 && c >= 1 { dye = green }
            if r == 2 && c >= 1 { dye = red }
            if r == 3 && c >= 3 { dye = blue }
            if let (light, dark) = dye {
                withShadow(rgb(dark, 0.55), blur: 14, dy: 0) { rgb(dark).setFill(); well.fill() }
                NSGradient(colors: [rgb(light), rgb(dark)])?
                    .draw(in: well, relativeCenterPosition: NSPoint(x: -0.25, y: 0.3))
            } else {
                NSGradient(colors: [rgb(0xCBD7E8), rgb(0xEDF2F9)])?.draw(in: well, angle: 90)
                rgb(0xB3C3DB).setStroke(); well.lineWidth = 2; well.stroke()
            }
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
