import SwiftUI
import AppKit
import UniformTypeIdentifiers

func hexString(_ color: Color) -> String {
    let c = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    return String(format: "%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
}


// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            ModeStrip()
            ZStack {
                if store.mode == .plan {
                    ProtocolView()
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    ResultsView()
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(alignment: .bottom) {
                if store.motion && store.showEppi {
                    EppiLane(store: store, event: store.eppiEvent, active: store.ambient).frame(maxWidth: .infinity).frame(height: 240)
                }
            }
        }
        .background(LinearGradient(colors: [Brand.pale.opacity(0.75), Brand.page], startPoint: .top, endPoint: .bottom))
        .overlay { ConfettiLayer() }
        .overlay(alignment: .top) {
            ZStack {
                if let t = store.toast {
                    ToastView(toast: t).id(t.id)
                        .transition(.move(edge: .top).combined(with: .scale(scale: 0.6)).combined(with: .opacity))
                }
            }
            .padding(.top, 128)
            .animation(.spring(response: 0.45, dampingFraction: 0.6), value: store.toast?.id)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            ZStack {
                if let r = store.receipt {
                    ReceiptView(receipt: r).id(r.id)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.trailing, 22).padding(.bottom, 22)
            .animation(store.motion ? .spring(response: 0.5, dampingFraction: 0.78) : nil, value: store.receipt?.id)
        }
        .overlay {
            if let show = store.importShow, store.motion, !store.importShowInWindow {
                ImportShowView(show: show).transition(.opacity)
            }
        }
        .tint(Brand.navy)
        .sheet(isPresented: Binding(get: { store.showIPadLink }, set: { store.showIPadLink = $0 })) {
            IPadLinkView().environmentObject(store)
        }
    }
}

/// The first gene's graph, by condition, for the export receipt.
func receiptChart(_ store: Store) -> MatureChart {
    let rs = store.results, opt = store.options
    let g = rs.genes[0]
    let hex = store.resultColor(g.name, 0)
    let cats: [BarCategory?] = rs.rows(opt).map { c in
        guard let c else { return nil }
        let v = rs.value(g, c, opt)
        return BarCategory(label: rs.label(c), group: nil, name: rs.label(c),
                           cells: [v.map { BarValue(value: $0.value, sd: $0.sd, low: $0.low, counted: $0.counted, wells: $0.wells) }],
                           measured: [g.sample(c) != nil && v == nil])
    }
    return MatureChart(title: g.name, colorHex: hex, categories: cats, series: [BarSeries(name: g.name, fill: hex)],
                       xTitle: opt.xTitle, yTitle: opt.yTitle, refLine: opt.refLine, brackets: false)
}

/// What was just exported: a picture of it, its name, and the two things one does next.
struct ReceiptView: View {
    @EnvironmentObject var store: Store
    let receipt: Receipt

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundColor(Color(hex: "2E9E5B"))
                Text(receipt.title).font(.system(size: 14, weight: .bold, design: .serif)).foregroundColor(Brand.ink)
                Spacer()
                Button { store.receipt = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: 20, height: 20).background(Circle().fill(Brand.pale))
                }
                .buttonStyle(.plain)
            }
            if let img = receipt.image {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .background(Color(fixed: "FFFFFF"))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Brand.rule, lineWidth: 1))
            }
            Text(receipt.detail ?? receipt.url.lastPathComponent).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(receipt.detail == nil ? 1 : 4).truncationMode(.middle)
            HStack(spacing: 8) {
                FunButton(action: { NSWorkspace.shared.open(receipt.url) }) {
                    Label("Open in Excel", systemImage: "tablecells").font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Brand.navy))
                }
                FunButton(action: { NSWorkspace.shared.activateFileViewerSelecting([receipt.url]) }) {
                    Label("Show in Finder", systemImage: "folder").font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Brand.accent).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().stroke(Brand.navy.opacity(0.4), lineWidth: 1))
                }
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.card)
            .shadow(color: Brand.navy.opacity(0.25), radius: 16, y: 6))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.rule, lineWidth: 1))
        .onHover { store.receiptHeld = $0 }
    }
}

struct HeaderBar: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) private var scheme

    private func headerLabel(_ title: String, _ icon: String, filled: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 13, weight: filled ? .bold : .semibold))
            .foregroundColor(filled ? .white : Brand.accent)
            .padding(.horizontal, filled ? 16 : 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(filled ? Brand.navy : Brand.card))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Brand.navy.opacity(filled ? 0 : 0.35), lineWidth: 1))
            .shadow(color: Brand.navy.opacity(filled ? 0.35 : 0), radius: 4, y: 2)
            .contentShape(Rectangle())
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: Brand.department, color: .white.opacity(0.95), size: 10.5)
                Text(Brand.appName).font(.system(size: 27, weight: .bold, design: .serif)).foregroundColor(.white)
            }
            .fixedSize()
            BannerLane(active: store.ambient)
                .frame(minWidth: 0, maxWidth: 320).frame(height: 54)
                .padding(.horizontal, 8)
                .layoutPriority(-1)
            Spacer(minLength: 0)
            if store.mode == .plan {
                IPadButton(menu: false)
                BenchButton(menu: false)
                FunButton(action: { store.newProtocol() }) { headerLabel("New", "plus.rectangle.on.rectangle", filled: false) }
                    .help("Start a new protocol")
                FunButton(action: { store.openPlan() }) { headerLabel("Open", "folder", filled: false) }
                    .help("Open a saved protocol (⇧⌘O)")
                FunButton(action: { store.savePlan() }) { headerLabel("Save", "square.and.arrow.down", filled: false) }
                    .help("Save this protocol to open again later (⌘S)")
                FunButton(action: { store.export() }) { headerLabel("Export Protocol", "arrow.down.doc", filled: true) }
                    .help("Export the protocol workbook and melt sheet (⌘E)")
            } else {
                FunButton(action: { store.openResults() }) { headerLabel("Open Results", "folder", filled: false) }
                    .help("Open the qTOWER result export (⌘O)")
                FunButton(action: { store.export() }) { headerLabel("Export Graphs", "arrow.down.doc", filled: true) }
                    .help("Save the workbook with the summary table and graphs (⌘E)")
            }
            if let logo = Brand.logo {
                Image(nsImage: logo).renderingMode(scheme == .dark ? .template : .original).resizable().interpolation(.high)
                    .foregroundColor(.white.opacity(0.92))
                    .aspectRatio(contentMode: .fit).frame(height: 44).padding(.leading, 10)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 80)
        .background(Brand.gradient)
    }
}

/// Strip under the banner: switch between the two jobs, and the file that will be written.
struct ModeStrip: View {
    @EnvironmentObject var store: Store

    private func tab(_ m: Mode, _ title: String, _ icon: String) -> some View {
        let on = store.mode == m
        return FunButton(action: { store.switchMode(m) }) {
            Label(title, systemImage: icon)
                .font(.system(size: 12.5, weight: on ? .bold : .medium))
                .foregroundColor(on ? .white : Brand.accent)
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(Capsule().fill(on ? Brand.navy : Color.clear))
                .overlay(Capsule().stroke(Brand.navy.opacity(on ? 0 : 0.35), lineWidth: 1))
                .contentShape(Capsule())
        }
    }

    private var customBinding: Binding<String> {
        Binding(
            get: { store.mode == .plan ? store.plan.customTitle : store.options.customTitle },
            set: { new in
                let t = String(new.prefix(120))
                if store.mode == .plan { store.plan.customTitle = t } else { store.options.customTitle = t }
            })
    }

