import SwiftUI
import AppKit
import QuartzCore

// MARK: - Ambient animation: Eppi and the banner curves
//
// Everything is drawn once at launch (Eppi's walk is a flip-book of frames made with the same drawing
// code as before); between frames the app only moves layers and swaps images.

func renderImage(_ size: CGSize, _ scale: CGFloat, _ draw: (Pen) -> Void) -> CGImage? {
    let w = Int(size.width * scale), h = Int(size.height * scale)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw(Pen(c: ctx))
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()
}

let screenScale: CGFloat = NSScreen.screens.map { $0.backingScaleFactor }.max() ?? 2

/// Eppi's frames, drawn once.
private enum Sprites {
    static let size = CGSize(width: 120, height: 170)

    static func frame(_ pose: EppiPose) -> CGImage? { renderImage(size, screenScale) { paintEppi($0, pose) } }

    /// Two strides; legs, arms, bob, lid, slosh and bubbles all loop seamlessly.
    static let walk: [CGImage] = (0..<36).compactMap { i in
        let u = Double(i) / 36
        var p = EppiPose()
        p.walk = u * 4 * .pi
        p.moving = true
        p.lift = CGFloat(abs(sin(p.walk)) * 3.5)
        p.lid = 0.1 + 0.18 * abs(sin(p.walk * 0.5))
        p.ripple = u * 4 * .pi
        p.bubbles = u
        return frame(p)
    }
    static let wave: [CGImage] = (0..<12).compactMap { i in
        let u = Double(i) / 12
        var p = EppiPose()
        p.moving = false
        p.waving = true
        p.wavePhase = u * 2 * .pi
        p.mouthOpen = true
        p.lid = 0.22
        p.blink = i == 6
        p.ripple = u * 2 * .pi
        p.bubbles = u
        return frame(p)
    }
    static func event(_ mood: EppiMood) -> [CGImage] {
        (0..<24).compactMap { i in
            let u = Double(i) / 24
            var p = EppiPose()
            p.moving = false
            p.mouthOpen = true
            p.t = u * 2.5
            p.ripple = u * 4 * .pi
            p.bubbles = u
            switch mood {
            case .jump: p.armsUp = 1; p.lid = 0.15 + 1.1 * sin(.pi * u)
            case .dance: p.armsUp = 0.5 + 0.5 * sin(u * 4 * .pi); p.lid = 0.3 + 0.6 * abs(sin(u * 4 * .pi)); p.notes = true
            case .cheer: p.armsUp = 1; p.lid = 1.2; p.sparkle = true; p.t = u * .pi
            }
            return frame(p)
        }
    }
    static let jump = event(.jump), dance = event(.dance), cheer = event(.cheer)
}

/// Eppi waving, for the splash.
func eppiWaveFrames() -> [CGImage] { Sprites.wave }

private func bubbleImage(_ text: String) -> (CGImage?, CGSize) {
    let font = NSFont.systemFont(ofSize: 13, weight: .bold)
    let t = (text as NSString).size(withAttributes: [.font: font])
    let size = CGSize(width: t.width + 70, height: t.height + 50)
    let img = renderImage(size, screenScale) { pen in
        _ = paintBubble(pen, text, bottom: CGPoint(x: size.width / 2, y: size.height - 8), pop: 1)
    }
    return (img, size)
}

// MARK: - One slow clock
//
// Core Animation always redraws at the display's full rate (120 Hz on a ProMotion screen), which keeps
// the window server busy even for a tiny moving strip. Ambient motion instead advances on one shared
// clock, 20 times a second, in a single transaction, and stops while the app is in the background.

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

    /// Development: told how long each tick took, in milliseconds (--lag-check).
    static var probe: ((Double) -> Void)?

    private func fire() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - last)
        last = now
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for b in boxes where b.client?.ambientActive == true { b.client?.tick(dt) }
        CATransaction.commit()
        Self.probe?((CACurrentMediaTime() - now) * 1000)
    }
}

/// Pop-in, hold, fade-out for a speech bubble `age` seconds into a `life`-second showing.
private func pop(_ layer: CALayer, age: Double, life: Double) {
    let s: Double = age < 0.18 ? 0.3 + 0.82 * age / 0.18 : (age < 0.3 ? 1.12 - 0.12 * (age - 0.18) / 0.12 : 1)
    let o: Double = age < 0.15 ? age / 0.15 : (age > life - 0.25 ? max(0, (life - age) / 0.25) : 1)
    layer.setAffineTransform(CGAffineTransform(scaleX: s, y: s))
    layer.opacity = Float(o)
}

