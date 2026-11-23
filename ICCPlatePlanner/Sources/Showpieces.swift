import SwiftUI
import AppKit
import QuartzCore
import Combine

// MARK: - Showpieces: the spectral strip, deep wells and the mixing tube
//
// Like the other effects, each is Core Animation layers in its own small view: pictures drawn once and then
// only moved, scaled or faded, so nothing in SwiftUI redraws while they play.

// MARK: the dyes' light

/// One dye's emission, modelled from its published peak: a quick rise and a long red tail, and the laser
/// line that excites it on a four-laser confocal.
struct Emission: Equatable {
    let name: String
    let hex: String
    let peak: Double
    let left: Double, right: Double
    let laser: Int

    func value(_ x: Double) -> Double {
        let s = x < peak ? left : right
        return exp(-0.5 * pow((x - peak) / s, 2))
    }
}

enum Spectra {
    /// Emission peaks (nm) of the Alexa Fluor dyes, by their number.
    static let peaks: [Int: Double] = [350: 442, 405: 421, 430: 541, 488: 519, 514: 540, 532: 554, 546: 573, 555: 565,
                                       568: 603, 594: 617, 633: 647, 647: 665, 660: 690, 680: 702, 700: 719, 750: 775, 790: 805]
    static let lasers = [405, 488, 561, 640]
    static let laserHex: [Int: String] = [405: "A07CFF", 488: "2BC7FF", 561: "C8F23A", 640: "FF4B4B"]
    static let range: ClosedRange<Double> = 400...780

    static func emission(_ f: Fluor) -> Emission {
        if f.counterstain { return Emission(name: f.name, hex: f.hex, peak: 461, left: 22, right: 45, laser: 405) }
        var peak = peaks[f.wavelength] ?? Double(f.wavelength) + 20
        switch f.name {
        case "Cy3": peak = 570
        case "Cy5": peak = 670
        case "Texas Red": peak = 615
        case "FITC": peak = 520
        default: break
        }
        let ex = f.wavelength
        let laser = ex <= 440 ? 405 : (ex <= 520 ? 488 : (ex <= 620 ? 561 : 640))
        return Emission(name: f.name, hex: f.hex, peak: peak, left: 14, right: 30, laser: laser)
    }

    static func emissions(_ channels: [Channel]) -> [Emission] {
        var seen = Set<String>()
        return channels.map { emission($0.fluor) }.filter { seen.insert($0.name).inserted }.sorted { $0.peak < $1.peak }
    }

    /// How much of one dye's light lands in the other's detection window (its peak −10 to +25 nm), relative
    /// to that dye's own light there; the worse of the two directions.
    static func crosstalk(_ a: Emission, _ b: Emission) -> Double {
        func into(_ s: Emission, _ t: Emission) -> Double {
            var sv = 0.0, tv = 0.0
            for x in stride(from: t.peak - 10, to: t.peak + 25, by: 1) { sv += s.value(x); tv += t.value(x) }
            return tv > 0 ? sv / tv : 0
        }
        return max(into(a, b), into(b, a))
    }

    struct Overlap: Equatable {
        let a: Emission, b: Emission
        let amount: Double
        /// Excited by the same laser: scanning one laser at a time cannot pull them apart.
        var sameLaser: Bool { a.laser == b.laser }
    }

    static func overlaps(_ e: [Emission]) -> [Overlap] {
        var out: [Overlap] = []
        for i in e.indices {
            for j in e.indices where j > i {
                let k = crosstalk(e[i], e[j])
                if k >= 0.15 { out.append(Overlap(a: e[i], b: e[j], amount: k)) }
            }
        }
        return out
    }

    /// What to do about the overlaps, if anything.
    static func advice(_ e: [Emission]) -> (text: String, severe: Bool) {
        let o = overlaps(e)
        if let bad = o.first(where: { $0.sameLaser }) {
            return ("\(bad.a.name) and \(bad.b.name) share the \(bad.a.laser) laser and overlap: they will bleed into each other. Pick dyes further apart.", true)
        }
        if let mild = o.first {
            return ("\(mild.a.name) and \(mild.b.name) overlap: scan them one laser at a time (sequential) to keep them apart.", false)
        }
        if e.count < 2 { return ("One channel: nothing to bleed into.", false) }
        return ("The channels are well apart.", false)
    }
}

/// A stain's spectrum, on its card: each dye's light, and where two would bleed into each other the overlap
/// glows amber, with what to do about it. Picking the stain plays it: the lasers fire and the light rises.
struct SpectralStrip: View {
    let channels: [Channel]
    let motion: Bool
    /// The stain picked to paint with.
    let active: Bool
    /// Gently moving (the app in front, Animations on).
    var alive = false

    var body: some View {
        let em = Spectra.emissions(channels)
        let advice = Spectra.advice(em)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("SPECTRUM").font(.system(size: 9.5, weight: .bold, design: .serif)).tracking(1.2).foregroundColor(Brand.mid)
                Spacer(minLength: 0)
                Text("lasers 405 · 488 · 561 · 640 nm").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            SpectrumView(emissions: em, motion: motion, active: active, alive: alive)
                .frame(height: 74)
                .accessibilityHidden(true)
            Label(advice.text, systemImage: advice.severe ? "exclamationmark.triangle.fill" : (em.count > 1 && !Spectra.overlaps(em).isEmpty ? "info.circle" : "checkmark.circle"))
                .font(.system(size: 11))
                .foregroundColor(advice.severe ? Color(hex: "B26A00") : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.pale.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(active ? Brand.mid.opacity(0.6) : Brand.rule, lineWidth: 1))
    }
}

