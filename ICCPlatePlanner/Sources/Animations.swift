import SwiftUI
import AppKit

// MARK: - Animations
//
// Small science-flavoured motion: a tube that fills with the blocking buffer, antibodies waiting on an
// empty plate, a rotating bench-side one-liner and a toast when something is saved. They tick at most
// 20 times a second and only while the app is in front (the banner helix, the glints over stained wells
// and the staining preview are on the shared clock in Ambient.swift and Sandbox.swift). Everything
// stops when "Animations" is switched off, and follows the Mac's Reduce Motion setting.

/// True when motion should play.
struct Motion {
    static func on(_ store: Store, _ reduce: Bool) -> Bool { store.animations && !reduce }
}

// MARK: Tube that fills with the blocking buffer (drawn on the shared clock, Ambient.swift)

struct TubeLevel: View {
    @EnvironmentObject var store: Store
    let fraction: Double       // 0...1 of the tube

    var body: some View {
        TubeLane(fraction: fraction, active: store.ambient)
            .accessibilityHidden(true)
    }
}

// MARK: Antibodies waiting for something to bind (empty plate)

struct AntibodyDoodle: View {
    @EnvironmentObject var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            DoodleLane(active: store.ambient)
            .frame(width: 130, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("These antibodies have nothing to bind to yet.")
                    .font(.system(size: 13, weight: .semibold, design: .serif)).foregroundColor(Brand.ink)
                Text("Add a stain set on the left, then paint its wells here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.pale.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Brand.rule, lineWidth: 1))
    }
}

// MARK: Bench-side one-liners (footer)

let benchLines = [
    "Stay positive. Unless you are the negative control.",
    "Block first, ask questions later.",
    "Keep calm and wash three times.",
    "In antibodies we trust. In controls we verify.",
    "May your background be low and your signal specific.",
    "Primary today, secondary tomorrow, signal on Friday.",
    "A watched plate never incubates.",
    "Label the tube. Future you is not a mind reader.",
]

struct Tagline: View {
    @EnvironmentObject var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 9)) { ctx in
            let i = Int(ctx.date.timeIntervalSinceReferenceDate / 9) % benchLines.count
            Text(benchLines[i])
                .font(.system(size: 12, design: .serif)).italic()
                .foregroundColor(Brand.mid)
                .id(i)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .clipped()
                .animation(Motion.on(store, reduceMotion) ? .easeInOut(duration: 0.7) : nil, value: i)
        }
    }
}

// MARK: Toast

struct Toast: Equatable {
    var id = UUID()
    var text: String
    var icon: String
}

/// A droplet that keeps falling into a ripple, for the toast.
private struct DropIcon: View {
    @EnvironmentObject var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !Motion.on(store, reduceMotion))) { ctx in
            Canvas { g, size in
                let p = Motion.on(store, reduceMotion) ? (ctx.date.timeIntervalSinceReferenceDate * 1.1).truncatingRemainder(dividingBy: 1) : 0.45
                let cx = size.width / 2, floor = size.height - 3
                if p < 0.6 {
                    let y = 2 + (floor - 6) * (p / 0.6) * (p / 0.6)
                    var d = Path()
                    d.move(to: CGPoint(x: cx, y: y - 5))
                    d.addQuadCurve(to: CGPoint(x: cx, y: y + 4), control: CGPoint(x: cx + 6, y: y + 3))
                    d.addQuadCurve(to: CGPoint(x: cx, y: y - 5), control: CGPoint(x: cx - 6, y: y + 3))
                    g.fill(d, with: .color(.white))
                } else {
                    let q = (p - 0.6) / 0.4
                    let r = 2 + 8 * q
                    g.stroke(Path(ellipseIn: CGRect(x: cx - r, y: floor - r * 0.35, width: 2 * r, height: r * 0.7)),
                             with: .color(.white.opacity(1 - q)), lineWidth: 1.5)
                }
            }
        }
        .frame(width: 20, height: 22)
    }
}

struct ToastView: View {
    let toast: Toast
    var body: some View {
        HStack(spacing: 10) {
            DropIcon()
            Text(toast.text).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
        .background(Capsule().fill(Brand.navy))
        .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
        .shadow(color: Brand.navy.opacity(0.35), radius: 10, y: 4)
    }
}

let exportLines = [
    "Exported. Go forth and pipette.",
    "Sheet's ready. The cells are waiting.",
    "Saved. May your signal be bright and your background dim.",
    "Done. Three washes and you're there.",
]
