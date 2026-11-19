import SwiftUI
import AppKit
import QuartzCore

// MARK: - Always-on motion, without the lag
//
// Core Animation and SwiftUI timelines redraw at the display's full rate (120 Hz on a ProMotion
// screen), which keeps the window server busy even for a small moving strip. The always-on motion
// (the banner helix, the glints over stained wells, the staining preview) is therefore drawn into
// images once; one shared clock then only moves and fades those images, 20 times a second, in a single
// transaction, and it stops whenever the app is in the background or Animations is off.

func renderImage(_ size: CGSize, _ scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage? {
    let w = max(1, Int(ceil(size.width * scale))), h = max(1, Int(ceil(size.height * scale)))
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    // drawn top-down, like a view
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()
}

let screenScale: CGFloat = NSScreen.screens.map { $0.backingScaleFactor }.max() ?? 2

extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        let v = UInt32(hex, radix: 16) ?? 0xCCCCCC
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }
}

func cg(_ hex: String, _ a: CGFloat = 1) -> CGColor { NSColor(hex: hex, alpha: a).cgColor }

/// Draws text top-down at `p` (its top-left corner, or top-right when `right`).
func drawText(_ s: String, _ p: CGPoint, _ size: CGFloat, _ color: NSColor, weight: NSFont.Weight = .regular,
              mono: Bool = false, serif: Bool = false, right: Bool = false, center: Bool = false, tracking: CGFloat = 0) {
    var font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    if serif, let d = font.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { font = f }
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: tracking]
    let w = (s as NSString).size(withAttributes: attrs).width
    let x = right ? p.x - w : (center ? p.x - w / 2 : p.x)
    (s as NSString).draw(at: CGPoint(x: x, y: p.y), withAttributes: attrs)
}

func textWidth(_ s: String, _ size: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
    (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width
}

// MARK: One slow clock

protocol AmbientClient: AnyObject {
    /// Whether this view wants to move right now (animations on and the app in front).
    var ambientActive: Bool { get }
    func tick(_ dt: Double)
}

final class AmbientClock {
    static let shared = AmbientClock()
    static let fps = 20.0
    private final class Box { weak var client: AmbientClient?; init(_ c: AmbientClient) { client = c } }
    private var boxes: [Box] = []
    private var timer: Timer?
    private var last: CFTimeInterval = 0

    func add(_ c: AmbientClient) { boxes.removeAll { $0.client == nil || $0.client === c }; boxes.append(Box(c)); update() }
    func remove(_ c: AmbientClient) { boxes.removeAll { $0.client == nil || $0.client === c }; update() }

    /// Runs only while at least one view on screen wants to move.
    func update() {
        let want = boxes.contains { $0.client?.ambientActive == true }
        if want, timer == nil {
            last = CACurrentMediaTime()
            let t = Timer(timeInterval: 1 / Self.fps, repeats: true) { [weak self] _ in self?.fire() }
            t.tolerance = 0.005
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !want, let t = timer {
            t.invalidate(); timer = nil
        }
    }

    /// Development: told how long each tick took, in milliseconds (the lag check).
    static var probe: ((Double) -> Void)?

    private func fire() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - last)
        last = now
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for b in boxes where b.client?.ambientActive == true { b.client?.tick(dt) }
        CATransaction.commit()
        if let p = Self.probe { p((CACurrentMediaTime() - now) * 1000) }
    }
}

