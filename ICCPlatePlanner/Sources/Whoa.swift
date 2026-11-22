import SwiftUI
import AppKit
import QuartzCore

// MARK: - The big moments
//
// Antibodies docking in the compatibility check, the plate reader sweeping the plate at export, the
// confetti, and the plate tilting towards the pointer. None of them redraws anything per frame in the
// app: each picture is drawn once, and the motion is handed to Core Animation as a one-shot animation
// (or a particle emitter), which the window server plays on its own and which ends by itself.

private extension CALayer {
    /// Adds a one-shot animation that starts `delay` seconds from now.
    func play(_ a: CAAnimation, _ key: String, delay: Double = 0) {
        a.beginTime = CACurrentMediaTime() + delay
        a.fillMode = .both
        a.isRemovedOnCompletion = true
        add(a, forKey: key)
    }
}

private func keyframes(_ path: String, _ values: [Any], _ times: [Double], _ duration: Double,
                       timing: CAMediaTimingFunctionName = .easeInEaseOut) -> CAKeyframeAnimation {
    let a = CAKeyframeAnimation(keyPath: path)
    a.values = values
    a.keyTimes = times.map { NSNumber(value: $0) }
    a.duration = duration
    a.timingFunctions = Array(repeating: CAMediaTimingFunction(name: timing), count: max(1, values.count - 1))
    return a
}

// MARK: - Antibodies docking (compatibility check)
//
// Each pairing in a stain's compatibility list gets a tiny scene: the primary lies on its side, and the
// secondary swims in from the right. A right pairing takes hold of the primary's stem with its arms and
// its dye lights up; a wrong one bumps the primary, bounces off and stays apart in red.

enum DockState: Equatable { case bound(String), refused, unsure, none }

struct DockingIcon: NSViewRepresentable {
    let state: DockState
    let motion: Bool
    /// Stagger, so a card's pairings dock one after another.
    let delay: Double
    /// Drawn for 40 × 16 and shown 1.3 times bigger, so the binding reads at a glance.
    static let zoom: CGFloat = 1.3
    static let size = CGSize(width: 40 * zoom, height: 16 * zoom)

    func makeNSView(context: Context) -> DockingView { DockingView(frame: CGRect(origin: .zero, size: Self.size)) }
    func updateNSView(_ v: DockingView, context: Context) { v.show(state, motion: motion, delay: delay) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DockingView, context: Context) -> CGSize? { Self.size }
}

final class DockingView: NSView {
    private let primary = CALayer(), secondary = CALayer(), glow = CALayer(), ring = CALayer(), spark = CALayer()
    /// Everything, laid out at 40 × 16 and scaled up.
    private let stage = CALayer()
    private var shown: DockState?
    private static let docked: CGFloat = 13      // the secondary's left edge once it holds the primary
    private static var cache: [String: CGImage] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        layer?.isGeometryFlipped = true
        stage.anchorPoint = .zero
        stage.bounds = CGRect(x: 0, y: 0, width: 40, height: 16)
        stage.position = .zero
        stage.transform = CATransform3DMakeScale(DockingIcon.zoom, DockingIcon.zoom, 1)
        layer?.addSublayer(stage)
        for l in [primary, glow, ring, secondary, spark] { stage.addSublayer(l) }
        spark.bounds = CGRect(x: 0, y: 0, width: 14, height: 14)
        spark.position = CGPoint(x: 17.5, y: 8)     // where the secondary's arms close on the primary's stem
        spark.opacity = 0
        primary.frame = CGRect(x: 0, y: 0, width: 18, height: 16)
        primary.contents = Self.image("p") { c in Self.drawPrimary(c) }
        secondary.anchorPoint = CGPoint(x: 0, y: 0.5)
        secondary.bounds = CGRect(x: 0, y: 0, width: 22, height: 16)
        glow.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
        ring.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
        ring.opacity = 0
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private static func image(_ key: String, _ draw: (CGContext) -> Void) -> CGImage? {
        if let i = cache[key] { return i }
        let side: CGFloat = key.hasPrefix("k") ? 14 : (key.hasPrefix("g") || key.hasPrefix("r") ? 16 : (key == "p" ? 18 : 22))
        let i = renderImage(CGSize(width: side, height: key.hasPrefix("k") ? 14 : 16), screenScale * DockingIcon.zoom, draw)
        cache[key] = i
        return i
    }

