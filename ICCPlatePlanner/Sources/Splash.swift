import SwiftUI
import AppKit

// MARK: - Splash
//
// A banner in the manner of Photoshop's: shown for a moment while the app opens (the main window
// waits behind it), and again from "About ICC Plate Planner". On the right an ibidi plate fills with
// stains and a field of view lights up channel by channel (nuclei, then 488, then 594) while antibodies
// drift past; the department and hospital are on the left. A click dismisses it.

private final class SplashWindow: NSWindow {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

final class SplashController {
    static let shared = SplashController()
    private var window: SplashWindow?
    var isShowing: Bool { window != nil }
    private var hider: Timer?
    private var hidden: [NSWindow] = []

    static var enabledAtLaunch: Bool {
        get { UserDefaults.standard.object(forKey: "showSplash") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showSplash") }
    }

    static var motion: Bool {
        (UserDefaults.standard.object(forKey: "animations") as? Bool ?? true) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// At launch: the splash, with the main window kept out of sight until it goes.
    func showAtLaunch() {
        guard Self.enabledAtLaunch else { return }
        let motion = Self.motion
        present(about: false, motion: motion)
        let t = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in self?.hideOthers() }
        RunLoop.main.add(t, forMode: .common)
        hider = t
        hideOthers()
        DispatchQueue.main.asyncAfter(deadline: .now() + (motion ? SplashView.length : 1.6)) { [weak self] in self?.dismiss() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.revealOthers() }     // never leave the app hidden
    }

    func showAbout() {
        if let w = window { w.makeKeyAndOrderFront(nil); return }
        present(about: true, motion: Self.motion)
        window?.makeKey()
    }

    private func present(about: Bool, motion: Bool) {
        let size = SplashView.size
        let w = SplashWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        w.hidesOnDeactivate = true
        w.isReleasedWhenClosed = false
        w.onEscape = { [weak self] in self?.dismiss() }
        let view = SplashView(about: about, motion: motion, start: Date()) { [weak self] in self?.dismiss() }
        w.contentView = NSHostingView(rootView: view)
        w.center()
        w.alphaValue = 0
        w.orderFrontRegardless()
        window = w
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            w.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { w.invalidateShadow() }
    }

    private func hideOthers() {
        for w in NSApp.windows where w !== window && w.isVisible && w.alphaValue > 0 && w.styleMask.contains(.titled) {
            w.alphaValue = 0
            hidden.append(w)
        }
    }

    private func revealOthers() {
        hider?.invalidate()
        hider = nil
        let shown = hidden
        hidden.removeAll()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            for w in shown { w.animator().alphaValue = 1 }
        }
        shown.first?.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        revealOthers()
        guard let w = window else { return }
        window = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            w.animator().alphaValue = 0
        }, completionHandler: {
            w.orderOut(nil)
            w.contentView = nil
        })
    }
}

struct SplashView: View {
    static let length = 4.8
    static let size = CGSize(width: 780, height: 450)
    static let steps = ["Thawing the antibodies…", "Blocking with NDS…", "Washing three times…", "Focusing the microscope…", "Ready."]

    let about: Bool
    let motion: Bool
    let start: Date
    let onClose: () -> Void
    private let settled = State(initialValue: false)

