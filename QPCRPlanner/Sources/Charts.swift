import SwiftUI
import AppKit

// MARK: - Graphs drawn in the app
//
// Styled after the lab's Excel charts (filled bars with thin black outlines, black error bars with
// caps) and tidied for reading: round tick values, no gridlines (a clean background), a dashed RQ = 1 line for the
// calibrator, group brackets under the axis (A3 | C2), "n.d." where nothing amplified, and the exact
// numbers when the pointer rests on a bar.

struct BarValue {
    var value: Double
    var sd: Double
    var low: Bool
    var counted: Int
    var wells: Int
}

struct BarCategory {
    var label: String            // shown under the bar
    var group: String?           // for the bracket under the axis
    var name: String             // full condition name, for the read-out
    var cells: [BarValue?]       // one per series
    var measured: [Bool]         // measured but no Ct at all -> "n.d."
    var key = ""                 // what a click spotlights in every graph and the table
    var ids: [String?] = []      // the condition behind each bar, so a bar can travel between layouts
}

/// The other way the same bars are laid out (by condition ⇄ compared), for the switch between them.
struct ChartAlt {
    var categories: [BarCategory?]
    var seriesCount: Int
    var brackets: Bool
}

struct BarSeries {
    var name: String
    var fill: String
}

private func niceTicks(_ maxValue: Double) -> [Double] {
    let m = max(maxValue, 1e-9)
    let raw = m / 4
    let mag = pow(10, floor(log10(raw)))
    let step = [1.0, 2, 2.5, 5, 10].map { $0 * mag }.first { $0 >= raw } ?? 10 * mag
    var ticks: [Double] = []
    var v = 0.0
    while v < m - 1e-9 { ticks.append(v); v += step }
    ticks.append(v)
    return ticks
}

private func tickText(_ v: Double, _ step: Double) -> String {
    let places = step >= 1 ? 0 : (step >= 0.1 ? 1 : (step >= 0.01 ? 2 : 3))
    return String(format: "%.\(places)f", v)
}

private func textWidth(_ s: String, _ size: CGFloat, bold: Bool = false) -> CGFloat {
    (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)]).width
}

struct MatureChart: View {
    @EnvironmentObject var store: Store
    let title: String
    let colorHex: String
    let categories: [BarCategory?]      // nil = a gap
    let series: [BarSeries]
    let xTitle: String
    let yTitle: String
    let refLine: Bool
    let brackets: Bool
    let alt: ChartAlt?

    init(title: String, colorHex: String, categories: [BarCategory?], series: [BarSeries],
         xTitle: String, yTitle: String, refLine: Bool, brackets: Bool, alt: ChartAlt? = nil) {
        self.title = title; self.colorHex = colorHex; self.categories = categories; self.series = series
        self.xTitle = xTitle; self.yTitle = yTitle; self.refLine = refLine; self.brackets = brackets; self.alt = alt
    }

