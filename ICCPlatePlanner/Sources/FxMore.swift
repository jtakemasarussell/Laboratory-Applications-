import SwiftUI
import AppKit
import QuartzCore

// MARK: - More of the bench: aspirator, lid, wash, rewind, loupe
//
// Each one is a one-shot Core Animation effect on the window-wide effects layer, like the pipette: drawn
// once into cached images, handed to the window server, and gone when it ends. All of them are off with
// Animations off.

extension FxView {
    /// The aspirator showing now: one at a time, like the pipette.
    private static var lastAspirator: CALayer?
    /// Where the aspirator's tip is, below the well's centre, as a fraction of the box's height.
    private static let aspTip: CGFloat = 0.24

    /// Erasing a well: a thin aspirator dips in and draws the stain up out of it, into its tube.
    func aspirate(at p: CGPoint, hex: String, cw: CGFloat, ch: CGFloat) {
        let root = space
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if let old = Self.lastAspirator {
            let o = old.presentation()?.opacity ?? 0
            old.removeAllAnimations()
            old.opacity = 0
            if o > 0.01 { old.run(frames("opacity", [o, 0], [0, 1], 0.08), "out") }
        }
        let box = Self.wellBox(cw: cw, ch: ch)
        let u = box.height / 40
        let tipY = box.height * (0.5 + Self.aspTip)
        let tip = CGPoint(x: p.x, y: p.y - box.height / 2 + tipY)
        // the stain in the well, drawn up into the tip
        let s = CALayer()
        s.bounds = CGRect(origin: .zero, size: box)
        s.cornerRadius = 8
        s.backgroundColor = cg(hex)
        s.position = p
        s.zPosition = 9
        s.opacity = 0
        root.addSublayer(s)
        let sg = CAAnimationGroup()
        sg.animations = [frames("position", [NSValue(point: p), NSValue(point: p), NSValue(point: tip)], [0, 0.25, 1], 0.42, .easeIn),
                         frames("transform.scale", [1, 0.94, 0.05], [0, 0.25, 1], 0.42, .easeIn),
                         frames("opacity", [1, 1, 0.3], [0, 0.55, 1], 0.42)]
        sg.duration = 0.42
        s.run(sg, "draw")
        expire(s, after: 0.48)
        // the aspirator, with the stain rising up its tube
        let a = CALayer()
        a.bounds = CGRect(origin: .zero, size: box)
        a.contents = Self.image("asp\(Int(box.width))x\(Int(box.height))", box) { c in Self.drawAspirator(c, size: box) }
        a.position = p
        a.zPosition = 10
        a.opacity = 0
        let rise = CALayer()
        let length = tipY - 9 * u
        rise.backgroundColor = cg(hex)
        rise.cornerRadius = 0.8 * u
        rise.anchorPoint = CGPoint(x: 0.5, y: 1)            // grows upwards from the tip
        rise.bounds = CGRect(x: 0, y: 0, width: 1.5 * u, height: 0)
        rise.position = CGPoint(x: box.width / 2, y: tipY - 0.8 * u)
        rise.opacity = 0.9
        a.addSublayer(rise)
        root.addSublayer(a)
        let g = CAAnimationGroup()
        g.animations = [frames("position.y", [p.y - 3, p.y, p.y, p.y - 3], [0, 0.18, 0.75, 1], 0.66),
                        frames("opacity", [0, 1, 1, 0], [0, 0.14, 0.75, 1], 0.66)]
        g.duration = 0.66
        a.run(g, "aspirate")
        rise.run(frames("bounds.size.height", [0, 0, length, length], [0, 0.22, 0.7, 1], 0.66), "rise")
        Self.lastAspirator = a
        expire(a, after: 0.72)
    }

    /// An aspirator seen from the side, in a well's box: its tubing, a metal collar and a long glass tip.
    private static func drawAspirator(_ c: CGContext, size: CGSize) {
        let u = size.height / 40
        let mid = size.width / 2
        let tipY = size.height * (0.5 + aspTip)
        let line = cg("5F6B7C", 0.85)
        // the vacuum tubing
        let tube = CGRect(x: mid - 2.6 * u, y: 0.4 * u, width: 5.2 * u, height: 6.2 * u)
        c.addPath(CGPath(roundedRect: tube, cornerWidth: 1.6 * u, cornerHeight: 1.6 * u, transform: nil))
        c.setFillColor(cg("9AA8BA")); c.fillPath()
        c.addPath(CGPath(roundedRect: tube, cornerWidth: 1.6 * u, cornerHeight: 1.6 * u, transform: nil))
        c.setStrokeColor(line); c.setLineWidth(0.8 * u); c.strokePath()
        // the collar
        let collar = CGRect(x: mid - 3.4 * u, y: 6.2 * u, width: 6.8 * u, height: 2.6 * u)
        c.addPath(CGPath(roundedRect: collar, cornerWidth: 1 * u, cornerHeight: 1 * u, transform: nil))
        c.setFillColor(cg("D5DCE5")); c.fillPath()
        c.addPath(CGPath(roundedRect: collar, cornerWidth: 1 * u, cornerHeight: 1 * u, transform: nil))
        c.setStrokeColor(line); c.setLineWidth(0.8 * u); c.strokePath()
        // the glass: straight, then tapering to the point
        let glass = CGMutablePath()
        glass.move(to: CGPoint(x: mid - 1.8 * u, y: 8.8 * u))
        glass.addLine(to: CGPoint(x: mid - 1.8 * u, y: tipY - 9 * u))
        glass.addLine(to: CGPoint(x: mid - 0.55 * u, y: tipY))
        glass.addLine(to: CGPoint(x: mid + 0.55 * u, y: tipY))
        glass.addLine(to: CGPoint(x: mid + 1.8 * u, y: tipY - 9 * u))
        glass.addLine(to: CGPoint(x: mid + 1.8 * u, y: 8.8 * u))
        glass.closeSubpath()
        c.addPath(glass); c.setFillColor(cg("F3F6FA", 0.75)); c.fillPath()
        c.addPath(glass); c.setStrokeColor(line); c.setLineWidth(0.8 * u); c.strokePath()
        // a glint down the glass
        c.setStrokeColor(cg("FFFFFF", 0.8)); c.setLineWidth(0.6 * u)
        c.move(to: CGPoint(x: mid - 0.9 * u, y: 10 * u)); c.addLine(to: CGPoint(x: mid - 0.9 * u, y: tipY - 10 * u)); c.strokePath()
    }