    init(about: Bool, motion: Bool, start: Date, onClose: @escaping () -> Void) {
        self.about = about; self.motion = motion; self.start = start; self.onClose = onClose
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        let live = motion && !settled.wrappedValue
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !live)) { ctx in
            let t = live ? ctx.date.timeIntervalSince(start) : 10
            ZStack(alignment: .topLeading) {
                Canvas { g, size in SplashArt.draw(&g, size, t) }
                text(t)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { onClose() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.length + 0.3) { settled.wrappedValue = true }
        }
    }

    /// Fade and rise in, `delay` seconds after the splash appears.
    private func enter(_ t: Double, _ delay: Double) -> (opacity: Double, y: CGFloat) {
        let p = easeOut((t - delay) / 0.8)
        return (p, CGFloat(1 - p) * 12)
    }

    @ViewBuilder private func text(_ t: Double) -> some View {
        let logo = enter(t, 0.1), title = enter(t, 0.5), tag = enter(t, 0.8), foot = enter(t, 0.5)
        ZStack(alignment: .topLeading) {
            if let img = Brand.logo {
                Image(nsImage: img).renderingMode(.template).resizable().interpolation(.high)
                    .aspectRatio(contentMode: .fit).frame(height: 76)
                    .foregroundColor(.white.opacity(0.95))
                    .opacity(logo.opacity).offset(y: logo.y)
                    .offset(x: 38, y: 30)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("ICC Plate Planner")
                    .font(.system(size: 46, weight: .bold, design: .serif))
                    .foregroundColor(.white)
                    .shadow(color: Color(hex: "0B1F3A").opacity(0.5), radius: 12, y: 4)
                    .opacity(title.opacity).offset(y: title.y)
                Text("Stain sets, plate maps and antibody volumes,\nfrom the bench to the microscope.")
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundColor(.white.opacity(0.78))
                    .lineSpacing(3)
                    .padding(.top, 8)
                    .opacity(tag.opacity).offset(y: tag.y)
                Text("Version \(version)")
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 14)
                    .opacity(tag.opacity)
            }
            .offset(x: 44, y: 142)

            VStack(alignment: .leading, spacing: 7) {
                if about {
                    Text("Click anywhere to close").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.7))
                } else {
                    let i = min(Self.steps.count - 1, Int(max(0, t) / (Self.length / Double(Self.steps.count))))
                    Text(motion ? Self.steps[i] : "Loading…").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.85))
                    progress(motion ? easeInOut(t / (Self.length - 0.6)) : 1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Brand.department) · \(Brand.hospital)")
                    Text("Created by \(Brand.author)  ·  © 2026")
                }
                .font(.system(size: 10.5))
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 8)
            }
            .opacity(foot.opacity)
            .offset(x: 44, y: 338)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    private func progress(_ p: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.14)).frame(width: 260, height: 3)
            Capsule()
                .fill(LinearGradient(colors: SplashArt.dyes.map { Color(hex: $0) }, startPoint: .leading, endPoint: .trailing))
                .frame(width: max(3, 260 * CGFloat(clamp01(p))), height: 3)
        }
    }
}

// MARK: - Artwork

enum SplashArt {
    /// DAPI, 488, 594, 647: the dyes, in the order they light up.
    static let dyes = ["5B8CFF", "3DDC6E", "FF5A4E", "E061FF"]

