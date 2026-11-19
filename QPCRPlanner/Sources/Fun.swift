import SwiftUI
import AppKit

// MARK: - Fun
//
// Everything here is decoration: Eppi the walking 1.5 mL tube, the qTOWER "run" that plays when
// results are imported, confetti, droplet bursts on buttons and amplification curves in the banner.
// Short effects are driven by time (TimelineView) and run only while they play. The always-on ones,
// Eppi and the banner curves, live in Lane.swift on one 20-frames-a-second clock that stops whenever
// the app is in the background. Everything stops when Animations is switched off in the File menu,
// and follows the Mac's Reduce Motion setting.

extension Store {
    var motion: Bool { animations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Long-running decoration (Eppi walking, banner curves) only plays while the app is in front.
    var ambient: Bool { motion && appActive }
}

func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - clamp01(x), 3) }
func easeInOut(_ x: Double) -> Double {
    let t = clamp01(x)
    return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}
func easeOutBack(_ x: Double) -> Double {
    let t = clamp01(x), c1 = 1.70158, c3 = c1 + 1
    return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
}
/// Deterministic pseudo-random number in 0..<1 (so particles look random but never flicker).
func hash01(_ i: Int, _ salt: Int) -> Double {
    var x = UInt64(truncatingIfNeeded: i &* 73856093 ^ salt &* 19349663 ^ 0x9E3779B9)
    x ^= x >> 33; x &*= 0xff51afd7ed558ccd; x ^= x >> 33; x &*= 0xc4ceb9fe1a85ec53; x ^= x >> 33
    return Double(x % 10_000) / 10_000
}

let funColors: [Color] = [Color(hex: "2FA84F"), Color(hex: "E2483D"), Color(hex: "2F6FE0"), Color(hex: "F2A900"),
                          Color(hex: "8E5BD1"), Color(hex: "17A2A2"), Color(hex: "1E4A83")]

/// A teardrop pointing up, centred on `c`.
func dropPath(_ c: CGPoint, _ r: CGFloat) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: c.x, y: c.y - r * 1.9))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y + r * 0.2), control: CGPoint(x: c.x + r * 0.95, y: c.y - r * 0.7))
    p.addArc(center: CGPoint(x: c.x, y: c.y + r * 0.2), radius: r, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r * 1.9), control: CGPoint(x: c.x - r * 0.95, y: c.y - r * 0.7))
    return p
}

/// A tiny 1.5 mL tube outline (for confetti), centred on the origin.
func miniTube(_ s: CGFloat) -> Path {
    var p = Path()
    p.addRoundedRect(in: CGRect(x: -s * 0.55, y: -s * 1.2, width: s * 1.1, height: s * 0.32), cornerSize: CGSize(width: 1, height: 1))
    p.move(to: CGPoint(x: -s * 0.4, y: -s * 0.88))
    p.addLine(to: CGPoint(x: -s * 0.4, y: s * 0.3))
    p.addLine(to: CGPoint(x: 0, y: s * 1.1))
    p.addLine(to: CGPoint(x: s * 0.4, y: s * 0.3))
    p.addLine(to: CGPoint(x: s * 0.4, y: -s * 0.88))
    p.closeSubpath()
    return p
}

func starPath(_ c: CGPoint, _ r: CGFloat) -> Path {
    var p = Path()
    for i in 0..<8 {
        let a = Double(i) / 8 * 2 * .pi - .pi / 2
        let rr = i % 2 == 0 ? r : r * 0.38
        let pt = CGPoint(x: c.x + CGFloat(cos(a)) * rr, y: c.y + CGFloat(sin(a)) * rr)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

// MARK: - Buttons: a gentle press, then a ring and a few droplets from the button's edge

struct SquishStyle: ButtonStyle {
    var on: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(on && configuration.isPressed ? 0.955 : 1)
            .brightness(on && configuration.isPressed ? -0.035 : 0)
            .animation(on ? .spring(response: 0.2, dampingFraction: 0.62) : nil, value: configuration.isPressed)
    }
}

/// A button whose click sends a soft ring out from its edge and pops a few droplets off its top.
/// The action runs straight away; panels open as sheets, so the ripple carries on behind them.
struct FunButton<Label: View>: View {
    @EnvironmentObject var store: Store
    let action: () -> Void
    let label: () -> Label
    private let firedAt = State(initialValue: Date.distantPast)
    private let settle = State(initialValue: 0)

    init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.label = label
    }

    var body: some View {
        Button { fire() } label: { label() }
            .buttonStyle(SquishStyle(on: store.motion))
            .overlay(
                Ripple(start: firedAt.wrappedValue, on: store.motion, settle: settle.wrappedValue)
                    .padding(-Ripple.pad)
                    .allowsHitTesting(false))
    }

    private func fire() {
        if store.motion {
            firedAt.wrappedValue = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + Ripple.length + 0.1) { settle.wrappedValue += 1 }
        }
        action()
    }
}

