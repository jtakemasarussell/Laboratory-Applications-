import SwiftUI
import AppKit
import QuartzCore

// MARK: - Staining preview: the stain set, played out under a microscope
//
// The stain you are painting with goes through the protocol in a field of view: the cells are fixed,
// their membranes opened, the blocking buffer settles, the primaries drift in and bind, the secondaries
// find them by species and carry their dyes, and then each channel lights up on its own before the merge.
// Colours come from the secondaries' dyes (488 green, 594 red, 647 far red shown in magenta, DAPI blue);
// where each marker sits (nucleus, cytoplasm, membrane) follows the marker. Like the banner, everything
// is drawn into images once; the shared 20-frames-a-second clock only moves and fades them.

struct PreviewInfo: Equatable {
    var title: String           // "Stain 1"
    var subtitle: String        // "LMX1A/B + FOXA2 → 488 rab + 594 g"
    var demo: Bool
    var channels: [Channel]
    var details: [String]       // one line (or two) per step
    var seed: Int
    var issues: Int
}

private struct Cell {
    var c: CGPoint
    var rx: CGFloat, ry: CGFloat, angle: CGFloat
    var nucleus: CGPoint
    var nr: CGFloat
    var neurites: [[CGPoint]]
}

let previewStepNames = ["Fix", "Permeabilise", "Block", "1st antibody", "2nd antibody", "Image"]
private let stepShort = ["Fix", "Perm", "Block", "1st Ab", "2nd Ab", "Image"]
private let stepLengths = [1.6, 1.4, 1.6, 2.8, 2.6]
private let perChannel = 1.6, mergeHold = 3.0, holdEnd = 0.8, fadeEnd = 0.8
/// The confocal scan: how long the laser takes to draw one channel, and the merge.
private let scanLength = 0.95, mergeScan = 0.6

private func ellipsePath(_ cell: Cell, grow: CGFloat = 0) -> CGPath {
    var t = CGAffineTransform(translationX: cell.c.x, y: cell.c.y).rotated(by: cell.angle)
    return CGPath(ellipseIn: CGRect(x: -cell.rx - grow, y: -cell.ry - grow, width: 2 * (cell.rx + grow), height: 2 * (cell.ry + grow)), transform: &t)
}

private func neuritePath(_ pts: [CGPoint]) -> CGPath {
    let p = CGMutablePath()
    guard pts.count == 3 else { return p }
    p.move(to: pts[0]); p.addQuadCurve(to: pts[2], control: pts[1])
    return p
}

final class StainingPreviewView: AmbientLayerView {
    /// The compact version projected from a well: only the confocal scan, in a translucent cyan scope.
    var hologram = false
    private let holo = CALayer(), lineLabel = CATextLayer()
    private var info: PreviewInfo?
    private var replay = -1
    private let stage = CALayer()
    private let back = CALayer()
    private let fov = CALayer(), fovMask = CAShapeLayer()
    private let fovBack = CALayer(), phase = CALayer(), perm = CALayer(), haze = CALayer(), darkness = CALayer(), merge = CALayer()
    private let ring = CALayer()
    private var channelLayers: [CALayer] = []
    /// What each channel has been drawn down to so far, and the laser line drawing it.
    private var channelMasks: [CALayer] = []
    private let mergeMask = CALayer(), scanLine = CALayer()
    private var scanImages: [CGImage?] = []
    private var scanWhite: CGImage?
    private var scanShown = -2
    private typealias Flyer = (layer: CALayer, from: CGPoint, to: CGPoint, final: CGFloat, wobble: CGFloat)
    private var ab1: [Flyer] = []
    private var ab2: [Flyer] = []
    private var chips: [CALayer] = []
    private var dots: [CALayer] = []
    private let marker = CALayer(), progress = CALayer()
    private let stepTitle = CATextLayer(), stepDetail = CATextLayer(), fovLabel = CATextLayer()
    private let headTitle = CATextLayer(), headSub = CATextLayer(), headNote = CATextLayer()
    /// A dark pill behind the field-of-view label (cheaper than a text shadow, which would cost a blur every frame).
    private let labelPill = CALayer()
    private var rightX: CGFloat = 0, pad: CGFloat = 14
    /// What the images depend on. Typing an antibody's name changes the words but not this, so only the
    /// words are redrawn; the cells and channels are drawn again only when a dye or a marker's place changes.
    private struct Look: Equatable { var dyes: [String]; var places: [String]; var seed: Int }
    private func look(_ i: PreviewInfo?) -> Look? {
        i.map { Look(dyes: $0.channels.map { $0.fluor.hex + ($0.fluor.counterstain ? "n" : "") },
                     places: $0.channels.map { "\($0.localisation)" + ($0.markers.isEmpty ? "-" : "+") }, seed: $0.seed) }
    }
    private var built: CGSize = .zero
    private var clock = 0.0
    private var stepX: [CGFloat] = []
    private var trackY: CGFloat = 0
    private var D: CGFloat = 0
    private var cells: [Cell] = []
    private var last = (step: -1, label: "", chip: -2)

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.addSublayer(stage)
        stage.addSublayer(back)
        stage.addSublayer(fov)
        fov.mask = fovMask
        for l in [fovBack, phase, perm, haze] { fov.addSublayer(l) }
        darkness.backgroundColor = cg("02060D")
        stage.addSublayer(ring)
        stage.addSublayer(progress)
        stage.addSublayer(marker)
        progress.anchorPoint = CGPoint(x: 0, y: 0.5)
        progress.backgroundColor = cg("8CF5A4", 0.85)
        progress.cornerRadius = 1
        for t in [stepTitle, stepDetail, fovLabel, headTitle, headSub, headNote] {
            t.contentsScale = screenScale
            t.truncationMode = .end
            stage.addSublayer(t)
        }
        stepDetail.isWrapped = true
        labelPill.backgroundColor = NSColor(white: 0, alpha: 0.42).cgColor
        labelPill.cornerRadius = 9
        stage.insertSublayer(labelPill, below: fovLabel)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setInfo(_ i: PreviewInfo, replay r: Int) {
        guard i != info || r != replay else { return }
        let restart = r != replay || i.seed != info?.seed
        let redraw = look(i) != look(info)
        info = i
        replay = r
        guard built != .zero else { return }
        if redraw {
            build()
        } else {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            refreshWords()
            CATransaction.commit()
        }
        if restart { clock = 0 }
        last = (-1, "", -2)
        if ambientActive || restart { show(clock) } else { rest() }
    }