    // MARK: the plate's lid

    /// The black ibidi lid: lifted off a plate that has just been opened, or lowered on when it is saved
    /// (it clicks into place, then fades so the plate stays in view).
    func lid(over plate: CGRect, grid: CGRect, cw: CGFloat, ch: CGFloat, lowering: Bool) {
        guard plate.width > 0, plate.height > 0 else { return }
        let root = space
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let r = plate.insetBy(dx: -3, dy: -3)
        let pad: CGFloat = 28
        let size = CGSize(width: r.width + 2 * pad, height: r.height + 2 * pad)
        let key = "lid\(Int(r.width))x\(Int(r.height))"
        let gridAt = CGPoint(x: grid.minX - r.minX + pad, y: grid.minY - r.minY + pad)
        let c = CGPoint(x: r.midX, y: r.midY)
        let shadow = CALayer()
        shadow.bounds = CGRect(origin: .zero, size: size)
        shadow.contents = Self.image(key + "s", size) { g in Self.drawLidShadow(g, size: size, pad: pad) }
        shadow.position = CGPoint(x: c.x, y: c.y + 5)
        shadow.zPosition = 19
        shadow.opacity = 0
        root.addSublayer(shadow)
        let l = CALayer()
        l.bounds = CGRect(origin: .zero, size: size)
        l.contents = Self.image(key, size) { g in Self.drawLid(g, size: size, pad: pad, grid: gridAt, cw: cw, ch: ch) }
        l.position = c
        l.zPosition = 20
        l.opacity = 0
        root.addSublayer(l)
        if lowering {
            let d = 1.7, t: [Double] = [0, 0.25, 0.29, 0.33, 0.78, 1]
            let g = CAAnimationGroup()
            g.animations = [frames("position.y", [c.y - 42, c.y, c.y + 1.5, c.y, c.y, c.y], t, d),
                            frames("transform.scale", [1.06, 1, 0.997, 1, 1, 1], t, d),
                            frames("opacity", [0, 0.96, 1, 1, 1, 0], t, d)]
            g.duration = d
            l.run(g, "lower")
            shadow.run(frames("opacity", [0, 0.7, 0.7, 0], [0, 0.25, 0.78, 1], d), "lower")
            DispatchQueue.main.asyncAfter(deadline: .now() + d * 0.25) { Sounds.lid() }
            expire(l, after: d + 0.05); expire(shadow, after: d + 0.05)
        } else {
            let d = 0.8, t: [Double] = [0, 0.2, 1]
            let g = CAAnimationGroup()
            g.animations = [frames("position.y", [c.y, c.y - 2, c.y - 40], t, d),
                            frames("transform.scale", [1, 1.005, 1.05], t, d),
                            frames("opacity", [1, 1, 0], t, d)]
            g.duration = d
            l.run(g, "lift")
            shadow.run(frames("opacity", [0.7, 0.7, 0], [0, 0.2, 0.7], d), "lift")
            expire(l, after: d + 0.05); expire(shadow, after: d + 0.05)
        }
    }

