import SwiftUI
import AppKit

// MARK: - Bench mode
//
// The protocol as a full-screen checklist to work through at the bench, in large type on the splash's
// navy: make the primer mixtures, dilute the cDNA, plate the cDNA, plate the primer mixtures, seal and
// spin, run. Each line is ticked off with a click or the space bar; the plate map beside it lights the
// wells the current line is about. Arrow keys move between steps; Esc leaves.

struct BenchItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    var plate: Int? = nil         // index into plan.plates
    var wells: Set<Int> = []      // row × 12 + column
}

struct BenchStep: Identifiable {
    let id: String
    let title: String
    let note: String
    let icon: String
    let items: [BenchItem]
}

/// "A1–H3" for a block of wells, otherwise how many there are.
func wellRange(_ wells: Set<Int>) -> String {
    guard let first = wells.min(), let last = wells.max() else { return "" }
    let rows = wells.map { $0 / 12 }, cols = wells.map { $0 % 12 }
    let r0 = rows.min()!, r1 = rows.max()!, c0 = cols.min()!, c1 = cols.max()!
    if (r1 - r0 + 1) * (c1 - c0 + 1) == wells.count {
        return wells.count == 1 ? "\(rowLetters[first / 12])\(first % 12 + 1)"
            : "\(rowLetters[r0])\(c0 + 1)–\(rowLetters[r1])\(c1 + 1)"
    }
    return "\(wells.count) wells from \(rowLetters[first / 12])\(first % 12 + 1) to \(rowLetters[last / 12])\(last % 12 + 1)"
}

extension Store {
    var benchSteps: [BenchStep] {
        let p = plan, st = settings
        let plates = p.plates
        let wellsGene = p.geneNames.isEmpty ? p.wellsReference : p.wellsPerGene
        let a = p.mix(wells: wellsGene, st), b = p.mix(wells: p.wellsReference, st)
        let cd = p.cdna(st)
        func mixLine(_ m: (fw: Double, rv: Double, water: Double, sybr: Double, total: Double)) -> String {
            "Fw \(fmtVol(m.fw)) · Rv \(fmtVol(m.rv)) · ddW \(fmtVol(m.water)) · SYBR \(fmtVol(m.sybr)) µL   →   \(fmtVol(m.total)) µL"
        }
        var steps: [BenchStep] = []

        var mixes = [BenchItem(id: "mix:ref", title: "\(p.reference)  (reference)", detail: mixLine(b))]
        mixes += p.geneNames.map { BenchItem(id: "mix:\($0)", title: $0, detail: mixLine(a)) }
        steps.append(BenchStep(id: "mix", title: "Make the primer mixtures", note: "One 1.5 mL tube per primer. Vortex, spin down, keep on ice.",
                               icon: "testtube.2", items: mixes))

        steps.append(BenchStep(id: "cdna", title: "Dilute the cDNA ×\(fmtNum(st.dilutionFactor))",
                               note: "Per sample: stock cDNA plus water. Mix and spin down. Each sample needs \(fmtVol(cd.needed)) µL.",
                               icon: "eyedropper",
                               items: p.sampleNames.map { BenchItem(id: "cdna:\($0)", title: $0, detail: "stock \(fmtVol(cd.stock)) µL  +  H₂O \(fmtVol(cd.water)) µL") }))

        var cdnaPlate: [BenchItem] = [], mixPlate: [BenchItem] = []
        for (k, plate) in plates.enumerated() {
            for (s, name) in plate.samples.enumerated() {
                var wells = Set<Int>()
                for b in plate.primers.indices { for r in 0..<plate.n { let w = plate.well(s, b, r); wells.insert(w.r * 12 + w.c) } }
                cdnaPlate.append(BenchItem(id: "pc:\(k):\(name)", title: (plates.count > 1 ? "Plate \(plate.number) · " : "") + name,
                                           detail: "\(fmtVol(st.dilutedPerWell)) µL into \(wellRange(wells))", plate: k, wells: wells))
            }
            for (b, primer) in plate.primers.enumerated() {
                var wells = Set<Int>()
                for s in plate.samples.indices { for r in 0..<plate.n { let w = plate.well(s, b, r); wells.insert(w.r * 12 + w.c) } }
                mixPlate.append(BenchItem(id: "pm:\(k):\(primer)", title: (plates.count > 1 ? "Plate \(plate.number) · " : "") + primer + (b == 0 ? "  (reference)" : ""),
                                          detail: "\(fmtNum(st.mixPerWell)) µL into \(wellRange(wells))", plate: k, wells: wells))
            }
        }
        steps.append(BenchStep(id: "pc", title: "Put the diluted cDNA in the plate", note: "White 96-well plate, \(fmtVol(st.dilutedPerWell)) µL per well.",
                               icon: "square.grid.3x3.topleft.filled", items: cdnaPlate))
        steps.append(BenchStep(id: "pm", title: "Add the primer mixtures", note: "\(fmtNum(st.mixPerWell)) µL per well, on top of the cDNA.",
                               icon: "drop.fill", items: mixPlate))
        steps.append(BenchStep(id: "seal", title: "Seal and spin", note: "Then straight to the qTOWER.", icon: "rectangle.compress.vertical",
                               items: [BenchItem(id: "seal:film", title: "Seal with optical adhesive film", detail: "Press firmly along every row and the edges."),
                                       BenchItem(id: "seal:spin", title: "Spin down", detail: "A brief spin in the plate centrifuge."),
                                       BenchItem(id: "seal:bubbles", title: "Check for bubbles", detail: "Tap out any at the bottom of the wells.")]))
        steps.append(BenchStep(id: "run", title: "Run on the qTOWER", note: "Analytik Jena qTOWER³ · \(p.runName)", icon: "thermometer.medium",
                               items: [BenchItem(id: "run:hold", title: "Hold 95 °C, 20 s", detail: "Initial denaturation."),
                                       BenchItem(id: "run:cycle", title: "40 cycles: 95 °C 3 s → 60 °C 30 s", detail: "Fluorescence read at 60 °C."),
                                       BenchItem(id: "run:melt", title: "Melt curve at the end", detail: "Export it with the gene files afterwards."),
                                       BenchItem(id: "run:name", title: "Name the run", detail: p.runName)]))
        return steps.filter { !$0.items.isEmpty }
    }

