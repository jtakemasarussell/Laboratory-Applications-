import SwiftUI
import AppKit
import QuartzCore

// MARK: - Waiting area: the qTOWER, lid open, hungry for files
//
// Shown on the right of Results & graphs until data is opened. The qTOWER waits with its lid open;
// Excel sheets and qTOWER exports tumble in, the lid slams shut, it hums through its cycles with the
// block glowing hot, and with a "ding" the lid pops open and the graphs come out baked, like toast.
// While files are dragged over the drop box on the left it gets excited. Like the banner, everything
// is drawn into images once; the shared 20-frames-a-second clock only moves, bends and fades them,
// and stops while the app is in the background.

private func ns(_ hex: String, _ a: CGFloat = 1) -> NSColor { NSColor(hex: hex, alpha: a) }

/// Files dropped (or opened) while the qTOWER waits: it swallows them, then they are imported.
struct Gulp: Equatable {
    let id = UUID()
    let urls: [URL]
    var names: [String] { urls.map { $0.lastPathComponent } }
}

// the loop, in seconds
// files fly in from the left (where the drop box is) and sprinkle down from above, one after another
private let filesAt = 0.9, fileGap = 0.25, fileFall = 1.2, fileCount = 16
private let closeAt = filesAt + Double(fileCount - 1) * fileGap + fileFall + 0.4
private let slamAt = closeAt + 0.6, cycleFrom = slamAt + 0.4, dingAt = cycleFrom + 4.9, sinkAt = dingAt + 3.9, loopEnd = sinkAt + 0.9
private let openAngle = 105.0

private func label(_ s: String, _ font: NSFont, _ color: NSColor, at p: CGPoint, center: Bool = false) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let w = (s as NSString).size(withAttributes: attrs).width
    (s as NSString).draw(at: CGPoint(x: center ? p.x - w / 2 : p.x, y: p.y), withAttributes: attrs)
}

private func roundedSystem(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let f = NSFont.systemFont(ofSize: size, weight: weight)
    return f.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? f
}

final class RunSandboxView: NSView, AmbientClient {
    var ambientActive = false {
        didSet {
            guard ambientActive != oldValue else { return }
            if !ambientActive { rest() }
            AmbientClock.shared.update()
        }
    }
    /// Files are being dragged over the drop box: the qTOWER wants them.
    var eager = false {
        didSet {
            guard eager != oldValue else { return }
            clock = eager ? 0 : 0.3
            if !ambientActive { rest() }
        }
    }

    private let stage = CALayer(), back = CALayer()
    private let machine = CALayer()
    private let bodyBack = CALayer(), bodyFront = CALayer()
    private let blockGlow = CALayer(), heat = CALayer()
    private let lid = CAShapeLayer(), lidEdge = CAShapeLayer(), lidPad = CAShapeLayer()
    private let toastBox = CALayer(), toastMask = CALayer(), toast = CALayer()
    private let led = CALayer(), ledGlow = CALayer()
    private let screenTop = CATextLayer(), screenSub = CATextLayer(), screenBar = CALayer()
    private let headline = CATextLayer(), subline = CATextLayer()
    private let bubble = CALayer()
    private var sprites: [(layer: CALayer, from: CGPoint, via: CGPoint, to: CGPoint, spin: CGFloat)] = []
    private var rings: [CALayer] = []
    private var steam: [CALayer] = []
    private var shimmer: [CALayer] = []
    // the extras: the run as a hologram over the lid, a reading light, crumbs, sparkles, butter, and clicks
    private let holo = CALayer(), holoBeam = CALayer(), holoPanel = CALayer(), holoReveal = CALayer(), holoCurves = CALayer(), holoCursor = CALayer()
    private var ctDots: [CALayer] = []
    private var ctAt: [Double] = []
    private var holoPlot = CGRect.zero       // inside the hologram, layer coordinates
    private let scan = CALayer()
    private var scanImages: [CGImage?] = []
    private var shownScan = -1
    private var crumbs: [CALayer] = []
    private var sparkles: [CALayer] = []
    private let butter = CALayer(), drip = CALayer()
    private var toastImages: [CGImage?] = []
    private var bites = 0, shownBites = -1
    private var biteAt = -10.0, biteFrom = CGPoint.zero
    private var pokeAt = -10.0
    // a real drop: the files, with their names, fall into the lid, it slams, and then they are imported
    private var gulpID: UUID?
    private var gulpActive = false, gulpReported = false
    private var gulpAt = 0.0, gulpTotal = 0
    private var gulpDone: ((UUID) -> Void)?
    private var gulpSprites: [(layer: CALayer, from: CGPoint, via: CGPoint, to: CGPoint, spin: CGFloat)] = []
    private var built: CGSize = .zero
    private var clock = 0.6
    private var frame_ = 0
    private var last = (head: "", top: "", sub: "", angle: -1.0, led: "")