    /// The primary on its side: arms to the left, stem to the right.
    private static func drawPrimary(_ c: CGContext) {
        c.setStrokeColor(cg("6B7C93")); c.setLineWidth(1.9); c.setLineCap(.round); c.setLineJoin(.round)
        c.move(to: CGPoint(x: 1.6, y: 2.6)); c.addLine(to: CGPoint(x: 8, y: 8)); c.addLine(to: CGPoint(x: 1.6, y: 13.4))
        c.move(to: CGPoint(x: 8, y: 8)); c.addLine(to: CGPoint(x: 17, y: 8))
        c.strokePath()
    }

    /// The secondary: arms open to the left to take the primary's stem, its dye on the end of its own stem.
    private static func drawSecondary(_ c: CGContext, body: String, dye: String?) {
        c.setStrokeColor(cg(body)); c.setLineWidth(1.9); c.setLineCap(.round); c.setLineJoin(.round)
        c.move(to: CGPoint(x: 0.8, y: 3.2)); c.addLine(to: CGPoint(x: 6, y: 8)); c.addLine(to: CGPoint(x: 0.8, y: 12.8))
        c.move(to: CGPoint(x: 6, y: 8)); c.addLine(to: CGPoint(x: 14.5, y: 8))
        c.strokePath()
        c.setFillColor(cg(dye ?? body)); c.fillEllipse(in: CGRect(x: 14.6, y: 4.9, width: 6.2, height: 6.2))
        c.setFillColor(NSColor(white: 1, alpha: 0.55).cgColor); c.fillEllipse(in: CGRect(x: 16, y: 6, width: 2.2, height: 2.2))
    }