    private static func lidPath(_ r: CGRect) -> CGPath {
        let cut: CGFloat = 18, rad: CGFloat = 14
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX + cut, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: rad)
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: rad)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: rad)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + cut))
        p.closeSubpath()
        return p
    }

    /// Smoked black polymer with the A1 corner cut, a raised rim, a ring moulded over each well and the
    /// maker's mark.
    private static func drawLid(_ c: CGContext, size: CGSize, pad: CGFloat, grid: CGPoint, cw: CGFloat, ch: CGFloat) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let r = CGRect(x: pad, y: pad, width: size.width - 2 * pad, height: size.height - 2 * pad)
        let path = lidPath(r)
        c.addPath(path); c.setFillColor(cg("0B0E13", 0.74)); c.fillPath()
        c.saveGState(); c.addPath(path); c.clip()
        if let g = CGGradient(colorsSpace: space, colors: [cg("FFFFFF", 0.16), cg("FFFFFF", 0.02), cg("FFFFFF", 0.07)] as CFArray, locations: [0, 0.55, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX, y: r.maxY), options: [])
        }
        // a moulded square over each well, the same size and shape as the well under it
        let box = FxView.wellBox(cw: cw, ch: ch)
        for i in 0..<8 {
            for j in 0..<12 {
                let o = CGPoint(x: grid.x + (CGFloat(j) + 0.5) * cw, y: grid.y + (CGFloat(i) + 0.5) * ch)
                let well = CGPath(roundedRect: CGRect(x: o.x - box.width / 2, y: o.y - box.height / 2, width: box.width, height: box.height),
                                  cornerWidth: 8, cornerHeight: 8, transform: nil)
                c.addPath(well); c.setFillColor(cg("FFFFFF", 0.035)); c.fillPath()
                c.addPath(well); c.setStrokeColor(cg("FFFFFF", 0.13)); c.setLineWidth(1); c.strokePath()
            }
        }
        c.restoreGState()
        c.addPath(lidPath(r.insetBy(dx: 7, dy: 7))); c.setStrokeColor(cg("FFFFFF", 0.10)); c.setLineWidth(1); c.strokePath()
        c.addPath(path); c.setStrokeColor(cg("FFFFFF", 0.30)); c.setLineWidth(1.4); c.strokePath()
        let mark = NSAttributedString(string: "ibidi", attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .heavy),
                                                                    .foregroundColor: NSColor(white: 1, alpha: 0.30)])
        mark.draw(at: CGPoint(x: r.maxX - 46, y: r.maxY - 22))
    }

    private static func drawLidShadow(_ c: CGContext, size: CGSize, pad: CGFloat) {
        let r = CGRect(x: pad, y: pad, width: size.width - 2 * pad, height: size.height - 2 * pad)
        c.setShadow(offset: .zero, blur: 20, color: cg("000000", 0.6))
        c.addPath(lidPath(r)); c.setFillColor(cg("000000", 0.35)); c.fillPath()
    }

    // MARK: clearing the plate: a wash

    /// A wave of buffer runs down the plate and the wells empty row by row as it passes.
    func wash(_ wells: [(Int, String)], grid: CGRect, cw: CGFloat, ch: CGFloat) {
        guard grid.width > 0 else { return }
        let root = space
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let box = Self.wellBox(cw: cw, ch: ch)
        let bandH = ch * 1.8
        let y0 = grid.minY - bandH / 2, y1 = grid.maxY + bandH / 2
        let T = 1.15
        let bsize = CGSize(width: grid.width + 24, height: bandH)
        let band = CALayer()
        band.bounds = CGRect(origin: .zero, size: bsize)
        band.contents = Self.image("wash\(Int(bsize.width))x\(Int(bandH))", bsize) { c in Self.drawWashBand(c, size: bsize) }
        band.position = CGPoint(x: grid.midX, y: y1)
        band.zPosition = 12
        band.opacity = 0
        root.addSublayer(band)
        let bg = CAAnimationGroup()
        bg.animations = [frames("position.y", [y0, y1], [0, 1], T, .linear),
                         frames("opacity", [0, 1, 1, 0], [0, 0.08, 0.85, 1], T)]
        bg.duration = T
        band.run(bg, "sweep")
        expire(band, after: T + 0.1)
        for (w, hex) in wells {
            let i = w / 12, j = w % 12
            let p = CGPoint(x: grid.minX + (CGFloat(j) + 0.5) * cw, y: grid.minY + (CGFloat(i) + 0.5) * ch)
            let at = max(0, T * Double((p.y - y0) / (y1 - y0)) - 0.05)
            let s = CALayer()
            s.bounds = CGRect(origin: .zero, size: box)
            s.cornerRadius = 8
            s.backgroundColor = cg(hex)
            s.anchorPoint = CGPoint(x: 0.5, y: 1)            // drains to the bottom of the well
            s.position = CGPoint(x: p.x, y: p.y + box.height / 2)
            s.zPosition = 11
            s.opacity = 0
            root.addSublayer(s)
            let g = CAAnimationGroup()
            g.animations = [frames("transform.scale.y", [1, 0.04], [0, 1], 0.3, .easeIn),
                            frames("opacity", [1, 1, 0], [0, 0.6, 1], 0.3)]
            g.duration = 0.3
            s.run(g, "drain", delay: at)
            expire(s, after: at + 0.36)
        }
        Sounds.wash()
    }

    /// The buffer's front: a pale blue band with a bright wavy edge and a few bubbles.
    private static func drawWashBand(_ c: CGContext, size: CGSize) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let g = CGGradient(colorsSpace: space, colors: [cg("9FD8FF", 0), cg("9FD8FF", 0.26), cg("E8F7FF", 0.5), cg("9FD8FF", 0.2), cg("9FD8FF", 0)] as CFArray,
                              locations: [0, 0.35, 0.6, 0.75, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
        }
        let front = CGMutablePath()
        let y = size.height * 0.6
        front.move(to: CGPoint(x: 0, y: y))
        var x: CGFloat = 0
        while x <= size.width { front.addLine(to: CGPoint(x: x, y: y + sin(x / 13) * 2.6)); x += 4 }
        c.addPath(front); c.setStrokeColor(cg("FFFFFF", 0.75)); c.setLineWidth(1.6); c.strokePath()
        c.setFillColor(cg("FFFFFF", 0.45))
        for k in 0..<18 {
            let bx = CGFloat(hash01(k, 31)) * size.width, by = y - 4 - CGFloat(hash01(k, 47)) * size.height * 0.4
            let br = 1 + CGFloat(hash01(k, 53)) * 1.8
            c.fillEllipse(in: CGRect(x: bx - br, y: by - br, width: 2 * br, height: 2 * br))
        }
    }

    // MARK: undo: a rewind

    /// Undone wells shrink back out, newest first, under a faint streak running right to left; wells the
    /// undo brings back pop in.
    func rewind(out: [(Int, String)], back: [(Int, String)], grid: CGRect, cw: CGFloat, ch: CGFloat) {
        guard grid.width > 0, !(out.isEmpty && back.isEmpty) else { return }
        let root = space
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let box = Self.wellBox(cw: cw, ch: ch)
        let ssize = CGSize(width: max(140, grid.width * 0.35), height: grid.height + 16)
        let streak = CALayer()
        streak.bounds = CGRect(origin: .zero, size: ssize)
        streak.contents = Self.image("rew\(Int(ssize.width))x\(Int(ssize.height))", ssize) { c in Self.drawRewind(c, size: ssize) }
        streak.position = CGPoint(x: grid.maxX + ssize.width / 2, y: grid.midY)
        streak.zPosition = 12
        streak.opacity = 0
        root.addSublayer(streak)
        let d = 0.6
        let sg = CAAnimationGroup()
        sg.animations = [frames("position.x", [grid.maxX + ssize.width / 2, grid.minX - ssize.width / 2], [0, 1], d, .easeIn),
                         frames("opacity", [0, 1, 1, 0], [0, 0.15, 0.8, 1], d)]
        sg.duration = d
        streak.run(sg, "rewind")
        expire(streak, after: d + 0.05)
        let n = out.count + back.count
        let step = min(0.035, 0.5 / Double(max(1, n)))
        func at(_ w: Int) -> CGPoint {
            CGPoint(x: grid.minX + (CGFloat(w % 12) + 0.5) * cw, y: grid.minY + (CGFloat(w / 12) + 0.5) * ch)
        }
        for (k, (w, hex)) in out.enumerated() {
            let s = CALayer()
            s.bounds = CGRect(origin: .zero, size: box)
            s.cornerRadius = 8
            s.backgroundColor = cg(hex)
            s.position = at(w)
            s.zPosition = 11
            s.opacity = 0
            root.addSublayer(s)
            let g = CAAnimationGroup()
            g.animations = [frames("transform.scale", [1, 0.12], [0, 1], 0.26, .easeIn),
                            frames("opacity", [1, 0], [0, 1], 0.26)]
            g.duration = 0.26
            s.run(g, "out", delay: Double(k) * step)
            expire(s, after: Double(k) * step + 0.3)
        }
        for (k, (w, hex)) in back.enumerated() {
            let s = CALayer()
            s.bounds = CGRect(origin: .zero, size: box)
            s.cornerRadius = 8
            s.backgroundColor = cg(hex)
            s.position = at(w)
            s.zPosition = 11
            s.opacity = 0
            root.addSublayer(s)
            let g = CAAnimationGroup()
            g.animations = [frames("transform.scale", [0.2, 1.08, 1], [0, 0.6, 1], 0.3, .easeOut),
                            frames("opacity", [1, 1, 0], [0, 0.7, 1], 0.3)]
            g.duration = 0.3
            s.run(g, "back", delay: Double(out.count + k) * step)
            expire(s, after: Double(out.count + k) * step + 0.34)
        }
    }

    /// A soft vertical streak with two rewind chevrons in it.
    private static func drawRewind(_ c: CGContext, size: CGSize) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let g = CGGradient(colorsSpace: space, colors: [cg("FFFFFF", 0), cg("CFE8FF", 0.22), cg("FFFFFF", 0.30), cg("CFE8FF", 0.10), cg("FFFFFF", 0)] as CFArray,
                              locations: [0, 0.3, 0.42, 0.7, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: 0), options: [])
        }
        let m = CGPoint(x: size.width * 0.42, y: size.height / 2)
        c.setFillColor(cg("FFFFFF", 0.55))
        for dx in [CGFloat(0), 15] {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: m.x + dx - 9, y: m.y))
            p.addLine(to: CGPoint(x: m.x + dx + 5, y: m.y - 9))
            p.addLine(to: CGPoint(x: m.x + dx + 5, y: m.y + 9))
            p.closeSubpath()
            c.addPath(p); c.fillPath()
        }
    }
}