    var body: some View {
        let custom = !customBinding.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
        HStack(spacing: 10) {
            tab(.plan, "1 · Protocol", "list.clipboard")
            tab(.results, "2 · Results & graphs", "chart.bar")
            Rectangle().fill(Brand.rule).frame(width: 1, height: 18).padding(.horizontal, 6)
            Eyebrow(text: "Output file")
            TextField(store.mode == .plan ? "Custom title (optional)" : "Custom file name (optional)", text: customBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .frame(width: 200)
                .background(RoundedRectangle(cornerRadius: 5).fill(custom ? Brand.pale : Color(hex: "F7F9FC")))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Brand.rule, lineWidth: 1))
                .help(store.mode == .plan ? "Your own title: used for the file name and the heading of the protocol sheet" : "Your own name for the graphs workbook")
            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary)
            Text(store.exportFileName)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(custom ? Brand.accent : Brand.ink.opacity(0.75))
                .lineLimit(1).truncationMode(.middle)
            if custom {
                Button("Auto") {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    customBinding.wrappedValue = ""
                }
                .buttonStyle(.borderless).font(.caption).foregroundColor(Brand.accent)
                .help("Back to the automatic name")
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 40)
        .background(Brand.card)
        .overlay(Rectangle().fill(Brand.rule).frame(height: 1), alignment: .bottom)
    }
}

private func credit() -> some View {
    VStack(spacing: 2) {
        Text("Created by \(Brand.author)").font(.system(size: 12, weight: .semibold, design: .serif)).foregroundColor(Brand.accent)
        Text("\(Brand.department) · \(Brand.hospital)").font(.system(size: 10)).foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, alignment: .center)
}

private func tableHead(_ text: String, width: CGFloat? = nil, alignment: Alignment = .leading) -> some View {
    Text(text.uppercased())
        .font(.system(size: 9.5, weight: .bold, design: .serif)).tracking(1.1).foregroundColor(Brand.mid)
        .frame(width: width, alignment: alignment)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
}

/// Room under the last card so nothing hides behind Eppi's walking lane.
private let laneRoom: CGFloat = 150

// MARK: - Protocol mode

struct ProtocolView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SamplesCard()
                    RunCard()
                    PrimersCard()
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .padding(.bottom, laneRoom)
            }
            .frame(width: 500)
            GeometryReader { geo in
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 14) {
                        MixCard()
                        ArrangementCard()
                        credit()
                    }
                    .frame(width: max(geo.size.width - 16, 660))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 16).padding(.trailing, 16)
                    .padding(.bottom, laneRoom)
                }
            }
        }
    }
}

struct SamplesCard: View {
    @EnvironmentObject var store: Store

    private var samplesCaption: String {
        let p = store.plan, n = p.n, per = p.samplesPerPlate
        let place: String
        switch p.activeLayout {
        case .rows: place = "One per plate row, top to bottom"
        case .columns: place = "One per plate column, left to right"
        case .primerRows: place = n == 1 ? "One per plate column, left to right" : "Each takes a block of \(n) columns"
        case .primerColumns: place = n == 1 ? "One per plate row, top to bottom" : "Each takes a block of \(n) rows"
        }
        return "\(place); more than \(per) start another plate (the layout is chosen under Plate arrangement). Tick the circle beside a sample to make it the calibrator (RQ = 1)."
    }

