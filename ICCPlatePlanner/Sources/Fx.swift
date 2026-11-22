import SwiftUI
import AppKit
import QuartzCore

// MARK: - Effects across the window
//
// One transparent layer over the whole window carries the effects that travel between views: antibodies
// flying from a stain's card to its wells, frost melting off a plate that has just been opened, a red
// alarm running through the wells of a stain whose pairing has gone wrong, and a pipette the size of a
// well over each well as you paint it. Every effect is a one-shot Core Animation animation handed to
// the window server, so nothing in the app redraws per frame, and they are all off with Animations.

/// Where things are on screen, in the window's (top-down) coordinates. Kept up to date by the views
/// without publishing anything, so recording a position never redraws a view.
final class FxCenter {
    static let shared = FxCenter()
    weak var view: FxView?
    /// Invisible marker views on the plate's grid and on each stain card. Where they are is asked only when
    /// an effect plays: tracking it continuously (SwiftUI preferences) re-ran the view graph on every frame
    /// of scrolling and made the card list lag.
    weak var gridAnchor: NSView?
    /// The whole plate (its moulded body), for the lid.
    weak var plateAnchor: NSView?
    /// The plan on screen, for the loupe to look up what is in a well.
    weak var store: Store?
    var cardAnchors: [UUID: Weak] = [:]
    final class Weak { weak var view: NSView?; init(_ v: NSView) { view = v } }

    /// `v`'s frame in the effects layer's (top-down) coordinates.
    private func rect(of v: NSView?) -> CGRect {
        guard let v, let fx = view, v.window != nil, v.window === fx.window else { return .zero }
        let r = fx.convert(v.bounds, from: v)
        return CGRect(x: r.minX, y: fx.bounds.height - r.maxY, width: r.width, height: r.height)
    }
    var gridFrame: CGRect { rect(of: gridAnchor) }
    var plateFrame: CGRect { rect(of: plateAnchor) }
    var cardFrames: [UUID: CGRect] {
        var out: [UUID: CGRect] = [:]
        for (id, w) in cardAnchors { let r = rect(of: w.view); if r != .zero { out[id] = r } }
        return out
    }
    var cw: CGFloat = 48, ch: CGFloat = 44
    var on = true

    func wellCenter(_ w: Int) -> CGPoint {
        CGPoint(x: gridFrame.minX + (CGFloat(w % 12) + 0.5) * cw, y: gridFrame.minY + (CGFloat(w / 12) + 0.5) * ch)
    }
    var usable: Bool { on && view != nil && gridFrame.width > 0 }
}

let fxSpace = "fxroot"

/// An invisible view that marks where the plate's grid or a stain card is.
struct FxAnchor: NSViewRepresentable {
    enum Kind { case grid, plate, card(UUID) }
    let kind: Kind
    func makeNSView(context: Context) -> AnchorView {
        let v = AnchorView(frame: .zero)
        v.kind = kind
        return v
    }
    func updateNSView(_ v: AnchorView, context: Context) {
        v.kind = kind
        if v.window != nil { v.register() }
    }

    /// Registers itself when it joins a window and lets go only if it is still the one registered: when the
    /// window is rebuilt (switching the microscope room), the old markers leave after the new ones arrive,
    /// and clearing on make/update let a departing marker take the effects' targets with it.
    final class AnchorView: NSView {
        var kind: Kind = .grid
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { register() } else { unregister() }
        }
        func register() {
            switch kind {
            case .grid: FxCenter.shared.gridAnchor = self
            case .plate: FxCenter.shared.plateAnchor = self
            case .card(let id): FxCenter.shared.cardAnchors[id] = FxCenter.Weak(self)
            }
        }
        private func unregister() {
            switch kind {
            case .grid: if FxCenter.shared.gridAnchor === self { FxCenter.shared.gridAnchor = nil }
            case .plate: if FxCenter.shared.plateAnchor === self { FxCenter.shared.plateAnchor = nil }
            case .card(let id): if FxCenter.shared.cardAnchors[id]?.view === self { FxCenter.shared.cardAnchors[id] = nil }
            }
        }
    }
}