    // geometry, top-down
    private var W: CGFloat = 0, H: CGFloat = 0
    private var x0: CGFloat = 0, bw: CGFloat = 0, frontH: CGFloat = 0, depth: CGFloat = 0, skew: CGFloat = 0
    private var baseY: CGFloat = 0, topY: CGFloat = 0, hingeY: CGFloat = 0, lidLen: CGFloat = 0
    private var slotY: CGFloat = 0, toastH: CGFloat = 0
    private var opening: [CGPoint] = []      // block opening: front-left, front-right, back-right, back-left
    /// The instrument's own area: its pictures and the lid are drawn at this size, not the whole panel's,
    /// so moving them asks little of the window server.
    private var mr = CGRect.zero, mrUp = CGRect.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        layer?.addSublayer(stage)
        stage.addSublayer(back)
        stage.addSublayer(machine)
        stage.addSublayer(holoBeam)
        stage.addSublayer(holo)
        holo.anchorPoint = CGPoint(x: 0.5, y: 0)
        for l in [holoPanel, holoReveal, holoCursor] { holo.addSublayer(l) }
        holoReveal.anchorPoint = .zero
        holoReveal.masksToBounds = true
        holoCurves.anchorPoint = .zero
        holoReveal.addSublayer(holoCurves)
        for l in [bodyBack, blockGlow, bodyFront] { machine.addSublayer(l) }
        machine.addSublayer(lidPad)
        machine.insertSublayer(lid, below: lidPad)
        machine.addSublayer(lidEdge)
        machine.addSublayer(scan)
        machine.addSublayer(heat)
        machine.addSublayer(toastBox)
        toastBox.mask = toastMask
        toastMask.backgroundColor = NSColor.white.cgColor
        toastBox.addSublayer(toast)
        toast.addSublayer(drip)
        toast.addSublayer(butter)
        for l in [ledGlow, led, screenBar] { machine.addSublayer(l) }
        for t in [screenTop, screenSub, headline, subline] {
            t.contentsScale = screenScale
            t.truncationMode = .end
            t.isWrapped = false
        }
        machine.addSublayer(screenTop)
        machine.addSublayer(screenSub)
        stage.addSublayer(headline)
        stage.addSublayer(subline)
        lid.lineJoin = .round
        lidEdge.lineJoin = .round
        lidPad.lineJoin = .round
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { AmbientClock.shared.add(self) } else { AmbientClock.shared.remove(self) }
    }

    override func layout() {
        super.layout()
        guard bounds.size != built, bounds.width > 300, bounds.height > 300 else { return }
        build()
    }

    private func up(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height) }
    private func up(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: H - p.y) }

    /// A point on the block opening, u across (0 left … 1 right), v from the back (0) to the front (1).
    private func onOpening(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        let fl = opening[0], fr = opening[1], br = opening[2], bl = opening[3]
        let front = CGPoint(x: fl.x + (fr.x - fl.x) * u, y: fl.y + (fr.y - fl.y) * u)
        let backP = CGPoint(x: bl.x + (br.x - bl.x) * u, y: bl.y + (br.y - bl.y) * u)
        return CGPoint(x: backP.x + (front.x - backP.x) * v, y: backP.y + (front.y - backP.y) * v)
    }

    // MARK: drawing once

    private func build() {
        built = bounds.size
        W = bounds.width; H = bounds.height
        // big enough to enjoy, small enough that the open lid stays clear of the headline
        bw = max(200, min(W * 0.44, (H * 0.86 - 82) / 1.18, 420))
        frontH = bw * 0.42
        depth = bw * 0.24
        skew = bw * 0.09
        x0 = (W - bw) / 2
        baseY = H * 0.86
        topY = baseY - frontH
        hingeY = topY - depth
        lidLen = frontH * 1.0
        let inset: CGFloat = 0.16
        opening = [CGPoint(x: x0 + bw * inset, y: topY - depth * 0.16), CGPoint(x: x0 + bw * (1 - inset), y: topY - depth * 0.16),
                   CGPoint(x: x0 + bw - skew - bw * (inset - 0.05), y: hingeY + depth * 0.2), CGPoint(x: x0 + skew + bw * (inset - 0.05), y: hingeY + depth * 0.2)]
        slotY = topY - depth * 0.55
        toastH = bw * 0.36

        let lidTop = hingeY - lidLen - depth * 0.65 - 12
        mr = CGRect(x: x0 - bw * 0.08, y: lidTop, width: bw * 1.16, height: baseY + 12 - lidTop).integral
        mrUp = up(mr)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        stage.frame = bounds
        back.frame = bounds
        machine.anchorPoint = CGPoint(x: 0.5, y: (H - baseY) / H)
        machine.bounds = bounds
        machine.position = CGPoint(x: W / 2, y: H - baseY)
        for l in [bodyBack, bodyFront, lid, lidEdge, lidPad] { l.frame = mrUp }

        drawBackground()
        drawBody()
        drawExtras()
        drawWow()
        buildSprites()
        window?.invalidateCursorRects(for: self)
        lid.path = nil
        last = ("", "", "", -1, "")
        if ambientActive { show(clock) } else { rest() }
    }

    /// No backdrop: the qTOWER stands on the card itself, with a soft shadow under it.
    private func drawBackground() {
        let W = self.W, baseY = self.baseY, bw = self.bw
        back.contents = renderImage(bounds.size, screenScale) { pen in
            let c = pen.c
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            if let g = CGGradient(colorsSpace: space, colors: [NSColor(white: 0, alpha: 0.28).cgColor, NSColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 1]) {
                c.saveGState()
                c.translateBy(x: W / 2, y: baseY + 3)
                c.scaleBy(x: 1, y: 0.13)
                c.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: bw * 0.62, options: [])
                c.restoreGState()
            }
        }
    }

    private func drawBody() {
        let x0 = self.x0, bw = self.bw, topY = self.topY, frontH = self.frontH, hingeY = self.hingeY, skew = self.skew, depth = self.depth
        let opening = self.opening, mr = self.mr
        // the top face and the block, seen from a little above
        bodyBack.contents = renderImage(mr.size, screenScale) { pen in
            let c = pen.c
            c.translateBy(x: -mr.minX, y: -mr.minY)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let top = CGMutablePath()
            top.move(to: CGPoint(x: x0, y: topY)); top.addLine(to: CGPoint(x: x0 + bw, y: topY))
            top.addLine(to: CGPoint(x: x0 + bw - skew, y: hingeY)); top.addLine(to: CGPoint(x: x0 + skew, y: hingeY)); top.closeSubpath()
            c.saveGState(); c.addPath(top); c.clip()
            if let g = CGGradient(colorsSpace: space, colors: [ns("C3CEDD").cgColor, ns("EEF2F7").cgColor] as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(g, start: CGPoint(x: 0, y: hingeY), end: CGPoint(x: 0, y: topY), options: [])
            }
            c.restoreGState()
            c.addPath(top); c.setStrokeColor(ns("8A99AF").cgColor); c.setLineWidth(1); c.strokePath()
            // the block
            let blk = CGMutablePath()
            blk.addLines(between: opening); blk.closeSubpath()
            c.saveGState(); c.addPath(blk); c.clip()
            if let g = CGGradient(colorsSpace: space, colors: [ns("3B4859").cgColor, ns("6D7C92").cgColor] as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(g, start: CGPoint(x: 0, y: opening[3].y), end: CGPoint(x: 0, y: opening[0].y), options: [])
            }
            c.restoreGState()
            c.addPath(blk); c.setStrokeColor(ns("2A3443").cgColor); c.setLineWidth(1.2); c.strokePath()
            for r in 0..<8 {
                for k in 0..<12 {
                    let u = (CGFloat(k) + 0.5) / 12, v = (CGFloat(r) + 0.5) / 8
                    let fl = opening[0], fr = opening[1], br = opening[2], bl = opening[3]
                    let fx = fl.x + (fr.x - fl.x) * u, bx = bl.x + (br.x - bl.x) * u
                    let p = CGPoint(x: bx + (fx - bx) * v, y: bl.y + (fl.y - bl.y) * v)
                    let rad = 2.1 * (0.72 + 0.28 * v) * bw / 400
                    c.setFillColor(ns("161D29").cgColor)
                    c.fillEllipse(in: CGRect(x: p.x - rad * 1.25, y: p.y - rad * 0.8, width: rad * 2.5, height: rad * 1.6))
                    c.setFillColor(NSColor(white: 1, alpha: 0.18).cgColor)
                    c.fillEllipse(in: CGRect(x: p.x - rad * 0.6, y: p.y - rad * 0.9, width: rad * 1.2, height: rad * 0.5))
                }
            }
            // the hinge along the back
            c.setFillColor(ns("3A4556").cgColor)
            c.fill(CGRect(x: x0 + skew + 6, y: hingeY - 3, width: bw - 2 * skew - 12, height: 5))
        }
        // the front: a pale case, a dark panel with the name and the screen
        bodyFront.contents = renderImage(mr.size, screenScale) { pen in
            let c = pen.c
            c.translateBy(x: -mr.minX, y: -mr.minY)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let front = CGRect(x: x0, y: topY, width: bw, height: frontH)
            let shape = CGPath(roundedRect: front, cornerWidth: 14, cornerHeight: 14, transform: nil)
            c.saveGState(); c.addPath(shape); c.clip()
            if let g = CGGradient(colorsSpace: space, colors: [ns("F6F8FB").cgColor, ns("D3DCE8").cgColor] as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(g, start: CGPoint(x: 0, y: front.minY), end: CGPoint(x: 0, y: front.maxY), options: [])
            }
            // a shine down the left
            if let g = CGGradient(colorsSpace: space, colors: [NSColor(white: 1, alpha: 0.7).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(g, start: CGPoint(x: front.minX, y: 0), end: CGPoint(x: front.minX + bw * 0.25, y: 0), options: [])
            }
            c.restoreGState()
            c.addPath(shape); c.setStrokeColor(ns("8A99AF").cgColor); c.setLineWidth(1.2); c.strokePath()
            // seam under the lid
            c.setStrokeColor(ns("AFBFD4").cgColor); c.setLineWidth(1)
            c.strokeLineSegments(between: [CGPoint(x: front.minX + 8, y: front.minY + 16), CGPoint(x: front.maxX - 8, y: front.minY + 16)])
            // the panel
            let panel = CGRect(x: front.minX + 18, y: front.minY + frontH * 0.3, width: bw - 36, height: frontH * 0.44)
            let pp = CGPath(roundedRect: panel, cornerWidth: 10, cornerHeight: 10, transform: nil)
            c.saveGState(); c.addPath(pp); c.clip()
            if let g = CGGradient(colorsSpace: space, colors: [ns("263244").cgColor, ns("141B26").cgColor] as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(g, start: CGPoint(x: 0, y: panel.minY), end: CGPoint(x: 0, y: panel.maxY), options: [])
            }
            c.restoreGState()
            let scale = bw / 400
            label("qTOWER³", roundedSystem(19 * scale, .bold), ns("E3E9F2"), at: CGPoint(x: panel.minX + 16 * scale, y: panel.minY + panel.height * 0.18))
            label("real-time PCR", NSFont.systemFont(ofSize: 10 * scale, weight: .medium), ns("8FA3BE"), at: CGPoint(x: panel.minX + 17 * scale, y: panel.minY + panel.height * 0.18 + 25 * scale))
            let screen = self.screenRect()
            let sp = CGPath(roundedRect: screen, cornerWidth: 6, cornerHeight: 6, transform: nil)
            c.addPath(sp); c.setFillColor(ns("06110D").cgColor); c.fillPath()
            c.addPath(sp); c.setStrokeColor(ns("3A475B").cgColor); c.setLineWidth(1.5); c.strokePath()
            c.saveGState(); c.addPath(sp); c.clip()
            if let g = CGGradient(colorsSpace: space, colors: [NSColor(white: 1, alpha: 0.08).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(g, start: CGPoint(x: 0, y: screen.minY), end: CGPoint(x: 0, y: screen.midY), options: [])
            }
            c.restoreGState()
            // vents and feet
            c.setStrokeColor(ns("B8C4D6").cgColor); c.setLineWidth(2); c.setLineCap(.round)
            for i in 0..<9 {
                let x = front.minX + bw * 0.3 + CGFloat(i) * bw * 0.05
                c.strokeLineSegments(between: [CGPoint(x: x, y: front.maxY - frontH * 0.17), CGPoint(x: x, y: front.maxY - frontH * 0.08)])
            }
            c.setFillColor(ns("3A4556").cgColor)
            for fx in [front.minX + 22, front.maxX - 52] {
                c.addPath(CGPath(roundedRect: CGRect(x: fx, y: front.maxY - 2, width: 30, height: 6), cornerWidth: 3, cornerHeight: 3, transform: nil)); c.fillPath()
            }
            _ = depth
        }
    }

    private func screenRect() -> CGRect {
        let front = CGRect(x: x0, y: topY, width: bw, height: frontH)
        let panel = CGRect(x: front.minX + 18, y: front.minY + frontH * 0.3, width: bw - 36, height: frontH * 0.44)
        let sw = panel.width * 0.46
        return CGRect(x: panel.maxX - sw - 10, y: panel.minY + 8, width: sw, height: panel.height - 16)
    }

    private func ledCenter() -> CGPoint {
        let front = CGRect(x: x0, y: topY, width: bw, height: frontH)
        let panel = CGRect(x: front.minX + 18, y: front.minY + frontH * 0.3, width: bw - 36, height: frontH * 0.44)
        return CGPoint(x: panel.minX + 22 * bw / 400, y: panel.maxY - 14 * bw / 400)
    }

    private func drawExtras() {
        let scale = bw / 400
        // the screen's two lines and its progress bar
        let screen = screenRect()
        func text(_ t: CATextLayer, _ r: CGRect, _ size: CGFloat, _ color: NSColor, _ weight: NSFont.Weight) {
            t.frame = up(r)
            t.font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            t.fontSize = size
            t.foregroundColor = color.cgColor
        }
        text(screenTop, CGRect(x: screen.minX + 9, y: screen.minY + 6 * scale, width: screen.width - 14, height: 18 * scale), 13 * scale, ns("8CF5A4"), .bold)
        text(screenSub, CGRect(x: screen.minX + 9, y: screen.minY + 24 * scale, width: screen.width - 14, height: 15 * scale), 10 * scale, ns("8CF5A4", 0.7), .medium)
        screenBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        screenBar.backgroundColor = ns("8CF5A4", 0.85).cgColor
        screenBar.cornerRadius = 1.5
        screenBar.bounds = CGRect(x: 0, y: 0, width: 0, height: 3)
        screenBar.position = up(CGPoint(x: screen.minX + 9, y: screen.maxY - 9 * scale))
        // the status light
        let lc = ledCenter()
        led.bounds = CGRect(x: 0, y: 0, width: 9 * scale, height: 9 * scale)
        led.cornerRadius = 4.5 * scale
        led.position = up(lc)
        ledGlow.bounds = CGRect(x: 0, y: 0, width: 30 * scale, height: 30 * scale)
        ledGlow.position = up(lc)
        ledGlow.contents = Self.glow("FFFFFF", 30 * scale, 0.9)
        // heat over the lid seam while cycling
        let hr = CGRect(x: x0 - bw * 0.1, y: hingeY - depth * 1.2, width: bw * 1.2, height: depth * 2.6)
        heat.frame = up(hr)
        heat.contents = renderImage(hr.size, screenScale) { pen in
            let c = pen.c
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            if let g = CGGradient(colorsSpace: space, colors: [ns("FF8A3D", 0.62).cgColor, ns("FF5A2E", 0.22).cgColor, ns("FF5A2E", 0).cgColor] as CFArray, locations: [0, 0.45, 1]) {
                c.translateBy(x: hr.width / 2, y: hr.height * 0.55)
                c.scaleBy(x: 1, y: hr.height / hr.width)
                c.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: hr.width / 2, options: [])
            }
        }
        heat.opacity = 0
        // the block lights up as files land
        let br = CGRect(x: opening[0].x - 20, y: opening[3].y - 20, width: opening[1].x - opening[0].x + 40, height: opening[0].y - opening[3].y + 40)
        blockGlow.frame = up(br)
        blockGlow.contents = renderImage(br.size, screenScale) { pen in
            let c = pen.c
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            if let g = CGGradient(colorsSpace: space, colors: [ns("8CF5A4", 0.75).cgColor, ns("8CF5A4", 0).cgColor] as CFArray, locations: [0, 1]) {
                c.translateBy(x: br.width / 2, y: br.height / 2)
                c.scaleBy(x: 1, y: br.height / br.width)
                c.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: br.width / 2, options: [])
            }
        }
        blockGlow.opacity = 0
        // the toast: it rises out of the block, hidden below the slot
        let tw = bw * 0.34
        toastBox.frame = bounds
        toastMask.frame = up(CGRect(x: 0, y: 0, width: W, height: slotY))
        toast.bounds = CGRect(x: 0, y: 0, width: tw, height: toastH)
        toast.contents = Self.toastImage(CGSize(width: tw, height: toastH))
        toast.position = up(CGPoint(x: W / 2, y: slotY + toastH / 2 + 6))
        // steam off the toast, shimmer off the lid
        steam.forEach { $0.removeFromSuperlayer() }
        shimmer.forEach { $0.removeFromSuperlayer() }
        let wisp = Self.wisp(CGSize(width: 18 * scale, height: 56 * scale))
        steam = (0..<4).map { _ in
            let l = CALayer(); l.bounds = CGRect(x: 0, y: 0, width: 18 * scale, height: 56 * scale); l.contents = wisp; l.opacity = 0
            stage.addSublayer(l); return l
        }
        shimmer = (0..<3).map { _ in
            let l = CALayer(); l.bounds = CGRect(x: 0, y: 0, width: 18 * scale, height: 56 * scale); l.contents = wisp; l.opacity = 0
            machine.addSublayer(l); return l
        }
        // "Ding!"
        let words = "Ding! Your graphs are baked."
        let font = roundedSystem(14 * max(0.85, scale), .bold)
        let tw2 = (words as NSString).size(withAttributes: [.font: font]).width
        let bs = CGSize(width: tw2 + 36, height: 48)
        bubble.removeFromSuperlayer()
        stage.addSublayer(bubble)
        bubble.bounds = CGRect(origin: .zero, size: bs)
        bubble.anchorPoint = CGPoint(x: 0.2, y: 0)
        bubble.position = up(CGPoint(x: x0 + bw * 0.02, y: hingeY - lidLen * 0.62))
        bubble.contents = renderImage(bs, screenScale) { pen in
            let c = pen.c
            let body = CGRect(x: 1.5, y: 1.5, width: bs.width - 3, height: bs.height - 14)
            let p = CGMutablePath()
            p.addRoundedRect(in: body, cornerWidth: 14, cornerHeight: 14)
            p.move(to: CGPoint(x: bs.width * 0.2 - 8, y: body.maxY - 1))
            p.addLine(to: CGPoint(x: bs.width * 0.2, y: bs.height - 1))
            p.addLine(to: CGPoint(x: bs.width * 0.2 + 8, y: body.maxY - 1))
            c.addPath(p); c.setFillColor(NSColor.white.cgColor); c.fillPath()
            c.addPath(p); c.setStrokeColor(ns("B7C5D8").cgColor); c.setLineWidth(1.2); c.strokePath()
            label(words, font, ns("1E4A83"), at: CGPoint(x: bs.width / 2, y: body.midY - font.pointSize * 0.62), center: true)
        }
        bubble.opacity = 0
        // the headline, top left
        func head(_ t: CATextLayer, _ r: CGRect, _ size: CGFloat, _ color: NSColor, _ weight: NSFont.Weight) {
            t.frame = up(r)
            t.font = NSFont.systemFont(ofSize: size, weight: weight)
            t.fontSize = size
            t.foregroundColor = color.cgColor
        }
        head(headline, CGRect(x: 22, y: 18, width: W - 44, height: 26), 19, .white, .semibold)
        head(subline, CGRect(x: 22, y: 46, width: W - 44, height: 18), 12, ns("BFD9FF"), .regular)
        applyColors()
        // lid colours
        lidEdge.fillColor = ns("1E2632").cgColor
        lidPad.fillColor = ns("AEB9C9").cgColor
        lidPad.strokeColor = ns("8A99AF").cgColor
        lidPad.lineWidth = 1
        lid.strokeColor = ns("1A212C").cgColor
        lid.lineWidth = 1.2
        stage.addSublayer(bubble)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        applyColors()
        CATransaction.commit()
    }

    /// The headline in the card's ink, light or dark.
    private func applyColors() {
        let dark = effectiveAppearance.isDark
        headline.foregroundColor = ns(dark ? "E8EFF8" : "172033").cgColor
        subline.foregroundColor = ns(dark ? "9AAEC8" : "5A6B85").cgColor
    }

    // MARK: the extras, drawn once

    private func drawWow() {
        let scale = bw / 400
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // --- a hologram of the run, projected over the closed lid
        let hh = min(160, hingeY - 22 - 84)
        holo.isHidden = hh < 70
        holoBeam.isHidden = hh < 70
        let hw = bw * 0.86
        let hr = CGRect(x: W / 2 - hw / 2, y: hingeY - 22 - max(hh, 1), width: hw, height: max(hh, 1))
        holo.bounds = CGRect(x: 0, y: 0, width: hw, height: hr.height)
        holo.position = up(CGPoint(x: W / 2, y: hr.maxY))
        holoPanel.frame = holo.bounds
        let pad: CGFloat = 12
        let plotTD = CGRect(x: pad + 20, y: pad + 12, width: hw - pad * 2 - 24, height: hr.height - pad * 2 - 22)
        let plot = CGRect(x: plotTD.minX, y: hr.height - plotTD.maxY, width: plotTD.width, height: plotTD.height)
        holoPlot = plot
        let hc = ["2FA84F", "E2A400", "E2483D", "8E5BD1"]
        let mids = [0.40, 0.50, 0.60, 0.70], tops = [0.92, 0.82, 0.72, 0.62], thr = 0.16, base = 0.02
        ctAt = (0..<4).map { mids[$0] - log(tops[$0] / (thr - base) - 1) / 14 }
        holoPanel.contents = renderImage(hr.size, screenScale) { pen in
            let c = pen.c
            let r = CGRect(origin: .zero, size: hr.size).insetBy(dx: 1, dy: 1)
            let shape = CGPath(roundedRect: r, cornerWidth: 12, cornerHeight: 12, transform: nil)
            c.addPath(shape); c.setFillColor(ns("38C6E8", 0.1).cgColor); c.fillPath()
            c.saveGState(); c.addPath(shape); c.clip()
            c.setFillColor(ns("38C6E8", 0.07).cgColor)
            var y: CGFloat = 0
            while y < r.maxY { c.fill(CGRect(x: 0, y: y, width: r.maxX + 2, height: 1)); y += 3 }
            c.restoreGState()
            c.addPath(shape); c.setStrokeColor(ns("1BA6C9", 0.65).cgColor); c.setLineWidth(1.3); c.strokePath()
            c.setStrokeColor(ns("1BA6C9", 0.16).cgColor); c.setLineWidth(1)
            for k in 1...3 {
                let yy = plotTD.maxY - plotTD.height * CGFloat(k) / 4
                c.strokeLineSegments(between: [CGPoint(x: plotTD.minX, y: yy), CGPoint(x: plotTD.maxX, y: yy)])
            }
            c.setStrokeColor(ns("1BA6C9", 0.6).cgColor)
            c.strokeLineSegments(between: [CGPoint(x: plotTD.minX, y: plotTD.minY), CGPoint(x: plotTD.minX, y: plotTD.maxY),
                                           CGPoint(x: plotTD.minX, y: plotTD.maxY), CGPoint(x: plotTD.maxX, y: plotTD.maxY)])
            c.setLineDash(phase: 0, lengths: [4, 3])
            let ty = plotTD.maxY - plotTD.height * CGFloat(thr)
            c.strokeLineSegments(between: [CGPoint(x: plotTD.minX, y: ty), CGPoint(x: plotTD.maxX, y: ty)])
            c.setLineDash(phase: 0, lengths: [])
            label("ΔRn", NSFont.systemFont(ofSize: 9, weight: .bold), ns("1593B8"), at: CGPoint(x: pad - 3, y: plotTD.minY - 3))
            label("cycle", NSFont.systemFont(ofSize: 9, weight: .bold), ns("1593B8"), at: CGPoint(x: plotTD.maxX - 26, y: plotTD.maxY + 3))
            label("● LIVE", NSFont.systemFont(ofSize: 9, weight: .heavy), ns("E2483D"), at: CGPoint(x: r.maxX - 46, y: pad - 5))
        }
        holoReveal.position = CGPoint(x: plot.minX, y: plot.minY - 4)
        holoReveal.bounds = CGRect(x: 0, y: 0, width: 0, height: plot.height + 8)
        holoCurves.frame = CGRect(x: 0, y: 4, width: plot.width, height: plot.height)
        holoCurves.contents = renderImage(plot.size, screenScale) { pen in
            let c = pen.c
            c.setLineCap(.round); c.setLineJoin(.round)
            for k in 0..<4 {
                let path = CGMutablePath()
                var u = 0.0
                while u <= 1.0001 {
                    let v = base + tops[k] / (1 + exp(-(u - mids[k]) * 14))
                    let p = CGPoint(x: plot.width * CGFloat(u), y: plot.height * CGFloat(1 - v))
                    if u == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    u += 0.01
                }
                c.addPath(path); c.setStrokeColor(ns(hc[k], 0.22).cgColor); c.setLineWidth(6); c.strokePath()
                c.addPath(path); c.setStrokeColor(ns(hc[k]).cgColor); c.setLineWidth(2.2); c.strokePath()
            }
        }
        holoCursor.bounds = CGRect(x: 0, y: 0, width: 2.5, height: plot.height)
        holoCursor.backgroundColor = ns("38C6E8", 0.85).cgColor
        holoCursor.cornerRadius = 1.25
        ctDots.forEach { $0.removeFromSuperlayer() }
        ctDots = (0..<4).map { k in
            let d = CALayer()
            d.bounds = CGRect(x: 0, y: 0, width: 11, height: 11)
            d.cornerRadius = 5.5
            d.backgroundColor = ns(hc[k]).cgColor
            d.borderColor = NSColor.white.cgColor
            d.borderWidth = 2
            d.position = CGPoint(x: plot.minX + plot.width * CGFloat(ctAt[k]), y: plot.minY + plot.height * CGFloat(thr))
            d.opacity = 0
            holo.addSublayer(d)
            return d
        }
        // the beam that projects it, from the lid up to the plot
        let beamTop = hr.maxY - 2, beamBottom = hingeY + depth * 0.45
        let br = CGRect(x: W / 2 - hw / 2, y: beamTop, width: hw, height: max(1, beamBottom - beamTop))
        holoBeam.frame = up(br)
        holoBeam.contents = renderImage(br.size, screenScale) { pen in
            let c = pen.c
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: br.width, y: 0))
            p.addLine(to: CGPoint(x: br.width * 0.64, y: br.height)); p.addLine(to: CGPoint(x: br.width * 0.36, y: br.height))
            p.closeSubpath()
            c.addPath(p); c.clip()
            if let g = CGGradient(colorsSpace: space, colors: [ns("38C6E8", 0.04).cgColor, ns("38C6E8", 0.34).cgColor] as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: br.height), options: [])
            }
        }
        holo.opacity = 0
        holoBeam.opacity = 0

        // --- the reading light, one image per dye
        let ss = CGSize(width: 90 * scale, height: 22 * scale)
        scanImages = ["8CF5A4", "FFD86B", "FF9A86", "C7A4FF"].map { hex in
            renderImage(ss, screenScale) { pen in
                let c = pen.c
                if let g = CGGradient(colorsSpace: space, colors: [NSColor.white.cgColor, ns(hex, 0.9).cgColor, ns(hex, 0).cgColor] as CFArray, locations: [0, 0.18, 1]) {
                    c.translateBy(x: ss.width / 2, y: ss.height / 2)
                    c.scaleBy(x: 1, y: ss.height / ss.width)
                    c.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: ss.width / 2, options: [])
                }
            }
        }
        scan.bounds = CGRect(origin: .zero, size: ss)
        scan.opacity = 0
        shownScan = -1

        // --- crumbs and sparkles
        crumbs.forEach { $0.removeFromSuperlayer() }
        crumbs = (0..<16).map { i in
            let l = CALayer()
            let r = CGFloat(2 + 2.5 * hash01(i, 501)) * max(0.8, scale)
            l.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 1.6)
            l.cornerRadius = r * 0.7
            l.backgroundColor = ns(["C27A2C", "A8621F", "E0A050", "8E4E16"][i % 4]).cgColor
            l.opacity = 0
            stage.addSublayer(l)
            return l
        }
        let star = renderImage(CGSize(width: 22, height: 22), screenScale) { pen in
            let c = pen.c
            if let g = CGGradient(colorsSpace: space, colors: [ns("FFD86B", 0.75).cgColor, ns("FFD86B", 0).cgColor] as CFArray, locations: [0, 1]) {
                c.drawRadialGradient(g, startCenter: CGPoint(x: 11, y: 11), startRadius: 0, endCenter: CGPoint(x: 11, y: 11), endRadius: 11, options: [])
            }
            let p = CGMutablePath()
            p.addLines(between: [CGPoint(x: 11, y: 1.5), CGPoint(x: 13, y: 9), CGPoint(x: 20.5, y: 11), CGPoint(x: 13, y: 13),
                                 CGPoint(x: 11, y: 20.5), CGPoint(x: 9, y: 13), CGPoint(x: 1.5, y: 11), CGPoint(x: 9, y: 9)])
            p.closeSubpath()
            c.addPath(p); c.setFillColor(NSColor.white.cgColor); c.fillPath()
            c.addPath(p); c.setStrokeColor(ns("E8B92E", 0.8).cgColor); c.setLineWidth(0.8); c.strokePath()
        }
        sparkles.forEach { $0.removeFromSuperlayer() }
        sparkles = (0..<6).map { _ in
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
            l.contents = star
            l.opacity = 0
            stage.addSublayer(l)
            return l
        }

        // --- the toast, bitten or not, and a pat of butter that melts down it
        let tsize = toast.bounds.size
        toastImages = (0...3).map { Self.toastImage(tsize, bites: $0) }
        shownBites = -1
        let tw = tsize.width
        let bsz = CGSize(width: tw * 0.34, height: tw * 0.2)
        butter.bounds = CGRect(origin: .zero, size: bsz)
        butter.anchorPoint = CGPoint(x: 0.5, y: 0)
        butter.contents = renderImage(bsz, screenScale) { pen in
            let c = pen.c
            let r = CGRect(origin: .zero, size: bsz).insetBy(dx: 1, dy: 1)
            let shape = CGPath(roundedRect: r, cornerWidth: bsz.height * 0.32, cornerHeight: bsz.height * 0.32, transform: nil)
            c.addPath(shape); c.setFillColor(ns("FFE9A3").cgColor); c.fillPath()
            c.addPath(shape); c.setStrokeColor(ns("E2B93F").cgColor); c.setLineWidth(1.2); c.strokePath()
            c.setFillColor(NSColor(white: 1, alpha: 0.75).cgColor)
            c.fill(CGRect(x: r.minX + r.width * 0.16, y: r.minY + r.height * 0.24, width: r.width * 0.4, height: r.height * 0.16))
        }
        butter.opacity = 0
        let dsz = CGSize(width: max(6, tw * 0.09), height: toastH * 0.42)
        drip.bounds = CGRect(origin: .zero, size: dsz)
        drip.anchorPoint = CGPoint(x: 0.5, y: 1)
        drip.contents = renderImage(dsz, screenScale) { pen in
            let c = pen.c
            let w = dsz.width, h = dsz.height
            let p = CGMutablePath()
            p.move(to: CGPoint(x: w * 0.12, y: 0)); p.addLine(to: CGPoint(x: w * 0.88, y: 0))
            p.addQuadCurve(to: CGPoint(x: w * 0.78, y: h - w * 0.9), control: CGPoint(x: w * 0.7, y: h * 0.4))
            p.addArc(center: CGPoint(x: w * 0.5, y: h - w * 0.5), radius: w * 0.45, startAngle: 0, endAngle: .pi, clockwise: false)
            p.addQuadCurve(to: CGPoint(x: w * 0.12, y: 0), control: CGPoint(x: w * 0.3, y: h * 0.4))
            p.closeSubpath()
            c.addPath(p); c.setFillColor(ns("FFE9A3", 0.95).cgColor); c.fillPath()
            c.addPath(p); c.setStrokeColor(ns("E2B93F", 0.7).cgColor); c.setLineWidth(1); c.strokePath()
        }
        drip.opacity = 0
        let land = CGPoint(x: tw * 0.4, y: toastH * 0.93)
        butter.position = land
        drip.position = CGPoint(x: land.x - bsz.width * 0.12, y: land.y + 2)
    }

    private static func glow(_ hex: String, _ s: CGFloat, _ a: CGFloat) -> CGImage? {
        renderImage(CGSize(width: s, height: s), screenScale) { pen in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            if let g = CGGradient(colorsSpace: space, colors: [ns(hex, a).cgColor, ns(hex, 0).cgColor] as CFArray, locations: [0, 1]) {
                pen.c.drawRadialGradient(g, startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0, endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: s / 2, options: [])
            }
        }
    }

    private static func wisp(_ s: CGSize) -> CGImage? {
        renderImage(s, screenScale) { pen in
            let c = pen.c
            let p = CGMutablePath()
            p.move(to: CGPoint(x: s.width / 2, y: s.height - 2))
            p.addCurve(to: CGPoint(x: s.width / 2, y: s.height * 0.45), control1: CGPoint(x: s.width * 0.05, y: s.height * 0.8), control2: CGPoint(x: s.width * 0.95, y: s.height * 0.62))
            p.addCurve(to: CGPoint(x: s.width / 2, y: 2), control1: CGPoint(x: s.width * 0.05, y: s.height * 0.3), control2: CGPoint(x: s.width * 0.9, y: s.height * 0.15))
            c.setLineCap(.round)
            c.addPath(p); c.setStrokeColor(ns("9FB3CC", 0.22).cgColor); c.setLineWidth(s.width * 0.42); c.strokePath()
            c.addPath(p); c.setStrokeColor(ns("8FA3BE", 0.75).cgColor); c.setLineWidth(s.width * 0.14); c.strokePath()
        }
    }

    /// A slice of toast with a bar chart seared into it.
    private static func toastImage(_ s: CGSize, bites: Int = 0) -> CGImage? {
        renderImage(s, screenScale) { pen in
            let c = pen.c
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            func slice(_ r: CGRect) -> CGPath {
                let w = r.width, h = r.height, x = r.minX, y = r.minY
                let p = CGMutablePath()
                p.move(to: CGPoint(x: x + w * 0.1, y: y + h))
                p.addLine(to: CGPoint(x: x + w * 0.9, y: y + h))
                p.addQuadCurve(to: CGPoint(x: x + w * 0.97, y: y + h * 0.9), control: CGPoint(x: x + w * 0.97, y: y + h))
                p.addLine(to: CGPoint(x: x + w * 0.95, y: y + h * 0.36))
                p.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.02), control1: CGPoint(x: x + w * 1.08, y: y + h * 0.1), control2: CGPoint(x: x + w * 0.78, y: y))
                p.addCurve(to: CGPoint(x: x + w * 0.05, y: y + h * 0.36), control1: CGPoint(x: x + w * 0.22, y: y), control2: CGPoint(x: x - w * 0.08, y: y + h * 0.1))
                p.addLine(to: CGPoint(x: x + w * 0.03, y: y + h * 0.9))
                p.addQuadCurve(to: CGPoint(x: x + w * 0.1, y: y + h), control: CGPoint(x: x + w * 0.03, y: y + h))
                p.closeSubpath()
                return p
            }
            let outer = slice(CGRect(origin: .zero, size: s).insetBy(dx: 1, dy: 1))
            c.addPath(outer); c.setFillColor(ns("A8621F").cgColor); c.fillPath()
            let inner = slice(CGRect(origin: .zero, size: s).insetBy(dx: s.width * 0.085, dy: s.height * 0.08).offsetBy(dx: 0, dy: s.height * 0.02))
            c.saveGState(); c.addPath(inner); c.clip()
            if let g = CGGradient(colorsSpace: space, colors: [ns("FBE2A6").cgColor, ns("F0BC6A").cgColor, ns("D48A39").cgColor] as CFArray, locations: [0, 0.55, 1]) {
                let ctr = CGPoint(x: s.width / 2, y: s.height * 0.55)
                c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: s.width * 0.62, options: [])
            }
            // the graph, branded in
            let chart = CGRect(x: s.width * 0.22, y: s.height * 0.3, width: s.width * 0.56, height: s.height * 0.36)
            let bars: [CGFloat] = [0.32, 0.58, 0.9, 0.66]
            let gap = chart.width / CGFloat(bars.count)
            c.setFillColor(ns("7A4012", 0.82).cgColor)
            c.setStrokeColor(ns("6A350C", 0.9).cgColor)
            c.setLineWidth(1.4)
            for (i, b) in bars.enumerated() {
                let bh = chart.height * b, bx = chart.minX + gap * CGFloat(i) + gap * 0.18
                c.fill(CGRect(x: bx, y: chart.maxY - bh, width: gap * 0.64, height: bh))
                let mid = bx + gap * 0.32, top = chart.maxY - bh
                c.strokeLineSegments(between: [CGPoint(x: mid, y: top - chart.height * 0.08), CGPoint(x: mid, y: top),
                                               CGPoint(x: mid - 3, y: top - chart.height * 0.08), CGPoint(x: mid + 3, y: top - chart.height * 0.08)])
            }
            c.strokeLineSegments(between: [CGPoint(x: chart.minX - 2, y: chart.maxY + 1), CGPoint(x: chart.maxX + 2, y: chart.maxY + 1)])
            c.restoreGState()
            // a little shine on the crust
            c.addPath(outer); c.setStrokeColor(ns("FFE3B0", 0.35).cgColor); c.setLineWidth(1.2); c.strokePath()
            // bites out of the top right, each a scallop of three teeth marks
            if bites > 0 {
                c.setBlendMode(.clear)
                for b in 0..<bites {
                    let cx = s.width * (0.88 - 0.24 * CGFloat(b)), cy = s.height * (0.03 + 0.05 * CGFloat(b))
                    let r = s.width * 0.12
                    for (dx, dy) in [(-0.95, 0.25), (0, 0), (0.95, 0.3)] as [(CGFloat, CGFloat)] {
                        c.fillEllipse(in: CGRect(x: cx + dx * r * 0.85 - r, y: cy + dy * r - r, width: 2 * r, height: 2 * r))
                    }
                }
                c.setBlendMode(.normal)
            }
        }
    }

    /// The files that fall in: Excel sheets, qTOWER exports and saved data.
    private static func fileImage(_ kind: Int, _ s: CGSize) -> CGImage? {
        renderImage(s, screenScale) { pen in
            let c = pen.c
            let w = s.width, h = s.height, fold = w * 0.3
            let doc = CGMutablePath()
            doc.move(to: CGPoint(x: 2, y: 2)); doc.addLine(to: CGPoint(x: w - fold, y: 2)); doc.addLine(to: CGPoint(x: w - 2, y: fold))
            doc.addLine(to: CGPoint(x: w - 2, y: h - 2)); doc.addLine(to: CGPoint(x: 2, y: h - 2)); doc.closeSubpath()
            let paper = kind == 2 ? ns("1E4A83") : NSColor.white
            c.addPath(doc); c.setFillColor(paper.cgColor); c.fillPath()
            c.addPath(doc); c.setStrokeColor((kind == 2 ? ns("0E2A50") : ns("8A99AF")).cgColor); c.setLineWidth(1.2); c.strokePath()
            let corner = CGMutablePath()
            corner.move(to: CGPoint(x: w - fold, y: 2)); corner.addLine(to: CGPoint(x: w - fold, y: fold)); corner.addLine(to: CGPoint(x: w - 2, y: fold)); corner.closeSubpath()
            c.addPath(corner); c.setFillColor((kind == 2 ? ns("4A78B8") : ns("D5DEEB")).cgColor); c.fillPath()
            switch kind {
            case 0:     // an Excel sheet: the green badge with its X, and a grid
                c.setStrokeColor(ns("1D6F42", 0.35).cgColor); c.setLineWidth(1)
                for i in 0..<4 { let y = h * 0.42 + CGFloat(i) * h * 0.13; c.strokeLineSegments(between: [CGPoint(x: w * 0.42, y: y), CGPoint(x: w - 6, y: y)]) }
                let badge = CGRect(x: 0, y: h * 0.36, width: w * 0.56, height: h * 0.4)
                c.addPath(CGPath(roundedRect: badge, cornerWidth: 3, cornerHeight: 3, transform: nil)); c.setFillColor(ns("1D6F42").cgColor); c.fillPath()
                label("X", NSFont.systemFont(ofSize: h * 0.3, weight: .heavy), .white, at: CGPoint(x: badge.midX, y: badge.minY + badge.height * 0.08), center: true)
            case 1:     // a qTOWER export: amplification curves
                let cols = ["2FA84F", "E2483D", "2F6FE0"]
                for (k, col) in cols.enumerated() {
                    c.beginPath()
                    var x: CGFloat = 5
                    while x <= w - 5 {
                        let u = Double((x - 5) / (w - 10))
                        let y = h * 0.78 - h * 0.42 / CGFloat(1 + exp(-(u - 0.4 - 0.12 * Double(k)) * 12))
                        if x == 5 { c.move(to: CGPoint(x: x, y: y)) } else { c.addLine(to: CGPoint(x: x, y: y)) }
                        x += 1
                    }
                    c.setStrokeColor(ns(col).cgColor); c.setLineWidth(1.6); c.strokePath()
                }
                c.addPath(CGPath(roundedRect: CGRect(x: 3, y: h * 0.82, width: w * 0.52, height: h * 0.14), cornerWidth: 2, cornerHeight: 2, transform: nil))
                c.setFillColor(ns("1D6F42").cgColor); c.fillPath()
                label("xls", NSFont.systemFont(ofSize: h * 0.11, weight: .bold), .white, at: CGPoint(x: 3 + w * 0.26, y: h * 0.818), center: true)
            default:    // saved .qpcrdata: a little plate
                c.setFillColor(NSColor(white: 1, alpha: 0.9).cgColor)
                for r in 0..<3 { for k in 0..<4 {
                    let p = CGPoint(x: w * 0.2 + CGFloat(k) * w * 0.17, y: h * 0.42 + CGFloat(r) * h * 0.13)
                    c.fillEllipse(in: CGRect(x: p.x - 2.2, y: p.y - 2.2, width: 4.4, height: 4.4))
                } }
                label("qPCR", NSFont.systemFont(ofSize: h * 0.12, weight: .heavy), .white, at: CGPoint(x: w / 2, y: h * 0.8), center: true)
            }
        }
    }

    private func buildSprites() {
        sprites.forEach { $0.layer.removeFromSuperlayer() }
        rings.forEach { $0.removeFromSuperlayer() }
        let scale = bw / 400
        let size = CGSize(width: 46 * scale, height: 56 * scale)
        let imgs = (0..<3).map { Self.fileImage($0, size) }
        let ring = renderImage(CGSize(width: 60, height: 60), screenScale) { pen in
            pen.c.setStrokeColor(ns("3DBF6A", 0.9).cgColor); pen.c.setLineWidth(2.5)
            pen.c.strokeEllipse(in: CGRect(x: 4, y: 4, width: 52, height: 52))
        }
        sprites = (0..<fileCount).map { i in
            let l = CALayer()
            l.bounds = CGRect(origin: .zero, size: size)
            l.contents = imgs[[0, 1, 0, 2, 0, 1, 0, 1, 2, 0, 1, 0, 0, 1, 2, 0][i % 16]]
            l.opacity = 0
            stage.addSublayer(l)
            // into the open lid: aim across the block
            let target = onOpening(0.15 + 0.7 * CGFloat(hash01(i, 401)), 0.3 + 0.5 * CGFloat(hash01(i, 402)))
            let from: CGPoint
            if i % 2 == 0 {
                // thrown in from the left, where the files are dropped
                from = CGPoint(x: -size.width, y: H * (0.18 + 0.4 * CGFloat(hash01(i, 403))))
            } else {
                // sprinkled down from above
                from = CGPoint(x: target.x + (CGFloat(hash01(i, 405)) - 0.5) * bw * 0.9, y: -size.height)
            }
            // an arc that tops out above the lid
            let peak = min(from.y, hingeY - lidLen - size.height) - H * 0.06 * CGFloat(hash01(i, 406))
            let via = CGPoint(x: (from.x + target.x) / 2, y: i % 2 == 0 ? peak : (from.y + target.y) / 2)
            return (l, up(from), up(via), up(target), CGFloat(hash01(i, 404) - 0.5) * 9)
        }
        rings = (0..<fileCount).map { i in
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: 60, height: 60)
            l.contents = ring
            l.position = sprites[i].to
            l.opacity = 0
            stage.addSublayer(l)
            return l
        }
        stage.addSublayer(bubble)
        steam.forEach { stage.addSublayer($0) }
    }

    // MARK: the lid

    /// The lid's outline when opened `angle` degrees about the hinge at the back of the top face.
    private func lidPoints(_ angle: Double, grow: CGFloat = 4, shrink: CGFloat = 0) -> (quad: [CGPoint], edge: [CGPoint]) {
        let th = angle * .pi / 180
        let L = Double(lidLen)
        let k = Double(depth) / L                      // depth on screen for a lid lying flat
        let z = L * cos(th), h = L * sin(th)
        let y = Double(hingeY) + z * k - h
        let f = CGFloat(1 - z / L)
        let lift = CGFloat(z / L) * grow
        let xl = x0 + skew * f - lift + shrink, xr = x0 + bw - skew * f + lift - shrink
        let hl = x0 + skew - grow * 0.4 + shrink, hr = x0 + bw - skew + grow * 0.4 - shrink
        let fy = CGFloat(y) + (shrink > 0 ? shrink * CGFloat(cos(th)) : 0)
        let hy = hingeY - (shrink > 0 ? shrink * 0.6 : 0)
        let quad = [CGPoint(x: hl, y: hy), CGPoint(x: hr, y: hy), CGPoint(x: xr, y: fy), CGPoint(x: xl, y: fy)]
        let thick = CGFloat(12 * cos(th) * Double(bw / 400))
        let edge = [CGPoint(x: xl, y: fy), CGPoint(x: xr, y: fy), CGPoint(x: xr, y: fy + max(0, thick)), CGPoint(x: xl, y: fy + max(0, thick))]
        return (quad, edge)
    }

    private func path(_ pts: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: pts.map { CGPoint(x: $0.x - mrUp.minX, y: H - $0.y - mrUp.minY) })
        p.closeSubpath()
        return p
    }

    private func setLid(_ angle: Double) {
        guard abs(angle - last.angle) > 0.05 else { return }
        last.angle = angle
        let pts = lidPoints(angle)
        lid.path = path(pts.quad)
        lidEdge.path = path(pts.edge)
        // the dark top while it lies shut, the pale heated underside as it stands open
        let u = CGFloat(clamp01((angle - 70) / 30))
        let top = ns("2E3747"), under = ns("D3DCE8")
        lid.fillColor = (top.blended(withFraction: u, of: under) ?? top).cgColor
        // the heated pad inside the lid: the same outline, drawn in a little from every side
        let q = pts.quad
        let cx = q.map { $0.x }.reduce(0, +) / 4, cy = q.map { $0.y }.reduce(0, +) / 4
        lidPad.path = u > 0.05 ? path(q.map { CGPoint(x: cx + ($0.x - cx) * 0.84, y: cy + ($0.y - cy) * 0.8) }) : nil
        lidPad.opacity = Float(u)
        lidEdge.opacity = Float(clamp01(1 - (angle - 60) / 30))
    }

    // MARK: every frame

    func tick(_ dt: Double) {
        guard built != .zero else { return }
        clock += dt
        frame_ += 1
        if gulpActive { showGulp(clock - gulpAt); return }
        if eager { show(clock); return }
        if clock >= loopEnd {
            clock = 0
            bites = 0; biteAt = -10; pokeAt = -10
        }
        show(clock)
    }

    private func set(_ l: CALayer, _ o: Double) { let f = Float(max(0, min(1, o))); if abs(l.opacity - f) > 0.004 { l.opacity = f } }

    private func text(_ t: CATextLayer, _ s: String, _ key: inout String) {
        guard s != key else { return }
        key = s
        t.string = s
    }

    private func show(_ t: Double) {
        guard built != .zero else { return }
        let scale = bw / 400
        let pk = t - pokeAt           // seconds since the qTOWER was poked
        // --- the lid
        var angle = openAngle
        if eager {
            angle = 118 + 4 * sin(t * 9)
        } else if t < closeAt {
            angle = openAngle
        } else if t < slamAt {
            let u = (t - closeAt) / (slamAt - closeAt)
            angle = openAngle * (1 - u * u)
        } else if t < slamAt + 0.4 {
            let u = (t - slamAt) / 0.4
            angle = 7 * sin(.pi * u) * (1 - u)
        } else if t < dingAt {
            angle = 0
        } else if t < dingAt + 0.55 {
            let u = (t - dingAt) / 0.55
            angle = openAngle * easeOutBack(u)
        } else {
            angle = openAngle
        }
        if pk >= 0 && pk < 0.5 && angle > 60 { angle += 12 * sin(.pi * pk / 0.5) }    // a startled flap
        setLid(angle)

        // --- the whole machine: squash on the slam, hum while cycling, hop at the ding, bounce when eager
        var sx: CGFloat = 1, sy: CGFloat = 1, dx: CGFloat = 0, dy: CGFloat = 0
        if eager {
            dy = -CGFloat(abs(sin(t * 7))) * 7 * scale
            sy = 1 + 0.025 * CGFloat(sin(t * 14))
        } else {
            let d = t - slamAt
            if d >= 0 && d < 0.6 {
                let k = CGFloat(exp(-d * 7) * cos(d * 30))
                sy = 1 - 0.06 * k; sx = 1 + 0.04 * k
            }
            if t > cycleFrom && t < dingAt { dx = CGFloat(hash01(frame_, 9) - 0.5) * 1.6 * scale; dy = CGFloat(hash01(frame_, 10) - 0.5) * 0.8 * scale }
            let h = t - dingAt
            if h >= 0 && h < 0.45 { dy = -CGFloat(sin(.pi * h / 0.45)) * 10 * scale; sy = 1 + 0.03 * CGFloat(sin(.pi * h / 0.45)) }
        }
        if pk >= 0 && pk < 0.6 {
            dy -= CGFloat(sin(.pi * pk / 0.6)) * 16 * scale
            let q = CGFloat(sin(.pi * min(1, pk / 0.3))) * 0.05
            sx += q; sy -= q
        }
        let mt = CGAffineTransform(translationX: dx, y: -dy).scaledBy(x: sx, y: sy)
        if machine.affineTransform() != mt { machine.setAffineTransform(mt) }

        // --- files tumbling in
        var landed = 0, flash = 0.0
        for (i, s) in sprites.enumerated() {
            let start = filesAt + Double(i) * fileGap
            let u = eager ? -1 : (t - start) / fileFall
            if u < 0 || u > 1.2 {
                set(s.layer, 0); set(rings[i], 0)
                if u > 1.2 { landed += 1 }
                continue
            }
            if u <= 1 {
                // along a curve through `via`, speeding up as it falls, fluttering like paper
                let p = CGFloat(0.55 * u + 0.45 * u * u), q = 1 - p
                let x = q * q * s.from.x + 2 * q * p * s.via.x + p * p * s.to.x
                let y = q * q * s.from.y + 2 * q * p * s.via.y + p * p * s.to.y
                s.layer.position = CGPoint(x: x, y: y)
                let shrink = u > 0.8 ? 1 - (u - 0.8) / 0.2 * 0.7 : 1
                let flutter = 0.28 * CGFloat(sin(u * 11 + Double(i)))
                s.layer.setAffineTransform(CGAffineTransform(rotationAngle: s.spin * (1 - p) + flutter * (1 - p)).scaledBy(x: CGFloat(shrink), y: CGFloat(shrink)))
                set(s.layer, u > 0.9 ? (1 - u) * 10 : 1)
                set(rings[i], 0)
            } else {
                landed += 1
                set(s.layer, 0)
                let r = (u - 1) / 0.2
                rings[i].setAffineTransform(CGAffineTransform(scaleX: CGFloat(0.3 + 1.2 * r) * scale, y: CGFloat(0.15 + 0.6 * r) * scale))
                set(rings[i], 1 - r)
                flash = max(flash, 1 - r)
            }
        }

        // --- glows
        let cycling = !eager && t >= cycleFrom && t < dingAt
        let done = !eager && t >= dingAt
        set(blockGlow, eager ? 0.35 + 0.25 * sin(t * 9) : flash * 0.9 + (angle > 60 && !done ? 0.12 : 0))
        var hot = 0.0
        if cycling { hot = (0.45 + 0.35 * (0.5 + 0.5 * sin(t * 7))) * clamp01((t - cycleFrom) / 0.8) }
        if done { hot = 0.7 * max(0.25, 1 - (t - dingAt) / 3) }
        set(heat, hot)
        for (i, l) in shimmer.enumerated() {
            let p = ((t * 0.8 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1))
            let x = x0 + bw * (0.3 + 0.2 * CGFloat(i))
            l.position = up(CGPoint(x: x + CGFloat(sin(t * 3 + Double(i))) * 4, y: hingeY - 10 - CGFloat(p) * 50 * scale))
            set(l, cycling ? sin(.pi * p) * 0.55 : 0)
        }

        // --- the status light
        var ledHex = "8CF5A4", ledLevel = 0.6 + 0.4 * sin(t * 2.4)
        if eager { ledHex = "6FB4FF"; ledLevel = 0.5 + 0.5 * sin(t * 14) }
        else if t >= filesAt && t < closeAt { ledHex = "6FB4FF"; ledLevel = flash > 0.2 ? 1 : 0.55 }
        else if t >= closeAt && t < dingAt { ledHex = "FFB547"; ledLevel = 0.55 + 0.45 * sin(t * 8) }
        else if done { ledHex = "8CF5A4"; ledLevel = 1 }
        if pk >= 0 && pk < 0.5 { ledHex = "FFFFFF"; ledLevel = 1 }
        if ledHex != last.led {
            last.led = ledHex
            led.backgroundColor = ns(ledHex).cgColor
            ledGlow.contents = ledGlowImage(ledHex)
        }
        set(ledGlow, ledLevel * 0.9)

        // --- the screen (a drop writes its own words)
        var top = "READY", sub = "Lid open · waiting" + (Int(t * 2) % 2 == 0 ? " ▍" : ""), bar = 0.0
        if eager { top = "FEED ME!"; sub = "Drop them on me" }
        else if t >= filesAt && t < closeAt { top = "RECEIVING"; sub = "\(landed) file\(landed == 1 ? "" : "s") in" }
        else if t >= closeAt && t < slamAt { top = "CLOSING"; sub = "Mind your fingers" }
        else if t >= slamAt && t < cycleFrom { top = "LID CLOSED"; sub = "Heating lid…" }
        else if cycling {
            let cyc = min(40, 1 + Int((t - cycleFrom) / (dingAt - cycleFrom) * 40))
            let temp = 77.5 + 17.5 * cos((t - cycleFrom) * 2 * .pi / 0.9)
            top = "CYCLE \(cyc)/40"
            sub = String(format: "%.1f °C", temp)
            bar = (t - cycleFrom) / (dingAt - cycleFrom)
        } else if done { top = "DONE ✓"; sub = "40 cycles · baked"; bar = 1 }
        if pk >= 0 && pk < 1.2 && !eager { top = "HEY! :)"; sub = "That tickles" }
        if !gulpActive {
            text(screenTop, top, &last.top)
            text(screenSub, sub, &last.sub)
            let barW = CGFloat(bar) * (screenRect().width - 18)
            if abs(screenBar.bounds.width - barW) > 0.3 { screenBar.bounds.size.width = barW }
            set(screenBar, barW > 1 ? 1 : 0)
        }

        // --- the toast
        var rise = 0.0, wobble = 0.0
        if done {
            let u = t - dingAt - 0.15
            if u > 0 {
                rise = 1 - exp(-u * 6) * cos(u * 11)                // a springy pop
                wobble = exp(-u * 5) * sin(u * 13) * 0.08
            }
            if t > sinkAt { rise *= max(0, 1 - easeInOut((t - sinkAt) / 0.6)) }
        }
        let peek = toastH * 0.8
        let ty = slotY + toastH / 2 + 6 - CGFloat(rise) * (peek + 6)
        let tp = up(CGPoint(x: W / 2, y: ty))
        if abs(toast.position.y - tp.y) > 0.2 { toast.position = tp }
        let tt = CGAffineTransform(rotationAngle: CGFloat(wobble))
        if toast.affineTransform() != tt { toast.setAffineTransform(tt) }
        for (i, l) in steam.enumerated() {
            let p = ((t * 0.55 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1))
            let sx0 = W / 2 + (CGFloat(i) - 1.5) * toastH * 0.2
            l.position = up(CGPoint(x: sx0 + CGFloat(sin(t * 2 + Double(i))) * 5, y: ty - toastH / 2 - 18 * scale - CGFloat(p) * 46 * scale))
            set(l, done && t > dingAt + 0.6 && t < sinkAt + 0.3 ? sin(.pi * p) * 0.8 * rise : 0)
        }

        if bites != shownBites, bites < toastImages.count {
            shownBites = bites
            toast.contents = toastImages[bites]
        }

        // --- the hologram: the run drawn in light over the closed lid, curves and Cts as the cycles go by
        if !holo.isHidden {
            var hs = 0.0, ho = 0.0
            if cycling {
                let a = (t - cycleFrom - 0.1) / 0.45
                hs = a <= 0 ? 0 : easeOutBack(min(1, a))
                ho = clamp01(a * 2)
                let out = (t - (dingAt - 0.4)) / 0.4
                if out > 0 { hs *= max(0.02, 1 - easeInOut(out)); ho *= max(0, 1 - out) }     // sucked back into the lid
                ho *= 0.9 + 0.1 * hash01(frame_, 21)                                          // a holographic flicker
            }
            set(holo, ho)
            set(holoBeam, ho * 0.9)
            let ht = CGAffineTransform(scaleX: CGFloat(0.6 + 0.4 * min(1, hs)), y: CGFloat(max(0.01, hs)))
            if holo.affineTransform() != ht { holo.setAffineTransform(ht) }
            let span = dingAt - cycleFrom - 0.7
            let prog = cycling ? clamp01((t - cycleFrom - 0.3) / span) : 0
            let rw = holoPlot.width * CGFloat(prog)
            if abs(holoReveal.bounds.width - rw) > 0.3 { holoReveal.bounds.size.width = rw }
            holoCursor.position = CGPoint(x: holoPlot.minX + rw, y: holoPlot.midY)
            set(holoCursor, prog > 0 && prog < 1 ? 1 : 0)
            for (k, d) in ctDots.enumerated() {
                let since = (prog - ctAt[k]) * span
                set(d, cycling && since >= 0 ? 1 : 0)
                let pop = since >= 0 && since < 0.4 ? CGFloat(1 + 0.9 * (1 - since / 0.4)) : 1
                let dtf = CGAffineTransform(scaleX: pop, y: pop)
                if d.affineTransform() != dtf { d.setAffineTransform(dtf) }
            }
        }

        // --- the reading light sweeping the lid seam, a new dye each pass
        if cycling && t > cycleFrom + 0.3 {
            let sweep = (t - cycleFrom - 0.3) / 0.7
            let k = Int(sweep) % 4
            if k != shownScan, k < scanImages.count { shownScan = k; scan.contents = scanImages[k] }
            let f = sweep - floor(sweep)
            scan.position = up(CGPoint(x: x0 + 16 + (bw - 32) * CGFloat(f), y: topY + 4 * scale))
            set(scan, sin(.pi * f))
        } else {
            set(scan, 0)
        }

        // --- crumbs: a burst as the toast pops, and one at every bite
        let popAt = dingAt + 0.25
        let slotTop = up(CGPoint(x: W / 2, y: slotY - peek))      // the crust, where the toast comes to rest
        for (i, l) in crumbs.enumerated() {
            let fromBite = i >= 8
            let tau = t - (fromBite ? biteAt : popAt)
            guard tau >= 0 && tau < 1.1 && (fromBite || done) else { set(l, 0); continue }
            let origin = fromBite ? biteFrom : slotTop
            let vx = (hash01(i, 511) - 0.5) * 240 * Double(scale)
            let vy = (110 + 170 * hash01(i, 512)) * Double(scale)
            l.position = CGPoint(x: origin.x + CGFloat(vx * tau), y: origin.y + CGFloat(vy * tau - 0.5 * 560 * Double(scale) * tau * tau))
            l.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(tau * 9 * (hash01(i, 513) - 0.5))))
            set(l, 1 - tau / 1.1)
        }

        // --- sparkles round the fresh toast
        for (i, l) in sparkles.enumerated() {
            guard done && t > dingAt + 0.5 && t < sinkAt else { set(l, 0); continue }
            let ph = (t * 1.2 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
            let ang = Double(i) / 6 * 2 * .pi + t * 0.35
            let p = up(CGPoint(x: W / 2 + CGFloat(cos(ang)) * toastH * 0.66, y: ty - toastH * 0.1 + CGFloat(sin(ang)) * toastH * 0.5))
            l.position = p
            let sp = CGFloat(sin(.pi * ph))
            l.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(ph * 2)).scaledBy(x: 0.4 + 0.8 * sp, y: 0.4 + 0.8 * sp))
            set(l, Double(sp) * min(1, (t - dingAt - 0.5) * 3))
        }

        // --- butter: drops onto the crust, squashes, then melts down the slice
        let landAt = dingAt + 1.1, fallT = 0.45
        if done && t > landAt - fallT && t < sinkAt + 0.6 {
            let land = CGPoint(x: toast.bounds.width * 0.4, y: toastH * 0.93)
            var y = land.y, bx: CGFloat = 1, by: CGFloat = 1
            if t < landAt {
                let u = (t - (landAt - fallT)) / fallT
                y = land.y + toastH * 1.4 * CGFloat(1 - u * u)
            } else {
                let d = t - landAt
                let k = CGFloat(exp(-d * 9) * cos(d * 26))
                by = 1 - 0.35 * k; bx = 1 + 0.25 * k
                let melt = CGFloat(clamp01((t - landAt - 0.5) / 1.6))
                by *= 1 - 0.45 * melt; bx *= 1 + 0.3 * melt
            }
            butter.position = CGPoint(x: land.x, y: y)
            butter.setAffineTransform(CGAffineTransform(scaleX: bx, y: by))
            set(butter, 1)
            let melt = clamp01((t - landAt - 0.6) / 1.8)
            drip.setAffineTransform(CGAffineTransform(scaleX: 1, y: CGFloat(max(0.01, melt))))
            set(drip, melt > 0 ? 0.95 : 0)
        } else {
            set(butter, 0); set(drip, 0)
        }

        // --- "Ding!"
        if done && t < sinkAt + 0.4 {
            let u = t - dingAt
            let s = u < 0.35 ? CGFloat(easeOutBack(u / 0.35)) : 1
            bubble.setAffineTransform(CGAffineTransform(scaleX: max(0.01, s), y: max(0.01, s)))
            set(bubble, t > sinkAt ? 1 - (t - sinkAt) / 0.4 : min(1, u * 5))
        } else {
            set(bubble, 0)
        }

        // --- the headline
        var head = "The qTOWER is waiting, lid open.", line = "Drop your qTOWER files right onto it, or press Open."
        if eager { head = "Ooh, files! Drop them in."; line = "Let go and they go straight into the block." }
        else if t >= filesAt && t < closeAt { head = "Files incoming!"; line = "Excel sheets and qTOWER exports, straight into the block." }
        else if t >= closeAt && t < cycleFrom { head = "Lid down!"; line = "Everything's in. Here we go." }
        else if t >= cycleFrom && t < dingAt { head = "Cycling…"; line = "40 rounds of 95 °C and 60 °C. Something smells good." }
        else if done {
            head = bites >= 3 ? "Mmm. Graphs taste better warm." : "Ding! Graphs baked."
            line = bites >= 3 ? "Every last crumb. Your real graphs are safe on the left." : "Fresh out of the qTOWER, golden brown. Go on, click the toast."
        }
        if head == "The qTOWER is waiting, lid open." { line += " (Psst: poke it.)" }
        if !gulpActive && head + line != last.head {
            last.head = head + line
            headline.string = head
            subline.string = line
        }
    }

    // MARK: a real drop

    /// Swallows the dropped files: they fall from where they were let go into the open lid, the lid
    /// slams, and `onDone` is called so they can be imported.
    func startGulp(_ g: Gulp, onDone: @escaping (UUID) -> Void) {
        guard g.id != gulpID else { return }
        gulpID = g.id
        guard built != .zero else { onDone(g.id); return }
        gulpDone = onDone
        gulpActive = true
        gulpReported = false
        gulpAt = clock
        gulpTotal = g.urls.count
        let scale = bw / 400
        // from the pointer if it is over the panel (a drop, or the Open button), else from the top left
        var origin = CGPoint(x: W * 0.16, y: -30)
        if let w = window {
            let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
            if bounds.contains(p) { origin = CGPoint(x: p.x, y: H - p.y) }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        gulpSprites.forEach { $0.layer.removeFromSuperlayer() }
        let size = CGSize(width: 46 * scale, height: 56 * scale)
        gulpSprites = g.names.prefix(8).enumerated().map { i, name in
            let ext = (name as NSString).pathExtension.lowercased()
            let kind = ext == "qpcrdata" ? 2 : (ext == "xls" ? 1 : 0)
            let label = g.names.count > 8 && i == 7 ? "+\(g.names.count - 7) more" : name
            let (img, sz) = Self.namedFile(kind, label, size)
            let l = CALayer()
            l.bounds = CGRect(origin: .zero, size: sz)
            l.contents = img
            l.opacity = 0
            stage.addSublayer(l)
            let from = CGPoint(x: origin.x + CGFloat(i % 3 - 1) * 14 * scale, y: origin.y - CGFloat(i / 3) * 10 * scale)
            let to = onOpening(0.2 + 0.6 * CGFloat(hash01(i, 601)), 0.35 + 0.4 * CGFloat(hash01(i, 602)))
            let via = CGPoint(x: (from.x + to.x) / 2, y: min(from.y, to.y) - H * 0.16)
            return (l, up(from), up(via), up(to), CGFloat(hash01(i, 603) - 0.5) * 6)
        }
        for (i, r) in rings.enumerated() where i < gulpSprites.count { r.position = gulpSprites[i].to }
        CATransaction.commit()
        if !ambientActive { showGulp(0) }
    }

    /// A file icon with its name beneath.
    private static func namedFile(_ kind: Int, _ name: String, _ size: CGSize) -> (CGImage?, CGSize) {
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        var text = name
        if text.count > 22 { text = String(text.prefix(10)) + "…" + String(text.suffix(9)) }
        let tw = (text as NSString).size(withAttributes: [.font: font]).width + 14
        let total = CGSize(width: max(size.width, tw), height: size.height + 20)
        let icon = fileImage(kind, size)
        let img = renderImage(total, screenScale) { pen in
            let c = pen.c
            if let icon = icon {
                c.saveGState()
                c.translateBy(x: (total.width - size.width) / 2, y: size.height)
                c.scaleBy(x: 1, y: -1)
                c.draw(icon, in: CGRect(origin: .zero, size: size))
                c.restoreGState()
            }
            let pill = CGRect(x: (total.width - tw) / 2, y: size.height + 3, width: tw, height: 16)
            c.addPath(CGPath(roundedRect: pill, cornerWidth: 8, cornerHeight: 8, transform: nil))
            c.setFillColor(ns("1E4A83").cgColor); c.fillPath()
            label(text, font, .white, at: CGPoint(x: pill.midX, y: pill.minY + 1.5), center: true)
        }
        return (img, total)
    }

    private func showGulp(_ g: Double) {
        guard built != .zero else { return }
        show(0.5)        // the waiting scene underneath: toast, hologram and the loop's own files out of sight
        let scale = bw / 400
        let n = gulpSprites.count
        let fall = 0.75, gap = 0.08
        let fallEnd = gap * Double(max(0, n - 1)) + fall
        let slamStart = fallEnd + 0.08, slamEnd = slamStart + 0.28
        // the lid: wide open for the files, then slammed
        var angle = 118.0
        if g > slamStart { let u = min(1, (g - slamStart) / (slamEnd - slamStart)); angle = 118 * (1 - u * u) }
        if g > slamEnd { let u = (g - slamEnd) / 0.35; angle = u < 1 ? 6 * sin(.pi * u) * (1 - u) : 0 }
        setLid(angle)
        var sx: CGFloat = 1, sy: CGFloat = 1, dy: CGFloat = 0
        if g < slamStart { dy = -CGFloat(abs(sin(g * 10))) * 5 * scale }
        let d = g - slamEnd
        if d >= 0 && d < 0.6 { let k = CGFloat(exp(-d * 7) * cos(d * 30)); sy = 1 - 0.07 * k; sx = 1 + 0.05 * k }
        let mt = CGAffineTransform(translationX: 0, y: -dy).scaledBy(x: sx, y: sy)
        if machine.affineTransform() != mt { machine.setAffineTransform(mt) }
        // the files, each to the block
        var landed = 0, flash = 0.0
        for (i, s) in gulpSprites.enumerated() {
            let u = (g - gap * Double(i)) / fall
            if u < 0 { set(s.layer, 0); continue }
            if u <= 1 {
                let p = CGFloat(0.5 * u + 0.5 * u * u), q = 1 - p
                s.layer.position = CGPoint(x: q * q * s.from.x + 2 * q * p * s.via.x + p * p * s.to.x,
                                           y: q * q * s.from.y + 2 * q * p * s.via.y + p * p * s.to.y)
                let shrink = u > 0.78 ? 1 - (u - 0.78) / 0.22 * 0.75 : 1
                s.layer.setAffineTransform(CGAffineTransform(rotationAngle: s.spin * (1 - p) + 0.25 * CGFloat(sin(u * 10 + Double(i))) * (1 - p))
                    .scaledBy(x: CGFloat(shrink), y: CGFloat(shrink)))
                set(s.layer, u > 0.9 ? (1 - u) * 10 : 1)
            } else {
                landed += 1
                set(s.layer, 0)
                if i < rings.count {
                    let r = min(1, (u - 1) / 0.25)
                    rings[i].setAffineTransform(CGAffineTransform(scaleX: CGFloat(0.3 + 1.2 * r) * scale, y: CGFloat(0.15 + 0.6 * r) * scale))
                    set(rings[i], 1 - r)
                    flash = max(flash, 1 - r)
                }
            }
        }
        set(blockGlow, flash * 0.95 + (angle > 60 ? 0.2 : 0))
        set(heat, d > 0 ? 0.45 * min(1, d / 0.3) : 0)
        // the screen, the light and the headline
        let all = landed >= n
        let top = d > 0 ? "GOT IT!" : (all ? "ALL IN" : "RECEIVING")
        let sub = d > 0 ? "Reading \(gulpTotal) file\(gulpTotal == 1 ? "" : "s")…" : "\(min(gulpTotal, landed)) of \(gulpTotal) in"
        text(screenTop, top, &last.top)
        text(screenSub, sub, &last.sub)
        set(screenBar, 0)
        let ledHex = d > 0 ? "FFB547" : "6FB4FF"
        if ledHex != last.led { last.led = ledHex; led.backgroundColor = ns(ledHex).cgColor; ledGlow.contents = ledGlowImage(ledHex) }
        set(ledGlow, flash > 0.2 || d > 0 ? 1 : 0.6)
        let head = d > 0 ? "Got them! Reading your run…" : "Mmm, files!"
        let line = d > 0 ? "Your graphs are on their way." : "Straight into the block."
        if head + line != last.head { last.head = head + line; headline.string = head; subline.string = line }
        // done: hand them over for import
        if g >= slamEnd + 0.3 && !gulpReported {
            gulpReported = true
            let id = gulpID, done = gulpDone
            DispatchQueue.main.async { if let id = id { done?(id) } }
        }
        // if the files turn out to hold nothing, the qTOWER goes back to waiting
        if g >= slamEnd + 1.2 {
            gulpActive = false
            gulpSprites.forEach { $0.layer.removeFromSuperlayer() }
            gulpSprites = []
            clock = 0.4
            last = ("", "", "", -1, "")
        }
    }

    // MARK: clicks

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Click the toast while it stands out of the block to take a bite; click the qTOWER to poke it.
    override func mouseDown(with event: NSEvent) {
        guard built != .zero, ambientActive, !eager else { return }
        let p = convert(event.locationInWindow, from: nil)        // y up, the same space as the layers
        if clock >= dingAt + 0.4 && clock < sinkAt && bites < 3 {
            let f = toast.convert(toast.bounds, to: stage)
            if f.insetBy(dx: -6, dy: -6).contains(p) {
                bites += 1
                biteAt = clock
                biteFrom = CGPoint(x: f.minX + f.width * (0.88 - 0.24 * CGFloat(bites - 1)), y: f.maxY - f.height * 0.06)
                return
            }
        }
        if mrUp.contains(p) { pokeAt = clock }
    }

    override func resetCursorRects() {
        if built != .zero { addCursorRect(mrUp, cursor: .pointingHand) }
    }

    private var glowCache: [String: CGImage] = [:]
    private func ledGlowImage(_ hex: String) -> CGImage? {
        if let g = glowCache[hex] { return g }
        let g = Self.glow(hex, 30 * bw / 400, 0.9)
        glowCache[hex] = g
        return g
    }

    var loopLength: Double { loopEnd }
    /// Development snapshots: files dropped `ago` seconds before.
    func previewGulp(_ names: [String], ago: Double) {
        let g = Gulp(urls: names.map { URL(fileURLWithPath: "/tmp/" + $0) })
        clock = 1
        startGulp(g, onDone: { _ in })
        CATransaction.begin(); CATransaction.setDisableActions(true)
        last = ("", "", "", -1, "")
        clock = 1 + ago
        showGulp(ago)
        CATransaction.commit()
    }
    /// Development snapshots: a bitten toast, or a poke a moment ago.
    func previewTweaks(bites b: Int, pokedAgo: Double?) {
        bites = b
        if let p = pokedAgo { pokeAt = clock - p }
    }

    /// The panel `seconds` into its loop (development snapshots).
    func preview(at seconds: Double) {
        layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        last = ("", "", "", -1, "")
        clock = seconds
        frame_ = Int(seconds * 20)
        show(seconds)
        CATransaction.commit()
    }

    /// While paused: the qTOWER waiting with its lid open.
    private func rest() {
        guard built != .zero else { return }
        if gulpActive {
            gulpActive = false
            gulpSprites.forEach { $0.layer.removeFromSuperlayer() }
            gulpSprites = []
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        last = ("", "", "", -1, "")
        clock = 0.6
        show(eager ? 0.3 : 0.6)
        CATransaction.commit()
    }
}

struct RunSandbox: NSViewRepresentable {
    let active: Bool
    /// Files are being dragged over the page (pass false when Animations is off). Finder is in front
    /// while you drag, so this plays even though the app is not.
    var eager = false
    /// Files just dropped or opened: swallow them, then call `onGulped` to import them.
    var gulp: Gulp? = nil
    var onGulped: (UUID) -> Void = { _ in }
    func makeNSView(context: Context) -> RunSandboxView { RunSandboxView(frame: .zero) }
    func updateNSView(_ v: RunSandboxView, context: Context) {
        v.eager = eager
        v.ambientActive = active || eager || gulp != nil
        if let g = gulp { v.startGulp(g, onDone: onGulped) }
    }
}
