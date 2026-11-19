import SwiftUI
import AppKit

// MARK: - Drawing helpers for the Core Animation surfaces
//
// SwiftUI refreshes the whole window for every animation frame, which made the always-running
// animations (Eppi walking, banner curves) cost 15–30 % of a CPU core. These two are drawn with plain
// Core Graphics in their own AppKit view instead: a frame repaints only the few square centimetres
// that changed, the timer runs only while the app is in front, and nothing else in the window is
// touched.

extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        let v = UInt32(hex, radix: 16) ?? 0x7F7F7F
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }
}

private func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

/// Thin drawing helper over a CGContext (the view is flipped: y grows downwards).
struct Pen {
    let c: CGContext

    func save() { c.saveGState() }
    func restore() { c.restoreGState() }
    func translate(_ x: CGFloat, _ y: CGFloat) { c.translateBy(x: x, y: y) }
    func rotate(_ a: Double) { c.rotate(by: CGFloat(a)) }
    func scale(_ x: CGFloat, _ y: CGFloat) { c.scaleBy(x: x, y: y) }
    func alpha(_ a: CGFloat) { c.setAlpha(a) }
    func clip(_ p: Path) { c.addPath(p.cgPath); c.clip() }

    func fill(_ p: Path, _ col: NSColor) {
        c.addPath(p.cgPath); c.setFillColor(col.cgColor); c.fillPath()
    }
    func stroke(_ p: Path, _ col: NSColor, _ w: CGFloat, round: Bool = false, dash: [CGFloat] = []) {
        c.addPath(p.cgPath)
        c.setStrokeColor(col.cgColor); c.setLineWidth(w)
        c.setLineCap(round ? .round : .butt); c.setLineJoin(round ? .round : .miter)
        c.setLineDash(phase: 0, lengths: dash)
        c.strokePath()
        c.setLineDash(phase: 0, lengths: [])
    }
    private func gradient(_ cols: [NSColor]) -> CGGradient? {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cols.map { $0.cgColor } as CFArray, locations: nil)
    }
    func linear(_ p: Path, _ cols: [NSColor], _ a: CGPoint, _ b: CGPoint) {
        guard let g = gradient(cols) else { return }
        save(); clip(p)
        c.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restore()
    }
    func shadow(_ col: NSColor, _ blur: CGFloat, _ dy: CGFloat) {
        c.setShadow(offset: CGSize(width: 0, height: -dy), blur: blur, color: col.cgColor)
    }
    /// Text centred on `at` (ax, ay = 0.5) or anchored by fractions of its size.
    func text(_ s: String, _ font: NSFont, _ col: NSColor, _ at: CGPoint, ax: CGFloat = 0.5, ay: CGFloat = 0.5) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: col]
        let str = s as NSString
        let size = str.size(withAttributes: attrs)
        str.draw(at: CGPoint(x: at.x - size.width * ax, y: at.y - size.height * ay), withAttributes: attrs)
    }
}

// MARK: - Eppi, drawn with Core Graphics

func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
private let funNS = ["2FA84F", "E2483D", "2F6FE0", "F2A900", "8E5BD1", "17A2A2", "1E4A83"].map { NSColor(hex: $0) }

