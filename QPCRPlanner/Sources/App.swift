import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Entry point

@main
enum Main {
    static func main() {
        let a = CommandLine.arguments
        // Development checks, run from the command line only.
        if let i = a.firstIndex(of: "--protocol-sample"), a.count > i + 1 {
            var p = examplePlan()
            applyLayoutFlags(&p)
            if a.contains("--custom-title") { p.customTitle = "My bench plate.xlsx" }
            var colors = GeneColors()
            if a.contains("--colors") { colors.custom = ["LMX1A": "D4578C", "GAPDH": "7F7F7F"] }
            try? buildProtocolWorkbook(p, ProtocolSettings(), colors: colors).write(to: URL(fileURLWithPath: a[i + 1]))
            return
        }
        if let i = a.firstIndex(of: "--plan-roundtrip"), a.count > i + 1 {   // save → open: same plan, same workbooks
            var p = examplePlan(); p.layout = .primerRows; p.customTitle = ""
            var st = ProtocolSettings(); st.extraWells = 6
            let url = URL(fileURLWithPath: a[i + 1])
            do {
                try encodePlanFile(p, st).write(to: url)
                let f = try decodePlanFile(Data(contentsOf: url))
                print("plan same:", f.plan == p, "| settings same:", f.settings == st,
                      "| protocol workbook same:", buildProtocolWorkbook(f.plan, f.settings) == buildProtocolWorkbook(p, st),
                      "| melt sheet same:", buildMeltWorkbook(f.plan) == buildMeltWorkbook(p))
                _ = NSApplication.shared
                let store = Store(inMemory: ProtocolPlan())
                store.openPlanFile(url)
                print("store after open:", store.plan == p, store.settings == st, store.mode)
                // not a plan file
                print("rejects a data file:", (try? decodePlanFile(Data("{\"app\":\"other\"}".utf8))) == nil)
            } catch { print("FAILED", error) }
            return
        }
        if let i = a.firstIndex(of: "--protocol-folder"), a.count > i + 1 {   // the lab's #384 run, as an export folder
            var p = ProtocolPlan()
            p.title = "384_C2_Wnt_PG vs CHIR_01"
            p.description = "#384 C2_Wnt_PG vs CHIR_01"
            p.genes = ["LMX1A", "CORIN", "EN1", "FOXA2", "OTX2", "GBX2"].map { NamedItem(name: $0) }
            p.samples = ["PG_20pM", "PG_Boost", "CHIR_1.2uM", "CHIR_Boost"].map { NamedItem(name: $0) }
            p.calibratorID = p.samples[2].id
            var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 19
            p.date = Calendar.current.date(from: c)!
            p.layout = .primerRows
            if a.contains("--many") { p.samples += (1...8).map { NamedItem(name: "S\($0)") } }
            let dir = URL(fileURLWithPath: a[i + 1]).appendingPathComponent(p.folderName)
            do { let (u, kept) = try writeProtocolFolder(p, ProtocolSettings(), colors: GeneColors(), to: dir); print(u.path, kept ? "melt kept" : "melt written") }
            catch { print("FAILED", error) }
            return
        }
        if let i = a.firstIndex(of: "--results"), a.count > i + 2 {
            var rs = ResultSet()
            do {
                let files = Store.expand([URL(fileURLWithPath: a[i + 1])])
                for url in files {
                    for t in try readTables(url) { rs.add(parseGenes(t)) }
                }
                if files.count > 1 { rs.order(by: Store.defaultGenes) }
            } catch { print("error: \(error.localizedDescription)"); exit(1) }
            var opt = ResultsOptions()
            if a.contains("--gap") { opt.groupGap = true }
            if a.contains("--compare") { opt.compare = true }
            if let j = a.firstIndex(of: "--groups"), a.count > j + 2 {
                opt.pickGroups = true
                opt.membersA = a[j + 1].split(separator: ",").map(String.init)
                opt.membersB = a[j + 2].split(separator: ",").map(String.init)
            }
            if a.contains("--noref") { opt.refLine = false }
            opt.xTitle = "PG-008"
            var colors = GeneColors()
            if a.contains("--colors") { colors.custom = ["LMX1A": "D4578C", "CORIN": "17A2A2"] }
            try? buildResultsWorkbook(rs, opt, colors: colors).write(to: URL(fileURLWithPath: a[i + 2]))
            print("genes: \(rs.genes.map { $0.name }) | conditions: \(rs.conditions)")
            return
        }
        if let i = a.firstIndex(of: "--data-roundtrip"), a.count > i + 4 {
            // import → save .qpcrdata → open it in a fresh store → both must give the same graph workbook
            _ = NSApplication.shared
            let s1 = Store(inMemory: examplePlan())
            s1.importFiles([URL(fileURLWithPath: a[i + 1])])
            s1.importShow = nil
            s1.options.compare = true
            s1.options.customTitle = "Round trip"
            s1.options.xTitle = "PG-008"
            s1.geneColorMap["LMX1A"] = "D4578C"
            let file = URL(fileURLWithPath: a[i + 2])
            do { try s1.writeData(to: file) } catch { print("error: \(error)"); exit(1) }
            let s2 = Store(inMemory: examplePlan())
            s2.openData(file)
            try? buildResultsWorkbook(s1.results, s1.options, colors: s1.resultColors).write(to: URL(fileURLWithPath: a[i + 3]))
            try? buildResultsWorkbook(s2.results, s2.options, colors: s2.resultColors).write(to: URL(fileURLWithPath: a[i + 4]))
            print(s1.importMessage)
            print("kept tabs: \(s1.results.extras.map { $0.name + " (" + $0.source + ", \($0.rows.count) rows)" }) → \(s2.results.extras.map { $0.name })")
            print("genes: \(s1.results.genes.count) → \(s2.results.genes.count) | conditions: \(s1.results.conditions.count) → \(s2.results.conditions.count) | title: \(s2.resultsFileName) | LMX1A colour: \(s2.geneColorMap["LMX1A"] ?? "-") | compare: \(s2.options.compare) | mode: \(s2.mode)")
            return
        }
        if let i = a.firstIndex(of: "--replicate-check"), a.count > i + 1 {
            var rs = ResultSet()
            for url in Store.expand([URL(fileURLWithPath: a[i + 1])]) { for t in (try? readTables(url)) ?? [] { rs.add(parseGenes(t)) } }
            for limit in [0.5, 0.3, 0.2] {
                let plates = rs.plateChecks(limit: limit)
                for p in plates {
                    print("limit \(limit) · \(p.title): \(p.wells.count) wells, \(p.wells.filter { $0.ct == nil }.count) without a Ct, \(p.flagged.count) flagged")
                    for w in p.flagged.prefix(8) { print("   \(w.well) \(w.sample) \(w.target) Ct \(w.ct!) vs \(w.partners) (\(String(format: "%+.2f", w.offBy ?? 0)))") }
                }
            }
            return
        }
        if let i = a.firstIndex(of: "--prism-copy"), a.count > i + 1 {
            // exactly what Copy for Prism puts on the clipboard: the grouped 2^−ΔΔCt table
            var rs = ResultSet()
            for url in Store.expand([URL(fileURLWithPath: a[i + 1])]) { for t in (try? readTables(url)) ?? [] { rs.add(parseGenes(t)) } }
            rs.order(by: Store.defaultGenes)
            print(tsv(rs.prismGrouped(.fold, ResultsOptions())), terminator: "")
            return
        }
        if let i = a.firstIndex(of: "--delta-check"), a.count > i + 1 {
            // ΔCt from the Cts, and 2^−ΔΔCt from the means against qTOWER's own normalised expression
            var rs = ResultSet()
            for url in Store.expand([URL(fileURLWithPath: a[i + 1])]) { for t in (try? readTables(url)) ?? [] { rs.add(parseGenes(t)) } }
            let opt = ResultsOptions()
            var worst = 0.0
            for g in rs.genes {
                for s in g.samples {
                    guard let d = rs.delta(g, s.name, opt), let q = s.normExpr, let dm = meanSD(d.dct), let cal = d.calibrator,
                          let c = g.sample(cal), let cm = meanSD(c.cts), let cr = meanSD(c.refCts) else { continue }
                    let fromMeans = pow(2, -(dm.mean - (cm.mean - cr.mean)))
                    worst = max(worst, abs(fromMeans / q - 1))
                }
            }
            print("genes \(rs.genes.count), largest difference from qTOWER: \(String(format: "%.2f", worst * 100))%")
            print(tsv(rs.prismGrouped(.fold, opt)).split(separator: "\n").prefix(3).joined(separator: "\n"))
            print("qTOWER dCt, as copied:")
            print(tsv(rs.prismFileDCt(opt)), terminator: "")
            if a.count > i + 2 {
                // the same after a save and reopen, and from data saved before dCt was read
                var file = rs
                for gi in file.genes.indices { for si in file.genes[gi].samples.indices { file.genes[gi].samples[si].dctFile = nil } }
                let back = try! JSONDecoder().decode(ResultSet.self, from: JSONEncoder().encode(file))
                print("reopened old-style data matches:", back.prismFileDCt(opt) == rs.prismFileDCt(opt))
            }
            return
        }
        if a.contains("--dose-check") {
            // how sample names are read, and how two dose series pair up
            for n in ["A3_100pM", "A3_cont_0", "C2_10fM", "SAG_0", "SAG_0.01uM", "SAG 100 nM", "SAG+22(S)_1µM", "SAG+22(S) 0nM",
                      "SAG+22(S)_vehicle", "DMSO", "Shh 10ng/mL", "22(S) only", "LMX1A_10mM", "A3_100pM_rep2", "x_10min"] {
                if let r = Dose.read(n) { print(n.padding(toLength: 20, withPad: " ", startingAt: 0), "→", r.dose.text, r.dose.value, r.dose.mass ? "g/mL" : "M", "| series:", r.stem) }
                else { print(n.padding(toLength: 20, withPad: " ", startingAt: 0), "→ no dose") }
            }
            func demo(_ conds: [String]) -> ResultSet {
                var rs = ResultSet()
                for (gi, gene) in ["LMX1A", "CORIN", "FOXA2"].enumerated() {
                    var g = GeneResult(name: gene)
                    g.reference = "GAPDH"
                    for (k, c) in conds.enumerated() {
                        let plus = c.contains("22") ? 1.8 : 1.0
                        let step = Double(k % (conds.count / 2)) + 1
                        let v = k % (conds.count / 2) == 0 ? 1.0 : plus * step * step * (1 + 0.3 * Double(gi))
                        g.samples.append(SampleResult(name: c, type: "Unknown", replicates: 3, cts: [24, 24.2, 23.9], refCts: [17, 17.1, 16.9], normExpr: v, sd: v * 0.12))
                    }
                    rs.genes.append(g)
                }
                return rs
            }
            let sag = ["SAG_0", "SAG_0.01uM", "SAG_0.1uM", "SAG_1uM", "SAG+22(S)_0", "SAG+22(S)_10nM", "SAG+22(S)_100nM", "SAG+22(S)_1µM"]
            let rs = demo(sag)
            print("series:", rs.compareStems)
            var o = ResultsOptions(); o.compare = true; o.pickGroups = true
            o.membersA = rs.members(ofStem: "SAG"); o.membersB = rs.members(ofStem: "SAG+22(S)")
            if let c = rs.comparison(o) { print(c.nameA, "vs", c.nameB, c.mode.rawValue, c.pairs.map { "\($0.label): \($0.a ?? "-") | \($0.b ?? "-")" }) }
            o.pairBy = .order
            if let c = rs.comparison(o) { print("order:", c.mode.rawValue, c.pairs.map { $0.label }) }
            if let i = a.firstIndex(of: "--dose-check"), a.count > i + 1 {
                // a made-up dose series to try the comparison with
                let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                var opt = ResultsOptions(); opt.notes[0] = "DEMO: made-up numbers, SAG vs SAG+22(S)"
                let store = Store(inMemory: examplePlan())
                store.results = rs; store.options = opt
                try? store.writeData(to: URL(fileURLWithPath: a[i + 1]))
            }
            let a3 = ["A3_100pM", "A3_10pM", "A3_1pM", "A3_100fM", "A3_cont", "C2_100pM", "C2_10pM", "C2_1pM"]
            let r2 = demo(a3 + ["C2_extra"].filter { _ in false })
            var o2 = ResultsOptions(); o2.compare = true
            if let c = r2.comparison(o2) { print(c.nameA, "vs", c.nameB, c.mode.rawValue, c.pairs.map { $0.label }) }
            return
        }
        if let i = a.firstIndex(of: "--export-data"), a.count > i + 2 {
            // a saved .qpcrdata file to a graphs workbook, as Export Graphs would write it
            _ = NSApplication.shared
            let store = Store(inMemory: examplePlan())
            store.openData(URL(fileURLWithPath: a[i + 1]))
            if a.contains("--compare") { store.options.compare = true }
            if let j = a.firstIndex(of: "--groups"), a.count > j + 2 {
                store.options.pickGroups = true
                store.options.membersA = a[j + 1].split(separator: ",").map(String.init)
                store.options.membersB = a[j + 2].split(separator: ",").map(String.init)
            }
            try? buildResultsWorkbook(store.results, store.options, colors: store.resultColors).write(to: URL(fileURLWithPath: a[i + 2]))
            return
        }
        if a.contains("--layout-check") {
            // every layout, size and replicate count: each sample–primer pair gets exactly n wells on its
            // plate, no well is used twice, every pair appears once, and the mix counts match the wells
            var problems: [String] = [], checked = 0
            let out = a.firstIndex(of: "--layout-check").flatMap { a.count > $0 + 1 ? a[$0 + 1] : nil }
            for sampleCount in [0, 1, 2, 5, 8, 9, 12, 13, 25] {
                for geneCount in [0, 1, 2, 3, 6, 7, 11, 12, 15] {
                    for n in 1...6 {
                        for auto in [false, true] {
                            for l in SampleLayout.allCases {
                                var p = ProtocolPlan()
                                p.samples = (0..<sampleCount).map { NamedItem(name: "S\($0)") }
                                p.genes = (0..<geneCount).map { NamedItem(name: "G\($0)") }
                                p.replicates = n; p.layout = l; p.autoLayout = auto
                                let tag = "s\(sampleCount) g\(geneCount) n\(n) \(l.rawValue)\(auto ? " auto" : "")"
                                var pairs: [String: Int] = [:]
                                var total = 0
                                for plate in p.plates {
                                    var seen = Set<Int>()
                                    for s in plate.samples.indices {
                                        for b in plate.primers.indices {
                                            for k in 0..<n {
                                                let (r, c) = plate.well(s, b, k)
                                                if !(0..<8).contains(r) || !(0..<12).contains(c) { problems.append("\(tag): off plate"); continue }
                                                if !seen.insert(r * 12 + c).inserted { problems.append("\(tag): well used twice") }
                                                if let w = plate.content(r, c), w.sample == s, w.primer == b, w.rep == k {} else { problems.append("\(tag): content mismatch") }
                                                total += 1
                                            }
                                            pairs["\(plate.samples[s])|\(plate.primers[b])", default: 0] += 1
                                        }
                                    }
                                }
                                for s in p.sampleNames {
                                    for g in p.geneNames where pairs["\(s)|\(g)"] != 1 { problems.append("\(tag): \(s)/\(g) on \(pairs["\(s)|\(g)"] ?? 0) plates") }
                                    if (pairs["\(s)|\(p.reference)"] ?? 0) != p.referenceRuns { problems.append("\(tag): reference runs") }
                                }
                                if total != p.wellsPerGene * p.geneNames.count + p.wellsReference { problems.append("\(tag): \(total) wells vs mix \(p.wellsPerGene * p.geneNames.count + p.wellsReference)") }
                                if auto, let best = SampleLayout.allCases.map({ p.plateCount($0) }).min(), p.plates.count != best { problems.append("\(tag): auto not fewest") }
                                if let out, checked % 7 == 0 { try? buildProtocolWorkbook(p, ProtocolSettings()).write(to: URL(fileURLWithPath: "\(out)/l_\(checked).xlsx")) }
                                checked += 1
                            }
                        }
                    }
                }
            }
            print("checked \(checked) plans, \(problems.count) problems")
            for x in Set(problems).sorted().prefix(30) { print(x) }
            return
        }
        if let i = a.firstIndex(of: "--protocol-matrix"), a.count > i + 1 {
            // development check: protocols for many plate sizes, with the numbers they should contain
            var index = 0
            var summary: [[String: Double]] = []
            for sampleCount in [0, 1, 5, 8, 9, 17] {
                for geneCount in [0, 1, 3, 4, 7, 12] {
                    for n in [1, 2, 3, 4, 6] {
                        var p = ProtocolPlan()
                        p.title = "t/est:\(index) <&>"
                        p.samples = (0..<sampleCount).map { NamedItem(name: "S\($0)_x") }
                        p.genes = (0..<geneCount).map { NamedItem(name: "G\($0)") }
                        p.replicates = n
                        let st = ProtocolSettings()
                        try? buildProtocolWorkbook(p, st).write(to: URL(fileURLWithPath: "\(a[i + 1])/p_\(index).xlsx"))
                        try? buildMeltWorkbook(p).write(to: URL(fileURLWithPath: "\(a[i + 1])/m_\(index).xlsx"))
                        summary.append(["samples": Double(sampleCount), "genes": Double(geneCount), "n": Double(n),
                                        "plates": Double(p.plates.count), "wellsGene": Double(p.wellsPerGene),
                                        "wellsRef": Double(p.wellsReference), "wellsSample": Double(p.wellsPerSample)])
                        index += 1
                    }
                }
            }
            if let d = try? JSONEncoder().encode(summary) { try? d.write(to: URL(fileURLWithPath: a[i + 1] + "/summary.json")) }
            print("wrote \(index) protocols")
            return
        }
        if let i = a.firstIndex(of: "--make-icon"), a.count > i + 1 { makeIcon(a[i + 1]); return }
        if let i = a.firstIndex(of: "--snapshot"), a.count > i + 1 { snapshot(a[i + 1]); return }
        if let i = a.firstIndex(of: "--splash-snapshot"), a.count > i + 2, let t = Double(a[i + 2]) { splashSnapshot(a[i + 1], at: t); return }
        if let i = a.firstIndex(of: "--bench-snapshot"), a.count > i + 2, let step = Int(a[i + 2]) {
            // bench mode at a given step, with the first lines of each step before it ticked
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            let store = Store(inMemory: examplePlan())
            store.platesAnimating = false
            store.plateRevealAt = .distantPast
            let steps = store.benchSteps
            for s in steps.prefix(step) { for it in s.items { store.benchDone.insert(it.id) } }
            if step < steps.count { for it in steps[step].items.prefix(2) { store.benchDone.insert(it.id) } }
            store.benchStep = step
            let size = NSSize(width: 1512, height: 945)
            let host = NSHostingView(rootView: BenchView().environmentObject(store).frame(width: size.width, height: size.height))
            let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            win.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(1.0))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[i + 1]))
            }
            return
        }
        if let i = a.firstIndex(of: "--run-snapshot"), a.count > i + 2, let t = Double(a[i + 2]) {
            // development: the layer-drawn import run `t` seconds in
            _ = NSApplication.shared
            let store = Store(inMemory: examplePlan())
            let genes = ["LMX1A", "CORIN", "EN1", "FOXA2", "GBX2", "OTX2"].enumerated().map {
                ShowGene(name: $0.element, hex: ["5FA046", "E0742B", "F2C232", "7E5BAF", "7E5BAF", "C0392B"][$0.offset], ct: [25.4, 27.1, 30.2, 24.0, 26.3, 28.8][$0.offset])
            }
            let v = ImportRunView(show: ImportShow(date: Date().addingTimeInterval(-t), genes: genes, conditions: 6), store: store)
            v.frame = NSRect(x: 0, y: 0, width: 900, height: 560)
            v.layout()
            if let ctx = CGContext(data: nil, width: 1800, height: 1120, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 1800, height: 1120))
                ctx.scaleBy(x: 2, y: 2)
                v.layer?.render(in: ctx)
                if let img = ctx.makeImage() { try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[i + 1])) }
            }
            return
        }
        if let i = a.firstIndex(of: "--export-files"), a.count > i + 2 {
            // development: import these files as a drop would, then write the graphs workbook
            _ = NSApplication.shared
            let store = Store(inMemory: examplePlan())
            store.importFiles(a[(i + 2)...].map { URL(fileURLWithPath: $0) })
            print(store.importMessage)
            for e in store.results.extras { print("kept tab:", e.name, "· pictures:", e.layout?.pictures.count ?? 0, "· coloured cells:", e.layout?.styled.count ?? 0) }
            try? buildResultsWorkbook(store.results, store.options, colors: store.resultColors).write(to: URL(fileURLWithPath: a[i + 1]))
            // saved data keeps them: write and read back a .qpcrdata
            let tmp = URL(fileURLWithPath: a[i + 1] + ".qpcrdata")
            try? store.writeData(to: tmp)
            let back = Store(inMemory: examplePlan())
            back.openData(tmp)
            print("after saving and reopening:", back.results.extras.map { "\($0.name) · \($0.layout?.pictures.count ?? 0) pictures" }.joined(separator: ", "),
                  "· same:", back.results.extras.map { $0.layout } == store.results.extras.map { $0.layout })
            return
        }
        if let i = a.firstIndex(of: "--lag-check"), a.count > i + 1 {
            // development: the real window through the waiting loop, a drop and import, and the graphs page,
            // measuring CPU, the cost of each ambient tick, and main-thread stalls (frames the screen waits for)
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let store = Store(inMemory: examplePlan())
            store.mode = .results
            let host = NSHostingView(rootView: ContentView().environmentObject(store).frame(width: 1360, height: 900))
            let win = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1360, height: 900), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            win.contentView = host
            win.orderFrontRegardless()
            store.appActive = true
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            var ticks: [Double] = [], gaps: [Double] = []
            AmbientClock.probe = { ticks.append($0) }
            var lastBeat = CACurrentMediaTime()
            let beat = Timer(timeInterval: 1.0 / 120, repeats: true) { _ in
                let now = CACurrentMediaTime(); gaps.append((now - lastBeat) * 1000); lastBeat = now
            }
            beat.tolerance = 0
            RunLoop.main.add(beat, forMode: .common)
            func cpu() -> Double {
                var r = rusage(); getrusage(RUSAGE_SELF, &r)
                return Double(r.ru_utime.tv_sec + r.ru_stime.tv_sec) + Double(r.ru_utime.tv_usec + r.ru_stime.tv_usec) / 1e6
            }
            func phase(_ name: String, _ secs: Double, _ start: () -> Void = {}) {
                ticks = []; gaps = []; lastBeat = CACurrentMediaTime()
                let c0 = cpu(), t0 = Date()
                start()
                var series: [String] = []
                var cPrev = c0, tPrev = Date()
                while Date().timeIntervalSince(t0) < secs {
                    RunLoop.main.run(until: min(t0.addingTimeInterval(secs), tPrev.addingTimeInterval(0.5)))
                    let c = cpu(), now = Date()
                    series.append(String(format: "%.0f", (c - cPrev) / now.timeIntervalSince(tPrev) * 100))
                    cPrev = c; tPrev = now
                }
                if a.contains("--series") { print("   CPU every 0.5 s:", series.joined(separator: " ")) }
                let wall = Date().timeIntervalSince(t0), used = cpu() - c0
                let tickAvg = ticks.isEmpty ? 0 : ticks.reduce(0, +) / Double(ticks.count)
                let hitches = gaps.filter { $0 > 34 }
                print(String(format: "%@: CPU %.1f%% · ambient %.1f ticks/s, avg %.2f ms, max %.2f ms · main-thread stalls >34 ms: %d (worst %.0f ms)",
                             name, used / wall * 100, Double(ticks.count) / wall, tickAvg, ticks.max() ?? 0, hitches.count, gaps.max() ?? 0))
            }
            if a.contains("--isolate") {
                phase("the run overlay alone (5 s)", 5) {
                    store.importShow = ImportShow(genes: ["LMX1A", "CORIN", "EN1", "FOXA2", "GBX2", "OTX2"].enumerated().map { ShowGene(name: $0.element, hex: ["2FA84F", "E2483D", "F2A900", "8E5BD1", "8E5BD1", "C0392B"][$0.offset], ct: 22 + Double($0.offset)) }, conditions: 6)
                }
                store.importShow = nil
                phase("import, no animations (4 s)", 4) {
                    store.animations = false
                    store.importFiles([URL(fileURLWithPath: a[i + 1])])
                }
                return
            }
            phase("waiting loop (17 s)", 17)
            phase("drop + import show (8 s)", 8) { store.dropFiles([URL(fileURLWithPath: a[i + 1])]) }
            phase("graphs page, idle (6 s)", 6)
            phase("spotlight a condition (3 s)", 3) { store.toggleSpotlight("c:" + (store.results.conditions.first ?? "")) }
            phase("export confetti (4 s)", 4) { store.confettiAt = Date() }
            beat.invalidate()
            return
        }
        if let i = a.firstIndex(of: "--drop-test"), a.count > i + 1 {
            // development: files dropped on the waiting page go through the qTOWER and are imported
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            let store = Store(inMemory: examplePlan())
            store.mode = .results
            let host = NSHostingView(rootView: ContentView().environmentObject(store).frame(width: 1360, height: 900))
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
            win.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let t0 = Date()
            store.dropFiles([URL(fileURLWithPath: a[i + 1])])
            print("motion:", store.motion, "· gulp started:", store.gulp != nil)
            while store.results.genes.isEmpty && Date().timeIntervalSince(t0) < 6 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            print(String(format: "imported %d genes after %.2f s", store.results.genes.count, Date().timeIntervalSince(t0)), "· import show playing:", store.importShow != nil)
            return
        }
        if let i = a.firstIndex(of: "--sandbox-live"), a.count > i + 1, let secs = Double(a[i + 1]) {
            // the waiting panel playing in a window of its own for `secs` seconds (development: measuring its cost)
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let v = RunSandboxView(frame: NSRect(x: 0, y: 0, width: 920, height: 520))
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 520), styleMask: [.titled], backing: .buffered, defer: false)
            win.contentView = v
            win.center()
            win.orderFrontRegardless()
            v.ambientActive = true
            RunLoop.main.run(until: Date().addingTimeInterval(secs))
            return
        }
        if let i = a.firstIndex(of: "--sandbox-gif"), a.count > i + 1 {
            // the whole waiting loop as an animated GIF, drawn on the card's colour (development: to look at it)
            _ = NSApplication.shared
            let v = RunSandboxView(frame: NSRect(x: 0, y: 0, width: 920, height: 520))
            v.appearance = NSAppearance(named: a.contains("--dark") ? .darkAqua : .aqua)
            v.layout()
            let card = a.contains("--dark") ? NSColor(hex: "102B50") : NSColor.white
            let url = URL(fileURLWithPath: a[i + 1]) as CFURL
            let fps = 12.0, length = v.loopLength
            let count = Int(length * fps)
            guard let dest = CGImageDestinationCreateWithURL(url, "com.compuserve.gif" as CFString, count, nil) else { return }
            CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            let scale: CGFloat = 0.75
            for f in 0..<count {
                v.preview(at: Double(f) / fps)
                guard let ctx = CGContext(data: nil, width: Int(920 * scale), height: Int(520 * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
                ctx.setFillColor(card.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 920 * scale, height: 520 * scale))
                ctx.scaleBy(x: scale, y: scale)
                v.layer?.render(in: ctx)
                if let img = ctx.makeImage() {
                    CGImageDestinationAddImage(dest, img, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary)
                }
            }
            CGImageDestinationFinalize(dest)
            return
        }
        if let i = a.firstIndex(of: "--sandbox-snapshot"), a.count > i + 2, let t = Double(a[i + 2]) {
            // the waiting panel `t` seconds into its run, drawn from its layers
            _ = NSApplication.shared
            let v = RunSandboxView(frame: NSRect(x: 0, y: 0, width: 920, height: 520))
            v.appearance = NSAppearance(named: a.contains("--dark") ? .darkAqua : .aqua)
            v.eager = a.contains("--eager")
            v.preview(at: t)
            let bitesArg = a.firstIndex(of: "--bites").flatMap { a.count > $0 + 1 ? Int(a[$0 + 1]) : nil }
            let pokeArg = a.firstIndex(of: "--poked").flatMap { a.count > $0 + 1 ? Double(a[$0 + 1]) : nil }
            if let gi = a.firstIndex(of: "--gulp"), a.count > gi + 1, let ago = Double(a[gi + 1]) {
                v.previewGulp(["LMX1A.xls", "CORIN.xls", "EN1.xls", "FOXA2.xls", "GBX2.xls", "OTX2.xls"], ago: ago)
            }
            if bitesArg != nil || pokeArg != nil {
                v.previewTweaks(bites: bitesArg ?? 0, pokedAgo: pokeArg)
                v.preview(at: t)
            }
            let scale: CGFloat = 2
            if let ctx = CGContext(data: nil, width: 1840, height: 1040, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                // on the card it sits on: white, or the dark-mode navy
                ctx.setFillColor((a.contains("--dark") ? NSColor(hex: "102B50") : NSColor.white).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: 1840, height: 1040))
                ctx.scaleBy(x: scale, y: scale)
                v.layer?.render(in: ctx)
                if let img = ctx.makeImage() {
                    let rep = NSBitmapImageRep(cgImage: img)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[i + 1]))
                }
            }
            return
        }
        launchObserver = NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
            SplashController.shared.showAtLaunch()
            // development: serve bench mode at once and write its address to the given file
            if let i = a.firstIndex(of: "--serve-bench"), a.count > i + 1 {
                BenchServer.shared.onChange = { try? BenchServer.shared.urls.joined(separator: "\n").write(toFile: a[i + 1], atomically: true, encoding: .utf8) }
                BenchServer.shared.start()
            }
        }
        PlannerApp.main()
    }
}

