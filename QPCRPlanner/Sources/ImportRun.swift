import SwiftUI
import AppKit
import QuartzCore

// MARK: - The qTOWER run that plays when files are imported, on layers
//
// The same picture as ImportShowView (which still draws it for snapshots), built so it costs next to
// nothing: everything that stays put (panel, title, instrument, screen, axes, legend and the finished
// curves) is drawn once into images, and each frame only moves the lid and the plate, reveals the
// curves, pops the Ct marks, fills the bar and changes three short texts. It lives in a borderless
// window over the main one, so nothing in the main window is touched while it plays.

final class ImportRunView: NSView {
    private let show: ImportShow
    private weak var store: Store?
    private let group = CALayer(), panel = CALayer(), canvas = CALayer(), art = CALayer()
    private let lid = CALayer(), plate = CALayer(), led = CALayer()
    private let phaseText = CATextLayer(), tempText = CATextLayer(), cycleText = CATextLayer()
    private var wisps: [CALayer] = []
    private let reveal = CALayer(), curves = CALayer()
    private var heads: [CALayer] = [], ctDots: [CALayer] = []
    private let barClip = CALayer(), barFill = CAGradientLayer()
    private let stamp = CALayer()
    private var timer: Timer?
    private var last = (phase: "", temp: "", cycle: -1, led: -1)
    private struct Curve { var top: Double; var m: Double; var ct: Double; var hex: String }
    private var gc: [Curve] = []
    private var ledColors: [CGColor] = []

    private static let W: CGFloat = 700, H: CGFloat = 420
    private let scr = CGRect(x: 300, y: 100, width: 360, height: 250)
    private var plot: CGRect { CGRect(x: scr.minX + 34, y: scr.minY + 34, width: scr.width - 54, height: scr.height - 64) }