// MARK: - The loupe

/// Hold Option over a stained well and a microscope eyepiece shows the cells in it, in that stain's colours;
/// moving within the well pans across the field. Follows the pointer through an event monitor and moves a
/// layer: nothing in SwiftUI redraws.
final class LoupeController {
    private weak var view: FxView?
    private var monitor: Any?
    private let root = CALayer(), cells = CALayer(), ring = CALayer(), caption = CATextLayer()
    private var key = ""
    private var showing = false
    static let size: CGFloat = 136
    private static var fields: [String: CGImage] = [:]

    init() {
        let S = Self.size
        root.bounds = CGRect(x: 0, y: 0, width: S, height: S + 24)
        root.zPosition = 50
        root.opacity = 0
        root.transform = CATransform3DMakeScale(0.85, 0.85, 1)
        cells.frame = CGRect(x: 7, y: 7, width: S - 14, height: S - 14)
        cells.cornerRadius = (S - 14) / 2
        cells.masksToBounds = true
        cells.backgroundColor = cg("020408")
        ring.frame = CGRect(x: 0, y: 0, width: S, height: S)
        ring.contents = renderImage(CGSize(width: S, height: S), screenScale) { c in Self.drawRing(c, S) }
        caption.frame = CGRect(x: S / 2 - 62, y: S + 4, width: 124, height: 18)
        caption.alignmentMode = .center
        caption.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        caption.fontSize = 11
        caption.foregroundColor = cg("D6FAFF")
        caption.backgroundColor = cg("04172A", 0.85)
        caption.cornerRadius = 9
        caption.contentsScale = screenScale
        for l in [cells, ring, caption] { root.addSublayer(l) }
    }