    static func draw(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let rect = CGRect(origin: .zero, size: size)

        // night-blue ground with two soft glows
        g.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color(hex: "071630"), Color(hex: "0F2F5A"), Color(hex: "1E4A83")]),
                                                 startPoint: CGPoint(x: 0, y: size.height), endPoint: CGPoint(x: size.width, y: 0)))
        g.fill(Path(rect), with: .radialGradient(Gradient(colors: [Color(hex: "5B8BD6").opacity(0.55), .clear]),
                                                 center: CGPoint(x: size.width * 0.8, y: size.height * 0.12), startRadius: 0, endRadius: 380))
        g.fill(Path(rect), with: .radialGradient(Gradient(colors: [Color(hex: "B04BD8").opacity(0.18), .clear]),
                                                 center: CGPoint(x: size.width * 0.6, y: size.height * 1.05), startRadius: 0, endRadius: 330))

        // a faint lattice, like the bottom of a culture dish
        var dots = Path()
        for x in stride(from: 392.0, through: Double(size.width), by: 26) {
            for y in stride(from: 14.0, through: Double(size.height), by: 26) { dots.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)) }
        }
        g.fill(dots, with: .color(.white.opacity(0.06)))

        antibodies(&g, size, t)
        plate(&g, t)
        micrograph(&g, size, t)

        // shade behind the words on the left
        g.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color(hex: "071630").opacity(0.55), Color(hex: "071630").opacity(0)]),
                                                 startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 430, y: 0)))
    }

    /// Antibodies drifting upwards, each with a glowing dye on its stem.
    private static func antibodies(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        for i in 0..<14 {
            let x = 410 + hash01(i, 1) * Double(size.width - 430)
            let speed = 14 + Double(i % 5) * 5
            let y = Double(size.height) + 24 - (t * speed + Double(i) * 41).truncatingRemainder(dividingBy: Double(size.height) + 48)
            let s = CGFloat(10 + 7 * hash01(i, 2))
            var l = g
            l.translateBy(x: x + 6 * sin(t * 0.8 + Double(i)), y: y)
            l.rotate(by: .radians(0.5 * sin(t * 0.6 + Double(i) * 1.7)))
            let dye = Color(hex: dyes[i % dyes.count])
            l.fill(Path(ellipseIn: CGRect(x: -s * 0.35, y: s * 0.5 - s * 0.35, width: s * 0.7, height: s * 0.7)),
                   with: .radialGradient(Gradient(colors: [dye.opacity(0.75), dye.opacity(0)]), center: CGPoint(x: 0, y: s * 0.5), startRadius: 0, endRadius: s * 0.38))
            l.stroke(antibodyPath(s), with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }

    /// A tilted ibidi 96-well plate whose wells take their stains in a diagonal wave.
    private static func plate(_ g: inout GraphicsContext, _ t: Double) {
        var p = g
        p.translateBy(x: 626, y: 126)
        p.rotate(by: .degrees(-8))
        let pitch: CGFloat = 19.5
        let w = 12 * pitch + 24, h = 8 * pitch + 24
        let body = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        var outline = Path()
        let cut: CGFloat = 13
        outline.move(to: CGPoint(x: body.minX + cut, y: body.minY))
        outline.addLine(to: CGPoint(x: body.maxX - 10, y: body.minY))
        outline.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + 10), control: CGPoint(x: body.maxX, y: body.minY))
        outline.addLine(to: CGPoint(x: body.maxX, y: body.maxY - 10))
        outline.addQuadCurve(to: CGPoint(x: body.maxX - 10, y: body.maxY), control: CGPoint(x: body.maxX, y: body.maxY))
        outline.addLine(to: CGPoint(x: body.minX + 10, y: body.maxY))
        outline.addQuadCurve(to: CGPoint(x: body.minX, y: body.maxY - 10), control: CGPoint(x: body.minX, y: body.maxY))
        outline.addLine(to: CGPoint(x: body.minX, y: body.minY + cut))
        outline.closeSubpath()
        p.opacity = easeOut(t / 0.8)
        p.fill(outline, with: .linearGradient(Gradient(colors: [.white.opacity(0.12), .white.opacity(0.04)]),
                                              startPoint: CGPoint(x: 0, y: body.minY), endPoint: CGPoint(x: 0, y: body.maxY)))
        p.stroke(outline, with: .color(.white.opacity(0.28)), lineWidth: 1.2)
        // stain sets in pairs of rows; the last two columns left as no-primary controls
        for r in 0..<8 {
            for c in 0..<12 {
                let center = CGPoint(x: body.minX + 12 + (CGFloat(c) + 0.5) * pitch, y: body.minY + 12 + (CGFloat(r) + 0.5) * pitch)
                let rad: CGFloat = 7.1
                // ibidi wells are square with round corners
                let well = CGRect(x: center.x - rad, y: center.y - rad, width: rad * 2, height: rad * 2)
                p.fill(Path(roundedRect: well, cornerRadius: 3), with: .color(.white.opacity(0.05)))
                p.stroke(Path(roundedRect: well, cornerRadius: 3), with: .color(.white.opacity(0.2)), lineWidth: 0.8)
                guard c < 10 else { continue }
                let k = easeOutBack((t - 0.4 - (Double(c) + Double(r) * 0.7) * 0.085) / 0.5)
                guard k > 0 else { continue }
                let hex = dyes[(r / 2 + 1) % dyes.count]
                let rr = rad * 0.84 * CGFloat(k)
                let glow = CGRect(x: center.x - rr * 1.9, y: center.y - rr * 1.9, width: rr * 3.8, height: rr * 3.8)
                p.fill(Path(ellipseIn: glow), with: .radialGradient(Gradient(colors: [Color(hex: hex).opacity(0.3), .clear]),
                                                                     center: center, startRadius: 0, endRadius: rr * 1.9))
                let liquid = CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)
                p.fill(Path(roundedRect: liquid, cornerRadius: 3 * CGFloat(k)),
                       with: .radialGradient(Gradient(colors: [.white.opacity(0.9), Color(hex: hex), Color(hex: hex).opacity(0.75)]),
                                             center: CGPoint(x: center.x - rr * 0.3, y: center.y - rr * 0.35), startRadius: 0, endRadius: rr * 1.4))
            }
        }
    }

    /// A field of view lighting up: nuclei, then 488, then 594, merged.
    private static func micrograph(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let ctr = CGPoint(x: 604, y: 338), R: CGFloat = 78
        let appear = easeOut((t - 0.7) / 0.6)
        guard appear > 0 else { return }
        var v = g
        v.opacity = appear
        let circle = Path(ellipseIn: CGRect(x: ctr.x - R, y: ctr.y - R, width: 2 * R, height: 2 * R))
        v.fill(Path(ellipseIn: CGRect(x: ctr.x - R - 12, y: ctr.y - R - 12, width: 2 * R + 24, height: 2 * R + 24)),
               with: .radialGradient(Gradient(colors: [.black.opacity(0.5), .clear]), center: ctr, startRadius: R, endRadius: R + 12))
        v.fill(circle, with: .color(Color(hex: "03070F")))
        let channels: [(hex: String, at: Double, name: String)] = [("5B8CFF", 1.3, "DAPI"), ("3DDC6E", 2.0, "488"), ("FF5A4E", 2.7, "594")]
        v.drawLayer { f in
            f.clip(to: circle)
            for i in 0..<9 {
                let a = hash01(i, 21) * 2 * .pi, d = sqrt(hash01(i, 22)) * Double(R - 22)
                let c = CGPoint(x: ctr.x + CGFloat(cos(a) * d), y: ctr.y + CGFloat(sin(a) * d))
                let rx = CGFloat(12 + 5 * hash01(i, 23)), ry = rx * 0.72
                let ang = hash01(i, 24) * .pi
                // 488: cytoplasm and neurites
                let green = easeOut((t - channels[1].at - Double(i) * 0.04) / 0.5) * (hash01(i, 25) > 0.2 ? 1 : 0.15)
                if green > 0 {
                    var cell = f
                    cell.translateBy(x: c.x, y: c.y)
                    cell.rotate(by: .radians(ang))
                    let col = Color(hex: channels[1].hex)
                    var neurite = Path()
                    neurite.move(to: CGPoint(x: rx * 0.8, y: 0))
                    neurite.addQuadCurve(to: CGPoint(x: rx + 30, y: 6 * CGFloat(hash01(i, 26) - 0.5) * 4), control: CGPoint(x: rx + 14, y: -8))
                    neurite.move(to: CGPoint(x: -rx * 0.8, y: 0))
                    neurite.addQuadCurve(to: CGPoint(x: -rx - 18, y: 10), control: CGPoint(x: -rx - 8, y: 8))
                    cell.stroke(neurite, with: .color(col.opacity(0.7 * green)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    cell.fill(Path(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry)),
                              with: .radialGradient(Gradient(colors: [col.opacity(0.75 * green), col.opacity(0.35 * green)]), center: .zero, startRadius: 0, endRadius: rx))
                }
                let nr = ry * 0.7
                let nucleus = CGRect(x: c.x - nr, y: c.y - nr * 0.85, width: 2 * nr, height: 1.7 * nr)
                // DAPI: every nucleus
                let blue = easeOut((t - channels[0].at - Double(i) * 0.04) / 0.5)
                if blue > 0 {
                    f.fill(Path(ellipseIn: nucleus.insetBy(dx: -2, dy: -2)), with: .radialGradient(Gradient(colors: [Color(hex: channels[0].hex).opacity(0.5 * blue), .clear]), center: c, startRadius: 0, endRadius: nr * 1.5))
                    f.fill(Path(ellipseIn: nucleus), with: .color(Color(hex: channels[0].hex).opacity(0.85 * blue)))
                }
                // 594: a nuclear marker in most cells (magenta-pink where it meets DAPI)
                let red = easeOut((t - channels[2].at - Double(i) * 0.04) / 0.5) * (hash01(i, 27) > 0.3 ? 1 : 0)
                if red > 0 {
                    f.fill(Path(ellipseIn: nucleus.insetBy(dx: 1.5, dy: 1.5)), with: .color(Color(hex: "FF6FA0").opacity(0.85 * red)))
                    f.fill(Path(ellipseIn: nucleus.insetBy(dx: nr * 0.55, dy: nr * 0.45)), with: .color(.white.opacity(0.4 * red)))
                }
            }
        }
        v.stroke(circle, with: .color(.white.opacity(0.25)), lineWidth: 1.5)
        // scale bar
        var bar = Path()
        bar.move(to: CGPoint(x: ctr.x + R * 0.28, y: ctr.y + R * 0.72)); bar.addLine(to: CGPoint(x: ctr.x + R * 0.62, y: ctr.y + R * 0.72))
        v.stroke(bar, with: .color(.white.opacity(0.8)), lineWidth: 2)
        // the channels, lit as they come in
        for (k, ch) in channels.enumerated() {
            let on = easeOut((t - ch.at) / 0.4)
            let y = ctr.y - 34 + CGFloat(k) * 26
            let x = ctr.x + R + 18
            v.fill(Path(ellipseIn: CGRect(x: x, y: y - 5, width: 10, height: 10)), with: .color(Color(hex: ch.hex).opacity(0.25 + 0.75 * on)))
            if on > 0 {
                v.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 10, width: 20, height: 20)),
                       with: .radialGradient(Gradient(colors: [Color(hex: ch.hex).opacity(0.45 * on), .clear]), center: CGPoint(x: x + 5, y: y), startRadius: 0, endRadius: 10))
            }
            v.draw(Text(ch.name).font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundColor(.white.opacity(0.35 + 0.6 * on)),
                   at: CGPoint(x: x + 17, y: y), anchor: .leading)
        }
        let merged = easeOut((t - 3.3) / 0.4)
        v.draw(Text("merge").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.85 * merged)),
               at: CGPoint(x: ctr.x + R + 18, y: ctr.y - 34 + 78), anchor: .leading)
    }
}
