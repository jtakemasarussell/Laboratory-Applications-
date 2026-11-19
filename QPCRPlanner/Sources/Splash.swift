import SwiftUI
import AppKit

// MARK: - Splash
//
// A banner in the manner of Photoshop's: shown for a moment while the app opens (the main window
// waits behind it), and again from "About qPCR Planner". Wells fill and amplification curves rise on
// the right; the laboratory, department and hospital are on the left. A click dismisses it.

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
    static let steps = ["Thawing the master mix…", "Vortexing the primers…", "Spinning down the plate…", "Warming up the qTOWER…", "Ready."]

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
                Text("qPCR Planner")
                    .font(.system(size: 54, weight: .bold, design: .serif))
                    .foregroundColor(.white)
                    .shadow(color: Color(hex: "0B1F3A").opacity(0.5), radius: 12, y: 4)
                    .opacity(title.opacity).offset(y: title.y)
                Text("Master mixes, plate maps and ΔΔCt graphs,\nfrom the bench to the qTOWER.")
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
                .fill(LinearGradient(colors: SplashArt.curveColors.map { Color(hex: $0) }, startPoint: .leading, endPoint: .trailing))
                .frame(width: max(3, 260 * CGFloat(clamp01(p))), height: 3)
        }
    }
}

// MARK: - Artwork

enum SplashArt {
    static let curveColors = ["8CF5A4", "9CCBFF", "FF9A86", "FFD86B"]
    private static let wellColors = ["7FB2FF", "8CF5A4", "FF9A86", "FFD86B"]   // reference + three genes, in blocks of three columns