struct SpectrumView: NSViewRepresentable {
    let emissions: [Emission]
    let motion: Bool
    let active: Bool
    let alive: Bool
    func makeNSView(context: Context) -> SpectrumNSView { SpectrumNSView(frame: .zero) }
    func updateNSView(_ v: SpectrumNSView, context: Context) {
        v.show(emissions, motion: motion, active: active)
        v.set(alive: alive && motion)
    }
}

final class SpectrumNSView: NSView {
    private let space = CALayer(), back = CALayer()
    private var shown: [Emission]?
    private var shownActive = false
    /// What to draw, and whether to play it.
    private var wanted: ([Emission], Bool)?
    private var drawn: [CALayer] = []
    private static var backs: [String: CGImage] = [:]
    /// The parts that keep moving: the stain's laser beams, its dye curves, and a detector line.
    private var beams: [CALayer] = []
    private var curves: [(CAShapeLayer, String)] = []
    private let sweep = CALayer()
    private var alive = false
    /// When the one-time firing ends, so the gentle loops start after it.
    private var settledAt: CFTimeInterval = 0

    /// Keep it gently moving, or still.
    func set(alive: Bool) {
        guard alive != self.alive else { return }
        self.alive = alive
        loops()
    }

    /// The gentle motion, all looping animations the window server runs: a detector line sweeping across the
    /// wavelengths, the stain's lasers pulsing softly, its dye curves glowing up and down.
    private func loops() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for b in beams { b.removeAnimation(forKey: "pulse") }
        for (c, _) in curves { c.removeAnimation(forKey: "breathe") }
        sweep.removeAnimation(forKey: "sweep")
        sweep.opacity = 0
        guard alive, bounds.width > 40, !curves.isEmpty else { return }
        let start = max(CACurrentMediaTime(), settledAt)
        let p = plot
        sweep.bounds = CGRect(x: 0, y: 0, width: 14, height: p.height + 4)
        sweep.contents = Self.beam("FFFFFF", height: p.height + 4)
        sweep.position = CGPoint(x: p.minX, y: p.midY)
        sweep.zPosition = 5
        if sweep.superlayer == nil { space.addSublayer(sweep) }
        let s = CAAnimationGroup()
        s.animations = [frames("position.x", [p.minX, p.maxX], [0, 1], 4.5, .linear), frames("opacity", [0, 0.35, 0.35, 0], [0, 0.08, 0.92, 1], 4.5)]
        s.duration = 4.5
        s.repeatCount = .infinity
        s.beginTime = start + 0.6
        s.fillMode = .backwards
        sweep.add(s, forKey: "sweep")
        for (k, b) in beams.enumerated() {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 0.22; a.toValue = 0.7
            a.duration = 1.6
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.beginTime = start + Double(k) * 0.55
            b.add(a, forKey: "pulse")
        }
        for (k, (c, hex)) in curves.enumerated() {
            let a = CABasicAnimation(keyPath: "fillColor")
            a.fromValue = cg(hex, 0.22); a.toValue = cg(hex, 0.46)
            a.duration = 2.2
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.beginTime = start + Double(k) * 0.8
            c.add(a, forKey: "breathe")
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        space.isGeometryFlipped = true
        layer?.addSublayer(space)
        space.addSublayer(back)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); play() }
    override func layout() { super.layout(); play() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); play() }

    /// Drawn still the first time (the window opening stays quiet); played when the stain is picked or its
    /// dyes change.
    func show(_ e: [Emission], motion: Bool, active: Bool) {
        let first = shown == nil && wanted == nil
        let picked = active && !shownActive
        shownActive = active
        guard e != shown || picked else { return }
        wanted = (e, motion && !first)
        play()
    }

    private var plot: CGRect { CGRect(x: 10, y: 12, width: bounds.width - 20, height: bounds.height - 30) }
    private func x(_ nm: Double) -> CGFloat {
        let r = Spectra.range
        return plot.minX + plot.width * CGFloat((nm - r.lowerBound) / (r.upperBound - r.lowerBound))
    }

    /// Draws (and plays) once the view has its size and a window.
    private func play() {
        guard let (e, animate) = wanted, bounds.width > 40, bounds.height > 30, window != nil else { return }
        wanted = nil
        shown = e
        let size = bounds.size, p = plot
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        space.frame = bounds
        drawn.forEach { $0.removeFromSuperlayer() }
        drawn = []
        beams = []
        curves = []
        back.frame = bounds
        let key = "\(Int(size.width))x\(Int(size.height))"
        if Self.backs[key] == nil { Self.backs[key] = renderImage(size, screenScale) { c in self.drawBack(c, size) } }
        back.contents = Self.backs[key]
        let base = p.maxY
        // the dyes' light, each as a filled curve rising from the baseline
        func curve(_ f: (Double) -> Double) -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x(Spectra.range.lowerBound), y: p.height))
            for nm in stride(from: Spectra.range.lowerBound, through: Spectra.range.upperBound, by: 2) {
                path.addLine(to: CGPoint(x: x(nm), y: p.height * CGFloat(1 - 0.92 * f(nm))))
            }
            path.addLine(to: CGPoint(x: x(Spectra.range.upperBound), y: p.height))
            path.closeSubpath()
            return path
        }
        func lay(_ l: CALayer) {
            l.anchorPoint = CGPoint(x: 0.5, y: 1)
            l.bounds = CGRect(x: 0, y: 0, width: size.width, height: p.height)
            l.position = CGPoint(x: size.width / 2, y: base)
            space.addSublayer(l)
            drawn.append(l)
        }
        // lasers: the ones this stain uses fire, in order
        let used = Spectra.lasers.filter { l in e.contains { $0.laser == l } }
        var fireAt: [Int: Double] = [:]
        for (k, laser) in used.enumerated() {
            let t = 0.15 + Double(k) * 0.22
            fireAt[laser] = t
            let beam = CALayer()
            beam.bounds = CGRect(x: 0, y: 0, width: 12, height: p.height + 6)
            beam.contents = Self.beam(Spectra.laserHex[laser] ?? "FFFFFF", height: p.height + 6)
            beam.position = CGPoint(x: x(Double(laser)), y: p.midY)
            beam.opacity = 0.3
            space.addSublayer(beam)
            drawn.append(beam)
            beams.append(beam)
            if animate { beam.run(frames("opacity", [0, 0, 1, 0.3], [0, 0.01, 0.2, 1], 0.9), "fire", delay: t) }
        }
        // the curves
        var lastDone = 0.0
        for d in e {
            let s = CAShapeLayer()
            s.path = curve { d.value($0) }
            s.fillColor = cg(d.hex, 0.30)
            s.strokeColor = cg(d.hex)
            s.lineWidth = 1.4
            s.lineJoin = .round
            lay(s)
            curves.append((s, d.hex))
            let at = (fireAt[d.laser] ?? 0.15) + 0.12 + Double(e.firstIndex(of: d) ?? 0) * 0.05
            lastDone = max(lastDone, at + 0.6)
            if animate {
                s.run(frames("transform.scale.y", [0, 0, 1.06, 1], [0, 0.01, 0.75, 1], 0.6), "rise", delay: at)
            }
            // its name over its peak
            let t = CATextLayer()
            t.string = d.name
            t.font = NSFont.systemFont(ofSize: 9, weight: .bold)
            t.fontSize = 9
            t.foregroundColor = cg(d.hex)
            t.alignmentMode = .center
            t.contentsScale = screenScale
            t.frame = CGRect(x: x(d.peak) - 30, y: p.minY - 11, width: 60, height: 11)
            t.opacity = 1
            space.addSublayer(t)
            drawn.append(t)
            if animate { t.run(frames("opacity", [0, 0, 1], [0, 0.5, 1], 0.6), "show", delay: at) }
        }
        // the overlaps, amber where two dyes would bleed into each other
        for o in Spectra.overlaps(e) {
            let s = CAShapeLayer()
            let path = curve { min(o.a.value($0), o.b.value($0)) }
            s.path = path
            s.fillColor = cg("FFB020", o.sameLaser ? 0.8 : 0.5)
            s.strokeColor = cg("FFD27A", 0.9)
            s.lineWidth = 0.8
            s.shadowColor = cg("FFB020")
            s.shadowOpacity = o.sameLaser ? 0.95 : 0.6
            s.shadowRadius = 5
            s.shadowOffset = .zero
            s.shadowPath = path
            lay(s)
            s.opacity = 0.8
            if animate {
                s.run(frames("opacity", [0, 0, 1, 0.55, 1, 0.8], [0, 0.01, 0.25, 0.5, 0.75, 1], 1.3), "glow", delay: lastDone)
            }
        }
        // the gentle motion carries on once the firing is over
        settledAt = CACurrentMediaTime() + (animate ? lastDone + 0.4 : 0)
        loops()
    }

    /// The dark strip: faint gridlines, the visible spectrum along the bottom, the four laser lines dashed,
    /// and the wavelengths.
    private func drawBack(_ c: CGContext, _ size: CGSize) {
        let p = plot
        let r = CGRect(origin: .zero, size: size)
        c.addPath(CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil))
        c.setFillColor(cg("0B1524")); c.fillPath()
        c.setStrokeColor(cg("FFFFFF", 0.06)); c.setLineWidth(1)
        for nm in stride(from: 450.0, through: 750, by: 50) {
            c.move(to: CGPoint(x: x(nm), y: p.minY)); c.addLine(to: CGPoint(x: x(nm), y: p.maxY)); c.strokePath()
        }
        // the visible spectrum
        let barY = p.maxY + 2
        for nm in stride(from: Spectra.range.lowerBound, to: Spectra.range.upperBound, by: 1) {
            c.setFillColor(cg(spectrumHex(nm), 0.85))
            c.fill(CGRect(x: x(nm), y: barY, width: x(nm + 1) - x(nm) + 0.5, height: 4))
        }
        // the laser lines
        c.setLineDash(phase: 0, lengths: [2, 3])
        for l in Spectra.lasers {
            c.setStrokeColor(cg(Spectra.laserHex[l] ?? "FFFFFF", 0.35)); c.setLineWidth(1)
            c.move(to: CGPoint(x: x(Double(l)), y: p.minY)); c.addLine(to: CGPoint(x: x(Double(l)), y: p.maxY)); c.strokePath()
        }
        c.setLineDash(phase: 0, lengths: [])
        for nm in [400.0, 500, 600, 700] {
            NSAttributedString(string: "\(Int(nm))", attributes: [.font: NSFont.systemFont(ofSize: 8, weight: .medium),
                                                                   .foregroundColor: NSColor(white: 1, alpha: 0.45)])
                .draw(at: CGPoint(x: x(nm) + 2, y: barY + 4))
        }
    }

    /// A laser beam: a bright core with a soft glow, in the laser's colour.
    private static var beams: [String: CGImage] = [:]
    private static func beam(_ hex: String, height: CGFloat) -> CGImage? {
        let key = "\(hex)\(Int(height))"
        if let b = beams[key] { return b }
        let b = renderImage(CGSize(width: 12, height: height), screenScale) { c in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            if let g = CGGradient(colorsSpace: space, colors: [cg(hex, 0), cg(hex, 0.55), cg("FFFFFF", 0.95), cg(hex, 0.55), cg(hex, 0)] as CFArray,
                                  locations: [0, 0.3, 0.5, 0.7, 1]) {
                c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 12, y: 0), options: [])
            }
        }
        beams[key] = b
        return b
    }
}