    /// A four-pointed spark, white at the heart and the colour at its tips.
    private static func drawSpark(_ c: CGContext, _ hex: String) {
        let m = CGPoint(x: 7, y: 7)
        let p = CGMutablePath()
        for i in 0..<8 {
            let a = Double(i) / 8 * 2 * .pi, r: CGFloat = i % 2 == 0 ? 6.8 : 1.8
            let q = CGPoint(x: m.x + CGFloat(cos(a)) * r, y: m.y + CGFloat(sin(a)) * r)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath()
        c.addPath(p); c.setFillColor(cg(hex)); c.fillPath()
        c.setFillColor(cg("FFFFFF", 0.95)); c.fillEllipse(in: CGRect(x: m.x - 1.8, y: m.y - 1.8, width: 3.6, height: 3.6))
    }

    func show(_ state: DockState, motion: Bool, delay: Double) {
        guard state != shown else { return }
        let first = shown == nil
        shown = state
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        secondary.removeAllAnimations(); glow.removeAllAnimations(); ring.removeAllAnimations(); spark.removeAllAnimations()
        spark.opacity = 0
        let d = Self.docked, y: CGFloat = 8
        var rest = d, alpha: Float = 1
        switch state {
        case .bound(let hex):
            secondary.contents = Self.image("s" + hex) { c in Self.drawSecondary(c, body: "8EA4C3", dye: hex) }
            glow.contents = Self.image("g" + hex) { c in
                let space = CGColorSpace(name: CGColorSpace.sRGB)!
                if let g = CGGradient(colorsSpace: space, colors: [cg(hex, 0.95), cg(hex, 0.35), cg(hex, 0)] as CFArray, locations: [0, 0.4, 1]) {
                    c.drawRadialGradient(g, startCenter: CGPoint(x: 8, y: 8), startRadius: 0, endCenter: CGPoint(x: 8, y: 8), endRadius: 8, options: [])
                }
            }
            ring.contents = Self.image("r" + hex) { c in
                c.setStrokeColor(cg(hex, 0.9)); c.setLineWidth(1.2); c.strokeEllipse(in: CGRect(x: 1, y: 1, width: 14, height: 14))
            }
        case .refused:
            secondary.contents = Self.image("sx") { c in Self.drawSecondary(c, body: "D9534F", dye: "E8908D") }
            glow.contents = nil
            rest = d + 5
        case .unsure:
            secondary.contents = Self.image("s?") { c in Self.drawSecondary(c, body: "A7B4C6", dye: "C9D2DE") }
            glow.contents = nil
            rest = d + 5; alpha = 0.75
        case .none:
            secondary.contents = nil
            glow.contents = nil
        }
        let dye = CGPoint(x: d + 17.7, y: y)
        secondary.position = CGPoint(x: rest, y: y)
        secondary.opacity = state == .none ? 0 : alpha
        secondary.transform = CATransform3DIdentity
        glow.position = dye; ring.position = dye
        if case .bound = state { glow.opacity = 0.75 } else { glow.opacity = 0 }
        ring.opacity = 0

        guard motion, state != .none, window != nil || first else { return }
        let wait = delay + (first ? 0.35 : 0)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = alpha; fade.duration = 0.22
        secondary.play(fade, "fade", delay: wait)
        switch state {
        case .bound(let hex):
            let swim = CASpringAnimation(keyPath: "position.x")
            swim.fromValue = d + 22; swim.toValue = d
            swim.mass = 0.6; swim.stiffness = 210; swim.damping = 11; swim.initialVelocity = -4
            swim.duration = swim.settlingDuration
            secondary.play(swim, "swim", delay: wait)
            let tilt = CASpringAnimation(keyPath: "transform.rotation.z")
            tilt.fromValue = 0.55; tilt.toValue = 0
            tilt.mass = 0.6; tilt.stiffness = 180; tilt.damping = 9
            tilt.duration = tilt.settlingDuration
            secondary.play(tilt, "tilt", delay: wait)
            // the dye lights up as it takes hold
            let g = CAAnimationGroup()
            g.animations = [keyframes("opacity", [0, 1, 0.75], [0, 0.35, 1], 0.6),
                            keyframes("transform.scale", [0.3, 1.9, 1], [0, 0.35, 1], 0.6)]
            g.duration = 0.6
            glow.play(g, "light", delay: wait + 0.32)
            let r = CAAnimationGroup()
            r.animations = [keyframes("opacity", [0.9, 0], [0, 1], 0.55, timing: .easeOut),
                            keyframes("transform.scale", [0.4, 2.2], [0, 1], 0.55, timing: .easeOut)]
            r.duration = 0.55
            ring.play(r, "pulse", delay: wait + 0.34)
            // it clicks into place: a spark where the arms close on the stem
            spark.contents = Self.image("k" + hex) { c in Self.drawSpark(c, hex) }
            let k = CAAnimationGroup()
            k.animations = [keyframes("opacity", [0, 1, 0], [0, 0.25, 1], 0.38),
                            keyframes("transform.scale", [0.2, 1.35, 0.6], [0, 0.3, 1], 0.38, timing: .easeOut),
                            keyframes("transform.rotation.z", [0, 0.6], [0, 1], 0.38)]
            k.duration = 0.38
            spark.play(k, "click", delay: wait + 0.2)
            if !first { DispatchQueue.main.asyncAfter(deadline: .now() + wait + 0.2) { Sounds.snap() } }
        case .refused:
            // in, a bump against the primary, then it backs off and shudders
            let bump = keyframes("position.x", [d + 22, d + 1.5, d + 8, d + 4, d + 6, d + 5], [0, 0.38, 0.58, 0.72, 0.86, 1], 0.85)
            secondary.play(bump, "bump", delay: wait)
            let shake = keyframes("transform.rotation.z", [0.4, 0, -0.25, 0.18, -0.08, 0], [0, 0.38, 0.55, 0.7, 0.85, 1], 0.85)
            secondary.play(shake, "shake", delay: wait)
            // the bump: a red burst where it hits the primary and is turned away
            spark.contents = Self.image("kBAD") { c in Self.drawSpark(c, "E5484D") }
            let k = CAAnimationGroup()
            k.animations = [keyframes("opacity", [0, 1, 0], [0, 0.2, 1], 0.42),
                            keyframes("transform.scale", [0.3, 1.5, 0.8], [0, 0.25, 1], 0.42, timing: .easeOut)]
            k.duration = 0.42
            spark.play(k, "bump", delay: wait + 0.3)
        case .unsure:
            let drift = keyframes("position.x", [d + 22, d + 4, d + 5], [0, 0.7, 1], 0.7, timing: .easeOut)
            secondary.play(drift, "drift", delay: wait)
        case .none: break
        }
    }
}

// MARK: - Plate reader (export)
//
// Before the confetti, a microscope objective sweeps the plate row by row, snaking like a plate reader,
// and every stained well it passes blooms in its stain's colour.

struct ReaderWell: Equatable { var index: Int; var hex: String }

struct PlateReaderSweep: NSViewRepresentable {
    let at: Date
    let wells: [ReaderWell]
    let cw: CGFloat, ch: CGFloat
    let on: Bool
    func makeNSView(context: Context) -> PlateReaderView { PlateReaderView(frame: .zero) }
    func updateNSView(_ v: PlateReaderView, context: Context) { v.run(at, wells: wells, cw: cw, ch: ch, on: on) }
}

/// How long the sweep takes; the confetti waits for it.
let readerSweepLength = 1.85

final class PlateReaderView: NSView {
    private var ran = Date.distantPast
    private static var blooms: [String: CGImage] = [:]
    static let lens: CGImage? = renderImage(CGSize(width: 64, height: 64), screenScale) { c in
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctr = CGPoint(x: 32, y: 32)
        // the light it throws on the plate
        if let g = CGGradient(colorsSpace: space, colors: [cg("FFFFFF", 0.55), cg("BFE6FF", 0.25), cg("BFE6FF", 0)] as CFArray, locations: [0, 0.45, 1]) {
            c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: 32, options: [])
        }
        // the barrel
        let barrel = CGRect(x: 14, y: 14, width: 36, height: 36)
        if let g = CGGradient(colorsSpace: space, colors: [cg("F4F6F9"), cg("9AA6B6"), cg("3E4A5C")] as CFArray, locations: [0, 0.55, 1]) {
            c.saveGState(); c.addEllipse(in: barrel); c.clip()
            c.drawLinearGradient(g, start: CGPoint(x: 14, y: 14), end: CGPoint(x: 50, y: 50), options: [])
            c.restoreGState()
        }
        c.setStrokeColor(cg("1E2A3A", 0.55)); c.setLineWidth(1); c.strokeEllipse(in: barrel.insetBy(dx: 0.5, dy: 0.5))
        // a coloured band, as objectives have
        c.setStrokeColor(cg("E2483D", 0.9)); c.setLineWidth(1.6); c.strokeEllipse(in: barrel.insetBy(dx: 3.2, dy: 3.2))
        // the glass
        let glass = barrel.insetBy(dx: 7.5, dy: 7.5)
        if let g = CGGradient(colorsSpace: space, colors: [cg("DDF3FF"), cg("4B8DD6"), cg("0B2142")] as CFArray, locations: [0, 0.5, 1]) {
            c.saveGState(); c.addEllipse(in: glass); c.clip()
            c.drawRadialGradient(g, startCenter: CGPoint(x: glass.midX - 4, y: glass.midY - 4), startRadius: 0,
                                 endCenter: CGPoint(x: glass.midX, y: glass.midY), endRadius: glass.width * 0.62, options: [])
            c.restoreGState()
        }
        c.setFillColor(NSColor(white: 1, alpha: 0.85).cgColor)
        c.fillEllipse(in: CGRect(x: glass.minX + 4, y: glass.minY + 3.5, width: 5, height: 3.5))
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        layer?.isGeometryFlipped = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private static func bloom(_ hex: String, _ size: CGSize) -> CGImage? {
        let key = hex + "\(Int(size.width))x\(Int(size.height))"
        if let i = blooms[key] { return i }
        let i = renderImage(CGSize(width: size.width + 24, height: size.height + 24), screenScale) { c in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let ctr = CGPoint(x: size.width / 2 + 12, y: size.height / 2 + 12)
            if let g = CGGradient(colorsSpace: space, colors: [cg("FFFFFF", 0.95), cg(hex, 0.85), cg(hex, 0)] as CFArray, locations: [0, 0.3, 1]) {
                c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: max(size.width, size.height) * 0.75, options: [])
            }
        }
        blooms[key] = i
        return i
    }