    override func layout() {
        super.layout()
        guard bounds.size != built, bounds.width > (hologram ? 80 : 420), bounds.height > (hologram ? 80 : 200), info != nil else { return }
        build()
        if ambientActive { show(clock) } else { rest() }
    }

    // MARK: drawing once

    private func build() {
        guard let info = info else { return }
        if hologram { buildHologram(info); return }
        built = bounds.size
        let W = bounds.width, H = bounds.height
        func up(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        stage.frame = bounds
        back.frame = bounds

        D = H - 2 * pad
        let fovTD = CGRect(x: pad, y: pad, width: D, height: D)
        let x0 = fovTD.maxX + 26, RW = W - x0 - pad - 6
        rightX = x0
        trackY = pad + 64
        stepX = (0..<6).map { x0 + 12 + (RW - 24) * CGFloat($0) / 5 }
        cells = makeCells(info.seed)

        back.contents = renderImage(bounds.size, screenScale) { c in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            c.saveGState()
            c.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: CGSize(width: W, height: H)), cornerWidth: 14, cornerHeight: 14, transform: nil))
            c.clip()
            if let g = CGGradient(colorsSpace: space, colors: [cg("071630"), cg("0F2F5A"), cg("17437A")] as CFArray, locations: [0, 0.6, 1]) {
                c.drawLinearGradient(g, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
            }
            if let g = CGGradient(colorsSpace: space, colors: [cg("5B8BD6", 0.3), cg("5B8BD6", 0)] as CFArray, locations: [0, 1]) {
                c.drawRadialGradient(g, startCenter: CGPoint(x: W * 0.72, y: 0), startRadius: 0, endCenter: CGPoint(x: W * 0.72, y: 0), endRadius: W * 0.5, options: [])
            }
            c.restoreGState()
            // the eyepiece: a dark rim around the field of view
            if let g = CGGradient(colorsSpace: space, colors: [cg("000000", 0.55), cg("000000", 0)] as CFArray, locations: [0, 1]) {
                let ctr = CGPoint(x: fovTD.midX, y: fovTD.midY)
                c.drawRadialGradient(g, startCenter: ctr, startRadius: D / 2, endCenter: ctr, endRadius: D / 2 + 14, options: [])
            }
            let dim = NSColor(white: 1, alpha: 0.55), faint = NSColor(white: 1, alpha: 0.38)
            drawText("PROTOCOL", CGPoint(x: x0, y: pad + 2), 10.5, dim, weight: .bold, tracking: 1.2)
            // the protocol track
            c.setStrokeColor(NSColor(white: 1, alpha: 0.16).cgColor)
            c.setLineWidth(2)
            c.strokeLineSegments(between: [CGPoint(x: stepX[0], y: trackY), CGPoint(x: stepX[5], y: trackY)])
            for (i, x) in stepX.enumerated() {
                c.setFillColor(cg("0B2142"))
                c.fillEllipse(in: CGRect(x: x - 6, y: trackY - 6, width: 12, height: 12))
                c.setStrokeColor(NSColor(white: 1, alpha: 0.35).cgColor); c.setLineWidth(1.4)
                c.strokeEllipse(in: CGRect(x: x - 6, y: trackY - 6, width: 12, height: 12))
                drawText(stepShort[i], CGPoint(x: x, y: trackY + 11), 9.5, faint, weight: .semibold, center: true)
            }
        }