struct Ripple: View {
    static let length = 0.55
    static let pad: CGFloat = 28
    let start: Date
    let on: Bool
    let settle: Int     // changes once the ripple is over, so the timeline can stop

    var body: some View {
        let live = on && Date().timeIntervalSince(start) < Self.length + 0.05
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !live)) { ctx in
            Canvas { g, size in
                let a = ctx.date.timeIntervalSince(start)
                guard on, a >= 0, a < Self.length else { return }
                let p = a / Self.length, e = CGFloat(easeOut(p))
                let button = CGRect(origin: .zero, size: size).insetBy(dx: Self.pad, dy: Self.pad)
                let corner = min(button.height / 2, 8)
                // a quick tint over the button
                g.fill(Path(roundedRect: button, cornerRadius: corner, style: .continuous),
                       with: .color(Brand.mid.opacity(0.16 * max(0, 1 - p * 2.5))))
                // the ring
                let grow = e * 12
                g.stroke(Path(roundedRect: button.insetBy(dx: -grow, dy: -grow), cornerRadius: corner + grow, style: .continuous),
                         with: .color(Brand.mid.opacity(0.55 * (1 - p))), lineWidth: 2 * CGFloat(1 - p) + 0.5)
                // droplets off the top edge
                for i in 0..<5 {
                    let u = (Double(i) + 0.5) / 5
                    let x = button.minX + button.width * CGFloat(0.22 + 0.56 * u) + CGFloat((u - 0.5) * 16) * e
                    let y = button.minY - 3 - e * CGFloat(10 + 9 * hash01(i, 5))
                    g.fill(dropPath(CGPoint(x: x, y: y), CGFloat(1.9 + 0.9 * hash01(i, 9))),
                           with: .color(funColors[i % funColors.count].opacity(1 - p * p)))
                }
            }
        }
    }
}

// MARK: - Confetti (export, import finished)
//
// Drawn by Core Animation's particle emitter: the app hands over one burst and the window server flies
// the pieces, so nothing in the app redraws per frame, and the burst ends by itself.

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

    /// One burst for each new `at`, if it is fresh.
    func fire(_ at: Date, on: Bool) {
        guard at != fired else { return }
        fired = at
        guard on, abs(Date().timeIntervalSince(at)) < 0.6 else { return }
        let now = CACurrentMediaTime()
        for e in [left, right] {
            e.beginTime = now
            e.birthRate = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.left.birthRate = 0
            self?.right.birthRate = 0
        }
    }

    /// Five shapes in the app's colours: tubes, drops, strips, stars and dots.
    private static func cells(_ side: Double) -> [CAEmitterCell] {
        let hexes = ["2FA84F", "E2483D", "2F6FE0", "F2A900", "8E5BD1", "17A2A2", "1E4A83"]
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
        renderImage(CGSize(width: 26, height: 26), 2) { pen in
            let c = pen.c
            c.setFillColor(NSColor.white.cgColor)
            switch kind {
            case 0:     // a little tube
                c.fill(CGRect(x: 6, y: 2, width: 14, height: 4))
                c.move(to: CGPoint(x: 8, y: 6)); c.addLine(to: CGPoint(x: 8, y: 17)); c.addLine(to: CGPoint(x: 13, y: 24))
                c.addLine(to: CGPoint(x: 18, y: 17)); c.addLine(to: CGPoint(x: 18, y: 6)); c.closePath(); c.fillPath()
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

// MARK: - Toast

struct Toast: Equatable {
    var id = UUID()
    var text: String
}

struct ToastView: View {
    @EnvironmentObject var store: Store
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !store.motion)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                Image(systemName: "testtube.2")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(store.motion ? 14 * sin(t * 9) : 0))
                    .offset(y: store.motion ? -4 * abs(sin(t * 6)) : 0)
            }
            .frame(width: 22, height: 24)
            Text(toast.text).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white)
        }
        .padding(.horizontal, 22).padding(.vertical, 11)
        .background(Capsule().fill(LinearGradient(colors: [Brand.navy, Brand.mid], startPoint: .leading, endPoint: .trailing)))
        .overlay(Capsule().stroke(Color.white.opacity(0.45), lineWidth: 1.2))
        .shadow(color: Brand.navy.opacity(0.4), radius: 14, y: 6)
    }
}