/// The colour of light at `nm`, roughly, for the spectrum bar.
func spectrumHex(_ nm: Double) -> String {
    var r = 0.0, g = 0.0, b = 0.0
    switch nm {
    case ..<440: r = -(nm - 440) / 60; b = 1
    case ..<490: g = (nm - 440) / 50; b = 1
    case ..<510: g = 1; b = -(nm - 510) / 20
    case ..<580: r = (nm - 510) / 70; g = 1
    case ..<645: r = 1; g = -(nm - 645) / 65
    default: r = 1
    }
    let fade = nm < 420 ? 0.4 + 0.6 * (nm - 380) / 40 : (nm > 700 ? max(0.3, 1 - (nm - 700) / 100) : 1)
    func h(_ v: Double) -> Int { Int(max(0, min(1, v * fade)) * 255) }
    return String(format: "%02X%02X%02X", h(r), h(g), h(b))
}

// MARK: - Deep wells

/// The wells' depth: a soft shadow inside each well that shifts as the plate tilts, as if the light stayed
/// put while the plate leaned. One picture of all 96 shadows, moved under a mask of the wells.
struct DeepWells: NSViewRepresentable {
    let tilt: TiltModel
    let cw: CGFloat, ch: CGFloat
    func makeNSView(context: Context) -> DeepWellsView { DeepWellsView(tilt: tilt, cw: cw, ch: ch) }
    func updateNSView(_ v: DeepWellsView, context: Context) {}
}