        // field of view
        fov.frame = up(fovTD)
        fovMask.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: D, height: D), transform: nil)
        let fsize = CGSize(width: D, height: D)
        for l in [fovBack, phase, perm, haze, darkness, merge] { l.frame = CGRect(origin: .zero, size: fsize) }
        fovBack.contents = renderImage(fsize, screenScale) { c in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            if let g = CGGradient(colorsSpace: space, colors: [cg("3B5170"), cg("22344D"), cg("142236")] as CFArray, locations: [0, 0.7, 1]) {
                c.drawRadialGradient(g, startCenter: CGPoint(x: D * 0.45, y: D * 0.4), startRadius: 0, endCenter: CGPoint(x: D / 2, y: D / 2), endRadius: D * 0.6, options: [])
            }
        }
        phase.contents = renderImage(fsize, screenScale) { c in self.drawPhase(c) }
        perm.contents = renderImage(fsize, screenScale) { c in
            c.setStrokeColor(NSColor(white: 1, alpha: 0.85).cgColor)
            c.setLineWidth(1.5); c.setLineCap(.round)
            c.setLineDash(phase: 0, lengths: [0.1, 4.2])
            for cell in self.cells { c.addPath(ellipsePath(cell)); c.strokePath() }
        }
        haze.contents = renderImage(fsize, screenScale) { c in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            for i in 0..<34 {
                let ctr = CGPoint(x: D * CGFloat(hash01(i, 71 + info.seed)), y: D * CGFloat(hash01(i, 72 + info.seed)))
                let r = D * CGFloat(0.12 + 0.16 * hash01(i, 73))
                if let g = CGGradient(colorsSpace: space, colors: [cg("A9CBFF", 0.16), cg("A9CBFF", 0)] as CFArray, locations: [0, 1]) {
                    c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: r, options: [])
                }
            }
        }

        // antibodies: primaries drift in and bind, secondaries carry the dyes to them
        (ab1 + ab2).forEach { $0.layer.removeFromSuperlayer() }
        ab1 = []; ab2 = []
        let dyes = info.channels.filter { !$0.fluor.counterstain }
        let primaryImg = Self.antibody(16, NSColor(white: 0.92, alpha: 1), tip: nil)
        let secondaryImgs = (dyes.isEmpty ? [Channel(fluor: Fluor(name: "", wavelength: 488, counterstain: false), secondary: "", markers: [], localisation: .cytoplasm)] : dyes)
            .map { Self.antibody(14, NSColor(hex: "CFE0FF"), tip: NSColor(hex: $0.fluor.hex)) }
        let n = min(14, max(8, cells.count))
        for i in 0..<n {
            let cell = cells[i % cells.count]
            let ang = Double(hash01(i, 11)) * 2 * .pi
            let rr = CGFloat(0.35 + 0.4 * hash01(i, 12))
            let site = CGPoint(x: cell.c.x + CGFloat(cos(ang)) * cell.rx * rr, y: cell.c.y + CGFloat(sin(ang)) * cell.ry * rr)
            let toUp = CGPoint(x: site.x, y: D - site.y)
            let from = CGPoint(x: site.x + CGFloat(hash01(i, 13) - 0.5) * 80, y: D + 24)
            let l1 = CALayer()
            l1.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
            l1.contents = primaryImg
            l1.opacity = 0
            fov.addSublayer(l1)
            ab1.append((l1, from, toUp, CGFloat(hash01(i, 14) - 0.5) * 0.6, CGFloat(hash01(i, 17) - 0.5) * 0.8))
            let l2 = CALayer()
            l2.bounds = CGRect(x: 0, y: 0, width: 14, height: 14)
            l2.contents = secondaryImgs[i % secondaryImgs.count]
            l2.opacity = 0
            fov.addSublayer(l2)
            let to2 = CGPoint(x: toUp.x + 2, y: toUp.y - 11)
            // just below the primary: its arms take hold of the primary's stem, its dye hangs underneath
            ab2.append((l2, CGPoint(x: to2.x + CGFloat(hash01(i, 15) - 0.5) * 90, y: D + 24), to2, CGFloat(hash01(i, 16) - 0.5) * 0.4, CGFloat(hash01(i, 18) - 0.5) * 0.8))
        }

        // channels, then the merge
        channelLayers.forEach { $0.removeFromSuperlayer() }
        channelLayers = info.channels.enumerated().map { j, ch in
            let l = CALayer()
            l.frame = CGRect(origin: .zero, size: fsize)
            l.contents = renderImage(fsize, screenScale) { c in self.drawChannel(c, ch, j) }
            l.opacity = 0
            return l
        }
        darkness.removeFromSuperlayer(); fov.addSublayer(darkness)
        channelLayers.forEach { fov.addSublayer($0) }
        channelMasks = channelLayers.map { l in
            let m = CALayer()
            m.backgroundColor = NSColor.black.cgColor
            m.frame = CGRect(x: 0, y: D, width: D, height: 0)
            l.mask = m
            return m
        }
        merge.removeFromSuperlayer(); fov.addSublayer(merge)
        mergeMask.backgroundColor = NSColor.black.cgColor
        mergeMask.frame = CGRect(x: 0, y: 0, width: D, height: D)
        merge.mask = mergeMask
        // the laser line: a bright core in the channel's colour with a glow above and below
        func line(_ hex: String) -> CGImage? {
            renderImage(CGSize(width: D, height: 22), screenScale) { c in
                let space = CGColorSpace(name: CGColorSpace.sRGB)!
                if let g = CGGradient(colorsSpace: space, colors: [cg(hex, 0), cg(hex, 0.55), cg(hex, 0)] as CFArray, locations: [0, 0.5, 1]) {
                    c.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 22), options: [])
                }
                if let g = CGGradient(colorsSpace: space, colors: [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(0.95).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 0.5, 1]) {
                    c.saveGState(); c.clip(to: CGRect(x: 0, y: 10.2, width: D, height: 1.6))
                    c.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: D, y: 0), options: [])
                    c.restoreGState()
                }
            }
        }
        scanImages = info.channels.map { line($0.fluor.hex) }
        scanWhite = line("FFFFFF")
        scanLine.removeFromSuperlayer(); fov.addSublayer(scanLine)
        scanLine.bounds = CGRect(x: 0, y: 0, width: D, height: 22)
        scanLine.opacity = 0
        scanShown = -2
        merge.contents = renderImage(fsize, screenScale) { c in
            c.setBlendMode(.plusLighter)
            for (j, ch) in info.channels.enumerated() { self.drawChannel(c, ch, j) }
        }

        ring.frame = up(fovTD.insetBy(dx: -2, dy: -2))
        ring.contents = renderImage(ring.bounds.size, screenScale) { c in
            let r = CGRect(origin: .zero, size: self.ring.bounds.size)
            c.setStrokeColor(NSColor(white: 1, alpha: 0.22).cgColor); c.setLineWidth(2)
            c.strokeEllipse(in: r.insetBy(dx: 1.5, dy: 1.5))
            // scale bar
            let y = r.height * 0.84, x1 = r.width * 0.78
            c.setStrokeColor(NSColor(white: 1, alpha: 0.85).cgColor); c.setLineWidth(2.5)
            c.strokeLineSegments(between: [CGPoint(x: x1 - 34, y: y), CGPoint(x: x1, y: y)])
            drawText("20 µm", CGPoint(x: x1 - 17, y: y + 4), 9, NSColor(white: 1, alpha: 0.8), weight: .semibold, center: true)
        }

        // the protocol track: done steps fill, a ring marks the current one
        dots.forEach { $0.removeFromSuperlayer() }
        dots = stepX.map { x in
            let d = CALayer()
            d.bounds = CGRect(x: 0, y: 0, width: 12, height: 12)
            d.position = CGPoint(x: x, y: H - trackY)
            d.cornerRadius = 6
            d.backgroundColor = cg("8CF5A4")
            d.opacity = 0
            stage.insertSublayer(d, below: marker)
            return d
        }
        marker.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
        marker.contents = renderImage(CGSize(width: 28, height: 28), screenScale) { c in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            if let g = CGGradient(colorsSpace: space, colors: [cg("8CF5A4", 0.55), cg("8CF5A4", 0)] as CFArray, locations: [0, 1]) {
                c.drawRadialGradient(g, startCenter: CGPoint(x: 14, y: 14), startRadius: 4, endCenter: CGPoint(x: 14, y: 14), endRadius: 14, options: [])
            }
            c.setStrokeColor(NSColor.white.cgColor); c.setLineWidth(2)
            c.strokeEllipse(in: CGRect(x: 7, y: 7, width: 14, height: 14))
        }
        progress.bounds = CGRect(x: 0, y: 0, width: 0, height: 2)
        progress.position = CGPoint(x: stepX[0], y: H - trackY)

        func text(_ t: CATextLayer, _ r: CGRect, _ size: CGFloat, _ color: NSColor, _ weight: NSFont.Weight) {
            t.frame = up(r)
            t.font = NSFont.systemFont(ofSize: size, weight: weight)
            t.fontSize = size
            t.foregroundColor = color.cgColor
        }
        text(stepTitle, CGRect(x: x0, y: pad + 98, width: RW, height: 30), 22, .white, .semibold)
        text(stepDetail, CGRect(x: x0, y: pad + 132, width: RW, height: 54), 12, NSColor(hex: "C9DCF5"), .regular)
        text(fovLabel, CGRect(x: fovTD.minX + 30, y: fovTD.minY + 26, width: D - 60, height: 16), 11, .white, .bold)
        fovLabel.alignmentMode = .center
        labelPill.position = CGPoint(x: fov.frame.midX, y: fovLabel.frame.midY - 1)
        text(headTitle, CGRect(x: x0 + 90, y: pad, width: RW - 86, height: 18), 12.5, .white, .semibold)
        headTitle.alignmentMode = .right
        text(headSub, CGRect(x: x0, y: pad + 22, width: RW, height: 18), 12, NSColor(hex: "BFD9FF"), .medium)
        text(headNote, CGRect(x: x0, y: pad + 192, width: RW, height: 16), 11, NSColor(hex: "FFC24A"), .semibold)
        refreshWords()
    }

    /// Pictures already drawn for a hologram, by stain look and size: picking a stain again shows at once.
    private static var holoCache: [String: [CGImage?]] = [:]

    /// The hologram: a round scope with the cells, the channels drawn by the laser line, and the merge.
    private func buildHologram(_ info: PreviewInfo) {
        built = bounds.size
        let W = bounds.width, H = bounds.height
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        stage.frame = bounds
        back.contents = nil
        D = min(W, H) - 8
        let fovTD = CGRect(x: (W - D) / 2, y: (H - D) / 2, width: D, height: D)
        fov.frame = CGRect(x: fovTD.minX, y: H - fovTD.maxY, width: D, height: D)
        fovMask.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: D, height: D), transform: nil)
        cells = makeCells(info.seed)
        stepX = Array(repeating: 0, count: 6)
        let fsize = CGSize(width: D, height: D)
        for l in [fovBack, phase, perm, haze, darkness, merge] { l.frame = CGRect(origin: .zero, size: fsize) }
        fovBack.contents = renderImage(fsize, screenScale) { c in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            if let g = CGGradient(colorsSpace: space, colors: [cg("0B3550", 0.5), cg("04172A", 0.62)] as CFArray, locations: [0, 1]) {
                c.drawRadialGradient(g, startCenter: CGPoint(x: D / 2, y: D / 2), startRadius: 0, endCenter: CGPoint(x: D / 2, y: D / 2), endRadius: D / 2, options: [])
            }
        }
        for l in [phase, perm, haze] { l.contents = nil; l.opacity = 0 }
        darkness.backgroundColor = cg("03111F", 0.5)
        (ab1 + ab2).forEach { $0.layer.removeFromSuperlayer() }
        ab1 = []; ab2 = []
        for l in [marker, progress, stepTitle, stepDetail, headTitle, headSub, headNote] { l.isHidden = true }
        dots.forEach { $0.removeFromSuperlayer() }; dots = []
        chips.forEach { $0.removeFromSuperlayer() }; chips = []

        let key = "\(look(info).map { "\($0)" } ?? "")|\(Int(D))"
        let pics: [CGImage?]
        if let cached = Self.holoCache[key] { pics = cached } else {
            pics = info.channels.enumerated().map { j, ch in renderImage(fsize, screenScale) { c in self.drawChannel(c, ch, j) } }
                + [renderImage(fsize, screenScale) { c in
                    c.setBlendMode(.plusLighter)
                    for (j, ch) in info.channels.enumerated() { self.drawChannel(c, ch, j) }
                }]
            if Self.holoCache.count > 24 { Self.holoCache.removeAll() }
            Self.holoCache[key] = pics
        }
        channelLayers.forEach { $0.removeFromSuperlayer() }
        channelLayers = info.channels.indices.map { j in
            let l = CALayer()
            l.frame = CGRect(origin: .zero, size: fsize)
            l.contents = pics[j]
            l.opacity = 0
            return l
        }
        darkness.removeFromSuperlayer(); fov.addSublayer(darkness)
        channelLayers.forEach { fov.addSublayer($0) }
        channelMasks = channelLayers.map { l in
            let m = CALayer(); m.backgroundColor = NSColor.black.cgColor
            m.frame = CGRect(x: 0, y: D, width: D, height: 0); l.mask = m; return m
        }
        merge.removeFromSuperlayer(); fov.addSublayer(merge)
        merge.contents = pics.last ?? nil
        mergeMask.backgroundColor = NSColor.black.cgColor
        mergeMask.frame = CGRect(x: 0, y: 0, width: D, height: D)
        merge.mask = mergeMask
        func line(_ hex: String) -> CGImage? {
            renderImage(CGSize(width: D, height: 18), screenScale) { c in
                let space = CGColorSpace(name: CGColorSpace.sRGB)!
                if let g = CGGradient(colorsSpace: space, colors: [cg(hex, 0), cg(hex, 0.6), cg(hex, 0)] as CFArray, locations: [0, 0.5, 1]) {
                    c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 18), options: [])
                }
                c.setFillColor(NSColor(white: 1, alpha: 0.9).cgColor); c.fill(CGRect(x: 0, y: 8.3, width: D, height: 1.4))
            }
        }
        scanImages = info.channels.map { line($0.fluor.hex) }
        scanWhite = line("FFFFFF")
        scanLine.removeFromSuperlayer(); fov.addSublayer(scanLine)
        scanLine.bounds = CGRect(x: 0, y: 0, width: D, height: 18)
        scanLine.opacity = 0
        scanShown = -2

        // the hologram itself: scan lines across the image, a cyan rim with a glow
        holo.removeFromSuperlayer(); stage.addSublayer(holo)
        holo.frame = bounds
        holo.contents = renderImage(bounds.size, screenScale) { c in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let ctr = CGPoint(x: fovTD.midX, y: fovTD.midY)
            c.saveGState(); c.addEllipse(in: fovTD); c.clip()
            c.setFillColor(cg("7FE8FF", 0.07))
            var y = fovTD.minY
            while y < fovTD.maxY { c.fill(CGRect(x: fovTD.minX, y: y, width: D, height: 1)); y += 3 }
            if let g = CGGradient(colorsSpace: space, colors: [cg("7FE8FF", 0), cg("7FE8FF", 0.22)] as CFArray, locations: [0.72, 1]) {
                c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: D / 2, options: [])
            }
            c.restoreGState()
            if let g = CGGradient(colorsSpace: space, colors: [cg("7FE8FF", 0.45), cg("7FE8FF", 0)] as CFArray, locations: [0, 1]) {
                c.drawRadialGradient(g, startCenter: ctr, startRadius: D / 2, endCenter: ctr, endRadius: D / 2 + 4, options: [])
            }
            c.setStrokeColor(cg("9BF0FF", 0.9)); c.setLineWidth(1.4); c.strokeEllipse(in: fovTD.insetBy(dx: 0.7, dy: 0.7))
            c.setStrokeColor(cg("9BF0FF", 0.35)); c.setLineWidth(0.8)
            c.setLineDash(phase: 0, lengths: [2, 5]); c.strokeEllipse(in: fovTD.insetBy(dx: 5, dy: 5))
            // scale bar
            c.setLineDash(phase: 0, lengths: [])
            let sy = fovTD.minY + D * 0.70, sx = fovTD.minX + D * 0.74
            c.setStrokeColor(NSColor(white: 1, alpha: 0.85).cgColor); c.setLineWidth(2)
            c.strokeLineSegments(between: [CGPoint(x: sx - 24, y: sy), CGPoint(x: sx, y: sy)])
            drawText("20 µm", CGPoint(x: sx - 12, y: sy + 3), 7.5, NSColor(white: 1, alpha: 0.8), weight: .semibold, center: true)
        }
        ring.contents = nil

        func text(_ t: CATextLayer, _ y: CGFloat, _ size: CGFloat, mono: Bool) {
            t.isHidden = false
            t.frame = CGRect(x: fovTD.minX + 16, y: H - y - size - 4, width: D - 32, height: size + 4)
            t.font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold) : NSFont.systemFont(ofSize: size, weight: .bold)
            t.fontSize = size
            t.alignmentMode = .center
            t.contentsScale = screenScale
        }
        text(fovLabel, fovTD.minY + D * 0.11, 10, mono: false)
        labelPill.position = CGPoint(x: fov.frame.midX, y: fovLabel.frame.midY - 1)
        lineLabel.removeFromSuperlayer(); stage.addSublayer(lineLabel)
        text(lineLabel, fovTD.minY + D * 0.76, 8.5, mono: true)
        lineLabel.foregroundColor = cg("9BF0FF")
        lineLabel.string = ""
        last = (-1, "", -2)
    }

    /// The words and the channel chips: cheap, so they follow every keystroke.
    private func refreshWords() {
        guard let info = info, built != .zero, !hologram else { return }
        let W = bounds.width, H = bounds.height, x0 = rightX, RW = W - x0 - pad - 6
        func up(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height) }
        headTitle.string = info.title
        headSub.string = info.subtitle
        if info.issues > 0 {
            headNote.string = "⚠︎ \(info.issues) problem\(info.issues == 1 ? "" : "s") with this stain's pairings: see its card"
            headNote.foregroundColor = cg("FF8A7A")
        } else {
            headNote.string = info.demo ? "A demo: add a stain set to see your own antibodies here." : ""
            headNote.foregroundColor = NSColor(white: 1, alpha: 0.45).cgColor
        }
        stepDetail.string = last.step >= 0 && last.step < info.details.count ? info.details[last.step] : stepDetail.string

        // a chip for each channel, along the bottom
        chips.forEach { $0.removeFromSuperlayer() }
        chips = []
        var cx = x0, cy = H - pad - 22
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        for ch in info.channels {
            let where_ = ch.localisation == .nuclear ? "nucleus" : (ch.localisation == .membrane ? "membrane" : "cytoplasm")
            let s = "\(ch.fluor.name) · \(ch.label)" + (ch.markers.isEmpty && !ch.fluor.counterstain ? "" : " · \(where_)")
            let w = (s as NSString).size(withAttributes: [.font: font]).width + 30
            if cx + w > W - pad && cx > x0 { cx = x0; cy -= 26 }
            let l = CALayer()
            l.frame = up(CGRect(x: cx, y: cy, width: w, height: 20))
            l.contents = renderImage(CGSize(width: w, height: 20), screenScale) { c in
                c.addPath(CGPath(roundedRect: CGRect(x: 0.5, y: 0.5, width: w - 1, height: 19), cornerWidth: 10, cornerHeight: 10, transform: nil))
                c.setFillColor(cg(ch.fluor.hex, 0.16)); c.fillPath()
                c.addPath(CGPath(roundedRect: CGRect(x: 0.5, y: 0.5, width: w - 1, height: 19), cornerWidth: 10, cornerHeight: 10, transform: nil))
                c.setStrokeColor(cg(ch.fluor.hex, 0.7)); c.setLineWidth(1); c.strokePath()
                c.setFillColor(cg(ch.fluor.hex)); c.fillEllipse(in: CGRect(x: 8, y: 6, width: 8, height: 8))
                drawText(s, CGPoint(x: 21, y: 3), 11, .white, weight: .semibold)
            }
            stage.addSublayer(l)
            chips.append(l)
            cx += w + 6
        }
        if info.channels.isEmpty {
            let s = "Name each secondary by its dye (488, 594, 647…) to see it here."
            let l = CATextLayer()
            l.contentsScale = screenScale
            l.frame = up(CGRect(x: x0, y: H - pad - 20, width: RW, height: 16))
            l.string = s; l.fontSize = 11; l.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            l.foregroundColor = NSColor(white: 1, alpha: 0.55).cgColor
            stage.addSublayer(l)
            chips.append(l)
        }
        last = (-1, "", -2)
    }

    private static func antibody(_ s: CGFloat, _ color: NSColor, tip: NSColor?) -> CGImage? {
        renderImage(CGSize(width: s, height: s), screenScale) { c in
            let m = s / 2
            if let tip = tip {
                let space = CGColorSpace(name: CGColorSpace.sRGB)!
                if let g = CGGradient(colorsSpace: space, colors: [NSColor.white.cgColor, tip.cgColor, tip.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 0.35, 1]) {
                    let ctr = CGPoint(x: m, y: s - 3)
                    c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: 4.5, options: [])
                }
            }
            c.setStrokeColor(color.cgColor); c.setLineWidth(s > 15 ? 2.2 : 1.8); c.setLineCap(.round); c.setLineJoin(.round)
            c.move(to: CGPoint(x: m, y: s - 3)); c.addLine(to: CGPoint(x: m, y: m))
            c.addLine(to: CGPoint(x: m - s * 0.32, y: 2.5))
            c.move(to: CGPoint(x: m, y: m)); c.addLine(to: CGPoint(x: m + s * 0.32, y: 2.5))
            c.strokePath()
        }
    }

    // MARK: cells

    private func makeCells(_ seed: Int) -> [Cell] {
        var out: [Cell] = []
        let R = D / 2 - 14
        var tries = 0
        while out.count < 13 && tries < 400 {
            tries += 1
            let a = hash01(tries, 1 + seed * 7) * 2 * .pi, r = sqrt(hash01(tries, 2 + seed * 7)) * Double(R)
            let c = CGPoint(x: D / 2 + CGFloat(cos(a) * r), y: D / 2 + CGFloat(sin(a) * r))
            guard out.allSatisfy({ hypot($0.c.x - c.x, $0.c.y - c.y) > D * 0.15 }) else { continue }
            let rx = D * CGFloat(0.052 + 0.022 * hash01(tries, 3)), ry = rx * CGFloat(0.62 + 0.25 * hash01(tries, 4))
            let angle = CGFloat(hash01(tries, 5) * .pi)
            let nr = ry * 0.72
            let nucleus = CGPoint(x: c.x + rx * 0.18 * CGFloat(cos(Double(angle))), y: c.y + rx * 0.18 * CGFloat(sin(Double(angle))))
            var neurites: [[CGPoint]] = []
            for k in 0..<(1 + Int(hash01(tries, 6) * 2.6)) {
                let na = Double(angle) + (k == 0 ? 0 : .pi) + (hash01(tries, 7 + k) - 0.5) * 0.9
                let len = D * CGFloat(0.09 + 0.12 * hash01(tries, 9 + k))
                let start = CGPoint(x: c.x + CGFloat(cos(na)) * rx * 0.9, y: c.y + CGFloat(sin(na)) * rx * 0.9)
                let end = CGPoint(x: c.x + CGFloat(cos(na)) * (rx + len), y: c.y + CGFloat(sin(na)) * (rx + len))
                let bend = CGFloat(hash01(tries, 12 + k) - 0.5) * len * 0.7
                let mid = CGPoint(x: (start.x + end.x) / 2 - CGFloat(sin(na)) * bend, y: (start.y + end.y) / 2 + CGFloat(cos(na)) * bend)
                neurites.append([start, mid, end])
            }
            out.append(Cell(c: c, rx: rx, ry: ry, angle: angle, nucleus: nucleus, nr: nr, neurites: neurites))
        }
        return out
    }

    /// Phase contrast: bright halos round grey cells, darker nuclei.
    private func drawPhase(_ c: CGContext) {
        c.setLineCap(.round)
        for cell in cells {
            for n in cell.neurites {
                c.addPath(neuritePath(n)); c.setStrokeColor(NSColor(white: 1, alpha: 0.28).cgColor); c.setLineWidth(1.6); c.strokePath()
            }
            c.addPath(ellipsePath(cell)); c.setFillColor(NSColor(white: 1, alpha: 0.12).cgColor); c.fillPath()
            c.addPath(ellipsePath(cell, grow: 1)); c.setStrokeColor(NSColor(white: 1, alpha: 0.42).cgColor); c.setLineWidth(1.3); c.strokePath()
            let nrect = CGRect(x: cell.nucleus.x - cell.nr, y: cell.nucleus.y - cell.nr * 0.85, width: cell.nr * 2, height: cell.nr * 1.7)
            c.setFillColor(cg("0E1A2B", 0.4)); c.fillEllipse(in: nrect)
            c.setStrokeColor(NSColor(white: 1, alpha: 0.2).cgColor); c.setLineWidth(0.9); c.strokeEllipse(in: nrect)
            c.setFillColor(NSColor(white: 1, alpha: 0.3).cgColor)
            c.fillEllipse(in: CGRect(x: cell.nucleus.x - 1.5, y: cell.nucleus.y - 2, width: 3, height: 3))
        }
    }

    /// One channel's signal: each cell expresses the marker more or less, where the marker lives.
    private func drawChannel(_ c: CGContext, _ ch: Channel, _ j: Int) {
        let color = NSColor(hex: ch.fluor.hex)
        c.setLineCap(.round)
        for (i, cell) in cells.enumerated() {
            let level: Double
            if ch.fluor.counterstain { level = 0.75 + 0.25 * hash01(i, 40) }
            else if ch.markers.isEmpty { level = 0.12 * hash01(i, 41 + j) }        // background only
            else { let h = hash01(i, 50 + j * 13); level = h < 0.25 ? 0.08 : 0.45 + 0.55 * hash01(i, 60 + j) }
            let a = CGFloat(level)
            c.saveGState()
            c.setShadow(offset: .zero, blur: 9, color: color.withAlphaComponent(0.85 * a).cgColor)
            let nrect = CGRect(x: cell.nucleus.x - cell.nr, y: cell.nucleus.y - cell.nr * 0.85, width: cell.nr * 2, height: cell.nr * 1.7)
            switch (ch.fluor.counterstain ? .nuclear : ch.localisation) {
            case .nuclear:
                c.setFillColor(color.withAlphaComponent(0.9 * a).cgColor)
                c.fillEllipse(in: nrect)
                c.setFillColor(NSColor.white.withAlphaComponent(0.35 * a).cgColor)
                c.fillEllipse(in: nrect.insetBy(dx: cell.nr * 0.45, dy: cell.nr * 0.4))
            case .cytoplasm:
                for n in cell.neurites {
                    c.addPath(neuritePath(n)); c.setStrokeColor(color.withAlphaComponent(0.85 * a).cgColor); c.setLineWidth(2); c.strokePath()
                }
                c.addPath(ellipsePath(cell)); c.setFillColor(color.withAlphaComponent(0.75 * a).cgColor); c.fillPath()
                c.setShadow(offset: .zero, blur: 0, color: nil)
                c.setBlendMode(.destinationOut)
                c.setFillColor(NSColor(white: 0, alpha: 0.55).cgColor)
                c.fillEllipse(in: nrect)
            case .membrane:
                c.addPath(ellipsePath(cell)); c.setFillColor(color.withAlphaComponent(0.18 * a).cgColor); c.fillPath()
                c.addPath(ellipsePath(cell, grow: 0.5)); c.setStrokeColor(color.withAlphaComponent(0.95 * a).cgColor); c.setLineWidth(2.4); c.strokePath()
                for n in cell.neurites {
                    c.addPath(neuritePath(n)); c.setStrokeColor(color.withAlphaComponent(0.4 * a).cgColor); c.setLineWidth(1.2); c.strokePath()
                }
            }
            c.restoreGState()
        }
    }

    // MARK: every frame

    private var starts: [Double] { stepLengths.reduce(into: [0.0]) { $0.append($0.last! + $1) } }   // 6 entries: Fix … Image
    private var imagingStart: Double { starts[5] }
    private var mergeStart: Double { imagingStart + 0.6 + Double(info?.channels.count ?? 0) * perChannel }
    private var loopLength: Double { mergeStart + mergeHold + holdEnd + fadeEnd }

    override func tick(_ dt: Double) {
        guard built != .zero else { return }
        clock += dt
        if hologram {
            // only the imaging: the lamp is already off when the scope appears
            if clock < holoStart || clock >= loopLength { clock = holoStart }
        } else if clock >= loopLength { clock = 0 }
        show(clock)
    }

    private var holoStart: Double { imagingStart + 0.45 }

    private func set(_ l: CALayer, _ o: Double) { let f = Float(max(0, min(1, o))); if abs(l.opacity - f) > 0.004 { l.opacity = f } }

    private func show(_ t: Double) {
        guard let info = info, built != .zero, stepX.count == 6 else { return }
        let st = starts
        let end = mergeStart + mergeHold + holdEnd
        let fade = t > end ? max(0, 1 - (t - end) / fadeEnd) : 1
        let dark = easeInOut((t - imagingStart) / 0.6)
        let step = t >= imagingStart ? 5 : (st.lastIndex { t >= $0 } ?? 0)

        // fix: the cells settle into place
        let fix = easeOut(t / 0.9)
        set(phase, fix * (1 - dark) * fade)
        set(fovBack, fade)
        let s = CGFloat(1.05 - 0.05 * fix)
        phase.setAffineTransform(CGAffineTransform(scaleX: s, y: s))
        // permeabilise: membranes open, then stay faintly dotted
        let pu = (t - st[1]) / stepLengths[1]
        set(perm, (pu < 0 ? 0 : (pu < 1 ? 0.25 + 0.65 * sin(.pi * pu) : 0.22)) * (1 - dark) * fade)
        // block: a haze settles, and thins as the antibodies go on
        let hz: Double = t < st[2] ? 0 : (t < st[3] ? 0.75 * easeOut((t - st[2]) / 0.8) : 0.75 - 0.5 * clamp01((t - st[3]) / (imagingStart - st[3])))
        set(haze, hz * (1 - dark) * fade)
        // antibodies
        func fly(_ list: [Flyer], _ start: Double) {
            for (i, a) in list.enumerated() {
                let u = (t - start - 0.15 - Double(i) * 0.11) / 1.05
                guard u > 0 else { set(a.layer, 0); continue }
                let e = CGFloat(easeOut(u))
                let sway = CGFloat(sin(u * 7 + Double(i))) * 6 * (1 - e)
                a.layer.position = CGPoint(x: a.from.x + (a.to.x - a.from.x) * e + sway, y: a.from.y + (a.to.y - a.from.y) * e)
                a.layer.setAffineTransform(CGAffineTransform(rotationAngle: a.final + a.wobble * (1 - e) * 3))
                set(a.layer, min(1, u * 5) * (1 - dark) * fade)
            }
        }
        fly(ab1, st[3])
        fly(ab2, st[4])
        // image: the lamp goes dark, each channel on its own, then all together
        set(darkness, dark * fade)
        var label = "Phase contrast", labelHex = "FFFFFF", chip = -1
        var scanning = -1, scanP = 0.0
        for (j, l) in channelLayers.enumerated() {
            let w0 = imagingStart + 0.6 + Double(j) * perChannel
            let o = (t >= w0 ? 1 : 0) * clamp01((w0 + perChannel - t) / 0.3 + 1) * (t < w0 + perChannel + 0.3 ? 1 : 0)
            set(l, o * fade)
            let p = clamp01((t - w0) / scanLength)
            if j < channelMasks.count {
                let h = D * CGFloat(p)
                let f = CGRect(x: 0, y: D - h, width: D, height: h)
                if channelMasks[j].frame != f { channelMasks[j].frame = f }
            }
            if t >= w0 && t < w0 + perChannel {
                let ch = info.channels[j]
                label = p < 1 ? "Scanning · \(ch.fluor.name) laser" : "\(ch.fluor.name) · \(ch.label)"
                labelHex = ch.fluor.hex; chip = j
                if p > 0 && p < 1 { scanning = j; scanP = p }
            }
        }
        let mp = clamp01((t - mergeStart) / mergeScan)
        let mh = D * CGFloat(t >= mergeStart ? mp : 1)
        let mf = CGRect(x: 0, y: D - mh, width: D, height: mh)
        if mergeMask.frame != mf { mergeMask.frame = mf }
        set(merge, (t >= mergeStart ? 1 : 0) * fade)
        if t >= mergeStart && mp < 1 { scanning = 99; scanP = mp }
        if t >= mergeStart { label = info.channels.isEmpty ? "No dyes recognised" : "Merge"; labelHex = "FFFFFF"; chip = 99 }
        else if t >= imagingStart && chip < 0 { label = "Lamp off · fluorescence" }
        // the laser line, where the image is being drawn
        if scanning != scanShown {
            scanShown = scanning
            if scanning == 99 { scanLine.contents = scanWhite }
            else if scanning >= 0 && scanning < scanImages.count { scanLine.contents = scanImages[scanning] }
        }
        if hologram {
            let line: String
            if scanning >= 0 && scanning < info.channels.count { line = "λ\(info.channels[scanning].fluor.name) · line \(Int(scanP * 512))/512" }
            else if scanning == 99 { line = "merging \(info.channels.count) ch" }
            else if t >= mergeStart { line = "merge · \(info.channels.count) ch · 512²" }
            else if chip >= 0 && chip < info.channels.count { line = "λ\(info.channels[chip].fluor.name) · 512/512 ✓" }
            else { line = "laser on" }
            if lineLabel.string as? String != line { lineLabel.string = line }
            let flicker = 0.9 + 0.06 * sin(t * 23) + 0.04 * sin(t * 61)
            set(holo, flicker * fade)
        }
        if scanning >= 0 {
            scanLine.position = CGPoint(x: D / 2, y: D - D * CGFloat(scanP))
            set(scanLine, min(1, scanP * 8, (1 - scanP) * 8) * fade)
        } else {
            set(scanLine, 0)
        }
        set(fovLabel, fade)
        if label != last.label {
            last.label = label
            fovLabel.string = label
            fovLabel.foregroundColor = cg(labelHex)
            labelPill.bounds = hologram ? CGRect(x: 0, y: 0, width: textWidth(label, 10, weight: .bold) + 16, height: 16)
                                        : CGRect(x: 0, y: 0, width: textWidth(label, 11, weight: .bold) + 20, height: 19)
        }
        set(labelPill, fade)
        if chip != last.chip {
            last.chip = chip
            for (j, l) in chips.enumerated() { l.opacity = chip < 0 ? 0.85 : (chip == 99 || chip == j ? 1 : 0.32) }
        }
        // the track
        if step != last.step {
            last.step = step
            stepTitle.string = previewStepNames[step]
            stepDetail.string = step < info.details.count ? info.details[step] : ""
        }
        let prev = max(0, step - 1)
        let mv = CGFloat(easeInOut((t - st[step]) / 0.45))
        let x = stepX[prev] + (stepX[step] - stepX[prev]) * (step == 0 ? 1 : mv)
        marker.position = CGPoint(x: x, y: bounds.height - trackY)
        set(marker, fade)
        progress.bounds.size.width = max(0, x - stepX[0])
        set(progress, fade)
        for (i, d) in dots.enumerated() { set(d, (i < step || (i == step && mv >= 1) ? 1 : 0) * fade) }
        set(stepTitle, fade > 0.5 ? 1 : fade * 2)
        set(stepDetail, fade > 0.5 ? 1 : fade * 2)
    }

    /// The panel `seconds` into the protocol (development snapshots).
    func preview(at seconds: Double) {
        layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        last = (-1, "", -2)
        clock = seconds
        show(seconds)
        CATransaction.commit()
    }

    /// While paused: the merged image, so the card still shows what the stain will look like.
    override func rest() {
        guard built != .zero else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        last = (-1, "", -2)
        clock = mergeStart + 1.2
        show(clock)
        CATransaction.commit()
    }
}