/// Development flags shared by the sample exports and snapshots: --layout rows|columns|primerRows|primerColumns,
/// --auto-layout, --samples N, --genes N, --n N.
func applyLayoutFlags(_ p: inout ProtocolPlan) {
    let a = CommandLine.arguments
    func value(_ f: String) -> String? { a.firstIndex(of: f).flatMap { a.count > $0 + 1 ? a[$0 + 1] : nil } }
    if let v = value("--layout"), let l = SampleLayout(rawValue: v) { p.layout = l }
    if a.contains("--auto-layout") { p.autoLayout = true }
    if let v = value("--samples").flatMap(Int.init) {
        let groups = ["A3", "C2", "B1", "D4"], doses = ["100pM", "10pM", "1pM", "100fM", "cont_0", "10fM"]
        p.samples = (0..<v).map { NamedItem(name: "\(groups[($0 / doses.count) % groups.count])_\(doses[$0 % doses.count])") }
        p.calibratorID = p.samples.first { $0.name.hasSuffix("cont_0") }?.id
    }
    if let v = value("--genes").flatMap(Int.init) {
        let names = ["LMX1A", "CORIN", "EN1", "FOXA2", "SFRP1", "PTCH1", "OTX2", "GBX2", "TH", "NURR1", "PITX3"]
        p.genes = (0..<v).map { NamedItem(name: names[$0 % names.count]) }
    }
    if let v = value("--n").flatMap(Int.init) { p.replicates = v }
}