// MARK: - Eppi

final class EppiLaneView: NSView, AmbientClient {
    var onClick: (() -> Void)?
    private let stage = CALayer()
    private let walker = CALayer()      // moves along the lane
    private let flipper = CALayer()     // faces the way Eppi walks
    private let sprite = CALayer()      // the drawing; jumps and spins for events
    private let quipBubble = CALayer(), eventBubble = CALayer()
    private var quip = Int.random(in: 0..<eppiQuips.count)
    private var walkClock = 0.0         // stands still while Eppi celebrates
    private var segment = -1
    private var event: (e: EppiEvent, age: Double)?
    private var lastEvent: UUID?
    var ambientActive = false { didSet { if ambientActive != oldValue { AmbientClock.shared.update() } } }

    private let speed = 64.0, margin = 70.0, standT = 3.6

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()                 // layer-hosting: this view owns its layer tree
        wantsLayer = true
        layer?.addSublayer(stage)
        stage.addSublayer(walker)
        walker.addSublayer(flipper)
        flipper.addSublayer(sprite)
        walker.anchorPoint = CGPoint(x: 0.5, y: 0)
        walker.bounds = CGRect(origin: .zero, size: Sprites.size)
        flipper.frame = walker.bounds
        sprite.frame = flipper.bounds
        sprite.contents = Sprites.walk.first
        for b in [quipBubble, eventBubble] {
            walker.addSublayer(b)
            b.anchorPoint = CGPoint(x: 0.5, y: 0)
            b.opacity = 0
        }
        walkClock = Double.random(in: 0..<8)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { AmbientClock.shared.add(self) } else { AmbientClock.shared.remove(self) }
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        stage.frame = bounds
        tick(0)         // place Eppi even while the clock is stopped
        CATransaction.commit()
    }

    private func setBubble(_ b: CALayer, _ text: String, x: CGFloat, y: CGFloat) {
        let (img, size) = bubbleImage(text)
        b.setAffineTransform(.identity)
        b.bounds = CGRect(origin: .zero, size: size)
        b.position = CGPoint(x: Sprites.size.width / 2 + x, y: y)
        b.contents = img
    }

    func tick(_ dt: Double) {
        let W = Double(bounds.width)
        guard W > 300 else { return }
        let span = W - 2 * margin, walkT = span / speed
        let loop = 2 * walkT + 2 * standT

        if var ev = event {
            ev.age += dt
            event = ev.age < max(ev.e.duration, 3.2) ? ev : nil
        }
        let celebrating = event.map { $0.age < $0.e.duration } ?? false
        if !celebrating { walkClock += dt }

        let phase = walkClock.truncatingRemainder(dividingBy: loop)
        let seg: Int, local: Double
        if phase < walkT { seg = 0; local = phase }
        else if phase < walkT + standT { seg = 1; local = phase - walkT }
        else if phase < 2 * walkT + standT { seg = 2; local = phase - walkT - standT }
        else { seg = 3; local = phase - 2 * walkT - standT }

        let x = [margin + span * local / walkT, W - margin, W - margin - span * local / walkT, margin][seg]
        walker.position = CGPoint(x: x, y: 0)
        flipper.setAffineTransform(CGAffineTransform(scaleX: seg < 2 ? 1 : -1, y: 1))

        var dy = 0.0, rot = 0.0
        if let ev = event, ev.age < ev.e.duration {
            let a = ev.age, d = ev.e.duration
            let frames: [CGImage]
            switch ev.e.mood {
            case .jump:
                frames = Sprites.jump
                let u = a / d
                if u < 0.64 { dy = 80 * sin(.pi * u / 0.64); rot = -2 * .pi * (0.5 - 0.5 * cos(.pi * u / 0.64)) }
                else { dy = 10 * sin(.pi * (u - 0.64) / 0.36) }
            case .dance:
                frames = Sprites.dance
                dy = 18 * abs(sin(a * 7)); rot = 0.3 * sin(a * 7)
            case .cheer:
                frames = Sprites.cheer
                dy = 40 * abs(sin(a * 6)) * max(0, 1 - a / d)
            }
            sprite.contents = frames[Int(a * 16) % frames.count]
        } else if seg % 2 == 0 {
            sprite.contents = Sprites.walk[Int(local * 24) % Sprites.walk.count]
        } else {
            sprite.contents = Sprites.wave[Int(local * 16) % Sprites.wave.count]
        }
        sprite.position = CGPoint(x: Sprites.size.width / 2, y: Sprites.size.height / 2 + dy)
        sprite.setAffineTransform(CGAffineTransform(rotationAngle: rot))

        // a quip while standing at each end of the lane
        if seg != segment {
            segment = seg
            if seg % 2 == 1 {
                setBubble(quipBubble, eppiQuips[quip % eppiQuips.count], x: seg == 1 ? -110 : 110, y: 150)
                quip += 1
            }
        }
        if seg % 2 == 1, event == nil { pop(quipBubble, age: local, life: standT) } else { quipBubble.opacity = 0 }

        if let ev = event { pop(eventBubble, age: ev.age, life: max(ev.e.duration, 3.2)) } else { eventBubble.opacity = 0 }
    }

    /// Jumps, dances or cheers, with a speech bubble.
    func play(_ e: EppiEvent) {
        guard e.id != lastEvent else { return }
        lastEvent = e.id
        let delay = max(0, e.date.timeIntervalSinceNow)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.start(e) }
    }

    private func start(_ e: EppiEvent) {
        guard ambientActive else { return }
        let x = walker.position.x
        let nudge: CGFloat = x < 200 ? 120 : (x > bounds.width - 200 ? -120 : 0)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        setBubble(eventBubble, e.text, x: nudge, y: 150 + (e.mood == .jump ? 30 : 10))
        eventBubble.opacity = 0
        CATransaction.commit()
        event = (e, 0)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let f = walker.frame
        let body = CGRect(x: f.midX - 30, y: f.minY, width: 60, height: 140)
        return body.contains(local) ? self : nil
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct EppiLane: NSViewRepresentable {
    let store: Store
    let event: EppiEvent?
    let active: Bool

    func makeNSView(context: Context) -> EppiLaneView {
        let v = EppiLaneView(frame: .zero)
        v.onClick = { [weak store] in store?.pokeEppi() }
        return v
    }

    func updateNSView(_ v: EppiLaneView, context: Context) {
        v.ambientActive = active
        if let e = event, active { v.play(e) }
    }
}

// MARK: - Banner: amplification curves drawing themselves
//
// The curves are drawn once into an image; a clip that widens from left to right reveals them, the
// way a real run adds one cycle after another, with a glow riding the front of each curve.

final class BannerLaneView: NSView, AmbientClient {
    private let stage = CALayer()
    private let axes = CALayer(), reveal = CALayer(), curves = CALayer()
    private var dots: [CALayer] = []
    private var built: CGSize = .zero
    private var clock = 4.6     // open on finished curves, then fade and start a new run
    private var shown: (width: CGFloat, opacity: Float, dots: Bool) = (-1, -1, true)
    var ambientActive = false {
        didSet {
            guard ambientActive != oldValue else { return }
            if !ambientActive { showFinished() }
            AmbientClock.shared.update()
        }
    }

    /// While paused, the banner shows a finished run rather than whatever frame it stopped on.
    private func showFinished() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        reveal.bounds.size.width = bounds.width
        reveal.opacity = 1
        for d in dots { d.opacity = 0 }
        CATransaction.commit()
        clock = Self.drawT
        shown = (-1, -1, true)
    }

    private static let colors = ["8CF5A4", "FF9A86", "9CCBFF", "FFD86B"]
    private static let mids = [0.30, 0.44, 0.58, 0.72], tops = [0.88, 0.8, 0.7, 0.6]
    private static let drawT = 4.6, holdT = 5.3, fadeT = 6.3, period = 7.3

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        layer?.addSublayer(stage)
        stage.addSublayer(axes)
        reveal.anchorPoint = .zero
        reveal.position = .zero
        reveal.masksToBounds = true
        curves.anchorPoint = .zero
        reveal.addSublayer(curves)
        stage.addSublayer(reveal)
        for _ in 0..<4 {
            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
            dot.contents = Self.glow
            stage.addSublayer(dot)
            dots.append(dot)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { AmbientClock.shared.add(self) } else { AmbientClock.shared.remove(self) }
    }

    override func layout() {
        super.layout()
        if bounds.size != built { build() }
    }

    /// Height of curve k at x, measured upwards from the bottom of the lane.
    private static func curveY(_ k: Int, _ x: Double, _ w: Double, _ h: Double) -> Double {
        8 + tops[k] / (1 + exp(-(x / w - mids[k]) * 16)) * (h - 14)
    }

    private static let glow: CGImage? = renderImage(CGSize(width: 22, height: 22), screenScale) { pen in
        let c = pen.c
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [NSColor(white: 1, alpha: 0.75).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            c.drawRadialGradient(g, startCenter: CGPoint(x: 11, y: 11), startRadius: 0, endCenter: CGPoint(x: 11, y: 11), endRadius: 11, options: [])
        }
        c.setFillColor(NSColor.white.cgColor)
        c.fillEllipse(in: CGRect(x: 7, y: 7, width: 8, height: 8))
    }

    private func build() {
        built = bounds.size
        let w = Double(bounds.width), h = Double(bounds.height)
        guard w > 40 else { return }
        let size = bounds.size
        let flipY = { (y: Double) in CGFloat(h - y) }      // images are drawn top-down
        CATransaction.begin(); CATransaction.setDisableActions(true)
        stage.frame = bounds
        axes.frame = bounds
        axes.contents = renderImage(size, screenScale) { pen in
            let c = pen.c
            c.setLineWidth(1)
            c.setStrokeColor(NSColor(white: 1, alpha: 0.25).cgColor)
            c.strokeLineSegments(between: [CGPoint(x: 0, y: flipY(8)), CGPoint(x: w, y: flipY(8))])
            c.setStrokeColor(NSColor(white: 1, alpha: 0.3).cgColor)
            c.setLineDash(phase: 0, lengths: [4, 4])
            let ty = flipY(8 + h * 0.26)
            c.strokeLineSegments(between: [CGPoint(x: 0, y: ty), CGPoint(x: w, y: ty)])
        }
        reveal.bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)   // whole curves until the clock runs
        for d in dots { d.opacity = 0 }
        curves.frame = CGRect(origin: .zero, size: size)
        curves.contents = renderImage(size, screenScale) { pen in
            let c = pen.c
            c.setLineWidth(2.4); c.setLineCap(.round); c.setLineJoin(.round)
            for k in 0..<4 {
                c.setStrokeColor(NSColor(hex: Self.colors[k], alpha: 0.95).cgColor)
                c.beginPath()
                var x = 0.0
                while x <= w {
                    let p = CGPoint(x: x, y: flipY(Self.curveY(k, x, w, h)))
                    if x == 0 { c.move(to: p) } else { c.addLine(to: p) }
                    x += 2
                }
                c.strokePath()
            }
        }
        shown = (-1, -1, true)
        CATransaction.commit()
    }

    func tick(_ dt: Double) {
        let w = Double(bounds.width), h = Double(bounds.height)
        guard w > 40 else { return }
        clock += dt
        let phase = clock.truncatingRemainder(dividingBy: Self.period)
        let u = min(1, phase / Self.drawT)
        let width = CGFloat(phase < Self.fadeT ? u * w : 0)
        let opacity = Float(phase < Self.holdT ? 1 : max(0, 1 - (phase - Self.holdT) / (Self.fadeT - Self.holdT)))
        let drawing = phase < Self.drawT
        // nothing moves during the pause between runs, so nothing is sent to the screen
        guard width != shown.width || opacity != shown.opacity || drawing || shown.dots else { return }
        reveal.bounds.size.width = width
        reveal.opacity = opacity
        for (k, dot) in dots.enumerated() {
            dot.opacity = drawing ? 1 : 0
            if drawing { dot.position = CGPoint(x: u * w, y: Self.curveY(k, u * w, w, h)) }
        }
        shown = (width, opacity, drawing)
    }
}

struct BannerLane: NSViewRepresentable {
    let active: Bool
    func makeNSView(context: Context) -> BannerLaneView { BannerLaneView(frame: .zero) }
    func updateNSView(_ v: BannerLaneView, context: Context) { v.ambientActive = active }
}
