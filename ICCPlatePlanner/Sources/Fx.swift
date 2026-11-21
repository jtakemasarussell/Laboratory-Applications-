import SwiftUI
import AppKit
import QuartzCore

// MARK: - Effects across the window
//
// One transparent layer over the whole window carries the effects that travel between views: antibodies
// flying from a stain's card to its wells, frost melting off a plate that has just been opened, a red
// alarm running through the wells of a stain whose pairing has gone wrong, and a multichannel pipette
// dispensing into the wells as you paint. Every effect is a one-shot Core Animation animation handed to
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
    var cardAnchors: [UUID: Weak] = [:]
    final class Weak { weak var view: NSView?; init(_ v: NSView) { view = v } }

    /// `v`'s frame in the effects layer's (top-down) coordinates.
    private func rect(of v: NSView?) -> CGRect {
        guard let v, let fx = view, v.window != nil, v.window === fx.window else { return .zero }
        let r = fx.convert(v.bounds, from: v)
        return CGRect(x: r.minX, y: fx.bounds.height - r.maxY, width: r.width, height: r.height)
    }
    var gridFrame: CGRect { rect(of: gridAnchor) }
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
    enum Kind { case grid, card(UUID) }
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
            case .card(let id): FxCenter.shared.cardAnchors[id] = FxCenter.Weak(self)
            }
        }
        private func unregister() {
            switch kind {
            case .grid: if FxCenter.shared.gridAnchor === self { FxCenter.shared.gridAnchor = nil }
            case .card(let id): if FxCenter.shared.cardAnchors[id]?.view === self { FxCenter.shared.cardAnchors[id] = nil }
            }
        }
    }
}

extension View {
    /// Marks this view as the plate's grid.
    func fxGrid() -> some View { background(FxAnchor(kind: .grid)) }
    /// Marks this view as stain `id`'s card.
    func fxCard(_ id: UUID) -> some View { background(FxAnchor(kind: .card(id))) }
}

struct FxOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> FxView { FxView(frame: .zero) }
    func updateNSView(_ v: FxView, context: Context) { if v.window != nil { FxCenter.shared.view = v } }
}

private extension CALayer {
    func run(_ a: CAAnimation, _ key: String, delay: Double = 0) {
        a.beginTime = CACurrentMediaTime() + delay
        a.fillMode = .both
        a.isRemovedOnCompletion = true
        add(a, forKey: key)
    }
}

private func frames(_ path: String, _ values: [Any], _ times: [Double], _ d: Double, _ timing: CAMediaTimingFunctionName = .easeInEaseOut) -> CAKeyframeAnimation {
    let a = CAKeyframeAnimation(keyPath: path)
    a.values = values
    a.keyTimes = times.map { NSNumber(value: $0) }
    a.duration = d
    a.timingFunctions = Array(repeating: CAMediaTimingFunction(name: timing), count: max(1, values.count - 1))
    return a
}

final class FxView: NSView {
    private static var images: [String: CGImage?] = [:]
    private let pipette = CALayer()
    private var pipetteHex = ""
    /// Everything is drawn in this layer, laid out top-down like the SwiftUI views. (AppKit resets the
    /// flip on a view's own layer, which turned every effect upside down; a sublayer keeps it.)
    private let space = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        space.isGeometryFlipped = true
        layer?.addSublayer(space)
        pipette.opacity = 0
        pipette.anchorPoint = CGPoint(x: 0.5, y: 0)
        space.addSublayer(pipette)
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

    /// Development: where the pipette is, in the drawing layer.
    var pipetteDebug: String { "root flipped: \(layer?.isGeometryFlipped ?? false) · drawing layer flipped: \(space.isGeometryFlipped), effective top-down: \(space.contentsAreFlipped()) · pipette frame \(pipette.frame) anchor \(pipette.anchorPoint) position \(pipette.position) along row: \(lyingAlongRow)" }

