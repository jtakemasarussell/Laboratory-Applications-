import SwiftUI
import AppKit

// MARK: - The freezer box, the sample timeline, the microscope room and the sounds

// MARK: Freezer box (the antibody library)
//
// The library as a −20 °C freezer box: a tube for each saved antibody, its cap coloured by the host it was
// raised in (primaries) or by its dye (secondaries). Tubes used lately sit at the front; ones not touched
// for weeks are frosted over. Click a tube and it lifts out and goes onto the stain card.

/// When each antibody (by name) was last taken out, kept beside the library so the plate format is unchanged.
enum FreezerLog {
    private static let key = "freezerLastUsed"
    static func lastUsed(_ name: String) -> Date? {
        (UserDefaults.standard.dictionary(forKey: key)?[name] as? Double).map { Date(timeIntervalSince1970: $0) }
    }
    static func touch(_ names: [String]) {
        guard !names.isEmpty else { return }
        var d = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        for n in names where !n.trimmingCharacters(in: .whitespaces).isEmpty { d[n] = Date().timeIntervalSince1970 }
        UserDefaults.standard.set(d, forKey: key)
    }
    /// 0 = used today … 1 = untouched for a month or more (or never).
    static func frost(_ name: String) -> Double {
        guard let d = lastUsed(name) else { return 0.85 }
        return min(1, max(0, Date().timeIntervalSince(d) / (30 * 86400)))
    }
}

let hostCapHex: [String: String] = [
    "rabbit": "E2483D", "goat": "F2A900", "mouse": "2F6FE0", "rat": "17A2A2", "sheep": "8E5BD1",
    "chicken": "E07A2D", "guinea pig": "B5651D", "human": "6B7A90", "donkey": "8C8C8C",
]

struct FreezerTube: Identifiable {
    let id: UUID
    let label: String
    let sub: String
    let capHex: String
    let frost: Double
}

/// The snowflake button that opens the box.
struct FreezerButton: View {
    @EnvironmentObject var store: Store
    let secondaries: Bool
    let add: (UUID) -> Void
    private let open = State(initialValue: false)

    var body: some View {
        Button { open.wrappedValue.toggle() } label: {
            Label("Freezer", systemImage: "snowflake").font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.borderless)
        .foregroundColor(Brand.mid)
        .help("Pick from the antibody freezer box")
        .popover(isPresented: open.projectedValue, arrowEdge: .bottom) {
            FreezerBox(tubes: tubes, title: secondaries ? "Secondaries · −20 °C" : "Primary antibodies · −20 °C", legend: !secondaries,
                       motion: store.motion) { id in
                add(id)
                DispatchQueue.main.asyncAfter(deadline: .now() + (store.motion ? 0.35 : 0)) { open.wrappedValue = false }
            }
        }
    }

    private var tubes: [FreezerTube] {
        let list: [FreezerTube]
        if secondaries {
            list = store.library.secondaries.map { q in
                FreezerTube(id: q.id, label: q.name, sub: q.dilution > 0 ? "1:\(fmtNum(q.dilution))" : "",
                            capHex: secondaryFluor(q)?.hex ?? "9AA6B6", frost: FreezerLog.frost(q.name))
            }
        } else {
            list = store.library.primaries.map { p in
                let host = host(ofPrimary: p) ?? ""
                return FreezerTube(id: p.id, label: markerName(p.name), sub: host.isEmpty ? p.cat : host,
                                   capHex: hostCapHex[host] ?? "9AA6B6", frost: FreezerLog.frost(p.name))
            }
        }
        // the ones used lately at the front
        return list.sorted { $0.frost < $1.frost }
    }
}