    var body: some View {
        let cal = store.plan.calibratorName
        Card(title: "Samples", icon: "testtube.2") {
            Text(samplesCaption)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(store.plan.samples.enumerated()), id: \.element.id) { i, s in
                let b = $store.plan.samples.row(s)
                let isCal = store.plan.calibratorID == s.id
                HStack(spacing: 8) {
                    Text(store.plan.sampleTag(i))
                        .font(.system(size: 11, weight: .bold, design: .serif)).foregroundColor(Brand.accent)
                        .lineLimit(1).fixedSize().frame(minWidth: 16)
                        .help("Where this sample goes on its plate")
                    TextField("e.g. A3_100pM", text: b.name)
                    Button { store.toggleCalibrator(s.id) } label: {
                        Image(systemName: isCal ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 12.5))
                            .foregroundColor(isCal ? Brand.accent : Color.secondary.opacity(0.45))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isCal ? "Calibrator (RQ = 1). Click to unset." : "Make this sample the calibrator")
                    if isCal { Text("calibrator").font(.caption).foregroundStyle(.secondary) }
                    Button { store.removeSample(s.id) } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(SquishStyle(on: store.motion))
                }
                .transition(.asymmetric(insertion: .scale(scale: 0.5, anchor: .leading).combined(with: .opacity), removal: .opacity))
            }
            HStack {
                FunButton(action: { store.addSample() }) {
                    Label("Add sample", systemImage: "plus.circle.fill").font(.system(size: 13, weight: .semibold)).foregroundColor(Brand.accent)
                }
                Spacer()
                Text(cal.isEmpty ? "No calibrator chosen" : "Calibrator: \(cal)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .textFieldStyle(.roundedBorder)
        .animation(store.motion ? .spring(response: 0.4, dampingFraction: 0.65) : nil, value: store.plan.samples.map { $0.id })
    }
}

struct RunCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Card(title: "Run", icon: "calendar") {
            HStack {
                Text("Title").frame(width: 92, alignment: .leading)
                TextField("365_WNT_Esc_02", text: $store.plan.title)
            }
            DatePicker("Run date", selection: $store.plan.date, displayedComponents: .date)
                .frame(maxWidth: 260, alignment: .leading)
            HStack {
                Text("Description").frame(width: 92, alignment: .leading)
                TextField("#365: 0 - 100 pM", text: $store.plan.description)
            }
            Divider()
            HStack {
                Text("Replicates").frame(width: 92, alignment: .leading)
                Stepper(value: $store.plan.replicates, in: 1...6) {
                    Text("n = \(store.plan.n)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        .contentTransition(.numericText())
                }
                .fixedSize()
                Text("wells per sample and primer").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}

struct PrimersCard: View {
    @EnvironmentObject var store: Store

    private func picker(_ name: String, _ index: Int) -> some View {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return ColorPicker("", selection: Binding(
            get: { Color(hex: store.colors.color(trimmed, index)) },
            set: { store.setColor(trimmed, hexString($0)) }), supportsOpacity: false)
            .labelsHidden()
            .disabled(trimmed.isEmpty)
            .help(trimmed.isEmpty ? "Type the gene name first" : "Colour for \(trimmed): used on the plate map and on its graph")
            .contextMenu {
                Button("Use the default colour") { store.setColor(trimmed, nil) }
            }
    }

    var body: some View {
        Card(title: "Primers", icon: "link") {
            HStack {
                picker(store.plan.referenceGene, 0)
                TextField("GAPDH", text: $store.plan.referenceGene)
                Pill(text: "REFERENCE", color: Brand.navy)
            }
            Text("The reference gene runs on every plate, in the first block. Click a colour swatch to choose that gene's colour; its graph uses the same colour.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(store.plan.genes.enumerated()), id: \.element.id) { i, g in
                let b = $store.plan.genes.row(g)
                HStack {
                    picker(g.name, i + 1)
                    TextField("Gene of interest", text: b.name)
                    Button { store.plan.genes.removeAll { $0.id == g.id } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(SquishStyle(on: store.motion))
                }
                .transition(.asymmetric(insertion: .scale(scale: 0.5, anchor: .leading).combined(with: .opacity), removal: .opacity))
            }
            Menu {
                ForEach(store.geneLibrary.filter { !store.plan.geneNames.contains($0) }, id: \.self) { name in
                    Button(name) { store.addGene(name) }
                }
                Divider()
                Button("Blank row") { store.addGene() }
                if !store.geneLibrary.isEmpty {
                    Menu("Forget saved gene") {
                        ForEach(store.geneLibrary, id: \.self) { name in
                            Button(name) { store.geneLibrary.removeAll { $0 == name } }
                        }
                    }
                }
            } label: { Label("Add primer", systemImage: "plus.circle.fill") }
                .menuStyle(.borderlessButton).fixedSize()
        }
        .textFieldStyle(.roundedBorder)
        .animation(store.motion ? .spring(response: 0.4, dampingFraction: 0.65) : nil, value: store.plan.genes.map { $0.id })
    }
}

struct MixCard: View {
    @EnvironmentObject var store: Store
    private let showSettings = State(initialValue: false)   // plain State: the @State macro plugin is not in the Command Line Tools

    private func tile(_ label: String, _ value: String, _ unit: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 16, weight: .light)).foregroundColor(Brand.accent)
                .frame(width: 36, height: 36).background(Circle().fill(Brand.pale)).overlay(Circle().stroke(Brand.rule, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased()).font(.system(size: 9, weight: .bold, design: .serif)).tracking(1.4).foregroundColor(Brand.mid)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 22, weight: .bold, design: .serif)).foregroundColor(Brand.ink)
                        .contentTransition(.numericText())
                        .animation(store.motion ? .spring(response: 0.4, dampingFraction: 0.7) : nil, value: value)
                    Text(unit).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.pale.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Brand.rule, lineWidth: 1))
    }

    private func row(_ name: String, _ recipe: Double, _ a: Double, _ b: Double?, bold: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(name).font(.system(size: 13, weight: bold ? .bold : .regular)).frame(maxWidth: .infinity, alignment: .leading)
            Text(fmtNum(recipe)).foregroundStyle(.secondary).monospacedDigit().frame(width: 70, alignment: .trailing)
            Text("\(fmtVol(a)) µL").font(.system(size: 13, weight: .semibold)).monospacedDigit().frame(width: 150, alignment: .trailing)
                .rolling(fmtVol(a), store.motion)
            if let b = b {
                Text("\(fmtVol(b)) µL").font(.system(size: 13, weight: .semibold)).monospacedDigit().frame(width: 150, alignment: .trailing)
                    .rolling(fmtVol(b), store.motion)
            }
        }
        .padding(.vertical, 3)
    }

    var body: some View {
        let p = store.plan, st = store.settings
        let wellsGene = p.geneNames.isEmpty ? p.wellsReference : p.wellsPerGene
        let showRef = !p.geneNames.isEmpty && p.wellsReference != p.wellsPerGene
        let a = p.mix(wells: wellsGene, st)
        let b = p.mix(wells: p.wellsReference, st)
        let cd = p.cdna(st)

        Card(title: "Primer mixture and cDNA", icon: "drop") {
            HStack(spacing: 12) {
                tile("Plates", "\(p.plates.count)", "× 96-well", "square.grid.3x3")
                tile("Wells per primer", "\(p.wellsPerGene)", "wells", "circle.grid.3x3")
                tile("cDNA per sample", fmtVol(cd.needed), "µL diluted", "eyedropper")
            }
            Eyebrow(text: "Mixture for each primer, in a 1.5 mL tube", color: Brand.mid, size: 9.5)
            HStack(spacing: 8) {
                tableHead("Component")
                tableHead("Recipe", width: 70, alignment: .trailing)
                tableHead(showRef ? "Each gene · \(wellsGene) wells" : "Each primer · \(wellsGene) wells", width: 150, alignment: .trailing)
                    .rolling(wellsGene, store.motion)
                if showRef { tableHead("\(p.reference) · \(p.wellsReference) wells", width: 150, alignment: .trailing).rolling(p.wellsReference, store.motion) }
            }
            Rectangle().fill(Brand.rule).frame(height: 1)
            row("Fw primer", st.fw, a.fw, showRef ? b.fw : nil)
            row("Rv primer", st.rv, a.rv, showRef ? b.rv : nil)
            row("ddW", st.water, a.water, showRef ? b.water : nil)
            row("Fast SYBR Green Master Mix", st.sybr, a.sybr, showRef ? b.sybr : nil)
            Rectangle().fill(Brand.rule).frame(height: 1)
            row("Total", st.recipeTotal, a.total, showRef ? b.total : nil, bold: true)
            Text("Total = \(fmtNum(st.mixPerWell)) µL × (wells + \(fmtNum(st.extraWells)) extra). \(showRef ? "\(p.reference) is on every plate, so its tube is larger. " : "")Pipette \(fmtNum(st.mixPerWell)) µL per well. Volumes are rounded to 0.1 µL, and to whole µL from 100 µL up.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            Eyebrow(text: "cDNA dilution, per sample", color: Brand.mid, size: 9.5).padding(.top, 4)
            HStack(spacing: 10) {
                Pill(text: "x\(fmtNum(st.dilutionFactor))", color: Brand.navy)
                Text("Stock cDNA \(fmtVol(cd.stock)) µL  +  H2O \(fmtVol(cd.water)) µL").font(.system(size: 13, weight: .semibold))
                    .rolling(fmtVol(cd.stock) + fmtVol(cd.water), store.motion)
                Text("→ \(fmtVol(st.dilutedPerWell)) µL per well, \(p.wellsPerSample) wells per sample").font(.caption).foregroundStyle(.secondary)
                    .rolling(p.wellsPerSample, store.motion)
                Spacer(minLength: 0)
            }

            DisclosureGroup("Volume settings", isExpanded: showSettings.projectedValue) {
                VStack(alignment: .leading, spacing: 6) {
                    setting("Primer mixture per well", $store.settings.mixPerWell, "µL")
                    setting("Extra wells of excess", $store.settings.extraWells, "wells")
                    setting("Recipe: Fw primer", $store.settings.fw, "parts")
                    setting("Recipe: Rv primer", $store.settings.rv, "parts")
                    setting("Recipe: ddW", $store.settings.water, "parts")
                    setting("Recipe: SYBR Green Master Mix", $store.settings.sybr, "parts")
                    setting("Undiluted cDNA per well", $store.settings.cdnaPerWell, "µL")
                    setting("Diluted cDNA per well", $store.settings.dilutedPerWell, "µL")
                }
                .padding(.top, 6)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func setting(_ label: String, _ value: Binding<Double>, _ unit: String) -> some View {
        HStack {
            Text(label).frame(width: 240, alignment: .leading)
            TextField("", value: value, format: plain).frame(width: 70)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

struct ArrangementCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let plates = store.plan.plates
        let n = store.plan.n
        let g = store.plan.genesPerPlate, per = store.plan.samplesPerPlate
        Card(title: "Plate arrangement", icon: "circle.grid.3x3") {
            LayoutPicker()
            Text("\(store.plan.activeLayout.detail(n)) Up to \(per) sample\(per == 1 ? "" : "s") and \(g) gene\(g == 1 ? "" : "s") of interest fit beside \(store.plan.reference) on one plate. Point at a well to see what goes in it.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(plates.enumerated()), id: \.offset) { k, plate in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Eyebrow(text: "Plate \(plate.number)", color: Brand.accent, size: 10.5)
                        Text("\(plate.primers.count) primer\(plate.primers.count == 1 ? "" : "s") × \(plate.samples.count) sample\(plate.samples.count == 1 ? "" : "s") · \(plate.primers.count * n * plate.samples.count) wells")
                            .font(.caption).foregroundStyle(.secondary)
                            .rolling(plate.primers.count * n * plate.samples.count, store.motion)
                    }
                    PlateArrangement(plate: plate, n: n, calibrator: store.plan.calibratorName, order: k)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// The four ways of laying samples and primers out, each with a small picture of this run's first plate
/// and the number of plates it needs.
struct LayoutPicker: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let plan = store.plan
        let active = plan.activeLayout
        let counts = Dictionary(uniqueKeysWithValues: SampleLayout.allCases.map { ($0, plan.plateCount($0)) })
        let fewest = counts.values.min() ?? 0
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Sample layout", color: Brand.accent, size: 9.5)
            HStack(spacing: 8) {
                ForEach(SampleLayout.allCases) { l in
                    tile(l, plan: plan, selected: l == active, count: counts[l] ?? 0, fewest: counts[l] == fewest && fewest < .max)
                }
            }
            Toggle(isOn: Binding(get: { store.plan.autoLayout }, set: { store.setAutoLayout($0) })) {
                Text("Always use the layout that needs the fewest plates").font(.caption)
            }
            .toggleStyle(.checkbox)
        }
        .padding(.bottom, 2)
    }

    private func tile(_ l: SampleLayout, plan: ProtocolPlan, selected: Bool, count: Int, fewest: Bool) -> some View {
        let fits = l.fits(plan.n)
        let cap = l.capacity(plan.n)
        return Button { store.setLayout(l) } label: {
            VStack(spacing: 5) {
                MiniPlate(plate: plan.plates(for: l).first, colors: store.colors)
                    .frame(width: 92, height: 62)
                Text(l.title).font(.system(size: 11, weight: .semibold)).foregroundColor(Brand.ink)
                if fits {
                    Text("\(cap.samples) × \(cap.primers - 1) gene\(cap.primers == 2 ? "" : "s")")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Text(count == 1 ? "1 plate" : "\(count) plates").font(.system(size: 11, weight: .bold)).foregroundColor(Brand.accent)
                            .rolling(count, store.motion)
                        if fewest {
                            Text("fewest").font(.system(size: 9, weight: .bold)).foregroundColor(Color(hex: "2E7D4F"))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color(hex: "DDF3E4")))
                        }
                    }
                } else {
                    Text("needs \(l == .columns ? "n ≤ 4" : "fewer replicates")").font(.system(size: 10)).foregroundColor(.secondary)
                    Text(" ").font(.system(size: 11, weight: .bold))
                }
            }
            .padding(.vertical, 8).padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? Brand.mid.opacity(0.14) : Brand.card))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(selected ? Brand.navy : Brand.rule, lineWidth: selected ? 1.6 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishStyle(on: store.motion))
        .disabled(!fits)
        .opacity(fits ? 1 : 0.45)
        .help(fits ? "\(l.title): \(l.detail(plan.n))" : "Does not fit with \(plan.n) replicates")
    }
}

