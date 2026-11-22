import SwiftUI
import AppKit

// Development check, run from the command line (never from the normal app):
//
//   "ICC Plate Planner" --selftest <ops> <output folder> [seed]
//
// It opens the real window off-screen, pushes it through thousands of random edits (adding and
// deleting rows, painting wells, odd text, extreme numbers) while redrawing it, and every so often
// writes the workbook plus the exact state it was built from. A separate script then recomputes
// every number from that state and compares it with what landed in the Excel file.

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private struct TestCase: Codable {
    var exp: Experiment
    var settings: Settings
}

private let oddText = [
    "", "", "#380", "#381", "#382", "007", "1e5", "0x10", "nan", "inf", "100", "56", "0.5", "-2", "0",
    "C2 boost 4.0", "PG\nconc. (pM)", "<b>&\"quote\"'", "神戸 μL", "😀 ok", "a\u{0001}b", "  spaced  ",
    String(repeating: "long ", count: 30), "=SUM(A1)", "#DIV/0!", "TRUE", "1,000", "１２３", "ctl", "A/B:C",
]

func selfTest(ops: Int, outDir: String, seed: UInt64) {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    var rng = SplitMix64(state: seed)
    let store = Store(inMemory: .starter)
    store.undoGrouping = 0   // every change is its own undo step, to exercise undo hard

    let size = NSSize(width: 1320, height: 900)
    let host = NSHostingView(rootView: ContentView().environmentObject(store).frame(width: size.width, height: size.height))
    let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
    win.appearance = NSAppearance(named: .aqua)
    win.contentView = host

    func redraw() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.002))
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) { host.cacheDisplay(in: host.bounds, to: rep) }
    }
    func pick<T>(_ a: [T]) -> T { a[Int.random(in: 0..<a.count, using: &rng)] }
    func text() -> String { pick(oddText) }
    func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &rng) < p }

    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    let exportEvery = max(1, ops / 60)
    var exports = 0
    let enc = JSONEncoder()

    for n in 0..<ops {
        switch Int.random(in: 0..<30, using: &rng) {
        case 0:
            if store.exp.samples.count < 6 {
                store.addSample()
                store.exp.samples[store.exp.samples.count - 1].code = text()
                store.exp.samples[store.exp.samples.count - 1].name = text()
            }
        case 1:
            if let smp = store.exp.samples.randomElement(using: &rng) { store.removeSample(smp.id) }
        case 2, 3:
            let i = Int.random(in: 0..<store.exp.samples.count, using: &rng)
            switch Int.random(in: 0..<7, using: &rng) {
            case 5: store.exp.samples[i].fixed = chance(0.5) ? nil : Date(timeIntervalSince1970: Double(Int.random(in: 1_600_000_000..<1_900_000_000, using: &rng)))
            case 6: store.settings.fixDay = pick([14, 14, 7, 0, 21])
            case 0: store.exp.samples[i].code = text()
            case 1: store.exp.samples[i].name = text()
            case 2: store.exp.samples[i].hasDay0.toggle()
            case 3: store.exp.samples[i].day0 = Date(timeIntervalSince1970: Double(Int.random(in: 1_600_000_000..<1_900_000_000, using: &rng)))
            default: store.exp.samples[i].day = pick(["", "14", "11", "d14", "007", "14 "])
            }
        case 4:
            if store.exp.sets.count < 6 {
                if chance(0.5), let s = store.exp.sets.randomElement(using: &rng) {
                    store.duplicateSet(s.id)
                } else {
                    store.addSet()
                }
            }
        case 5:
            if let s = store.exp.sets.randomElement(using: &rng), chance(0.6) { store.removeSet(s.id) }
        case 6, 7, 8:
            guard !store.exp.sets.isEmpty else { break }
            let i = Int.random(in: 0..<store.exp.sets.count, using: &rng)
            switch Int.random(in: 0..<9, using: &rng) {
            case 0:
                if store.exp.sets[i].primaries.count < 5 {
                    var p = store.library.primaries.randomElement(using: &rng) ?? Antibody()
                    p.id = UUID()
                    store.exp.sets[i].primaries.append(p)
                }
            case 1:
                if !store.exp.sets[i].primaries.isEmpty { store.exp.sets[i].primaries.remove(at: Int.random(in: 0..<store.exp.sets[i].primaries.count, using: &rng)) }
            case 2:
                if !store.exp.sets[i].primaries.isEmpty {
                    let k = Int.random(in: 0..<store.exp.sets[i].primaries.count, using: &rng)
                    store.exp.sets[i].primaries[k].name = text()
                    store.exp.sets[i].primaries[k].cat = text()
                    store.exp.sets[i].primaries[k].company = text()
                    store.exp.sets[i].primaries[k].dilution = pick([0, 500, 1000, 250.5, -3, 400])
                }
            case 3:
                if store.exp.sets[i].secondaries.count < 5 {
                    var q = store.library.secondaries.randomElement(using: &rng) ?? Secondary()
                    q.id = UUID()
                    store.exp.sets[i].secondaries.append(q)
                }
            case 4:
                if !store.exp.sets[i].secondaries.isEmpty { store.exp.sets[i].secondaries.remove(at: Int.random(in: 0..<store.exp.sets[i].secondaries.count, using: &rng)) }
            case 5:
                if !store.exp.sets[i].secondaries.isEmpty {
                    let k = Int.random(in: 0..<store.exp.sets[i].secondaries.count, using: &rng)
                    store.exp.sets[i].secondaries[k].name = text()
                    store.exp.sets[i].secondaries[k].dilution = pick([0, 500, 400, 333.3, -1])
                }
            case 6: store.exp.sets[i].colorHex = pick([nil, "FAD7E4", "1E4A83", "000000", "ffffff", "zzzzzz", "12", "CFEFEA"])
            case 7: store.exp.sets[i].volumeOverride = pick([nil, nil, 900, 0, 1234.5, -50])
            default: store.exp.blockingOverride = pick([nil, 7, 0, 4.25])
            }
        case 9, 10:
            var tools: [Tool] = [.erase, .text, .duplicate, .duplicate, .paint(UUID()), .tag(UUID())]
            tools += store.exp.sets.map { .paint($0.id) }
            tools += store.exp.sets.map { .paint($0.id) }
            tools += store.exp.samples.map { .tag($0.id) }
            store.tool = pick(tools)
            store.duplicateScope = chance(0.5) ? .well : .row
        case 11, 12, 13, 14, 15, 16:
            for _ in 0..<Int.random(in: 1...14, using: &rng) { store.touch(Int.random(in: -2..<98, using: &rng)) }
            store.endDrag()
        case 17:
            store.selectedWell = chance(0.2) ? nil : Int.random(in: 0..<96, using: &rng)
        case 18, 19:
            store.setLabel(Int.random(in: -1..<97, using: &rng), text())
        case 20:
            store.exp.leftLabels[Int.random(in: 0..<8, using: &rng)] = text()
        case 21:
            store.exp.topLabels[Int.random(in: 0..<12, using: &rng)] = text()
        case 22:
            store.settings.ulPerWell = pick([100, 100, 50, 120.5, 0])
            store.settings.extraWells = pick([1, 1, 2, 0, 0.5])
        case 23:
            store.settings.blockPerWell = pick([100, 100, 200, 0])
            store.settings.blockExtraUl = pick([100, 0, 250])
            store.settings.ndsPerMl = pick([20, 20, 0, 15.5])
        case 24:
            if chance(0.15) { store.clearPlate() }
        case 25:
            if chance(0.08) { store.newExperiment() }
        case 26:
            store.library.remember(store.exp.sets)
        case 27:
            if chance(0.3), !store.library.primaries.isEmpty { store.library.primaries.remove(at: Int.random(in: 0..<store.library.primaries.count, using: &rng)) }
            if store.library.primaries.count < 3 { store.library = .seed }
        case 28:
            store.exp.date = Date(timeIntervalSince1970: Double(Int.random(in: 1_600_000_000..<1_900_000_000, using: &rng)))
        default:
            // undo and redo, in bursts
            for _ in 0..<Int.random(in: 1...6, using: &rng) { if chance(0.6) { store.undo() } else { store.redo() } }
        }

        if n % 3 == 0 { redraw() }
        if n % exportEvery == 0 {
            let data = buildWorkbook(store.exp, store.settings)
            let base = "\(outDir)/case_\(String(format: "%03d", exports))"
            try? data.write(to: URL(fileURLWithPath: base + ".xlsx"))
            if let j = try? enc.encode(TestCase(exp: store.exp, settings: store.settings)) {
                try? j.write(to: URL(fileURLWithPath: base + ".json"))
            }
            exports += 1
        }
    }
    redraw()
    if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: outDir + "/final.png"))
    }
    print("selftest finished: \(ops) random edits, \(exports) workbooks written, seed \(seed)")
}