    func attach(_ v: FxView) {
        view = v
        CATransaction.begin(); CATransaction.setDisableActions(true)
        v.space.addSublayer(root)
        CATransaction.commit()
        v.window?.acceptsMouseMovedEvents = true
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .mouseMoved, .leftMouseDragged]) { [weak self] e in
                self?.handle(e)
                return e
            }
        }
    }

    func detach() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        root.removeFromSuperlayer()
        showing = false
    }

    private func handle(_ e: NSEvent) {
        guard let v = view, let win = v.window, e.window === win else { return }
        guard e.modifierFlags.contains(.option) else { hide(); return }
        let q = v.convert(win.mouseLocationOutsideOfEventStream, from: nil)
        look(at: CGPoint(x: q.x, y: v.bounds.height - q.y))
    }

    /// Shows the loupe for the point `p` (the effects layer's top-down coordinates), or hides it.
    func look(at p: CGPoint) {
        let fx = FxCenter.shared
        guard fx.on, let store = fx.store, store.motion else { hide(); return }
        let g = fx.gridFrame
        guard g.width > 0, g.contains(p) else { hide(); return }
        let j = min(11, Int((p.x - g.minX) / fx.cw)), i = min(7, Int((p.y - g.minY) / fx.ch))
        let w = i * 12 + j
        guard let id = store.exp.wells[w], let k = store.exp.sets.firstIndex(where: { $0.id == id }) else { hide(); return }
        let chans = panel(store.exp.sets[k]).channels
        let key = "\(k)|" + chans.map { "\($0.fluor.hex)\($0.fluor.counterstain)\($0.localisation)" }.joined(separator: ",")
        let within = CGPoint(x: (p.x - g.minX) / fx.cw - CGFloat(j), y: (p.y - g.minY) / fx.ch - CGFloat(i))
        let S = Self.size
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if key != self.key {
            if Self.fields[key] == nil { Self.fields[key] = Self.field(chans, seed: k + 1) }
            cells.contents = Self.fields[key]
            self.key = key
        }
        // pan across the field as the pointer moves within the well
        cells.contentsRect = CGRect(x: within.x * 0.45, y: within.y * 0.45, width: 0.55, height: 0.55)
        caption.string = "\(rowLetters[i])\(j + 1) · Stain \(k + 1)"
        // above the pointer, or below it near the top
        var c = CGPoint(x: p.x, y: p.y - S / 2 - 30)
        if c.y - S / 2 < 6 { c.y = p.y + S / 2 + 30 }
        root.position = CGPoint(x: c.x, y: c.y + 12)
        CATransaction.commit()
        if !showing {
            showing = true
            CATransaction.begin(); CATransaction.setAnimationDuration(0.14)
            root.opacity = 1
            root.transform = CATransform3DIdentity
            CATransaction.commit()
        }
    }

    func hide() {
        guard showing else { return }
        showing = false
        CATransaction.begin(); CATransaction.setAnimationDuration(0.12)
        root.opacity = 0
        root.transform = CATransform3DMakeScale(0.85, 0.85, 1)
        CATransaction.commit()
    }

    /// The eyepiece: a dark metal ring with a highlight, a vignette at the edge of the field and a scale bar.
    private static func drawRing(_ c: CGContext, _ S: CGFloat) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctr = CGPoint(x: S / 2, y: S / 2)
        if let g = CGGradient(colorsSpace: space, colors: [cg("000000", 0), cg("000000", 0), cg("000000", 0.6)] as CFArray, locations: [0, 0.78, 1]) {
            c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: S / 2 - 7, options: [])
        }
        let ringPath = CGMutablePath()
        ringPath.addEllipse(in: CGRect(x: 0.5, y: 0.5, width: S - 1, height: S - 1))
        ringPath.addEllipse(in: CGRect(x: 7, y: 7, width: S - 14, height: S - 14))
        c.saveGState(); c.addPath(ringPath); c.clip(using: .evenOdd)
        if let g = CGGradient(colorsSpace: space, colors: [cg("6B7686"), cg("2A323D"), cg("4A5462"), cg("1B2129")] as CFArray, locations: [0, 0.35, 0.65, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: S, y: S), options: [])
        }
        c.restoreGState()
        c.setStrokeColor(cg("9BF0FF", 0.55)); c.setLineWidth(1)
        c.strokeEllipse(in: CGRect(x: 7, y: 7, width: S - 14, height: S - 14))
        c.setStrokeColor(cg("FFFFFF", 0.25)); c.setLineWidth(0.8)
        c.strokeEllipse(in: CGRect(x: 1, y: 1, width: S - 2, height: S - 2))
        c.setStrokeColor(cg("FFFFFF", 0.75)); c.setLineWidth(1.6)
        c.move(to: CGPoint(x: S * 0.62, y: S * 0.78)); c.addLine(to: CGPoint(x: S * 0.76, y: S * 0.78)); c.strokePath()
    }

    /// A field of cells in the stain's channels, added like light: nuclei for nuclear markers and
    /// counterstains, a soft cytoplasm for the rest, a rim for membrane markers.
    private static func field(_ chans: [Channel], seed: Int) -> CGImage? {
        let S: CGFloat = 260
        return renderImage(CGSize(width: S, height: S), screenScale) { c in
            c.setFillColor(cg("020408")); c.fill(CGRect(x: 0, y: 0, width: S, height: S))
            var cellsAt: [(CGPoint, CGFloat)] = []
            for n in 0..<78 {
                let p = CGPoint(x: CGFloat(hash01(n, seed * 13 + 1)) * S, y: CGFloat(hash01(n, seed * 13 + 2)) * S)
                cellsAt.append((p, 9 + CGFloat(hash01(n, seed * 13 + 3)) * 6))
            }
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            c.setBlendMode(.plusLighter)
            for ch in chans {
                let hex = ch.fluor.hex
                for (n, cell) in cellsAt.enumerated() {
                    let (p, r) = cell
                    if !ch.fluor.counterstain && hash01(n, ch.fluor.wavelength) < 0.3 { continue }
                    if ch.fluor.counterstain || ch.localisation == .nuclear {
                        c.setFillColor(cg(hex, ch.fluor.counterstain ? 0.7 : 0.85))
                        c.fillEllipse(in: CGRect(x: p.x - r * 0.62, y: p.y - r * 0.5, width: r * 1.24, height: r))
                    } else if ch.localisation == .membrane {
                        c.setStrokeColor(cg(hex, 0.75)); c.setLineWidth(1.6)
                        c.strokeEllipse(in: CGRect(x: p.x - r * 1.35, y: p.y - r * 1.15, width: r * 2.7, height: r * 2.3))
                    } else if let g = CGGradient(colorsSpace: space, colors: [cg(hex, 0.7), cg(hex, 0.32), cg(hex, 0)] as CFArray, locations: [0, 0.6, 1]) {
                        c.drawRadialGradient(g, startCenter: p, startRadius: r * 0.4, endCenter: p, endRadius: r * 1.7, options: [])
                    }
                }
            }
        }
    }
}