extension View {
    /// Marks this view as the plate's grid.
    func fxGrid() -> some View { background(FxAnchor(kind: .grid)) }
    /// Marks this view as the whole plate.
    func fxPlate() -> some View { background(FxAnchor(kind: .plate)) }
    /// Marks this view as stain `id`'s card.
    func fxCard(_ id: UUID) -> some View { background(FxAnchor(kind: .card(id))) }
}

struct FxOverlay: NSViewRepresentable {
    let store: Store
    func makeNSView(context: Context) -> FxView { FxCenter.shared.store = store; return FxView(frame: .zero) }
    func updateNSView(_ v: FxView, context: Context) {
        FxCenter.shared.store = store
        if v.window != nil { FxCenter.shared.view = v }
    }
}

extension CALayer {
    func run(_ a: CAAnimation, _ key: String, delay: Double = 0) {
        a.beginTime = CACurrentMediaTime() + delay
        a.fillMode = .both
        a.isRemovedOnCompletion = true
        add(a, forKey: key)
    }
}

func frames(_ path: String, _ values: [Any], _ times: [Double], _ d: Double, _ timing: CAMediaTimingFunctionName = .easeInEaseOut) -> CAKeyframeAnimation {
    let a = CAKeyframeAnimation(keyPath: path)
    a.values = values
    a.keyTimes = times.map { NSNumber(value: $0) }
    a.duration = d
    a.timingFunctions = Array(repeating: CAMediaTimingFunction(name: timing), count: max(1, values.count - 1))
    return a
}