/// A small plate: every well in its primer's colour, empty wells pale.
struct MiniPlate: View {
    let plate: PlateLayout?
    let colors: GeneColors

    var body: some View {
        Canvas { g, size in
            let pitch = min((size.width - 8) / 12, (size.height - 8) / 8)
            let w = pitch * 12 + 8, h = pitch * 8 + 8
            let box = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
            g.fill(Path(roundedRect: box, cornerRadius: 5), with: .color(Color(hex: "F3F6FA")))
            g.stroke(Path(roundedRect: box, cornerRadius: 5), with: .color(Color(hex: "C9D4E3")), lineWidth: 1)
            for r in 0..<8 {
                for c in 0..<12 {
                    let center = CGPoint(x: box.minX + 4 + (CGFloat(c) + 0.5) * pitch, y: box.minY + 4 + (CGFloat(r) + 0.5) * pitch)
                    let rad = pitch * 0.36
                    let dot = Path(ellipseIn: CGRect(x: center.x - rad, y: center.y - rad, width: rad * 2, height: rad * 2))
                    if let p = plate, let w = p.content(r, c) {
                        g.fill(dot, with: .color(Color(hex: colors.color(p.primers[w.primer], p.primerIndex[w.primer]))))
                    } else {
                        g.fill(dot, with: .color(Color(hex: "DCE3EC")))
                    }
                }
            }
        }
    }
}

// MARK: - Results mode

struct ResultsView: View {
    @EnvironmentObject var store: Store
    private let dropping = State(initialValue: false)

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // before any data, the qTOWER on the right is where files go in
                    if !store.results.genes.isEmpty || !store.results.extras.isEmpty { ImportCard(dropping: dropping.wrappedValue) }
                    if !store.results.genes.isEmpty { ConditionsCard() }
                    OptionsCard()
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .padding(.bottom, laneRoom)
            }
            .frame(width: 430)
            GeometryReader { geo in
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 14) {
                        if store.results.genes.isEmpty {
                            WaitingCard(height: max(460, min(620, geo.size.height - 150)), eager: dropping.wrappedValue)
                        } else {
                            GraphsCard()
                            SummaryCard()
                            PlateCheckCard()
                        }
                        credit()
                    }
                    .frame(width: max(geo.size.width - 16, 680))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 16).padding(.trailing, 16)
                    .padding(.bottom, laneRoom)
                }
            }
        }
        // files can land anywhere on this page; the qTOWER (or the drop strip, once there is data) lights up while they hover
        .onDrop(of: [UTType.fileURL], isTargeted: dropping.projectedValue) { providers in
            let found = DroppedURLs()
            let group = DispatchGroup()
            for p in providers {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { found.add(url) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                let urls = found.all
                if !urls.isEmpty { store.dropFiles(urls) }
            }
            return true
        }
    }
}

/// Collects the files of one drop, which arrive one by one on background threads.
final class DroppedURLs {
    private var urls: [URL] = []
    private let lock = NSLock()
    func add(_ u: URL) { lock.lock(); urls.append(u); lock.unlock() }
    var all: [URL] { lock.lock(); defer { lock.unlock() }; return urls.sorted { $0.path < $1.path } }
}

/// Where files are opened or dropped: one .xls per gene, a run folder, a workbook, or saved data.
struct DropArea: View {
    @EnvironmentObject var store: Store
    let dropping: Bool
    let compact: Bool

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 17)).foregroundColor(Brand.accent)
                    Text("Drop more files or a folder to add genes").font(.system(size: 12, weight: .medium)).foregroundColor(Brand.ink)
                    Spacer(minLength: 4)
                    openButton(small: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
            } else {
                VStack(spacing: 9) {
                    ZStack {
                        Circle().fill(Brand.card).frame(width: 58, height: 58)
                            .shadow(color: Brand.navy.opacity(0.15), radius: 6, y: 2)
                        Image(systemName: dropping ? "arrow.down.circle.fill" : "square.and.arrow.down.on.square")
                            .font(.system(size: 24, weight: .medium)).foregroundColor(Brand.accent)
                    }
                    Text(dropping ? "Let go to open" : "Drop qTOWER files or a run folder")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(Brand.ink)
                    Text("One .xls per gene, the whole run folder, a workbook with one sheet per gene, or a .qpcrdata file you saved.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    openButton(small: false).padding(.top, 2)
                }
                .padding(.vertical, 18).padding(.horizontal, 14)
            }
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(dropping ? Brand.mid.opacity(0.12) : Brand.pale.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .stroke(dropping ? Brand.mid : Brand.navy.opacity(0.28), style: StrokeStyle(lineWidth: dropping ? 2 : 1.4, dash: [7, 5])))
        .scaleEffect(dropping && store.motion ? 1.02 : 1)
        .animation(store.motion ? .spring(response: 0.3, dampingFraction: 0.7) : nil, value: dropping)
    }

    private func openButton(small: Bool) -> some View {
        FunButton(action: { store.openResults() }) {
            Label("Open…", systemImage: "folder.fill").font(.system(size: small ? 12 : 13, weight: .semibold))
                .foregroundColor(.white).padding(.horizontal, small ? 10 : 14).padding(.vertical, small ? 5 : 7)
                .background(Capsule().fill(Brand.navy))
        }
        .help("Open qTOWER exports, a run folder, or a saved .qpcrdata file")
    }
}