    init(show: ImportShow, store: Store) {
        self.show = show
        self.store = store
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: "0B1F3A", alpha: 0.6).cgColor
        (NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua)!).performAsCurrentDrawingAppearance { self.build() }
        apply(max(0, Date().timeIntervalSince(show.date)))
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { store?.skipImportShow() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { timer?.invalidate(); timer = nil }
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        group.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    private func tick() {
        let a = Date().timeIntervalSince(show.date)
        if a > ImportShow.length + 0.6 { timer?.invalidate(); timer = nil }
        apply(a)
    }

    // top-down geometry inside the 700 × 420 canvas, to layer geometry (y up)
    private func up(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: Self.H - r.maxY, width: r.width, height: r.height) }
    private func up(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: Self.H - p.y) }
    private func col(_ hex: String, _ a: CGFloat = 1) -> CGColor { NSColor(Color(hex: hex)).withAlphaComponent(a).cgColor }

    // MARK: drawn once

    private func build() {
        let s = screenScale
        group.bounds = CGRect(x: 0, y: 0, width: 760, height: 480)
        layer?.addSublayer(group)
        panel.frame = group.bounds
        panel.contents = ImportShowView.panelImage()
        group.addSublayer(panel)
        canvas.frame = CGRect(x: 30, y: 30, width: Self.W, height: Self.H)
        canvas.masksToBounds = true
        group.addSublayer(canvas)

        let genes = show.genes.isEmpty ? [ShowGene(name: "", hex: "2FA84F", ct: 25)] : Array(show.genes.prefix(8))
        gc = genes.enumerated().map { k, g in
            let top = 0.92 - 0.06 * Double(k % 4), ct = min(max(g.ct, 12), 37)
            return Curve(top: top, m: ct + 1.6 * log(top / 0.2 - 1), ct: ct, hex: tintHex(g.hex, 0.2))
        }
        let navy = NSColor(Brand.accent), plot = self.plot, scr = self.scr

        // the still picture: title, instrument, screen, axes, legend, progress track
        art.frame = canvas.bounds
        art.contents = renderImage(CGSize(width: Self.W, height: Self.H), s) { pen in
            let c = pen.c
            Self.text("qTOWER³ run", NSFont.systemFont(ofSize: 22, weight: .heavy).withDesign(.serif), navy, CGPoint(x: 40, y: 46), .left)
            Self.text("click to skip", .systemFont(ofSize: 11, weight: .medium), NSColor(Color(hex: "9AA8BC")), CGPoint(x: 668, y: 46), .right)
            // instrument
            let base = CGRect(x: 40, y: 200, width: 230, height: 140)
            let bp = CGPath(roundedRect: base, cornerWidth: 18, cornerHeight: 18, transform: nil)
            c.saveGState(); c.addPath(bp); c.clip()
            if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [self.col("F4F7FB"), self.col("CDD7E5")] as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(g, start: CGPoint(x: 0, y: 200), end: CGPoint(x: 0, y: 340), options: [])
            }
            c.restoreGState()
            c.addPath(bp); c.setStrokeColor(self.col("9AA8BC")); c.setLineWidth(1.5); c.strokePath()
            c.addPath(CGPath(roundedRect: CGRect(x: 40, y: 290, width: 230, height: 34), cornerWidth: 6, cornerHeight: 6, transform: nil))
            c.setFillColor(navy.cgColor); c.fillPath()
            Self.text("qTOWER³", .systemFont(ofSize: 15, weight: .heavy), .white, CGPoint(x: 62, y: 307), .left)
            c.addPath(CGPath(roundedRect: CGRect(x: 62, y: 262, width: 186, height: 9), cornerWidth: 3, cornerHeight: 3, transform: nil))
            c.setFillColor(self.col("2A3445")); c.fillPath()
            // screen
            let sp = CGPath(roundedRect: scr, cornerWidth: 14, cornerHeight: 14, transform: nil)
            c.addPath(sp); c.setFillColor(self.col("0E1B30")); c.fillPath()
            c.addPath(sp); c.setStrokeColor(self.col("2C4466")); c.setLineWidth(2); c.strokePath()
            c.setStrokeColor(NSColor(white: 1, alpha: 0.08).cgColor); c.setLineWidth(1)
            for i in 0...4 {
                let y = plot.maxY - plot.height * CGFloat(i) / 4
                c.strokeLineSegments(between: [CGPoint(x: plot.minX, y: y), CGPoint(x: plot.maxX, y: y)])
            }
            c.setStrokeColor(NSColor(white: 1, alpha: 0.5).cgColor); c.setLineWidth(1.2)
            c.strokeLineSegments(between: [CGPoint(x: plot.minX, y: plot.minY), CGPoint(x: plot.minX, y: plot.maxY),
                                           CGPoint(x: plot.minX, y: plot.maxY), CGPoint(x: plot.maxX, y: plot.maxY)])
            Self.text("Cycle", .systemFont(ofSize: 10, weight: .semibold), NSColor(white: 1, alpha: 0.6), CGPoint(x: plot.midX, y: plot.maxY + 16), .center)
            Self.text("ΔRn", .systemFont(ofSize: 10, weight: .semibold), NSColor(white: 1, alpha: 0.6), CGPoint(x: plot.minX - 18, y: plot.midY), .center)
            let thrY = plot.maxY - plot.height * 0.2
            c.setStrokeColor(self.col("FFD86B", 0.6)); c.setLineWidth(1); c.setLineDash(phase: 0, lengths: [5, 4])
            c.strokeLineSegments(between: [CGPoint(x: plot.minX, y: thrY), CGPoint(x: plot.maxX, y: thrY)])
            c.setLineDash(phase: 0, lengths: [])
            // legend in the corner of the screen
            for (k, g) in genes.enumerated() where !g.name.isEmpty {
                let ly = plot.minY + 4 + CGFloat(k) * 15
                let hex = self.gc[k].hex
                c.addPath(CGPath(roundedRect: CGRect(x: plot.minX + 8, y: ly - 3, width: 12, height: 6), cornerWidth: 3, cornerHeight: 3, transform: nil))
                c.setFillColor(self.col(hex)); c.fillPath()
                Self.text(g.name, .systemFont(ofSize: 10.5, weight: .bold), NSColor(Color(hex: hex)), CGPoint(x: plot.minX + 26, y: ly), .left)
            }
            // progress track
            c.addPath(CGPath(roundedRect: CGRect(x: 40, y: 368, width: 620, height: 10), cornerWidth: 5, cornerHeight: 5, transform: nil))
            c.setFillColor(self.col("E3EAF4")); c.fillPath()
        }
        canvas.addSublayer(art)

        // the plate sliding in
        plate.bounds = CGRect(x: 0, y: 0, width: 160, height: 30)
        plate.contents = renderImage(CGSize(width: 160, height: 30), s) { pen in
            let c = pen.c
            let r = CGRect(x: 0.6, y: 0.6, width: 158.8, height: 28.8)
            c.addPath(CGPath(roundedRect: r, cornerWidth: 5, cornerHeight: 5, transform: nil)); c.setFillColor(NSColor.white.cgColor); c.fillPath()
            c.addPath(CGPath(roundedRect: r, cornerWidth: 5, cornerHeight: 5, transform: nil)); c.setStrokeColor(self.col("9AA8BC")); c.setLineWidth(1.2); c.strokePath()
            for row in 0..<3 {
                for k in 0..<12 {
                    let hex = self.show.genes.isEmpty ? ["2FA84F", "E2483D", "2F6FE0", "F2A900"][k % 4] : self.show.genes[(k / 3) % self.show.genes.count].hex
                    c.setFillColor(self.col(hex, 0.85))
                    c.fillEllipse(in: CGRect(x: 8 + CGFloat(k) * 12.4, y: 4 + CGFloat(row) * 8.3, width: 6.6, height: 6.6))
                }
            }
        }
        canvas.addSublayer(plate)

        // the lid, hinged at its back (right) end
        lid.bounds = CGRect(x: 0, y: 0, width: 230, height: 36)
        lid.anchorPoint = CGPoint(x: 1, y: 2.0 / 36)
        lid.position = up(CGPoint(x: 270, y: 200))
        lid.contents = renderImage(CGSize(width: 230, height: 36), s) { pen in
            let c = pen.c
            let r = CGRect(x: 0.75, y: 0.75, width: 228.5, height: 34.5)
            let p = CGPath(roundedRect: r, cornerWidth: 14, cornerHeight: 14, transform: nil)
            c.saveGState(); c.addPath(p); c.clip()
            if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [self.col("E3E9F2"), self.col("B8C4D6")] as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 36), options: [])
            }
            c.restoreGState()
            c.addPath(p); c.setStrokeColor(self.col("8A99AF")); c.setLineWidth(1.5); c.strokePath()
            c.addPath(CGPath(roundedRect: CGRect(x: 30, y: 10, width: 120, height: 6), cornerWidth: 3, cornerHeight: 3, transform: nil))
            c.setFillColor(NSColor(white: 1, alpha: 0.6).cgColor); c.fillPath()
        }
        canvas.addSublayer(lid)

        // the status light and the texts that change
        led.bounds = CGRect(x: 0, y: 0, width: 12, height: 12)
        led.cornerRadius = 6
        led.position = up(CGPoint(x: 250, y: 306))
        ledColors = [col("F2A900"), col("39D353"), col("39D353", 0.25)]
        canvas.addSublayer(led)
        func text(_ t: CATextLayer, _ font: NSFont, _ frame: CGRect, _ align: CATextLayerAlignmentMode) {
            t.contentsScale = s
            t.font = font
            t.fontSize = font.pointSize
            t.alignmentMode = align
            t.frame = up(frame)
            canvas.addSublayer(t)
        }
        text(phaseText, NSFont.systemFont(ofSize: 14, weight: .semibold).withDesign(.rounded), CGRect(x: 40, y: 62, width: 600, height: 20), .left)
        phaseText.foregroundColor = col("4A78B8")
        text(tempText, .monospacedSystemFont(ofSize: 12, weight: .bold), CGRect(x: 150, y: 299, width: 82, height: 17), .right)
        text(cycleText, .monospacedSystemFont(ofSize: 15, weight: .heavy), CGRect(x: scr.maxX - 214, y: scr.minY + 7, width: 200, height: 21), .right)
        cycleText.foregroundColor = NSColor.white.cgColor

        // heat rising while it cycles
        let wisp = renderImage(CGSize(width: 14, height: 44), s) { pen in
            let c = pen.c
            c.setStrokeColor(self.col("FF8E7A")); c.setLineWidth(2.4); c.setLineCap(.round)
            for k in 0...20 {
                let y = 42 - CGFloat(k) * 2, x = 7 + 5 * CGFloat(sin(Double(k) / 3))
                if k == 0 { c.move(to: CGPoint(x: x, y: y)) } else { c.addLine(to: CGPoint(x: x, y: y)) }
            }
            c.strokePath()
        }
        wisps = (0..<4).map { _ in
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: 14, height: 44)
            l.contents = wisp
            l.opacity = 0
            canvas.addSublayer(l)
            return l
        }

        // the curves, drawn whole once and uncovered cycle by cycle
        reveal.anchorPoint = .zero
        reveal.masksToBounds = true
        reveal.position = CGPoint(x: plot.minX - 3, y: Self.H - plot.maxY - 3)
        reveal.bounds = CGRect(x: 0, y: 0, width: 0, height: plot.height + 6)
        curves.anchorPoint = .zero
        curves.frame = CGRect(x: 0, y: 0, width: plot.width + 6, height: plot.height + 6)
        curves.contents = renderImage(curves.bounds.size, s) { pen in
            let c = pen.c
            c.setLineWidth(2.6); c.setLineCap(.round); c.setLineJoin(.round)
            for g in self.gc {
                var x = 0.0
                c.beginPath()
                while x <= 40 {
                    let v = g.top / (1 + exp(-(x - g.m) / 1.6))
                    let p = CGPoint(x: 3 + plot.width * CGFloat(x / 40), y: 3 + plot.height - plot.height * CGFloat(v))
                    if x == 0 { c.move(to: p) } else { c.addLine(to: p) }
                    x += 0.25
                }
                c.setStrokeColor(self.col(g.hex)); c.strokePath()
            }
        }
        reveal.addSublayer(curves)
        canvas.addSublayer(reveal)
        heads = gc.map { g in
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
            l.contents = renderImage(CGSize(width: 18, height: 18), s) { pen in
                pen.c.setFillColor(self.col(g.hex, 0.3)); pen.c.fillEllipse(in: CGRect(x: 0, y: 0, width: 18, height: 18))
                pen.c.setFillColor(NSColor.white.cgColor); pen.c.fillEllipse(in: CGRect(x: 5.5, y: 5.5, width: 7, height: 7))
            }
            l.opacity = 0
            canvas.addSublayer(l)
            return l
        }
        ctDots = gc.map { g in
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
            l.cornerRadius = 4
            l.backgroundColor = col("FFD86B")
            l.position = up(CGPoint(x: plot.minX + plot.width * CGFloat(g.ct / 40), y: plot.maxY - plot.height * 0.2))
            l.opacity = 0
            canvas.addSublayer(l)
            return l
        }

        // the progress bar's fill
        barClip.anchorPoint = .zero
        barClip.position = up(CGPoint(x: 40, y: 378))
        barClip.bounds = CGRect(x: 0, y: 0, width: 0, height: 10)
        barClip.masksToBounds = true
        barClip.cornerRadius = 5
        barFill.anchorPoint = .zero
        barFill.frame = CGRect(x: 0, y: 0, width: 620, height: 10)
        barFill.colors = [col("2FA84F"), col("4A78B8")]
        barFill.startPoint = CGPoint(x: 0, y: 0.5)
        barFill.endPoint = CGPoint(x: 1, y: 0.5)
        barClip.addSublayer(barFill)
        canvas.addSublayer(barClip)

        // the "done" stamp
        let n = show.genes.count
        let words = "✓  \(n) gene\(n == 1 ? "" : "s") · \(show.conditions) condition\(show.conditions == 1 ? "" : "s") · ΔΔCt ready!"
        stamp.bounds = CGRect(x: 0, y: 0, width: 470, height: 70)
        stamp.position = up(CGPoint(x: 350, y: 238))
        stamp.contents = renderImage(CGSize(width: 470, height: 70), s) { pen in
            let c = pen.c
            let r = CGRect(x: 5, y: 5, width: 460, height: 60)
            c.addPath(CGPath(roundedRect: r, cornerWidth: 30, cornerHeight: 30, transform: nil)); c.setFillColor(self.col("2FA84F")); c.fillPath()
            c.addPath(CGPath(roundedRect: r, cornerWidth: 30, cornerHeight: 30, transform: nil)); c.setStrokeColor(NSColor.white.cgColor); c.setLineWidth(3); c.strokePath()
            Self.text(words, NSFont.systemFont(ofSize: 19, weight: .heavy).withDesign(.rounded), .white, CGPoint(x: 235, y: 35), .center)
        }
        stamp.opacity = 0
        canvas.addSublayer(stamp)
    }

    private enum Anchor { case left, center, right }
    /// Text centred vertically on `p`, as SwiftUI's draw(_:at:anchor:) places it.
    private static func text(_ s: String, _ font: NSFont, _ color: NSColor, _ p: CGPoint, _ anchor: Anchor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (s as NSString).size(withAttributes: attrs)
        let x = anchor == .left ? p.x : (anchor == .center ? p.x - size.width / 2 : p.x - size.width)
        (s as NSString).draw(at: CGPoint(x: x, y: p.y - size.height / 2), withAttributes: attrs)
    }

    // MARK: every frame

    private func apply(_ a: Double) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let len = ImportShow.length
        let fadeOut = 1 - clamp01((a - (len - 0.45)) / 0.45)
        let sc = CGFloat(0.6 + 0.4 * easeOutBack(a / 0.45)) * CGFloat(1 - 0.08 * (1 - fadeOut))
        group.setAffineTransform(CGAffineTransform(scaleX: sc, y: sc))
        group.opacity = Float(fadeOut)

        let phase = a < 1.2 ? "Loading your plate into the qTOWER³…" : (a < 3.2 ? "Cycling: 95 °C → 60 °C, 40 times…" : "ΔΔCt analysed. Your graphs are ready!")
        if phase != last.phase { last.phase = phase; phaseText.string = phase }

        // lid up and down while the plate goes in; the plate slides in from the left
        let open = a < 1.05 ? sin(.pi * clamp01(a / 1.05)) : 0
        lid.setAffineTransform(CGAffineTransform(rotationAngle: -CGFloat(0.75 * open)))
        let slide = easeOut((a - 0.3) / 0.7)
        plate.position = up(CGPoint(x: -180 + 255 * slide + 80, y: 247))
        plate.opacity = a < 1.15 ? 1 : 0

        // the light: amber, blinking green while cycling, steady green when done
        let cycling = a > 1.35 && a < 3.2
        let ledState = a >= 3.2 ? 1 : (cycling ? (sin(a * 18) > 0 ? 1 : 2) : 0)
        if ledState != last.led { last.led = ledState; led.backgroundColor = ledColors[ledState] }
        let temp = cycling ? (Int(a * 4) % 2 == 0 ? "95 °C" : "60 °C") : ""
        if temp != last.temp {
            last.temp = temp
            tempText.string = temp
            tempText.foregroundColor = col(temp.hasPrefix("95") ? "FF8E7A" : "9CCBFF")
        }
        for (i, w) in wisps.enumerated() {
            let q = (a * 0.9 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1)
            w.position = up(CGPoint(x: 80 + CGFloat(i) * 50 + 5 * CGFloat(sin(a * 6 + Double(i))), y: 140 - CGFloat(q) * 60))
            w.opacity = cycling ? Float(0.55 * (1 - q)) : 0
        }

        // the curves come up cycle by cycle; each gets its Ct mark where it crosses the threshold
        let cycle = 40 * clamp01((a - 1.35) / 1.85)
        reveal.bounds.size.width = 3 + plot.width * CGFloat(cycle / 40) + (cycle > 0 ? 2 : 0)
        for (k, g) in gc.enumerated() {
            let v = g.top / (1 + exp(-(cycle - g.m) / 1.6))
            heads[k].position = up(CGPoint(x: plot.minX + plot.width * CGFloat(cycle / 40), y: plot.maxY - plot.height * CGFloat(v)))
            heads[k].opacity = cycle > 0 && cycle < 40 ? 1 : 0
            let on = cycle >= g.ct
            ctDots[k].opacity = on ? 1 : 0
            let pop = on ? CGFloat(easeOutBack((cycle - g.ct) / 3)) : 0
            ctDots[k].setAffineTransform(CGAffineTransform(scaleX: max(0.01, pop), y: max(0.01, pop)))
        }
        if Int(cycle) != last.cycle { last.cycle = Int(cycle); cycleText.string = "Cycle \(Int(cycle)) / 40" }

        barClip.bounds.size.width = 620 * CGFloat(clamp01(a / 3.2))

        if a >= 3.2 {
            let s = CGFloat(easeOutBack((a - 3.2) / 0.4))
            stamp.setAffineTransform(CGAffineTransform(rotationAngle: 6 * .pi / 180).scaledBy(x: max(0.01, s), y: max(0.01, s)))
            stamp.opacity = 1
        } else {
            stamp.opacity = 0
        }
    }
}

private extension NSFont {
    func withDesign(_ d: NSFontDescriptor.SystemDesign) -> NSFont {
        fontDescriptor.withDesign(d).flatMap { NSFont(descriptor: $0, size: pointSize) } ?? self
    }
}