/// Draws Eppi in a 120 × 170 box whose top-left corner is the current origin.
func paintEppi(_ pen: Pen, _ p: EppiPose) {
    let ink = NSColor(hex: "33425C")
    let cx = 60.0
    let baseY = 160.0
    let lift = Double(p.lift)

    let sh = max(0.35, 1 - lift / 100)
    pen.fill(Path(ellipseIn: CGRect(x: cx - 24 * sh, y: baseY - 3, width: 48 * sh, height: 7)), NSColor(white: 0, alpha: 0.18 * sh))

    if p.notes {
        for i in 0..<3 {
            let q = (p.t * 0.9 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
            let nx = cx + (i == 1 ? 34 : -30) + 8 * sin(p.t * 3 + Double(i))
            let ny = baseY - 110 - lift - q * 40
            pen.text(i == 1 ? "♫" : "♪", NSFont.systemFont(ofSize: 18, weight: .bold), funNS[i + 2].withAlphaComponent(1 - q), pt(nx, ny))
        }
    }
    if p.sparkle {
        for i in 0..<6 {
            let ang = Double(i) / 6 * 2 * .pi + p.t * 2
            let r = 52 + 6 * sin(p.t * 8 + Double(i))
            let s = 4 + 2.5 * abs(sin(p.t * 6 + Double(i)))
            pen.fill(starPath(pt(cx + cos(ang) * r, baseY - 62 - lift + sin(ang) * r * 0.75), CGFloat(s)), NSColor(hex: "FFC83D"))
        }
    }

    pen.save()
    pen.translate(CGFloat(cx), CGFloat(baseY - 30 - lift))
    pen.rotate(p.spin + p.tilt)
    pen.scale(p.dir, 1)

    let swing = p.moving ? 0.55 * sin(p.walk) : 0
    for (k, a) in [(0, -swing), (1, swing)] {
        let hip = pt(k == 0 ? -6 : 6, 10)
        let foot = pt(hip.x + sin(a) * 19, hip.y + cos(a) * 19)
        var leg = Path(); leg.move(to: hip); leg.addLine(to: foot)
        pen.stroke(leg, k == 0 ? ink.withAlphaComponent(0.75) : ink, 3.6, round: true)
        pen.fill(Path(ellipseIn: CGRect(x: foot.x - 3, y: foot.y - 2.5, width: 11, height: 6)), NSColor(hex: k == 0 ? "C0392B" : "E2483D"))
    }

    func arm(_ shoulder: CGPoint, _ angle: Double, front: Bool) {
        let hand = pt(shoulder.x + sin(angle) * 15, shoulder.y + cos(angle) * 15)
        var a = Path(); a.move(to: shoulder); a.addLine(to: hand)
        pen.stroke(a, front ? ink : ink.withAlphaComponent(0.7), 3.2, round: true)
        let r = CGRect(x: hand.x - 3.4, y: hand.y - 3.4, width: 6.8, height: 6.8)
        pen.fill(Path(ellipseIn: r), .white)
        pen.stroke(Path(ellipseIn: r), ink, 1.2)
    }
    let walkArm = p.moving ? 0.6 * sin(p.walk + .pi) : 0.25
    let up = p.armsUp
    arm(pt(-15, -12), -(walkArm * (1 - up) + up * 2.5) - 0.25, front: false)

    var tube = Path()
    tube.move(to: pt(-16, -40))
    tube.addLine(to: pt(-16, 6))
    tube.addQuadCurve(to: pt(-3.5, 25), control: pt(-14, 17))
    tube.addQuadCurve(to: pt(3.5, 25), control: pt(0, 28.5))
    tube.addQuadCurve(to: pt(16, 6), control: pt(14, 17))
    tube.addLine(to: pt(16, -40))
    tube.closeSubpath()
    pen.linear(tube, [NSColor(white: 1, alpha: 0.95), NSColor(hex: "E3EEFA"), NSColor(white: 1, alpha: 0.85)], pt(-16, 0), pt(16, 0))

    pen.save()
    pen.clip(tube)
    let level = -4 + 2 * sin(p.walk * 2)
    let slope = p.moving ? 0.09 * sin(p.walk) : 0
    var liquid = Path()
    liquid.move(to: pt(-17, level - slope * 17))
    var x = -17.0
    while x <= 17 {
        liquid.addLine(to: pt(x, level + slope * x + 1.2 * sin(x / 4 + p.ripple)))
        x += 1.5
    }
    liquid.addLine(to: pt(17, 30)); liquid.addLine(to: pt(-17, 30)); liquid.closeSubpath()
    pen.linear(liquid, [NSColor(hex: "9BF0A8"), NSColor(hex: "2FA84F")], pt(0, level), pt(0, 26))
    for i in 0..<3 {
        let q = (p.bubbles + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
        let by = 22 - (22 - level - 2) * q
        pen.fill(Path(ellipseIn: CGRect(x: -6 + Double(i) * 6 - 1.3, y: by - 1.3, width: 2.6, height: 2.6)), NSColor(white: 1, alpha: 0.75))
    }
    pen.restore()
    pen.stroke(tube, NSColor(hex: "7E93B3"), 1.5)
    pen.fill(Path(roundedRect: CGRect(x: -12.5, y: -35, width: 3.2, height: 34), cornerRadius: 1.6), NSColor(white: 1, alpha: 0.75))
    for (i, y) in [-30.0, -20, -10].enumerated() {
        var m = Path(); m.move(to: pt(9, y)); m.addLine(to: pt(i == 1 ? 15 : 13, y))
        pen.stroke(m, NSColor(hex: "7E93B3", alpha: 0.8), 1)
    }

    for ex in [-5.0, 8.0] {
        if p.blink {
            var b = Path(); b.move(to: pt(ex - 3.5, -26)); b.addQuadCurve(to: pt(ex + 3.5, -26), control: pt(ex, -24))
            pen.stroke(b, ink, 1.8, round: true)
        } else {
            let eye = CGRect(x: ex - 4.4, y: -30.5, width: 8.8, height: 9.4)
            pen.fill(Path(ellipseIn: eye), .white)
            pen.stroke(Path(ellipseIn: eye), ink.withAlphaComponent(0.6), 0.8)
            pen.fill(Path(ellipseIn: CGRect(x: ex - 1.2, y: -28, width: 5, height: 5.4)), ink)
            pen.fill(Path(ellipseIn: CGRect(x: ex + 1.2, y: -27.2, width: 1.6, height: 1.6)), .white)
        }
    }
    for cxk in [-9.0, 13.0] {
        pen.fill(Path(ellipseIn: CGRect(x: cxk - 3, y: -21, width: 6, height: 3.6)), NSColor(hex: "FF8FA3", alpha: 0.55))
    }
    if p.mouthOpen {
        var m = Path()
        m.move(to: pt(-1, -18.5)); m.addQuadCurve(to: pt(7, -18.5), control: pt(3, -11.5)); m.closeSubpath()
        pen.fill(m, NSColor(hex: "8C1D2B"))
        pen.fill(Path(ellipseIn: CGRect(x: 1.2, y: -16.3, width: 3.6, height: 2.2)), NSColor(hex: "FF7A8A"))
    } else {
        var m = Path(); m.move(to: pt(-0.5, -18)); m.addQuadCurve(to: pt(6.5, -18), control: pt(3, -14))
        pen.stroke(m, ink, 1.6, round: true)
    }

    let rim = CGRect(x: -19, y: -45, width: 38, height: 6)
    pen.fill(Path(roundedRect: rim, cornerRadius: 2), NSColor(hex: "DCE6F3"))
    pen.stroke(Path(roundedRect: rim, cornerRadius: 2), NSColor(hex: "7E93B3"), 1.2)
    pen.save()
    pen.translate(-19, -45)
    pen.rotate(p.lid)
    pen.fill(Path(roundedRect: CGRect(x: 3, y: 0, width: 32, height: 4), cornerRadius: 1), NSColor(hex: "3F6FBF"))
    pen.fill(Path(roundedRect: CGRect(x: 0, y: -8, width: 38, height: 8), cornerRadius: 3), NSColor(hex: "5B8BD6"))
    pen.fill(Path(roundedRect: CGRect(x: 3, y: -7, width: 30, height: 2.4), cornerRadius: 1.2), NSColor(white: 1, alpha: 0.45))
    pen.fill(Path(roundedRect: CGRect(x: 36, y: -6.5, width: 7, height: 5), cornerRadius: 2), NSColor(hex: "5B8BD6"))
    pen.restore()
    pen.fill(Path(ellipseIn: CGRect(x: -22, y: -47.5, width: 5, height: 5)), NSColor(hex: "3F6FBF"))

    var frontAngle = walkArm * (1 - up) + up * 2.5 + 0.25
    if p.waving && up == 0 { frontAngle = 2.4 + 0.45 * sin(p.wavePhase) }
    arm(pt(15, -12), frontAngle, front: true)
    pen.restore()
}

/// Speech bubble; `bottom` is where the tail points.
func paintBubble(_ pen: Pen, _ text: String, bottom: CGPoint, pop: CGFloat) -> CGRect {
    let font = roundedFont(13, .bold)
    let size = (text as NSString).size(withAttributes: [.font: font])
    let w = size.width + 28, h = size.height + 18
    let rect = CGRect(x: bottom.x - w / 2, y: bottom.y - h - 9, width: w, height: h)
    guard pop > 0.01 else { return rect.insetBy(dx: -12, dy: -12) }
    pen.save()
    pen.translate(bottom.x, bottom.y)
    pen.scale(pop, pop)
    pen.translate(-bottom.x, -bottom.y)
    var shape = Path(roundedRect: rect, cornerRadius: 14)
    var tail = Path()
    tail.move(to: CGPoint(x: bottom.x - 8, y: rect.maxY - 1)); tail.addLine(to: CGPoint(x: bottom.x, y: bottom.y)); tail.addLine(to: CGPoint(x: bottom.x + 8, y: rect.maxY - 1))
    shape.addPath(tail)
    pen.save()
    pen.shadow(NSColor(hex: "1E4A83", alpha: 0.25), 8, 3)
    pen.fill(Path(roundedRect: rect, cornerRadius: 14), .white)
    pen.restore()
    pen.fill(tail, .white)
    pen.stroke(Path(roundedRect: rect, cornerRadius: 14), NSColor(hex: "1E4A83"), 2)
    var tailEdge = Path()
    tailEdge.move(to: CGPoint(x: bottom.x - 8, y: rect.maxY)); tailEdge.addLine(to: CGPoint(x: bottom.x, y: bottom.y)); tailEdge.addLine(to: CGPoint(x: bottom.x + 8, y: rect.maxY))
    pen.stroke(tailEdge, NSColor(hex: "1E4A83"), 2, round: true)
    pen.fill(Path(CGRect(x: bottom.x - 7, y: rect.maxY - 2, width: 14, height: 2.5)), .white)
    pen.text(text, font, NSColor(hex: "172033"), CGPoint(x: rect.midX, y: rect.midY))
    pen.restore()
    return rect.insetBy(dx: -14, dy: -14)
}