/// Before any data is opened: one card where the files go in. Drop them onto the qTOWER (or anywhere
/// on the page) or press Open; the qTOWER swallows them and the import plays.
struct WaitingCard: View {
    @EnvironmentObject var store: Store
    let height: CGFloat
    var eager = false

    var body: some View {
        Card(title: "qTOWER data", icon: "tray.and.arrow.down") {
            HStack(alignment: .center, spacing: 12) {
                Text("Drop your qTOWER files or the run folder onto the qTOWER, or open them: one .xls per gene, the whole run folder, a workbook with one sheet per gene, or a .qpcrdata file you saved.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                FunButton(action: { store.openResults() }) {
                    Label("Open…", systemImage: "folder.fill").font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white).padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(Brand.navy))
                }
                .help("Open qTOWER exports, a run folder, or a saved .qpcrdata file")
            }
            if !store.importMessage.isEmpty {
                Label(store.importMessage, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundColor(Color(hex: flagLine)).fixedSize(horizontal: false, vertical: true)
            }
            // no drop shadow: a shadow under a moving picture is redrawn every frame
            RunSandbox(active: store.ambient, eager: eager && store.motion, gulp: store.gulp, onGulped: { store.finishGulp($0) })
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Brand.mid, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .opacity(eager ? 1 : 0)
                        .animation(store.motion ? .easeOut(duration: 0.2) : nil, value: eager))
                .help("Drop qTOWER files here, or click the qTOWER to poke it")
        }
    }
}

struct ImportCard: View {
    @EnvironmentObject var store: Store
    let dropping: Bool

    var body: some View {
        let empty = store.results.genes.isEmpty
        Card(title: "qTOWER data", icon: "tray.and.arrow.down") {
            DropArea(dropping: dropping, compact: !empty)
            if !empty {
                Text("The genes read from your qTOWER files. Recolour, reorder or remove them here and the graphs follow. Save data keeps this data, your labels and graph settings in one file to reopen later without the original exports.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if !store.results.genes.isEmpty || !store.results.extras.isEmpty {
                    FunButton(action: { store.saveData() }) {
                        Label("Save data…", systemImage: "square.and.arrow.down").font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Brand.accent).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().stroke(Brand.navy.opacity(0.4), lineWidth: 1))
                    }
                    .help("Save the imported data, labels and graph settings as a .qpcrdata file")
                    FunButton(action: { store.clearResults() }) {
                        Label("Clear", systemImage: "arrow.counterclockwise").font(.system(size: 13)).foregroundColor(Brand.accent)
                    }
                }
                Spacer()
            }
            if !store.importMessage.isEmpty {
                Text(store.importMessage).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !store.results.genes.isEmpty {
                HStack(spacing: 8) {
                    tableHead("Gene")
                    tableHead("Reference", width: 80)
                    tableHead("Plotted", width: 60, alignment: .trailing)
                    Spacer().frame(width: 60)
                }
                Rectangle().fill(Brand.rule).frame(height: 1)
                ForEach(Array(store.results.genes.enumerated()), id: \.element.id) { i, g in
                    let plotted = g.samples.filter { store.results.value(g, $0.name, store.options) != nil }.count
                    let flagged = g.samples.filter { store.results.value(g, $0.name, store.options)?.low == true }.count
                    HStack(spacing: 8) {
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: store.resultColor(g.name, i)) },
                            set: { store.setColor(g.name, hexString($0)) }), supportsOpacity: false)
                            .labelsHidden()
                            .help("Colour for \(g.name)'s graph (also used for it on the plate map)")
                            .contextMenu { Button("Use the default colour") { store.setColor(g.name, nil) } }
                        Text(g.name).font(.system(size: 13, weight: .semibold))
                        if g.recalculated { Pill(text: "RECALCULATED", color: .orange).help("This file had no normalised expression, so ΔΔCt was calculated from the Ct values.") }
                        Spacer(minLength: 0)
                        Text(g.reference).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                        if flagged > 0 {
                            Text("\(flagged) red").font(.system(size: 10, weight: .semibold)).foregroundColor(Color(hex: flagLine))
                                .help("\(flagged) condition\(flagged == 1 ? "" : "s") rest on too few wells and are marked red")
                        }
                        Text("\(plotted) / \(g.samples.count)").font(.system(size: 12)).monospacedDigit().frame(width: 44, alignment: .trailing)
                        Button { store.moveGene(g.id, by: -1) } label: { Image(systemName: "chevron.up").font(.system(size: 10, weight: .semibold)) }
                            .buttonStyle(SquishStyle(on: store.motion)).foregroundColor(Brand.accent).disabled(i == 0).frame(width: 14)
                            .help("Move this gene earlier in the table and graphs")
                        Button { store.moveGene(g.id, by: 1) } label: { Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)) }
                            .buttonStyle(SquishStyle(on: store.motion)).foregroundColor(Brand.accent).disabled(i == store.results.genes.count - 1).frame(width: 14)
                            .help("Move this gene later in the table and graphs")
                        Button { store.results.genes.removeAll { $0.id == g.id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(SquishStyle(on: store.motion)).frame(width: 16)
                    }
                }
            }
            if !store.results.extras.isEmpty {
                Text("ALSO EXPORTED AS THEIR OWN TABS").font(.system(size: 10, weight: .bold, design: .serif)).tracking(1.2)
                    .foregroundColor(Brand.accent).padding(.top, 4)
                ForEach(store.results.extras) { e in
                    HStack(spacing: 8) {
                        Image(systemName: e.melt ? "thermometer.medium" : "tablecells")
                            .font(.system(size: 13)).foregroundColor(Brand.mid).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.name).font(.system(size: 12.5, weight: .semibold)).foregroundColor(Brand.ink)
                            let pics = e.layout?.pictures.count ?? 0
                            Text("\(e.source) · \(e.rows.count) rows" + (pics > 0 ? " · \(pics) picture\(pics == 1 ? "" : "s")" : "")).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button { store.results.extras.removeAll { $0.id == e.id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(SquishStyle(on: store.motion)).frame(width: 16)
                        .help("Leave this tab out of the export")
                    }
                }
            }
        }
    }
}

/// Lets a condition be shown under a tidier label, the way the lab retypes them on the Graph sheet.
struct ConditionsCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Card(title: "Condition labels", icon: "tag") {
            Text("Type a label to show instead of the sample name on the table and graphs, e.g. 100 pM. Leave empty to keep the name.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(store.results.conditions, id: \.self) { c in
                HStack {
                    Text(c).font(.system(size: 12, weight: .medium)).lineLimit(1).frame(width: 130, alignment: .leading)
                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                    TextField(c, text: Binding(get: { store.results.labels[c] ?? "" }, set: { store.results.labels[c] = $0 }))
                }
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}

struct OptionsCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Card(title: "Graph options", icon: "slider.horizontal.3") {
            HStack {
                Text("X-axis title").frame(width: 110, alignment: .leading)
                TextField("e.g. PG-008 (pM)", text: $store.options.xTitle)
            }
            HStack {
                Text("Y-axis title").frame(width: 110, alignment: .leading)
                TextField("RQ", text: $store.options.yTitle)
            }
            HStack {
                Text("Mark red").frame(width: 110, alignment: .leading)
                Stepper(value: $store.options.minReplicates, in: 1...6) {
                    Text("if fewer than \(store.options.minReplicates) well\(store.options.minReplicates == 1 ? "" : "s") gave a Ct")
                        .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                }
                .fixedSize()
                Spacer()
            }
            Toggle("Dashed line at RQ = 1 (the calibrator)", isOn: $store.options.refLine)
            Toggle("Blank row between groups (A3_…, C2_…)", isOn: $store.options.groupGap)
            Divider()
            Eyebrow(text: "Lines at the top of the Graph sheet", color: Brand.mid, size: 9.5)
            ForEach(0..<4, id: \.self) { i in
                TextField(i == 0 ? "Title, e.g. #365_d11" : "Note", text: $store.options.notes[i])
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}

struct SummaryCard: View {
    @EnvironmentObject var store: Store
    private let ns = Namespace()