// MARK: - The room lights

/// Switching the microscope room on dims the window's panels one after another, like the room lights going
/// off down a row; switching it off, they come back up the same way. Kept gentle: a faint veil and one soft
/// dip per panel, nothing that strobes. A see-through window over the planner carries it, so it lives
/// through the planner rebuilding itself in the new colours underneath.
enum RoomLights {
    private static var overlay: NSWindow?

    static func play(over window: NSWindow?, toDark: Bool) {
        guard let window, let content = window.contentView, content.bounds.width > 0 else { return }
        if let o = overlay { o.parent?.removeChildWindow(o); o.orderOut(nil) }
        let frame = window.convertToScreen(content.frame)
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        let v = NSView(frame: NSRect(origin: .zero, size: frame.size))
        v.layer = CALayer()
        v.wantsLayer = true
        let space = CALayer()
        space.isGeometryFlipped = true
        space.frame = v.bounds
        v.layer?.addSublayer(space)
        w.contentView = v
        window.addChildWindow(w, ordered: .above)
        overlay = w
        let W = frame.width, H = frame.height
        let head = min(118, H * 0.14), left = min(612, W * 0.45)
        let mid = head + (H - head) / 2
        let panels = [CGRect(x: 0, y: 0, width: W, height: head),
                      CGRect(x: 0, y: head, width: left, height: mid - head), CGRect(x: left, y: head, width: W - left, height: mid - head),
                      CGRect(x: 0, y: mid, width: left, height: H - mid), CGRect(x: left, y: mid, width: W - left, height: H - mid)]
        let gap = 0.07, d = 0.42
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (k, r) in panels.enumerated() {
            let l = CALayer()
            l.frame = r
            l.backgroundColor = toDark ? cg("F4F8FF", 0.32) : cg("05080D", 0.36)
            l.opacity = 0
            space.addSublayer(l)
            // one soft dip, then the panel settles into the new light
            l.run(frames("opacity", [1, 0.7, 0.85, 0], [0, 0.25, 0.4, 1], d), "dim", delay: 0.05 + Double(k) * gap)
        }
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 + Double(panels.count) * gap + d + 0.1) {
            guard overlay === w else { return }
            window.removeChildWindow(w)
            w.orderOut(nil)
            overlay = nil
        }
    }
}

// MARK: - The fridge door

/// Opening the fridge: its frosted door swings open, a puff of cold mist rolls out, then the tubes slide
/// forward (the rack animates those).
struct FridgeDoor: NSViewRepresentable {
    let motion: Bool
    func makeNSView(context: Context) -> FridgeDoorView { FridgeDoorView(frame: .zero) }
    func updateNSView(_ v: FridgeDoorView, context: Context) { v.motion = motion }
}

final class FridgeDoorView: NSView {
    var motion = true
    private var ran = false
    private static var puff: CGImage? = renderImage(CGSize(width: 70, height: 70), screenScale) { c in
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let g = CGGradient(colorsSpace: space, colors: [cg("F4FBFF", 0.75), cg("DDF0FF", 0.3), cg("DDF0FF", 0)] as CFArray, locations: [0, 0.5, 1]) {
            c.drawRadialGradient(g, startCenter: CGPoint(x: 35, y: 35), startRadius: 0, endCenter: CGPoint(x: 35, y: 35), endRadius: 35, options: [])
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() { super.layout(); start() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); start() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); start() }

    /// Plays once, as soon as the view has its size and a window.
    private func start() {
        guard !ran, bounds.width > 10, bounds.height > 10, window != nil else { return }
        ran = true
        guard motion, let root = layer else { return }
        let b = bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // the door, hinged on the left
        let clip = CALayer()
        clip.frame = b
        clip.masksToBounds = true
        clip.cornerRadius = 8
        root.addSublayer(clip)
        let door = CALayer()
        door.anchorPoint = CGPoint(x: 0, y: 0.5)
        door.bounds = CGRect(origin: .zero, size: b.size)
        door.position = CGPoint(x: 0, y: b.height / 2)
        door.contents = renderImage(b.size, screenScale) { c in Self.drawDoor(c, b.size) }
        door.opacity = 0
        var persp = CATransform3DIdentity
        persp.m34 = -1 / 700
        clip.sublayerTransform = persp
        clip.addSublayer(door)
        let open = CAAnimationGroup()
        open.animations = [frames("transform.rotation.y", [0, 0, -1.75], [0, 0.15, 1], 0.55, .easeIn),
                           frames("opacity", [1, 1, 1, 0], [0, 0.15, 0.75, 1], 0.55)]
        open.duration = 0.55
        door.run(open, "open")
        // mist rolling out from the opening edge
        for k in 0..<9 {
            let m = CALayer()
            m.bounds = CGRect(x: 0, y: 0, width: 70, height: 70)
            m.contents = Self.puff
            let y = b.height * (0.1 + 0.8 * CGFloat(hash01(k, 7)))
            let x = b.width * (0.15 + 0.7 * CGFloat(hash01(k, 11)))
            m.position = CGPoint(x: x, y: y)
            m.opacity = 0
            root.addSublayer(m)
            let g = CAAnimationGroup()
            let drift = CGFloat(hash01(k, 13) - 0.5) * 50
            g.animations = [frames("transform.scale", [0.4, 1.9], [0, 1], 1.0, .easeOut),
                            frames("opacity", [0, 0.8, 0], [0, 0.25, 1], 1.0),
                            frames("position", [NSValue(point: CGPoint(x: x, y: y)), NSValue(point: CGPoint(x: x + drift, y: y + 22))], [0, 1], 1.0, .easeOut)]
            g.duration = 1.0
            m.run(g, "mist", delay: 0.12 + Double(k) * 0.03)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { m.removeFromSuperlayer() }
        }
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { clip.removeFromSuperlayer() }
    }