final class FxView: NSView {
    private static var images: [String: CGImage?] = [:]
    /// Everything is drawn in this layer, laid out top-down like the SwiftUI views. (AppKit resets the
    /// flip on a view's own layer, which turned every effect upside down; a sublayer keeps it.)
    let space = CALayer()
    /// Hold Option over a stained well: a microscope eyepiece over it.
    let loupe = LoupeController()

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        space.isGeometryFlipped = true
        layer?.addSublayer(space)
    }

    override func layout() {
        super.layout()
        fitSpace()
    }

    private func fitSpace() {
        guard space.frame != bounds else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        space.frame = bounds
        CATransaction.commit()
    }

    /// Development: the drawing layer's size against the view's.
    var spaceFrame: CGRect { space.frame }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // the effects layer in the window, kept the same way as the markers
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { FxCenter.shared.view = self; loupe.attach(self) } else {
            loupe.detach()
            if FxCenter.shared.view === self { FxCenter.shared.view = nil }
        }
    }

    static func image(_ key: String, _ size: CGSize, _ draw: (CGContext) -> Void) -> CGImage? {
        if let i = images[key] { return i }
        let i = renderImage(size, screenScale, draw)
        images[key] = i
        return i
    }

    /// Removes `l` once its animations are over.
    func expire(_ l: CALayer, after: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + after) { l.removeFromSuperlayer() }
    }

    // MARK: antibodies flying from a card to its wells

    func fly(from: CGPoint, to targets: [CGPoint], hexes: [String]) {
        let root = space
        guard !targets.isEmpty else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for (k, to) in targets.enumerated() {
            var hex = hexes.isEmpty ? "4A78B8" : hexes[k % hexes.count]
            // "BAD": a pairing that cannot work; its antibody is marked with a cross and bounces off the well
            let rejected = hex == "BAD"
            if rejected { hex = "FF3B30" }
            let ab = CALayer()
            ab.bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
            ab.contents = rejected ? Self.image("abBAD", CGSize(width: 22, height: 22)) { c in
                let space = CGColorSpace(name: CGColorSpace.sRGB)!
                if let g = CGGradient(colorsSpace: space, colors: [cg("FF3B30", 0.5), cg("FF3B30", 0)] as CFArray, locations: [0, 1]) {
                    c.drawRadialGradient(g, startCenter: CGPoint(x: 11, y: 11), startRadius: 0, endCenter: CGPoint(x: 11, y: 11), endRadius: 11, options: [])
                }
                c.setStrokeColor(cg("FF453A")); c.setLineWidth(2.2); c.setLineCap(.round); c.setLineJoin(.round)
                c.move(to: CGPoint(x: 11, y: 19)); c.addLine(to: CGPoint(x: 11, y: 11))
                c.addLine(to: CGPoint(x: 5, y: 4)); c.move(to: CGPoint(x: 11, y: 11)); c.addLine(to: CGPoint(x: 17, y: 4))
                c.strokePath()
                // the cross
                c.setFillColor(NSColor.white.cgColor); c.fillEllipse(in: CGRect(x: 12, y: 12, width: 10, height: 10))
                c.setStrokeColor(cg("FF3B30")); c.setLineWidth(1.8)
                c.move(to: CGPoint(x: 14.5, y: 14.5)); c.addLine(to: CGPoint(x: 19.5, y: 19.5))
                c.move(to: CGPoint(x: 19.5, y: 14.5)); c.addLine(to: CGPoint(x: 14.5, y: 19.5))
                c.strokePath()
            } : Self.image("ab" + hex, CGSize(width: 22, height: 22)) { c in
                let space = CGColorSpace(name: CGColorSpace.sRGB)!
                if let g = CGGradient(colorsSpace: space, colors: [cg(hex, 0.55), cg(hex, 0)] as CFArray, locations: [0, 1]) {
                    c.drawRadialGradient(g, startCenter: CGPoint(x: 11, y: 11), startRadius: 0, endCenter: CGPoint(x: 11, y: 11), endRadius: 11, options: [])
                }
                c.setStrokeColor(NSColor.white.cgColor); c.setLineWidth(2.4); c.setLineCap(.round); c.setLineJoin(.round)
                c.move(to: CGPoint(x: 11, y: 19)); c.addLine(to: CGPoint(x: 11, y: 11))
                c.addLine(to: CGPoint(x: 5, y: 4)); c.move(to: CGPoint(x: 11, y: 11)); c.addLine(to: CGPoint(x: 17, y: 4))
                c.strokePath()
                c.setStrokeColor(cg(hex)); c.setLineWidth(1.4)
                c.move(to: CGPoint(x: 11, y: 19)); c.addLine(to: CGPoint(x: 11, y: 11))
                c.addLine(to: CGPoint(x: 5, y: 4)); c.move(to: CGPoint(x: 11, y: 11)); c.addLine(to: CGPoint(x: 17, y: 4))
                c.strokePath()
            }
            ab.position = to
            ab.opacity = 0
            root.addSublayer(ab)
            let start = CGPoint(x: from.x + CGFloat(k % 3 - 1) * 14, y: from.y + CGFloat(k / 3) * 6)
            let path = CGMutablePath()
            path.move(to: start)
            let lift = min(start.y, to.y) - 90 - CGFloat(k % 4) * 14
            path.addCurve(to: to, control1: CGPoint(x: start.x + (to.x - start.x) * 0.3, y: lift),
                          control2: CGPoint(x: start.x + (to.x - start.x) * 0.75, y: lift + 20))
            let d = 0.95, wait = Double(k) * 0.07
            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path
            move.duration = d
            move.timingFunctions = [CAMediaTimingFunction(controlPoints: 0.3, 0, 0.25, 1)]
            let g = CAAnimationGroup()
            if rejected {
                // lands on its well, shudders there (it cannot bind) and fades where it stands
                let shake = CAKeyframeAnimation(keyPath: "position.x")
                shake.values = [to.x, to.x - 4, to.x + 4, to.x - 3, to.x + 3, to.x]
                shake.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
                shake.duration = 0.45
                shake.beginTime = d
                g.animations = [move, shake,
                                frames("opacity", [0, 1, 1, 1, 0], [0, 0.08, 0.6, 0.8, 1], d + 0.55),
                                frames("transform.rotation.z", [-0.6, 0.4, 0, 0], [0, 0.4, 0.62, 1], d + 0.55),
                                frames("transform.scale", [0.6, 1.25, 1.0, 0.85], [0, 0.35, 0.62, 1], d + 0.55)]
                g.duration = d + 0.55
            } else {
                g.animations = [move,
                                frames("opacity", [0, 1, 1, 0], [0, 0.12, 0.85, 1], d),
                                frames("transform.rotation.z", [-0.6, 0.5, 0], [0, 0.6, 1], d),
                                frames("transform.scale", [0.6, 1.25, 0.7], [0, 0.5, 1], d)]
                g.duration = d
            }
            ab.run(g, "fly", delay: wait)
            expire(ab, after: wait + g.duration + 0.1)
            ripple(at: to, hex: hex, delay: wait + d - 0.08, size: 30)
        }
    }

    private func ripple(at p: CGPoint, hex: String, delay: Double, size: CGFloat) {
        let root = space
        let r = CALayer()
        r.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        r.cornerRadius = size / 2
        r.borderWidth = 2
        r.borderColor = cg(hex, 0.9)
        r.position = p
        r.opacity = 0
        root.addSublayer(r)
        let g = CAAnimationGroup()
        g.animations = [frames("opacity", [0.95, 0], [0, 1], 0.55, .easeOut), frames("transform.scale", [0.4, 1.7], [0, 1], 0.55, .easeOut)]
        g.duration = 0.55
        r.run(g, "ripple", delay: delay)
        expire(r, after: delay + 0.65)
    }

    // MARK: frost melting off a freshly opened plate

    func thaw(grid: CGRect, cw: CGFloat, ch: CGFloat) {
        let root = space
        guard grid.width > 0 else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        // a sheet of frost over the whole plate, crystals and all
        let sheet = CALayer()
        sheet.frame = grid.insetBy(dx: -20, dy: -30)
        let size = sheet.bounds.size
        sheet.contents = renderImage(size, screenScale) { c in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            c.setFillColor(cg("EAF4FF", 0.55)); c.fill(CGRect(origin: .zero, size: size))
            if let g = CGGradient(colorsSpace: space, colors: [cg("FFFFFF", 0.5), cg("CFE6FF", 0.15)] as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            c.setLineCap(.round)
            for i in 0..<160 {                                  // ice crystals: little six-armed stars
                let x = CGFloat(hash01(i, 301)) * size.width, y = CGFloat(hash01(i, 302)) * size.height
                let r = CGFloat(2 + 7 * hash01(i, 303))
                c.setStrokeColor(cg("FFFFFF", 0.35 + 0.4 * CGFloat(hash01(i, 304)))); c.setLineWidth(0.8)
                for k in 0..<3 {
                    let a = Double(k) * .pi / 3 + hash01(i, 305)
                    c.move(to: CGPoint(x: x - CGFloat(cos(a)) * r, y: y - CGFloat(sin(a)) * r))
                    c.addLine(to: CGPoint(x: x + CGFloat(cos(a)) * r, y: y + CGFloat(sin(a)) * r))
                }
                c.strokePath()
            }
            for i in 0..<700 {                                  // rime
                c.setFillColor(cg("FFFFFF", 0.25 + 0.5 * CGFloat(hash01(i, 311))))
                c.fill(CGRect(x: CGFloat(hash01(i, 312)) * size.width, y: CGFloat(hash01(i, 313)) * size.height, width: 1.2, height: 1.2))
            }
        }
        sheet.cornerRadius = 14
        sheet.masksToBounds = true
        sheet.opacity = 0
        sheet.zPosition = 25              // on the lid: the frost melts off it before the lid comes off
        root.addSublayer(sheet)
        // the sheet melts from the edges inwards: a mask of 96 well-sized tiles that vanish edge-first
        let mask = CALayer()
        mask.frame = sheet.bounds
        let tile = CGSize(width: cw + 2, height: ch + 2)
        var longest = 0.0
        for i in -1...8 {
            for j in -1...12 {
                let t = CALayer()
                t.backgroundColor = NSColor.black.cgColor
                t.frame = CGRect(x: 20 + CGFloat(j) * cw - 1, y: 30 + CGFloat(i) * ch - 1, width: tile.width, height: tile.height)
                if i == -1 { t.frame.origin.y = 0; t.frame.size.height = 30 + ch * 0 + 1 }
                if i == 8 { t.frame.size.height = 31 }
                if j == -1 { t.frame.origin.x = 0; t.frame.size.width = 21 }
                if j == 12 { t.frame.size.width = 21 }
                let edge = min(min(i + 1, 8 - i), min(j + 1, 12 - j))          // 0 at the rim, 4 in the middle
                let delay = 0.55 + Double(edge) * 0.32 + 0.12 * hash01(i * 13 + j, 321)
                longest = max(longest, delay)
                t.opacity = 0
                t.run(frames("opacity", [1, 1, 0], [0, 0.6, 1], delay + 0.35), "melt")
                mask.addSublayer(t)
            }
        }
        sheet.mask = mask
        sheet.run(frames("opacity", [0, 1, 1], [0, 0.08, 1], longest + 0.35), "show")
        expire(sheet, after: longest + 0.5)
        // a breath of cold mist rolling off as it goes
        for k in 0..<6 {
            let m = CALayer()
            m.bounds = CGRect(x: 0, y: 0, width: 120, height: 60)
            m.contents = Self.image("mist", CGSize(width: 120, height: 60)) { c in
                let space = CGColorSpace(name: CGColorSpace.sRGB)!
                if let g = CGGradient(colorsSpace: space, colors: [cg("FFFFFF", 0.45), cg("FFFFFF", 0)] as CFArray, locations: [0, 1]) {
                    c.saveGState(); c.scaleBy(x: 2, y: 1)
                    c.drawRadialGradient(g, startCenter: CGPoint(x: 30, y: 30), startRadius: 0, endCenter: CGPoint(x: 30, y: 30), endRadius: 30, options: [])
                    c.restoreGState()
                }
            }
            let x = grid.minX + grid.width * CGFloat(k) / 5
            m.position = CGPoint(x: x, y: grid.maxY + 10)
            m.opacity = 0
            root.addSublayer(m)
            let g = CAAnimationGroup()
            g.animations = [frames("opacity", [0, 0.8, 0], [0, 0.3, 1], 1.8),
                            frames("position.y", [grid.maxY + 10, grid.maxY + 40], [0, 1], 1.8, .easeOut),
                            frames("transform.scale", [0.6, 1.4], [0, 1], 1.8, .easeOut)]
            g.duration = 1.8
            m.run(g, "mist", delay: 0.4 + Double(k) * 0.12)
            expire(m, after: 2.5 + Double(k) * 0.12)
        }
    }

    // MARK: the alarm when a stain's pairing goes wrong

    func alarm(at points: [CGPoint], cw: CGFloat, ch: CGFloat) {
        let root = space
        guard !points.isEmpty else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let minX = points.map { $0.x }.min() ?? 0
        let glow = Self.image("alarm\(Int(cw))x\(Int(ch))", CGSize(width: cw + 18, height: ch + 18)) { c in
            let r = CGRect(x: 9, y: 9, width: cw, height: ch).insetBy(dx: 2.5, dy: 2.5)
            c.setShadow(offset: .zero, blur: 8, color: cg("FF3B30", 0.95))
            c.addPath(CGPath(roundedRect: r, cornerWidth: 8, cornerHeight: 8, transform: nil))
            c.setStrokeColor(cg("FF453A")); c.setLineWidth(2.6); c.strokePath()
            c.addPath(CGPath(roundedRect: r, cornerWidth: 8, cornerHeight: 8, transform: nil))
            c.setFillColor(cg("FF3B30", 0.22)); c.fillPath()
        }
        for p in points {
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: cw + 18, height: ch + 18)
            l.position = p
            l.contents = glow
            l.opacity = 0
            root.addSublayer(l)
            // the pulse runs across the stain's wells from left to right, twice
            let wait = Double((p.x - minX) / cw) * 0.05
            l.run(frames("opacity", [0, 1, 0.15, 1, 0], [0, 0.18, 0.45, 0.65, 1], 1.3), "alarm", delay: wait)
            expire(l, after: wait + 1.4)
        }
    }

    // MARK: a pipette the size of a well, over the well being painted

    /// The pipette showing now: one at a time, so it hops from well to well as the drag runs.
    private weak var lastPipette: CALayer?

    /// The well's own box (the same box the stain pops into), centred on the well.
    static func wellBox(cw: CGFloat, ch: CGFloat) -> CGSize { CGSize(width: cw - 5, height: ch - 5) }

    /// A pipette drawn inside the box of the well being painted, centred on the well exactly like the stain's
    /// pop, so it cannot sit over a neighbouring row or column. It settles in, dispenses (the drop falls from
    /// its tip) and fades; the next well's pipette takes over and this one goes at once.
    func pipetteDispense(at p: CGPoint, hex: String, cw: CGFloat, ch: CGFloat) {
        let root = space
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if let old = lastPipette {
            let o = old.presentation()?.opacity ?? 0
            old.removeAllAnimations()
            old.opacity = 0
            if o > 0.01 { old.run(frames("opacity", [o, 0], [0, 1], 0.08), "out") }
        }
        let box = Self.wellBox(cw: cw, ch: ch)
        let l = CALayer()
        l.bounds = CGRect(origin: .zero, size: box)
        l.contents = Self.image("pipWell\(hex)\(Int(box.width))x\(Int(box.height))", box) { c in
            Self.drawWellPipette(c, size: box, hex: hex)
        }
        l.position = p
        l.zPosition = 10                                  // above the stain's pop, which arrives after it
        l.opacity = 0
        root.addSublayer(l)
        let g = CAAnimationGroup()
        g.animations = [frames("position.y", [p.y - 3, p.y, p.y, p.y - 2], [0, 0.22, 0.7, 1], 0.55),
                        frames("opacity", [0, 1, 1, 0], [0, 0.16, 0.7, 1], 0.55)]
        g.duration = 0.55
        l.run(g, "pipette")
        lastPipette = l
        expire(l, after: 0.62)
    }

    /// Where the pipette's tip is, below the well's centre, as a fraction of the box's height.
    private static let tipBelowCentre: CGFloat = 0.22

    /// A single-channel pipette seen from the side, drawn in a well's box from its top edge to three quarters down: plunger, a
    /// metal body with the stain's colour band, and a frosted tip, outlined so it shows on a pale well too.
    private static func drawWellPipette(_ c: CGContext, size: CGSize, hex: String) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let u = size.height / 40                          // drawn for a 40-pt-tall box, scaled
        let mid = size.width / 2
        let tipY = size.height * (0.5 + tipBelowCentre)
        // plunger
        let plunger = CGRect(x: mid - 3 * u, y: 0.8 * u, width: 6 * u, height: 4.6 * u)
        c.addPath(CGPath(roundedRect: plunger, cornerWidth: 1.6 * u, cornerHeight: 1.6 * u, transform: nil))
        c.setFillColor(cg("D5DCE5")); c.fillPath()
        c.addPath(CGPath(roundedRect: plunger, cornerWidth: 1.6 * u, cornerHeight: 1.6 * u, transform: nil))
        c.setStrokeColor(cg("5F6B7C", 0.85)); c.setLineWidth(0.8 * u); c.strokePath()
        // body, shaded like a metal cylinder
        let body = CGRect(x: mid - 6.8 * u, y: 5 * u, width: 13.6 * u, height: 14 * u)
        let bodyPath = CGPath(roundedRect: body, cornerWidth: 3.5 * u, cornerHeight: 3.5 * u, transform: nil)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: 1.2 * u), blur: 2.5 * u, color: cg("000000", 0.35))
        c.addPath(bodyPath); c.setFillColor(cg("B7C2D0")); c.fillPath()
        c.restoreGState()
        c.saveGState(); c.addPath(bodyPath); c.clip()
        if let g = CGGradient(colorsSpace: space, colors: [cg("8F9BAC"), cg("F4F7FA"), cg("C3CCD8"), cg("7D899B")] as CFArray, locations: [0, 0.35, 0.65, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: body.minX, y: 0), end: CGPoint(x: body.maxX, y: 0), options: [])
        }
        c.setFillColor(cg(hex)); c.fill(CGRect(x: body.minX, y: 9.4 * u, width: body.width, height: 3.4 * u))   // the colour band
        c.restoreGState()
        c.addPath(bodyPath); c.setStrokeColor(cg("5F6B7C", 0.85)); c.setLineWidth(0.8 * u); c.strokePath()
        // the frosted tip, narrowing to the point, holding a bead of the stain
        let cone = CGMutablePath()
        cone.move(to: CGPoint(x: mid - 4.6 * u, y: body.maxY - 0.5 * u))
        cone.addLine(to: CGPoint(x: mid + 4.6 * u, y: body.maxY - 0.5 * u))
        cone.addLine(to: CGPoint(x: mid + 0.9 * u, y: tipY))
        cone.addLine(to: CGPoint(x: mid - 0.9 * u, y: tipY))
        cone.closeSubpath()
        c.addPath(cone); c.setFillColor(cg("F3F6FA", 0.95)); c.fillPath()
        c.setFillColor(cg(hex, 0.95))
        c.fillEllipse(in: CGRect(x: mid - 1.8 * u, y: tipY - 6 * u, width: 3.6 * u, height: 3.6 * u))
        c.addPath(cone); c.setStrokeColor(cg("5F6B7C", 0.85)); c.setLineWidth(0.8 * u); c.strokePath()
    }

    /// A drop from the pipette's tip over the well at `p`, into the well.
    func drop(at p: CGPoint, hex: String, cw: CGFloat, ch: CGFloat) {
        let root = space
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let box = Self.wellBox(cw: cw, ch: ch)
        let d = CALayer()
        d.bounds = CGRect(x: 0, y: 0, width: 6, height: 7.5)
        d.contents = Self.image("drop" + hex, CGSize(width: 8, height: 10)) { c in
            c.move(to: CGPoint(x: 4, y: 0))
            c.addQuadCurve(to: CGPoint(x: 8, y: 6.5), control: CGPoint(x: 8, y: 3))
            c.addArc(center: CGPoint(x: 4, y: 6.3), radius: 3.7, startAngle: 0, endAngle: .pi, clockwise: false)
            c.addQuadCurve(to: CGPoint(x: 4, y: 0), control: CGPoint(x: 0, y: 3))
            c.setFillColor(cg(hex)); c.fillPath()
            c.setFillColor(NSColor(white: 1, alpha: 0.7).cgColor); c.fillEllipse(in: CGRect(x: 2.2, y: 4.5, width: 1.6, height: 2))
        }
        let from = p.y + box.height * Self.tipBelowCentre + 2, to = p.y + box.height * 0.5 - 4
        d.position = CGPoint(x: p.x, y: to)
        d.zPosition = 11
        d.opacity = 0
        root.addSublayer(d)
        let g = CAAnimationGroup()
        g.animations = [frames("position.y", [from, from, to], [0, 0.35, 1], 0.3, .easeIn),
                        frames("opacity", [0, 1, 1, 0], [0, 0.3, 0.8, 1], 0.3)]
        g.duration = 0.3
        d.run(g, "fall")
        expire(d, after: 0.36)
    }

    /// A painted well: the stain pops into it, and a ring spreads out from it.
    func pop(at p: CGPoint, fill: String, accent: String, cw: CGFloat, ch: CGFloat) {
        let root = space
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let l = CALayer()
        l.bounds = CGRect(x: 0, y: 0, width: cw - 5, height: ch - 5)
        l.cornerRadius = 8
        l.backgroundColor = cg(fill)
        l.borderColor = cg(accent)
        l.borderWidth = 1.5
        l.position = p
        l.opacity = 0
        root.addSublayer(l)
        let g = CAAnimationGroup()
        g.animations = [frames("transform.scale", [0.3, 1.12, 1.0], [0, 0.6, 1], 0.32, .easeOut),
                        frames("opacity", [1, 1, 0], [0, 0.7, 1], 0.32)]
        g.duration = 0.32
        l.run(g, "pop")
        expire(l, after: 0.4)
        ripple(at: p, hex: accent, delay: 0.05, size: max(cw, ch) - 6)
    }
}