    /// Fixed decimals, so a column of numbers lines up: two, or three for fold changes under 1.
    private static func fmt(_ v: Double, _ view: SummaryView) -> String {
        String(format: view == .fold && abs(v) < 1 ? "%.3f" : "%.2f", v)
    }

    /// "2⁻ΔΔCt" with the exponent raised.
    static func title(_ v: SummaryView, size: CGFloat, weight: Font.Weight) -> Text {
        guard v == .fold else { return Text(v.title).font(.system(size: size, weight: weight)) }
        return Text("2").font(.system(size: size, weight: weight)) + Text("−ΔΔCt").font(.system(size: size * 0.72, weight: weight)).baselineOffset(size * 0.42)
    }

    var body: some View {
        let rs = store.results, opt = store.options
        let view = opt.summaryView
        let rows = rs.rows(opt)
        Card(title: "Summary table", icon: "tablecells") {
            HStack(spacing: 10) {
                viewPicker(view)
                Spacer(minLength: 8)
                copyMenu(view)
            }
            formulaStrip(view)
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        tableHead("Conditions", width: 116)
                        ForEach(Array(rs.genes.enumerated()), id: \.element.id) { i, g in
                            VStack(alignment: .trailing, spacing: 1) {
                                HStack(spacing: 5) {
                                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: store.resultColor(g.name, i))).frame(width: 9, height: 9)
                                    Text(g.name).font(.system(size: 11, weight: .bold)).foregroundColor(Brand.ink)
                                }
                                (view == .ct ? Text("gene · \(g.reference.isEmpty ? "reference" : g.reference)").font(.system(size: 9.5, weight: .medium))
                                             : Self.title(view, size: 9.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 146, alignment: .trailing)
                        }
                    }
                    .padding(.bottom, 5)
                    Rectangle().fill(Brand.rule).frame(height: 1)
                    let lit = store.spotlitConditions
                    let strays = rs.replicateFlags(limit: opt.replicateLimit)
                    ForEach(Array(rows.enumerated()), id: \.offset) { k, cond in
                        if let cond = cond {
                            let on = lit?.contains(cond) ?? false
                            HStack(spacing: 0) {
                                Text(rs.label(cond)).font(.system(size: 12, weight: on ? .bold : .medium)).foregroundColor(on ? Brand.accent : Brand.ink)
                                    .lineLimit(1).frame(width: 116, alignment: .leading)
                                ForEach(rs.genes) { g in
                                    cell(g, cond, view, strays["\(cond)|\(g.name)"] ?? [])
                                        .font(.system(size: 12)).monospacedDigit()
                                        .overlay(alignment: .leading) {
                                            if let ws = strays["\(cond)|\(g.name)"], !ws.isEmpty {
                                                Circle().fill(Color(hex: amberHex)).frame(width: 7, height: 7)
                                                    .shadow(color: Color(hex: amberHex).opacity(0.9), radius: 3)
                                                    .offset(x: -12)
                                                    .help("Stray replicate" + (ws.count == 1 ? "" : "s") + ": " + ws.map { "\($0.well) \($0.target) Ct \(fmtNum($0.ct ?? 0, 2)) (\(String(format: "%+.2f", $0.offBy ?? 0)))" }.joined(separator: "; "))
                                            }
                                        }
                                        .frame(width: 146, alignment: .trailing)
                                }
                            }
                            .padding(.vertical, view == .relative ? 4 : 6)
                            .background(on ? Brand.mid.opacity(0.15) : (k % 2 == 1 ? Brand.pale.opacity(0.35) : Color.clear))
                            .opacity(lit == nil || on ? 1 : 0.32)
                            .contentShape(Rectangle())
                            .onTapGesture { store.toggleSpotlight(store.spotlightKey(for: cond)) }
                            .help(on ? "Click to clear the spotlight" : "Click to spotlight this condition in every graph")
                        } else {
                            Spacer().frame(height: 10)
                        }
                    }
                }
                .id(view)
                .transition(.opacity)
            }
        }
    }

    // MARK: pieces

    /// Relative expression · Ct · ΔCt · ΔΔCt · 2^−ΔΔCt, with the highlight sliding to the chosen one.
    private func viewPicker(_ current: SummaryView) -> some View {
        HStack(spacing: 2) {
            ForEach(SummaryView.allCases) { v in
                let on = v == current
                Button {
                    store.tap(.alignment)
                    withAnimation(store.motion ? .spring(response: 0.38, dampingFraction: 0.78) : nil) { store.options.summaryView = v }
                } label: {
                    Self.title(v, size: 12, weight: on ? .bold : .semibold)
                        .foregroundColor(on ? .white : Brand.accent)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background {
                            if on { Capsule().fill(Brand.navy).matchedGeometryEffect(id: "pill", in: ns.wrappedValue) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(SquishStyle(on: store.motion))
            }
        }
        .padding(3)
        .background(Capsule().fill(Brand.pale))
        .overlay(Capsule().stroke(Brand.rule, lineWidth: 1))
    }

    /// How the numbers in this view are worked out, and the calibrator they are taken against.
    private func formulaStrip(_ view: SummaryView) -> some View {
        let ref = store.results.genes.first?.reference ?? "GAPDH"
        let text: String
        switch view {
        case .relative: text = "Normalised expression from qTOWER, ± SD. Red: fewer than \(store.options.minReplicates) wells gave a Ct (count beside it); grey: no Ct."
        case .ct: text = "Mean Ct of the gene's wells, with the mean Ct of the same sample's \(ref) wells beneath."
        case .dct: text = store.results.hasFileDCt
            ? "ΔCt copied exactly from qTOWER's dCt column (Ct \(ref) − Ct gene), nothing recalculated or rounded. qTOWER gives one value per sample; higher means more transcript."
            : "These files have no dCt column, so there is no ΔCt to copy. qTOWER's gene exports carry one."
        case .ddct: text = "qTOWER does not export ΔΔCt, so it is worked out for each well from the Ct columns: (Ct gene − mean Ct \(ref)) − the calibrator's mean of the same."
        case .fold: text = "2^−ΔΔCt = fold change against the calibrator, for each well; shown as the mean of the wells ± SD, as Prism plots it. qTOWER's normalised expression does the same from the mean Cts, so it can differ a little."
        }
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: view == .relative ? "chart.bar.xaxis" : "function")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(Brand.accent)
                .frame(width: 26, height: 26).background(Circle().fill(Brand.card))
            Text(text).font(.system(size: 11.5)).foregroundColor(Brand.ink.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if view == .ddct || view == .fold { calibratorMenu() }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.pale.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Brand.rule, lineWidth: 1))
        .id(view)
        .transition(.opacity)
    }

    private func calibratorMenu() -> some View {
        let rs = store.results, opt = store.options
        let auto = Set(rs.genes.compactMap { rs.calibrator($0, ResultsOptions()) })
        let autoName = auto.count == 1 ? auto.first! : "per gene"
        return Menu {
            Button { store.options.deltaCalibrator = "" } label: {
                if opt.deltaCalibrator.isEmpty { Label("As in qTOWER (\(autoName))", systemImage: "checkmark") } else { Text("As in qTOWER (\(autoName))") }
            }
            Divider()
            ForEach(rs.conditions, id: \.self) { c in
                Button { store.options.deltaCalibrator = c } label: {
                    if opt.deltaCalibrator == c { Label(rs.label(c), systemImage: "checkmark") } else { Text(rs.label(c)) }
                }
            }
        } label: {
            Text("Calibrator: " + (opt.deltaCalibrator.isEmpty ? autoName : rs.label(opt.deltaCalibrator)))
                .font(.system(size: 11.5, weight: .semibold))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("The sample every ΔCt is held against. As in qTOWER, the numbers match its normalised expression.")
    }

    /// Ready-to-paste tables for GraphPad Prism, put on the clipboard.
    private func copyMenu(_ view: SummaryView) -> some View {
        let rs = store.results, opt = store.options
        let perWell = view != .relative
        return Menu {
            Text(view.quantity)
            if view == .dct {
                Button("Grouped table · ΔCt exactly as in qTOWER") { copy(rs.prismFileDCt(opt), "qTOWER's ΔCt, one value per sample,") }
                    .disabled(!rs.hasFileDCt)
            } else {
                Button("Grouped table · replicates side by side") { copy(rs.prismGrouped(view, opt), "a grouped table with \(rs.maxReplicates) replicates side by side") }
                    .disabled(!perWell || view == .ct)
                Button("Grouped table · mean, SD and N") { copy(rs.prismMeanSD(view, opt), "a grouped table of mean, SD and N") }
                Divider()
                ForEach(rs.genes) { g in
                    Button("Column table · \(g.name)") { copy(rs.prismColumn(g, view, opt), "a column table for \(g.name)") }
                        .disabled(!perWell)
                }
            }
            Divider()
            Button("Mean Ct of each gene and its reference") { copy(rs.prismCt(opt), "the mean Cts") }
        } label: {
            Label("Copy for Prism", systemImage: "doc.on.clipboard").font(.system(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Copy this table as GraphPad Prism takes it: click the first title cell of a Prism table and paste")
    }

    private func copy(_ rows: [[String]], _ what: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tsv(rows), forType: .string)
        store.tap(.levelChange)
        store.showToast("Copied \(what) for Prism. Click the first title cell in Prism and paste.")
    }

    // MARK: cells

    @ViewBuilder private func cell(_ g: GeneResult, _ cond: String, _ view: SummaryView, _ strays: [PlateWell]) -> some View {
        let rs = store.results, opt = store.options
        switch view {
        case .relative:
            if let v = rs.value(g, cond, opt) {
                if v.low {
                    Text("\(fmtNum(v.value, 2)) ± \(fmtNum(v.sd, 2)) (\(v.counted)/\(v.wells))")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: flagLine))
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: flagFill).opacity(0.7)))
                        .help("Only \(v.counted) of \(v.wells) wells gave a Ct")
                } else {
                    Text("\(Self.fmt(v.value, .relative)) ± \(Self.fmt(v.sd, .relative))").foregroundColor(Brand.ink)
                }
            } else if let s = g.sample(cond) {
                Text("\(s.cts.count)/\(s.replicates) Ct").foregroundStyle(.tertiary)
            } else {
                Text("–").foregroundStyle(.tertiary)
            }
        case .ct:
            if let d = rs.delta(g, cond, opt), let ct = d.ct {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Self.fmt(ct, .ct)).font(.system(size: 12, weight: .semibold)).foregroundColor(Brand.ink)
                    Text("\(g.reference.isEmpty ? "ref" : g.reference) \(d.refCt.map { Self.fmt($0, .ct) } ?? "–")")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            } else {
                Text(g.sample(cond) == nil ? "–" : "no Ct").foregroundStyle(.tertiary)
            }
        case .dct:
            // qTOWER's own number, as the file has it
            let vals = rs.fileDCt(g, cond)
            if !vals.isEmpty {
                Text(vals.map(exactNumber).joined(separator: " / "))
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit()).foregroundColor(Brand.ink)
                    .help("qTOWER dCt (\(g.reference.isEmpty ? "reference" : g.reference) − \(g.name)), as in \(g.source)")
            } else {
                Text(g.sample(cond) == nil ? "–" : "n.d.").foregroundStyle(.tertiary)
                    .help(g.sample(cond) == nil ? "" : "No dCt for this sample in \(g.source)")
            }
        default:
            let d = rs.delta(g, cond, opt)
            let vals = d?.values(view) ?? []
            if let s = meanSD(vals) {
                // a well that strays from its partners shows in amber
                let strayCts = Set(strays.filter { !$0.isRef }.compactMap { $0.ct })
                let cts = g.sample(cond)?.cts ?? []
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Self.fmt(s.mean, view)) ± \(Self.fmt(s.sd, view))").font(.system(size: 12, weight: .semibold)).foregroundColor(Brand.ink)
                    HStack(spacing: 6) {
                        ForEach(Array(vals.enumerated()), id: \.offset) { i, v in
                            let stray = i < cts.count && strayCts.contains(cts[i])
                            Text(Self.fmt(v, view)).font(.system(size: 10, weight: stray ? .bold : .regular, design: .monospaced))
                                .foregroundColor(stray ? Color(hex: "B26B00") : Brand.chartGrey)
                        }
                    }
                }
            } else if d != nil && d?.calibrator == nil {
                Text("no calibrator").font(.system(size: 11)).foregroundStyle(.tertiary)
                    .help("The calibrator has no Ct for this gene; pick another one above")
            } else {
                Text(g.sample(cond) == nil ? "–" : "no Ct").foregroundStyle(.tertiary)
            }
        }
    }
}

