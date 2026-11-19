import AppKit

// The installer window's background: 660 × 420 points, drawn at 1x and 2x.
let W: CGFloat = 660, H: CGFloat = 420
let version = CommandLine.arguments[1]
let logoPath = CommandLine.arguments[2]
let out = CommandLine.arguments[3]

func hex(_ h: String, _ a: CGFloat = 1) -> NSColor {
    let v = UInt32(h, radix: 16) ?? 0
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ font: NSFont, _ color: NSColor, center: Bool = false, width: CGFloat = 600) {
    let p = NSMutableParagraphStyle()
    p.alignment = center ? .center : .left
    p.lineSpacing = 2
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
    let r = CGRect(x: center ? x - width / 2 : x, y: y, width: width, height: 80)
    (s as NSString).draw(with: r, options: [.usesLineFragmentOrigin], attributes: attrs)
}

func serif(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size) ?? base
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let c = ctx.cgContext
    // top-down coordinates
    c.translateBy(x: 0, y: H); c.scaleBy(x: 1, y: -1)
    let flipped = NSGraphicsContext(cgContext: c, flipped: true)
    NSGraphicsContext.current = flipped

    // page: white to pale blue
    NSGradient(colors: [hex("FFFFFF"), hex("E8EEF6")])!.draw(in: CGRect(x: 0, y: 0, width: W, height: H), angle: 90)

    // header band, navy to blue
    let band = CGRect(x: 0, y: 0, width: W, height: 88)
    NSGradient(colors: [hex("1E4A83"), hex("2F6BC0"), hex("4A78B8")])!.draw(in: band, angle: 0)
    // a DNA helix turning across the band, beads in the dye colours
    let k = 2 * CGFloat.pi / 62, mid: CGFloat = 29, amp: CGFloat = 13
    for (strand, alpha) in [(CGFloat(1), CGFloat(0.7)), (-1, 0.4)] {
        let path = NSBezierPath()
        var x: CGFloat = 330
        while x <= W - 20 {
            let p = CGPoint(x: x, y: mid + amp * strand * sin(k * x))
            if x == 330 { path.move(to: p) } else { path.line(to: p) }
            x += 2
        }
        NSColor(white: 1, alpha: alpha).setStroke()
        path.lineWidth = 1.8
        path.stroke()
    }
    let dyes = ["3DDC6E", "FF5A4E", "5B8CFF", "E061FF"]
    var x: CGFloat = 336
    var n = 0
    while x <= W - 26 {
        let s = sin(k * x), depth = cos(k * x)
        NSColor(white: 1, alpha: 0.22).setStroke()
        let rung = NSBezierPath(); rung.move(to: CGPoint(x: x, y: mid + amp * s)); rung.line(to: CGPoint(x: x, y: mid - amp * s)); rung.lineWidth = 1.2; rung.stroke()
        let r = 2.2 + 1.2 * depth
        hex(dyes[n % 4], 0.6 + 0.35 * depth).setFill()
        NSBezierPath(ovalIn: CGRect(x: x - r, y: mid + amp * s - r, width: 2 * r, height: 2 * r)).fill()
        x += 10.33; n += 1
    }
    text("ICC Plate Planner", 28, 16, serif(30, .bold), .white)
    text("Department of Regenerative Medicine Research · Kobe City Medical Center General Hospital", 30, 56, .systemFont(ofSize: 11, weight: .medium), NSColor(white: 1, alpha: 0.85))

    // soft pads under the two icons
    for cx in [CGFloat(170), 490] {
        let pad = CGRect(x: cx - 78, y: 138, width: 156, height: 156)
        let shadow = NSShadow(); shadow.shadowColor = hex("1E4A83", 0.12); shadow.shadowBlurRadius = 14; shadow.shadowOffset = NSSize(width: 0, height: -3)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        hex("FFFFFF").setFill()
        NSBezierPath(roundedRect: pad, xRadius: 28, yRadius: 28).fill()
        NSGraphicsContext.restoreGraphicsState()
        hex("D5DEEB").setStroke()
        let b = NSBezierPath(roundedRect: pad, xRadius: 28, yRadius: 28); b.lineWidth = 1; b.stroke()
    }

    // the arrow: from the app to Applications
    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 262, y: 206))
    arrow.curve(to: CGPoint(x: 396, y: 206), controlPoint1: CGPoint(x: 300, y: 176), controlPoint2: CGPoint(x: 358, y: 176))
    hex("4A78B8").setStroke()
    arrow.lineWidth = 3
    arrow.setLineDash([7, 6], count: 2, phase: 0)
    arrow.lineCapStyle = .round
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: CGPoint(x: 384, y: 192)); head.line(to: CGPoint(x: 400, y: 208)); head.line(to: CGPoint(x: 380, y: 214))
    head.lineWidth = 3; head.lineCapStyle = .round; head.lineJoinStyle = .round
    head.stroke()
    text("Drag to install", 330, 150, .systemFont(ofSize: 13, weight: .semibold), hex("1E4A83"), center: true, width: 200)

    // steps and the first-launch note
    hex("D5DEEB").setFill()
    NSBezierPath(rect: CGRect(x: 30, y: 322, width: W - 60, height: 1)).fill()
    text("1   Drag ICC Plate Planner onto Applications.     2   Open it from Applications or Launchpad.", 30, 332, .systemFont(ofSize: 12, weight: .semibold), hex("172033"))
    text("First launch: if macOS says it can’t check the app, open System Settings → Privacy & Security and click “Open Anyway”. You only do this once.",
         30, 352, .systemFont(ofSize: 11), hex("4F5D73"), width: W - 60)
    text("Version \(version)  ·  Created by Joey Russell  ·  Apple silicon and Intel, macOS 13 or later", 30, 392, .systemFont(ofSize: 10), hex("8A99AF"), width: W - 60)

    // the department logo, bottom right of the band
    if let logo = NSImage(contentsOfFile: logoPath) {
        let h: CGFloat = 0
        _ = h
        _ = logo
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (scale, name) in [(CGFloat(1), "bg.png"), (2, "bg@2x.png")] {
    let rep = render(scale: scale)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out + "/" + name))
}
print("drawn")