    func run(_ at: Date, wells: [ReaderWell], cw: CGFloat, ch: CGFloat, on: Bool) {
        guard at != ran else { return }
        ran = at
        guard on, window != nil, abs(Date().timeIntervalSince(at)) < 0.6, !wells.isEmpty, let root = layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        let rows = 8, cols = 12, T = readerSweepLength
        let lead = 0.18, perRow = (T - 2 * lead) / Double(rows)
        // the lens snakes A1 → A12, B12 → B1, …
        var points: [CGPoint] = [], times: [Double] = []
        func center(_ i: Int, _ j: Int) -> CGPoint { CGPoint(x: (CGFloat(j) + 0.5) * cw, y: (CGFloat(i) + 0.5) * ch) }
        for i in 0..<rows {
            let leftToRight = i % 2 == 0
            let a = center(i, leftToRight ? 0 : cols - 1), b = center(i, leftToRight ? cols - 1 : 0)
            points += [a, b]; times += [lead + Double(i) * perRow, lead + Double(i + 1) * perRow - 0.012]
        }
        let first = points[0], last = points[points.count - 1]
        points = [CGPoint(x: first.x - cw, y: first.y - ch)] + points + [CGPoint(x: last.x - cw, y: last.y + ch)]
        times = [0] + times + [T]
        let lens = CALayer()
        lens.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
        lens.contents = Self.lens
        lens.position = points.last!
        lens.opacity = 0
        root.addSublayer(lens)
        let move = CAKeyframeAnimation(keyPath: "position")
        move.values = points.map { NSValue(point: $0) }
        move.keyTimes = times.map { NSNumber(value: $0 / T) }
        move.duration = T
        move.calculationMode = .linear
        lens.play(move, "move")
        lens.play(keyframes("opacity", [0, 1, 1, 0], [0, 0.08, 0.9, 1], T), "fade")

        // each stained well blooms as the lens crosses it
        let size = CGSize(width: cw, height: ch)
        for w in wells {
            let i = w.index / 12, j = w.index % 12
            let along = i % 2 == 0 ? Double(j) : Double(cols - 1 - j)
            let when = lead + Double(i) * perRow + along / Double(cols - 1) * (perRow - 0.012)
            let b = CALayer()
            b.bounds = CGRect(x: 0, y: 0, width: cw + 24, height: ch + 24)
            b.position = center(i, j)
            b.contents = Self.bloom(w.hex, size)
            b.opacity = 0
            b.compositingFilter = "screenBlendMode"
            root.insertSublayer(b, below: lens)
            let g = CAAnimationGroup()
            g.animations = [keyframes("opacity", [0, 1, 0.45, 0], [0, 0.18, 0.55, 1], 0.9),
                            keyframes("transform.scale", [0.55, 1.18, 1.0, 0.96], [0, 0.18, 0.55, 1], 0.9)]
            g.duration = 0.9
            b.play(g, "bloom", delay: max(0, when - 0.04))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + T + 1.0) { [weak self] in
            guard let self, self.ran == at else { return }
            self.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        }
    }
}