final class DeepWellsView: NSView {
    private let well = CALayer(), shade = CALayer(), light = CALayer(), mask = CAShapeLayer()
    private let cw: CGFloat, ch: CGFloat
    private var watch: AnyCancellable?
    private static let margin: CGFloat = 14
    private static var pictures: [String: CGImage] = [:]

    init(tilt: TiltModel, cw: CGFloat, ch: CGFloat) {
        self.cw = cw; self.ch = ch
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true
        well.isGeometryFlipped = true
        well.mask = mask
        well.addSublayer(shade)
        well.addSublayer(light)
        layer?.addSublayer(well)
        watch = Publishers.CombineLatest(tilt.$x, tilt.$y).sink { [weak self] x, y in self?.lean(x, y) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); fit() }
    override func layout() { super.layout(); fit() }

    private var fitted = CGSize.zero
    private func fit() {
        let size = bounds.size
        guard size.width > 10, size.height > 10, size != fitted else { return }
        fitted = size
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        well.frame = bounds
        let m = Self.margin
        let wells = CGMutablePath()
        let box = FxView.wellBox(cw: cw, ch: ch)
        for i in 0..<8 {
            for j in 0..<12 {
                let r = CGRect(x: CGFloat(j) * cw + (cw - box.width) / 2, y: CGFloat(i) * ch + (ch - box.height) / 2, width: box.width, height: box.height)
                wells.addPath(CGPath(roundedRect: r, cornerWidth: 8, cornerHeight: 8, transform: nil))
            }
        }
        mask.frame = bounds
        mask.path = wells
        let full = CGSize(width: size.width + 2 * m, height: size.height + 2 * m)
        let key = "\(Int(size.width))x\(Int(size.height))"
        if Self.pictures["s" + key] == nil {
            Self.pictures["s" + key] = renderImage(full, screenScale) { c in Self.drawRim(c, cw: self.cw, ch: self.ch, m: m, colour: cg("000000", 0.95), blur: 8) }
            Self.pictures["l" + key] = renderImage(full, screenScale) { c in Self.drawRim(c, cw: self.cw, ch: self.ch, m: m, colour: cg("CFE3FF", 0.4), blur: 3.5) }
        }
        for (l, k) in [(shade, "s"), (light, "l")] {
            l.bounds = CGRect(origin: .zero, size: full)
            l.contents = Self.pictures[k + key]
        }
        place(0, 0)
    }

    /// The shadow falls from the wall nearest the light, the far wall catches it.
    private func place(_ x: CGFloat, _ y: CGFloat) {
        let c = CGPoint(x: fitted.width / 2, y: fitted.height / 2)
        shade.position = CGPoint(x: c.x - x * 5, y: c.y + 2.5 - y * 5)
        light.position = CGPoint(x: c.x + x * 4, y: c.y - 2.5 + y * 4)
    }

    /// Lean the shadows: away from the side of the plate that dips towards the pointer.
    private func lean(_ x: CGFloat, _ y: CGFloat) {
        guard fitted != .zero else { return }
        CATransaction.begin(); CATransaction.setAnimationDuration(0.14)
        place(x, y)
        CATransaction.commit()
    }

    /// The shadow each well's wall casts inward: only the blurred shadow of a ring round the well is drawn
    /// (the ring itself is far off the picture), so it is soft all the way in.
    private static func drawRim(_ c: CGContext, cw: CGFloat, ch: CGFloat, m: CGFloat, colour: CGColor, blur: CGFloat) {
        let box = FxView.wellBox(cw: cw, ch: ch)
        let far: CGFloat = 4000
        c.setShadow(offset: CGSize(width: -far, height: 0), blur: blur, color: colour)
        c.setFillColor(cg("000000"))
        for i in 0..<8 {
            for j in 0..<12 {
                let r = CGRect(x: m + CGFloat(j) * cw + (cw - box.width) / 2 + far, y: m + CGFloat(i) * ch + (ch - box.height) / 2,
                               width: box.width, height: box.height)
                let ring = CGMutablePath()
                ring.addPath(CGPath(roundedRect: r.insetBy(dx: -9, dy: -9), cornerWidth: 12, cornerHeight: 12, transform: nil))
                ring.addPath(CGPath(roundedRect: r, cornerWidth: 8, cornerHeight: 8, transform: nil))
                c.addPath(ring)
                c.fillPath(using: .evenOdd)
            }
        }
    }
}