/// A layer-hosting view on the shared clock.
class AmbientLayerView: NSView, AmbientClient {
    var ambientActive = false {
        didSet {
            guard ambientActive != oldValue else { return }
            if !ambientActive { rest() }
            AmbientClock.shared.update()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()           // layer-hosting: this view owns its layer tree
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { AmbientClock.shared.add(self) } else { AmbientClock.shared.remove(self) }
    }

    /// Clicks and drags go to whatever is underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func tick(_ dt: Double) {}
    /// The still picture shown while paused.
    func rest() {}
}

// MARK: - Banner: a DNA helix turning
//
// Turning the helix is the same as sliding it sideways by its own pitch, so it is drawn once, a pitch
// wider than the strip, and the clock only slides it; a mask fades both ends.

final class HelixLaneView: AmbientLayerView {
    private let strip = CALayer()
    private let fade = CAGradientLayer()
    private var built: CGSize = .zero
    private var phase = 0.0
    static let pitch: CGFloat = 78
    static let speed = 1.1 * 78 / (2 * Double.pi)     // points a second: the old 1.1 rad/s turn

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.addSublayer(strip)
        strip.anchorPoint = .zero
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor(white: 1, alpha: 0).cgColor, NSColor.white.cgColor, NSColor.white.cgColor, NSColor(white: 1, alpha: 0).cgColor]
        layer?.mask = fade
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard bounds.size != built, bounds.width > 30 else { return }
        built = bounds.size
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fade.frame = bounds
        let edge = NSNumber(value: Double(min(0.3, 40 / bounds.width)))
        fade.locations = [0, edge, NSNumber(value: 1 - edge.doubleValue), 1]
        let size = CGSize(width: bounds.width + Self.pitch, height: bounds.height)
        strip.bounds = CGRect(origin: .zero, size: size)
        strip.contents = Self.draw(size)
        place()
        CATransaction.commit()
    }

    private static func draw(_ size: CGSize) -> CGImage? {
        renderImage(size, screenScale) { c in
            let mid = size.height / 2, amp = size.height * 0.36
            let k = 2 * Double.pi / Double(pitch)
            for (strand, alpha) in [(1.0, 0.75), (-1.0, 0.45)] {
                c.beginPath()
                var x = 0.0
                while x <= Double(size.width) {
                    let p = CGPoint(x: x, y: mid + amp * strand * sin(k * x))
                    if x == 0 { c.move(to: p) } else { c.addLine(to: p) }
                    x += 1.5
                }
                c.setStrokeColor(NSColor(white: 1, alpha: alpha).cgColor)
                c.setLineWidth(1.8); c.setLineCap(.round)
                c.strokePath()
            }
            // base pairs: rungs and two beads whose size and brightness follow which strand is in front
            var x = 6.0
            while x <= Double(size.width) {
                let s = sin(k * x), depth = cos(k * x)
                c.setStrokeColor(NSColor(white: 1, alpha: 0.22).cgColor)
                c.setLineWidth(1.2)
                c.strokeLineSegments(between: [CGPoint(x: x, y: mid + amp * s), CGPoint(x: x, y: mid - amp * s)])
                let r1 = 2.0 + 1.3 * depth, r2 = 2.0 - 1.3 * depth
                c.setFillColor(cg("9FE3B0", 0.45 + 0.4 * depth))
                c.fillEllipse(in: CGRect(x: x - r1, y: mid + amp * s - r1, width: 2 * r1, height: 2 * r1))
                c.setFillColor(cg("FFD27A", 0.45 - 0.4 * depth))
                c.fillEllipse(in: CGRect(x: x - r2, y: mid - amp * s - r2, width: 2 * r2, height: 2 * r2))
                x += Double(pitch) / 6
            }
        }
    }

    private func place() {
        let shift = CGFloat(phase.truncatingRemainder(dividingBy: Double(Self.pitch)))
        strip.position = CGPoint(x: -shift, y: 0)
    }

    override func tick(_ dt: Double) {
        phase += dt * Self.speed
        place()
    }
}

struct HelixLane: NSViewRepresentable {
    let active: Bool
    func makeNSView(context: Context) -> HelixLaneView { HelixLaneView(frame: .zero) }
    func updateNSView(_ v: HelixLaneView, context: Context) { v.ambientActive = active }
}

// MARK: - Glints over stained wells
//
// A soft highlight sweeps diagonally across the stained wells every few seconds, like signal coming
// into focus. Each stained well has one small layer with the glint drawn once; the clock only fades them.