// MARK: - Eppi, the walking 1.5 mL tube

enum EppiMood { case jump, dance, cheer }

struct EppiEvent: Equatable {
    var id = UUID()
    var mood: EppiMood
    var text: String
    var date = Date()
    var duration: Double {
        switch mood { case .jump: return 1.4; case .dance: return 3.0; case .cheer: return 2.4 }
    }
}

let eppiQuips = [
    "I'm 1.5 mL of pure enthusiasm!",
    "Spin me down before you open me!",
    "Label me. Please. I beg you.",
    "Vortex? Again?!",
    "Keep me on ice, I'm sensitive.",
    "ΔΔCt? More like ΔΔ-see-ya-later!",
    "I contain multitudes. And SYBR Green.",
    "No bubbles in the wells, okay?",
    "40 cycles? I could do 41.",
    "GAPDH: the friend who's always there.",
]

struct EppiPose {
    var dir: CGFloat = 1
    var walk: Double = 0
    var moving = true
    var lift: CGFloat = 0
    var spin: Double = 0
    var tilt: Double = 0
    var lid: Double = 0.15
    var blink = false
    var armsUp: Double = 0
    var waving = false
    var wavePhase: Double = 0
    var mouthOpen = false
    var notes = false
    var sparkle = false
    var t: Double = 0
    var ripple: Double = 0       // liquid surface wave phase
    var bubbles: Double = 0      // 0..1, rising bubbles in the liquid
}

// MARK: - The qTOWER run that plays when results are imported

struct ShowGene: Equatable {
    var name: String
    var hex: String
    var ct: Double
}

struct ImportShow: Equatable {
    var id = UUID()
    var date = Date()
    var genes: [ShowGene]
    var conditions: Int
    static let length = 4.2
}

/// The run plays in a borderless window of its own, laid over the main window's content. Its frames then
/// redraw that small view alone, instead of laying out the whole window (every graph included) 60 times a
/// second underneath it.
final class ImportShowWindow {
    static let shared = ImportShowWindow()
    private var window: NSWindow?

    func present(_ show: ImportShow, _ store: Store) {
        dismiss(animated: false)
        guard let host = NSApp.mainWindow ?? NSApp.keyWindow
                ?? NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) && $0.parent == nil }),
              let content = host.contentView else { return }
        let rect = host.convertToScreen(content.convert(content.bounds, to: nil))
        let w = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        w.contentView = ImportRunView(show: show, store: store)
        host.addChildWindow(w, ordered: .above)
        w.alphaValue = 0
        NSAnimationContext.runAnimationGroup { $0.duration = 0.3; w.animator().alphaValue = 1 }
        window = w
    }

    func dismiss(animated: Bool = true) {
        guard let w = window else { return }
        window = nil
        let done = {
            w.parent?.removeChildWindow(w)
            w.orderOut(nil)
            w.contentView = nil
        }
        if animated {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; w.animator().alphaValue = 0 }, completionHandler: done)
        } else {
            done()
        }
    }
}