// MARK: - Lights down while the hologram plays

/// A faint veil over the rest of the window while the hologram scans, like a microscope room with the
/// lights lowered; it lifts as the hologram folds away. The fade is Core Animation's, so it glides
/// instead of redrawing the window frame by frame.
struct LightsDim: View {
    @ObservedObject var holo = HoloController.shared
    @EnvironmentObject var store: Store
    var body: some View {
        FadeVeil(on: holo.shown != nil && store.motion, alpha: 0.12, duration: 0.9).allowsHitTesting(false)
    }
}

struct FadeVeil: NSViewRepresentable {
    let on: Bool
    let alpha: Float
    let duration: Double
    func makeNSView(context: Context) -> FadeVeilView { FadeVeilView(frame: .zero) }
    func updateNSView(_ v: FadeVeilView, context: Context) { v.fade(on ? alpha : 0, duration) }
}

final class FadeVeilView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        layer?.backgroundColor = cg("02060D")
        layer?.opacity = 0
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func fade(_ to: Float, _ d: Double) {
        guard let l = layer, l.opacity != to else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(d)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        l.opacity = to
        CATransaction.commit()
    }
}

// MARK: - Spotlight on a stain's wells

/// Pointing at a stain's card or summary row: the other wells sink under a soft veil and the stain's own
/// wells get a glowing outline. Drawn as two shape layers and faded by Core Animation, instead of
/// animating all 96 wells in SwiftUI (which looked choppy).
struct SpotVeil: NSViewRepresentable {
    let wells: [Int]
    let hex: String
    let cw: CGFloat, ch: CGFloat
    let motion: Bool
    func makeNSView(context: Context) -> SpotVeilView { SpotVeilView(frame: .zero) }
    func updateNSView(_ v: SpotVeilView, context: Context) { v.show(wells, hex: hex, cw: cw, ch: ch, motion: motion) }
}

