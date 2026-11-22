import SwiftUI
import AppKit

// MARK: - Brand

enum Brand {
    static let appName = "ICC Plate Planner"
    static let department = "Department of Regenerative Medicine Research"
    static let hospital = "Kobe City Medical Center General Hospital"
    static let author = "Joey Russell"

    // Palette taken from the department's slide banner: navy -> blue -> pale blue-white.
    // In the microscope room (Theme.dark) the same roles take night colours.
    static var navy: Color { Color(hex: Theme.dark ? "8DB8F2" : "1E4A83") }
    static var mid: Color { Color(hex: Theme.dark ? "6E9BDC" : "4A78B8") }
    static var pale: Color { Color(hex: Theme.dark ? "16233A" : "E8EEF6") }
    static var rule: Color { Color(hex: Theme.dark ? "2A3A52" : "D5DEEB") }
    static var ink: Color { Color(hex: Theme.dark ? "E3EBF6" : "172033") }
    /// Card and page surfaces.
    static var card: Color { Theme.dark ? Color(hex: "111B2B") : .white }
    static var page: Color { Color(hex: Theme.dark ? "0A1220" : "F7F9FC") }
    static var gradient: LinearGradient {
        Theme.dark
            ? LinearGradient(stops: [.init(color: Color(hex: "08111F"), location: 0), .init(color: Color(hex: "13294A"), location: 0.6), .init(color: Color(hex: "1B3A66"), location: 1)],
                             startPoint: .leading, endPoint: .trailing)
            : LinearGradient(stops: [.init(color: Color(hex: "1E4A83"), location: 0), .init(color: Color(hex: "4A78B8"), location: 0.5), .init(color: Color(hex: "E8EEF6"), location: 1)],
                             startPoint: .leading, endPoint: .trailing)
    }

    /// Department logo shipped inside the app bundle (the same image used on the slide banner).
    static let logo: NSImage? = Bundle.main.url(forResource: "DeptLogo", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
}

/// Small navy square + letter-spaced serif capitals, like the eyebrow line on the department's slides.
struct Eyebrow: View {
    let text: String
    var color: Color = Brand.navy
    var size: CGFloat = 10
    var body: some View {
        HStack(spacing: 7) {
            Rectangle().fill(color).frame(width: size * 0.8, height: size * 0.8)
            Text(text.uppercased()).font(.system(size: size, weight: .bold, design: .serif)).tracking(size * 0.2).foregroundColor(color)
        }
    }
}

/// Stronger companion colours for the default pastel fills (outline, dots, accents in the app only).
private let setAccents = ["5FA046", "E0A100", "4A8FD0", "E0742B", "8565B0", "8A8A8A", "D9694B", "6FAE4F"]

func setFill(_ set: StainSet, _ i: Int) -> Color { Color(hex: fillHex(set, i)) }

func setAccent(_ set: StainSet, _ i: Int) -> Color {
    guard let custom = set.colorHex else { return Color(hex: setAccents[i % setAccents.count]) }
    // derive an outline from a custom colour: same hue, more saturated, a little darker
    let c = NSColor(Color(hex: custom)).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    var h: CGFloat = 0, sat: CGFloat = 0, br: CGFloat = 0, al: CGFloat = 0
    c.getHue(&h, saturation: &sat, brightness: &br, alpha: &al)
    return Color(hue: Double(h), saturation: Double(sat < 0.05 ? sat : max(sat, 0.55)), brightness: Double(min(br, 0.72)))
}

func hexString(_ color: Color) -> String {
    let c = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    return String(format: "%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
}

/// Ready-made well colours offered next to the free colour picker.
let wellColorPresets: [(String, String)] = [
    ("Green", "E2EFDA"), ("Gold", "FFF2CC"), ("Blue", "DDEBF7"), ("Orange", "FCE4D6"), ("Purple", "E4DFEC"),
    ("Pink", "FAD7E4"), ("Teal", "CFEFEA"), ("Red", "F4B6B0"), ("Grey", "EDEDED"),
]

extension Color {
    init(hex: String) {
        let v = UInt32(hex, radix: 16) ?? 0xCCCCCC
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

private let plain = FloatingPointFormatStyle<Double>.number.grouping(.never)

extension Binding where Value == String? {
    /// An optional text as a plain field: empty when missing, and missing again when emptied.
    var orEmpty: Binding<String> {
        Binding<String>(get: { wrappedValue ?? "" },
                        set: { new in wrappedValue = new.trimmingCharacters(in: .whitespaces).isEmpty ? nil : new })
    }
}

extension Binding where Value: MutableCollection, Value.Element: Identifiable {
    /// A binding to one row that is looked up by id every time it is read or written. A row that has
    /// just been deleted can therefore never be reached through a stale index.
    func row(_ element: Value.Element) -> Binding<Value.Element> {
        Binding<Value.Element>(
            get: { wrappedValue.first(where: { $0.id == element.id }) ?? element },
            set: { new in
                if let i = wrappedValue.firstIndex(where: { $0.id == element.id }) { wrappedValue[i] = new }
            })
    }
}

// MARK: - Building blocks

struct CardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Brand.card)
            .shadow(color: Brand.navy.opacity(0.10), radius: 7, x: 0, y: 2)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Brand.rule, lineWidth: 1))
    }
}

struct Card<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Rectangle().fill(Brand.navy).frame(width: 9, height: 9)
                Text(title).font(.system(size: 18, weight: .bold, design: .serif)).foregroundColor(Brand.ink)
                Spacer()
                Image(systemName: icon).font(.system(size: 15, weight: .light)).foregroundColor(Brand.mid)
            }
            Rectangle().fill(Brand.rule).frame(height: 1)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground())
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var roll = false
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
            .rolling(text, roll)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().stroke(color.opacity(0.55), lineWidth: 0.75))
    }
}

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar().overlay(LightsDim())
            OutputStrip().overlay(LightsDim())
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ExperimentSection()
                        ForEach(Array(store.exp.sets.enumerated()), id: \.element.id) { idx, set in
                            StainCard(setID: set.id, index: idx)
                                .transition(.asymmetric(insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity), removal: .opacity))
                        }
                        Button { store.addSet() } label: {
                            Label("Add stain set", systemImage: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Brand.mid.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
                                .foregroundColor(Brand.navy)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(SquishStyle(on: store.motion))
                        BlockingSection()
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .animation(store.animations ? .spring(response: 0.42, dampingFraction: 0.82) : nil, value: store.exp.sets.map { $0.id })
                }
                .frame(width: 580)
                .overlay(LightsDim())
                GeometryReader { geo in
                    ScrollView([.vertical, .horizontal]) {
                        VStack(alignment: .leading, spacing: 14) {
                            PlateSection()
                                .zIndex(1)      // the hologram floats over the cards below
                            SummarySection().overlay(LightsDim())
                        }
                        .frame(width: max(geo.size.width - 16, 712))   // never narrower than the plate
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 16).padding(.trailing, 16)
                    }
                }
            }
        }
        .background(
            LinearGradient(colors: [Brand.pale.opacity(0.75), Brand.page], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .top) {
            ZStack {
                if let toast = store.toast {
                    ToastView(toast: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .id(toast.id)
                }
            }
            .padding(.top, 124)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: store.toast?.id)
            .allowsHitTesting(false)
        }
        .overlay(FxOverlay(store: store).allowsHitTesting(false))
        .task { store.arrangeSoon() }          // cards saved before secondaries were kept in order line up too
        .overlay(ConfettiLayer())
        .tint(Brand.navy)
        .preferredColorScheme(store.darkRoom ? .dark : .light)   // a white page with navy accents, or the microscope room
        // switching the room rebuilds every view, so none keeps the old colours (views whose inputs did not
        // change were not redrawn, which left white cards with light text)
        .id(store.darkRoom)
    }
}