/// The lab's 17 Sep 2026 run, dated as on its own protocol sheet.
func examplePlan() -> ProtocolPlan {
    var p = ProtocolPlan.example
    var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 17
    p.date = Calendar.current.date(from: c) ?? Date()
    return p
}

/// Files dropped on the Dock icon or opened with "Open With": qTOWER exports, run folders or saved data.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Store.current?.openFromFinder(urls)
    }
}

struct PlannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()

    var body: some Scene {
        Window("qPCR Planner", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1080, idealWidth: 1360, minHeight: 640, idealHeight: 880)
                .onAppear {
                    if let note = Updater.shared.noteIfJustUpdated() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { store.showToast(note) }
                    }
                    Updater.shared.checkAtLaunch()
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                BenchButton(menu: true).environmentObject(store)
                IPadButton(menu: true).environmentObject(store)
            }
            CommandGroup(before: .toolbar) {
                Picker("Appearance", selection: Binding(get: { store.appearance }, set: { store.appearance = $0 })) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                Divider()
            }
            CommandGroup(replacing: .appInfo) {
                Button("About qPCR Planner") { SplashController.shared.showAbout() }
                Button("Check for Updates…") { Updater.shared.check(userInitiated: true) }
                Toggle("Check for Updates Automatically", isOn: Binding(get: { Updater.automatic }, set: { Updater.automatic = $0 }))
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Results…") { store.switchMode(.results); store.openResults() }.keyboardShortcut("o")
                Divider()
                Button("Open Protocol…") { store.openPlan() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Save Protocol…") { store.savePlan() }.keyboardShortcut("s")
                Divider()
                Button("Export Excel…") { store.export() }.keyboardShortcut("e")
                Divider()
                Toggle("Animations", isOn: Binding(get: { store.animations }, set: { store.animations = $0 }))
                Toggle("Show Eppi the Tube", isOn: Binding(get: { store.showEppi }, set: { store.showEppi = $0 }))
                Toggle("Trackpad Feedback", isOn: Binding(get: { store.haptics }, set: { store.haptics = $0 }))
                Toggle("Show Splash at Launch", isOn: Binding(get: { SplashController.enabledAtLaunch }, set: { SplashController.enabledAtLaunch = $0 }))
            }
        }
        Window("Bench Mode", id: "bench") {
            BenchView().environmentObject(store)
        }
        .defaultSize(width: 1400, height: 900)
    }
}