final class SpotVeilView: NSView {
    private let space = CALayer(), veil = CAShapeLayer(), rings = CAShapeLayer()
    private var shown: [Int] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        space.isGeometryFlipped = true
        layer?.addSublayer(space)
        veil.fillRule = .evenOdd
        veil.fillColor = cg("05090F", 0.42)
        rings.fillColor = nil
        rings.lineWidth = 2
        rings.shadowOpacity = 0.8
        rings.shadowRadius = 5
        rings.shadowOffset = .zero
        for l in [veil, rings] { l.opacity = 0; space.addSublayer(l) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        space.frame = bounds
        veil.frame = bounds; rings.frame = bounds
        CATransaction.commit()
    }

    func show(_ wells: [Int], hex: String, cw: CGFloat, ch: CGFloat, motion: Bool) {
        guard wells != shown else { return }
        shown = wells
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if !wells.isEmpty {
            let holes = CGMutablePath(), outlines = CGMutablePath()
            holes.addRect(CGRect(x: -2, y: -2, width: cw * 12 + 4, height: ch * 8 + 4))
            for w in wells {
                let r = CGRect(x: CGFloat(w % 12) * cw + 2.5, y: CGFloat(w / 12) * ch + 2.5, width: cw - 5, height: ch - 5)
                holes.addRoundedRect(in: r, cornerWidth: 8, cornerHeight: 8)
                outlines.addRoundedRect(in: r.insetBy(dx: -1, dy: -1), cornerWidth: 9, cornerHeight: 9)
            }
            veil.path = holes
            rings.path = outlines
            rings.strokeColor = cg(hex)
            rings.shadowColor = cg(hex)
        }
        CATransaction.commit()
        let to: Float = wells.isEmpty ? 0 : 1
        CATransaction.begin()
        CATransaction.setAnimationDuration(motion ? 0.35 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        veil.opacity = to; rings.opacity = to
        CATransaction.commit()
    }
}

/// A short shake, for the stain chip whose pairing has just gone wrong.
struct Shake: GeometryEffect {
    var amount: CGFloat = 5
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * 6), y: 0))
    }
}