    /// Development: the drawing layer's size against the view's.
    var spaceFrame: CGRect { space.frame }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // the effects layer in the window, kept the same way as the markers
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { FxCenter.shared.view = self } else if FxCenter.shared.view === self { FxCenter.shared.view = nil }
    }

    private static func image(_ key: String, _ size: CGSize, _ draw: (CGContext) -> Void) -> CGImage? {
        if let i = images[key] { return i }
        let i = renderImage(size, screenScale, draw)
        images[key] = i
        return i
    }

    /// Removes `l` once its animations are over.
    private func expire(_ l: CALayer, after: Double) {
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

    // MARK: the multichannel pipette while painting

    /// The 8-channel pipette over column `col` (tips over every row); `row` is the one dispensing.
    /// The well painted just before, to tell which way the drag runs; and which way the pipette lies now.
    private var lastCell: (col: Int, row: Int)?
    private var lyingAlongRow = true
    private var shownAlongRow: Bool?

    /// The multichannel over the wells being painted. It lies the way the drag runs: along a row (a tip over
    /// each column of that row) or down a column (a tip over each row of that column).
    func pipette(over grid: CGRect, col: Int, row: Int, cw: CGFloat, ch: CGFloat, hex: String) {
        if let last = lastCell, pipette.opacity > 0 {
            if last.row == row && last.col != col { lyingAlongRow = true }
            else if last.col == col && last.row != row { lyingAlongRow = false }
        }
        lastCell = (col, row)
        let along = lyingAlongRow
        let x = grid.minX + (CGFloat(col) + 0.5) * cw, y = grid.minY + (CGFloat(row) + 0.5) * ch
        let place = along ? CGPoint(x: grid.minX - 64, y: y) : CGPoint(x: x, y: grid.minY - 64)
        CATransaction.begin()
        if pipette.opacity == 0 || shownAlongRow != along || hex != pipetteHex {
            CATransaction.setDisableActions(true)
            let size = along ? CGSize(width: grid.width + 66, height: 46) : CGSize(width: 46, height: grid.height + 66)
            pipette.anchorPoint = along ? CGPoint(x: 0, y: 0.5) : CGPoint(x: 0.5, y: 0)
            pipette.bounds = CGRect(origin: .zero, size: size)
            pipette.position = place
            pipette.contents = along
                ? Self.image("pipH\(hex)\(Int(cw))x\(Int(grid.width))", size) { c in Self.drawPipetteAlongRow(c, size: size, cw: cw, hex: hex) }
                : Self.image("pipV\(hex)\(Int(ch))x\(Int(grid.height))", size) { c in Self.drawPipette(c, size: size, ch: ch, hex: hex) }
            if pipette.opacity == 0 {
                pipette.removeAnimation(forKey: "out")
                pipette.run(frames("opacity", [0, 0.92], [0, 1], 0.18), "in")
                pipette.opacity = 0.92
            }
            shownAlongRow = along
            pipetteHex = hex
        } else {
            CATransaction.setAnimationDuration(0.12)
            pipette.position = place
        }
        CATransaction.commit()
    }

    /// The pipette lying along a row: the head on the left, the manifold across the plate, and a tip centred
    /// over each of the twelve wells of the row.
    private static func drawPipetteAlongRow(_ c: CGContext, size: CGSize, cw: CGFloat, hex: String) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let mid = size.height / 2
        let gridLeft: CGFloat = 64                        // the grid's left edge in this picture
        c.setFillColor(cg("C9D2DE", 0.95)); c.fill(CGRect(x: 2, y: mid - 3.5, width: 14, height: 7))
        let head = CGRect(x: 14, y: mid - 14, width: 34, height: 28)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: 2), blur: 5, color: cg("000000", 0.35))
        c.addPath(CGPath(roundedRect: head, cornerWidth: 7, cornerHeight: 7, transform: nil)); c.setFillColor(cg("B7C2D0")); c.fillPath()
        c.restoreGState()
        c.saveGState(); c.addPath(CGPath(roundedRect: head, cornerWidth: 7, cornerHeight: 7, transform: nil)); c.clip()
        if let g = CGGradient(colorsSpace: space, colors: [cg("F4F7FA"), cg("C3CCD8"), cg("8F9BAC")] as CFArray, locations: [0, 0.55, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: head.minY), end: CGPoint(x: 0, y: head.maxY), options: [])
        }
        c.restoreGState()
        c.setFillColor(cg(hex)); c.fill(CGRect(x: 22, y: mid - 9, width: 4, height: 18))      // the colour band
        let bar = CGRect(x: head.maxX - 2, y: mid - 5, width: gridLeft + 12 * cw - head.maxX - cw * 0.5 + 2, height: 10)
        let barPath = CGPath(roundedRect: bar, cornerWidth: 5, cornerHeight: 5, transform: nil)
        c.saveGState(); c.addPath(barPath); c.clip()
        if let g = CGGradient(colorsSpace: space, colors: [cg("FFFFFF", 0.55), cg("DDE4EC", 0.35), cg("FFFFFF", 0.5)] as CFArray, locations: [0, 0.5, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: bar.minY), end: CGPoint(x: 0, y: bar.maxY), options: [])
        }
        c.restoreGState()
        c.addPath(barPath); c.setStrokeColor(cg("FFFFFF", 0.7)); c.setLineWidth(0.8); c.strokePath()
        for j in 0..<12 {
            let x = gridLeft + (CGFloat(j) + 0.5) * cw
            let nub = CGRect(x: x - 4, y: mid - 4, width: 8, height: 8)
            c.setFillColor(cg("F6F9FC", 0.95)); c.fillEllipse(in: nub)
            c.setStrokeColor(cg("8E9CAE", 0.9)); c.setLineWidth(0.8); c.strokeEllipse(in: nub)
            c.setFillColor(cg(hex)); c.fillEllipse(in: nub.insetBy(dx: 2.2, dy: 2.2))
        }
    }

    /// The pipette, seen from above: a head with its plunger and colour band, one frosted manifold running
    /// down the column, and a small tip centred over each of the eight wells, holding a bead of the stain.
    private static func drawPipette(_ c: CGContext, size: CGSize, ch: CGFloat, hex: String) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let mid = size.width / 2
        let gridTop: CGFloat = 64                         // the grid's top edge in this picture
        // plunger and head
        c.setFillColor(cg("C9D2DE", 0.95)); c.fill(CGRect(x: mid - 3.5, y: 2, width: 7, height: 14))
        let head = CGRect(x: mid - 14, y: 14, width: 28, height: 34)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: 2), blur: 5, color: cg("000000", 0.35))
        c.addPath(CGPath(roundedRect: head, cornerWidth: 7, cornerHeight: 7, transform: nil)); c.setFillColor(cg("B7C2D0")); c.fillPath()
        c.restoreGState()
        c.saveGState(); c.addPath(CGPath(roundedRect: head, cornerWidth: 7, cornerHeight: 7, transform: nil)); c.clip()
        if let g = CGGradient(colorsSpace: space, colors: [cg("F4F7FA"), cg("C3CCD8"), cg("8F9BAC")] as CFArray, locations: [0, 0.55, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: head.minX, y: 0), end: CGPoint(x: head.maxX, y: 0), options: [])
        }
        c.restoreGState()
        c.setFillColor(cg(hex)); c.fill(CGRect(x: mid - 9, y: 22, width: 18, height: 4))     // the colour band
        // one manifold, from the head to the last well, frosted and see-through
        let bar = CGRect(x: mid - 5, y: head.maxY - 2, width: 10, height: gridTop + 8 * ch - head.maxY - ch * 0.5 + 2)
        let barPath = CGPath(roundedRect: bar, cornerWidth: 5, cornerHeight: 5, transform: nil)
        c.saveGState(); c.addPath(barPath); c.clip()
        if let g = CGGradient(colorsSpace: space, colors: [cg("FFFFFF", 0.55), cg("DDE4EC", 0.35), cg("FFFFFF", 0.5)] as CFArray, locations: [0, 0.5, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: bar.minX, y: 0), end: CGPoint(x: bar.maxX, y: 0), options: [])
        }
        c.restoreGState()
        c.addPath(barPath); c.setStrokeColor(cg("FFFFFF", 0.7)); c.setLineWidth(0.8); c.strokePath()
        // a tip nub centred over each well, with a bead of stain
        for i in 0..<8 {
            let y = gridTop + (CGFloat(i) + 0.5) * ch
            let nub = CGRect(x: mid - 4, y: y - 4, width: 8, height: 8)
            c.setFillColor(cg("F6F9FC", 0.95)); c.fillEllipse(in: nub)
            c.setStrokeColor(cg("8E9CAE", 0.9)); c.setLineWidth(0.8); c.strokeEllipse(in: nub)
            c.setFillColor(cg(hex)); c.fillEllipse(in: nub.insetBy(dx: 2.2, dy: 2.2))
        }
    }

    /// A drop from the tip over `well` into it.
    func drop(at p: CGPoint, hex: String, ch: CGFloat) {
        let root = space
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let d = CALayer()
        d.bounds = CGRect(x: 0, y: 0, width: 8, height: 10)
        d.contents = Self.image("drop" + hex, CGSize(width: 8, height: 10)) { c in
            c.move(to: CGPoint(x: 4, y: 0))
            c.addQuadCurve(to: CGPoint(x: 8, y: 6.5), control: CGPoint(x: 8, y: 3))
            c.addArc(center: CGPoint(x: 4, y: 6.3), radius: 3.7, startAngle: 0, endAngle: .pi, clockwise: false)
            c.addQuadCurve(to: CGPoint(x: 4, y: 0), control: CGPoint(x: 0, y: 3))
            c.setFillColor(cg(hex)); c.fillPath()
            c.setFillColor(NSColor(white: 1, alpha: 0.7).cgColor); c.fillEllipse(in: CGRect(x: 2.2, y: 4.5, width: 1.6, height: 2))
        }
        d.position = p
        d.opacity = 0
        root.addSublayer(d)
        let g = CAAnimationGroup()
        g.animations = [frames("position.y", [p.y - ch * 0.42, p.y], [0, 1], 0.22, .easeIn),
                        frames("opacity", [1, 1, 0], [0, 0.85, 1], 0.22)]
        g.duration = 0.22
        d.run(g, "fall")
        expire(d, after: 0.3)
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

    func pipetteAway() {
        lastCell = nil
        guard pipette.opacity > 0 else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        pipette.run(frames("opacity", [0.92, 0], [0, 1], 0.35), "out")
        pipette.opacity = 0
        CATransaction.commit()
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