// MARK: - Confetti (export)
//
// Core Animation's particle emitter: the app hands over one burst and the window server flies the
// pieces, so nothing in the app redraws per frame, and the burst ends by itself.

struct ConfettiLayer: View {
    @EnvironmentObject var store: Store
    var body: some View {
        ConfettiBurst(at: store.confettiAt, on: store.motion).allowsHitTesting(false)
    }
}

struct ConfettiBurst: NSViewRepresentable {
    let at: Date
    let on: Bool
    func makeNSView(context: Context) -> ConfettiView { ConfettiView(frame: .zero) }
    func updateNSView(_ v: ConfettiView, context: Context) { v.fire(at, on: on) }
}

final class ConfettiView: NSView {
    private let left = CAEmitterLayer(), right = CAEmitterLayer()
    private var fired = Date.distantPast

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        for (e, side) in [(left, 1.0), (right, -1.0)] {
            e.emitterShape = .point
            e.birthRate = 0
            e.emitterCells = Self.cells(side)
            layer?.addSublayer(e)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for e in [left, right] { e.frame = bounds }
        left.emitterPosition = CGPoint(x: bounds.width * 0.06, y: -12)
        right.emitterPosition = CGPoint(x: bounds.width * 0.94, y: -12)
        CATransaction.commit()
    }