final class GlintLaneView: AmbientLayerView {
    var cw: CGFloat = 48, ch: CGFloat = 44
    private var glints: [Int: CALayer] = [:]
    private var clock = 2.0
    private var image: CGImage?
    private var imageSize: CGSize = .zero

    func setStained(_ wells: [Int]) {
        let want = Set(wells)
        guard want != Set(glints.keys) else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (w, l) in glints where !want.contains(w) { l.removeFromSuperlayer(); glints[w] = nil }
        let size = CGSize(width: cw - 2, height: ch - 2)
        if image == nil || imageSize != size {
            imageSize = size
            image = renderImage(size, screenScale) { c in
                let r = CGRect(x: 3, y: 3, width: size.width - 6, height: size.height - 6)
                let space = CGColorSpace(name: CGColorSpace.sRGB)!
                c.saveGState()
                c.addPath(CGPath(roundedRect: r, cornerWidth: 8, cornerHeight: 8, transform: nil)); c.clip()
                if let g = CGGradient(colorsSpace: space, colors: [NSColor(white: 1, alpha: 0.75).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1]) {
                    let ctr = CGPoint(x: r.midX - 4, y: r.midY - 4)
                    c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: size.width * 0.55, options: [])
                }
                c.restoreGState()
                c.setStrokeColor(NSColor(white: 1, alpha: 0.85).cgColor)
                c.setLineWidth(1.5)
                c.addPath(CGPath(roundedRect: r.insetBy(dx: -1.5, dy: -1.5), cornerWidth: 9, cornerHeight: 9, transform: nil))
                c.strokePath()
            }
        }
        for w in want where glints[w] == nil {
            let l = CALayer()
            l.contents = image
            l.opacity = 0
            layer?.addSublayer(l)
            glints[w] = l
        }
        placeAll()
        CATransaction.commit()
        if ambientActive { tick(0) }
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        placeAll()
        CATransaction.commit()
    }

    private func placeAll() {
        let H = bounds.height
        for (w, l) in glints {
            let row = CGFloat(w / 12), col = CGFloat(w % 12)
            // layer coordinates run upwards
            l.frame = CGRect(x: col * cw + 1, y: H - (row + 1) * ch + 1, width: cw - 2, height: ch - 2)
        }
    }

    override func tick(_ dt: Double) {
        clock += dt
        let sweep = (clock.truncatingRemainder(dividingBy: 6.5) / 6.5) * 22 - 3
        for (w, l) in glints {
            let phase = sweep - (Double(w % 12) + Double(w / 12) * 0.7)
            let glow = Float(exp(-phase * phase / 1.6))
            let o: Float = glow > 0.02 ? glow : 0
            if abs(l.opacity - o) > 0.004 { l.opacity = o }
        }
    }

    override func rest() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for l in glints.values { l.opacity = 0 }
        CATransaction.commit()
    }
}

struct GlintLane: NSViewRepresentable {
    let stained: [Int]
    let cw: CGFloat, ch: CGFloat
    let active: Bool
    func makeNSView(context: Context) -> GlintLaneView {
        let v = GlintLaneView(frame: .zero)
        v.cw = cw; v.ch = ch
        return v
    }
    func updateNSView(_ v: GlintLaneView, context: Context) {
        v.setStained(stained)
        v.ambientActive = active && !stained.isEmpty
    }
}

// MARK: - The blocking-buffer tube
//
// The tube is drawn once; the clock only reshapes the liquid's surface and moves three bubbles.

