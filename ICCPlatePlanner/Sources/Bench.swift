import SwiftUI
import AppKit
import AudioToolbox
import AVFoundation

// MARK: - The freezer box, the sample timeline, the microscope room and the sounds

// MARK: The 4 °C fridge (the antibody library)
//
// The one place antibodies come from: the library as a fridge rack of tubes, the cap coloured by the host
// a primary was raised in or a secondary's dye. Tubes used lately sit at the front; ones not touched for
// weeks look faded. Click a tube to put it on the stain card; add a new tube with its company, catalogue
// number and dilution; right-click a tube to take it out of the fridge; or start an empty row.

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
    static func age(_ name: String) -> Double {
        guard let d = lastUsed(name) else { return 0.85 }
        return min(1, max(0, Date().timeIntervalSince(d) / (30 * 86400)))
    }
}

let hostCapHex: [String: String] = [
    "rabbit": "E2483D", "goat": "F2A900", "mouse": "2F6FE0", "rat": "17A2A2", "sheep": "8E5BD1",
    "chicken": "E07A2D", "guinea pig": "B5651D", "human": "6B7A90", "donkey": "8C8C8C",
]

struct FridgeTube: Identifiable {
    let id: UUID
    let regKey: String      // its manufacturer check

    let label: String       // what the tube says: the marker, or the secondary's short name
    let detail: String      // company · Cat#
    let dilution: String    // "1:500"
    let capHex: String
    let age: Double
    let help: String
}

/// The fridge button on a stain card: opens the rack for primaries or for secondaries.
struct FridgeButton: View {
    @EnvironmentObject var store: Store
    let secondaries: Bool
    let setID: UUID
    private let open = State(initialValue: false)

    var body: some View {
        Button { open.wrappedValue.toggle() } label: {
            Label(secondaries ? "4 °C fridge · secondary / counterstain" : "4 °C fridge · primary antibody", systemImage: "refrigerator")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.borderless)
        .foregroundColor(Brand.navy)
        .help(secondaries ? "Take a secondary or counterstain from the fridge, or add a new tube" : "Take a primary antibody from the fridge, or add a new tube")
        .popover(isPresented: open.projectedValue, arrowEdge: .bottom) {
            FridgeRack(secondaries: secondaries, setID: setID, motion: store.motion) {
                DispatchQueue.main.asyncAfter(deadline: .now() + (store.motion ? 0.3 : 0)) { open.wrappedValue = false }
            }
            .environmentObject(store)
        }
    }
}

struct FridgeRack: View {
    @EnvironmentObject var store: Store
    @ObservedObject var registry = Registry.shared
    let secondaries: Bool
    let setID: UUID
    let motion: Bool
    let close: () -> Void
    private let lifted = State(initialValue: UUID?.none)
    private let showForm = State(initialValue: false)
    /// The door has opened: the tubes slide forward.
    private let opened = State(initialValue: false)
    // the new tube's fields
    private let fName = State(initialValue: ""), fCompany = State(initialValue: ""), fCat = State(initialValue: "")
    private let fDilution = State(initialValue: ""), fRRID = State(initialValue: ""), fProduct = State(initialValue: "")