// MARK: - The mixing tube

/// A little tube on each stain card holding its mix: wisps of each dye swirl through the buffer and specks of
/// antibody drift up, all the time the app is in front. When the volume or a dilution changes it fills again
/// in layers (buffer, then each dye) and swirls them into one. The swirl is a few looping Core Animation
/// layers: the window server moves them, the app does nothing per frame.
struct MixTube: NSViewRepresentable {
    let dyes: [String]
    let level: CGFloat
    let key: String
    let motion: Bool
    /// Swirling (the app in front, Animations on).
    let alive: Bool
    func makeNSView(context: Context) -> MixTubeView { MixTubeView(frame: .zero) }
    func updateNSView(_ v: MixTubeView, context: Context) { v.show(dyes: dyes, level: level, key: key, motion: motion, alive: alive) }
}

final class MixTubeView: NSView {
    private let space = CALayer(), glass = CALayer(), liquid = CALayer(), liquidMask = CAShapeLayer()
    private let mixed = CALayer(), swirl = CALayer(), wispsA = CALayer(), wispsB = CALayer(), shine = CALayer()
    /// The liquid itself: the wisps and specks stay inside it, below the surface.
    private let pond = CALayer()
    private var specks: [CALayer] = []
    private var bands: [CALayer] = []
    private var shownKey: String?
    private var wanted: (dyes: [String], level: CGFloat, key: String, motion: Bool)?
    private var alive = false
    /// The liquid as last laid out: its rectangle in the tube, and the dyes in it.
    private var pool = CGRect.zero
    private var dyes: [String] = []
    private static let buffer = "DDE8F4"
    private static var wispPictures: [String: CGImage] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        space.isGeometryFlipped = true
        layer?.addSublayer(space)
        liquid.mask = liquidMask
        pond.masksToBounds = true
        for l in [mixed, pond, swirl, shine] { liquid.addSublayer(l) }
        for l in [wispsA, wispsB] { pond.addSublayer(l) }
        for _ in 0..<4 {
            let d = CALayer()
            d.bounds = CGRect(x: 0, y: 0, width: 1.8, height: 1.8)
            d.cornerRadius = 0.9
            d.opacity = 0
            pond.addSublayer(d)
            specks.append(d)
        }
        space.addSublayer(liquid)
        space.addSublayer(glass)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); play() }
    override func layout() { super.layout(); play() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); play() }

    func show(dyes: [String], level: CGFloat, key: String, motion: Bool, alive: Bool) {
        let wasAlive = self.alive
        self.alive = alive && motion
        if key != shownKey {
            wanted = (dyes, level, key, motion)
            play()
        } else if self.alive != wasAlive {
            stir()
        }
    }

    private func tubePath(_ r: CGRect) -> CGPath {
        let p = CGMutablePath()
        let rad = r.width / 2
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - rad))
        p.addArc(center: CGPoint(x: r.midX, y: r.maxY - rad), radius: rad, startAngle: .pi, endAngle: 0, clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }

    /// The mix once swirled: mostly buffer, tinted by the dyes' combined light (averaging their colours as
    /// paint turned a green and a red dye into mud).
    private static func mixHex(_ dyes: [String]) -> String {
        guard let light = mergeHex(dyes) else { return buffer }
        func rgb(_ h: String) -> (Double, Double, Double) {
            let v = UInt32(h, radix: 16) ?? 0
            return (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
        }
        let (r1, g1, b1) = rgb(light), (r0, g0, b0) = rgb(buffer)
        func mix(_ d: Double, _ base: Double) -> Int { Int(d * 0.38 + base * 0.62) }
        return String(format: "%02X%02X%02X", mix(r1, r0), mix(g1, g0), mix(b1, b0))
    }

    /// Wisps of each dye winding up through the liquid, twice over so the picture loops seamlessly when it
    /// has moved up by one liquid-height.
    private static func wisps(_ dyes: [String], width: CGFloat, height: CGFloat, mirrored: Bool) -> CGImage? {
        let key = dyes.joined(separator: ",") + "|\(Int(width))x\(Int(height))\(mirrored)"
        if let w = wispPictures[key] { return w }
        let all = dyes.isEmpty ? ["9FB7D6"] : dyes
        let w = renderImage(CGSize(width: width, height: height * 2), screenScale) { c in
            c.setLineCap(.round)
            for (k, hex) in all.enumerated() {
                for strand in 0..<1 {
                    let phase = Double(k) * 2.1 + Double(strand) * 3.3 + (mirrored ? 1.4 : 0)
                    let amp = width * 0.3
                    let path = CGMutablePath()
                    var y: CGFloat = 0
                    path.move(to: CGPoint(x: width / 2 + CGFloat(sin(phase)) * amp, y: 0))
                    while y <= height * 2 {
                        y += 1
                        let t = Double(y / height) * 2 * .pi
                        path.addLine(to: CGPoint(x: width / 2 + CGFloat(sin(t + phase)) * amp, y: y))
                    }
                    c.saveGState()
                    c.setShadow(offset: .zero, blur: 2.6, color: cg(hex, 0.7))
                    c.addPath(path); c.setStrokeColor(cg(hex, 0.5)); c.setLineWidth(1.8); c.strokePath()
                    c.restoreGState()
                }
            }
        }
        wispPictures[key] = w
        return w
    }

    private func play() {
        guard let w = wanted, bounds.width > 6, bounds.height > 10 else { return }
        wanted = nil
        let replay = shownKey != nil && w.motion
        shownKey = w.key
        let b = bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        space.frame = b
        let inner = b.insetBy(dx: 2, dy: 1.5)
        glass.frame = b
        glass.contents = renderImage(b.size, screenScale) { c in
            let t = self.tubePath(b.insetBy(dx: 1.2, dy: 0.8))
            c.addPath(t); c.setFillColor(cg("FFFFFF", 0.18)); c.fillPath()
            c.addPath(t); c.setStrokeColor(cg("5F6B7C", 0.8)); c.setLineWidth(1); c.strokePath()
            c.setStrokeColor(cg("FFFFFF", 0.7)); c.setLineWidth(0.8)
            c.move(to: CGPoint(x: b.minX + 3.4, y: b.minY + 3)); c.addLine(to: CGPoint(x: b.minX + 3.4, y: b.maxY - b.width * 0.6)); c.strokePath()
        }
        liquid.frame = b
        liquidMask.path = tubePath(inner)
        liquidMask.frame = b
        let top = inner.maxY - inner.height * max(0.15, min(0.92, w.level))
        let height = inner.maxY - top
        pool = CGRect(x: inner.minX, y: top, width: inner.width, height: height)
        dyes = w.dyes
        mixed.frame = pool
        mixed.backgroundColor = cg(Self.mixHex(w.dyes))
        // the meniscus catching the light
        shine.frame = CGRect(x: pool.minX, y: pool.minY, width: pool.width, height: 1.2)
        shine.backgroundColor = cg("FFFFFF", 0.7)
        pond.frame = pool
        for (l, mirrored) in [(wispsA, false), (wispsB, true)] {
            l.anchorPoint = CGPoint(x: 0.5, y: 0)
            l.bounds = CGRect(x: 0, y: 0, width: pool.width, height: pool.height * 2)
            l.position = CGPoint(x: pool.width / 2, y: -pool.height)
            l.contents = Self.wisps(w.dyes, width: pool.width, height: pool.height, mirrored: mirrored)
        }
        for (k, d) in specks.enumerated() { d.backgroundColor = cg(w.dyes.isEmpty ? "FFFFFF" : w.dyes[k % w.dyes.count]) }
        bands.forEach { $0.removeFromSuperlayer() }
        bands = []
        stir()
        guard replay else {
            mixed.opacity = 1
            swirl.opacity = 0
            return
        }
        // poured in layers: buffer first, then each dye
        let colours = [Self.buffer] + w.dyes
        let share = height / CGFloat(colours.count)
        for (k, hex) in colours.enumerated() {
            let l = CALayer()
            l.anchorPoint = CGPoint(x: 0.5, y: 1)
            l.bounds = CGRect(x: 0, y: 0, width: inner.width, height: share + 0.5)
            l.position = CGPoint(x: inner.midX, y: inner.maxY - CGFloat(k) * share)
            l.backgroundColor = cg(hex)
            l.opacity = 0
            liquid.insertSublayer(l, below: mixed)
            bands.append(l)
            let g = CAAnimationGroup()
            g.animations = [frames("transform.scale.y", [0, 1], [0, 1], 0.22, .easeOut),
                            frames("opacity", [1, 1, 1, 0], [0, 0.2, 0.75, 1], 1.7)]
            g.duration = 1.7
            l.run(g, "pour", delay: Double(k) * 0.16)
        }
        let poured = Double(colours.count) * 0.16 + 0.25
        // then swirled into one, and the wisps come back
        mixed.opacity = 1
        mixed.run(frames("opacity", [0, 0, 1], [0, 0.01, 1], 0.7), "mix", delay: poured)
        for l in [wispsA, wispsB] { l.run(frames("opacity", [0, 0, 1], [0, 0.01, 1], 0.9), "back", delay: poured + 0.3) }
        swirl.frame = CGRect(x: inner.minX - 2, y: top, width: inner.width + 4, height: height)
        swirl.contents = renderImage(swirl.bounds.size, screenScale) { c in
            let s = self.swirl.bounds.size
            c.setStrokeColor(cg("FFFFFF", 0.75)); c.setLineWidth(1.3); c.setLineCap(.round)
            c.move(to: CGPoint(x: 1, y: s.height * 0.9))
            var y = s.height * 0.9
            var k = 0
            while y > s.height * 0.1 {
                k += 1
                c.addQuadCurve(to: CGPoint(x: k % 2 == 0 ? 1 : s.width - 1, y: y - s.height * 0.2),
                               control: CGPoint(x: s.width / 2, y: y - s.height * 0.05))
                y -= s.height * 0.2
            }
            c.strokePath()
        }
        swirl.opacity = 0
        let sg = CAAnimationGroup()
        sg.animations = [frames("opacity", [0, 0.9, 0], [0, 0.3, 1], 0.9),
                         frames("transform.scale.x", [1, -1, 1], [0, 0.5, 1], 0.9)]
        sg.duration = 0.9
        swirl.run(sg, "swirl", delay: poured - 0.05)
    }

    /// The ongoing swirl: two layers of wisps winding up at different speeds, swaying against each other, and
    /// specks of antibody drifting up. Looping animations the window server runs on its own; removed while
    /// the app is in the background or Animations is off.
    private func stir() {
        guard pool.height > 2 else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let layers = [wispsA, wispsB] + specks
        guard alive else {
            for l in layers { l.removeAnimation(forKey: "flow"); l.removeAnimation(forKey: "sway") }
            wispsA.opacity = 0.5; wispsB.opacity = 0.3
            for d in specks { d.opacity = 0 }
            return
        }
        let h = pool.height, mid = pool.width / 2
        wispsA.opacity = 0.6; wispsB.opacity = 0.38
        for (l, period, sway) in [(wispsA, 5.5, 1.4), (wispsB, 8.0, -1.8)] {
            // up by one liquid-height, where the picture repeats, over and over
            let flow = CABasicAnimation(keyPath: "position.y")
            flow.fromValue = 0
            flow.toValue = -h
            flow.duration = period
            flow.repeatCount = .infinity
            l.position.y = -h
            l.add(flow, forKey: "flow")
            let s = CABasicAnimation(keyPath: "position.x")
            s.fromValue = mid - CGFloat(sway); s.toValue = mid + CGFloat(sway)
            s.duration = period * 0.37
            s.autoreverses = true
            s.repeatCount = .infinity
            s.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            l.add(s, forKey: "sway")
        }
        for (k, d) in specks.enumerated() {
            let x = pool.width * CGFloat(0.25 + 0.5 * hash01(k, 91))
            d.position = CGPoint(x: x, y: h)
            let g = CAAnimationGroup()
            let life = 3.2 + 1.3 * hash01(k, 93)
            g.animations = [frames("position.y", [h - 1, 1], [0, 1], life, .linear),
                            frames("position.x", [x, x + 1.5, x - 1.5, x], [0, 0.33, 0.66, 1], life),
                            frames("opacity", [0, 0.95, 0.95, 0], [0, 0.15, 0.8, 1], life)]
            g.duration = life
            g.repeatCount = .infinity
            g.beginTime = CACurrentMediaTime() + Double(k) * 0.9
            g.fillMode = .backwards
            d.add(g, forKey: "flow")
        }
    }
}