    /// Frosted white-blue panel with an inner gasket and a long handle on the right.
    private static func drawDoor(_ c: CGContext, _ size: CGSize) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let r = CGRect(origin: .zero, size: size)
        if let g = CGGradient(colorsSpace: space, colors: [cg("EEF6FF"), cg("CFE0F2"), cg("B9CCE2")] as CFArray, locations: [0, 0.6, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: size.height), options: [])
        }
        c.addPath(CGPath(roundedRect: r.insetBy(dx: 6, dy: 6), cornerWidth: 6, cornerHeight: 6, transform: nil))
        c.setStrokeColor(cg("FFFFFF", 0.8)); c.setLineWidth(1.5); c.strokePath()
        let handle = CGRect(x: size.width - 26, y: size.height * 0.25, width: 7, height: size.height * 0.5)
        c.addPath(CGPath(roundedRect: handle, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil))
        c.setFillColor(cg("8FA3BB")); c.fillPath()
        let label = NSAttributedString(string: "4 °C", attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .heavy),
                                                                   .foregroundColor: NSColor(srgbRed: 0.36, green: 0.44, blue: 0.53, alpha: 0.6)])
        label.draw(at: CGPoint(x: 22, y: 18))
    }
}

// MARK: - The printout

/// When the export finishes, a page with the plate map slides out of a slot. Layers, not SwiftUI: animating it
/// in SwiftUI redrew the window-sized overlay it sits in on every frame.
struct Printout: NSViewRepresentable {
    let map: [Int: String]
    let title: String
    let motion: Bool
    static let page = CGSize(width: 178, height: 226)
    static var size: CGSize { CGSize(width: page.width + 26, height: page.height + 8) }

    func makeNSView(context: Context) -> PrintoutView { PrintoutView(frame: CGRect(origin: .zero, size: Self.size)) }
    func updateNSView(_ v: PrintoutView, context: Context) { v.show(map: map, title: title, motion: motion) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PrintoutView, context: Context) -> CGSize? { Self.size }

    private static let pad: CGFloat = 10

    static func pageImage(map: [Int: String], title: String) -> CGImage? {
        let W = page.width, H = page.height, p = pad
        return renderImage(CGSize(width: W + 2 * p, height: H + 2 * p), screenScale) { c in
            let paper = CGRect(x: p, y: p, width: W, height: H)
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: 3), blur: 7, color: cg("000000", 0.45))
            c.setFillColor(cg("F7F5EF")); c.fill(paper)
            c.restoreGState()
            NSAttributedString(string: "ICC PLATE PLAN", attributes: [.font: NSFont(name: "Georgia-Bold", size: 8.5) ?? NSFont.boldSystemFont(ofSize: 8.5),
                                                                       .foregroundColor: NSColor(hex: "1E2F4D")])
                .draw(at: CGPoint(x: p + 12, y: p + 8))
            NSAttributedString(string: title, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 6.5, weight: .regular),
                                                           .foregroundColor: NSColor(hex: "6B7C93")])
                .draw(at: CGPoint(x: p + 12, y: p + 21))
            c.setFillColor(cg("1E2F4D", 0.5)); c.fill(CGRect(x: p + 12, y: p + 34, width: W - 24, height: 0.8))
            let cell = (W - 24) / 12
            for w in 0..<96 {
                let r = CGRect(x: p + 12 + CGFloat(w % 12) * cell + 0.8, y: p + 42 + CGFloat(w / 12) * cell + 0.8, width: cell - 1.6, height: cell - 1.6)
                let path = CGPath(roundedRect: r, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
                if let hex = map[w] {
                    c.addPath(path); c.setFillColor(cg(hex)); c.fillPath()
                    c.addPath(path); c.setStrokeColor(cg("000000", 0.18)); c.setLineWidth(0.5); c.strokePath()
                } else {
                    c.addPath(path); c.setStrokeColor(cg("B8C2CF")); c.setLineWidth(0.6); c.strokePath()
                }
            }
            let top = p + 42 + cell * 8 + 12
            c.setFillColor(cg("C9D1DC"))
            for (k, wide) in [0.9, 0.75, 0.82, 0.6, 0.88, 0.7, 0.45].enumerated() {
                c.addPath(CGPath(roundedRect: CGRect(x: p + 12, y: top + CGFloat(k) * 9, width: (W - 24) * wide, height: 3),
                                 cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
                c.fillPath()
            }
        }
    }
}