// MARK: - State

enum Mode: String { case plan, results }

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { self == .system ? "Match System" : (self == .light ? "Light" : "Dark") }
}

struct Receipt: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    var detail: String? = nil
    let image: NSImage?
}

/// Writes the protocol export: a folder holding the protocol workbook and the prepared melt-curve sheet.
/// A melt sheet already in the folder is kept (it may hold pasted screenshots); says whether it was.
func writeProtocolFolder(_ plan: ProtocolPlan, _ st: ProtocolSettings, colors: GeneColors, to folder: URL) throws -> (URL, Bool) {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    if fm.fileExists(atPath: folder.path, isDirectory: &isDir), !isDir.boolValue {
        throw NSError(domain: "qPCRPlanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(folder.lastPathComponent) is a file, not a folder. Choose another name."])
    }
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let protocolURL = folder.appendingPathComponent(plan.protocolFileName)
    try buildProtocolWorkbook(plan, st, colors: colors).write(to: protocolURL, options: .atomic)
    let meltURL = folder.appendingPathComponent(plan.meltFileName)
    let kept = fm.fileExists(atPath: meltURL.path)
    if !kept { try buildMeltWorkbook(plan).write(to: meltURL, options: .atomic) }
    return (protocolURL, kept)
}

/// Imported results saved by the app, to reopen later without the original qTOWER exports.
let dataFileType = UTType(exportedAs: "lab.qpcr.planner.data", conformingTo: .json)
let planFileType = UTType(exportedAs: "lab.qpcr.planner.plan", conformingTo: .json)

/// A saved protocol (.qpcrplan): the plan and the volume settings it was made with, as readable JSON.
struct PlanFile: Codable {
    var app = "qPCR Planner"
    var version = 1
    var plan: ProtocolPlan
    var settings: ProtocolSettings
}

func encodePlanFile(_ p: ProtocolPlan, _ st: ProtocolSettings) throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try enc.encode(PlanFile(plan: p, settings: st))
}

func decodePlanFile(_ d: Data) throws -> PlanFile {
    let f = try JSONDecoder().decode(PlanFile.self, from: d)
    guard f.app == "qPCR Planner" else {
        throw NSError(domain: "qPCRPlanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "It was not saved by qPCR Planner."])
    }
    return f
}

/// Enables files in the Open panel by their extension, so a saved .qpcrdata file can always be picked
/// (macOS only knows that type once the app has been registered).
final class ImportPanelFilter: NSObject, NSOpenSavePanelDelegate {
    static let extensions: Set<String> = ["xls", "xlsx", "csv", "txt", "tsv", "qpcrdata", "qpcrplan"]
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return true }
        return Self.extensions.contains(url.pathExtension.lowercased())
    }
}

private struct SavedState: Codable {
    var plan: ProtocolPlan
    var settings: ProtocolSettings
    var options: ResultsOptions
    var geneLibrary: [String]
    var geneColors: [String: String]?
}

final class Store: ObservableObject {
    @Published var plan: ProtocolPlan {
        didSet {
            save()
            if Self.layoutKey(plan) != Self.layoutKey(oldValue) { revealPlates() }
        }
    }
    @Published var settings: ProtocolSettings { didSet { save() } }
    @Published var options: ResultsOptions { didSet { save() } }
    @Published var geneLibrary: [String] { didSet { save() } }
    @Published var results = ResultSet()
    @Published var mode: Mode = .plan
    @Published var importMessage = ""
    /// Files on their way into the waiting qTOWER; they are imported once it has swallowed them.
    @Published var gulp: Gulp? = nil
    /// Colours picked for genes (by upper-case name), shared by primers, plate maps and graphs.
    @Published var geneColorMap: [String: String] = [:] { didSet { save() } }
    @Published var animations: Bool = UserDefaults.standard.object(forKey: "animations") as? Bool ?? true {
        didSet { if persist { UserDefaults.standard.set(animations, forKey: "animations") } }
    }
    /// Light, dark (the splash's navy), or whatever the Mac is set to.
    @Published var appearance: Appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system {
        didSet { if persist { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }; applyAppearance() }
    }

    func applyAppearance() {
        NSApp?.appearance = appearance == .system ? nil : NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
    }