// MARK: - Cold mist from the fridge buttons

/// Cold air spilling out of a fridge: a few faint, pale-blue wisps that sink from behind the button, spread
/// and fade, over and over. Looping layers the window server runs; stopped in the background or with
/// Animations off.
struct ColdMist: NSViewRepresentable {
    let alive: Bool
    func makeNSView(context: Context) -> ColdMistView { ColdMistView(frame: .zero) }
    func updateNSView(_ v: ColdMistView, context: Context) { v.set(alive: alive) }
}

final class ColdMistView: NSView {
    private let space = CALayer()
    private var wisps: [CALayer] = []
    private var alive = false
    private var laidOut = CGSize.zero
    /// One wisp: pale on the dark room's navy, a deeper icy blue so it still shows on a white card.
    private static func wisp(dark: Bool) -> CGImage? {
        renderImage(CGSize(width: 60, height: 30), screenScale) { c in
            c.scaleBy(x: 1, y: 0.5)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let core = dark ? cg("CFE7FB", 0.85) : cg("8EC3EE", 0.8), edge = dark ? cg("D8ECFC", 0.35) : cg("A9D2F3", 0.32)
            if let g = CGGradient(colorsSpace: space, colors: [core, edge, cg("D8ECFC", 0)] as CFArray, locations: [0, 0.5, 1]) {
                c.drawRadialGradient(g, startCenter: CGPoint(x: 30, y: 30), startRadius: 0, endCenter: CGPoint(x: 30, y: 30), endRadius: 30, options: [])
            }
        }
    }
    private static let wisps = (light: wisp(dark: false), dark: wisp(dark: true))

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        space.isGeometryFlipped = true
        layer?.addSublayer(space)
        for _ in 0..<3 {
            let w = CALayer()
            w.bounds = CGRect(x: 0, y: 0, width: 60, height: 30)
            w.contents = Theme.dark ? Self.wisps.dark : Self.wisps.light
            w.opacity = 0
            space.addSublayer(w)
            wisps.append(w)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); restart() }

    func set(alive: Bool) {
        guard alive != self.alive else { return }
        self.alive = alive
        restart()
    }

    private func restart() {
        let size = bounds.size
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        space.frame = bounds
        for w in wisps { w.removeAllAnimations() }
        guard alive, size.width > 20, size.height > 10 else { return }
        laidOut = size
        for (k, w) in wisps.enumerated() {
            let x = size.width * CGFloat(0.2 + 0.3 * Double(k)), y = size.height * 0.72
            w.position = CGPoint(x: x, y: y)
            let life = 3.4 + 0.6 * Double(k)
            let g = CAAnimationGroup()
            g.animations = [frames("position", [NSValue(point: CGPoint(x: x, y: y)), NSValue(point: CGPoint(x: x + CGFloat(k - 1) * 10, y: y + 12))], [0, 1], life, .easeOut),
                            frames("transform.scale", [0.5, 1.5], [0, 1], life, .easeOut),
                            frames("opacity", [0, 0.75, 0], [0, 0.3, 1], life)]
            g.duration = life
            g.repeatCount = .infinity
            g.beginTime = CACurrentMediaTime() + Double(k) * 1.15
            g.fillMode = .backwards
            w.add(g, forKey: "mist")
        }
    }
}