/// A click on the run skips it, even on the first click into the window.
final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct ImportShowView: View {
    @EnvironmentObject var store: Store
    let show: ImportShow

    var body: some View {
        ZStack {
            // the dim stays still (the window fades); only the panel below is redrawn each frame
            Color(hex: "0B1F3A").opacity(store.importShowInWindow ? 0.6 : 0.6 * clamp01(Date().timeIntervalSince(show.date) / 0.3))
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { ctx in
                let a = ctx.date.timeIntervalSince(show.date)
                let fadeOut = 1 - clamp01((a - (ImportShow.length - 0.45)) / 0.45)
                ZStack {
                    // the panel and its soft shadow are a picture made once; only the run inside is redrawn
                    if let panel = Self.panelImage() {
                        Image(decorative: panel, scale: screenScale).frame(width: 760, height: 480)
                    }
                    Canvas { g, size in drawRun(&g, size, a) }
                        .frame(width: 700, height: 420)
                }
                .scaleEffect(CGFloat(0.6 + 0.4 * easeOutBack(a / 0.45)) * CGFloat(1 - 0.08 * (1 - fadeOut)))
                .opacity(fadeOut)
            }
            .frame(width: 760, height: 480)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.skipImportShow() }
    }

    /// The card behind the run with its shadow, drawn once for the current light or dark look.
    private static var panelCache: (dark: Bool, image: CGImage?)?
    static func panelImage() -> CGImage? {
        let dark = NSApp?.effectiveAppearance.isDark ?? false
        if let c = panelCache, c.dark == dark { return c.image }
        var img: CGImage?
        (NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua)!).performAsCurrentDrawingAppearance {
            img = renderImage(CGSize(width: 760, height: 480), screenScale) { pen in
                let c = pen.c
                let card = NSColor(Brand.card).cgColor
                let r = CGRect(x: 40, y: 40, width: 680, height: 400)
                c.setShadow(offset: CGSize(width: 0, height: 10), blur: 44, color: NSColor.black.withAlphaComponent(0.35).cgColor)
                c.addPath(CGPath(roundedRect: r, cornerWidth: 24, cornerHeight: 24, transform: nil))
                c.setFillColor(card)
                c.fillPath()
            }
        }
        panelCache = (dark, img)
        return img
    }

    private func drawRun(_ g: inout GraphicsContext, _ size: CGSize, _ a: Double) {
        let navy = Brand.accent
        let phase: String
        switch a {
        case ..<1.2: phase = "Loading your plate into the qTOWER³…"
        case ..<3.2: phase = "Cycling: 95 °C → 60 °C, 40 times…"
        default: phase = "ΔΔCt analysed. Your graphs are ready!"
        }
        g.draw(Text("qTOWER³ run").font(.system(size: 22, weight: .heavy, design: .serif)).foregroundColor(navy), at: pt(40, 46), anchor: .leading)
        g.draw(Text("click to skip").font(.system(size: 11, weight: .medium)).foregroundColor(Color(hex: "9AA8BC")), at: pt(668, 46), anchor: .trailing)
        g.draw(Text(phase).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(Color(hex: "4A78B8")), at: pt(40, 72), anchor: .leading)

        // ---- instrument
        let open = a < 1.05 ? sin(.pi * clamp01(a / 1.05)) : 0
        let base = CGRect(x: 40, y: 200, width: 230, height: 140)
        g.fill(Path(roundedRect: base, cornerRadius: 18), with: .linearGradient(Gradient(colors: [Color(hex: "F4F7FB"), Color(hex: "CDD7E5")]), startPoint: pt(0, 200), endPoint: pt(0, 340)))
        g.stroke(Path(roundedRect: base, cornerRadius: 18), with: .color(Color(hex: "9AA8BC")), lineWidth: 1.5)
        g.fill(Path(roundedRect: CGRect(x: 40, y: 290, width: 230, height: 34), cornerRadius: 6), with: .color(navy))
        g.draw(Text("qTOWER³").font(.system(size: 15, weight: .heavy)).foregroundColor(.white), at: pt(62, 307), anchor: .leading)
        let cycling = a > 1.35 && a < 3.2
        let ledOn = cycling ? sin(a * 18) > 0 : true
        let led = a >= 3.2 ? Color(hex: "39D353") : (cycling ? Color(hex: "39D353") : Color(hex: "F2A900"))
        g.fill(Path(ellipseIn: CGRect(x: 244, y: 300, width: 12, height: 12)), with: .color(ledOn ? led : led.opacity(0.25)))
        if cycling {
            let hot = Int(a * 4) % 2 == 0
            g.draw(Text(hot ? "95 °C" : "60 °C").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(hot ? Color(hex: "FF8E7A") : Color(hex: "9CCBFF")), at: pt(232, 307), anchor: .trailing)
        }
        g.fill(Path(roundedRect: CGRect(x: 62, y: 262, width: 186, height: 9), cornerRadius: 3), with: .color(Color(hex: "2A3445")))
        // plate sliding in
        let slide = easeOut((a - 0.3) / 0.7)
        if a < 1.15 {
            let px = -180 + (75 + 180) * slide
            let plate = CGRect(x: px, y: 232, width: 160, height: 30)
            g.fill(Path(roundedRect: plate, cornerRadius: 5), with: .color(.white))
            g.stroke(Path(roundedRect: plate, cornerRadius: 5), with: .color(Color(hex: "9AA8BC")), lineWidth: 1.2)
            for r in 0..<3 {
                for c in 0..<12 {
                    let color = show.genes.isEmpty ? funColors[c % funColors.count] : Color(hex: show.genes[(c / 3) % show.genes.count].hex)
                    g.fill(Path(ellipseIn: CGRect(x: px + 8 + Double(c) * 12.4, y: 236 + Double(r) * 8.3, width: 6.6, height: 6.6)), with: .color(color.opacity(0.85)))
                }
            }
        }
        // lid, hinged at the back
        var lid = g
        lid.translateBy(x: 270, y: 200)
        lid.rotate(by: .radians(0.75 * open))     // lifts the front edge, hinged at the back
        lid.fill(Path(roundedRect: CGRect(x: -230, y: -34, width: 230, height: 36), cornerRadius: 14), with: .linearGradient(Gradient(colors: [Color(hex: "E3E9F2"), Color(hex: "B8C4D6")]), startPoint: pt(0, -34), endPoint: pt(0, 2)))
        lid.stroke(Path(roundedRect: CGRect(x: -230, y: -34, width: 230, height: 36), cornerRadius: 14), with: .color(Color(hex: "8A99AF")), lineWidth: 1.5)
        lid.fill(Path(roundedRect: CGRect(x: -200, y: -24, width: 120, height: 6), cornerRadius: 3), with: .color(.white.opacity(0.6)))
        // heat shimmer while cycling
        if cycling {
            for i in 0..<4 {
                let q = (a * 0.9 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1)
                var w = Path()
                let x0 = 80 + Double(i) * 50
                for s in 0...20 {
                    let y = 160 - q * 60 - Double(s) * 2
                    let x = x0 + 5 * sin(Double(s) / 3 + a * 6)
                    if s == 0 { w.move(to: pt(x, y)) } else { w.addLine(to: pt(x, y)) }
                }
                g.stroke(w, with: .color(Color(hex: "FF8E7A").opacity(0.55 * (1 - q))), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
        }

        // ---- screen with amplification curves
        let scr = CGRect(x: 300, y: 100, width: 360, height: 250)
        g.fill(Path(roundedRect: scr, cornerRadius: 14), with: .color(Color(hex: "0E1B30")))
        g.stroke(Path(roundedRect: scr, cornerRadius: 14), with: .color(Color(hex: "2C4466")), lineWidth: 2)
        let plot = CGRect(x: scr.minX + 34, y: scr.minY + 34, width: scr.width - 54, height: scr.height - 64)
        for i in 0...4 {
            var gl = Path()
            let y = plot.maxY - plot.height * Double(i) / 4
            gl.move(to: pt(plot.minX, y)); gl.addLine(to: pt(plot.maxX, y))
            g.stroke(gl, with: .color(.white.opacity(0.08)), lineWidth: 1)
        }
        var ax = Path()
        ax.move(to: pt(plot.minX, plot.minY)); ax.addLine(to: pt(plot.minX, plot.maxY)); ax.addLine(to: pt(plot.maxX, plot.maxY))
        g.stroke(ax, with: .color(.white.opacity(0.5)), lineWidth: 1.2)
        g.draw(Text("Cycle").font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.6)), at: pt(plot.midX, plot.maxY + 16))
        g.draw(Text("ΔRn").font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.6)), at: pt(plot.minX - 18, plot.midY))
        let thrY = plot.maxY - plot.height * 0.2
        var thr = Path(); thr.move(to: pt(plot.minX, thrY)); thr.addLine(to: pt(plot.maxX, thrY))
        g.stroke(thr, with: .color(Color(hex: "FFD86B").opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        let cycle = 40 * clamp01((a - 1.35) / 1.85)
        let genes = show.genes.isEmpty ? [ShowGene(name: "", hex: "2FA84F", ct: 25)] : Array(show.genes.prefix(8))
        for (k, gene) in genes.enumerated() {
            let top = 0.92 - 0.06 * Double(k % 4)
            let s = 1.6
            let ct = min(max(gene.ct, 12), 37)
            let m = ct + s * log(top / 0.2 - 1)
            var path = Path()
            var c = 0.0
            var last = pt(plot.minX, plot.maxY)
            let color = Color(hex: tintHex(gene.hex, 0.2))
            while c <= cycle {
                let v = top / (1 + exp(-(c - m) / s))
                last = pt(plot.minX + plot.width * c / 40, plot.maxY - plot.height * v)
                if c == 0 { path.move(to: last) } else { path.addLine(to: last) }
                c += 0.25
            }
            g.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            if cycle > 0 && cycle < 40 {
                g.fill(Path(ellipseIn: CGRect(x: last.x - 9, y: last.y - 9, width: 18, height: 18)), with: .color(color.opacity(0.3)))
                g.fill(Path(ellipseIn: CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7)), with: .color(.white))
            }
            if cycle >= ct {
                let cx = plot.minX + plot.width * ct / 40
                let pop = easeOutBack((cycle - ct) / 3)
                g.fill(Path(ellipseIn: CGRect(x: cx - 4 * pop, y: thrY - 4 * pop, width: 8 * pop, height: 8 * pop)), with: .color(Color(hex: "FFD86B")))
            }
            if !gene.name.isEmpty {
                // a small legend in the top-left corner of the screen
                let ly = plot.minY + 4 + Double(k) * 15
                g.fill(Path(roundedRect: CGRect(x: plot.minX + 8, y: ly - 3, width: 12, height: 6), cornerRadius: 3), with: .color(color))
                g.draw(Text(gene.name).font(.system(size: 10.5, weight: .bold)).foregroundColor(color), at: pt(plot.minX + 26, ly), anchor: .leading)
            }
        }
        g.draw(Text("Cycle \(Int(cycle)) / 40").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundColor(.white),
               at: pt(scr.maxX - 14, scr.minY + 17), anchor: .trailing)

        // progress bar
        let bar = CGRect(x: 40, y: 368, width: 620, height: 10)
        g.fill(Path(roundedRect: bar, cornerRadius: 5), with: .color(Color(hex: "E3EAF4")))
        g.fill(Path(roundedRect: CGRect(x: bar.minX, y: bar.minY, width: bar.width * clamp01(a / 3.2), height: bar.height), cornerRadius: 5),
               with: .linearGradient(Gradient(colors: [Color(hex: "2FA84F"), Color(hex: "4A78B8")]), startPoint: pt(bar.minX, 0), endPoint: pt(bar.maxX, 0)))

        // done stamp
        if a >= 3.2 {
            let s = easeOutBack((a - 3.2) / 0.4)
            var stamp = g
            stamp.translateBy(x: 350, y: 238)
            stamp.scaleBy(x: s, y: s)
            stamp.rotate(by: .degrees(-6))
            let n = show.genes.count
            let text = "✓  \(n) gene\(n == 1 ? "" : "s") · \(show.conditions) condition\(show.conditions == 1 ? "" : "s") · ΔΔCt ready!"
            stamp.fill(Path(roundedRect: CGRect(x: -230, y: -30, width: 460, height: 60), cornerRadius: 30), with: .color(Color(hex: "2FA84F")))
            stamp.stroke(Path(roundedRect: CGRect(x: -230, y: -30, width: 460, height: 60), cornerRadius: 30), with: .color(.white), lineWidth: 3)
            stamp.draw(Text(text).font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundColor(.white), at: .zero)
        }
    }
}

// MARK: - Empty results: a drop zone

