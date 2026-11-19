import SwiftUI
import AppKit

// MARK: - Plate check: the plate as run, coloured by Ct
//
// Rebuilt from the qTOWER exports: every well with its Ct printed on it, coloured from early (bright mint)
// to late (deep blue), grey with a cross where nothing came up, and a soft amber glow on a replicate that
// sits away from its partners. Hovering a well tells its story.

private let ramp = ["8CF5A4", "2BB3A3", "2F6BC0", "1E3A6E"]
let amberHex = "FFB020"

/// Colour for a Ct, `t` of the way from the earliest Ct on the plates to the latest.
private func ctColor(_ t: Double) -> String {
    let x = min(1, max(0, t)) * Double(ramp.count - 1)
    let i = min(Int(x), ramp.count - 2)
    return mixHex(ramp[i], ramp[i + 1], x - Double(i))
}

func mixHex(_ a: String, _ b: String, _ t: Double) -> String {
    func comps(_ h: String) -> [Double] {
        let v = UInt32(h, radix: 16) ?? 0
        return [Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF)]
    }
    let ca = comps(a), cb = comps(b)
    return zip(ca, cb).map { String(format: "%02X", Int(($0 + ($1 - $0) * t).rounded())) }.joined()
}

struct PlateCheckCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let limit = store.options.replicateLimit
        let plates = store.results.plateChecks(limit: limit)
        let cts = plates.flatMap { $0.wells.compactMap { $0.ct } }
        let lo = floor(cts.min() ?? 15), hi = ceil(cts.max() ?? 35)
        let flagged = plates.flatMap { $0.flagged }
        if !plates.isEmpty {
            Card(title: "Plate check", icon: "checkmark.seal") {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("The plate as it was run, each well coloured by its Ct. A soft amber glow marks a replicate more than")
                        .font(.caption).foregroundStyle(.secondary)
                    Stepper(value: Binding(get: { store.options.replicateLimit }, set: { store.options.replicateLimit = (($0 * 10).rounded() / 10) }),
                            in: 0.1...3, step: 0.1) {
                        Text("\(fmtNum(limit, 1)) Ct").font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundColor(Brand.accent)
                            .rolling(limit, store.motion)
                    }
                    .fixedSize()
                    Text("from its partners.").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 14) {
                    legendRamp(lo, hi)
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: amberHex).opacity(0.35)).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color(hex: amberHex), lineWidth: 2))
                        Text(flagged.isEmpty ? "no stray replicates" : "\(flagged.count) stray replicate\(flagged.count == 1 ? "" : "s")")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(flagged.isEmpty ? Color(hex: "2E7D4F") : Color(hex: "B26B00"))
                    }
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: "C9D1DC")).frame(width: 12, height: 12)
                            .overlay(Text("×").font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                        Text("no Ct").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(Array(plates.enumerated()), id: \.offset) { _, plate in
                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow(text: plate.title, color: Brand.accent, size: 9.5)
                            CtPlate(plate: plate, lo: lo, hi: hi)
                        }
                    }
                }
                if !flagged.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(flagged.prefix(12).enumerated()), id: \.offset) { _, w in
                            Text("\(w.well) · \(w.target)\(w.isRef ? " (reference)" : "") · \(w.sample):  Ct \(fmtNum(w.ct ?? 0, 2)) beside \(w.partners.map { fmtNum($0, 2) }.joined(separator: ", "))  (\(String(format: "%+.2f", w.offBy ?? 0)))")
                                .font(.system(size: 11)).monospacedDigit().foregroundColor(Color(hex: "8A5300"))
                        }
                        if flagged.count > 12 {
                            Text("and \(flagged.count - 12) more; point at a glowing well for its details.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: amberHex).opacity(0.1)))
                }
            }
        }
    }

    private func legendRamp(_ lo: Double, _ hi: Double) -> some View {
        HStack(spacing: 6) {
            Text("Ct \(fmtNum(lo, 0))").font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.secondary)
            LinearGradient(colors: ramp.map { Color(hex: $0) }, startPoint: .leading, endPoint: .trailing)
                .frame(width: 110, height: 9).clipShape(Capsule())
            Text("\(fmtNum(hi, 0))").font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

/// One plate, wells coloured by Ct.
struct CtPlate: View {
    @EnvironmentObject var store: Store
    let plate: PlateCheck
    let lo: Double
    let hi: Double
    static let pitch: CGFloat = 31
    static let size = CGSize(width: 26 + 12 * pitch + 16, height: 26 + 8 * pitch + 14)

    private func center(_ r: Int, _ c: Int) -> CGPoint {
        CGPoint(x: 26 + (CGFloat(c) + 0.5) * Self.pitch, y: 24 + (CGFloat(r) + 0.5) * Self.pitch)
    }

    var body: some View {
        Canvas { g, _ in draw(&g) }
            .frame(width: Self.size.width, height: Self.size.height)
            .overlay(HoverCanvas { g, size, p in hover(&g, size, p) })
    }

    private func draw(_ g: inout GraphicsContext) {
        let pitch = Self.pitch
        let body = CGRect(x: 18, y: 16, width: 12 * pitch + 16, height: 8 * pitch + 16)
        g.fill(Path(roundedRect: body, cornerRadius: 10), with: .color(Brand.plateBody))
        g.stroke(Path(roundedRect: body, cornerRadius: 10), with: .color(Brand.rule), lineWidth: 1)
        for c in 0..<12 {
            g.draw(Text("\(c + 1)").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundColor(Brand.chartGrey),
                   at: CGPoint(x: center(0, c).x, y: 8))
        }
        for r in 0..<8 {
            g.draw(Text(rowLetters[r]).font(.system(size: 9.5, weight: .heavy, design: .serif)).foregroundColor(Brand.accent),
                   at: CGPoint(x: 9, y: center(r, 0).y))
        }
        let byWell = Dictionary(plate.wells.map { ($0.row * 12 + $0.col, $0) }, uniquingKeysWith: { a, _ in a })
        let rad = pitch * 0.42
        for r in 0..<8 {
            for c in 0..<12 {
                let p = center(r, c)
                let well = CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2)
                guard let w = byWell[r * 12 + c] else {
                    g.stroke(Path(ellipseIn: well), with: .color(Brand.rule), lineWidth: 0.9)
                    continue
                }
                if w.flagged {
                    let glow = well.insetBy(dx: -rad * 0.75, dy: -rad * 0.75)
                    g.fill(Path(ellipseIn: glow), with: .radialGradient(Gradient(colors: [Color(hex: amberHex).opacity(0.55), Color(hex: amberHex).opacity(0)]),
                                                                         center: p, startRadius: rad * 0.8, endRadius: rad * 1.75))
                }
                if let ct = w.ct {
                    let hex = ctColor((ct - lo) / max(hi - lo, 0.1))
                    g.fill(Path(ellipseIn: well), with: .radialGradient(Gradient(colors: [Color(hex: tintHex(hex, 0.35)), Color(hex: hex)]),
                                                                         center: CGPoint(x: p.x - rad * 0.3, y: p.y - rad * 0.35), startRadius: 0, endRadius: rad * 1.3))
                    let text: Color = isDarkHex(hex) ? .white : Color(hex: "10233F")
                    g.draw(Text(fmtNum(ct, 1)).font(.system(size: 8.5, weight: .bold, design: .rounded)).monospacedDigit().foregroundColor(text), at: p)
                } else {
                    g.fill(Path(ellipseIn: well), with: .color(Color(hex: "C9D1DC")))
                    g.draw(Text("×").font(.system(size: 11, weight: .bold)).foregroundColor(.white), at: p)
                }
                if w.isRef {
                    g.fill(Path(ellipseIn: CGRect(x: p.x + rad * 0.45, y: p.y - rad * 0.95, width: 5, height: 5)), with: .color(.white.opacity(0.9)))
                }
                if w.flagged {
                    g.stroke(Path(ellipseIn: well.insetBy(dx: -1.5, dy: -1.5)), with: .color(Color(hex: amberHex)), lineWidth: 2.2)
                }
            }
        }
    }

    private func hover(_ g: inout GraphicsContext, _ size: CGSize, _ p: CGPoint) {
        let c = Int(((p.x - 26) / Self.pitch).rounded(.down)), r = Int(((p.y - 24) / Self.pitch).rounded(.down))
        guard (0..<12).contains(c), (0..<8).contains(r), let w = plate.wells.first(where: { $0.row == r && $0.col == c }) else { return }
        let rad = Self.pitch * 0.42
        let ctr = center(r, c)
        g.stroke(Path(ellipseIn: CGRect(x: ctr.x - rad - 3, y: ctr.y - rad - 3, width: rad * 2 + 6, height: rad * 2 + 6)), with: .color(Brand.accent), lineWidth: 2)
        var lines = ["\(w.well) · \(w.sample)", "\(w.target)\(w.isRef ? " (reference)" : "") · " + (w.ct.map { "Ct \(fmtNum($0, 2))" } ?? "no Ct")]
        if !w.partners.isEmpty {
            lines.append("partners: " + w.partners.map { fmtNum($0, 2) }.joined(separator: ", "))
            if let off = w.offBy { lines.append(String(format: "%+.2f Ct from them", off) + (w.flagged ? "  ⚠︎ stray" : "")) }
        }
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let width = (lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 80) + 20
        let height = CGFloat(lines.count) * 15 + 10
        var bx = ctr.x + 16
        if bx + width > size.width - 2 { bx = ctr.x - 16 - width }
        let by = min(max(ctr.y - height / 2, 2), size.height - height - 2)
        var tip = g
        tip.addFilter(.shadow(color: .black.opacity(0.2), radius: 5, y: 2))
        tip.fill(Path(roundedRect: CGRect(x: bx, y: by, width: width, height: height), cornerRadius: 7), with: .color(Brand.tooltip.opacity(0.95)))
        for (i, line) in lines.enumerated() {
            let warn = w.flagged && i == lines.count - 1
            g.draw(Text(line).font(.system(size: 11, weight: i == 0 ? .bold : .medium)).foregroundColor(warn ? Color(hex: amberHex) : .white),
                   at: CGPoint(x: bx + 10, y: by + 12 + CGFloat(i) * 15), anchor: .leading)
        }
    }
}