    /// A faint tap under the finger on a Force Touch trackpad when something lands or snaps into place.
    @Published var haptics: Bool = UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true {
        didSet { if persist { UserDefaults.standard.set(haptics, forKey: "haptics") } }
    }

    func tap(_ kind: NSHapticFeedbackManager.FeedbackPattern = .generic) {
        guard haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(kind, performanceTime: .now)
    }

    @Published var showEppi: Bool = UserDefaults.standard.object(forKey: "showEppi") as? Bool ?? true {
        didSet { if persist { UserDefaults.standard.set(showEppi, forKey: "showEppi") } }
    }
    // animation events
    @Published var eppiEvent: EppiEvent? = nil
    @Published var confettiAt = Date.distantPast
    @Published var toast: Toast? = nil
    /// The card shown after an export: a picture of what was saved, and where it went.
    @Published var receipt: Receipt? = nil
    // bench mode: which lines are ticked, and the step on screen
    @Published var benchDone: Set<String> = [] { didSet { saveBench() } }
    @Published var benchStep = 0 { didSet { saveBench() } }

    /// Bench progress is kept for the run it belongs to, so quitting mid-experiment loses nothing.
    private func saveBench() {
        guard persist else { return }
        UserDefaults.standard.set(["run": plan.runName, "done": Array(benchDone), "step": benchStep] as [String: Any], forKey: "benchProgress")
    }

    private func restoreBench() {
        guard let saved = UserDefaults.standard.dictionary(forKey: "benchProgress"), saved["run"] as? String == plan.runName else { return }
        benchDone = Set(saved["done"] as? [String] ?? [])
        benchStep = saved["step"] as? Int ?? 0
    }
    // bench mode on the iPad
    @Published var showIPadLink = false
    var ipadSeen: Date? = nil            // last request from the iPad (not published: polls must not redraw the window)
    var receiptHeld = false
    @Published var importShow: ImportShow? = nil {
        didSet {
            guard importShowInWindow, importShow?.id != oldValue?.id else { return }
            if let show = importShow { ImportShowWindow.shared.present(show, self) } else { ImportShowWindow.shared.dismiss() }
        }
    }
    /// The run plays in a small window of its own over the main one (snapshots draw it in place).
    var importShowInWindow = true
    // a condition picked out in every graph and the table
    @Published var spotlight: String? = nil
    var spotlightPrev: String? = nil
    var spotlightAt = Date.distantPast
    @Published var spotlightFading = false
    private var spotlightToken = 0
    // bars travelling between "by condition" and "compare"
    @Published var morphing = false
    var morphAt = Date.distantPast
    private var morphToken = 0
    var debugMorph: Bool { morphing }

    @Published var chartRevealAt = Date.distantPast
    @Published var chartsAnimating = false
    @Published var plateRevealAt = Date.distantPast
    @Published var platesAnimating = false
    private var chartToken = 0, plateToken = 0
    /// Whether the app is in front; long-running animations pause when it is not.
    /// Ambient motion runs only while the app is in front; it starts off until the app is actually activated
    /// (it can be launched in the background).
    @Published var appActive = false
    private var observers: [NSObjectProtocol] = []
    var persist = true

    static let defaultGenes = ["LMX1A", "CORIN", "EN1", "FOXA2", "PTCH1", "SFRP1", "GLI1", "GLI3"]