/// The department banner: navy fading to pale blue, logo on the right.
struct HeaderBar: View {
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: Brand.department, color: .white.opacity(0.95), size: 10.5)
                Text(Brand.appName)
                    .font(.system(size: 27, weight: .bold, design: .serif))
                    .foregroundColor(.white)
            }
            .fixedSize()
            HelixLane(active: store.ambient)
                .frame(minWidth: 0, maxWidth: 280).frame(height: 46)
                .padding(.horizontal, 6)
                .layoutPriority(-1)
            Spacer(minLength: 0)
            FunButton(action: { store.openPlate() }) {
                Label("Open", systemImage: "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Brand.navy)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Brand.card))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Brand.navy.opacity(0.35), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .help("Load a plate you saved earlier (⌘O) — your current plate stays one ⌘Z away")
            FunButton(action: { store.savePlate() }) {
                Label("Save", systemImage: "square.and.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Brand.navy)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Brand.card))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Brand.navy.opacity(0.35), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .help("Save this plate to load again later (⌘S)")
            FunButton(action: { store.confirmNew() }) {
                Label("New", systemImage: "plus.rectangle.on.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Brand.navy)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Brand.card))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Brand.navy.opacity(0.35), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .help("Start a new experiment (keeps your antibody panels)")
            FunButton(action: { store.export() }) {
                Label("Export Excel", systemImage: "arrow.down.doc")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Brand.navy))
                    .shadow(color: Brand.navy.opacity(0.35), radius: 4, y: 2)
                    .contentShape(Rectangle())
            }
            .help("Save the staining workbook (⌘E)")
            if let logo = Brand.logo {
                Image(nsImage: logo).resizable().interpolation(.high)
                    .aspectRatio(contentMode: .fit).frame(height: 44)
                    .padding(.leading, 10)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 80)
        .background(Brand.gradient)
    }
}

/// Thin strip under the banner: the file that will be written. The box takes your own name when the
/// automatic one (date + every sample number) gets too long; the name that will actually be used is
/// shown next to it, so you can see the effect as you type.
struct OutputStrip: View {
    @EnvironmentObject var store: Store

    private var customBinding: Binding<String> {
        Binding(
            get: { store.exp.customTitle },
            set: {
                let t = String($0.prefix(80))
                // a name that is only spaces would look empty but hide the placeholder — treat it as empty
                store.exp.customTitle = t.trimmingCharacters(in: .whitespaces).isEmpty ? "" : t
            })
    }

    var body: some View {
        let hasCustom = !store.exp.customTitle.trimmingCharacters(in: .whitespaces).isEmpty
        HStack(spacing: 10) {
            Eyebrow(text: "Output file")
            TextField("Custom name (optional)", text: customBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(Brand.ink)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .frame(width: 190)
                .background(RoundedRectangle(cornerRadius: 5).fill(hasCustom ? Brand.pale : Color(nsColor: .textBackgroundColor).opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Brand.rule, lineWidth: 1))
                .help("Type your own file name if the automatic one is too long; leave it empty for automatic")
            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary)
            Text(store.exp.fileName)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(hasCustom ? Brand.navy : .secondary)
                .lineLimit(1).truncationMode(.middle)
                .help(hasCustom ? "Your custom name will be used" : "Automatic name: date + sample numbers")
            if hasCustom {
                Button("Auto") {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    store.exp.customTitle = ""
                }
                .buttonStyle(.borderless).font(.caption).foregroundColor(Brand.navy)
                .help("Back to the automatic name (date + sample numbers)")
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 34)
        .background(Brand.card)
        .overlay(Rectangle().fill(Brand.rule).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Left column

struct ExperimentSection: View {
    @EnvironmentObject var store: Store

    /// The fixed-date picker shows the automatic date until another one is chosen; choosing the
    /// automatic date again keeps it automatic, so it goes on following Day 0.
    private func fixedBinding(_ b: Binding<Sample>) -> Binding<Date> {
        Binding(
            get: { store.exp.fixedDate(b.wrappedValue, store.settings) ?? Date() },
            set: { picked in
                let new = fixCentury(picked)
                let auto = store.exp.autoFixedDate(b.wrappedValue, store.settings)
                let isAuto = auto.map { Calendar.current.isDate($0, inSameDayAs: new) } ?? false
                b.wrappedValue.fixed = isAuto ? nil : new
            })
    }

    var body: some View {
        Card(title: "Experiment", icon: "calendar") {
            HStack(spacing: 8) {
                Text("Staining date")
                LiteDateField(date: Binding(get: { store.exp.date }, set: { store.exp.date = fixCentury($0) }))
            }
            Eyebrow(text: "Samples · Day 0, date fixed and Day", color: Brand.mid, size: 9.5)
            ForEach(store.exp.samples) { s in
                let b = $store.exp.samples.row(s)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("#380", text: b.code).frame(width: 80)
                        TextField("Name, e.g. Large Scale", text: b.name)
                        Button {
                            store.removeSample(s.id)
                        } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.tertiary) }
                            .buttonStyle(SquishStyle(on: store.motion))
                            .disabled(store.exp.samples.count <= 1)
                    }
                    HStack(spacing: 8) {
                        Toggle("Day 0", isOn: b.hasDay0).font(.system(size: 12))
                        LiteDateField(date: Binding(get: { b.wrappedValue.day0 }, set: { b.wrappedValue.day0 = fixCentury($0) }), enabled: s.hasDay0)
                        Text("Fixed").font(.system(size: 12)).padding(.leading, 8)
                        LiteDateField(date: fixedBinding(b), enabled: s.hasDay0)
                        if s.hasDay0 {
                            if s.fixed == nil {
                                Pill(text: "AUTO", color: Brand.navy)
                                    .help("Day 0 + \(fmtNum(store.settings.fixDay)) days. Pick a date to set your own.")
                            } else {
                                Button("Auto") { b.wrappedValue.fixed = nil }
                                    .buttonStyle(.borderless).font(.caption).foregroundColor(Brand.navy)
                                    .help("Go back to Day 0 + \(fmtNum(store.settings.fixDay)) days")
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 4)
                    HStack(spacing: 8) {
                        Text("Day").font(.system(size: 12))
                        // empty = automatic (date fixed minus Day 0), shown in grey; type to set your own
                        TextField(store.exp.dayText(Sample(hasDay0: s.hasDay0, day0: s.day0, fixed: s.fixed), store.settings), text: b.day)
                            .frame(width: 52)
                        if s.hasDay0 {
                            if s.day.trimmingCharacters(in: .whitespaces).isEmpty {
                                Pill(text: "AUTO", color: Brand.navy)
                                    .help("Date fixed minus Day 0. Type a number to set your own.")
                            } else {
                                Button("Auto") { b.wrappedValue.day = "" }
                                    .buttonStyle(.borderless).font(.caption).foregroundColor(Brand.navy)
                                    .help("Go back to the automatic Day")
                            }
                        }
                        if let d = store.exp.daysSinceDay0(s) {
                            Text("staining date = day \(d)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 4)
                    if s.hasDay0 {
                        SampleTimeline(day0: s.day0, fixed: store.exp.fixedDate(s, store.settings), staining: store.exp.date)
                            .padding(.leading, 4).padding(.top, 2)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.pale.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Brand.rule, lineWidth: 1))
            }
            Button { store.addSample() } label: { Label("Add sample", systemImage: "plus") }
                .buttonStyle(.borderless).foregroundColor(Brand.navy)
        }
        .textFieldStyle(.roundedBorder)
    }
}

struct StainCard: View {
    @EnvironmentObject var store: Store
    let setID: UUID
    let index: Int

    private var binding: Binding<StainSet> {
        Binding(
            get: { store.exp.sets.first { $0.id == setID } ?? StainSet(id: setID) },
            set: { new in
                if let i = store.exp.sets.firstIndex(where: { $0.id == setID }) { store.exp.sets[i] = new }
            })
    }

    private func spotlight(_ inside: Bool) {
        if inside { store.spotlightSet = setID } else if store.spotlightSet == setID { store.spotlightSet = nil }
    }

    private func columnHeader(_ tag: String, _ cols: [(String, CGFloat?)]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(cols.enumerated()), id: \.offset) { _, c in
                if let w = c.1 { Text(c.0).frame(width: w, alignment: .leading) }
                else { Text(c.0).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
        .font(.system(size: 9.5, weight: .bold, design: .serif)).tracking(1.2).foregroundColor(Brand.mid)
        .overlay(alignment: .topLeading) { EmptyView() }
        .padding(.top, 2)
        .accessibilityLabel(tag)
    }

    var body: some View {
        let set = binding.wrappedValue
        let vol = store.exp.volume(set, store.settings)
        let auto = store.exp.autoVolume(set, store.settings)
        let accent = setAccent(set, index)
        let report = panel(set, library: store.library)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ColorPicker("", selection: Binding(
                    get: { setFill(binding.wrappedValue, index) },
                    set: { binding.wrappedValue.colorHex = hexString($0) }), supportsOpacity: false)
                    .labelsHidden()
                    .help("Choose any colour for this stain's wells")
                Text("Stain \(index + 1)").font(.system(size: 18, weight: .bold, design: .serif)).foregroundColor(Brand.ink)
                VerdictIcon(verdict: report.verdict, why: report.summary, size: 16)
                    .animation(store.motion ? .spring(response: 0.35, dampingFraction: 0.55) : nil, value: report.verdict)
                Pill(text: "\(store.exp.wellCount(set)) wells", color: accent, roll: store.motion)
                    .onHover { inside in spotlight(inside) }
                    .help("Rest the pointer here to see this stain's wells on the plate")
                Menu {
                    ForEach(wellColorPresets, id: \.1) { preset in
                        Button(preset.0) { binding.wrappedValue.colorHex = preset.1 }
                    }
                    Divider()
                    Button("Default colour") { binding.wrappedValue.colorHex = nil }
                } label: { Image(systemName: "paintpalette") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Quick colours for this stain's wells")
                Spacer()
                MixTube(dyes: report.channels.map { $0.fluor.hex },
                        level: CGFloat(min(1, vol / 1500)) * 0.75 + 0.15,
                        key: "\(vol)|" + set.primaries.map { "\($0.dilution)" }.joined(separator: ",") + "|"
                            + set.secondaries.map { "\($0.name):\($0.dilution)" }.joined(separator: ","),
                        motion: store.motion, alive: store.ambient)
                    .frame(width: 16, height: 32)
                    .help("This stain's mix: blocking buffer with its antibodies and dyes")
                Text("Volume").foregroundStyle(.secondary)
                TextField(fmtNum(auto), value: binding.volumeOverride, format: plain)
                    .frame(width: 66)
                    .help("Leave empty to use (wells + extra) × µL per well = \(fmtNum(auto)) µL")
                Text("µL").foregroundStyle(.secondary)
                Button { store.duplicateSet(setID) } label: { Image(systemName: "plus.square.on.square").foregroundStyle(.secondary) }
                    .buttonStyle(SquishStyle(on: store.motion))
                    .help("Duplicate this stain set (same antibodies, ready to tweak)")
                Button { store.removeSet(setID) } label: { Image(systemName: "trash").foregroundStyle(.secondary) }
                    .buttonStyle(SquishStyle(on: store.motion))
                    .help("Remove this stain set")
            }

            columnHeader("1st", [("", 15), ("1ST · ANTIBODY", nil), ("COMPANY", 110), ("CAT#", 74), ("DILUTION", 76), ("ADD", 58), ("", 16)])
            ForEach(set.primaries) { ab in
                let b = binding.primaries.row(ab)
                HStack(spacing: 6) {
                    let v = report.verdict(primary: ab.id)
                    VerdictIcon(verdict: v.0, why: v.1, size: 13).frame(width: 15)
                        .animation(store.motion ? .spring(response: 0.35, dampingFraction: 0.55) : nil, value: v.0)
                    TextField("Antibody (host)", text: b.name)
                    TextField("Company", text: b.company).frame(width: 110)
                    TextField("Cat#", text: b.cat).frame(width: 74)
                    Text("1:").foregroundStyle(.secondary).frame(width: 12)
                    TextField("", value: b.dilution, format: plain).frame(width: 58)
                    Text(ab.dilution > 0 ? "\(fmtNum(vol / ab.dilution)) µL" : "dilution?")
                        .font(.system(size: ab.dilution > 0 ? 12 : 10.5, weight: .semibold)).monospacedDigit()
                        .rolling(vol, store.motion)
                        .foregroundColor(ab.dilution > 0 ? Brand.ink : .red)
                        .frame(width: 58, alignment: .trailing)
                        .help(ab.dilution > 0 ? "Volume of antibody to add" : "Enter this antibody's dilution")
                    Button {
                        let id = ab.id
                        binding.wrappedValue.primaries.removeAll { $0.id == id }
                    } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(SquishStyle(on: store.motion)).frame(width: 16)
                }
            }
            FridgeButton(secondaries: false, setID: setID)

            columnHeader("2nd", [("", 15), ("2ND · SECONDARY", nil), ("COMPANY", 110), ("CAT#", 74), ("DILUTION", 76), ("ADD", 58), ("", 16)])
            ForEach(set.secondaries) { q in
                let b = binding.secondaries.row(q)
                HStack(spacing: 6) {
                    let v = report.verdict(secondary: q.id)
                    VerdictIcon(verdict: v.0, why: v.1, size: 13).frame(width: 15)
                        .animation(store.motion ? .spring(response: 0.35, dampingFraction: 0.55) : nil, value: v.0)
                    TextField("e.g. 488 rab", text: b.name)
                    // the maker and catalogue number, as for primaries: edits go back to the fridge tube and
                    // are checked with the manufacturer's record
                    TextField("Company", text: b.company.orEmpty).frame(width: 110)
                    TextField("Cat#", text: b.cat.orEmpty).frame(width: 74)
                    Text("1:").foregroundStyle(.secondary).frame(width: 12)
                    TextField("", value: b.dilution, format: plain).frame(width: 58)
                    Text(q.dilution > 0 ? "\(fmtNum(vol / q.dilution)) µL" : "dilution?")
                        .font(.system(size: q.dilution > 0 ? 12 : 10.5, weight: .semibold)).monospacedDigit()
                        .rolling(vol, store.motion)
                        .foregroundColor(q.dilution > 0 ? Brand.ink : .red)
                        .frame(width: 58, alignment: .trailing)
                    Button {
                        let id = q.id
                        binding.wrappedValue.secondaries.removeAll { $0.id == id }
                    } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(SquishStyle(on: store.motion)).frame(width: 16)
                }
            }
            FridgeButton(secondaries: true, setID: setID)
            PanelStrip(report: report)
            // its spectrum, on every card; picking the stain to paint with plays it (the lasers fire, the
            // light rises, any overlap glows), and so does changing its dyes
            if !report.channels.isEmpty {
                SpectralStrip(channels: report.channels, motion: store.motion, active: store.tool == .paint(setID))
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(14)
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.card)
                .overlay(alignment: .leading) {
                    Rectangle().fill(accent).frame(width: 5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Brand.rule, lineWidth: 1))
                .shadow(color: Brand.navy.opacity(0.10), radius: 7, x: 0, y: 2)
        )
        .fxCard(setID)
    }
}

struct BlockingSection: View {
    @EnvironmentObject var store: Store
    private let showSettings = State(initialValue: false)   // plain State: the @State macro plugin is not in the Command Line Tools

    var body: some View {
        let suggested = store.exp.suggestedBlocking(store.settings)
        let mL = store.exp.blocking(store.settings)
        Card(title: "Blocking buffer", icon: "drop") {
            HStack {
                Text("Make")
                TextField(fmtNum(suggested), value: $store.exp.blockingOverride, format: plain).frame(width: 66)
                Text("mL")
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Pill(text: "NDS \(fmtNum(mL * store.settings.ndsPerMl)) µL", color: Brand.navy)
                Spacer()
                if store.exp.blockingOverride == nil {
                    Pill(text: "AUTO", color: Brand.navy)
                } else {
                    Button("Back to auto") {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        store.exp.blockingOverride = nil
                    }
                    .buttonStyle(.borderless).foregroundColor(Brand.navy)
                }
            }
            Text("Follows the plate automatically: \(fmtNum(store.exp.blockingNeedUl(store.settings))) µL needed for \(store.exp.totalStainedWells) stained wells (blocking step + 1st + 2nd dilutions) plus \(fmtNum(store.settings.blockExtraUl)) µL extra = \(fmtNum(suggested)) mL. Type a number to fix it for this plate; it returns to automatic when you change the wells.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Volume and day settings", isExpanded: showSettings.projectedValue) {
                VStack(alignment: .leading, spacing: 6) {
                    settingRow("Antibody solution per well", $store.settings.ulPerWell, "µL")
                    settingRow("Extra wells of excess", $store.settings.extraWells, "wells")
                    settingRow("Blocking step per stained well", $store.settings.blockPerWell, "µL")
                    settingRow("Extra blocking buffer", $store.settings.blockExtraUl, "µL")
                    settingRow("NDS per mL of blocking buffer", $store.settings.ndsPerMl, "µL")
                    settingRow("Cells are fixed on day", $store.settings.fixDay, "after Day 0")
                }
                .padding(.top, 6)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func settingRow(_ label: String, _ value: Binding<Double>, _ unit: String) -> some View {
        HStack {
            Text(label).frame(width: 220, alignment: .leading)
            TextField("", value: value, format: plain).frame(width: 66)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Plate

struct PlateSection: View {
    @EnvironmentObject var store: Store
    @FocusState private var labelFocused: Bool
    // kept without observing them: the pointer moving changes these many times a second, and only the
    // tilt wrapper and the hologram (which observe them) should redraw, never this whole card
    private let tiltBox = State(initialValue: TiltModel())
    private let hoverBox = State(initialValue: HoverFlag())
    private var tilt: TiltModel { tiltBox.wrappedValue }
    private var hover: HoverFlag { hoverBox.wrappedValue }

    private let cw: CGFloat = 48, ch: CGFloat = 44, leftW: CGFloat = 64, letterW: CGFloat = 18

    var body: some View {
        Card(title: "ibidi 96-well plate", icon: "circle.grid.3x3") {
            HStack(alignment: .top, spacing: 8) {
                toolBar.frame(maxWidth: .infinity, alignment: .leading)
                Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward").font(.system(size: 13)) }
                    .buttonStyle(.borderless).disabled(store.undoCount == 0)
                    .help("Undo (⌘Z)")
                Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward").font(.system(size: 13)) }
                    .buttonStyle(.borderless).disabled(store.redoCount == 0)
                    .help("Redo (⇧⌘Z)")
                Button { store.confirmClearPlate() } label: {
                    Label("Clear", systemImage: "arrow.counterclockwise").font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Remove all painted wells and labels")
            }
            if store.exp.sets.isEmpty { AntibodyDoodle() }
            tagBar
            HStack(spacing: 10) {
                if store.tool == .duplicate {
                    Picker("", selection: $store.duplicateScope) {
                        Text("Well").tag(DuplicateScope.well)
                        Text("Row").tag(DuplicateScope.row)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                    .help("Duplicate a single well or a whole row at once")
                }
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text("labels").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .frame(width: leftW + letterW + 8, alignment: .trailing)
                    ForEach(0..<12, id: \.self) { j in
                        TextField("", text: $store.exp.topLabels[j])
                            .textFieldStyle(.plain).font(.system(size: 10))
                            .padding(.horizontal, 3).frame(width: cw - 4, height: 20)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
                            .frame(width: cw)
                    }
                }
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 26)
                        ForEach(0..<8, id: \.self) { i in
                            TextField("", text: $store.exp.leftLabels[i])
                                .textFieldStyle(.plain).font(.system(size: 11))
                                .padding(.horizontal, 3).frame(width: leftW - 6, height: 22)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
                                .frame(width: leftW, height: ch)
                        }
                    }
                    TiltPlate(on: store.motion, model: tilt, hover: hover) { plateBody }
                        .fxPlate()          // the lid's outline: the plate lying flat, outside the tilt
                        // The marker the effects aim at sits outside the tilt, over where the grid lies flat
                        // (plateBody's padding, then the row letters; the column numbers and their gap).
                        // Inside the tilt, AppKit reported it hundreds of points away while the plate leaned
                        // towards the pointer, so a quick click played its effects over the toolbar.
                        .background(alignment: .topLeading) {
                            Color.clear.frame(width: 12 * cw, height: 8 * ch)
                                .fxGrid()
                                .padding(.leading, 6 + letterW).padding(.top, 8 + 14 + 4)
                        }
                }
            }

            if store.tool == .text {
                HStack {
                    if let w = store.selectedWell {
                        Pill(text: "\(rowLetters[w / 12])\(w % 12 + 1)", color: Brand.navy)
                        TextField("text or number — Return moves to the next well",
                                  text: Binding(get: { store.exp.label(w) }, set: { store.setLabel(w, $0) }))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 340)
                            .focused($labelFocused)
                            .onSubmit {
                                store.selectedWell = (w + 1) % 96
                                labelFocused = true
                            }
                    } else {
                        Text("Click a well to type a label into it.").foregroundStyle(.secondary)
                    }
                }
                .onChange(of: store.selectedWell) { _ in labelFocused = true }
            }
        }
    }

    private var hint: String {
        switch store.tool {
        case .paint: return "Click or drag across wells to assign this stain. Click a painted well again to clear it."
        case .erase: return "Click or drag across wells to remove their stain."
        case .text: return "Click a well, type its label (a concentration or condition), press Return for the next well."
        case .tag: return "Click any well beside a stained block to stamp this experiment number there. Click it again to remove it."
        case .duplicate:
            guard let s = store.duplicateSource else {
                return store.duplicateScope == .row
                    ? "Click the row whose wells you want to copy, then click or drag across the rows that should look the same."
                    : "Click the well you want to copy, then click or drag across the wells that should match it."
            }
            if store.duplicateScope == .row {
                return "Copying row \(rowLetters[s / 12]): click or drag across other rows to give them the same stains and labels. Click row \(rowLetters[s / 12]) again to stop."
            }
            return "Copying \(rowLetters[s / 12])\(s % 12 + 1): click or drag across other wells to copy its stain and label there. Click it again to stop."
        }
    }

    private var toolBar: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(store.exp.sets.enumerated()), id: \.element.id) { idx, set in
                toolButton(.paint(set.id), setAccent(set, idx)) {
                    Circle().fill(setFill(set, idx)).overlay(Circle().stroke(setAccent(set, idx), lineWidth: 1.5))
                        .frame(width: 14, height: 14)
                    Text("Stain \(idx + 1)")
                    Text("\(store.exp.wellCount(set))").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            toolButton(.erase, Brand.navy) { Image(systemName: "eraser"); Text("Erase") }
            toolButton(.text, Brand.navy) { Image(systemName: "character.cursor.ibeam"); Text("Label") }
            toolButton(.duplicate, Brand.navy) { Image(systemName: "square.on.square"); Text("Duplicate") }
        }
    }

    /// One chip per sample: stamps that experiment number onto the plate with a click.
    private var tagBar: some View {
        let samples = store.exp.samples.filter { !$0.tag.isEmpty }
        return FlowLayout(spacing: 8) {
            Eyebrow(text: "Experiment tags", color: Brand.mid, size: 9.5).frame(height: 28)
            if samples.isEmpty {
                Text("add a sample number on the left to tag wells with it").font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(samples) { sample in
                toolButton(.tag(sample.id), Brand.navy) { Image(systemName: "tag"); Text(sample.tag) }
            }
        }
    }

    private func shakeCount(_ t: Tool) -> Int {
        if case .paint(let id) = t { return store.shakes[id] ?? 0 }
        return 0
    }

    private func toolButton<L: View>(_ t: Tool, _ color: Color, @ViewBuilder label: () -> L) -> some View {
        let on = store.tool == t
        return Button {
            // the selected stain clicked again: show its hologram now
            if on, case .paint = t { store.hologramRequest += 1 } else if case .paint = t { store.stainPicked += 1 }
            store.tool = t
        } label: {
            HStack(spacing: 6) { label() }
                .lineLimit(1)
                .fixedSize()            // never squeezed: a full row wraps to the next instead
                .font(.system(size: 12.5, weight: on ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(on ? color.opacity(0.20) : Color(nsColor: .textBackgroundColor)))
                .overlay(Capsule().stroke(on ? color : Color(nsColor: .separatorColor), lineWidth: on ? 1.8 : 1))
                .contentShape(Capsule())
                .scaleEffect(on ? 1.05 : 1)
                .animation(store.animations ? .spring(response: 0.28, dampingFraction: 0.55) : nil, value: on)
                .modifier(Shake(animatableData: CGFloat(shakeCount(t))))
                .animation(store.motion ? .linear(duration: 0.5) : nil, value: shakeCount(t))
                .padding(3)             // room for the outline and the selected chip's grow
        }
        .buttonStyle(SquishStyle(on: store.motion))
    }

    /// Plate drawn like the real thing: a moulded body with the A1 corner cut, embossed column numbers
    /// and row letters, and a raised deck of square wells.
    private var plateBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Spacer().frame(width: letterW)
                ForEach(0..<12, id: \.self) { j in
                    Embossed(text: "\(j + 1)").frame(width: cw)
                }
            }
            .frame(height: 14)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { i in
                        Embossed(text: rowLetters[i]).frame(width: letterW, height: ch)
                    }
                }
                PlateGrid(paint: store.paint, hover: hover, cw: cw, ch: ch)
                    // the wells' depth, leaning with the plate
                    .overlay(DeepWells(tilt: tilt, cw: cw, ch: ch).allowsHitTesting(false))
                    .background(
                        // the raised deck the wells sit in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: "1C222B"), Color(hex: "14181F")], startPoint: .top, endPoint: .bottom))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(LinearGradient(colors: [.white.opacity(0.14), .black.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
                            .padding(-4)
                    )
            }
        }
        .padding(.top, 8).padding(.bottom, 12).padding(.leading, 6).padding(.trailing, 12)
        .background(PlateShell())
    }

}

/// The plate's 96 wells. Its own view observing the drag in progress, so painting redraws the plate
/// alone; the rest of the window catches up when the drag ends.
struct PlateGrid: View {
    @EnvironmentObject var store: Store
    @ObservedObject var paint: PaintBuffer
    let hover: HoverFlag
    let cw: CGFloat, ch: CGFloat

    var body: some View {
        let sets = store.exp.sets
        let ids = sets.map { $0.id }
        let fills = sets.enumerated().map { fillHex($0.element, $0.offset) }
        let accents = sets.enumerated().map { setAccent($0.element, $0.offset) }
        let spot = store.spotlightSet.flatMap { ids.contains($0) ? $0 : nil }
        let wells = (0..<96).map { paint.value($0, store.exp.wells[$0]) }
        let bad = store.clashingSets
        return VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { i in
                HStack(spacing: 0) {
                    ForEach(0..<12, id: \.self) { j in
                        let w = i * 12 + j
                        let k = wells[w].flatMap { ids.firstIndex(of: $0) }
                        let dupSource = store.tool == .duplicate && store.duplicateSource != nil
                            && (store.duplicateScope == .row ? store.duplicateSource! / 12 == i : store.duplicateSource == w)
                        WellCell(fill: k.map { fills[$0] }, accent: k.map { accents[$0] }, label: store.exp.label(w),
                                 selected: store.tool == .text && store.selectedWell == w, dupSource: dupSource,
                                 dim: false, glow: false,      // the spotlight is drawn over the grid (SpotVeil)
                                 motion: store.motion, cw: cw, ch: ch,
                                 clash: wells[w].map { bad.contains($0) } ?? false)
                            .equatable()
                    }
                }
            }
        }
        // in the microscope room the stained wells glow from behind
        .background(store.darkRoom ? RoomGlow(wells: (0..<96).compactMap { w in wells[w].flatMap { ids.firstIndex(of: $0) }.map { (w, fills[$0]) } }, cw: cw, ch: ch)
                        .allowsHitTesting(false).padding(-8) : nil)
        .overlay(GlintLane(stained: (0..<96).filter { w in wells[w].map { ids.contains($0) } ?? false }, cw: cw, ch: ch, active: store.ambient && spot == nil)
                    .allowsHitTesting(false))
        .overlay(SpotVeil(wells: spot.map { id in (0..<96).filter { wells[$0] == id } } ?? [],
                          hex: spot.flatMap { id in sets.firstIndex { $0.id == id } }.map { setAccentHex(sets[$0], $0) } ?? "4A78B8",
                          cw: cw, ch: ch, motion: store.motion)
                    .allowsHitTesting(false))
        .overlay(HologramProjector(hover: hover, holo: HoloController.shared, cw: cw, ch: ch))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    let j = Int(floor(v.location.x / cw)), i = Int(floor(v.location.y / ch))
                    store.dragOver((0..<12).contains(j) && (0..<8).contains(i) ? i * 12 + j : nil)
                }
                .onEnded { _ in store.endDrag() }
        )
    }
}

/// One well. Its own small view with plain values, so painting a well redraws that well and not all 96.
struct WellCell: View, Equatable {
    let fill: String?
    let accent: Color?
    let label: String
    let selected: Bool
    let dupSource: Bool
    let dim: Bool
    let glow: Bool
    /// The stain in this well has a pairing that cannot work: outlined in red with a "!".
    var clash = false
    let motion: Bool
    let cw: CGFloat
    let ch: CGFloat
    private let splashAt = State(initialValue: Date.distantPast)
    private let settle = State(initialValue: 0)

    static func == (a: WellCell, b: WellCell) -> Bool {
        a.fill == b.fill && a.accent == b.accent && a.label == b.label && a.selected == b.selected && a.dupSource == b.dupSource
            && a.dim == b.dim && a.glow == b.glow && a.motion == b.motion && a.cw == b.cw && a.ch == b.ch && a.clash == b.clash
    }

    init(fill: String?, accent: Color?, label: String, selected: Bool, dupSource: Bool, dim: Bool, glow: Bool, motion: Bool, cw: CGFloat, ch: CGFloat, clash: Bool = false) {
        self.clash = clash
        self.fill = fill; self.accent = accent; self.label = label; self.selected = selected; self.dupSource = dupSource
        self.dim = dim; self.glow = glow; self.motion = motion; self.cw = cw; self.ch = ch
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let dark = fill.map { isDark($0) } ?? false
        ZStack {
            // the empty well: its floor in the shade of the wall at the top
            // the empty well: black walls round a dark glass bottom, with a faint reflection
            shape.fill(LinearGradient(colors: [Color(hex: "0A121D"), Color(hex: "13202F"), Color(hex: "1A2B3F")],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.fill(LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0)],
                                      startPoint: .topLeading, endPoint: UnitPoint(x: 0.55, y: 0.55)))
            if let f = fill {
                ZStack {
                    shape.fill(Color(hex: f))
                    // the meniscus: darker where the liquid climbs the wall, brighter in the middle
                    shape.strokeBorder(Color.black.opacity(dark ? 0.22 : 0.10), lineWidth: 3)
                    shape.fill(RadialGradient(colors: [.white.opacity(dark ? 0.22 : 0.42), .white.opacity(0)],
                                              center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: cw * 0.55))
                    // the light on the surface
                    Capsule().fill(Color.white.opacity(dark ? 0.10 : 0.20))
                        .frame(width: cw * 0.24, height: 2.4)
                        .rotationEffect(.degrees(-18))
                        .offset(x: -cw * 0.17, y: -ch * 0.27)
                }
            }
            // the black wall: its top edge catching the light
            shape.strokeBorder(LinearGradient(colors: [Color(hex: "6B7685"), Color(hex: "39424E"), Color(hex: "232A33")],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1.6)
            if fill != nil { shape.stroke(accent ?? Color(hex: "B9C8DF"), lineWidth: glow ? 2.4 : 1.3) }
            if clash {
                shape.fill(Color(hex: "FF3B30").opacity(0.14))
                shape.stroke(Color(hex: "FF453A"), lineWidth: 2.2)
            }
            if selected { shape.stroke(Color(hex: "9BD2FF"), lineWidth: 3) }
            if dupSource { shape.stroke(Color(hex: "9BD2FF"), style: StrokeStyle(lineWidth: 2, dash: [4, 3])) }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.65)
                // light on an empty (dark) well or a dark stain, dark ink on a pale stain
                // pale stains always get dark lettering (also in the microscope room)
                .foregroundColor(fill == nil || dark ? Color(hex: "E3ECF7") : Color(hex: "172033"))
                .padding(2)
        }
        .overlay(alignment: .topTrailing) {
            if clash {
                Text("!")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(.white)
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(Color(hex: "FF3B30")))
                    .offset(x: 2, y: -2)
                    .help("This stain has a pairing that cannot work: see its card")
            }
        }
        .padding(2.5)
        .frame(width: cw, height: ch)
        .shadow(color: glow ? (accent ?? Brand.mid).opacity(0.55) : .clear, radius: glow ? 7 : 0)
        .scaleEffect(glow ? 1.04 : 1)
        .opacity(dim ? 0.28 : 1)
        // the pop and ripple when a well is painted are played by the effects layer (Fx.swift): as SwiftUI
        // animations here they redrew the whole plate every frame and cost most of the CPU while painting
        .animation(motion ? .spring(response: 0.32, dampingFraction: 0.7) : nil, value: dim)
        .animation(motion ? .spring(response: 0.32, dampingFraction: 0.7) : nil, value: glow)
    }
}

// MARK: - Compatibility

struct VerdictIcon: View {
    let verdict: Verdict
    let why: String
    var size: CGFloat = 14

    var body: some View {
        Image(systemName: verdict == .ok ? "checkmark.circle.fill" : (verdict == .problem ? "xmark.circle.fill" : "questionmark.circle"))
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(verdict == .ok ? Color(hex: "2FA84F") : (verdict == .problem ? Color(hex: "D93A2F") : Color(hex: "9AA8BC")))
            .id(verdict)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
            .help(why)
            .accessibilityLabel(verdict == .ok ? "Compatible" : (verdict == .problem ? "Problem: \(why)" : "Not checked: \(why)"))
    }
}

/// Every primary with the secondary that should find it, judged against the makers' data.
struct PanelStrip: View {
    @EnvironmentObject var store: Store
    let report: PanelReport

    /// A secondary on the card that found no primary: it is the one turned away by a primary left without one.
    private var stray: String? { report.channels.first { $0.markers.isEmpty && !$0.fluor.counterstain }?.secondary }

    private func dockState(_ c: Combination) -> DockState {
        guard c.secondary != nil else { return stray != nil ? .refused : .none }
        switch c.verdict {
        case .ok: return .bound(c.fluor?.hex ?? "8EA4C3")
        case .problem: return .refused
        case .unknown: return .unsure
        }
    }

    private func dockHelp(_ c: Combination) -> String {
        switch dockState(c) {
        case .bound: return "The secondary takes hold of the primary: \(c.secondary ?? "") recognises \(c.host ?? "its") host."
        case .refused:
            if c.secondary == nil, let s = stray { return "\(s) cannot bind this \(c.host ?? "") primary: it is turned away." }
            return "The secondary cannot bind this primary."
        case .unsure: return "Not enough is known to say whether these bind."
        case .none: return "No secondary for this primary yet."
        }
    }

    var body: some View {
        let r = report
        if !r.combos.isEmpty || !r.channels.isEmpty {
            let comboReasons = Set(r.combos.flatMap { $0.reasons })
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("COMPATIBILITY").font(.system(size: 9.5, weight: .bold, design: .serif)).tracking(1.2).foregroundColor(Brand.mid)
                    Spacer(minLength: 0)
                    switch r.verdict {
                    case .ok: Label("Every pairing checks out", systemImage: "checkmark.circle.fill").foregroundColor(Color(hex: "2F8F4E"))
                    case .problem: Label("\(r.issues.count) problem\(r.issues.count == 1 ? "" : "s")", systemImage: "xmark.circle.fill").foregroundColor(Color(hex: "C2362B"))
                    case .unknown: Label("Some antibodies cannot be checked", systemImage: "questionmark.circle").foregroundColor(.secondary)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                ForEach(Array(r.combos.enumerated()), id: \.element.primaryID) { k, c in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        VerdictIcon(verdict: c.verdict, why: c.reasons.joined(separator: "\n"), size: 11.5)
                        DockingIcon(state: dockState(c), motion: store.motion, delay: Double(k) * 0.12)
                            .frame(width: DockingIcon.size.width, height: DockingIcon.size.height)
                            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
                            .help(dockHelp(c))
                        Text(c.marker).font(.system(size: 11.5, weight: .bold)).foregroundColor(Brand.ink)
                        Text(c.host ?? "host?").font(.system(size: 11)).foregroundStyle(.secondary)
                            .help(c.hostFacts ?? "Host from the name in brackets")
                        Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                        if let sname = c.secondary {
                            Text(sname).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Brand.ink)
                                .help(c.secondaryFacts ?? sname)
                            if let f = c.fluor { DyeTag(fluor: f, owner: c.primaryID) }
                        } else {
                            Text("no secondary").font(.system(size: 11.5, weight: .semibold)).foregroundColor(Color(hex: "C2362B"))
                        }
                        if let kb = c.hostFacts { Text(kb).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail) }
                        Spacer(minLength: 0)
                    }
                    .onAppear { DyeFlash.owners.insert(c.primaryID) }
                    if c.verdict != .ok {
                        ForEach(c.reasons, id: \.self) { why in
                            Text(why).font(.system(size: 11)).foregroundColor(c.verdict == .problem ? Color(hex: "9B2C22") : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 18)
                        }
                    }
                }
                ForEach(r.channels.filter { $0.fluor.counterstain }, id: \.secondary) { ch in
                    HStack(spacing: 6) {
                        VerdictIcon(verdict: .ok, why: "\(ch.secondary) stains every nucleus", size: 11.5)
                        Text(ch.secondary).font(.system(size: 11.5, weight: .semibold))
                        DyeTag(fluor: ch.fluor)
                        Text("every nucleus").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                ForEach(r.issues.filter { !comboReasons.contains($0) }, id: \.self) { why in
                    Label(why, systemImage: "xmark.circle.fill").font(.system(size: 11)).foregroundColor(Color(hex: "9B2C22"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(r.notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle").font(.system(size: 10.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(r.verdict == .problem ? Color(hex: "FDEDEB") : Brand.pale.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(r.verdict == .problem ? Color(hex: "F0B4AD") : Brand.rule, lineWidth: 1))
        }
    }
}

// MARK: - Summary

struct SummarySection: View {
    @EnvironmentObject var store: Store

    private func tile(_ label: String, _ value: String, _ unit: String, _ icon: String, level: Double? = nil) -> some View {
        HStack(spacing: 10) {
            Group {
                if let level = level {
                    TubeLevel(fraction: level)          // a tube that fills as the buffer volume grows
                } else {
                    Image(systemName: icon).font(.system(size: 16, weight: .light)).foregroundColor(Brand.navy)
                }
            }
                .frame(width: 36, height: 36)
                .background(Circle().fill(Brand.pale))
                .overlay(Circle().stroke(Brand.rule, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased()).font(.system(size: 9, weight: .bold, design: .serif)).tracking(1.4).foregroundColor(Brand.mid)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 22, weight: .bold, design: .serif)).foregroundColor(Brand.ink)
                        .contentTransition(.numericText())
                        .animation(store.animations ? .easeOut(duration: 0.35) : nil, value: value)
                    Text(unit).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(CardBackground())
    }

    var body: some View {
        let mL = store.exp.blocking(store.settings)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                tile("Stained wells", "\(store.exp.totalStainedWells)", "of 96", "circle.grid.3x3")
                tile("Blocking buffer", fmtNum(mL), "mL", "drop", level: min(mL / 12, 1))
                tile("NDS", fmtNum(mL * store.settings.ndsPerMl), "µL", "eyedropper")
            }
            if !store.exp.sets.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(store.exp.sets.enumerated()), id: \.element.id) { idx, set in
                        let lit = store.spotlightSet == set.id
                        HStack(spacing: 8) {
                            Circle().fill(setFill(set, idx)).overlay(Circle().stroke(setAccent(set, idx), lineWidth: 1.5))
                                .frame(width: 13, height: 13)
                                .scaleEffect(lit ? 1.25 : 1)
                            Text("Stain \(idx + 1)").font(.system(size: 12, weight: .semibold))
                            let rep = panel(set, library: store.library)
                            VerdictIcon(verdict: rep.verdict, why: rep.summary, size: 12)
                            Text(legend(set)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 4)
                            Pill(text: "\(store.exp.wellCount(set)) wells · \(fmtNum(store.exp.volume(set, store.settings))) µL", color: setAccent(set, idx), roll: store.motion)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(lit ? setAccent(set, idx).opacity(0.1) : .clear))
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside { store.spotlightSet = set.id } else if store.spotlightSet == set.id { store.spotlightSet = nil }
                        }
                        .onTapGesture {
                            if store.tool != .paint(set.id) { store.stainPicked += 1 }
                            store.tool = .paint(set.id)
                        }
                        .help("Rest the pointer here to see this stain's wells; click to paint with it")
                        .animation(store.motion ? .easeOut(duration: 0.18) : nil, value: lit)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CardBackground())
            }
            VStack(spacing: 2) {
                Tagline()
                Text("Created by \(Brand.author)").font(.system(size: 12, weight: .semibold, design: .serif)).foregroundColor(Brand.navy)
                Text("\(Brand.department) · \(Brand.hospital)").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func legend(_ set: StainSet) -> String {
        let a = set.primaries.map { $0.name.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " + ")
        let b = set.secondaries.map { $0.name.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " + ")
        return b.isEmpty ? a : "\(a)  →  \(b)"
    }
}


/// Lays its children out left to right, starting a new row when the next one would not fit, so a plate
/// with many stain sets wraps its buttons instead of squeezing them.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { y += row + spacing; x = 0; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            v.place(at: CGPoint(x: x, y: y + (row > 0 ? 0 : 0)), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}


/// The secondary's dye as a small labelled tag ("594", "DAPI") in the channel's colour, so it reads
/// as the dye and not as a check result.
struct DyeTag: View {
    let fluor: Fluor
    /// The pairing row it sits on, so a dye new to that row lights up.
    var owner: UUID? = nil
    /// Bumped to light it up for a moment when the dye arrives on the card, like a fluorophore being excited.
    /// The light is a Core Animation layer over the tag: animating the tag in SwiftUI redrew the whole card
    /// on every frame.
    private let flashes = State(initialValue: 0)
    var body: some View {
        let c = Color(hex: fluor.hex)
        let label = fluor.name
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5).fill(c).frame(width: 3, height: 9)
            Text(label).font(.system(size: 9.5, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 5).padding(.vertical, 1.5)
        .background(RoundedRectangle(cornerRadius: 4).fill(c.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(c.opacity(0.35), lineWidth: 0.75))
        .overlay(DyeGlow(hex: fluor.hex, label: label, flashes: flashes.wrappedValue).allowsHitTesting(false))
        .help("Dye: \(fluor.name) (\(fluor.wavelength) nm channel). This shows the colour, not a check result.")
        .onAppear { if DyeFlash.shouldFlash(fluor, owner: owner) { flash() } }
        // gone from its row: if the dye comes back later, it lights up again
        .onDisappear { if let o = owner { DyeFlash.seen.remove("\(o)|\(fluor.name)") } }
        .onChange(of: fluor.hex) { _ in if Date() >= DyeFlash.quietUntil { flash() } }
    }

    private func flash() {
        guard FxCenter.shared.store?.motion ?? true else { return }
        flashes.wrappedValue += 1
    }
}


// MARK: - The plate's moulding

/// The plate body: white polymer with a soft drop shadow, a bevelled edge and the A1 corner cut off,
/// as on a real SBS-format plate.
struct PlateShell: View {
    var body: some View {
        GeometryReader { g in
            if let img = PlateShell.image(g.size) {
                Image(decorative: img, scale: screenScale).resizable()
                    .frame(width: g.size.width + 32, height: g.size.height + 32)
                    .offset(x: -16, y: -16)
            }
        }
    }

    /// The plate body drawn once per size: re-blurring its shadow every time a well was painted was
    /// most of the cost of painting.
    private static var cache: [String: CGImage] = [:]
    static func image(_ size: CGSize) -> CGImage? {
        guard size.width > 1, size.height > 1 else { return nil }
        let key = "\(Int(size.width))x\(Int(size.height))"
        if let i = cache[key] { return i }
        let pad: CGFloat = 16
        let full = CGSize(width: size.width + 2 * pad, height: size.height + 2 * pad)
        let img = renderImage(full, screenScale) { c in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let r = CGRect(x: pad, y: pad, width: size.width, height: size.height)
            func outline(_ rect: CGRect, _ radius: CGFloat, _ cut: CGFloat) -> CGPath {
                ChamferedRect(radius: radius, cut: cut).path(in: rect).cgPath
            }
            let body = outline(r, 14, 16)
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: 6), blur: 16, color: NSColor.black.withAlphaComponent(0.35).cgColor)
            c.addPath(body); c.setFillColor(cg("1A1F27")); c.fillPath()
            c.restoreGState()
            c.saveGState(); c.addPath(body); c.clip()
            if let g = CGGradient(colorsSpace: space, colors: [cg("3A424E"), cg("20262F"), cg("15191F")] as CFArray, locations: [0, 0.5, 1]) {
                c.drawLinearGradient(g, start: CGPoint(x: 0, y: r.minY), end: CGPoint(x: 0, y: r.maxY), options: [])
            }
            if let g = CGGradient(colorsSpace: space, colors: [cg("FFFFFF", 0.09), cg("FFFFFF", 0)] as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.minX + r.width * 0.4, y: r.minY + r.height * 0.6), options: [])
            }
            c.restoreGState()
            c.addPath(body); c.setStrokeColor(cg("FFFFFF", 0.22)); c.setLineWidth(1.4); c.strokePath()
            c.addPath(outline(r.insetBy(dx: 5, dy: 5), 11, 13)); c.setStrokeColor(cg("000000", 0.55)); c.setLineWidth(1.4); c.strokePath()
            c.addPath(outline(r.insetBy(dx: 6, dy: 6), 11, 13)); c.setStrokeColor(cg("FFFFFF", 0.06)); c.setLineWidth(1); c.strokePath()
        }
        cache[key] = img
        return img
    }
}