// MARK: - The live Dock icon

/// The app's Dock icon with a miniature of the plate in its stain colours; while an export scans, a bar under
/// the plate fills with its progress. Redrawn only after changes settle, and only when the progress moves.
final class DockPlate {
    static let shared = DockPlate()
    private var cells: [String?] = Array(repeating: nil, count: 96)
    private var progress: Double?
    private var work: DispatchWorkItem?

    func update(_ store: Store) {
        work?.cancel()
        let w = DispatchWorkItem { [weak store] in
            guard let store else { return }
            let ids = store.exp.sets.map { $0.id }
            self.cells = (0..<96).map { w in
                store.exp.wells[w].flatMap { id in ids.firstIndex(of: id) }.map { fillHex(store.exp.sets[$0], $0) }
            }
            self.draw()
        }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }

    func setProgress(_ p: Double?) {
        if let p, let q = progress, abs(p - q) < 0.04, p < 1 { return }
        if p == nil && progress == nil { return }
        progress = p
        draw()
    }

    private func draw() {
        guard let img = picture() else { return }
        let v = NSImageView(image: img)
        NSApp.dockTile.contentView = v
        NSApp.dockTile.display()
    }

    /// The icon as it is drawn into the Dock.
    func picture() -> NSImage? {
        guard let icon = NSApp.applicationIconImage else { return nil }
        let cells = self.cells, progress = self.progress
        return NSImage(size: NSSize(width: 256, height: 256), flipped: true) { r in
            icon.draw(in: r)
            // the plate, lower right
            let plate = NSRect(x: 100, y: 132, width: 146, height: 104)
            NSColor(white: 0, alpha: 0.35).setFill()
            NSBezierPath(roundedRect: plate.offsetBy(dx: 0, dy: 3), xRadius: 12, yRadius: 12).fill()
            NSColor(hex: "1A222D").setFill()
            NSBezierPath(roundedRect: plate, xRadius: 12, yRadius: 12).fill()
            NSColor(white: 1, alpha: 0.25).setStroke()
            let rim = NSBezierPath(roundedRect: plate.insetBy(dx: 1, dy: 1), xRadius: 11, yRadius: 11); rim.lineWidth = 2; rim.stroke()
            let inner = plate.insetBy(dx: 9, dy: progress == nil ? 9 : 7)
            let cw = inner.width / 12, ch = (inner.height - (progress == nil ? 0 : 10)) / 8
            for w in 0..<96 {
                let cell = NSRect(x: inner.minX + CGFloat(w % 12) * cw + 1, y: inner.minY + CGFloat(w / 12) * ch + 1, width: cw - 2, height: ch - 2)
                if let hex = cells[w] { NSColor(hex: hex).setFill() } else { NSColor(hex: "2C3846").setFill() }
                NSBezierPath(roundedRect: cell, xRadius: 2, yRadius: 2).fill()
            }
            if let p = progress {
                let track = NSRect(x: inner.minX, y: inner.maxY - 6, width: inner.width, height: 5)
                NSColor(white: 1, alpha: 0.2).setFill(); NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()
                NSColor(hex: "5BE38A").setFill()
                NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * CGFloat(max(0.04, min(1, p))), height: track.height),
                             xRadius: 2.5, yRadius: 2.5).fill()
            }
            return true
        }
    }

    /// Development: the cells straight from a store, without waiting.
    func load(_ store: Store) {
        let ids = store.exp.sets.map { $0.id }
        cells = (0..<96).map { w in store.exp.wells[w].flatMap { id in ids.firstIndex(of: id) }.map { fillHex(store.exp.sets[$0], $0) } }
    }
    func devProgress(_ p: Double?) { progress = p }
}

