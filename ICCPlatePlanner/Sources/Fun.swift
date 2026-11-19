import SwiftUI
import AppKit

// MARK: - Fun
//
// Decoration and feel: a gentle press on every button with a ring and droplets from its edge, a ripple
// where a well is painted, confetti when the workbook is exported, numbers that roll, and a tick on the
// trackpad as wells fill. Short effects are driven by time (TimelineView) and run only while they play;
// the always-on ones live on the shared 20-frames-a-second clock (Ambient.swift). Everything stops when
// Animations is switched off in the File menu, and follows the Mac's Reduce Motion setting.

extension Store {
    var motion: Bool { animations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Long-running decoration only plays while the app is in front.
    var ambient: Bool { motion && appActive }

    /// A light tick on a Force Touch trackpad (Trackpad Feedback in the File menu).
    func tap(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
        guard haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
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

/// Immunofluorescence colours: 488 green, 594 red, DAPI blue, 647 magenta, 555 amber, plus the navy.
let funColors: [Color] = [Color(hex: "2FB85A"), Color(hex: "E2483D"), Color(hex: "2F6FE0"), Color(hex: "C04BD8"),
                          Color(hex: "F2A900"), Color(hex: "17A2A2"), Color(hex: "1E4A83")]

/// A teardrop pointing up, centred on `c`.
func dropPath(_ c: CGPoint, _ r: CGFloat) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: c.x, y: c.y - r * 1.9))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y + r * 0.2), control: CGPoint(x: c.x + r * 0.95, y: c.y - r * 0.7))
    p.addArc(center: CGPoint(x: c.x, y: c.y + r * 0.2), radius: r, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r * 1.9), control: CGPoint(x: c.x - r * 0.95, y: c.y - r * 0.7))
    return p
}

/// An antibody, the Y, centred on the origin, `s` tall.
func antibodyPath(_ s: CGFloat) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 0, y: s * 0.5)); p.addLine(to: CGPoint(x: 0, y: 0))
    p.addLine(to: CGPoint(x: -s * 0.36, y: -s * 0.5))
    p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: s * 0.36, y: -s * 0.5))
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
/// The action runs straight away; nothing waits for the ripple.
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
        store.tap(.generic)
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
                g.fill(Path(roundedRect: button, cornerRadius: corner, style: .continuous),
                       with: .color(Brand.mid.opacity(0.16 * max(0, 1 - p * 2.5))))
                let grow = e * 12
                g.stroke(Path(roundedRect: button.insetBy(dx: -grow, dy: -grow), cornerRadius: corner + grow, style: .continuous),
                         with: .color(Brand.mid.opacity(0.55 * (1 - p))), lineWidth: 2 * CGFloat(1 - p) + 0.5)
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

// MARK: - A ripple where a well is painted

struct WellSplash: View {
    let start: Date
    let color: Color
    let on: Bool
    let settle: Int
    static let length = 0.6

    var body: some View {
        let live = on && Date().timeIntervalSince(start) < Self.length + 0.05
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !live)) { ctx in
            Canvas { g, size in
                let a = ctx.date.timeIntervalSince(start)
                guard on, a >= 0, a < Self.length else { return }
                let p = a / Self.length, e = CGFloat(easeOut(p))
                let r = CGRect(origin: .zero, size: size).insetBy(dx: 12.5, dy: 12.5)
                let grow = e * 9
                g.stroke(Path(roundedRect: r.insetBy(dx: -grow, dy: -grow), cornerRadius: 9 + grow, style: .continuous),
                         with: .color(color.opacity(0.75 * (1 - p))), lineWidth: 2.2 * CGFloat(1 - p) + 0.4)
                // a few drops thrown off by the pipette
                for i in 0..<4 {
                    let ang = Double(i) / 4 * 2 * .pi + 0.6
                    let d = (8 + 10 * e) + CGFloat(4 * hash01(i, 3))
                    let c = CGPoint(x: r.midX + CGFloat(cos(ang)) * (r.width / 2 + d * 0.4), y: r.midY + CGFloat(sin(ang)) * (r.height / 2 + d * 0.4))
                    g.fill(Path(ellipseIn: CGRect(x: c.x - 1.6, y: c.y - 1.6, width: 3.2, height: 3.2)), with: .color(color.opacity(0.9 * (1 - p))))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Digits roll to their new value (an odometer) when `value` changes.
    func rolling<V: Equatable>(_ value: V, _ on: Bool) -> some View {
        self.contentTransition(.numericText())
            .animation(on ? .spring(response: 0.5, dampingFraction: 0.78) : nil, value: value)
    }
}