struct GraphsCard: View {
    @EnvironmentObject var store: Store

    private func spotName(_ key: String) -> String {
        key.hasPrefix("c:") ? store.results.label(String(key.dropFirst(2))) : String(key.dropFirst(2))
    }

    private func bar(_ v: (value: Double, sd: Double, low: Bool, counted: Int, wells: Int)?) -> BarValue? {
        v.map { BarValue(value: $0.value, sd: $0.sd, low: $0.low, counted: $0.counted, wells: $0.wells) }
    }

    var body: some View {
        let rs = store.results, opt = store.options
        let groups = rs.groups
        let comparing = opt.compare
        let cmp = comparing ? rs.comparison(opt) : nil
        Card(title: "Graphs", icon: "chart.bar") {
            HStack(spacing: 10) {
                Picker("", selection: Binding(get: { opt.compare }, set: { store.setCompare($0) })) {
                    Text("By condition").tag(false)
                    Text("Compare two groups").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 290)
                Spacer()
                if let s = store.spotlight {
                    Button { store.toggleSpotlight(nil) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "light.max").font(.system(size: 11, weight: .bold))
                            Text("Spotlight: " + spotName(s)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                        }
                        .foregroundColor(.white).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.mid))
                    }
                    .buttonStyle(SquishStyle(on: store.motion))
                    .help("Clear the spotlight")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            if comparing {
                GroupBuilder()
            } else {
                Text(groups.count < 2
                     ? "One chart per gene with SD error bars. Point at a bar for the exact numbers; click it to spotlight that condition in every graph and the table. A red dashed bar rests on too few wells."
                     : "One chart per gene with SD error bars, grouped by \(groups.joined(separator: " / ")). Point at a bar for the exact numbers; click it to spotlight that condition in every graph and the table. A red dashed bar rests on too few wells.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if comparing && cmp == nil {
                HStack(spacing: 10) {
                    Image(systemName: "hand.point.up.left").font(.system(size: 18)).foregroundColor(Brand.mid)
                    Text("Pick at least one condition for each group above, and the graphs appear here.")
                        .font(.system(size: 12.5)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 14)], spacing: 14) {
                ForEach(Array(rs.genes.enumerated()), id: \.element.id) { i, g in
                    let hex = store.resultColor(g.name, i)
                    let plain = byCondition(g)
                    let paired = pairs.map { compared(g, $0) }
                    if comparing {
                        if let cmp = pairs, let cats = paired {
                            MatureChart(title: g.name, colorHex: hex, categories: cats,
                                        series: [BarSeries(name: cmp.nameA, fill: hex), BarSeries(name: cmp.nameB, fill: tintHex(hex, 0.55))],
                                        xTitle: opt.xTitle, yTitle: opt.yTitle, refLine: opt.refLine, brackets: false,
                                        alt: ChartAlt(categories: plain.cats, seriesCount: 1, brackets: plain.brackets))
                                .frame(height: 300)
                        }
                    } else {
                        MatureChart(title: g.name, colorHex: hex, categories: plain.cats, series: [BarSeries(name: g.name, fill: hex)],
                                    xTitle: opt.xTitle, yTitle: opt.yTitle, refLine: opt.refLine, brackets: plain.brackets,
                                    alt: paired.map { ChartAlt(categories: $0, seriesCount: 2, brackets: false) })
                            .frame(height: 300)
                    }
                }
            }
        }
    }