// MARK: - The workbook flies to the Dock

/// When the export finishes, the workbook's icon arcs out of the export window and down into the Dock, the way
/// a download does. A see-through window over the screen carries it for a second.
enum FileFlight {
    private static var overlay: NSWindow?

    static func play(from window: NSWindow?, file: URL) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let sf = screen.frame, vf = screen.visibleFrame
        // where the Dock is: the side of the screen the visible area stops short of
        let target: CGPoint
        if vf.minX - sf.minX > 4 { target = CGPoint(x: sf.minX + (vf.minX - sf.minX) / 2, y: sf.midY) }
        else if sf.maxX - vf.maxX > 4 { target = CGPoint(x: sf.maxX - (sf.maxX - vf.maxX) / 2, y: sf.midY) }
        else { target = CGPoint(x: sf.midX, y: sf.minY + max(24, (vf.minY - sf.minY) / 2)) }
        let start = CGPoint(x: window.frame.midX, y: window.frame.midY)
        overlay?.orderOut(nil)
        let w = NSWindow(contentRect: sf, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.ignoresMouseEvents = true; w.hasShadow = false
        w.level = .statusBar
        w.isReleasedWhenClosed = false
        let v = NSView(frame: NSRect(origin: .zero, size: sf.size))
        v.layer = CALayer(); v.wantsLayer = true
        w.contentView = v
        w.orderFrontRegardless()
        overlay = w
        let icon = CALayer()
        icon.bounds = CGRect(x: 0, y: 0, width: 72, height: 72)
        let img = NSWorkspace.shared.icon(forFile: file.path)
        icon.contents = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let a = CGPoint(x: start.x - sf.minX, y: start.y - sf.minY), b = CGPoint(x: target.x - sf.minX, y: target.y - sf.minY)
        icon.position = b
        icon.opacity = 0
        CATransaction.begin(); CATransaction.setDisableActions(true)
        v.layer?.addSublayer(icon)
        CATransaction.commit()
        let path = CGMutablePath()
        path.move(to: a)
        path.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2, y: max(a.y, b.y) + 160))
        let fly = CAKeyframeAnimation(keyPath: "position")
        fly.path = path
        fly.timingFunction = CAMediaTimingFunction(name: .easeIn)
        let g = CAAnimationGroup()
        g.animations = [fly, frames("transform.scale", [0.6, 1.15, 0.35], [0, 0.25, 1], 0.95), frames("opacity", [0, 1, 1, 0], [0, 0.12, 0.85, 1], 0.95)]
        g.duration = 0.95
        icon.run(g, "fly", delay: 0.15)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            guard overlay === w else { return }
            w.orderOut(nil); overlay = nil
        }
    }
}