/// A rounded rectangle with its top-left corner cut at 45°.
struct ChamferedRect: Shape, InsettableShape {
    var radius: CGFloat
    var cut: CGFloat
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> ChamferedRect { var c = self; c.insetAmount += amount; return c }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + cut, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addArc(center: CGPoint(x: r.maxX - radius, y: r.maxY - radius), radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + cut))
        p.closeSubpath()
        return p
    }
}

/// A column number or row letter moulded into the plate: a light edge under dark lettering.
struct Embossed: View {
    let text: String
    var body: some View {
        ZStack {
            Text(text).foregroundColor(.black.opacity(0.6)).offset(y: 0.8)
            Text(text).foregroundColor(Color(hex: "9AA6B6"))
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
    }
}

let fxProbe = ProcessInfo.processInfo.environment["ICC_FX_PROBE"] ?? ""

/// A stain's outline colour as hex, for the effects layer.
func setAccentHex(_ set: StainSet, _ i: Int) -> String {
    let c = NSColor(setAccent(set, i)).usingColorSpace(.sRGB) ?? NSColor.gray
    return String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
}


/// A light date field: the date as text with a day up / day down, and the calendar in a popover when
/// clicked. (The system date picker redrew itself on every frame while the list scrolled; sixteen of
/// them made scrolling lag.)
struct LiteDateField: View {
    let date: Binding<Date>
    var enabled = true
    private let open = State(initialValue: false)
    private static let format: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    private func step(_ days: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: days, to: date.wrappedValue) { date.wrappedValue = d }
    }

    var body: some View {
        HStack(spacing: 3) {
            Button { open.wrappedValue.toggle() } label: {
                Text(Self.format.string(from: date.wrappedValue))
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundColor(Brand.ink)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
            }
            .buttonStyle(.plain)
            .help("Click for a calendar")
            .popover(isPresented: open.projectedValue, arrowEdge: .bottom) {
                DatePicker("", selection: date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(10)
            }
            VStack(spacing: 0) {
                Button { step(1) } label: { Image(systemName: "chevron.up").font(.system(size: 7, weight: .bold)).frame(width: 14, height: 9) }
                Button { step(-1) } label: { Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).frame(width: 14, height: 9) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("A day later / earlier")
        }
        .opacity(enabled ? 1 : 0.45)
        .disabled(!enabled)
    }
}