    private static var stateURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("qPCR Planner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    private let importFilter = ImportPanelFilter()

    /// The window's store, for files handed over by Finder.
    static weak var current: Store?

    init() {
        defer { Store.current = self }
        if let d = try? Data(contentsOf: Self.stateURL), let s = try? JSONDecoder().decode(SavedState.self, from: d) {
            plan = s.plan; settings = s.settings; options = s.options; geneLibrary = s.geneLibrary
            geneColorMap = s.geneColors ?? [:]
        } else {
            if FileManager.default.fileExists(atPath: Self.stateURL.path) {
                let stamp = Int(Date().timeIntervalSince1970)
                try? FileManager.default.copyItem(at: Self.stateURL, to: Self.stateURL.deletingLastPathComponent().appendingPathComponent("state.unreadable-\(stamp).json"))
            }
            plan = .example; settings = ProtocolSettings(); options = ResultsOptions(); geneLibrary = Self.defaultGenes
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.revealPlates() }
        restoreBench()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.appActive = true })
        observers.append(nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.appActive = false })
        DispatchQueue.main.async { [weak self] in
            self?.appActive = NSApp?.isActive ?? false
            self?.applyAppearance()
        }
    }

    /// A store that never touches the saved file (development checks only).
    init(inMemory plan: ProtocolPlan) {
        self.plan = plan; settings = ProtocolSettings(); options = ResultsOptions(); geneLibrary = Self.defaultGenes
        persist = false
    }

    private func save() {
        guard persist else { return }
        let s = SavedState(plan: plan, settings: settings, options: options, geneLibrary: geneLibrary, geneColors: geneColorMap)
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: Self.stateURL, options: .atomic) }
    }

    // MARK: colours

    var colors: GeneColors { GeneColors(custom: geneColorMap) }

    func setColor(_ name: String, _ hex: String?) {
        let key = name.trimmingCharacters(in: .whitespaces).uppercased()
        guard !key.isEmpty else { return }
        if let h = validHex(hex) { geneColorMap[key] = h } else { geneColorMap.removeValue(forKey: key) }
    }

    /// A result gene's colour: its custom colour, else the colour its primer has in the protocol,
    /// else the default for its position in the results.
    func resultColor(_ name: String, _ index: Int) -> String {
        if let c = colors.custom(name) { return c }
        if let j = plan.geneNames.firstIndex(where: { $0.uppercased() == name.uppercased() }) { return geneColor(j + 1) }
        if plan.reference.uppercased() == name.uppercased() { return geneColor(0) }
        return geneColor(index)
    }

    /// Every result gene's colour, written out for the Excel builder.
    var resultColors: GeneColors {
        var m: [String: String] = [:]
        for (i, g) in results.genes.enumerated() { m[g.name.uppercased()] = resultColor(g.name, i) }
        return GeneColors(custom: m)
    }

    // MARK: animation events

    private static func layoutKey(_ p: ProtocolPlan) -> String { "\(p.sampleNames.count)|\(p.geneNames.count)|\(p.n)|\(p.activeLayout.rawValue)" }

    func setLayout(_ l: SampleLayout) {
        tap(.alignment)
        let before = plan.plates.count
        var p = plan
        p.layout = l
        p.autoLayout = false
        plan = p
        cheerPlates(before)
    }

    /// Turning "fewest plates" off keeps the layout it had picked.
    func setAutoLayout(_ on: Bool) {
        tap(.alignment)
        let before = plan.plates.count
        var p = plan
        if !on { p.layout = p.activeLayout }
        p.autoLayout = on
        plan = p
        cheerPlates(before)
    }

    private func cheerPlates(_ before: Int) {
        let after = plan.plates.count
        if after < before { eppi(.dance, after == 1 ? "All on one plate! Less plastic!" : "\(before - after) plate\(before - after == 1 ? "" : "s") saved!") }
        else if after > before { eppi(.jump, "\(after) plates? More pipetting!") }
    }

    func revealPlates(after delay: Double = 0) {
        plateRevealAt = Date().addingTimeInterval(delay)
        platesAnimating = true
        plateToken += 1
        let tok = plateToken, plates = Double(plan.plates.count)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.9 + 0.35 * plates) { [weak self] in
            if self?.plateToken == tok { self?.platesAnimating = false }
        }
    }

    func revealCharts(after delay: Double = 0) {
        chartRevealAt = Date().addingTimeInterval(delay)
        chartToken += 1
        let tok = chartToken
        // the graphs only start moving when their turn comes (not while the run plays over them)
        chartsAnimating = delay <= 0
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                if self?.chartToken == tok { self?.chartsAnimating = true }
            }
        }
        // the bars grow for 0.6 s each, 0.06 s apart: stop redrawing the moment the last one lands
        let bars = Double(max(1, results.conditions.count)) * (options.compare ? 2 : 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.75 + 0.06 * bars) { [weak self] in
            if self?.chartToken == tok { self?.chartsAnimating = false }
        }
    }

    func eppi(_ mood: EppiMood, _ text: String, after delay: Double = 0) {
        guard motion else { return }
        eppiEvent = EppiEvent(mood: mood, text: text, date: Date().addingTimeInterval(delay))
    }

    func pokeEppi() {
        let lines = ["Wheee!", "Hey! I'm sterile, you know.", "Again! Again!", "Careful, I'm full of SYBR!",
                     "Boop! Now spin me down.", "That tickles my meniscus!"]
        eppi([EppiMood.jump, .dance, .cheer][Int.random(in: 0..<3)], lines.randomElement() ?? "Wheee!")
    }

    func showToast(_ text: String) {
        let t = Toast(text: text)
        withAnimation { toast = t }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) { [weak self] in
            if self?.toast?.id == t.id { withAnimation { self?.toast = nil } }
        }
    }

    /// After an export: the receipt card, confetti and a cheer.
    func showReceipt(_ url: URL, title: String? = nil, detail: String? = nil) {
        let plan = mode == .plan
        let r = Receipt(url: url, title: title ?? (plan ? "Protocol exported" : "Graphs exported"), detail: detail, image: receiptImage())
        receipt = r
        tap(.levelChange)
        dismissReceipt(r.id, after: 12)
        guard motion else { return }
        confettiAt = Date()
        eppi(.cheer, plan ? "Protocol saved! Go pipette!" : "Graphs exported! SCIENCE!")
    }

    private func dismissReceipt(_ id: UUID, after: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
            guard let self, self.receipt?.id == id else { return }
            if self.receiptHeld { self.dismissReceipt(id, after: 3); return }   // not while the pointer is on it
            self.receipt = nil
        }
    }

    /// A picture of what was exported: the first plate, or the first gene's graph.
    private func receiptImage() -> NSImage? {
        let view: AnyView
        if mode == .plan, let plate = plan.plates.first {
            view = AnyView(PlateArrangement(plate: plate, n: plan.n, calibrator: plan.calibratorName, order: 0)
                .environmentObject(self).padding(10).background(Color.white))
        } else if !results.genes.isEmpty {
            view = AnyView(receiptChart(self).frame(width: 440, height: 300).environmentObject(self).background(Color.white))
        } else {
            return nil
        }
        return MainActor.assumeIsolated {
            let r = ImageRenderer(content: view.environment(\.colorScheme, .light))
            r.scale = 2
            return r.nsImage
        }
    }

    func celebrate(_ toastText: String, _ eppiText: String) {
        showToast(toastText)
        guard motion else { return }
        confettiAt = Date()
        eppi(.cheer, eppiText)
    }

    func switchMode(_ m: Mode) {
        guard m != mode else { return }
        if motion { withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { mode = m } } else { mode = m }
        if m == .results {
            revealCharts(after: 0.3)
            eppi(.jump, results.genes.isEmpty ? "To the qTOWER! Feed me results!" : "To the graphs!")
        } else {
            revealPlates(after: 0.3)
            eppi(.jump, "Back to the bench!")
        }
    }

    // MARK: protocol

    func toggleCalibrator(_ id: UUID) {
        tap(.generic)
        plan.calibratorID = plan.calibratorID == id ? nil : id
    }

    func removeSample(_ id: UUID) {
        plan.samples.removeAll { $0.id == id }
        if plan.calibratorID == id { plan.calibratorID = nil }
    }

    func newProtocol() {
        let a = NSAlert()
        a.messageText = "Start a new protocol?"
        a.informativeText = "The run title, samples and primers are cleared. Your volume settings are kept."
        a.addButton(withTitle: "New Protocol")
        a.addButton(withTitle: "Cancel")
        sheet(a) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            NSApp.keyWindow?.makeFirstResponder(nil)
            var p = ProtocolPlan()
            p.referenceGene = self.plan.referenceGene
            p.replicates = self.plan.replicates
            p.layout = self.plan.layout
            p.autoLayout = self.plan.autoLayout
            p.samples = [NamedItem()]
            p.genes = [NamedItem()]
            self.plan = p
            self.benchDone = []
            self.benchStep = 0
            self.eppi(.dance, "Fresh plate, fresh start!")
        }
    }

    func addSample() {
        plan.samples.append(NamedItem())
        let lines = ["Another sample! The more the merrier.", "Row \(rowLetters[(plan.samples.count - 1) % 8]), coming up!", "Ooh, a new sample!"]
        eppi(.jump, lines[plan.samples.count % lines.count])
    }

    func addGene(_ name: String = "") {
        plan.genes.append(NamedItem(name: name))
        eppi(.jump, name.isEmpty ? "A new primer! So specific!" : "\(name)? Great choice!")
    }

    // MARK: panels and alerts, as sheets
    //
    // A sheet slides down from the window and leaves the app running behind it, so a button's ripple
    // finishes and nothing has to wait for it. Without a visible window (the splash is still up, or a
    // development check), the panel or alert opens on its own as before.

    private var sheetWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.alphaValue > 0 && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
    }

    private func sheet(_ panel: NSSavePanel, _ done: @escaping (Bool) -> Void) {
        if let w = sheetWindow {
            guard w.attachedSheet == nil else { return }       // one at a time
            panel.beginSheetModal(for: w) { done($0 == .OK) }
        } else {
            done(panel.runModal() == .OK)
        }
    }

    private func sheet(_ alert: NSAlert, _ done: @escaping (NSApplication.ModalResponse) -> Void = { _ in }) {
        if let w = sheetWindow, w.attachedSheet == nil {
            alert.beginSheetModal(for: w, completionHandler: done)
        } else {
            done(alert.runModal())
        }
    }

    /// A message, shown once any sheet that led to it has gone.
    func showAlert(_ title: String, _ text: String) {
        DispatchQueue.main.async { [weak self] in
            let a = NSAlert()
            a.messageText = title
            a.informativeText = text
            self?.sheet(a)
        }
    }

    // MARK: results

    func openResults() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.delegate = importFilter
        panel.message = "Choose the qTOWER exports (one .xls per gene), the run's folder, a workbook with one sheet per gene, or a saved .qpcrdata file."
        sheet(panel) { [weak self] ok in
            guard ok else { return }
            let urls = panel.urls
            DispatchQueue.main.async { self?.dropFiles(urls) }   // after the sheet has slid away
        }
    }

    /// Files dropped on the results page or opened. While the qTOWER waits for a run it swallows them
    /// first (a second, with Animations on); otherwise they are imported straight away.
    func dropFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard mode == .results, results.genes.isEmpty, results.extras.isEmpty, motion, gulp == nil else {
            importFiles(urls)
            return
        }
        let g = Gulp(urls: urls)
        gulp = g
        // never hold the files back for long, whatever happens on screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.finishGulp(g.id) }
    }

    func finishGulp(_ id: UUID) {
        guard let g = gulp, g.id == id else { return }
        gulp = nil
        importFiles(g.urls)
    }

    /// A folder stands for the result files inside it: the instrument's own .xls exports if there are
    /// any, otherwise the workbooks and text files.
    static func expand(_ urls: [URL]) -> [URL] {
        var out: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { out.append(url); continue }
            let inside = ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                .filter { !$0.lastPathComponent.hasPrefix(".") && !$0.lastPathComponent.hasPrefix("~$") }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let raw = inside.filter { $0.pathExtension.lowercased() == "xls" }
            out += raw.isEmpty ? inside.filter { ["xlsx", "csv", "txt", "tsv"].contains($0.pathExtension.lowercased()) } : raw
            // a melt curve saved in another format beside the instrument's .xls files
            if !raw.isEmpty {
                out += inside.filter { u in
                    ["xlsx", "csv", "txt", "tsv"].contains(u.pathExtension.lowercased()) &&
                        ["melt", "融解", "dissociation"].contains { u.lastPathComponent.lowercased().contains($0) }
                }
            }
        }
        return out
    }

    func moveGene(_ id: UUID, by offset: Int) {
        guard let i = results.genes.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard results.genes.indices.contains(j) else { return }
        results.genes.swapAt(i, j)
    }

    func importFiles(_ picked: [URL]) {
        if let saved = picked.first(where: { $0.pathExtension.lowercased() == "qpcrplan" }) {
            openPlanFile(saved)
            return
        }
        if let saved = picked.first(where: { $0.pathExtension.lowercased() == "qpcrdata" }) {
            openData(saved)
            return
        }
        tap(.levelChange)      // the files have landed
        var messages: [String] = []
        var foundAny = false, keptAny = false
        let urls = Self.expand(picked)
        let pickedOne = Set(picked.map { $0.standardizedFileURL })
        if urls.isEmpty { messages.append("No result files were found there.") }
        for url in urls {
            do {
                let tables = try readTables(url)
                var found: [GeneResult] = []
                for t in tables { found += parseGenes(t) }
                results.add(found)
                if !found.isEmpty { foundAny = true }
                let skipped = tables.count - Set(found.map { $0.source }).count
                if found.isEmpty {
                    // no Ct table: a melt curve (or a file picked on purpose) is kept as its own tab
                    let melt = ExtraSheet.looksLikeMelt(url.lastPathComponent, tables)
                    // a sheet counts if it has text or pictures (a melt curve can be screenshots alone)
                    let filled = tables.filter { !$0.rows.allSatisfy { $0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } } || !$0.layout.pictures.isEmpty }
                    if (melt || pickedOne.contains(url.standardizedFileURL)) && !filled.isEmpty {
                        let base = url.deletingPathExtension().lastPathComponent
                        for t in filled {
                            let tab = melt ? (filled.count > 1 ? "Melt curve \(t.name)" : "Melt curve") : (filled.count > 1 ? "\(base) \(t.name)" : base)
                            results.addExtra(ExtraSheet(name: tab, source: url.lastPathComponent + (filled.count > 1 ? " · " + t.name : ""), rows: t.rows, melt: melt,
                                                        layout: t.layout.isEmpty ? nil : t.layout))
                        }
                        keptAny = true
                        let pics = filled.reduce(0) { $0 + $1.layout.pictures.count }
                        messages.append("\(url.lastPathComponent): \(melt ? "melt curve" : "no Ct table")\(pics > 0 ? " with \(pics) picture\(pics == 1 ? "" : "s")" : ""), kept as its own tab in the graphs workbook.")
                    } else {
                        messages.append("\(url.lastPathComponent): no result table found (it needs the instrument's \"Well / Sample name / GOI\" table).")
                    }
                } else {
                    messages.append("\(url.lastPathComponent): \(found.count) gene\(found.count == 1 ? "" : "s")" + (skipped > 0 ? ", \(skipped) other sheet\(skipped == 1 ? "" : "s") ignored" : "") + ".")
                }
            } catch {
                messages.append(error.localizedDescription)
            }
        }
        // Separate files arrive in file-name order, which means nothing, so put the genes in the usual
        // order: the current protocol's genes, then the saved gene list, then the rest. A workbook's
        // own sheet order is kept as it is.
        if urls.count > 1 { results.order(by: plan.geneNames + geneLibrary) }
        importMessage = messages.joined(separator: "\n")
        if options.notes.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }), !results.runTitle.isEmpty {
            options.notes[0] = results.runTitle
        }
        guard foundAny else {
            eppi(.jump, keptAny ? "Melt curve tucked in!" : "Hmm, no Cts in there…")
            return
        }
        playRun()
    }

    /// The qTOWER "runs" the plate, then the graphs grow in.
    // MARK: spotlight

    /// Picks a condition out in every graph and the table (again, or nil, to clear).
    func toggleSpotlight(_ key: String?) {
        let new = key == nil || key == spotlight ? nil : key
        guard new != spotlight else { return }
        tap(.alignment)
        spotlightPrev = spotlight
        spotlightAt = Date()
        spotlightToken += 1
        let tok = spotlightToken
        spotlightFading = true
        withAnimation(motion ? .easeOut(duration: 0.25) : nil) { spotlight = new }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            if self?.spotlightToken == tok { self?.spotlightFading = false }
        }
    }

    /// What a condition's row spotlights: itself, or in Compare the pair it belongs to.
    func spotlightKey(for condition: String) -> String {
        if options.compare, let cmp = results.comparison(options), let p = cmp.pairs.first(where: { $0.a == condition || $0.b == condition }) {
            return "p:" + p.label
        }
        return "c:" + condition
    }

    /// The conditions the spotlight currently covers.
    var spotlitConditions: Set<String>? {
        guard let s = spotlight else { return nil }
        if s.hasPrefix("c:") { return [String(s.dropFirst(2))] }
        if s.hasPrefix("p:"), let cmp = results.comparison(options), let p = cmp.pairs.first(where: { "p:" + $0.label == s }) {
            return Set([p.a, p.b].compactMap { $0 })
        }
        return []
    }

    private func morphCharts() {
        guard motion else { return }
        morphAt = Date()
        morphToken += 1
        let tok = morphToken
        morphing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            if self?.morphToken == tok { self?.morphing = false }
        }
    }

    // MARK: two-group comparison

    func setCompare(_ on: Bool) {
        tap(.levelChange)
        var o = options
        o.compare = on
        // nothing to read from the names: start with groups picked by hand
        if on && !o.pickGroups && results.groups.count < 2 { o.pickGroups = true }
        spotlight = nil
        spotlightPrev = nil
        options = o
        morphCharts()
    }

    /// A click on a condition: into group A, then group B, then out.
    func cycleGroup(_ c: String) {
        tap(.generic)
        var o = options
        let (a, b) = results.compareMembers(o)
        o.pickGroups = true
        o.membersA = a.filter { $0 != c }
        o.membersB = b.filter { $0 != c }
        if a.contains(c) { o.membersB.append(c) } else if !b.contains(c) { o.membersA.append(c) }
        options = o
    }

    /// Every condition of one series against every condition of another (A3_… vs C2_…, or
    /// SAG … vs SAG+22(S) …), paired by dose or level.
    func fillGroups(_ a: String, _ b: String) {
        tap(.levelChange)
        var o = options
        o.pickGroups = true
        o.membersA = results.members(ofStem: a)
        o.membersB = results.members(ofStem: b)
        o.nameA = ""; o.nameB = ""
        options = o
        revealCharts()
    }

    func setPairBy(_ m: PairMode) {
        options.pairBy = m
        revealCharts()
    }

    func clearGroups() {
        var o = options
        o.pickGroups = true
        o.membersA = []; o.membersB = []
        options = o
    }

    func openFromFinder(_ urls: [URL]) {
        // wait for the launch splash, so the qTOWER run plays where it can be seen
        if SplashController.shared.isShowing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.openFromFinder(urls) }
            return
        }
        importFiles(urls)
    }

    /// Clicking the qTOWER run ends it and shows the graphs at once.
    func skipImportShow() {
        guard importShow != nil else { return }
        withAnimation(.easeOut(duration: 0.2)) { importShow = nil }
        revealCharts()
    }

    private func playRun() {
        if mode != .results { if motion { withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { mode = .results } } else { mode = .results } }
        guard motion else { revealCharts(); return }
        // the qTOWER "runs" the plate, then the graphs grow in
        let genes = results.genes.enumerated().map { ShowGene(name: $0.element.name, hex: resultColor($0.element.name, $0.offset), ct: results.meanCt($0.element) ?? 25) }
        let show = ImportShow(genes: genes, conditions: results.conditions.count)
        importShow = show
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.25) { [weak self] in
            if self?.importShow?.id == show.id { self?.confettiAt = Date() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ImportShow.length) { [weak self] in
            if self?.importShow?.id == show.id { withAnimation { self?.importShow = nil } }
        }
        revealCharts(after: ImportShow.length - 0.25)
        eppi(.dance, "Fresh Cts! Let's plot!", after: ImportShow.length - 0.3)
    }

    // MARK: saved data (.qpcrdata)

    private struct DataFile: Codable {
        var app = "qPCR Planner"
        var version = 1
        var saved = Date()
        var results: ResultSet
        var options: ResultsOptions
        var colors: [String: String]
    }

    // MARK: saved protocols (.qpcrplan)

    func savePlan() {
        NSApp.keyWindow?.makeFirstResponder(nil)   // commit any field still being edited
        let panel = NSSavePanel()
        panel.nameFieldStringValue = plan.folderName + ".qpcrplan"
        panel.allowedContentTypes = [planFileType]
        panel.canCreateDirectories = true
        sheet(panel) { [weak self] ok in
            guard ok, let self, let url = panel.url else { return }
            do {
                try encodePlanFile(self.plan, self.settings).write(to: url, options: .atomic)
                self.celebrate("Protocol saved: \(url.lastPathComponent)", "Protocol saved! Safe and sound.")
            } catch {
                self.showAlert("Could not save the protocol", error.localizedDescription)
            }
        }
    }

    func openPlan() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [planFileType]
        panel.allowsMultipleSelection = false
        panel.message = "Open a saved protocol (.qpcrplan)"
        sheet(panel) { [weak self] ok in
            guard ok, let self, let url = panel.url else { return }
            self.openPlanFile(url)
        }
    }

    /// Loads a saved protocol with the volume settings it was saved with, and shows the Plan page.
    func openPlanFile(_ url: URL) {
        do {
            let f = try decodePlanFile(Data(contentsOf: url))
            plan = f.plan
            settings = f.settings
            for g in plan.geneNames where !geneLibrary.contains(g) { geneLibrary.append(g) }
            if mode != .plan { switchMode(.plan) }
            showToast("Opened \(url.lastPathComponent)")
        } catch {
            showAlert("Could not open the protocol", "\(url.lastPathComponent) is not a saved qPCR Planner protocol (\(error.localizedDescription)).")
        }
    }

    func saveData() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        let panel = NSSavePanel()
        let base = resultsFileName.hasSuffix(".xlsx") ? String(resultsFileName.dropLast(5)) : resultsFileName
        panel.nameFieldStringValue = base.replacingOccurrences(of: "_graphs", with: "") + ".qpcrdata"
        panel.allowedContentTypes = [dataFileType]
        panel.canCreateDirectories = true
        sheet(panel) { [weak self] ok in
            guard ok, let self, let url = panel.url else { return }
            do {
                try self.writeData(to: url)
                self.celebrate("Data saved: \(url.lastPathComponent)", "Data saved! Safe and sound.")
            } catch {
                self.showAlert("Could not save the data", error.localizedDescription)
            }
        }
    }

    /// The imported results, graph options and the colours of the genes in them, as JSON.
    func writeData(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let colorsUsed = geneColorMap.filter { k, _ in results.genes.contains { $0.name.uppercased() == k } }
        try enc.encode(DataFile(results: results, options: options, colors: colorsUsed)).write(to: url, options: .atomic)
    }

    func openData(_ url: URL) {
        do {
            let file = try JSONDecoder().decode(DataFile.self, from: Data(contentsOf: url))
            results = file.results
            options = file.options
            for (k, v) in file.colors { geneColorMap[k] = v }
            importMessage = "\(url.lastPathComponent): \(results.genes.count) gene\(results.genes.count == 1 ? "" : "s") from saved data."
            if mode != .results { if motion { withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { mode = .results } } else { mode = .results } }
            if results.genes.isEmpty { return }
            playRun()
        } catch {
            showAlert("Could not open the data file", "\(url.lastPathComponent) is not a qPCR Planner data file (\(error.localizedDescription)).")
        }
    }

    func clearResults() {
        spotlight = nil
        results = ResultSet()
        importMessage = ""
        eppi(.jump, "Squeaky clean!")
    }

    var resultsFileName: String {
        if let c = cleanCustomName(options.customTitle) { return c + ".xlsx" }
        let t = results.runTitle.trimmingCharacters(in: .whitespaces)
        let base = t.isEmpty ? "qPCR" : t.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return base + "_graphs.xlsx"
    }

    var exportFileName: String { mode == .plan ? plan.protocolFileName : resultsFileName }

    // MARK: export

    func export() {
        NSApp.keyWindow?.makeFirstResponder(nil)   // commit any field still being edited
        if mode == .results && results.genes.isEmpty {
            showAlert("Nothing to export yet", "Open a qTOWER result file first.")
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        if mode == .plan {
            // a folder with the protocol and a melt-curve sheet, or either file on its own
            let chooser = ExportChooser(panel: panel, plan: plan, kind: protocolExportKind)
            sheet(panel) { [weak self] ok in
                guard let self else { return }
                if self.persist { self.protocolExportKind = chooser.kind }
                guard ok, let url = panel.url else { return }
                switch chooser.kind {
                case .folder: self.writeFolder(to: url)
                case .protocolOnly: self.write(to: url)
                case .meltOnly: self.writeMelt(to: url)
                }
            }
            return
        }
        panel.nameFieldStringValue = exportFileName
        if let t = UTType(filenameExtension: "xlsx") { panel.allowedContentTypes = [t] }
        sheet(panel) { [weak self] ok in
            guard ok, let url = panel.url else { return }
            self?.write(to: url)
        }
    }

    /// What the protocol export saved last time (a folder, or one of its files).
    var protocolExportKind: ProtocolExportKind {
        get { ProtocolExportKind(rawValue: UserDefaults.standard.string(forKey: "protocolExportKind") ?? "") ?? .folder }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "protocolExportKind") }
    }

    /// The melt-curve sheet on its own.
    private func writeMelt(to url: URL) {
        do {
            try buildMeltWorkbook(plan).write(to: url, options: .atomic)
            showReceipt(url, title: "Melt sheet exported")
        } catch {
            showAlert("Could not save the melt sheet", error.localizedDescription)
        }
    }

    /// The protocol export: a folder with the protocol workbook and the prepared melt-curve sheet.
    /// A melt sheet already in the folder is kept, since it may hold pasted screenshots.
    private func writeFolder(to folder: URL) {
        do {
            let (protocolURL, keptMelt) = try writeProtocolFolder(plan, settings, colors: colors, to: folder)
            for g in plan.geneNames where !geneLibrary.contains(g) { geneLibrary.append(g) }
            // Open in Excel opens the protocol; Show in Finder shows it in its folder
            showReceipt(protocolURL, title: "Protocol folder exported",
                        detail: "\(folder.lastPathComponent)/\n  \(plan.protocolFileName)\n  \(plan.meltFileName)\(keptMelt ? "  (already there, kept)" : "")")
        } catch {
            showAlert("Could not save the protocol folder", error.localizedDescription)
        }
    }

    private func write(to url: URL) {
        do {
            let data = mode == .plan ? buildProtocolWorkbook(plan, settings, colors: colors) : buildResultsWorkbook(results, options, colors: resultColors)
            try data.write(to: url, options: .atomic)
            if mode == .plan {
                for g in plan.geneNames where !geneLibrary.contains(g) { geneLibrary.append(g) }
            }
            showReceipt(url)      // with Open in Excel and Show in Finder on it
        } catch {
            showAlert("Could not save the Excel file", error.localizedDescription)
        }
    }
}