    /// One burst for each new `at`, now or at that moment if it is a little in the future.
    func fire(_ at: Date, on: Bool) {
        guard at != fired else { return }
        fired = at
        let wait = at.timeIntervalSinceNow
        guard on, wait > -0.6, wait < 5 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, wait)) { [weak self] in
            guard let self, self.fired == at else { return }
            let now = CACurrentMediaTime()
            for e in [self.left, self.right] { e.beginTime = now; e.birthRate = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                self?.left.birthRate = 0
                self?.right.birthRate = 0
            }
        }
    }

    /// Five shapes in the app's colours: antibodies, drops, strips, stars and dots.
    private static func cells(_ side: Double) -> [CAEmitterCell] {
        let hexes = ["2FB85A", "E2483D", "2F6FE0", "C04BD8", "F2A900", "17A2A2", "1E4A83"]
        let shapes = (0..<5).map { shapeImage($0) }
        var out: [CAEmitterCell] = []
        for (k, img) in shapes.enumerated() {
            for (j, hex) in hexes.enumerated() where (k + j) % 2 == 0 || k == 2 {
                let c = CAEmitterCell()
                c.contents = img
                c.color = NSColor(hex: hex).cgColor
                c.birthRate = 16
                c.lifetime = 3.2
                c.velocity = 1000
                c.velocityRange = 280
                c.emissionLongitude = .pi / 2 - 0.42 * side          // up and in towards the middle
                c.emissionRange = 0.32
                c.yAcceleration = -1150
                c.spin = 4
                c.spinRange = 9
                c.scale = 0.5
                c.scaleRange = 0.22
                c.alphaSpeed = -0.28
                out.append(c)
            }
        }
        return out
    }

    private static func shapeImage(_ kind: Int) -> CGImage? {
        renderImage(CGSize(width: 26, height: 26), 2) { c in
            c.setFillColor(NSColor.white.cgColor)
            c.setStrokeColor(NSColor.white.cgColor)
            switch kind {
            case 0:     // an antibody
                c.setLineWidth(3.4); c.setLineCap(.round); c.setLineJoin(.round)
                c.move(to: CGPoint(x: 13, y: 24)); c.addLine(to: CGPoint(x: 13, y: 13))
                c.addLine(to: CGPoint(x: 4, y: 3)); c.move(to: CGPoint(x: 13, y: 13)); c.addLine(to: CGPoint(x: 22, y: 3))
                c.strokePath()
            case 1:     // a drop
                c.move(to: CGPoint(x: 13, y: 3))
                c.addQuadCurve(to: CGPoint(x: 20, y: 16), control: CGPoint(x: 20, y: 9))
                c.addArc(center: CGPoint(x: 13, y: 16), radius: 7, startAngle: 0, endAngle: .pi, clockwise: false)
                c.addQuadCurve(to: CGPoint(x: 13, y: 3), control: CGPoint(x: 6, y: 9))
                c.fillPath()
            case 2:     // a strip of paper
                c.fill(CGRect(x: 2, y: 9, width: 22, height: 8))
            case 3:     // a star
                let p = CGMutablePath()
                for i in 0..<8 {
                    let ang = Double(i) / 8 * 2 * .pi - .pi / 2, r = i % 2 == 0 ? 12.0 : 4.6
                    let pt = CGPoint(x: 13 + cos(ang) * r, y: 13 + sin(ang) * r)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.closeSubpath()
                c.addPath(p); c.fillPath()
            default:    // a dot
                c.fillEllipse(in: CGRect(x: 6, y: 6, width: 14, height: 14))
            }
        }
    }
}

// MARK: - The plate tilts towards the pointer
//
// A few degrees of 3D tilt and a sheen that follows the pointer. The tilt lives in its own small model,
// so moving the pointer re-renders only this wrapper's transform, never the 96 wells inside it. It lies
// flat again the moment a drag starts, so painting lands exactly where the pointer is.

/// Whether the pointer is over the plate (its own model, so only what depends on it redraws).
final class HoverFlag: ObservableObject {
    @Published var on = false
    func set(_ v: Bool) { if on != v { on = v } }
}

final class TiltModel: ObservableObject {
    /// The plate's tilt, for the lag check to drive as a pointer would.
    static weak var current: TiltModel?
    init() { Self.current = self }
    @Published var x: CGFloat = 0      // -1 … 1, pointer left … right
    @Published var y: CGFloat = 0      // -1 … 1, pointer top … bottom
    @Published var lit = false
    /// The plate's size, for turning the pointer into a tilt (not published: it never redraws anything).
    var size: CGSize = .zero
}

struct TiltPlate<Content: View>: View {
    let on: Bool
    @ObservedObject var model: TiltModel
    let hover: HoverFlag
    let content: Content

    init(on: Bool, model: TiltModel, hover: HoverFlag, @ViewBuilder content: () -> Content) {
        self.on = on; self.model = model; self.hover = hover; self.content = content()
    }



    var body: some View {
        if tiltProbeMode == "none" { content } else { tilted }
    }