struct FreezerBox: View {
    let tubes: [FreezerTube]
    let title: String
    let legend: Bool
    let motion: Bool
    let pick: (UUID) -> Void
    private let lifted = State(initialValue: UUID?.none)
    private let hover = State(initialValue: UUID?.none)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "snowflake").foregroundColor(Color(hex: "9BD2FF"))
                Text(title).font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                Spacer()
                Text("\(tubes.count) tubes").font(.system(size: 11)).foregroundColor(Color(hex: "9FB7D6"))
            }
            if tubes.isEmpty {
                Text("The box is empty: antibodies are added here when you export a plan.")
                    .font(.system(size: 11)).foregroundColor(Color(hex: "9FB7D6")).frame(width: 330, alignment: .leading)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(58), spacing: 6), count: 6), spacing: 8) {
                    ForEach(tubes) { t in tube(t) }
                }
                .padding(10)
                .background(
                    // the cardboard grid of the box, frosted at the edges
                    RoundedRectangle(cornerRadius: 8).fill(Color(hex: "1B2A3E"))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(0.55), Color(hex: "BFE3FF").opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 2))
                )
            }
            if legend {
                HStack(spacing: 10) {
                    ForEach(["rabbit", "goat", "mouse", "rat", "sheep"], id: \.self) { h in
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: hostCapHex[h]!)).frame(width: 8, height: 8)
                            Text(h).font(.system(size: 10)).foregroundColor(Color(hex: "9FB7D6"))
                        }
                    }
                }
            }
            Text("Front: used lately · frosted: untouched for weeks").font(.system(size: 10)).foregroundColor(Color(hex: "6F87A8"))
        }
        .padding(14)
        .background(LinearGradient(colors: [Color(hex: "0E1B2C"), Color(hex: "142740")], startPoint: .top, endPoint: .bottom))
    }

    private func tube(_ t: FreezerTube) -> some View {
        let up = lifted.wrappedValue == t.id
        let over = hover.wrappedValue == t.id
        return Button {
            if motion { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { lifted.wrappedValue = t.id } }
            pick(t.id)
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .top) {
                    // the tube: frosted plastic with a little liquid, and its coloured cap
                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(hex: t.capHex)).frame(width: 26, height: 10)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                        TubeShape()
                            .fill(LinearGradient(colors: [Color.white.opacity(0.85), Color(hex: "DDE8F3").opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 22, height: 34)
                            .overlay(alignment: .bottom) {
                                TubeShape()
                                    .fill(Color(hex: t.capHex).opacity(0.35)).frame(width: 20, height: 11).padding(.bottom, 1)
                            }
                    }
                    // frost on tubes left alone
                    if t.frost > 0.15 {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.55 * t.frost))
                            .overlay(Image(systemName: "snowflake").font(.system(size: 9)).foregroundColor(.white.opacity(t.frost)))
                            .frame(width: 30, height: 46)
                            .blendMode(.screen)
                    }
                }
                Text(t.label).font(.system(size: 9.5, weight: .bold)).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
                Text(t.sub).font(.system(size: 8.5)).foregroundColor(Color(hex: "9FB7D6")).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: 58, height: 82)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(over ? 0.10 : 0.03)))
            .offset(y: up ? -18 : (over ? -3 : 0))
            .opacity(up ? 0 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if motion { withAnimation(.easeOut(duration: 0.15)) { hover.wrappedValue = inside ? t.id : (over ? nil : hover.wrappedValue) } }
        }
        .help(t.label)
    }
}

// MARK: Sample timeline

/// From Day 0 to the staining date: the cells grow along it, the fixed date and today are marked, and a
/// note says when fixing is due. Drawn once per change (no animation running).
struct SampleTimeline: View {
    let day0: Date
    let fixed: Date?
    let staining: Date

    private func days(_ a: Date, _ b: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: a), to: Calendar.current.startOfDay(for: b)).day ?? 0
    }

    var body: some View {
        let today = Date()
        let end = max(staining, fixed ?? staining, today)
        let span = max(1, days(day0, end))
        let note: String = {
            guard let f = fixed else { return "" }
            let d = days(today, f)
            if d > 1 { return "fix in \(d) days" }
            if d == 1 { return "fix tomorrow" }
            if d == 0 { return "fix today" }
            return "fixed \(-d) day\(d == -1 ? "" : "s") ago"
        }()
        let due = fixed.map { days(today, $0) } ?? 99
        HStack(spacing: 8) {
            Canvas { g, size in
                let y = size.height / 2
                let x0: CGFloat = 4, x1 = size.width - 4
                func x(_ d: Date) -> CGFloat { x0 + (x1 - x0) * CGFloat(min(span, max(0, days(day0, d)))) / CGFloat(span) }
                // the line, and how far it has come
                g.stroke(Path { p in p.move(to: CGPoint(x: x0, y: y)); p.addLine(to: CGPoint(x: x1, y: y)) }, with: .color(Brand.rule), lineWidth: 3)
                g.stroke(Path { p in p.move(to: CGPoint(x: x0, y: y)); p.addLine(to: CGPoint(x: x(today), y: y)) }, with: .color(Brand.mid.opacity(0.55)), lineWidth: 3)
                // cells, more of them the further along
                let grown = min(14, 1 + days(day0, min(today, fixed ?? today)) / 3)
                for i in 0..<grown {
                    let f = CGFloat(i) / CGFloat(max(1, grown - 1))
                    let cx = x0 + 6 + (x(min(today, fixed ?? today)) - x0 - 6) * f
                    let cy = y + CGFloat(sin(Double(i) * 2.1)) * 5
                    let r: CGFloat = 2.2 + CGFloat(hash01(i, 77)) * 1.6
                    g.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)), with: .color(Color(hex: "2FB85A").opacity(0.75)))
                }
                func mark(_ d: Date, _ color: Color, _ big: Bool) {
                    let r: CGFloat = big ? 5 : 3.5
                    g.fill(Path(ellipseIn: CGRect(x: x(d) - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(color))
                    g.stroke(Path(ellipseIn: CGRect(x: x(d) - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(.white), lineWidth: 1.2)
                }
                mark(day0, Brand.navy, false)
                if let f = fixed { mark(f, Color(hex: "E2483D"), true) }
                mark(staining, Brand.mid, false)
                // today: a thin upright tick
                g.stroke(Path { p in p.move(to: CGPoint(x: x(today), y: y - 8)); p.addLine(to: CGPoint(x: x(today), y: y + 8)) }, with: .color(Brand.ink.opacity(0.6)), lineWidth: 1.2)
            }
            .frame(height: 22)
            if !note.isEmpty {
                Text(note).font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(due <= 1 && due >= 0 ? Color(hex: "C2362B") : Brand.mid)
                    .fixedSize()
            }
        }
        .help("Day 0 (navy) → fixed (red) → staining (blue); the tick is today, the green dots are the cells growing")
    }
}