final class TubeLaneView: AmbientLayerView {
    var fraction = 0.3 { didSet { if fraction != oldValue { placeLiquid() } } }
    private let outline = CALayer()
    private let inside = CALayer(), insideMask = CAShapeLayer()
    private let liquid = CAGradientLayer(), surface = CAShapeLayer()
    private var bubbles: [CALayer] = []
    private var built: CGSize = .zero
    private var clock = 0.0
    // geometry, top-down
    private var x0: CGFloat = 0, w: CGFloat = 0, top: CGFloat = 0, bottom: CGFloat = 0, level: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.addSublayer(inside)
        inside.mask = insideMask
        inside.addSublayer(liquid)
        liquid.mask = surface
        liquid.colors = [cg("7FB0E8"), cg("1E4A83")]
        for i in 0..<3 {
            let b = CALayer()
            let r = 1.1 + 0.4 * CGFloat(i % 2)
            b.bounds = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)
            b.cornerRadius = r
            b.backgroundColor = NSColor(white: 1, alpha: 0.7).cgColor
            inside.addSublayer(b)
            bubbles.append(b)
        }
        layer?.addSublayer(outline)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func up(_ y: CGFloat) -> CGFloat { bounds.height - y }

    private func tubePath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x0, y: up(top)))
        p.addLine(to: CGPoint(x: x0, y: up(bottom - w / 2)))
        p.addArc(center: CGPoint(x: x0 + w / 2, y: up(bottom - w / 2)), radius: w / 2, startAngle: .pi, endAngle: 0, clockwise: false)
        p.addLine(to: CGPoint(x: x0 + w, y: up(top)))
        return p
    }

    override func layout() {
        super.layout()
        guard bounds.size != built, bounds.width > 4 else { return }
        built = bounds.size
        let W = bounds.width, H = bounds.height
        w = W * 0.46; x0 = (W - w) / 2; top = H * 0.10; bottom = H * 0.92
        CATransaction.begin(); CATransaction.setDisableActions(true)
        inside.frame = bounds
        let closed = tubePath().mutableCopy()!
        closed.closeSubpath()
        insideMask.path = closed
        outline.frame = bounds
        outline.contents = renderImage(bounds.size, screenScale) { c in
            c.setStrokeColor(cg("1E4A83")); c.setLineWidth(1.6); c.setLineCap(.round); c.setLineJoin(.round)
            c.move(to: CGPoint(x: x0, y: top))
            c.addLine(to: CGPoint(x: x0, y: bottom - w / 2))
            c.addArc(center: CGPoint(x: x0 + w / 2, y: bottom - w / 2), radius: w / 2, startAngle: .pi, endAngle: 0, clockwise: true)
            c.addLine(to: CGPoint(x: x0 + w, y: top))
            c.strokePath()
            c.setLineWidth(1.8)
            c.strokeLineSegments(between: [CGPoint(x: x0 - 2.5, y: top), CGPoint(x: x0 + w + 2.5, y: top)])
        }
        placeLiquid()
        CATransaction.commit()
    }

    private func placeLiquid() {
        guard built != .zero else { return }
        let f = CGFloat(max(0.06, min(fraction, 1)))
        level = bottom - (bottom - top - 3) * f
        CATransaction.begin(); CATransaction.setDisableActions(true)
        liquid.frame = CGRect(x: x0 - 2, y: up(bottom + 2), width: w + 4, height: bottom - level + 6)
        liquid.startPoint = CGPoint(x: 0.5, y: 1); liquid.endPoint = CGPoint(x: 0.5, y: 0)
        drawSurface()
        CATransaction.commit()
    }

    /// The liquid's wavy top, in the liquid layer's own coordinates.
    private func drawSurface() {
        let p = CGMutablePath()
        let h = liquid.bounds.height
        p.move(to: CGPoint(x: 0, y: 0))
        var x: CGFloat = 0
        while x <= w + 4 {
            let y = (bottom + 2 - level) - 1.3 * CGFloat(sin(Double((x - 2) / w) * 2 * .pi + clock * 2.4))
            p.addLine(to: CGPoint(x: x, y: min(h, y)))
            x += 1.5
        }
        p.addLine(to: CGPoint(x: w + 4, y: 0))
        p.closeSubpath()
        surface.path = p
    }

    override func tick(_ dt: Double) {
        guard built != .zero else { return }
        clock += dt
        drawSurface()
        for (i, b) in bubbles.enumerated() {
            let p = (clock * 0.35 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
            let by = bottom - 3 - (bottom - level - 4) * CGFloat(p)
            let bx = x0 + w * (0.3 + 0.2 * CGFloat(i)) + 1.2 * CGFloat(sin(clock * 2 + Double(i)))
            b.position = CGPoint(x: bx, y: up(by))
            b.opacity = by > level + 2 ? 1 : 0
        }
    }

    override func rest() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for b in bubbles { b.opacity = 0 }
        CATransaction.commit()
    }
}