    private var tilted: some View {
        content
            .overlay(
                GeometryReader { geo in
                    // a soft band of light across the plate, where the pointer is
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.07), .white.opacity(0.10), .white.opacity(0.07), .white.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.7)
                        .rotationEffect(.degrees(18))
                        .offset(x: geo.size.width * (0.15 + 0.3 * (model.x + 1) / 2) - geo.size.width * 0.15)
                        .opacity(model.lit ? 1 : 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .allowsHitTesting(false)
                .opacity(tiltProbeMode == "nosheen" ? 0 : 1)
            )
            .rotation3DEffect(.degrees(on && tiltProbeMode != "norotate" ? Double(model.y) * -2.4 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(on && tiltProbeMode != "norotate" ? Double(model.x) * 2.8 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .onContinuousHover { phase in
                switch phase {
                case .active: hover.set(true)
                case .ended: hover.set(false)
                }
                guard on else { return }
                switch phase {
                case .active(let p):
                    guard NSEvent.pressedMouseButtons == 0 else { return }
                    let sz = model.size
                    guard sz.width > 0, sz.height > 0 else { return }
                    // set straight away: the pointer already moves smoothly, and animating every
                    // small step made SwiftUI redraw the plate continuously
                    model.x = max(-1, min(1, p.x / sz.width * 2 - 1))
                    model.y = max(-1, min(1, p.y / sz.height * 2 - 1))
                    if !model.lit { model.lit = true }
                case .ended:
                    flatten()
                }
            }
            .background(GeometryReader { g in Color.clear.onAppear { model.size = g.size }.onChange(of: g.size) { model.size = $0 } })
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in if model.x != 0 || model.y != 0 { flatten() } })
    }

    private func flatten() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { model.x = 0; model.y = 0; model.lit = false }
    }
}


// MARK: - The hologram over a stained well
//
// Pick a stain and, a moment later, one of its wells (the one nearest the middle of its block) becomes
// a projector: a beam reaches up to a cyan scope docked above the plate's
// top-right corner, out of the way of the wells, where the confocal scan plays once: the laser line
// draws DAPI, then 488, 594 and 647, one channel at a time, and a white pass sweeps in the merge. Then it
// folds back into its well, wherever the pointer is. The same stain does not pop up again for a while;
// clicking the selected stain's button again shows it on purpose.

/// When the hologram shows: a moment after a stain is picked, once per stain per cooldown, for one scan.
final class HoloController: ObservableObject {
    /// One for the window: the plate projects it, the rest of the window dims for it.
    static let shared = HoloController()
    @Published private(set) var shown: UUID?
    /// Bumped each time it shows, so the scan starts from the beginning.
    @Published private(set) var plays = 0
    static let dwell = 1.5, cooldown = 30.0
    private var lastShown: [UUID: Date] = [:]
    private var pending: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var selected: UUID?
    private var hovering = false
    private var enabled = true

    /// Called whenever the stain, the pointer or the setting changes. It comes up only when the user picks
    /// a stain (`picked`): the stain restored at launch, or one selected by opening a plate, stays quiet.
    func update(selected: UUID?, hovering: Bool, enabled: Bool, length: Double, picked: Bool = false) {
        self.selected = selected; self.hovering = hovering; self.enabled = enabled
        // the pointer no longer matters: once shown it plays its scan to the end, wherever the pointer is
        if selected == nil || !enabled {
            pending?.cancel(); pending = nil
            hide()
            return
        }
        if shown != nil && shown != selected { hide() }
        if shown == selected { return }
        if picked { schedule(force: false, length: length) }
    }

    /// The selected stain's button clicked again: show it now, cooldown or not.
    func request(length: Double) {
        guard selected != nil, enabled else { return }
        schedule(force: true, length: length)
    }

    private func schedule(force: Bool, length: Double) {
        pending?.cancel(); pending = nil
        guard let id = selected else { return }
        if !force, let t = lastShown[id], Date().timeIntervalSince(t) < Self.cooldown { return }
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.selected == id, self.enabled else { return }
            self.pending = nil
            self.lastShown[id] = Date()
            self.plays += 1
            self.shown = id
            self.hideWork?.cancel()
            let h = DispatchWorkItem { [weak self] in if self?.shown == id { self?.hide() } }
            self.hideWork = h
            DispatchQueue.main.asyncAfter(deadline: .now() + length, execute: h)
        }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + (force ? 0.05 : Self.dwell), execute: w)
    }

    private func hide() {
        hideWork?.cancel(); hideWork = nil
        if shown != nil { shown = nil }
    }
}

struct HologramProjector: View {
    @EnvironmentObject var store: Store
    @ObservedObject var hover: HoverFlag
    @ObservedObject var holo: HoloController
    let cw: CGFloat, ch: CGFloat
    static let scope: CGFloat = 180

    /// The selected stain and the well it projects from.
    private var anchor: (set: UUID, well: Int)? {
        guard case .paint(let id) = store.tool else { return nil }
        let wells = (0..<96).filter { store.exp.wells[$0] == id }
        guard !wells.isEmpty else { return nil }
        let mi = wells.map { Double($0 / 12) }.reduce(0, +) / Double(wells.count)
        let mj = wells.map { Double($0 % 12) }.reduce(0, +) / Double(wells.count)
        let w = wells.min { a, b in
            hypot(Double(a / 12) - mi, Double(a % 12) - mj) < hypot(Double(b / 12) - mi, Double(b % 12) - mj)
        }!
        return (id, w)
    }