// MARK: Microscope room (dark mode)

/// The app in the dark, like the imaging room: set from the File menu; Brand's colours follow it.
enum Theme {
    static var dark = UserDefaults.standard.bool(forKey: "darkRoom")
}

/// In the dark room, each stained well glows faintly in its stain's colour. One picture, drawn when the
/// wells change; nothing moves.
struct RoomGlow: NSViewRepresentable {
    let wells: [(Int, String)]
    let cw: CGFloat, ch: CGFloat
    func makeNSView(context: Context) -> RoomGlowView { RoomGlowView(frame: .zero) }
    func updateNSView(_ v: RoomGlowView, context: Context) { v.show(wells, cw: cw, ch: ch) }
}

final class RoomGlowView: NSView {
    private var key = ""
    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func show(_ wells: [(Int, String)], cw: CGFloat, ch: CGFloat) {
        let k = wells.map { "\($0.0)\($0.1)" }.joined() + "\(Int(cw))"
        guard k != key else { return }
        key = k
        let size = CGSize(width: cw * 12 + 16, height: ch * 8 + 16)
        let img = renderImage(size, screenScale) { c in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            for (w, hex) in wells {
                let ctr = CGPoint(x: 8 + (CGFloat(w % 12) + 0.5) * cw, y: 8 + (CGFloat(w / 12) + 0.5) * ch)
                if let g = CGGradient(colorsSpace: space, colors: [cg(hex, 0.7), cg(hex, 0)] as CFArray, locations: [0, 1]) {
                    c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: cw * 0.85, options: [])
                }
            }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.contents = img
        layer?.contentsGravity = .resize
        CATransaction.commit()
    }
}

// MARK: Sounds

/// Soft sounds made in code (no audio files): a pipette click, the confocal's hum, and a chime when the
/// export is done. Off unless switched on in the File menu.
enum Sounds {
    static var on = UserDefaults.standard.bool(forKey: "sounds")
    private static var lastClick = Date.distantPast
    private static let click: NSSound? = make(seconds: 0.05) { t in
        let env = exp(-t * 90)
        return (sin(2 * .pi * 2300 * t) * 0.35 + Double.random(in: -1...1) * 0.25) * env * 0.35
    }
    private static let chime: NSSound? = make(seconds: 1.2) { t in
        let a = sin(2 * .pi * 1318.5 * t) * exp(-t * 3.2)
        let b = t > 0.12 ? sin(2 * .pi * 1975.5 * (t - 0.12)) * exp(-(t - 0.12) * 3.0) : 0
        return (a * 0.5 + b * 0.45) * 0.28
    }
    private static let hum: NSSound? = {
        let s = make(seconds: 2.0) { t in
            // a low, steady scanner hum with a slow shimmer; whole cycles so the loop is seamless
            (sin(2 * .pi * 110 * t) * 0.5 + sin(2 * .pi * 220 * t) * 0.25 + sin(2 * .pi * 330 * t) * 0.08)
                * (0.85 + 0.15 * sin(2 * .pi * 2 * t)) * 0.12
        }
        s?.loops = true
        return s
    }()

    /// Development: each sound is made and plays.
    static func selfTest() {
        on = true
        for (name, snd) in [("click", click), ("chime", chime), ("hum", hum)] {
            print(name, snd.map { String(format: "%.2f s, plays: %@", $0.duration, $0.play() ? "yes" : "no") } ?? "could not be made")
            snd?.stop()
        }
    }

    static func pipette() {
        guard on, Date().timeIntervalSince(lastClick) > 0.045 else { return }
        lastClick = Date()
        click?.stop(); click?.play()
    }
    static func done() { guard on else { return }; chime?.stop(); chime?.play() }
    static func scanning(_ yes: Bool) {
        guard let h = hum else { return }
        if yes && on { h.volume = 0.9; h.play() } else { h.stop() }
    }

    /// A mono 16-bit WAV of `seconds`, sample by sample.
    private static func make(seconds: Double, _ f: (Double) -> Double) -> NSSound? {
        let rate = 44100, n = Int(seconds * Double(rate))
        var pcm = Data(capacity: n * 2)
        for i in 0..<n {
            let t = Double(i) / Double(rate)
            // a short fade at both ends, so nothing clicks
            let edge = min(1, t / 0.004, (seconds - t) / 0.01)
            let v = Int16(max(-1, min(1, f(t) * edge)) * 32000)
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var wav = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count)); wav.append(contentsOf: Array("WAVE".utf8))
        wav.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        wav.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count)); wav.append(pcm)
        return NSSound(data: wav)
    }
}


/// A tube's body: straight sides and a round bottom (works on macOS 13).
struct TubeShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let rad = r.width / 2
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addArc(center: CGPoint(x: r.midX, y: r.maxY - rad), radius: rad, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}
