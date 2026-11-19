import SwiftUI
import AppKit

// MARK: - Plate arrangement, drawn like a real 96-well plate
//
// Whatever the layout, primers are labelled with coloured tags and samples with their names, along the
// top or the left side of the plate; a label over a single column stands upright above the plate. Wells
// are round and glossy in the primer's colour, a pipette fills the plate column by column whenever the
// layout changes, and hovering a well names it.

/// A label along one edge of the plate, covering `span` rows or columns from `start`.
struct PlateBand {
    var start: Int
    var span: Int
    var text: String
    var hex: String?        // primer colour; nil for a sample
    var primer: Int? = nil  // the primer's place on the plate; nil for a sample
    var isRef = false
    var isCal = false
}

extension PlateLayout {
    /// Labels over the columns, and beside the rows.
    func bands(colors: GeneColors, calibrator: String) -> (top: [PlateBand], side: [PlateBand]) {
        let primerBands = primers.indices.map { b -> PlateBand in
            let (r, c) = well(0, b, 0)
            return PlateBand(start: (layout == .rows || layout == .primerColumns) ? c : r, span: (layout == .rows || layout == .columns) ? n : 1,
                             text: primers[b], hex: colors.color(primers[b], primerIndex[b]), primer: b, isRef: b == 0)
        }
        let sampleBands = samples.indices.map { i -> PlateBand in
            let (r, c) = well(i, 0, 0)
            return PlateBand(start: (layout == .columns || layout == .primerRows) ? c : r, span: (layout == .rows || layout == .columns) ? 1 : n,
                             text: samples[i], hex: nil, isCal: !calibrator.isEmpty && samples[i] == calibrator)
        }
        switch layout {
        case .rows, .primerColumns: return (primerBands, sampleBands)
        case .columns, .primerRows: return (sampleBands, primerBands)
        }
    }
}

struct PlateArrangement: View {
    @EnvironmentObject var store: Store
    let plate: PlateLayout
    let n: Int
    let calibrator: String
    let order: Int              // plate number in the list, staggers the fill animation

    let highlight: Set<Int>?    // wells (row × 12 + column) picked out for bench mode; the rest fade
    let animated: Bool

    init(plate: PlateLayout, n: Int, calibrator: String, order: Int, highlight: Set<Int>? = nil, animated: Bool = true) {
        self.plate = plate; self.n = n; self.calibrator = calibrator; self.order = order
        self.highlight = highlight; self.animated = animated
    }

    static let pitch: CGFloat = 34
    static let nameW: CGFloat = 132

    /// Room above the plate for upright labels, and the plate's own top margin.
    private static func header(_ top: [PlateBand]) -> (outside: CGFloat, inside: CGFloat) {
        (top.contains { $0.span == 1 } ? 88 : 0, top.contains { $0.span > 1 } ? 50 : 30)
    }

    static func size(_ plate: PlateLayout) -> CGSize {
        let h = header(plate.bands(colors: GeneColors(), calibrator: "").top)
        return CGSize(width: nameW + 8 + 26 + 12 * pitch + 14 + 6, height: 4 + h.outside + h.inside + 8 * pitch + 16 + 14)
    }