    private var tubes: [FridgeTube] {
        let list: [FridgeTube]
        if secondaries {
            list = store.library.secondaries.map { q in
                let detail = [q.company ?? "", q.cat ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                return FridgeTube(id: q.id, regKey: Registry.key(q.cat ?? "", q.name), label: q.name, detail: detail, dilution: q.dilution > 0 ? "1:\(fmtNum(q.dilution))" : "1:?",
                                  capHex: secondaryFluor(q)?.hex ?? "9AA6B6", age: FreezerLog.age(q.name),
                                  help: [q.name, q.detail ?? "", detail].filter { !$0.isEmpty }.joined(separator: "\n"))
            }
        } else {
            list = store.library.primaries.map { p in
                let host = host(ofPrimary: p) ?? ""
                let detail = [p.company, p.cat].filter { !$0.isEmpty }.joined(separator: " · ")
                return FridgeTube(id: p.id, regKey: Registry.key(p.cat, p.name), label: markerName(p.name), detail: detail, dilution: p.dilution > 0 ? "1:\(fmtNum(p.dilution))" : "1:?",
                                  capHex: hostCapHex[host] ?? "9AA6B6", age: FreezerLog.age(p.name),
                                  help: [p.name, detail, p.rrid.map { "RRID " + $0 } ?? ""].filter { !$0.isEmpty }.joined(separator: "\n"))
            }
        }
        return list.sorted { $0.age < $1.age }     // the ones used lately at the front
    }

    private var cardIndex: Int? { store.exp.sets.firstIndex { $0.id == setID } }

    /// Every tube with a catalogue number checked against the manufacturer's record.
    private func checkAll(force: Bool) {
        if secondaries { store.library.secondaries.forEach { Registry.shared.check(secondary: $0, force: force) } }
        else { store.library.primaries.forEach { Registry.shared.check(primary: $0, force: force) } }
    }

    /// The tube being typed in, as an antibody, so it can be checked as you type.
    private var draftPrimary: Antibody {
        Antibody(name: fName.wrappedValue, company: fCompany.wrappedValue, cat: fCat.wrappedValue, dilution: 0, rrid: nil)
    }
    private var draftSecondary: Secondary {
        Secondary(name: fName.wrappedValue, dilution: 0, detail: fProduct.wrappedValue, company: fCompany.wrappedValue, cat: fCat.wrappedValue)
    }
    private var draftKey: String { Registry.key(fCat.wrappedValue, fName.wrappedValue) }

    /// Fills the form from the manufacturer's record.
    private func use(_ r: RegistryRecord) {
        let firstCat = r.catalogNum.components(separatedBy: CharacterSet(charactersIn: " ,(")).first ?? r.catalogNum
        fCat.wrappedValue = firstCat
        fCompany.wrappedValue = r.vendorName
        fRRID.wrappedValue = r.rrid
        if secondaries { fProduct.wrappedValue = r.abName }
    }

    private func take(_ id: UUID) {
        guard let k = cardIndex else { return }
        if secondaries, let q = store.library.secondaries.first(where: { $0.id == id }) {
            var n = q; n.id = UUID(); DyeFlash.added(n); store.exp.sets[k].secondaries.append(n); FreezerLog.touch([q.name])
        } else if let p = store.library.primaries.first(where: { $0.id == id }) {
            var n = p; n.id = UUID(); store.exp.sets[k].primaries.append(n); FreezerLog.touch([p.name])
        }
        if motion { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { lifted.wrappedValue = id } }
        close()
    }

    private func remove(_ id: UUID) {
        if secondaries { store.library.secondaries.removeAll { $0.id == id } } else { store.library.primaries.removeAll { $0.id == id } }
    }

    private func emptyRow() {
        guard let k = cardIndex else { return }
        if secondaries { store.exp.sets[k].secondaries.append(Secondary()) } else { store.exp.sets[k].primaries.append(Antibody()) }
        close()
    }

    /// Puts the new tube in the fridge (and on the card).
    private func addNew(toCard: Bool) {
        let name = fName.wrappedValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let dil = Double(fDilution.wrappedValue.replacingOccurrences(of: "1:", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
        func opt(_ s: String) -> String? { let t = s.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t }
        if secondaries {
            let q = Secondary(name: name, dilution: dil, detail: opt(fProduct.wrappedValue), company: opt(fCompany.wrappedValue),
                              cat: opt(fCat.wrappedValue), rrid: opt(fRRID.wrappedValue))
            store.library.secondaries.removeAll { $0.name == name }
            store.library.secondaries.append(q)
            if toCard, let k = cardIndex { var n = q; n.id = UUID(); DyeFlash.added(n); store.exp.sets[k].secondaries.append(n) }
        } else {
            let p = Antibody(name: name, company: fCompany.wrappedValue.trimmingCharacters(in: .whitespaces),
                             cat: fCat.wrappedValue.trimmingCharacters(in: .whitespaces), dilution: dil, rrid: opt(fRRID.wrappedValue))
            store.library.primaries.removeAll { $0.name == name }
            store.library.primaries.append(p)
            if toCard, let k = cardIndex { var n = p; n.id = UUID(); store.exp.sets[k].primaries.append(n) }
        }
        FreezerLog.touch([name])
        if secondaries { Registry.shared.check(secondary: draftSecondary) } else { Registry.shared.check(primary: draftPrimary) }
        for f in [fName, fCompany, fCat, fDilution, fRRID, fProduct] { f.wrappedValue = "" }
        showForm.wrappedValue = false
        if toCard { close() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "refrigerator").foregroundColor(Color(hex: "9BD2FF"))
                Text(secondaries ? "Secondaries & counterstains · 4 °C" : "Primary antibodies · 4 °C").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                Spacer()
                Text("\(tubes.count) tube\(tubes.count == 1 ? "" : "s")").font(.system(size: 11)).foregroundColor(Color(hex: "9FB7D6"))
            }
            if tubes.isEmpty {
                Text("The fridge is empty: add a tube below.").font(.system(size: 11)).foregroundColor(Color(hex: "9FB7D6"))
                    .frame(width: 400, alignment: .leading)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 6), count: 6), spacing: 8) {
                        ForEach(Array(tubes.enumerated()), id: \.element.id) { k, t in
                            tube(t)
                                .offset(y: opened.wrappedValue ? 0 : 18)
                                .opacity(opened.wrappedValue ? 1 : 0)
                                .animation(motion ? .spring(response: 0.7, dampingFraction: 0.82).delay(1.0 + Double(min(k, 17)) * 0.05) : nil,
                                           value: opened.wrappedValue)
                        }
                    }
                    .padding(10)
                }
                .frame(width: 430, height: min(330, CGFloat((tubes.count + 5) / 6) * 104 + 20))
                .background(
                    // the fridge shelf, lit from above
                    RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [Color(hex: "22364F"), Color(hex: "17263A")], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                )
                // the door swings open and a puff of cold mist rolls out
                .overlay(FridgeDoor(motion: motion).allowsHitTesting(false))
            }
            if !secondaries {
                HStack(spacing: 10) {
                    ForEach(["rabbit", "goat", "mouse", "rat", "sheep"], id: \.self) { h in
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: hostCapHex[h]!)).frame(width: 8, height: 8)
                            Text(h).font(.system(size: 10)).foregroundColor(Color(hex: "9FB7D6"))
                        }
                    }
                }
            }
            Text("Click a tube to add it · right-click to take it out of the fridge · grey and faint: not used for weeks")
                .font(.system(size: 10)).foregroundColor(Color(hex: "6F87A8"))
            HStack(spacing: 8) {
                let checked = tubes.compactMap { registry.result($0.regKey) }
                let ok = checked.filter { if case .verified = $0.status { return true }; return false }.count
                let bad = checked.filter { switch $0.status { case .mismatch: return true; case .notFound(let near): return near != nil; default: return false } }.count
                Image(systemName: "checkmark.seal").foregroundColor(Color(hex: "3BB36A"))
                Text("Manufacturer check: \(ok) match\(bad > 0 ? " · \(bad) to look at" : "") · \(tubes.count - checked.count) without a Cat#")
                    .font(.system(size: 10.5)).foregroundColor(Color(hex: "BFE3FF"))
                Spacer()
                Button("Check all again") { checkAll(force: true) }
                    .buttonStyle(.borderless).font(.system(size: 10.5, weight: .semibold)).foregroundColor(Color(hex: "BFE3FF"))
                    .help("Ask the Antibody Registry again for every tube with a catalogue number")
            }
            Divider().overlay(Color.white.opacity(0.15))
            if showForm.wrappedValue { form } else {
                HStack(spacing: 12) {
                    Button { showForm.wrappedValue = true } label: { Label("New tube…", systemImage: "plus.circle.fill") }
                    Button { emptyRow() } label: { Label("Empty row on the card", systemImage: "text.badge.plus") }
                }
                .buttonStyle(.borderless)
                .foregroundColor(Color(hex: "BFE3FF"))
                .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(14)
        .frame(width: 458)
        .background(LinearGradient(colors: [Color(hex: "0E1B2C"), Color(hex: "142740")], startPoint: .top, endPoint: .bottom))
        .onAppear {
            checkAll(force: false)
            opened.wrappedValue = true
        }
    }

    /// A new tube: its name and what the lab records about it.
    private var form: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New tube").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
            field(secondaries ? "Name, e.g. 488 rab" : "Name with host, e.g. LMX1A/B (rab)", fName)
            if secondaries {
                HStack { field("Dilution, e.g. 500", fDilution); field("Cat#", fCat) }
                field("Product, e.g. Donkey anti-Rabbit IgG, Alexa Fluor 488", fProduct)
                HStack { field("Company", fCompany); field("RRID", fRRID) }
            } else {
                HStack { field("Company", fCompany); field("Cat#", fCat) }
                HStack { field("Dilution, e.g. 1000", fDilution); field("RRID", fRRID) }
            }
            // the manufacturer's record, looked up as you type the catalogue number
            RegistryLine(result: registry.result(draftKey)) { rec in use(rec) }
                .task(id: draftKey + fCompany.wrappedValue) {
                    guard catKey(fCat.wrappedValue).count >= 3 else { return }
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    guard !Task.isCancelled else { return }
                    if secondaries { Registry.shared.check(secondary: draftSecondary) } else { Registry.shared.check(primary: draftPrimary) }
                }
            HStack {
                Button("Cancel") { showForm.wrappedValue = false }
                Spacer()
                Button("Put in the fridge") { addNew(toCard: false) }
                Button("Add to fridge and card") { addNew(toCard: true) }
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(false)
            .padding(.top, 2)
        }
        .textFieldStyle(.roundedBorder)
    }

    private func field(_ hint: String, _ v: State<String>) -> some View {
        TextField(hint, text: v.projectedValue).font(.system(size: 12))
    }

    private func tube(_ t: FridgeTube) -> some View {
        let up = lifted.wrappedValue == t.id
        // the longer a tube has sat unused, the greyer and fainter it gets: a month or more is a ghost
        let fade = max(0, min(1, (t.age - 0.15) / 0.7))
        return Button { take(t.id) } label: {
            VStack(spacing: 2) {
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: t.capHex)).frame(width: 26, height: 10)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                    TubeShape()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.9), Color(hex: "DDE8F3").opacity(0.75)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 22, height: 32)
                        .overlay(alignment: .bottom) {
                            TubeShape().fill(Color(hex: t.capHex).opacity(0.35)).frame(width: 20, height: 11).padding(.bottom, 1)
                        }
                }
                Text(t.label).font(.system(size: 9.5, weight: .bold)).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
                Text(t.dilution).font(.system(size: 8.5, weight: .semibold).monospacedDigit()).foregroundColor(Color(hex: "BFE3FF"))
                Text(t.detail.isEmpty ? " " : t.detail).font(.system(size: 7.5)).foregroundColor(Color(hex: "8FA7C6")).lineLimit(2)
                    .multilineTextAlignment(.center).minimumScaleFactor(0.7)
            }
            .frame(width: 64, height: 96)
            .saturation(1 - fade)
            .opacity(up ? 0 : 1 - 0.68 * fade)
            .overlay(alignment: .topTrailing) {
                if fade > 0.5 {
                    Text("unused").font(.system(size: 7, weight: .heavy)).tracking(0.3)
                        .foregroundColor(Color(hex: "0E1B2C"))
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Capsule().fill(Color(hex: "9FB7D6")))
                        .offset(x: -2, y: 2)
                }
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
            .overlay(alignment: .topLeading) { RegistryBadge(result: registry.result(t.regKey)).offset(x: 2, y: 2) }
            .offset(y: up ? -18 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(t.help)
        .contextMenu {
            Button("Add to the card") { take(t.id) }
            Divider()
            Button("Take out of the fridge", role: .destructive) { remove(t.id) }
        }
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
                // none before Day 0: a sample planned for later (or fixed before its Day 0) made this negative,
                // and a negative count crashed the app
                let grown = max(0, min(14, 1 + days(day0, min(today, fixed ?? today)) / 3))
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
    /// One small glow layer per stained well, the picture shared by every well of a colour: painting
    /// adds or removes a layer instead of redrawing the whole plate's glow.
    private var glows: [Int: (CALayer, String)] = [:]
    private var cw: CGFloat = 48, ch: CGFloat = 44
    private static var images: [String: CGImage?] = [:]
    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        layer?.isGeometryFlipped = false
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private static func glow(_ hex: String, _ size: CGSize) -> CGImage? {
        let key = hex + "\(Int(size.width))"
        if let i = images[key] { return i }
        let i = renderImage(size, screenScale) { c in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let ctr = CGPoint(x: size.width / 2, y: size.height / 2)
            if let g = CGGradient(colorsSpace: space, colors: [cg(hex, 0.7), cg(hex, 0)] as CFArray, locations: [0, 1]) {
                c.drawRadialGradient(g, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: size.width / 2, options: [])
            }
        }
        images[key] = i
        return i
    }

    func show(_ wells: [(Int, String)], cw: CGFloat, ch: CGFloat) {
        let want = Dictionary(wells.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for (w, (l, hex)) in glows where want[w] != hex { l.removeFromSuperlayer(); glows[w] = nil }
        self.cw = cw; self.ch = ch
        let size = CGSize(width: cw * 1.7, height: cw * 1.7)
        for (w, hex) in want where glows[w] == nil {
            let l = CALayer()
            l.contents = Self.glow(hex, size)
            layer?.addSublayer(l)
            glows[w] = (l, hex)
        }
        place()
    }

    /// The view is 8 pt larger than the grid on every side; layer coordinates run upwards.
    private func place() {
        let size = CGSize(width: cw * 1.7, height: cw * 1.7)
        let H = bounds.height
        for (w, (l, _)) in glows {
            let cx = 8 + (CGFloat(w % 12) + 0.5) * cw, cy = 8 + (CGFloat(w / 12) + 0.5) * ch
            l.frame = CGRect(x: cx - size.width / 2, y: H - cy - size.height / 2, width: size.width, height: size.height)
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        place()
        CATransaction.commit()
    }
}

// MARK: Sounds

/// Soft sounds made in code (no audio files): a pipette click, the confocal's hum, and a chime when the
/// export is done. Off unless switched on in the File menu.
enum Sounds {
    static var on = UserDefaults.standard.bool(forKey: "sounds")
    private static var lastClick = Date.distantPast
    // The click and the chime go through the system-sound player, which plays without blocking: NSSound's
    // stop() and play() on every painted well held up painting.
    private static let clickID: SystemSoundID? = systemSound("click", seconds: 0.05) { t in
        let env = exp(-t * 90)
        return (sin(2 * .pi * 2300 * t) * 0.35 + Double.random(in: -1...1) * 0.25) * env * 0.35
    }
    private static let chimeID: SystemSoundID? = systemSound("chime", seconds: 1.2) { t in
        let a = sin(2 * .pi * 1318.5 * t) * exp(-t * 3.2)
        let b = t > 0.12 ? sin(2 * .pi * 1975.5 * (t - 0.12)) * exp(-(t - 0.12) * 3.0) : 0
        return (a * 0.5 + b * 0.45) * 0.28
    }
    /// The lid settling onto the plate: a soft plastic clack.
    private static let lidID: SystemSoundID? = systemSound("lid", seconds: 0.12) { t in
        (sin(2 * .pi * 180 * t) * exp(-t * 55) * 0.6 + sin(2 * .pi * 1400 * t) * exp(-t * 140) * 0.3
            + Double.random(in: -1...1) * exp(-t * 220) * 0.2) * 0.5
    }
    /// The aspirator drawing a well up: a short rising slurp.
    private static let aspirateID: SystemSoundID? = {
        var lp = 0.0
        return systemSound("aspirate", seconds: 0.18) { t in
            lp += (Double.random(in: -1...1) - lp) * 0.25
            return (lp * 0.5 + sin(2 * .pi * (420 + 1800 * t) * t) * 0.12) * sin(.pi * t / 0.18) * 0.4
        }
    }()
    /// Buffer washing over the plate: a soft whoosh.
    private static let washID: SystemSoundID? = {
        var lp = 0.0
        return systemSound("wash", seconds: 0.95) { t in
            lp += (Double.random(in: -1...1) - lp) * 0.06
            let env = pow(sin(.pi * t / 0.95), 2)
            return lp * env * 0.9
        }
    }()
    /// A secondary antibody taking hold of its primary: a tiny snap.
    private static let snapID: SystemSoundID? = systemSound("snap", seconds: 0.04) { t in
        sin(2 * .pi * 3200 * t) * exp(-t * 240) * 0.28
    }
    /// The hum: an audio player loaded and primed ahead of time (NSSound's play() took ~110 ms to start).
    private static let hum: AVAudioPlayer? = {
        let data = wav(seconds: 2.0) { t in
            // a low, steady scanner hum with a slow shimmer; whole cycles so the loop is seamless
            (sin(2 * .pi * 110 * t) * 0.5 + sin(2 * .pi * 220 * t) * 0.25 + sin(2 * .pi * 330 * t) * 0.08)
                * (0.85 + 0.15 * sin(2 * .pi * 2 * t)) * 0.12
        }
        guard let data, let p = try? AVAudioPlayer(data: data) else { return nil }
        p.numberOfLoops = -1
        p.prepareToPlay()
        return p
    }()

    /// Development: each sound is made and plays.
    static func selfTest() {
        on = true
        print("click", clickID != nil ? "made" : "could not be made")
        print("chime", chimeID != nil ? "made" : "could not be made")
        for (name, id) in [("lid", lidID), ("aspirate", aspirateID), ("wash", washID), ("snap", snapID)] {
            print(name, id != nil ? "made" : "could not be made")
        }
        _ = hum
        let h0 = Date()
        scanning(true)
        print(String(format: "hum plays: %@, starting it took %.1f ms", hum?.isPlaying == true ? "yes" : "no", Date().timeIntervalSince(h0) * 1000))
        let s0 = Date()
        scanning(false)
        print(String(format: "stopping it took %.1f ms", Date().timeIntervalSince(s0) * 1000))
        let t0 = Date()
        for _ in 0..<20 { lastClick = .distantPast; pipette() }
        print(String(format: "20 clicks took %.1f ms on the main thread", Date().timeIntervalSince(t0) * 1000))
    }

    /// Makes the sounds in the background, so none is built at the moment it should play.
    static func prewarm() {
        guard on else { return }
        DispatchQueue.global(qos: .utility).async { _ = clickID; _ = chimeID; _ = hum; _ = lidID; _ = aspirateID; _ = washID; _ = snapID }
    }

    static func pipette() {
        guard on, Date().timeIntervalSince(lastClick) > 0.045, let id = clickID else { return }
        lastClick = Date()
        AudioServicesPlaySystemSound(id)
    }
    static func done() { guard on, let id = chimeID else { return }; AudioServicesPlaySystemSound(id) }
    static func lid() { guard on, let id = lidID else { return }; AudioServicesPlaySystemSound(id) }
    static func wash() { guard on, let id = washID else { return }; AudioServicesPlaySystemSound(id) }
    static func snap() { guard on, let id = snapID else { return }; AudioServicesPlaySystemSound(id) }
    static func aspirate() {
        guard on, Date().timeIntervalSince(lastClick) > 0.045, let id = aspirateID else { return }
        lastClick = Date()
        AudioServicesPlaySystemSound(id)
    }
    static func scanning(_ yes: Bool) {
        guard let h = hum else { return }
        if yes && on {
            h.currentTime = 0
            h.volume = 0
            h.play()
            h.setVolume(0.9, fadeDuration: 0.4)
        } else if h.isPlaying {
            h.setVolume(0, fadeDuration: 0.3)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { if h.volume == 0 { h.pause(); h.prepareToPlay() } }
        }
    }

    /// A sound written once to a temporary WAV and registered with the system-sound player.
    private static func systemSound(_ name: String, seconds: Double, _ f: (Double) -> Double) -> SystemSoundID? {
        guard let data = wav(seconds: seconds, f) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("iccplanner-\(name).wav")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        var id: SystemSoundID = 0
        return AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr ? id : nil
    }

    /// A mono 16-bit WAV of `seconds`, sample by sample.
    private static func wav(seconds: Double, _ f: (Double) -> Double) -> Data? {
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
        return wav
    }
}