    /// One bar per condition, grouped under brackets when the names allow it.
    private func byCondition(_ g: GeneResult) -> (cats: [BarCategory?], brackets: Bool) {
        let rs = store.results, opt = store.options
        let rows = rs.rows(opt)
        let brackets = rs.groups.count >= 2 && rows.compactMap { $0 }.allSatisfy { ResultSet.split($0) != nil }
        let cats: [BarCategory?] = rows.map { c in
            guard let c = c else { return nil }
            let custom = rs.labels[c]?.trimmingCharacters(in: .whitespaces) ?? ""
            let split = ResultSet.split(c)
            let label = !custom.isEmpty ? custom : (brackets ? split?.level ?? c : c)
            let v = rs.value(g, c, opt)
            return BarCategory(label: label, group: brackets ? split?.group : nil, name: rs.label(c),
                               cells: [bar(v)], measured: [g.sample(c) != nil && v == nil], key: "c:" + c, ids: [c])
        }
        return (cats, brackets)
    }

    /// Group A beside group B for each pair.
    private func compared(_ g: GeneResult, _ cmp: GroupComparison) -> [BarCategory?] {
        let rs = store.results, opt = store.options
        return cmp.pairs.map { p in
            let va = p.a.flatMap { rs.value(g, $0, opt) }, vb = p.b.flatMap { rs.value(g, $0, opt) }
            return BarCategory(label: p.label, group: nil, name: p.label, cells: [bar(va), bar(vb)],
                               measured: [p.a.flatMap { g.sample($0) } != nil && va == nil, p.b.flatMap { g.sample($0) } != nil && vb == nil],
                               key: "p:" + p.label, ids: [p.a, p.b])
        }
    }

    private var pairs: GroupComparison? { store.results.comparison(store.options) }
}

/// Choosing the two groups: every condition is a chip; a click puts it in group A, the next in group B,
/// the next leaves it out. The groups can be named, or filled in one go from names like A3_… and C2_….
struct GroupBuilder: View {
    @EnvironmentObject var store: Store
    static let colorA = Brand.navy
    static let colorB = Color(hex: "9DB8DE")

    var body: some View {
        let rs = store.results, opt = store.options
        let (inA, inB) = rs.compareMembers(opt)
        let cmp = rs.comparison(opt)
        let groups = rs.compareStems
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                nameField(Self.colorA, "A", text: Binding(get: { store.options.nameA }, set: { store.options.nameA = $0 }),
                          placeholder: cmp?.nameA ?? "Group A")
                Text("vs").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                nameField(Self.colorB, "B", text: Binding(get: { store.options.nameB }, set: { store.options.nameB = $0 }),
                          placeholder: cmp?.nameB ?? "Group B")
                Spacer(minLength: 6)
                if groups.count >= 2 {
                    Menu {
                        ForEach(groups, id: \.self) { x in
                            ForEach(groups.filter { $0 != x }, id: \.self) { y in
                                Button("\(x)  vs  \(y)") { store.fillGroups(x, y) }
                            }
                        }
                    } label: {
                        Label("From names", systemImage: "wand.and.stars").font(.system(size: 12, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Put one whole series in each group (A3 vs C2, SAG vs SAG+22(S)), paired by dose")
                }
                Menu {
                    ForEach(PairMode.allCases) { m in
                        Button { store.setPairBy(m) } label: {
                            if opt.pairBy == m { Label(m.title, systemImage: "checkmark") } else { Text(m.title) }
                        }
                    }
                } label: {
                    Text("Pair by: \(opt.pairBy == .auto ? "Auto (\(cmp?.mode.title.lowercased() ?? "dose"))" : opt.pairBy.title)")
                        .font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("How bars are matched: by dose (0 → 1 µM, however it is written), by matching names, or in the order you click")
                Button { store.clearGroups() } label: {
                    Label("Clear", systemImage: "xmark.circle").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(inA.isEmpty && inB.isEmpty)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(rs.conditions, id: \.self) { c in
                    chip(c, side: inA.contains(c) ? "A" : (inB.contains(c) ? "B" : nil))
                }
            }
            Text("Click a condition to put it in group A, again for group B, once more to leave it out. " + pairing(cmp) + " Group A is drawn in the gene's colour, group B lighter; exported as its own \"Compare\" sheet.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Brand.pale.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Brand.rule, lineWidth: 1))
    }

    private func pairing(_ cmp: GroupComparison?) -> String {
        guard let cmp else { return "Bars are paired by dose when the names carry one (SAG_0.1uM beside SAG+22(S)_0.1uM)." }
        let ends = cmp.pairs.count > 1 ? "\(cmp.pairs.first!.label) → \(cmp.pairs.last!.label)" : cmp.pairs.first?.label ?? ""
        switch cmp.mode {
        case .dose: return "Bars are paired by dose, \(ends)."
        case .name: return "Bars are paired by matching names (\(ends))."
        default: return "Bars are paired in the order you click them."
        }
    }

    private func nameField(_ color: Color, _ letter: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 6) {
            Text(letter).font(.system(size: 10.5, weight: .heavy)).foregroundColor(letter == "A" ? .white : Brand.navy)
                .frame(width: 18, height: 18).background(RoundedRectangle(cornerRadius: 4).fill(color))
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder).frame(width: 130)
        }
    }

    private func chip(_ c: String, side: String?) -> some View {
        let label = store.results.label(c)
        return Button { store.cycleGroup(c) } label: {
            HStack(spacing: 6) {
                Text(side ?? "–").font(.system(size: 10, weight: .heavy))
                    .foregroundColor(side == "A" ? Brand.navy : (side == "B" ? Brand.navy : .secondary))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(side == nil ? Color.secondary.opacity(0.12) : Color.white.opacity(side == "A" ? 0.9 : 0.75)))
                Text(label).font(.system(size: 11.5, weight: side == nil ? .regular : .semibold)).lineLimit(1).truncationMode(.middle)
                    .foregroundColor(side == "A" ? .white : Brand.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(side == "A" ? Self.colorA : (side == "B" ? Self.colorB : Brand.card)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(side == nil ? Brand.rule : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishStyle(on: store.motion))
        .help(side == "A" ? "In group A. Click to move it to group B." : (side == "B" ? "In group B. Click to leave it out." : "Click to put it in group A."))
    }
}