    static func draw(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let rect = CGRect(origin: .zero, size: size)

        // night-blue ground with two soft glows
        g.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color(hex: "071630"), Color(hex: "0F2F5A"), Color(hex: "1E4A83")]),
                                                 startPoint: CGPoint(x: 0, y: size.height), endPoint: CGPoint(x: size.width, y: 0)))
        g.fill(Path(rect), with: .radialGradient(Gradient(colors: [Color(hex: "5B8BD6").opacity(0.55), .clear]),
                                                 center: CGPoint(x: size.width * 0.8, y: size.height * 0.12), startRadius: 0, endRadius: 380))
        g.fill(Path(rect), with: .radialGradient(Gradient(colors: [Color(hex: "2BB3A3").opacity(0.2), .clear]),
                                                 center: CGPoint(x: size.width * 0.55, y: size.height * 1.05), startRadius: 0, endRadius: 330))

        // faint chart grid on the right
        var grid = Path()
        for x in stride(from: 380.0, through: Double(size.width), by: 34) { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)) }
        for y in stride(from: 16.0, through: Double(size.height), by: 34) { grid.move(to: CGPoint(x: 380, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)) }
        g.stroke(grid, with: .color(.white.opacity(0.045)), lineWidth: 1)

        // rising bubbles
        for i in 0..<16 {
            let seed = Double(i) * 12.9898
            let fx = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
            let x = 400 + abs(fx) * Double(size.width - 420)
            let speed = 18 + Double(i % 5) * 6
            let y = Double(size.height) + 20 - (t * speed + Double(i) * 37).truncatingRemainder(dividingBy: Double(size.height) + 40)
            let r = 1.5 + Double(i % 4) * 0.9
            g.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.16)), lineWidth: 0.8)
        }

        plate(&g, t)
        curves(&g, size, t)
        eppi(&g, size, t)

        // shade behind the words on the left
        g.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color(hex: "071630").opacity(0.55), Color(hex: "071630").opacity(0)]),
                                                 startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 430, y: 0)))
    }

    /// A tilted 96-well plate whose wells fill in a diagonal wave.
    private static func plate(_ g: inout GraphicsContext, _ t: Double) {
        var p = g
        p.translateBy(x: 606, y: 152)
        p.rotate(by: .degrees(-8))
        let pitch: CGFloat = 23
        let w = 12 * pitch + 26, h = 8 * pitch + 26
        let body = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        var outline = Path()
        let cut: CGFloat = 14
        outline.move(to: CGPoint(x: body.minX + cut, y: body.minY))
        outline.addLine(to: CGPoint(x: body.maxX - 10, y: body.minY))
        outline.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + 10), control: CGPoint(x: body.maxX, y: body.minY))
        outline.addLine(to: CGPoint(x: body.maxX, y: body.maxY - 10))
        outline.addQuadCurve(to: CGPoint(x: body.maxX - 10, y: body.maxY), control: CGPoint(x: body.maxX, y: body.maxY))
        outline.addLine(to: CGPoint(x: body.minX + 10, y: body.maxY))
        outline.addQuadCurve(to: CGPoint(x: body.minX, y: body.maxY - 10), control: CGPoint(x: body.minX, y: body.maxY))
        outline.addLine(to: CGPoint(x: body.minX, y: body.minY + cut))
        outline.closeSubpath()
        let appear = easeOut(t / 0.8)
        p.opacity = appear
        p.fill(outline, with: .linearGradient(Gradient(colors: [.white.opacity(0.12), .white.opacity(0.04)]),
                                              startPoint: CGPoint(x: 0, y: body.minY), endPoint: CGPoint(x: 0, y: body.maxY)))
        p.stroke(outline, with: .color(.white.opacity(0.28)), lineWidth: 1.2)
        for r in 0..<8 {
            for c in 0..<12 {
                let center = CGPoint(x: body.minX + 13 + (CGFloat(c) + 0.5) * pitch, y: body.minY + 13 + (CGFloat(r) + 0.5) * pitch)
                let rad: CGFloat = 8
                let well = CGRect(x: center.x - rad, y: center.y - rad, width: rad * 2, height: rad * 2)
                p.fill(Path(ellipseIn: well), with: .color(.white.opacity(0.05)))
                p.stroke(Path(ellipseIn: well), with: .color(.white.opacity(0.2)), lineWidth: 0.8)
                let k = easeOutBack((t - 0.4 - (Double(c) + Double(r) * 0.7) * 0.085) / 0.5)
                guard k > 0 else { continue }
                let hex = wellColors[(c / 3) % wellColors.count]
                let rr = rad * 0.86 * CGFloat(k)
                let glow = CGRect(x: center.x - rr * 1.9, y: center.y - rr * 1.9, width: rr * 3.8, height: rr * 3.8)
                p.fill(Path(ellipseIn: glow), with: .radialGradient(Gradient(colors: [Color(hex: hex).opacity(0.28), .clear]),
                                                                     center: center, startRadius: 0, endRadius: rr * 1.9))
                let liquid = CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)
                p.fill(Path(ellipseIn: liquid), with: .radialGradient(Gradient(colors: [Color(hex: tintHex(hex, 0.6)), Color(hex: hex), Color(hex: shadeHex(hex, 0.2))]),
                                                                       center: CGPoint(x: center.x - rr * 0.3, y: center.y - rr * 0.35), startRadius: 0, endRadius: rr * 1.3))
                p.fill(Path(ellipseIn: CGRect(x: center.x - rr * 0.5, y: center.y - rr * 0.6, width: rr * 0.55, height: rr * 0.32)), with: .color(.white.opacity(0.6)))
            }
        }
    }

    /// Amplification curves rising across the lower right, a glow riding each front.
    private static func curves(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let x0 = 345.0, x1 = Double(size.width) - 30, base = 352.0, height = 150.0
        let mids = [0.36, 0.48, 0.6, 0.72], tops = [1.0, 0.9, 0.78, 0.66]
        let reveal = easeInOut((t - 1.1) / 2.4)
        var axis = Path()
        axis.move(to: CGPoint(x: x0, y: base)); axis.addLine(to: CGPoint(x: x1, y: base))
        g.stroke(axis, with: .color(.white.opacity(0.22)), lineWidth: 1)
        var threshold = Path()
        let ty = base - height * 0.2
        threshold.move(to: CGPoint(x: x0, y: ty)); threshold.addLine(to: CGPoint(x: x1, y: ty))
        g.stroke(threshold, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        g.draw(Text("threshold").font(.system(size: 9, weight: .medium)).foregroundColor(.white.opacity(0.4)),
               at: CGPoint(x: x1, y: ty - 8), anchor: .trailing)
        g.draw(Text("cycles →").font(.system(size: 9, weight: .medium)).foregroundColor(.white.opacity(0.35)),
               at: CGPoint(x: x1, y: base + 10), anchor: .trailing)
        guard reveal > 0 else { return }
        for k in 0..<4 {
            var path = Path()
            var u = 0.0, last = CGPoint.zero
            while u <= reveal {
                let y = base - height * tops[k] / (1 + exp(-(u - mids[k]) * 13))
                last = CGPoint(x: x0 + (x1 - x0) * u, y: y)
                if u == 0 { path.move(to: last) } else { path.addLine(to: last) }
                u += 0.004
            }
            let hex = curveColors[k]
            g.stroke(path, with: .color(Color(hex: hex).opacity(0.18)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            g.stroke(path, with: .color(Color(hex: hex).opacity(0.95)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            if reveal < 1 {
                g.fill(Path(ellipseIn: CGRect(x: last.x - 9, y: last.y - 9, width: 18, height: 18)),
                       with: .radialGradient(Gradient(colors: [.white.opacity(0.8), Color(hex: hex).opacity(0.3), .clear]), center: last, startRadius: 0, endRadius: 9))
            }
        }
    }

    /// Eppi pops up at the end of the run and waves.
    private static func eppi(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let frames = eppiWaveFrames()
        guard !frames.isEmpty else { return }
        let p = easeOutBack((t - 3.3) / 0.5)
        guard p > 0 else { return }
        let i = Int(max(0, t - 3.3) * 12) % frames.count
        let img = frames[t > 9 ? 0 : i]
        let w = 60 * CGFloat(p), h = 85 * CGFloat(p)
        let bottom = CGPoint(x: size.width - 70, y: size.height - 16)
        g.draw(Image(decorative: img, scale: CGFloat(img.width) / 120), in: CGRect(x: bottom.x - w / 2, y: bottom.y - h, width: w, height: h))
    }
}