struct StainingPreview: NSViewRepresentable {
    let info: PreviewInfo
    let active: Bool
    let replay: Int
    var hologram = false
    func makeNSView(context: Context) -> StainingPreviewView {
        let v = StainingPreviewView(frame: .zero)
        v.hologram = hologram
        return v
    }
    func updateNSView(_ v: StainingPreviewView, context: Context) {
        v.setInfo(info, replay: replay)
        v.ambientActive = active
    }
}

// MARK: - What the preview shows, from the plate

extension Store {
    /// The stain being painted with, or the first one; nil when there are none (the preview plays a demo).
    var previewSetIndex: Int? {
        if case .paint(let id) = tool, let i = exp.sets.firstIndex(where: { $0.id == id }) { return i }
        return exp.sets.isEmpty ? nil : 0
    }

    var previewInfo: PreviewInfo { previewInfo(for: previewSetIndex) }

    /// What the scope shows for stain `setIndex` (nil: the demo).
    func previewInfo(for setIndex: Int?) -> PreviewInfo {
        let demo = setIndex == nil
        let set: StainSet
        let index = setIndex ?? 0
        if let i = setIndex { set = exp.sets[i] } else {
            let lib = Library.seed
            set = StainSet(primaries: [lib.primaries[0], lib.primaries[1]], secondaries: [lib.secondaries[0], lib.secondaries[1]])
        }
        let report = panel(set)
        let vol = exp.volume(set, settings)
        let prim = set.primaries.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let secs = set.secondaries.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        func dil(_ d: Double) -> String { d > 0 ? "1:\(fmtNum(d))" : "dilution not set" }
        let p1 = prim.map { "\(markerName($0.name)) \(dil($0.dilution))" }.joined(separator: " · ")
        let amounts = prim.filter { $0.dilution > 0 }.map { "\(fmtNum(vol / $0.dilution)) µL \(markerName($0.name))" }.joined(separator: " + ")
        let s1 = secs.map { "\($0.name) \(dil($0.dilution))" }.joined(separator: " · ")
        let finds = report.channels.filter { !$0.markers.isEmpty }.map { ch in "\(ch.fluor.name) finds \(ch.label)" }.joined(separator: " · ")
        let image = report.channels.map { ch in
            "\(ch.fluor.name) → \(ch.label)"
        }.joined(separator: " · ")
        let wells = demo ? 0 : exp.wellCount(set)
        let details = [
            "Cells are fixed on day \(fmtNum(settings.fixDay)) after Day 0, holding every protein where it is.",
            "The membranes are opened so the antibodies can reach inside the cell and the nucleus.",
            "Blocking buffer with \(fmtNum(settings.ndsPerMl)) µL NDS per mL: \(fmtNum(exp.blocking(settings))) mL for this plate.",
            (p1.isEmpty ? "No primary antibodies yet." : p1) + (amounts.isEmpty ? "" : "\n\(fmtNum(vol)) µL for \(demo ? "the" : "\(wells)") wells: \(amounts)"),
            (s1.isEmpty ? "No secondaries yet." : s1) + (finds.isEmpty ? "" : "\n\(finds)"),
            image.isEmpty ? "Name the secondaries by their dye to see the channels." : image,
        ]
        let markers = prim.map { markerName($0.name) }.joined(separator: " + ")
        let dyes = secs.map { $0.name }.joined(separator: " + ")
        return PreviewInfo(title: demo ? "Demo" : "Stain \(index + 1)",
                           subtitle: [markers, dyes].filter { !$0.isEmpty }.joined(separator: "  →  "),
                           demo: demo, channels: report.channels.sorted { $0.fluor.wavelength < $1.fluor.wavelength }, details: details,
                           seed: demo ? 3 : index + 1, issues: report.issues.count)
    }
}