private var launchObserver: NSObjectProtocol?

/// The splash as it looks `t` seconds in (development check).
func splashSnapshot(_ path: String, at t: Double) {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let about = CommandLine.arguments.contains("--about")
    let view = SplashView(about: about, motion: true, start: Date().addingTimeInterval(1 - t)) {}
    let host = NSHostingView(rootView: view)
    let win = NSWindow(contentRect: NSRect(origin: .zero, size: SplashView.size), styleMask: [.borderless], backing: .buffered, defer: false)
    win.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

// MARK: - Offscreen snapshot of the window (development check)

func snapshot(_ path: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let a = CommandLine.arguments
    var plan = examplePlan()
    applyLayoutFlags(&plan)
    let store = Store(inMemory: plan)
    store.importShowInWindow = false
    func at(_ flag: String) -> Double? { a.firstIndex(of: flag).flatMap { a.count > $0 + 1 ? Double(a[$0 + 1]) : nil } }
    if a.contains("--colors") { store.geneColorMap = ["LMX1A": "D4578C", "GAPDH": "7F7F7F"] }
    if a.contains("--custom-title") { store.plan.customTitle = "My bench plate" }
    if let i = a.firstIndex(of: "--input"), a.count > i + 1 {
        store.mode = .results
        store.importFiles([URL(fileURLWithPath: a[i + 1])])
        store.options.xTitle = "PG-008"
        store.importShow = nil
        store.chartsAnimating = false
        store.chartRevealAt = .distantPast
        store.eppiEvent = nil
    }
    if a.contains("--compare") { store.options.compare = true }
    if a.contains("--results-mode") { store.mode = .results }
    if let i = a.firstIndex(of: "--groups"), a.count > i + 2 {
        store.options.pickGroups = true
        store.options.membersA = a[i + 1].split(separator: ",").map(String.init)
        store.options.membersB = a[i + 2].split(separator: ",").map(String.init)
    }
    if let i = a.firstIndex(of: "--spotlight"), a.count > i + 1 { store.spotlight = a[i + 1] }
    if let i = a.firstIndex(of: "--summary-view"), a.count > i + 1, let v = SummaryView(rawValue: a[i + 1]) { store.options.summaryView = v }
    if let t = at("--morph") { store.morphAt = Date().addingTimeInterval(1 - t); store.morphing = true }
    if let i = a.firstIndex(of: "--hover"), a.count > i + 2, let x = Double(a[i + 1]), let y = Double(a[i + 2]) { debugHoverPoint = CGPoint(x: x, y: y) }
    store.platesAnimating = false
    store.plateRevealAt = .distantPast
    // freeze-frames of the animations, "seconds into the animation" after the 1 s render delay
    if let t = at("--show") {
        let genes = store.results.genes.enumerated().map { ShowGene(name: $0.element.name, hex: store.resultColor($0.element.name, $0.offset), ct: store.results.meanCt($0.element) ?? 25) }
        store.importShow = ImportShow(date: Date().addingTimeInterval(1 - t), genes: genes, conditions: store.results.conditions.count)
    }
    if let t = at("--charts-at") { store.chartRevealAt = Date().addingTimeInterval(1 - t); store.chartsAnimating = true }
    if let t = at("--plates-at") { store.plateRevealAt = Date().addingTimeInterval(1 - t); store.platesAnimating = true }
    if let t = at("--confetti") { store.confettiAt = Date().addingTimeInterval(1 - t) }
    if let t = at("--eppi") { store.eppiEvent = EppiEvent(mood: .cheer, text: "Graphs exported! SCIENCE!", date: Date().addingTimeInterval(1 - t)) }
    if a.contains("--receipt") {
        store.showReceipt(URL(fileURLWithPath: "/Users/me/Documents/" + (store.mode == .plan ? store.plan.protocolFileName : store.resultsFileName)))
        store.eppiEvent = nil
        store.confettiAt = .distantPast
    }
    if a.contains("--toast") { store.toast = Toast(text: "Protocol exported: 20260917_365_WNT_Esc_02_protocol.xlsx") }
    var size = NSSize(width: 1360, height: 900)
    if let i = a.firstIndex(of: "--size"), a.count > i + 2, let w = Double(a[i + 1]), let h = Double(a[i + 2]) { size = NSSize(width: w, height: h) }
    let root: AnyView = a.contains("--ipad-sheet") ? AnyView(IPadLinkView().environmentObject(store)) : AnyView(ContentView().environmentObject(store).frame(width: size.width, height: size.height))
    if a.contains("--ipad-sheet") { size = NSSize(width: 620, height: 470) }
    let host = NSHostingView(rootView: root)
    let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
    win.appearance = NSAppearance(named: a.contains("--dark") ? .darkAqua : .aqua)
    win.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}


// MARK: - Protocol export: a folder or a single file

enum ProtocolExportKind: String, CaseIterable {
    case folder, protocolOnly, meltOnly
    var title: String {
        switch self {
        case .folder: return "Folder with protocol and melt sheet"
        case .protocolOnly: return "Protocol only"
        case .meltOnly: return "Melt sheet only"
        }
    }
}

/// The "Export:" menu at the bottom of the save window. Picking an item renames the file to match
/// and switches between saving a folder and saving an .xlsx.
final class ExportChooser: NSObject {
    private weak var panel: NSSavePanel?
    private let plan: ProtocolPlan
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private(set) var kind: ProtocolExportKind

    init(panel: NSSavePanel, plan: ProtocolPlan, kind: ProtocolExportKind) {
        self.panel = panel
        self.plan = plan
        self.kind = kind
        super.init()
        popup.addItems(withTitles: ProtocolExportKind.allCases.map { $0.title })
        popup.selectItem(at: ProtocolExportKind.allCases.firstIndex(of: kind) ?? 0)
        popup.target = self
        popup.action = #selector(changed)
        let label = NSTextField(labelWithString: "Export:")
        let row = NSStackView(views: [label, popup])
        row.orientation = .horizontal
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        row.frame.size = row.fittingSize
        panel.accessoryView = row
        panel.isExtensionHidden = false
        objc_setAssociatedObject(panel, &ExportChooser.key, self, .OBJC_ASSOCIATION_RETAIN)   // lives as long as the panel
        apply()
    }

    private static var key = 0

    @objc private func changed() {
        kind = ProtocolExportKind.allCases[max(0, popup.indexOfSelectedItem)]
        apply()
    }

    private func apply() {
        guard let panel else { return }
        let xlsx = UTType(filenameExtension: "xlsx").map { [$0] } ?? []
        switch kind {
        case .folder:
            panel.allowedContentTypes = []
            panel.nameFieldLabel = "Folder:"
            panel.nameFieldStringValue = plan.folderName
            panel.message = "Saves a folder with \(plan.protocolFileName) and \(plan.meltFileName) inside."
        case .protocolOnly:
            panel.allowedContentTypes = xlsx
            panel.nameFieldLabel = "Save As:"
            panel.nameFieldStringValue = plan.protocolFileName
            panel.message = "Saves the protocol workbook on its own."
        case .meltOnly:
            panel.allowedContentTypes = xlsx
            panel.nameFieldLabel = "Save As:"
            panel.nameFieldStringValue = plan.meltFileName
            panel.message = "Saves the melt-curve sheet on its own, ready for the screenshots."
        }
    }
}