final class PrintoutView: NSView {
    private let space = CALayer(), slot = CALayer(), clip = CALayer(), sheet = CALayer()
    private var shown = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        space.isGeometryFlipped = true
        layer?.addSublayer(space)
        for l in [clip, slot] { space.addSublayer(l) }
        clip.addSublayer(sheet)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(map: [Int: String], title: String, motion: Bool) {
        guard !shown else { return }
        shown = true
        let W = Printout.page.width, H = Printout.page.height, pad: CGFloat = 10
        let full = Printout.size
        CATransaction.begin(); CATransaction.setDisableActions(true)
        space.frame = CGRect(origin: .zero, size: full)
        slot.frame = CGRect(x: 0, y: 0, width: full.width, height: 10)
        slot.cornerRadius = 5
        slot.backgroundColor = cg("02060D")
        slot.borderColor = cg("FFFFFF", 0.22)
        slot.borderWidth = 1
        slot.zPosition = 2
        // the page comes out from under the slot; the clip is wide enough for its shadow
        clip.frame = CGRect(x: 0, y: 5, width: full.width, height: H + pad)
        clip.masksToBounds = true
        sheet.bounds = CGRect(x: 0, y: 0, width: W + 2 * pad, height: H + 2 * pad)
        sheet.contents = Printout.pageImage(map: map, title: title)
        let x = full.width / 2
        let out = CGPoint(x: x, y: H / 2), inside = CGPoint(x: x, y: -H / 2 - pad)
        sheet.position = out
        if motion {
            let a = CABasicAnimation(keyPath: "position.y")
            a.fromValue = inside.y; a.toValue = out.y
            a.duration = 1.15
            a.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.3, 1)
            sheet.run(a, "print", delay: 0.3)
        }
        CATransaction.commit()
    }
}

/// The light over a dye tag when its dye arrives: the tag fills with the dye's colour, its name turns white,
/// and a halo blooms around it, then it all fades back to the tag.
struct DyeGlow: NSViewRepresentable {
    let hex: String
    let label: String
    let flashes: Int
    func makeNSView(context: Context) -> DyeGlowView { DyeGlowView(frame: .zero) }
    func updateNSView(_ v: DyeGlowView, context: Context) { v.update(hex: hex, label: label, flashes: flashes) }
}

final class DyeGlowView: NSView {
    private let glow = CALayer(), halo = CALayer(), fill = CALayer(), bar = CALayer(), text = CATextLayer()
    private var played = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        glow.opacity = 0
        for l in [halo, fill, bar, text] { glow.addSublayer(l) }
        layer?.addSublayer(glow)
        text.alignmentMode = .left
        text.font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
        text.fontSize = 9.5
        text.foregroundColor = cg("FFFFFF")
        text.contentsScale = screenScale
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var pending: (hex: String, label: String)?

    func update(hex: String, label: String, flashes: Int) {
        guard flashes != played else { return }
        played = flashes
        guard flashes > 0 else { return }
        pending = (hex, label)
        play()
    }

    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); play() }
    override func layout() { super.layout(); play() }

    /// Plays a waiting flash once the tag has its size (a tag that appears lit has none at first).
    private func play() {
        guard let (hex, label) = pending, bounds.width > 2, bounds.height > 2 else { return }
        pending = nil
        let b = bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glow.frame = b
        halo.frame = b.insetBy(dx: -3.5, dy: -3.5)
        halo.cornerRadius = 7
        halo.backgroundColor = cg(hex, 0.35)
        fill.frame = b
        fill.cornerRadius = 4
        fill.backgroundColor = cg(hex)
        // where the tag draws its colour bar and its name (5 pt in, a 3 pt bar, 3 pt apart)
        bar.frame = CGRect(x: 5, y: (b.height - 9) / 2, width: 3, height: 9)
        bar.cornerRadius = 1.5
        bar.backgroundColor = cg("FFFFFF")
        text.string = label
        text.frame = CGRect(x: 11, y: (b.height - 12) / 2 - 0.5, width: b.width - 11, height: 12)
        let g = CAAnimationGroup()
        g.animations = [frames("opacity", [0, 1, 1, 0], [0, 0.11, 0.26, 1], 1.05),
                        frames("transform.scale", [1, 1.14, 1.14, 1], [0, 0.11, 0.26, 1], 1.05)]
        g.duration = 1.05
        glow.run(g, "flash")
        CATransaction.commit()
    }
}

// MARK: - Dye flash

/// Secondaries just taken from the fridge: their dye tags light up when they appear on the card.
enum DyeFlash {
    static var fresh: [String: Date] = [:]
    /// Pairing rows that have been on screen, and the dyes each has shown: a dye new to a row it was not on
    /// before lights up; the same dye shown again (the window rebuilt in the dark room) does not.
    static var owners: Set<UUID> = []
    static var seen: Set<String> = []
    /// Nothing lights up while the window is first built or a plate has just been opened.
    static var quietUntil = Date().addingTimeInterval(3)
    static func quiet(for t: Double) { quietUntil = max(quietUntil, Date().addingTimeInterval(t)) }

    /// Whether this dye tag, appearing now on `owner`'s row, should light up.
    static func shouldFlash(_ fluor: Fluor, owner: UUID?) -> Bool {
        var flash = isFresh(fluor)
        if let o = owner {
            let key = "\(o)|\(fluor.name)"
            if owners.contains(o) && !seen.contains(key) { flash = true }
            owners.insert(o); seen.insert(key)
        }
        return flash && Date() >= quietUntil
    }
    static func added(_ q: Secondary) {
        if let f = secondaryFluor(q) { fresh[f.name] = Date() }
    }
    static func isFresh(_ fluor: Fluor) -> Bool {
        guard let t = fresh[fluor.name] else { return false }
        return Date().timeIntervalSince(t) < 2
    }
}