    func benchTick(_ id: String) {
        tap(.generic)
        if benchDone.contains(id) { benchDone.remove(id) } else { benchDone.insert(id) }
        // a finished step moves on by itself
        let steps = benchSteps
        if benchStep < steps.count, steps[benchStep].items.allSatisfy({ benchDone.contains($0.id) }), benchStep < steps.count - 1 {
            let at = benchStep
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self, self.benchStep == at else { return }
                withAnimation(self.motion ? .spring(response: 0.45, dampingFraction: 0.85) : nil) { self.benchStep = at + 1 }
            }
        }
    }

    func benchMove(_ by: Int) {
        let n = benchSteps.count
        let to = min(max(benchStep + by, 0), max(n - 1, 0))
        guard to != benchStep else { return }
        tap(.alignment)
        withAnimation(motion ? .spring(response: 0.45, dampingFraction: 0.85) : nil) { benchStep = to }
    }
}

/// Finds the window a view sits in.
struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { found(w) } }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

struct BenchView: View {
    @EnvironmentObject var store: Store
    private let window = State<NSWindow?>(initialValue: nil)
    private let monitor = State<Any?>(initialValue: nil)
    private let hovered = State<String?>(initialValue: nil)

    var body: some View {
        let steps = store.benchSteps
        let index = min(store.benchStep, max(steps.count - 1, 0))
        let step = steps.isEmpty ? nil : steps[index]
        let total = steps.reduce(0) { $0 + $1.items.count }
        let done = steps.reduce(0) { n, s in n + s.items.filter { store.benchDone.contains($0.id) }.count }
        ZStack {
            LinearGradient(colors: [Color(hex: "071630"), Color(hex: "0F2F5A"), Color(hex: "17437A")], startPoint: .bottomLeading, endPoint: .topTrailing)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar(done: done, total: total)
                HStack(alignment: .top, spacing: 26) {
                    sidebar(steps, index)
                        .frame(width: 290)
                    if let step {
                        stepView(step, number: index + 1, of: steps.count)
                            .id(step.id)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    } else {
                        Text("Add samples and primers to the protocol first.").font(.system(size: 22)).foregroundColor(.white.opacity(0.7))
                        Spacer()
                    }
                }
                .padding(.horizontal, 34).padding(.top, 22).padding(.bottom, 26)
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
        .background(WindowReader { w in
            window.wrappedValue = w
            w.backgroundColor = NSColor(hex: "071630")
            if w.isVisible && !w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
        })
        .onAppear { startKeys() }
        .onDisappear { if let m = monitor.wrappedValue { NSEvent.removeMonitor(m) }; monitor.wrappedValue = nil }
        .preferredColorScheme(.dark)
    }

    // MARK: pieces

    private func topBar(done: Int, total: Int) -> some View {
        HStack(spacing: 16) {
            if let logo = Brand.logo {
                Image(nsImage: logo).renderingMode(.template).resizable().aspectRatio(contentMode: .fit).frame(height: 30).foregroundColor(.white.opacity(0.85))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("BENCH MODE").font(.system(size: 11, weight: .bold, design: .serif)).tracking(2).foregroundColor(Color(hex: "8CF5A4"))
                Text(store.plan.customName ?? store.plan.runName).font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
            }
            Spacer()
            HStack(spacing: 10) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12)).frame(width: 220, height: 6)
                    Capsule().fill(LinearGradient(colors: [Color(hex: "8CF5A4"), Color(hex: "9CCBFF")], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, 220 * CGFloat(total == 0 ? 0 : Double(done) / Double(total))), height: 6)
                        .animation(store.motion ? .spring(response: 0.5, dampingFraction: 0.8) : nil, value: done)
                }
                Text("\(done) of \(total)").font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundColor(.white.opacity(0.8))
                    .rolling(done, store.motion)
            }
            Button { store.benchDone.removeAll(); store.benchStep = 0 } label: {
                Label("Start over", systemImage: "arrow.counterclockwise").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundColor(.white.opacity(0.75))
            Button { window.wrappedValue?.close() } label: {
                Label("Leave", systemImage: "xmark.circle.fill").font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "071630")).padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.9)))
            }
            .buttonStyle(SquishStyle(on: store.motion))
        }
        .padding(.horizontal, 34).padding(.top, 26).padding(.bottom, 8)
    }

    private func sidebar(_ steps: [BenchStep], _ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, s in
                let left = s.items.filter { !store.benchDone.contains($0.id) }.count
                Button { store.benchMove(i - store.benchStep) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(left == 0 ? Color(hex: "2E9E5B") : (i == index ? Color.white : Color.white.opacity(0.1))).frame(width: 34, height: 34)
                            if left == 0 {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy)).foregroundColor(.white)
                            } else {
                                Text("\(i + 1)").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(i == index ? Color(hex: "0F2F5A") : .white.opacity(0.8))
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).font(.system(size: 15, weight: i == index ? .bold : .medium)).foregroundColor(.white.opacity(i == index ? 1 : 0.75))
                                .lineLimit(2).multilineTextAlignment(.leading)
                            Text(left == 0 ? "done" : "\(left) to go").font(.system(size: 11.5)).foregroundColor(left == 0 ? Color(hex: "8CF5A4") : .white.opacity(0.5))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(i == index ? 0.12 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Space ticks the next line · ← → move between steps · Esc leaves")
                .font(.system(size: 11.5)).foregroundColor(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepView(_ step: BenchStep, number: Int, of count: Int) -> some View {
        let next = step.items.first { !store.benchDone.contains($0.id) }
        let focus = step.items.first { $0.id == hovered.wrappedValue } ?? next ?? step.items.last
        return HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: step.icon).font(.system(size: 26, weight: .medium)).foregroundColor(Color(hex: "8CF5A4"))
                    Text("STEP \(number) OF \(count)").font(.system(size: 12, weight: .bold, design: .serif)).tracking(2).foregroundColor(.white.opacity(0.6))
                }
                Text(step.title).font(.system(size: 38, weight: .bold, design: .serif)).foregroundColor(.white)
                Text(step.note).font(.system(size: 18)).foregroundColor(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(step.items) { item in
                            itemRow(item, isNext: item.id == next?.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                HStack(spacing: 12) {
                    benchButton("Back", "chevron.left", primary: false) { store.benchMove(-1) }.disabled(number == 1).opacity(number == 1 ? 0.4 : 1)
                    benchButton(number == count ? "All done" : "Next step", number == count ? "checkmark" : "chevron.right", primary: true) {
                        if number == count { window.wrappedValue?.close() } else { store.benchMove(1) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let k = focus?.plate, k < store.plan.plates.count {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.plan.plates.count > 1 ? "PLATE \(store.plan.plates[k].number)" : "THE PLATE")
                        .font(.system(size: 12, weight: .bold, design: .serif)).tracking(2).foregroundColor(.white.opacity(0.6))
                    PlateArrangement(plate: store.plan.plates[k], n: store.plan.n, calibrator: store.plan.calibratorName, order: 0,
                                     highlight: focus?.wells, animated: false)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.card))
                        .scaleEffect(1.05, anchor: .topLeading)
                    if let f = focus {
                        Text(f.detail).font(.system(size: 17, weight: .semibold)).foregroundColor(Color(hex: "8CF5A4")).padding(.top, 14)
                    }
                }
                .frame(width: PlateArrangement.size(store.plan.plates[k]).width * 1.05 + 28)
                .transition(.opacity)
            }
        }
    }

    private func itemRow(_ item: BenchItem, isNext: Bool) -> some View {
        let ticked = store.benchDone.contains(item.id)
        return Button { store.benchTick(item.id) } label: {
            HStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(ticked ? Color(hex: "2E9E5B") : Color.white.opacity(0.08))
                        .frame(width: 38, height: 38)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(ticked ? Color(hex: "8CF5A4") : Color.white.opacity(isNext ? 0.8 : 0.35), lineWidth: 2)
                        .frame(width: 38, height: 38)
                    if ticked {
                        Image(systemName: "checkmark").font(.system(size: 19, weight: .heavy)).foregroundColor(.white)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
                .animation(store.motion ? .spring(response: 0.3, dampingFraction: 0.55) : nil, value: ticked)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.system(size: 22, weight: .semibold)).foregroundColor(.white.opacity(ticked ? 0.45 : 1))
                        .strikethrough(ticked, color: .white.opacity(0.4))
                    Text(item.detail).font(.system(size: 17)).monospacedDigit().foregroundColor(.white.opacity(ticked ? 0.35 : 0.75))
                }
                Spacer(minLength: 0)
                if isNext {
                    Text("next").font(.system(size: 12, weight: .bold)).foregroundColor(Color(hex: "071630"))
                        .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(Color(hex: "8CF5A4")))
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(isNext ? 0.12 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(isNext ? 0.35 : 0.08), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishStyle(on: store.motion))
        .onHover { hovered.wrappedValue = $0 ? item.id : (hovered.wrappedValue == item.id ? nil : hovered.wrappedValue) }
    }

    private func benchButton(_ title: String, _ icon: String, primary: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if !primary { Image(systemName: icon) }
                Text(title)
                if primary { Image(systemName: icon) }
            }
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(primary ? Color(hex: "071630") : .white)
            .padding(.horizontal, 22).padding(.vertical, 12)
            .background(Capsule().fill(primary ? Color(hex: "8CF5A4") : Color.white.opacity(0.12)))
        }
        .buttonStyle(SquishStyle(on: store.motion))
    }

    // MARK: keys

    private func startKeys() {
        guard monitor.wrappedValue == nil else { return }
        monitor.wrappedValue = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard let w = window.wrappedValue, e.window === w else { return e }
            switch e.keyCode {
            case 49:            // space: tick the next line
                let steps = store.benchSteps
                let i = min(store.benchStep, max(steps.count - 1, 0))
                if i < steps.count, let next = steps[i].items.first(where: { !store.benchDone.contains($0.id) }) { store.benchTick(next.id) }
                return nil
            case 124, 125: store.benchMove(1); return nil      // → ↓
            case 123, 126: store.benchMove(-1); return nil     // ← ↑
            case 53:            // Esc: leave
                w.close()
                return nil
            default: return e
            }
        }
    }
}

/// The menu command and header button that open bench mode.
struct BenchButton: View {
    @Environment(\.openWindow) private var openWindow
    let menu: Bool
    @EnvironmentObject var store: Store

    var body: some View {
        if menu {
            Button("Bench Mode") { openWindow(id: "bench") }.keyboardShortcut("b")
        } else {
            FunButton(action: { openWindow(id: "bench") }) {
                Label("Bench mode", systemImage: "checklist").font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Brand.accent).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Brand.card))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Brand.navy.opacity(0.35), lineWidth: 1))
            }
            .help("Work through the protocol at the bench, step by step, full screen (⌘B)")
        }
    }
}