struct TubeLane: NSViewRepresentable {
    let fraction: Double
    let active: Bool
    func makeNSView(context: Context) -> TubeLaneView { TubeLaneView(frame: .zero) }
    func updateNSView(_ v: TubeLaneView, context: Context) {
        v.fraction = fraction
        v.ambientActive = active
    }
}

// MARK: - Antibodies waiting on an empty plate

final class DoodleLaneView: AmbientLayerView {
    private struct Ab { let holder: CALayer; let tip: CALayer; let fx: CGFloat; let phase: Double }
    private var abs: [Ab] = []
    private var clock = 0.0

    override init(frame: NSRect) {
        super.init(frame: frame)
        let specs: [(CGFloat, String, String, Double)] = [(0.2, "1E4A83", "3DDC6E", 0.0), (0.5, "4A78B8", "FF6B5A", 1.7), (0.8, "1E4A83", "6FA8FF", 3.1)]
        for (fx, body, tip, phase) in specs {
            let holder = CALayer()
            holder.bounds = CGRect(x: 0, y: 0, width: 26, height: 40)
            let y = CALayer()
            y.frame = holder.bounds
            y.contents = renderImage(holder.bounds.size, screenScale) { c in
                c.setStrokeColor(cg(body)); c.setLineWidth(3.2); c.setLineCap(.round); c.setLineJoin(.round)
                c.move(to: CGPoint(x: 13, y: 31)); c.addLine(to: CGPoint(x: 13, y: 17)); c.addLine(to: CGPoint(x: 4, y: 4))
                c.move(to: CGPoint(x: 13, y: 17)); c.addLine(to: CGPoint(x: 22, y: 4))
                c.strokePath()
            }
            let t = CALayer()
            t.bounds = CGRect(x: 0, y: 0, width: 12, height: 12)
            t.position = CGPoint(x: 13, y: 40 - 34)
            t.contents = renderImage(CGSize(width: 12, height: 12), screenScale) { c in
                let space = CGColorSpace(name: CGColorSpace.sRGB)!
                if let g = CGGradient(colorsSpace: space, colors: [cg(tip, 0.95), cg(tip, 0)] as CFArray, locations: [0, 1]) {
                    c.drawRadialGradient(g, startCenter: CGPoint(x: 6, y: 6), startRadius: 0, endCenter: CGPoint(x: 6, y: 6), endRadius: 6, options: [])
                }
            }
            holder.addSublayer(y)
            holder.addSublayer(t)
            layer?.addSublayer(holder)
            abs.append(Ab(holder: holder, tip: t, fx: fx, phase: phase))
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        tick(0)
        CATransaction.commit()
    }

    override func tick(_ dt: Double) {
        clock += dt
        let t = clock
        for a in abs {
            let x = bounds.width * a.fx + 4 * CGFloat(sin(t * 0.9 + a.phase))
            let y = bounds.height / 2 + 2 - 5 * CGFloat(sin(t * 1.3 + a.phase))
            a.holder.position = CGPoint(x: x, y: y)
            a.holder.setAffineTransform(CGAffineTransform(rotationAngle: -0.22 * CGFloat(sin(t * 0.8 + a.phase))))
            let glow = 0.5 + 0.5 * sin(t * 2.2 + a.phase)
            let s = CGFloat((3.0 + 2.2 * glow) / 5.2)
            a.tip.setAffineTransform(CGAffineTransform(scaleX: s, y: s))
        }
    }
}

struct DoodleLane: NSViewRepresentable {
    let active: Bool
    func makeNSView(context: Context) -> DoodleLaneView { DoodleLaneView(frame: .zero) }
    func updateNSView(_ v: DoodleLaneView, context: Context) { v.ambientActive = active }
}