// Direct checks of specific behaviours:  "ICC Plate Planner" --featuretest [saved state file]
func featureTest(statePath: String?) {
    _ = NSApplication.shared
    var failures = 0
    func expect(_ ok: Bool, _ what: String) {
        print((ok ? "PASS  " : "FAIL  ") + what)
        if !ok { failures += 1 }
    }
    func cell(_ data: Data, _ e: Experiment) -> Bool { !data.isEmpty && e.wells.count == 96 }

    let store = Store(inMemory: sampleExperiment())
    store.undoGrouping = 0
    let a = store.exp.samples[0], b = store.exp.samples[1]

    // tags follow a renamed sample
    store.tool = .tag(b.id)
    store.touch(40); store.endDrag()
    expect(store.exp.label(40) == "#381", "stamping a tag shows the sample number")
    store.exp.samples[1].code = "#381-B"
    expect(store.exp.label(40) == "#381-B", "renaming the sample updates the stamped well")
    expect(store.exp.wellText[40].isEmpty, "a stamped tag is stored as a link, not as text")
    store.exp.samples[1].code = ""
    expect(store.exp.label(40) == "C2_Wnt_Esc_03", "with no number the tag falls back to the sample name")
    store.exp.samples[1].code = "#381"
    store.touch(40); store.endDrag()
    expect(store.exp.label(40).isEmpty, "clicking a stamped well again removes the tag")
    store.touch(41); store.endDrag()
    store.setLabel(41, "typed")
    expect(store.exp.label(41) == "typed" && store.exp.wellTags[41] == nil, "typing a label replaces a tag")
    store.touch(42); store.endDrag()
    store.removeSample(b.id)
    expect(store.exp.label(42).isEmpty && store.exp.wellTags[42] == nil, "deleting a sample clears its tags")
    if case .tag = store.tool { expect(false, "tag tool resets when its sample is deleted") } else { expect(true, "tag tool resets when its sample is deleted") }

    // undo / redo
    let s2 = Store(inMemory: sampleExperiment())
    s2.undoGrouping = 0
    let start = s2.exp
    expect(s2.undoCount == 0, "nothing to undo at the start")
    s2.tool = .paint(s2.exp.sets[0].id)
    s2.touch(50); s2.touch(51); s2.endDrag()
    let painted = s2.exp
    expect(s2.exp.wellCount(s2.exp.sets[0]) == 9, "painting two wells adds two wells")
    expect(s2.undoCount == 1, "one drag is one undo step, however many wells it painted")
    // a catalogue number corrected on a card is saved to the fridge tube it came from
    let fz = Store(inMemory: sampleExperiment())
    fz.syncTubesInTests = true
    fz.library.primaries = [Antibody(name: "TH (rab)", company: "Merck", cat: "AB15O2", dilution: 1000),
                            Antibody(name: "FOXA2 (g)", company: "R&D Systems", cat: "AF2400", dilution: 500)]
    fz.library.secondaries = [Secondary(name: "488 rab", dilution: 500, company: "Thermo Fisher", cat: "A-2l206")]
    var th = fz.library.primaries[0]; th.id = UUID()
    var sec = fz.library.secondaries[0]; sec.id = UUID()
    fz.exp.sets[0].primaries = [th]
    fz.exp.sets[0].secondaries = [sec]
    let tubeID = fz.library.primaries[0].id
    fz.exp.sets[0].primaries[0].cat = "AB152"
    expect(fz.library.primaries.first { $0.id == tubeID }?.cat == "AB152", "a catalogue number fixed on a card is saved to its fridge tube")
    fz.exp.sets[0].secondaries[0].cat = "A-21206"
    expect(fz.library.secondaries[0].cat == "A-21206", "a secondary's catalogue number fixed on a card is saved to its tube")
    fz.exp.sets[0].secondaries[0].company = "Thermo Fisher Scientific"
    expect(fz.library.secondaries[0].company == "Thermo Fisher Scientific", "a secondary's company edited on a card is saved to its tube")
    fz.exp.sets[0].primaries[0].name = "TH (rabbit)"
    expect(fz.library.primaries.first { $0.id == tubeID }?.name == "TH (rabbit)", "a corrected name reaches the same tube")
    fz.exp.sets[0].primaries[0].name = "FOXA2 (g)"
    expect(fz.library.primaries.filter { $0.name == "FOXA2 (g)" }.count == 1 && fz.library.primaries.first { $0.id == tubeID }?.name == "TH (rabbit)",
           "an edit never takes over another tube's name")
    fz.exp.sets[0].primaries.append(Antibody(name: "", company: "", cat: ""))
    fz.exp.sets[0].primaries[1].name = "NEW (m)"
    expect(!fz.library.primaries.contains { $0.name == "NEW (m)" }, "a new row typed on the card is not put in the fridge until export")
    expect(fz.library.primaries.count == 2, "the fridge keeps the same tubes")

    // every new stain gets a colour of its own; the others keep theirs when stains come and go
    let cs = Store(inMemory: sampleExperiment())
    for _ in 0..<(12 - cs.exp.sets.count) { cs.addSet() }
    let fills = cs.exp.sets.enumerated().map { fillHex($0.element, $0.offset) }
    let closest = fills.indices.flatMap { i in fills.indices.filter { $0 > i }.map { colourDistance(fills[i], fills[$0]) } }.min() ?? 0
    expect(Set(fills).count == fills.count && closest >= 5, "twelve stains, twelve colours (closest pair ΔE \(Int(closest)))")
    let before3 = fillHex(cs.exp.sets[3], 3), before5 = fillHex(cs.exp.sets[5], 5)
    let id3 = cs.exp.sets[3].id, id5 = cs.exp.sets[5].id
    cs.removeSet(cs.exp.sets[1].id)
    let k3 = cs.exp.sets.firstIndex { $0.id == id3 }!, k5 = cs.exp.sets.firstIndex { $0.id == id5 }!
    expect(fillHex(cs.exp.sets[k3], k3) == before3 && fillHex(cs.exp.sets[k5], k5) == before5, "removing a stain leaves the others' colours alone")
    cs.duplicateSet(cs.exp.sets[0].id)
    let n3 = cs.exp.sets.firstIndex { $0.id == id3 }!
    expect(fillHex(cs.exp.sets[1], 1) != fillHex(cs.exp.sets[0], 0), "a duplicated stain gets its own colour")
    expect(fillHex(cs.exp.sets[n3], n3) == before3, "and the stains after it keep theirs")
    let cs2 = Store(inMemory: Experiment())
    cs2.addSet(); cs2.addSet()
    expect(fillHex(cs2.exp.sets[0], 0) == setPalette[0] && fillHex(cs2.exp.sets[1], 1) == setPalette[1], "the first stains keep the lab's usual green and gold")

    // secondaries line up with the primaries they find, counterstains last; it is not an undo step
    let ar = Store(inMemory: sampleExperiment())
    ar.undoGrouping = 0
    ar.exp.sets[0].primaries = [Antibody(name: "LMX1A/B (rab)", company: "Merck", cat: "AB10533", dilution: 1000),
                                Antibody(name: "FOXA2 (g)", company: "R&D Systems", cat: "AF2400", dilution: 500)]
    ar.exp.sets[0].secondaries = [Secondary(name: "DAPI", dilution: 1000), Secondary(name: "594 g", dilution: 500), Secondary(name: "488 rab", dilution: 500)]
    let undosBefore = ar.undoCount
    ar.arrangePairs()
    expect(ar.exp.sets[0].secondaries.map { $0.name } == ["488 rab", "594 g", "DAPI"],
           "secondaries follow their primaries' order, the counterstain last")
    expect(ar.undoCount == undosBefore, "putting them in order is not an undo step")
    ar.exp.sets[0].primaries.swapAt(0, 1)
    ar.arrangePairs()
    expect(ar.exp.sets[0].secondaries.map { $0.name } == ["594 g", "488 rab", "DAPI"], "and follow them when the primaries change order")

    // a quick stroke the system reported as C1 then C5 still paints C2–C4; leaving the plate breaks it
    let sd = Store(inMemory: sampleExperiment())
    sd.tool = .paint(sd.exp.sets[0].id)
    for w in 0..<96 { sd.exp.wells[w] = nil }
    sd.dragOver(24); sd.dragOver(28); sd.endDrag()
    expect((24...28).allSatisfy { sd.exp.wells[$0] == sd.exp.sets[0].id }, "a fast stroke paints every well it crossed")
    sd.dragOver(36); sd.dragOver(nil); sd.dragOver(40); sd.endDrag()
    expect(sd.exp.wells[36] != nil && sd.exp.wells[40] != nil && (37...39).allSatisfy { sd.exp.wells[$0] == nil },
           "leaving the plate mid-drag doesn't paint a line back across it")
    sd.dragOver(0); sd.dragOver(27); sd.endDrag()
    expect(sd.exp.wells[13] != nil && sd.exp.wells[27] != nil, "a diagonal stroke paints the wells along it")
    s2.clearPlate()
    expect(s2.exp.totalStainedWells == 0, "clear plate empties the plate")
    s2.undo()
    expect(s2.exp == painted, "undo brings back a cleared plate")
    s2.undo(); s2.undo()
    expect(s2.exp == start, "undoing every step returns to the starting plate")
    expect(s2.undoCount == 0 && s2.redoCount == 2, "undo and redo counts are right")
    s2.redo()
    expect(s2.exp == painted, "redo re-applies the step")
    s2.exp.samples[0].name = "changed"
    expect(s2.redoCount == 0, "a new edit discards the redo history")
    let setID = s2.exp.sets[1].id
    s2.tool = .paint(setID)
    s2.removeSet(setID)
    s2.undo()
    expect(s2.exp.sets.contains { $0.id == setID } && s2.exp.wellCount(s2.exp.sets[1]) == 7, "undo restores a deleted stain set with its wells")
    s2.newExperiment()
    s2.undo(); s2.undo(); s2.undo()
    expect(s2.exp.samples.count == 2 && s2.exp.totalStainedWells > 0, "undo restores the plate after New Experiment")
    s2.undoGrouping = 0.5
    let before = s2.undoCount
    for w in 60..<70 { s2.touch(w) }
    s2.endDrag()
    expect(s2.undoCount == before + 1, "one drag across ten wells is a single undo step")
    for _ in 0..<300 { s2.undo() }
    for _ in 0..<300 { s2.redo() }
    expect(true, "undoing and redoing past the ends does nothing harmful")
    _ = a

    // a new sample has its Day 0 filled in
    let s4 = Store(inMemory: sampleExperiment())
    s4.addSample()
    expect(s4.exp.samples[2].hasDay0 && s4.exp.samples[2].day0 == s4.exp.samples[1].day0, "a new sample copies the Day 0 of the sample above it")
    s4.newExperiment()
    expect(s4.exp.samples.count == 1 && s4.exp.samples[0].hasDay0 && Calendar.current.isDateInToday(s4.exp.samples[0].day0),
           "after New Experiment the first sample's Day 0 is filled in with today")
    expect(Calendar.current.isDateInToday(s4.exp.date), "after New Experiment the staining date is today")

    // Date fixed fills in as Day 0 + 14, and Day follows it
    var s5 = sampleExperiment()
    let st5 = Settings()
    let cal = Calendar.current
    s5.samples[0].day = ""
    let fixed0 = s5.fixedDate(s5.samples[0], st5)
    expect(fixed0.map { cal.dateComponents([.year, .month, .day], from: $0) } == DateComponents(year: 2026, month: 11, day: 6),
           "Date fixed fills in as Day 0 + 14 days (23 Oct -> 6 Nov)")
    expect(s5.dayText(s5.samples[0], st5) == "14", "an empty Day is filled with 14 (date fixed minus Day 0)")
    s5.date = cal.date(byAdding: .day, value: 5, to: s5.date)!
    expect(s5.dayText(s5.samples[0], st5) == "14", "Day no longer changes with the staining date")
    s5.samples[0].day0 = cal.date(byAdding: .day, value: 2, to: s5.samples[0].day0)!
    expect(s5.fixedDate(s5.samples[0], st5).map { cal.dateComponents([.month, .day], from: $0) } == DateComponents(month: 11, day: 8),
           "the automatic fixed date follows a changed Day 0")
    s5.samples[0].fixed = cal.date(byAdding: .day, value: 16, to: s5.samples[0].day0)!
    expect(s5.dayText(s5.samples[0], st5) == "16", "picking a different fixed date changes Day to match")
    s5.samples[0].day = "15"
    expect(s5.dayText(s5.samples[0], st5) == "15", "a typed Day is kept as typed")
    s5.samples[0].day = ""; s5.samples[0].fixed = nil
    var st7 = Settings(); st7.fixDay = 7
    expect(s5.dayText(s5.samples[0], st7) == "7", "the fixation day can be changed in the settings")
    s5.samples[0].hasDay0 = false
    expect(s5.fixedDate(s5.samples[0], st5) == nil && s5.dayText(s5.samples[0], st5).isEmpty, "without a Day 0 there is no fixed date and no Day")

    // a two-digit year typed into a date is read as 20xx
    var c26 = DateComponents(); c26.year = 26; c26.month = 11; c26.day = 17
    let y26 = Calendar.current.date(from: c26)!
    expect(Calendar.current.component(.year, from: fixCentury(y26)) == 2026, "a staining date typed as year 26 becomes 2026")
    var e26 = sampleExperiment(); e26.date = y26; e26.samples[0].day0 = y26
    if let d = try? encodePlate(e26), let back = try? decodePlate(d) {
        expect(back.dateNumber == 20261117 && Calendar.current.component(.year, from: back.samples[0].day0) == 2026, "a saved plate with a year-26 date loads as 2026")
    } else { expect(false, "a saved plate with a year-26 date loads as 2026") }
    var eX = Experiment(); eX.customTitle = "my plate.xlsx"
    expect(eX.fileName == "my plate.xlsx", "a custom name typed with .xlsx does not get the extension twice")

    // the exported sheet carries the renamed tag
    let s3 = Store(inMemory: sampleExperiment())
    s3.tool = .tag(s3.exp.samples[0].id)
    s3.touch(30); s3.endDrag()
    s3.exp.samples[0].code = "#400"
    expect(cell(buildWorkbook(s3.exp, s3.settings), s3.exp) && s3.exp.label(30) == "#400", "export uses the renamed tag")

    // duplicating a stain set makes an independent copy
    let s6 = Store(inMemory: sampleExperiment())
    let origID = s6.exp.sets[0].id
    s6.duplicateSet(origID)
    expect(s6.exp.sets.count == 3, "duplicating a stain set adds a new set right after it")
    expect(s6.exp.sets[1].id != origID, "the copy has its own identity")
    expect(s6.exp.sets[1].primaries.map(\.name) == s6.exp.sets[0].primaries.map(\.name)
           && s6.exp.sets[1].secondaries.map(\.name) == s6.exp.sets[0].secondaries.map(\.name),
           "the copy keeps the same antibodies")
    expect(s6.exp.wellCount(s6.exp.sets[1]) == 0 && s6.exp.wellCount(s6.exp.sets[0]) == 7,
           "the copy starts with no wells; the original keeps its own")
    s6.exp.sets[1].primaries[0].name = "CHANGED"
    expect(s6.exp.sets[0].primaries[0].name != "CHANGED", "editing the copy leaves the original alone")
    if case .paint(let id) = s6.tool { expect(id == s6.exp.sets[1].id, "the paint tool switches to the copy") }
    else { expect(false, "the paint tool switches to the copy") }

    // duplicate mode, row scope: copies a whole row onto another
    let s7 = Store(inMemory: sampleExperiment())
    s7.undoGrouping = 0
    s7.tool = .duplicate
    s7.duplicateScope = .row
    s7.touch(1 * 12 + 3); s7.endDrag()   // pick row B as the source
    expect(s7.duplicateSource == 1 * 12 + 3, "duplicate mode picks the source")
    s7.touch(4 * 12 + 5); s7.endDrag()   // copy it onto row E
    expect(s7.exp.wells[4 * 12] == s7.exp.sets[0].id && s7.exp.wells[4 * 12 + 6] == s7.exp.sets[0].id,
           "duplicating a row copies its stains")
    expect(s7.exp.label(4 * 12 + 5) == "#381", "duplicating a row copies its labels")
    expect(s7.exp.leftLabels[4] == "#380", "duplicating a row copies the row label")
    s7.touch(2 * 12); s7.endDrag()       // copy onto row C, which already has stain 2
    expect(s7.exp.wells[2 * 12 + 6] == s7.exp.sets[0].id, "duplicating over a row replaces what was there")
    s7.touch(1 * 12 + 2); s7.endDrag()   // click the source row again
    expect(s7.duplicateSource == nil, "clicking the source again stops the copying")
    let beforeCopy = s7.exp
    s7.tool = .duplicate
    s7.touch(0); s7.touch(6 * 12); s7.endDrag()   // copy row A onto row G
    expect(s7.exp != beforeCopy, "duplicating a row changes the plate")
    s7.undo()
    expect(s7.exp == beforeCopy, "the row copies are undoable")
    s7.tool = .erase
    expect(s7.duplicateSource == nil, "leaving duplicate mode forgets the source")

    // duplicate mode, well scope: copies one well onto another
    let s7w = Store(inMemory: sampleExperiment())
    s7w.undoGrouping = 0
    s7w.tool = .duplicate
    expect(s7w.duplicateScope == .well, "well scope is the default")
    s7w.touch(1 * 12 + 5); s7w.endDrag()   // pick B6 (label "#381", unstained)
    expect(s7w.duplicateSource == 1 * 12 + 5, "well scope picks the source well")
    s7w.touch(5 * 12 + 5); s7w.endDrag()   // copy onto F6
    expect(s7w.exp.label(5 * 12 + 5) == "#381", "duplicating a well copies its label")
    expect(s7w.exp.label(5 * 12 + 3).isEmpty && s7w.exp.wells[5 * 12 + 3] == nil,
           "duplicating a well leaves its neighbours alone")
    s7w.touch(1 * 12 + 5); s7w.endDrag()   // click the source well again
    expect(s7w.duplicateSource == nil, "clicking the source well again stops the copying")
    s7w.touch(1 * 12 + 6); s7w.endDrag()   // pick B7 (stain 1, no label)
    s7w.touch(5 * 12 + 6); s7w.endDrag()   // copy onto F7
    expect(s7w.exp.wells[5 * 12 + 6] == s7w.exp.sets[0].id, "duplicating a well copies its stain")
    // copying a well that carries a stamped tag keeps the tag linked to its sample
    let s7t = Store(inMemory: sampleExperiment())
    s7t.tool = .tag(s7t.exp.samples[0].id)
    s7t.touch(3 * 12 + 4); s7t.endDrag()
    s7t.tool = .duplicate
    s7t.touch(3 * 12 + 4); s7t.touch(7 * 12 + 4); s7t.endDrag()
    expect(s7t.exp.wellTags[7 * 12 + 4] == s7t.exp.samples[0].id, "duplicating a stamped well copies the tag as a link")
    s7t.exp.samples[0].code = "#999"
    expect(s7t.exp.label(7 * 12 + 4) == "#999", "the copied tag follows a renamed sample")


    // saving a plate and loading it again keeps everything
    let s8 = Store(inMemory: sampleExperiment())
    s8.exp.customTitle = "bench top plate"
    if let d = try? encodePlate(s8.exp), let back = try? decodePlate(d) {
        expect(back == s8.exp, "a saved plate loads back exactly")
    } else {
        expect(false, "a saved plate loads back exactly")
    }
    expect((try? decodePlate(Data("[]".utf8))) == nil, "a file that is not a plate is rejected")

    // a custom title replaces a too-long automatic file name
    var e9 = sampleExperiment()
    expect(e9.fileName.contains("380") && e9.fileName.hasSuffix(".xlsx"), "the automatic file name is the date plus the samples")
    e9.customTitle = "Short name"
    expect(e9.fileName == "Short name.xlsx", "a custom title replaces the file name")
    e9.customTitle = "  a/b:c  "
    expect(e9.fileName == "a-b-c.xlsx", "slashes and colons in a custom title are made safe")
    e9.customTitle = ""
    expect(e9.fileName.hasPrefix("20261111"), "an empty custom title goes back to the automatic name")

    // the department list: secondary dilutions follow the lab sheet, plus the imported antibodies
    let lib = Library.seed
    for (name, dil) in [("488 rab", 500.0), ("594 g", 500.0), ("488 rat", 500.0), ("647 ms", 400.0),
                        ("488 ms", 400.0), ("594 rab", 400.0), ("647 rab", 400.0), ("488 sheep", 200.0)] {
        expect(lib.secondaries.first { $0.name == name }?.dilution == dil, "secondary \(name) defaults to 1:\(Int(dil)) as on the sheet")
    }
    expect(Secondary().dilution == 0 && Antibody().dilution == 0, "blank antibody rows start empty, not with a made-up dilution")
    for (name, cat, dil) in [("TH (mouse)", "MAB318", 500.0), ("Barhl1 (rab)", "NBO1-86513", 500.0),
                             ("Pitx2 (sheep)", "AD7388", 200.0), ("Pitx3 (rab)", "ab313403", 500.0),
                             ("SOX6 (mouse)", "MAB7759", 500.0), ("EN1 (rab)", "AB5732", 2000.0),
                             ("Tubulin beta III (rab)", "RPB435-P", 1000.0)] {
        let p = lib.primaries.first { $0.cat == cat }
        expect(p?.name == name && p?.dilution == dil, "imported antibody \(name) is in the defaults")
    }
    expect(lib.secondaries.contains { $0.name == "647 rab" } && lib.secondaries.contains { $0.name == "488 sheep" },
           "imported secondaries are in the defaults")

    // the 1:400 correction only touches the three names at exactly 1:500 (what the interim build wrote)
    expect(Library.isSecondary500FromSheet400(Secondary(name: "647 ms", dilution: 500)), "a standard secondary at 1:500 is corrected to 1:400")
    expect(!Library.isSecondary500FromSheet400(Secondary(name: "647 ms", dilution: 350)), "a hand-set dilution is left alone")
    expect(!Library.isSecondary500FromSheet400(Secondary(name: "488 rab", dilution: 500)), "the sheet's 1:500 secondaries stay at 1:500")

    // merging the seed into an older library adds the imports without duplicating or overwriting
    var old = Library(primaries: [Antibody(name: "TH（mouse)", company: "", cat: "MAB318", dilution: 500)],
                      secondaries: [Secondary(name: "488 ms", dilution: 300)])
    old.mergeSeed()
    expect(old.primaries.filter { $0.cat == "MAB318" }.count == 1, "an antibody already saved is not duplicated")
    expect(old.primaries.first { $0.cat == "MAB318" }?.dilution == 500, "the saved dilution is kept")
    expect(old.primaries.first { $0.cat == "MAB318" }?.company == "Merck", "missing details are filled in")
    expect(old.secondaries.first { $0.name == "488 ms" }?.dilution == 300, "a saved secondary keeps its own dilution")
    expect(old.primaries.contains { $0.cat == "ab313403" }, "mergeSeed adds the imported primaries")

    // a fresh start is blank: no pre-filled stain sets, and new stain sets carry no antibodies
    expect(Experiment.starter.sets.isEmpty, "first launch starts with no stain sets")
    let s10 = Store(inMemory: sampleExperiment())
    s10.addSet()
    let added = s10.exp.sets.last!
    expect(added.primaries.isEmpty && added.secondaries.isEmpty, "a new stain set starts blank")



    // a file saved by the previous version still loads, and its stamped text becomes linked tags
    if let path = statePath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
        struct Saved: Codable { var exp: Experiment }
        if let old = try? JSONDecoder().decode(Saved.self, from: data) {
            let e = old.exp
            let linked = e.wellTags.compactMap { $0 }.count
            print("INFO  saved plate loaded: \(e.samples.count) samples, \(e.sets.count) stains, \(e.totalStainedWells) stained wells, \(linked) wells linked to a sample tag, \(e.wellText.filter { !$0.isEmpty }.count) typed labels")
            expect(e.wells.count == 96 && e.wellTags.count == 96, "the saved plate from the previous version loads")
        } else {
            expect(false, "the saved plate from the previous version loads")
        }
    }
    print(failures == 0 ? "ALL FEATURE CHECKS PASSED" : "\(failures) FEATURE CHECK(S) FAILED")
}