    /// The last place it projected from, so it can fold away where it was.
    private static var lastAnchor: (set: UUID, well: Int)?

    /// One pass of the scan: each channel, the merge, and a moment to look at it.
    private func playLength(_ info: PreviewInfo) -> Double { 0.6 + Double(info.channels.count) * 1.6 + 4.2 }

    private func sync(picked: Bool = false) {
        holo.update(selected: anchor?.set, hovering: false, enabled: store.showHologram && store.motion,
                    length: playLength(store.previewInfo), picked: picked)
    }

    var body: some View {
        let W = cw * 12, H = ch * 8
        let found = anchor
        let live = found.flatMap { holo.shown == $0.set ? $0 : nil }
        if let live { Self.lastAnchor = live }
        let a = live ?? Self.lastAnchor
        let visible = live != nil
        // always in the view tree (built once); showing it only fades and scales it out of its well
        return ZStack {
            if let a {
                let i = a.well / 12, j = a.well % 12
                let well = CGPoint(x: (CGFloat(j) + 0.5) * cw, y: (CGFloat(i) + 0.5) * ch)
                let S = Self.scope
                // docked above the plate's top-right corner, clear of the wells
                let cx = W - S / 2 - 4
                let cy = -S / 2 - 62          // its caption sits underneath, between it and the plate
                let info = store.previewInfo
                ZStack {
                    // the light pooled on the well
                    Ellipse()
                        .fill(RadialGradient(colors: [Color(hex: "9BF0FF").opacity(0.85), Color(hex: "38C8F0").opacity(0.25), .clear],
                                             center: .center, startRadius: 0, endRadius: cw * 0.6))
                        .frame(width: cw * 1.2, height: ch * 1.1)
                        .position(well)
                    // the beam up to the scope
                    HologramBeam(from: well, half: cw * 0.22, to: CGPoint(x: cx, y: cy + S / 2 - 8), wide: S * 0.36)
                        .fill(LinearGradient(colors: [Color(hex: "9BF0FF").opacity(0.30), Color(hex: "38C8F0").opacity(0.05)],
                                             startPoint: .bottom, endPoint: .top))
                    StainingPreview(info: info, active: store.ambient && visible, replay: holo.plays, hologram: true)
                        .frame(width: S, height: S)
                        .position(x: cx, y: cy)
                    // the stain's whole description: wraps onto more lines rather than being cut off
                    VStack(spacing: 1) {
                        Text(info.title.uppercased())
                            .font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.8)
                        Text(info.subtitle)
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundColor(Color(hex: "D6FAFF"))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(hex: "04172A").opacity(0.85)))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color(hex: "9BF0FF").opacity(0.6), lineWidth: 0.8))
                    .frame(maxWidth: S + 60)
                    .frame(width: S + 60, height: 48, alignment: .top)     // under the scope, growing downwards
                    .position(x: cx - 14, y: cy + S / 2 + 4 + 24)
                }
                .frame(width: W, height: H)
                .scaleEffect(visible ? 1 : 0.05, anchor: UnitPoint(x: well.x / W, y: well.y / H))
                .opacity(visible ? 1 : 0)
            }
        }
        .frame(width: W, height: H)
        .animation(store.motion ? .spring(response: 0.5, dampingFraction: 0.8) : nil, value: visible)
        .allowsHitTesting(false)
        .onAppear { sync() }
        .onChange(of: found?.set) { _ in sync() }
        .onChange(of: store.stainPicked) { _ in sync(picked: true) }
        .onChange(of: store.showHologram) { _ in sync() }
        .onChange(of: store.hologramRequest) { _ in
            sync()
            holo.request(length: playLength(store.previewInfo))
        }
    }
}

/// A beam from a small disc on the well to a wider band under (or over) the scope.
struct HologramBeam: Shape {
    let from: CGPoint, half: CGFloat, to: CGPoint, wide: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: from.x - half, y: from.y))
        p.addLine(to: CGPoint(x: to.x - wide, y: to.y))
        p.addLine(to: CGPoint(x: to.x + wide, y: to.y))
        p.addLine(to: CGPoint(x: from.x + half, y: from.y))
        p.closeSubpath()
        return p
    }
}

let tiltProbeMode = ProcessInfo.processInfo.environment["ICC_TILT_PROBE"] ?? ""