    var body: some View {
        let live = store.platesAnimating && store.motion && animated
        return TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !live)) { ctx in
            Canvas { g, size in draw(&g, size, live ? ctx.date : .distantFuture) }
        }
        .frame(width: Self.size(plate).width, height: Self.size(plate).height)
        .overlay(HoverCanvas { g, size, p in drawHover(&g, size, p) })
    }

    /// Where the plate and its wells sit.
    private struct Frame {
        var px: CGFloat, plateRect: CGRect, wellX0: CGFloat, wellY0: CGFloat, inside: CGFloat
        func wx(_ c: Int) -> CGFloat { wellX0 + CGFloat(c) * PlateArrangement.pitch }
        func wy(_ r: Int) -> CGFloat { wellY0 + CGFloat(r) * PlateArrangement.pitch }
    }

    private func frame(_ top: [PlateBand]) -> Frame {
        let pitch = Self.pitch
        let head = Self.header(top)
        let px = Self.nameW + 8
        let plateRect = CGRect(x: px, y: 4 + head.outside, width: 26 + 12 * pitch + 14, height: head.inside + 8 * pitch + 16)
        return Frame(px: px, plateRect: plateRect, wellX0: px + 26 + pitch / 2, wellY0: plateRect.minY + head.inside + pitch / 2, inside: head.inside)
    }

    private func colorFor(_ primer: Int) -> String { store.colors.color(plate.primers[primer], plate.primerIndex[primer]) }

    private func short(_ s: String, _ max: Int) -> String { s.count > max ? String(s.prefix(max - 1)) + "…" : s }

    /// A primer's coloured tag.
    private func primerTag(_ g: inout GraphicsContext, _ r: CGRect, _ band: PlateBand, upright: Bool = false) {
        let hex = band.hex ?? "4A78B8"
        let (start, end) = upright ? (CGPoint(x: r.minX, y: 0), CGPoint(x: r.maxX, y: 0)) : (CGPoint(x: 0, y: r.minY), CGPoint(x: 0, y: r.maxY))
        g.fill(Path(roundedRect: r, cornerRadius: min(10, min(r.width, r.height) / 2)),
               with: .linearGradient(Gradient(colors: [Color(hex: tintHex(hex, 0.15)), Color(hex: hex)]), startPoint: start, endPoint: end))
        let fg: Color = isDarkHex(hex) ? .white : Color(hex: "172033")
        let label = Text(band.isRef ? "\(band.text) · ref" : band.text).font(.system(size: 11, weight: .heavy)).foregroundColor(fg)
        if upright {
            var u = g
            u.translateBy(x: r.midX, y: r.maxY - 7)
            u.rotate(by: .degrees(-90))
            u.draw(label, at: .zero, anchor: .leading)
        } else {
            g.draw(label, in: r.insetBy(dx: 6, dy: max(2.5, (r.height - 15) / 2)))
        }
    }

    private func sampleText(_ band: PlateBand, size: CGFloat = 11.5, max: Int = 17) -> Text {
        let ink = Color(hex: "172033"), grey = Color(hex: "6B7A90")
        var t = Text(short(band.text, max)).font(.system(size: size, weight: band.isCal ? .bold : .medium)).foregroundColor(ink)
        if band.isCal { t = Text("cal  ").font(.system(size: 9, weight: .semibold)).foregroundColor(grey) + t }
        return t
    }

    private func draw(_ g: inout GraphicsContext, _ size: CGSize, _ now: Date) {
        let pitch = Self.pitch
        let (top, side) = plate.bands(colors: store.colors, calibrator: calibrator)
        let f = frame(top)
        let px = f.px, plateRect = f.plateRect, wellX0 = f.wellX0, wellY0 = f.wellY0
        let head = (outside: plateRect.minY - 4, inside: f.inside)
        func wx(_ c: Int) -> CGFloat { f.wx(c) }
        func wy(_ r: Int) -> CGFloat { f.wy(r) }
        let grey = Color(hex: "6B7A90"), rule = Color(hex: "C9D4E3")

        // plate body with a cut corner at A1
        let cut: CGFloat = 16
        var body = Path()
        body.move(to: CGPoint(x: plateRect.minX + cut, y: plateRect.minY))
        body.addLine(to: CGPoint(x: plateRect.maxX - 12, y: plateRect.minY))
        body.addQuadCurve(to: CGPoint(x: plateRect.maxX, y: plateRect.minY + 12), control: CGPoint(x: plateRect.maxX, y: plateRect.minY))
        body.addLine(to: CGPoint(x: plateRect.maxX, y: plateRect.maxY - 12))
        body.addQuadCurve(to: CGPoint(x: plateRect.maxX - 12, y: plateRect.maxY), control: CGPoint(x: plateRect.maxX, y: plateRect.maxY))
        body.addLine(to: CGPoint(x: plateRect.minX + 12, y: plateRect.maxY))
        body.addQuadCurve(to: CGPoint(x: plateRect.minX, y: plateRect.maxY - 12), control: CGPoint(x: plateRect.minX, y: plateRect.maxY))
        body.addLine(to: CGPoint(x: plateRect.minX, y: plateRect.minY + cut))
        body.closeSubpath()
        var shadowed = g
        shadowed.addFilter(.shadow(color: Color(hex: "1E4A83").opacity(0.22), radius: 7, y: 3))
        shadowed.fill(body, with: .linearGradient(Gradient(colors: [Brand.card, Color(hex: "E9EEF5")]),
                                                  startPoint: CGPoint(x: 0, y: plateRect.minY), endPoint: CGPoint(x: 0, y: plateRect.maxY)))
        g.stroke(body, with: .color(Color(hex: "AFBFD4")), lineWidth: 1.4)
        let field = CGRect(x: wellX0 - pitch / 2 - 3, y: wellY0 - pitch / 2 - 3, width: 12 * pitch + 6, height: 8 * pitch + 6)
        g.fill(Path(roundedRect: field, cornerRadius: 8), with: .color(Color(hex: "F3F6FA")))
        g.stroke(Path(roundedRect: field, cornerRadius: 8), with: .color(Color(hex: "D3DDEA")), lineWidth: 1)

        // labels over the columns: tags on the plate's top margin, or upright above a single column
        for band in top where band.start + band.span <= 12 {
            if band.span > 1 {
                let x0 = wx(band.start) - pitch / 2 + 2, x1 = wx(band.start + band.span - 1) + pitch / 2 - 2
                let r = CGRect(x: x0, y: plateRect.minY + 8, width: x1 - x0, height: 20)
                if band.hex != nil {
                    primerTag(&g, r, band)
                } else {
                    g.fill(Path(roundedRect: r, cornerRadius: 10), with: .color(Color(hex: band.isCal ? "DCE6F3" : "EAF0F7")))
                    g.stroke(Path(roundedRect: r, cornerRadius: 10), with: .color(rule), lineWidth: 1)
                    let chars = max(4, Int((r.width - 10) / 6.6))
                    g.draw(sampleText(band, size: 10.5, max: chars), in: r.insetBy(dx: 6, dy: 3))
                }
            } else {
                let x = wx(band.start)
                if band.hex != nil {
                    primerTag(&g, CGRect(x: x - pitch / 2 + 3, y: plateRect.minY - 84, width: pitch - 6, height: 80), band, upright: true)
                } else {
                    var u = g
                    u.translateBy(x: x, y: plateRect.minY - 8)
                    u.rotate(by: .degrees(-90))
                    u.draw(sampleText(band, size: 10.5, max: 14), at: .zero, anchor: .leading)
                }
            }
        }
        for c in 0..<12 {
            g.draw(Text("\(c + 1)").font(.system(size: 9.5, weight: .bold, design: .rounded)).foregroundColor(grey),
                   at: CGPoint(x: wx(c), y: plateRect.minY + head.inside - 10))
        }
        for r in 0..<8 {
            g.draw(Text(rowLetters[r]).font(.system(size: 10, weight: .heavy, design: .serif)).foregroundColor(Brand.accent),
                   at: CGPoint(x: px + 13, y: wy(r)))
        }

        // labels beside the rows
        for band in side where band.start + band.span <= 8 {
            let y0 = wy(band.start) - pitch / 2, y1 = wy(band.start + band.span - 1) + pitch / 2
            if band.hex != nil {
                let r = band.span == 1 ? CGRect(x: 8, y: wy(band.start) - 11, width: Self.nameW - 10, height: 22)
                                       : CGRect(x: 8, y: y0 + 3, width: Self.nameW - 10, height: y1 - y0 - 6)
                primerTag(&g, r, band)
                var lead = Path()
                for row in band.start..<(band.start + band.span) {
                    lead.move(to: CGPoint(x: r.maxX + 2, y: wy(row))); lead.addLine(to: CGPoint(x: px - 1, y: wy(row)))
                }
                g.stroke(lead, with: .color(rule), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            } else if band.span == 1 {
                g.draw(sampleText(band), at: CGPoint(x: Self.nameW, y: wy(band.start)), anchor: .trailing)
                var lead = Path()
                lead.move(to: CGPoint(x: Self.nameW + 3, y: wy(band.start))); lead.addLine(to: CGPoint(x: px - 1, y: wy(band.start)))
                g.stroke(lead, with: .color(rule), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            } else {
                // a bracket gathering the sample's rows
                let mid = (y0 + y1) / 2
                g.draw(sampleText(band), at: CGPoint(x: Self.nameW - 4, y: mid), anchor: .trailing)
                var br = Path()
                br.move(to: CGPoint(x: px - 2, y: y0 + 5)); br.addLine(to: CGPoint(x: Self.nameW + 2, y: y0 + 5))
                br.addLine(to: CGPoint(x: Self.nameW + 2, y: y1 - 5)); br.addLine(to: CGPoint(x: px - 2, y: y1 - 5))
                g.stroke(br, with: .color(Color(hex: "AFBFD4")), lineWidth: 1.2)
            }
        }

        // wells, filled column by column
        let start = store.plateRevealAt.addingTimeInterval(Double(order) * 0.35)
        let elapsed = now.timeIntervalSince(start)
        let radius = pitch * 0.39
        for r in 0..<8 {
            for c in 0..<12 {
                let content = plate.content(r, c)
                let center = CGPoint(x: wx(c), y: wy(r))
                // the empty well
                let well = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                g.fill(Path(ellipseIn: well), with: .radialGradient(Gradient(colors: [Color(hex: "D2DBE7"), Color(hex: "EEF2F7")]),
                                                                    center: CGPoint(x: center.x, y: center.y - radius * 0.35), startRadius: 0, endRadius: radius * 1.1))
                g.stroke(Path(ellipseIn: well), with: .color(Color(hex: "B7C5D8")), lineWidth: 0.9)
                guard let content else { continue }
                let p = store.motion && animated ? easeOutBack((elapsed - Double(c) * 0.075 - Double(r) * 0.03) / 0.32) : 1
                guard p > 0 else { continue }
                let hex = colorFor(content.primer)
                let picked = highlight?.contains(r * 12 + c)
                var w = g
                if picked == false { w.opacity = 0.16 }
                if picked == true {
                    w.fill(Path(ellipseIn: well.insetBy(dx: -radius * 0.6, dy: -radius * 0.6)),
                           with: .radialGradient(Gradient(colors: [Color(hex: "8CF5A4").opacity(0.75), Color(hex: "8CF5A4").opacity(0)]),
                                                 center: center, startRadius: radius * 0.7, endRadius: radius * 1.6))
                }
                let rr = radius * 0.9 * CGFloat(p)
                let liquid = CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)
                w.fill(Path(ellipseIn: liquid), with: .radialGradient(Gradient(colors: [Color(hex: tintHex(hex, 0.5)), Color(hex: hex), Color(hex: shadeHex(hex, 0.18))]),
                                                                      center: CGPoint(x: center.x - rr * 0.3, y: center.y - rr * 0.35), startRadius: 0, endRadius: rr * 1.25))
                w.stroke(Path(ellipseIn: liquid), with: .color(Color(hex: shadeHex(hex, 0.3)).opacity(0.8)), lineWidth: 0.9)
                w.fill(Path(ellipseIn: CGRect(x: center.x - rr * 0.55, y: center.y - rr * 0.62, width: rr * 0.62, height: rr * 0.38)), with: .color(.white.opacity(0.55)))
                if picked == true {
                    w.stroke(Path(ellipseIn: well.insetBy(dx: -1.5, dy: -1.5)), with: .color(Color(hex: "2E9E5B")), lineWidth: 2)
                }
            }
        }

        // the pipette, dropping liquid into the column it is filling
        if store.motion && animated && elapsed > -0.1 && elapsed < 12 * 0.075 + 0.45 && !plate.samples.isEmpty {
            let col = min(11, max(0, Int(elapsed / 0.075)))
            let x = wx(col)
            let bob = CGFloat(4 * sin(elapsed * 30))
            let tipY = wellY0 - pitch / 2 - 2 + bob
            var tip = Path()
            tip.move(to: CGPoint(x: x - 4, y: tipY - 16)); tip.addLine(to: CGPoint(x: x, y: tipY)); tip.addLine(to: CGPoint(x: x + 4, y: tipY - 16)); tip.closeSubpath()
            var pip = g
            pip.addFilter(.shadow(color: .black.opacity(0.25), radius: 3, y: 2))
            pip.fill(Path(roundedRect: CGRect(x: x - 6, y: tipY - 46, width: 12, height: 30), cornerRadius: 4), with: .color(Color(hex: "5B8BD6")))
            pip.fill(Path(roundedRect: CGRect(x: x - 9, y: tipY - 52, width: 18, height: 7), cornerRadius: 3), with: .color(Color(hex: "1E4A83")))
            pip.fill(tip, with: .color(Color(hex: "F2F6FB")))
            pip.stroke(tip, with: .color(Color(hex: "9AA8BC")), lineWidth: 1)
            let dropY = tipY + CGFloat((elapsed * 13).truncatingRemainder(dividingBy: 1)) * pitch * 0.8
            g.fill(dropPath(CGPoint(x: x, y: dropY), 3), with: .color(Color(hex: "4A78B8")))
        }
    }

    /// The ring around the well under the pointer, and what goes in it.
    private func drawHover(_ g: inout GraphicsContext, _ size: CGSize, _ h: CGPoint) {
        let pitch = Self.pitch
        let f = frame(plate.bands(colors: store.colors, calibrator: calibrator).top)
        let c = Int(((h.x - (f.wellX0 - pitch / 2)) / pitch).rounded(.down)), r = Int(((h.y - (f.wellY0 - pitch / 2)) / pitch).rounded(.down))
        guard (0..<12).contains(c), (0..<8).contains(r) else { return }
        func wx(_ c: Int) -> CGFloat { f.wx(c) }
        func wy(_ r: Int) -> CGFloat { f.wy(r) }
        let radius = pitch * 0.39
        do {
            var lines = ["\(rowLetters[r])\(c + 1)"]
            if let w = plate.content(r, c) {
                lines[0] += " · \(plate.samples[w.sample])"
                lines.append("\(plate.primers[w.primer]) · replicate \(w.rep + 1) of \(n)")
            } else {
                lines.append("empty")
            }
            let w = (lines.map { ($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width }.max() ?? 60) + 20
            let center = CGPoint(x: wx(c), y: wy(r))
            var bx = center.x + 14
            if bx + w > size.width - 2 { bx = center.x - 14 - w }
            let by = max(center.y - 46, 2)
            g.stroke(Path(ellipseIn: CGRect(x: center.x - radius - 2, y: center.y - radius - 2, width: radius * 2 + 4, height: radius * 2 + 4)),
                     with: .color(Brand.accent), lineWidth: 2.2)
            var tip = g
            tip.addFilter(.shadow(color: .black.opacity(0.2), radius: 5, y: 2))
            tip.fill(Path(roundedRect: CGRect(x: bx, y: by, width: w, height: 40), cornerRadius: 7), with: .color(Brand.tooltip.opacity(0.94)))
            for (i, line) in lines.enumerated() {
                g.draw(Text(line).font(.system(size: 11, weight: i == 0 ? .bold : .medium)).foregroundColor(.white),
                       at: CGPoint(x: bx + 10, y: by + 12 + CGFloat(i) * 16), anchor: .leading)
            }
        }
    }
}