    private var anyLow: Bool { categories.contains { $0?.cells.contains { $0?.low == true } == true } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: colorHex))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.6), lineWidth: 0.8))
                    .frame(width: 13, height: 13)
                Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(Brand.ink)
                Spacer(minLength: 6)
                if series.count > 1 {
                    ForEach(Array(series.enumerated()), id: \.offset) { _, s in
                        HStack(spacing: 4) {
                            Rectangle().fill(Color(hex: s.fill)).overlay(Rectangle().stroke(Color.black.opacity(0.7), lineWidth: 0.7)).frame(width: 11, height: 9)
                            Text(s.name).font(.system(size: 11, weight: .semibold)).foregroundColor(Brand.ink)
                        }
                    }
                }
                if refLine {
                    HStack(spacing: 4) {
                        Rectangle().fill(Color.clear).frame(width: 16, height: 1)
                            .overlay(Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: 16, y: 0)) }
                                .stroke(Color(hex: "8C8C8C"), style: StrokeStyle(lineWidth: 1.4, dash: [3, 2])))
                        Text("calibrator").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
                if anyLow {
                    HStack(spacing: 4) {
                        Rectangle().fill(Color(hex: flagFill))
                            .overlay(Rectangle().stroke(Color(hex: flagLine), style: StrokeStyle(lineWidth: 1, dash: [2, 1.5])))
                            .frame(width: 11, height: 9)
                        Text("few wells").font(.system(size: 10.5)).foregroundColor(Color(hex: flagLine))
                    }
                }
            }
            let live = (store.chartsAnimating || store.spotlightFading || store.morphing) && store.motion
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !live)) { ctx in
                // before a reveal that is still to come the bars wait, empty and still; nothing is redrawn
                Canvas { g, size in draw(&g, size, live ? ctx.date : (store.chartRevealAt > Date() ? store.chartRevealAt : .distantFuture)) }
            }
            .overlay(HoverCanvas({ g, size, p in readout(&g, size, p) }, onTap: { p, size in tap(p, size) }))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Brand.rule, lineWidth: 1))
    }

    // MARK: layout

    private struct Slot { var index: Int; var x: CGFloat; var w: CGFloat }

    private struct Geo {
        var plot: CGRect
        var top: Double
        var ticks: [Double]
        var step: Double
        var bottom: CGFloat
        var rotate: Bool
        var slots: [Slot]
        func y(_ v: Double) -> CGFloat { plot.maxY - plot.height * CGFloat(v / top) }
    }

    private static func slots(_ cats: [BarCategory?], _ brackets: Bool, _ plotX: CGFloat, _ plotW: CGFloat) -> [Slot] {
        var units: [(Int, Double)] = []      // (category index, start unit)
        var u = 0.0
        var lastGroup: String? = nil
        for (i, c) in cats.enumerated() {
            guard let c = c else { u += 0.5; lastGroup = nil; continue }
            if brackets, let g = c.group, let lg = lastGroup, lg != g { u += 0.45 }
            units.append((i, u))
            u += 1
            lastGroup = c.group ?? lastGroup
        }
        let total = max(u, 1)
        let unit = plotW / CGFloat(total)
        return units.map { Slot(index: $0.0, x: plotX + CGFloat($0.1) * unit, w: unit) }
    }

    private func geometry(_ size: CGSize, _ cats: [BarCategory?], _ brackets: Bool) -> Geo {
        let maxV = cats.compactMap { $0 }.flatMap { $0.cells }.compactMap { $0.map { $0.value + $0.sd } }.max() ?? 1
        let ticks = niceTicks(max(maxV, refLine ? 1.08 : 0) * 1.04)
        let top = ticks.last ?? 1
        let step = ticks.count > 1 ? ticks[1] - ticks[0] : 1
        let left: CGFloat = 50
        let maxLabel = cats.compactMap { $0?.label }.map { textWidth($0, 10.5) }.max() ?? 0
        let plotW = size.width - left - 8
        let n = max(cats.compactMap { $0 }.count, 1)
        let slotW = plotW / CGFloat(Double(n) + (brackets ? 1 : 0))
        let rotate = !brackets && maxLabel > slotW - 6
        var bottom: CGFloat = rotate ? min(84, maxLabel * 0.64 + 18) : 22
        if brackets { bottom = 46 }
        if !xTitle.trimmingCharacters(in: .whitespaces).isEmpty { bottom += 18 }
        let plot = CGRect(x: left, y: 8, width: plotW, height: max(size.height - 8 - bottom, 40))
        return Geo(plot: plot, top: top, ticks: ticks, step: step, bottom: bottom, rotate: rotate, slots: Self.slots(cats, brackets, plot.minX, plot.width))
    }

    /// Bar j of k in slot s, `value` high.
    private static func barRect(_ geo: Geo, _ s: Slot, _ j: Int, _ k: Int, _ value: Double) -> CGRect {
        let groupW = s.w * (k == 1 ? 0.62 : 0.8)
        let bw = groupW / CGFloat(k)
        let x0 = s.x + (s.w - groupW) / 2
        let h = max(geo.plot.height * CGFloat(value / geo.top), 0)
        return CGRect(x: x0 + CGFloat(j) * bw + (k > 1 ? 1 : 0), y: geo.plot.maxY - h, width: bw - (k > 1 ? 2 : 0), height: h)
    }

    private func slot(at p: CGPoint, _ geo: Geo) -> Slot? {
        guard p.y <= geo.plot.maxY + geo.bottom else { return nil }
        return geo.slots.first { p.x >= $0.x && p.x < $0.x + $0.w && categories[$0.index] != nil }
    }

    /// How far a category is dimmed (0 = not at all), easing from the previous spotlight to this one.
    private func dim(_ key: String, _ now: Date) -> Double {
        func target(_ s: String?) -> Double { s != nil && s != key ? 0.78 : 0 }
        let p = store.motion ? easeOut(now.timeIntervalSince(store.spotlightAt) / 0.3) : 1
        return target(store.spotlightPrev) + (target(store.spotlight) - target(store.spotlightPrev)) * p
    }

    // MARK: drawing

    private func label(_ g: inout GraphicsContext, _ text: Text, _ s: Slot, _ geo: Geo) {
        if geo.rotate {
            var l = g
            l.translateBy(x: s.x + s.w / 2 + 3, y: geo.plot.maxY + 7)
            l.rotate(by: .degrees(-40))
            l.draw(text, at: .zero, anchor: .trailing)
        } else {
            g.draw(text, at: CGPoint(x: s.x + s.w / 2, y: geo.plot.maxY + 11))
        }
    }

    private func draw(_ g: inout GraphicsContext, _ size: CGSize, _ now: Date) {
        let ink = Brand.chartInk, grey = Brand.chartGrey
        let cats = categories
        let geo = geometry(size, cats, brackets)
        let plot = geo.plot

        // tick marks and labels (no gridlines: the lab's graphs keep a clean background)
        for t in geo.ticks {
            var tk = Path(); tk.move(to: CGPoint(x: plot.minX - 4, y: geo.y(t))); tk.addLine(to: CGPoint(x: plot.minX, y: geo.y(t)))
            g.stroke(tk, with: .color(grey), lineWidth: 1)
            g.draw(Text(tickText(t, geo.step)).font(.system(size: 10).monospacedDigit()).foregroundColor(grey),
                   at: CGPoint(x: plot.minX - 7, y: geo.y(t)), anchor: .trailing)
        }
        var yt = g
        yt.translateBy(x: 11, y: plot.midY)
        yt.rotate(by: .degrees(-90))
        yt.draw(Text(yTitle).font(.system(size: 11, weight: .semibold)).foregroundColor(ink), at: .zero)
        if refLine && geo.top >= 1 {
            var rl = Path(); rl.move(to: CGPoint(x: plot.minX, y: geo.y(1))); rl.addLine(to: CGPoint(x: plot.maxX, y: geo.y(1)))
            g.stroke(rl, with: .color(Color(hex: "8C8C8C")), style: StrokeStyle(lineWidth: 1.3, dash: [5, 4]))
        }

        // switching layouts: where each bar was, so it can travel to where it goes now
        var morph: Double? = nil
        var from: [String: CGRect] = [:]
        if let alt, store.motion {
            let t = now.timeIntervalSince(store.morphAt)
            if t >= 0 && t < 0.7 {
                let mp = easeInOut(t / 0.65)
                morph = mp
                let ag = geometry(size, alt.categories, alt.brackets)
                for s in ag.slots {
                    guard let c = alt.categories[s.index] else { continue }
                    for (j, v) in c.cells.enumerated() {
                        guard let v, j < c.ids.count, let id = c.ids[j] else { continue }
                        from[id] = Self.barRect(ag, s, j, alt.seriesCount, v.value)
                    }
                    var fading = g
                    fading.opacity = 1 - mp
                    label(&fading, Text(c.label).font(.system(size: 10.5)).foregroundColor(ink), s, ag)
                }
                // bars with no place in the new layout fade where they stood
                let here = Set(cats.compactMap { $0 }.flatMap { $0.ids.compactMap { $0 } })
                var leaving = g
                leaving.opacity = 0.85 * (1 - mp)
                for (id, r) in from where !here.contains(id) {
                    leaving.fill(Path(r), with: .color(Color(hex: colorHex)))
                }
            }
        }

        // bars
        let revealAt = store.chartRevealAt
        let k = series.count
        for (order, s) in geo.slots.enumerated() {
            guard let c = cats[s.index] else { continue }
            let p = store.motion ? easeOutBack((now.timeIntervalSince(revealAt) - Double(order) * 0.06) / 0.6) : 1
            let d = c.key.isEmpty ? 0 : dim(c.key, now)
            var b = g
            b.opacity = (1 - d) * (morph.map { 0.35 + 0.65 * $0 } ?? 1)
            if store.spotlight != nil && store.spotlight == c.key {
                let band = CGRect(x: s.x + 1, y: plot.minY, width: s.w - 2, height: plot.height)
                g.fill(Path(roundedRect: band, cornerRadius: 4), with: .color(Brand.mid.opacity(0.1)))
            }
            for j in 0..<k {
                guard j < c.cells.count, let v = c.cells[j] else {
                    if j < c.measured.count, c.measured[j] {
                        let r = Self.barRect(geo, s, j, k, 0)
                        b.draw(Text("n.d.").font(.system(size: 9, weight: .medium)).foregroundColor(Color(hex: "9AA3B2")),
                               at: CGPoint(x: r.midX, y: plot.maxY - 8))
                    }
                    continue
                }
                let full = Self.barRect(geo, s, j, k, v.value)
                var rect = Self.barRect(geo, s, j, k, v.value * Double(max(p, 0)))
                var bar = b
                if let mp = morph {
                    bar.opacity = 1 - d
                    let id = j < c.ids.count ? c.ids[j] : nil
                    if let id, let f = from[id] {
                        rect = CGRect(x: f.minX + (full.minX - f.minX) * mp, y: f.minY + (full.minY - f.minY) * mp,
                                      width: f.width + (full.width - f.width) * mp, height: f.height + (full.height - f.height) * mp)
                    } else {
                        rect = CGRect(x: full.minX, y: full.maxY - full.height * mp, width: full.width, height: full.height * mp)
                    }
                }
                if v.low {
                    bar.fill(Path(rect), with: .color(Color(hex: flagFill)))
                    bar.stroke(Path(rect), with: .color(Color(hex: flagLine)), style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                } else {
                    bar.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color(hex: tintHex(series[j].fill, 0.12)), Color(hex: series[j].fill)]),
                                                               startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.minY)))
                    bar.stroke(Path(rect), with: .color(Brand.barEdge), lineWidth: 0.9)
                }
                let errAlpha = clamp01((p - 0.75) / 0.25) * (morph.map { clamp01(($0 - 0.8) / 0.2) } ?? 1)
                if v.sd > 0 && errAlpha > 0 {
                    let cx = full.midX
                    let yTop = geo.y(v.value + v.sd), yBot = geo.y(max(v.value - v.sd, 0))
                    let cap = min(full.width * 0.45, 9) / 2
                    var e = Path()
                    e.move(to: CGPoint(x: cx, y: yTop)); e.addLine(to: CGPoint(x: cx, y: yBot))
                    e.move(to: CGPoint(x: cx - cap, y: yTop)); e.addLine(to: CGPoint(x: cx + cap, y: yTop))
                    e.move(to: CGPoint(x: cx - cap, y: yBot)); e.addLine(to: CGPoint(x: cx + cap, y: yBot))
                    b.stroke(e, with: .color(Brand.errorBar.opacity(errAlpha)), lineWidth: 1.1)
                }
                if v.low && p > 0.9 && morph == nil {
                    b.draw(Text("\(v.counted)/\(v.wells)").font(.system(size: 9, weight: .bold)).foregroundColor(Color(hex: flagLine)),
                           at: CGPoint(x: full.midX, y: geo.y(v.value + v.sd) - 8))
                }
            }
            // category label
            let low = c.cells.contains { $0?.low == true }
            let spot = store.spotlight != nil && store.spotlight == c.key
            var lb = b
            if let mp = morph { lb.opacity = (1 - d) * mp }
            label(&lb, Text(c.label).font(.system(size: 10.5, weight: low || spot ? .bold : .regular))
                    .foregroundColor(low ? Color(hex: flagLine) : (spot ? Brand.accent : ink)), s, geo)
        }

        // axes
        var axes = Path()
        axes.move(to: CGPoint(x: plot.minX, y: plot.minY)); axes.addLine(to: CGPoint(x: plot.minX, y: plot.maxY)); axes.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        g.stroke(axes, with: .color(grey), lineWidth: 1.1)

        // group brackets: A3 | C2
        if brackets {
            var groups: [(String, CGFloat, CGFloat)] = []
            for s in geo.slots {
                guard let c = cats[s.index], let gname = c.group else { continue }
                if let last = groups.last, last.0 == gname { groups[groups.count - 1].2 = s.x + s.w } else { groups.append((gname, s.x, s.x + s.w)) }
            }
            for (gname, a, b) in groups {
                var br = Path()
                let by = plot.maxY + 24
                br.move(to: CGPoint(x: a + 4, y: by - 4)); br.addLine(to: CGPoint(x: a + 4, y: by))
                br.addLine(to: CGPoint(x: b - 4, y: by)); br.addLine(to: CGPoint(x: b - 4, y: by - 4))
                g.stroke(br, with: .color(grey), lineWidth: 1)
                g.draw(Text(gname).font(.system(size: 11, weight: .bold)).foregroundColor(ink), at: CGPoint(x: (a + b) / 2, y: by + 10))
            }
        }
        if !xTitle.trimmingCharacters(in: .whitespaces).isEmpty {
            g.draw(Text(xTitle).font(.system(size: 11, weight: .semibold)).foregroundColor(ink),
                   at: CGPoint(x: plot.midX, y: size.height - 8))
        }
    }

    /// A click on a bar spotlights its condition everywhere; a click on empty space clears it.
    private func tap(_ p: CGPoint, _ size: CGSize) {
        let geo = geometry(size, categories, brackets)
        if let s = slot(at: p, geo), let c = categories[s.index], !c.key.isEmpty {
            store.toggleSpotlight(c.key)
        } else {
            store.toggleSpotlight(nil)
        }
    }

    /// The highlight and exact numbers for the bars under the pointer, on the layer above the chart.
    private func readout(_ g: inout GraphicsContext, _ size: CGSize, _ hp: CGPoint) {
        let geo = geometry(size, categories, brackets)
        guard let s = slot(at: hp, geo), let c = categories[s.index] else { return }
        let k = series.count
        let band = CGRect(x: s.x + 1, y: geo.plot.minY, width: s.w - 2, height: geo.plot.height)
        g.fill(Path(band), with: .color(Brand.mid.opacity(0.08)))
        g.stroke(Path(band), with: .color(Brand.mid.opacity(0.3)), lineWidth: 1)
        var lines = [c.name]
        for j in 0..<k {
            if j < c.cells.count, let v = c.cells[j] {
                lines.append((k > 1 ? series[j].name + ": " : "") + "\(fmtNum(v.value, 3)) ± \(fmtNum(v.sd, 3))  (\(v.counted)/\(v.wells) wells)")
            } else if j < c.measured.count, c.measured[j] {
                lines.append((k > 1 ? series[j].name + ": " : "") + "no Ct (n.d.)")
            }
        }
        if !c.key.isEmpty { lines.append(store.spotlight == c.key ? "click to clear the spotlight" : "click to spotlight in every graph") }
        let w = (lines.map { textWidth($0, 11, bold: true) }.max() ?? 80) + 20
        let h = CGFloat(lines.count) * 15 + 10
        let hoverX = s.x + s.w / 2
        var bx = hoverX + 12
        if bx + w > size.width - 2 { bx = hoverX - 12 - w }
        let by = min(max(hp.y - h - 6, 2), size.height - h - 2)
        var tip = g
        tip.addFilter(.shadow(color: .black.opacity(0.18), radius: 5, y: 2))
        tip.fill(Path(roundedRect: CGRect(x: bx, y: by, width: w, height: h), cornerRadius: 7), with: .color(Brand.tooltip.opacity(0.94)))
        for (i, line) in lines.enumerated() {
            let last = !c.key.isEmpty && i == lines.count - 1
            g.draw(Text(line).font(.system(size: last ? 10 : 11, weight: i == 0 ? .bold : .medium)).foregroundColor(.white.opacity(last ? 0.6 : 1)),
                   at: CGPoint(x: bx + 10, y: by + 12 + CGFloat(i) * 15), anchor: .leading)
        }
    }
}
