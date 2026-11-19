import Foundation

// MARK: - Protocol workbook (same rows and columns as the lab's hand-made protocol sheet)

/// The colours the lab gives each sample's curve on the melt-curve sheet, in order.
let meltSampleColors = ["0E8CBE", "3BAE28", "002F8E", "C00000", "E3A21A", "7B3FA0", "17A2A2", "E0457B", "6B6B6B", "8C5A2B"]

/// An empty melt-curve sheet laid out like the lab's: the run at the top, a colour key for the samples,
/// and a 10-row block per primer (reference gene last, once per plate) to paste each melt-curve screenshot into.
func buildMeltWorkbook(_ p: ProtocolPlan) -> Data {
    let s = Sheet(name: "Melt")
    s.selected = true
    s.cols = [(1, 1, 10.8), (18, 18, 14)]
    let base = CellStyle()
    var bold = base; bold.bold = true

    s.set(1, 1, .num(Double(p.dateNumber)), base)
    let d = p.description.trimmingCharacters(in: .whitespaces)
    let t = p.title.trimmingCharacters(in: .whitespaces)
    if !(d.isEmpty && t.isEmpty) { s.set(1, 3, .str(d.isEmpty ? t : d), base) }
    let cal = p.calibratorName
    if !cal.isEmpty { s.set(1, 9, .str("Calibration: \(cal)"), bold) }

    // colour key beside the first block
    for (i, name) in p.sampleNames.enumerated() {
        var swatch = base.box(.thin); swatch.fill = meltSampleColors[i % meltSampleColors.count]
        s.set(4 + i, 17, .blank, swatch)
        s.set(4 + i, 18, .str(name), base)
    }

    // one block per primer; the reference gene comes last, once for each plate it is run on
    let runs = max(1, p.plates.count)
    let refs = (1...runs).map { $0 == 1 ? p.reference : "\(p.reference) \($0)" }
    var row = 4
    for g in p.geneNames + refs {
        s.set(row, 1, .str(g), base)
        row += 10
    }
    return packageWorkbook([s])
}

func buildProtocolWorkbook(_ p: ProtocolPlan, _ st: ProtocolSettings, colors: GeneColors = GeneColors()) -> Data {
    let s = Sheet(name: "Protocol")
    s.selected = true
    s.cols = [(1, 1, 10.7), (7, 7, 10.8)]
    let base = CellStyle()
    var bold = base; bold.bold = true
    func T(_ r: Int, _ c: Int, _ text: String, _ style: CellStyle? = nil) { s.set(r, c, .str(text), style ?? base) }
    func N(_ r: Int, _ c: Int, _ v: Double) { s.set(r, c, .num(v), base) }

    let genes = p.geneNames, samples = p.sampleNames
    let ref = p.reference

    T(1, 1, p.sheetHeading, CellStyle(size: 14, bold: true))
    var vol = base; vol.numFmtCode = volumeFormat     // 1.1 µL, but 279 µL

    // Materials
    T(2, 1, "Materials", bold); T(2, 2, "ThermoFisher"); T(2, 6, "BioRad")
    T(3, 2, "Fast SYBR Green Master Mix"); T(3, 6, "Hard-Shell 96well PCR plate (white)")
    N(4, 2, 4385612); T(4, 3, "1 box"); N(4, 4, 38300); T(4, 6, "HSP9655")
    T(6, 6, "Applied Biosystems"); T(7, 6, "MicroAmp Optical Adhesive Film"); N(8, 6, 4311971)
    T(10, 2, "Primer"); T(10, 3, "Life Technologies (Invitrogen)"); T(10, 6, "100μM"); T(10, 8, "50nmol/500uL")

    // Reaction per well
    T(12, 2, "component"); T(12, 5, "20uL/well")
    T(13, 2, "SYBR Green"); N(13, 5, 10)
    T(14, 2, "Fw primer"); N(14, 5, 0.04); T(14, 6, "primer concentration  >final 200nM")
    T(15, 2, "Rv primer"); N(15, 5, 0.04); T(15, 6, "primer concentration  >final 200nM")
    T(16, 2, "cDNA template"); N(16, 5, st.cdnaPerWell); T(16, 6, "cDNA <20ng"); T(16, 8, "about 800 ng/uL")
    T(17, 2, "H2O"); N(17, 5, 10)
    T(18, 2, "Total volume"); N(18, 5, 20)

    // Primers and samples
    T(21, 1, "Group1"); T(21, 2, "Primers"); T(21, 3, ref); T(21, 5, "Sample"); T(21, 6, p.description)
    for (i, g) in genes.enumerated() { T(22 + i, 3, g) }
    for (i, name) in samples.enumerated() {
        T(22 + i, 5, name)
        if !p.calibratorName.isEmpty && name == p.calibratorName { T(22 + i, 6, "calibrator") }
    }
    T(22, 8, "cDNA (x\(fmtNum(st.dilutionFactor))) → \(fmtNum(st.dilutedPerWell)) uL/well")
    T(23, 8, "n = \(p.n) wells per sample and primer")

    // Master mix
    // the template starts this block on row 29; a list of up to 8 samples ends on row 29 in another column
    let r0 = max(29, 21 + max(genes.count, samples.count))
    let wellsGene = genes.isEmpty ? p.wellsReference : p.wellsPerGene
    let showRef = !genes.isEmpty && p.wellsReference != p.wellsPerGene
    let hdr = r0 + 2, first = r0 + 3, tot = r0 + 7
    T(r0, 8, "number of well per primer")
    T(r0 + 1, 1, "Protocol", bold)
    T(hdr, 2, "mixture for each primer in 1.5mL tube"); T(hdr, 7, "μL")
    N(hdr, 8, Double(wellsGene)); T(hdr, 9, "well")
    if showRef { N(hdr, 11, Double(p.wellsReference)); T(hdr, 12, "well (\(ref), all plates)") }
    let labels = ["Fw primer", "Rv primer", "ddW", "Fast SYBR Green Master Mix"]
    let recipe = [st.fw, st.rv, st.water, st.sybr]
    let totalGene = p.mixTotal(wells: wellsGene, st), totalRef = p.mixTotal(wells: p.wellsReference, st)
    let sum = st.recipeTotal
    for i in 0..<4 {
        let r = first + i
        T(r, 6, labels[i]); N(r, 7, recipe[i])
        s.set(r, 8, .formula("G\(r)*$H$\(tot)/$G$\(tot)", sum > 0 ? recipe[i] * totalGene / sum : nil), vol); T(r, 9, "ul")
        if showRef {
            s.set(r, 11, .formula("G\(r)*$K$\(tot)/$G$\(tot)", sum > 0 ? recipe[i] * totalRef / sum : nil), vol); T(r, 12, "ul")
        }
    }
    T(tot, 6, "Total")
    s.set(tot, 7, .formula("SUM(G\(first):G\(first + 3))", sum), base)
    s.set(tot, 8, .formula("\(fmtNum(st.mixPerWell))*($H$\(hdr)+\(fmtNum(st.extraWells)))", totalGene), vol); T(tot, 9, "ul")
    if showRef {
        s.set(tot, 11, .formula("\(fmtNum(st.mixPerWell))*($K$\(hdr)+\(fmtNum(st.extraWells)))", totalRef), vol); T(tot, 12, "ul")
    }
    T(r0 + 9, 2, "mix and centrifuge")

    // cDNA dilution
    let cd = p.cdna(st)
    T(r0 + 11, 2, "dilute cDNA template"); T(r0 + 11, 5, "per 1well")
    T(r0 + 12, 3, "cDNA"); N(r0 + 12, 5, st.cdnaPerWell); T(r0 + 12, 6, "uL")
    T(r0 + 12, 8, "Stock cDNA"); N(r0 + 12, 9, cd.stock); T(r0 + 12, 10, "uL")
    T(r0 + 13, 3, "dilution factor ")
    s.set(r0 + 13, 4, .formula("E\(r0 + 14)/E\(r0 + 12)", st.dilutionFactor > 0 ? st.dilutionFactor : nil), base)
    T(r0 + 13, 8, "H2O")
    s.set(r0 + 13, 9, .formula("I\(r0 + 12)*(D\(r0 + 13)-1)", cd.water), vol); T(r0 + 13, 10, "uL")
    T(r0 + 14, 3, "diluted cDNA"); N(r0 + 14, 5, st.dilutedPerWell); T(r0 + 14, 6, "uL")
    T(r0 + 14, 8, "each sample needs \(fmtVol(cd.needed)) uL (\(p.wellsPerSample) wells)")

    // Plating
    let plates = p.plates
    let perPlate = p.n * (plates.first?.primers.count ?? 1)
    T(r0 + 16, 2, "Put the diluted cDNA in a 96 well plate (white plate)")
    T(r0 + 17, 5, "/well"); N(r0 + 17, 6, st.dilutedPerWell); T(r0 + 17, 7, "uL")
    T(r0 + 17, 8, "x\(perPlate)"); T(r0 + 17, 9, "(n=\(p.n)) per sample, per plate")
    T(r0 + 19, 2, "Put the Primer Mixture in a 96 well plate ")
    T(r0 + 20, 5, "/well"); N(r0 + 20, 6, st.mixPerWell); T(r0 + 20, 7, "uL"); T(r0 + 20, 8, "x\(p.wellsPerGene)")
    T(r0 + 20, 9, "per primer")
    T(r0 + 22, 2, "seal and centrifuge")

    // PCR
    T(r0 + 24, 2, "for PCR"); T(r0 + 25, 2, "　analytik jena qTOWER")
    // "PCR" is short so the temperature column beside it does not cut it off
    T(r0 + 26, 3, "PCR"); T(r0 + 26, 4, "℃"); T(r0 + 26, 5, "Time"); T(r0 + 26, 6, "cycle")
    N(r0 + 27, 4, 95); T(r0 + 27, 5, "20 sec"); T(r0 + 27, 6, "Hold")
    T(r0 + 28, 3, "Denature"); N(r0 + 28, 4, 95); T(r0 + 28, 5, "3 sec")
    s.set(r0 + 28, 6, .num(40), CellStyle(h: "center"))
    s.set(r0 + 29, 6, .blank, CellStyle(h: "center"))
    s.merges.append("F\(r0 + 28):F\(r0 + 29)")
    T(r0 + 29, 3, "Anneal"); N(r0 + 29, 4, 60); T(r0 + 29, 5, "30 sec")
    T(r0 + 31, 2, "　analyse (ΔΔCt)"); T(r0 + 31, 4, "Reference gene: \(ref)")
    T(r0 + 32, 4, "Calibrator: \(p.calibratorName)")

    // Arrangement: one map per plate. Columns B..M are plate columns 1..12.
    T(r0 + 34, 1, "Arrangement", bold)
    let layout = p.activeLayout
    if layout != .rows {
        T(r0 + 34, 3, "\(layout.title). \(layout.detail(p.n))")
        s.cols.append((14, 14, 16))
    }
    for (k, plate) in plates.enumerated() {
        let numbers = r0 + 36 + k * 10
        let head = numbers - 1
        T(head, 1, "Plate \(plate.number)", bold)
        if layout != .rows {
            arrangement(s, plate, head: head, colors: colors, calibrator: p.calibratorName)
            continue
        }
        for (b, primer) in plate.primers.enumerated() {
            let c0 = 2 + b * p.n, c1 = c0 + p.n - 1
            guard c1 <= 13 else { break }
            let hs = CellStyle(bold: true, fill: colors.pale(primer, plate.primerIndex[b]), h: "center").box()
            s.set(head, c0, .str(primer), hs)
            if c1 > c0 {
                for c in (c0 + 1)...c1 { s.set(head, c, .blank, hs) }
                s.merges.append("\(ref_(head, c0)):\(ref_(head, c1))")
            }
        }
        for c in 1...12 { s.set(numbers, 1 + c, .num(Double(c)), CellStyle(h: "center")) }
        for i in 0..<8 {
            let r = numbers + 1 + i
            T(r, 1, rowLetters[i])
            for c in 1...12 {
                let block = (c - 1) / p.n
                var cs = CellStyle(size: 10).box()
                let used = block < plate.primers.count && i < plate.samples.count
                if used { cs.fill = colors.pale(plate.primers[block], plate.primerIndex[block]) }
                let firstOfBlock = (c - 1) % p.n == 0
                s.set(r, 1 + c, used && firstOfBlock ? .str(plate.samples[i]) : .blank, cs)
            }
        }
    }
    return packageWorkbook([s])
}

private func ref_(_ row: Int, _ col: Int) -> String { colName(col) + String(row) }

/// A plate map for the layouts other than the lab's usual one: wells coloured by primer, labels over the
/// columns (upright when a label covers one column) and in column N beside the rows.
private func arrangement(_ s: Sheet, _ plate: PlateLayout, head: Int, colors: GeneColors, calibrator: String) {
    let numbers = head + 1
    let (top, side) = plate.bands(colors: colors, calibrator: calibrator)
    func label(_ b: PlateBand) -> String { b.isRef ? "\(b.text) (ref)" : (b.isCal ? "\(b.text) (cal)" : b.text) }
    func style(_ b: PlateBand) -> CellStyle {
        var st = CellStyle(size: 10, bold: true, h: "center").box()
        if let i = b.primer { st.fill = colors.pale(plate.primers[i], plate.primerIndex[i]) } else { st.fill = "EEF2F7" }
        return st
    }
    let upright = top.filter { $0.span == 1 }
    if let longest = upright.map({ label($0).count }).max() {
        s.heights[head] = min(150, max(36, Double(longest) * 6.2 + 12))
    }
    for b in top where b.start + b.span <= 12 {
        let c0 = 2 + b.start, c1 = c0 + b.span - 1
        var st = style(b)
        if b.span == 1 { st.rotate = 90; st.v = "bottom" }
        s.set(head, c0, .str(label(b)), st)
        if c1 > c0 {
            for c in (c0 + 1)...c1 { s.set(head, c, .blank, st) }
            s.merges.append("\(ref_(head, c0)):\(ref_(head, c1))")
        }
    }
    for c in 1...12 { s.set(numbers, 1 + c, .num(Double(c)), CellStyle(h: "center")) }
    for i in 0..<8 {
        let r = numbers + 1 + i
        s.set(r, 1, .str(rowLetters[i]), CellStyle())
        for c in 1...12 {
            var cs = CellStyle(size: 10).box()
            if let w = plate.content(i, c - 1) { cs.fill = colors.pale(plate.primers[w.primer], plate.primerIndex[w.primer]) }
            s.set(r, 1 + c, .blank, cs)
        }
    }
    for b in side where b.start + b.span <= 8 {
        let r0 = numbers + 1 + b.start, r1 = r0 + b.span - 1
        var st = style(b)
        st.h = "left"
        st.wrap = b.span > 1
        s.set(r0, 14, .str(label(b)), st)
        if r1 > r0 {
            for r in (r0 + 1)...r1 { s.set(r, 14, .blank, st) }
            s.merges.append("N\(r0):N\(r1)")
        }
    }
}

// MARK: - Results workbook (summary table + one native chart per gene, as on the lab's Graph sheet)

private func sheetName(_ raw: String, taken: inout Set<String>) -> String {
    var n = String(raw.map { "[]:*?/\\'".contains($0) ? "_" : $0 }).trimmingCharacters(in: .whitespaces)
    if n.isEmpty { n = "Gene" }
    n = String(n.prefix(28))
    var out = n, k = 2
    while taken.contains(out.lowercased()) { out = "\(n) (\(k))"; k += 1 }
    taken.insert(out.lowercased())
    return out
}

func buildResultsWorkbook(_ rs: ResultSet, _ opt: ResultsOptions, colors: GeneColors = GeneColors()) -> Data {
    let name = "Graph"
    let g = Sheet(name: name)
    g.selected = true
    g.cols = [(1, 1, 14)]
    let base = CellStyle()
    var bold = base; bold.bold = true
    let flag = CellStyle(fill: flagFill, fontColor: flagLine)   // a result resting on too few wells

    var notes = opt.notes.map { $0.trimmingCharacters(in: .whitespaces) }
    if notes.allSatisfy({ $0.isEmpty }) { notes[0] = rs.runTitle }
    for (i, t) in notes.enumerated() where !t.isEmpty { g.set(1 + i, 1, .str(t), i == 0 ? bold : base) }

    let rows = rs.rows(opt)
    let genes = rs.genes
    let top = 7, last = top + max(rows.count, 1) - 1

    // Table 1: value and SD for every gene
    g.set(6, 1, .str("Conditions"), bold)
    for (i, gene) in genes.enumerated() {
        g.set(6, 2 + 2 * i, .str(gene.name), bold)
        g.set(6, 3 + 2 * i, .str(gene.name + "_SD"), bold)
    }
    for (k, cond) in rows.enumerated() {
        guard let cond = cond else { continue }
        g.set(top + k, 1, .str(rs.label(cond)), base)
        for (i, gene) in genes.enumerated() {
            if let v = rs.value(gene, cond, opt) {
                let st = v.low ? flag : base
                g.set(top + k, 2 + 2 * i, .num(v.value), st)
                g.set(top + k, 3 + 2 * i, .num(v.sd), st)
            }
        }
    }

    // Table 2: values only (what the charts plot)
    let head2 = last + 3
    let top2 = head2 + 1, last2 = top2 + max(rows.count, 1) - 1
    g.set(head2, 1, .str("Conditions"), bold)
    for (i, gene) in genes.enumerated() { g.set(head2, 2 + i, .str(gene.name), bold) }
    for (k, cond) in rows.enumerated() {
        guard let cond = cond else { continue }
        g.set(top2 + k, 1, .str(rs.label(cond)), base)
        for (i, gene) in genes.enumerated() {
            if let v = rs.value(gene, cond, opt), !v.low { g.set(top2 + k, 2 + i, .num(v.value), base) }
        }
    }

    // Table 3: the results that rest on too few wells (for example 1 of 3). They are plotted as a
    // separate red series, so the main table above holds only the well-supported values.
    var anyLow = false
    for gene in genes { for c in rows { if let c = c, rs.value(gene, c, opt)?.low == true { anyLow = true } } }
    let head3 = last2 + 4
    let top3 = head3 + 1, last3 = top3 + max(rows.count, 1) - 1
    if anyLow {
        g.set(last2 + 2, 1, .blank, flag)
        g.set(last2 + 2, 2, .str("Red = fewer than \(max(opt.minReplicates, 1)) wells gave a Ct for that condition (for example 1 of 3). Treat with caution."), CellStyle(fontColor: flagLine))
        g.set(head3, 1, .str("Conditions"), bold)
        for (i, gene) in genes.enumerated() { g.set(head3, 2 + i, .str(gene.name + " (<\(max(opt.minReplicates, 1)) wells)"), CellStyle(bold: true, fontColor: flagLine)) }
        for (k, cond) in rows.enumerated() {
            guard let cond = cond else { continue }
            g.set(top3 + k, 1, .str(rs.label(cond)), base)
            for (i, gene) in genes.enumerated() {
                if let v = rs.value(gene, cond, opt), v.low { g.set(top3 + k, 2 + i, .num(v.value), flag) }
            }
        }
    }

    // Charts, three across, to the right of the second table
    let chartCol = max(10, genes.count + 3)
    let cats = rows.map { $0.map { rs.label($0) } ?? "" }
    for (i, gene) in genes.enumerated() {
        let found = rows.map { c in c.flatMap { rs.value(gene, $0, opt) } }
        let sds = found.map { $0?.sd }
        let solid = found.map { v -> Double? in (v?.low ?? true) ? nil : v?.value }
        let low = found.map { v -> Double? in (v?.low ?? false) ? v?.value : nil }
        var series = [SeriesSpec(nameRef: absRef(name, head2, 2 + i), name: gene.name,
                                 valRef: absRange(name, top2, last2, 2 + i), values: solid,
                                 errRef: absRange(name, top, last, 3 + 2 * i), errors: sds,
                                 fill: colors.color(gene.name, i), inLegend: false)]
        if low.contains(where: { $0 != nil }) {
            // results resting on too few wells sit on the same spots, drawn red
            series.append(SeriesSpec(nameRef: absRef(name, head3, 2 + i), name: gene.name + " (<\(max(opt.minReplicates, 1)) wells)",
                                     valRef: absRange(name, top3, last3, 2 + i), values: low,
                                     errRef: absRange(name, top, last, 3 + 2 * i), errors: sds,
                                     fill: flagFill, line: flagLine, dashed: true, lineWidth: 19050))
        }
        var c = ChartSpec(title: gene.name, catRef: absRange(name, top2, last2, 1), categories: cats, series: series)
        c.overlap = series.count > 1 ? 100 : -10
        c.refLine = opt.refLine
        c.xTitle = opt.xTitle; c.yTitle = opt.yTitle
        c.fromCol = chartCol + (i % 3) * 7
        c.toCol = c.fromCol + 6
        c.fromRow = (head2 - 1) + (i / 3) * 19
        c.toRow = c.fromRow + 17
        g.charts.append(c)
    }

    var sheets = [g]
    var taken: Set<String> = [name.lowercased()]

    // Summary: the app's summary table, ready to read or paste: normalised expression ± SD for every
    // condition and gene, the wells behind each value, and the raw Ct values' mean
    let sum = Sheet(name: sheetName("Summary", taken: &taken))
    sum.cols = [(1, 1, 18), (2, 1 + max(genes.count, 1), 17)]
    let grey = "9AA3B2"
    sum.set(1, 1, .str("Summary: normalised expression (\(opt.yTitle.isEmpty ? "RQ" : opt.yTitle)) ± SD"), CellStyle(size: 14, bold: true))
    sum.set(2, 1, .str((notes.first { !$0.isEmpty } ?? rs.runTitle) + "  ·  Red: fewer than \(max(opt.minReplicates, 1)) wells gave a Ct (count in brackets). Grey: no Ct. The numbers behind the graphs are on the Graph sheet."),
            CellStyle(fontColor: "595959"))
    func tableHead(_ r: Int, _ title: String) {
        sum.set(r, 1, .str(title), CellStyle(bold: true, fontColor: "1E4A83"))
        sum.set(r + 1, 1, .str("Conditions"), CellStyle(bold: true, fill: "E8EEF6").box())
        for (i, gene) in genes.enumerated() {
            sum.set(r + 1, 2 + i, .str(gene.name), CellStyle(bold: true, fill: colors.pale(gene.name, i), h: "center").box())
        }
    }
    let conds = rows.compactMap { $0 }
    // table 1: value ± SD
    tableHead(4, "Normalised expression ± SD")
    for (k, cond) in conds.enumerated() {
        let r = 6 + k
        let zebra: String? = k % 2 == 1 ? "F5F8FC" : nil
        sum.set(r, 1, .str(rs.label(cond)), CellStyle(fill: zebra).box())
        for (i, gene) in genes.enumerated() {
            if let v = rs.value(gene, cond, opt) {
                let text = "\(fmtNum(v.value, 2)) ± \(fmtNum(v.sd, 2))" + (v.low ? "  (\(v.counted)/\(v.wells))" : "")
                sum.set(r, 2 + i, .str(text), v.low ? CellStyle(fill: flagFill, h: "right", fontColor: flagLine).box()
                                                    : CellStyle(fill: zebra, h: "right").box())
            } else if let s = gene.sample(cond) {
                sum.set(r, 2 + i, .str("n.d. (\(s.cts.count)/\(s.replicates) Ct)"), CellStyle(fill: zebra, h: "right", fontColor: grey).box())
            } else {
                sum.set(r, 2 + i, .str("–"), CellStyle(fill: zebra, h: "right", fontColor: grey).box())
            }
        }
    }
    // table 2: wells that gave a Ct, and their mean Ct
    let t2 = 6 + conds.count + 2
    tableHead(t2, "Wells with a Ct, and their mean Ct")
    for (k, cond) in conds.enumerated() {
        let r = t2 + 2 + k
        let zebra: String? = k % 2 == 1 ? "F5F8FC" : nil
        sum.set(r, 1, .str(rs.label(cond)), CellStyle(fill: zebra).box())
        for (i, gene) in genes.enumerated() {
            guard let s = gene.sample(cond) else { sum.set(r, 2 + i, .str("–"), CellStyle(fill: zebra, h: "right", fontColor: grey).box()); continue }
            let ct = s.cts.isEmpty ? "no Ct" : "Ct \(fmtNum(s.cts.reduce(0, +) / Double(s.cts.count), 2))"
            let low = !s.cts.isEmpty && s.cts.count < max(opt.minReplicates, 1)
            sum.set(r, 2 + i, .str("\(s.cts.count)/\(s.replicates) wells · \(ct)"),
                    low ? CellStyle(fill: flagFill, h: "right", fontColor: flagLine).box() : CellStyle(fill: zebra, h: "right", fontColor: s.cts.isEmpty ? grey : "000000").box())
        }
    }
    // table 3: qTOWER's own dCt, copied exactly (a number cell in General format shows it as the file does)
    var tr = t2 + 2 + conds.count + 2
    if rs.hasFileDCt {
        tableHead(tr, "ΔCt exactly as in the qTOWER files: dCt (Ref. gene − GOI), not recalculated or rounded")
        for (k, cond) in conds.enumerated() {
            let r = tr + 2 + k
            let zebra: String? = k % 2 == 1 ? "F5F8FC" : nil
            sum.set(r, 1, .str(rs.label(cond)), CellStyle(fill: zebra).box())
            for (i, gene) in genes.enumerated() {
                let vals = rs.fileDCt(gene, cond)
                if vals.count == 1 {
                    sum.set(r, 2 + i, .num(vals[0]), CellStyle(fill: zebra, h: "right").box())
                } else if !vals.isEmpty {
                    sum.set(r, 2 + i, .str(vals.map(exactNumber).joined(separator: " / ")), CellStyle(fill: zebra, h: "right").box())
                } else {
                    sum.set(r, 2 + i, .str(gene.sample(cond) == nil ? "–" : "n.d."), CellStyle(fill: zebra, h: "right", fontColor: grey).box())
                }
            }
        }
        tr += 2 + conds.count + 2
    }
    // tables 4–5: ΔΔCt and 2^−ΔΔCt, which qTOWER does not export, from each well's Ct, mean ± SD
    let calNames = Set(genes.compactMap { rs.calibrator($0, opt) })
    let calText = calNames.count == 1 ? calNames.first! : "per gene, as in qTOWER"
    for (view, title) in [(SummaryView.ddct, "ΔΔCt = (Ct gene − mean Ct reference) − the calibrator's mean of the same (calibrator: \(calText)), mean ± SD of the wells"),
                          (.fold, "2^−ΔΔCt, fold change against the calibrator, mean ± SD of the wells (as Prism plots it)")] {
        tableHead(tr, title)
        for (k, cond) in conds.enumerated() {
            let r = tr + 2 + k
            let zebra: String? = k % 2 == 1 ? "F5F8FC" : nil
            sum.set(r, 1, .str(rs.label(cond)), CellStyle(fill: zebra).box())
            for (i, gene) in genes.enumerated() {
                if let m = rs.delta(gene, cond, opt).flatMap({ meanSD($0.values(view)) }) {
                    let f = view == .fold && abs(m.mean) < 1 ? "%.3f" : "%.2f"
                    sum.set(r, 2 + i, .str(String(format: "\(f) ± \(f)", m.mean, m.sd) + (m.n < max(opt.minReplicates, 1) ? "  (n = \(m.n))" : "")),
                            CellStyle(fill: zebra, h: "right").box())
                } else {
                    sum.set(r, 2 + i, .str(gene.sample(cond) == nil ? "–" : "n.d."), CellStyle(fill: zebra, h: "right", fontColor: grey).box())
                }
            }
        }
        tr += 2 + conds.count + 2
    }
    sheets.append(sum)

    // Prism: blocks to paste straight into GraphPad Prism, numbers from each well
    let pr = Sheet(name: sheetName("Prism", taken: &taken))
    let n = rs.maxReplicates
    pr.cols = [(1, 1, 18), (2, 2 + max(genes.count * max(n, 3), 12), 10.5)]
    pr.set(1, 1, .str("GraphPad Prism: ready to paste"), CellStyle(size: 14, bold: true))
    pr.set(2, 1, .str("Each shaded block is one Prism data table. Make the table named above it in Prism, click its first title cell, then copy the block here (titles included) and paste. Calibrator: \(calText)."),
           CellStyle(fontColor: "595959"))
    let num = CellStyle(fill: "F5F8FC", h: "right", numFmtCode: "0.0000").box()
    let rowTitle = CellStyle(bold: true, fill: "EEF2F7").box()
    var pRow = 4
    /// One block: its heading, how to make the Prism table, then the cells (header rows bold).
    func block(_ title: String, _ how: String, _ rows: [[String]], headers: Int, geneSpan: Int?, exact: Bool = false) {
        pr.set(pRow, 1, .str(title), CellStyle(size: 12, bold: true, fontColor: "1E4A83"))
        pr.set(pRow + 1, 1, .str(how), CellStyle(fontColor: "595959"))
        for (k, row) in rows.enumerated() {
            let r = pRow + 2 + k
            for (c, text) in row.enumerated() {
                if k < headers {
                    var st = CellStyle(bold: true, h: c == 0 ? "left" : "center").box()
                    if let span = geneSpan, c > 0 {
                        let gi = (c - 1) / span
                        if gi < genes.count { st.fill = colors.pale(genes[gi].name, gi) }
                    } else if c > 0 { st.fill = "E8EEF6" }
                    pr.set(r, 1 + c, text.isEmpty ? .blank : .str(text), st)
                } else if c == 0 && geneSpan != nil {
                    pr.set(r, 1, .str(text), rowTitle)
                } else if let v = Double(text) {
                    // N is a count: a whole number
                    let isN = headers == 2 && rows.count > 1 && c < rows[1].count && rows[1][c] == "N"
                    pr.set(r, 1 + c, .num(v), isN ? CellStyle(fill: "F5F8FC", h: "right", numFmtCode: "0").box()
                                              : exact ? CellStyle(fill: "F5F8FC", h: "right").box() : num)
                } else {
                    pr.set(r, 1 + c, text.isEmpty ? .blank : .str(text), num)
                }
            }
        }
        pRow += 2 + rows.count + 2
    }
    let grouped = "Prism: Grouped table, \"Enter \(n) replicate values in side-by-side subcolumns\"."
    block("2^−ΔΔCt (fold change), every well", grouped, rs.prismGrouped(.fold, opt), headers: 1, geneSpan: n)
    block("2^−ΔΔCt (fold change), mean, SD and N", "Prism: Grouped table, \"Enter and plot error values already calculated elsewhere: Mean, SD, N\".",
          rs.prismMeanSD(.fold, opt), headers: 2, geneSpan: 3)
    if rs.hasFileDCt {
        block("ΔCt exactly as in the qTOWER files (dCt, Ref. gene − GOI)", "Prism: Grouped table, single values (one subcolumn). Copied from qTOWER, not recalculated or rounded.",
              rs.prismFileDCt(opt), headers: 1, geneSpan: 1, exact: true)
    }
    block("ΔΔCt, every well", grouped, rs.prismGrouped(.ddct, opt), headers: 1, geneSpan: n)
    block("Mean Ct of each gene and of its reference", "Prism: Grouped table, single values (one subcolumn).", rs.prismCt(opt), headers: 1, geneSpan: 2)
    for g in genes {
        block("2^−ΔΔCt · \(g.name), one column per condition", "Prism: Column table, \"Enter replicate values, stacked into columns\"; one graph for this gene.",
              rs.prismColumn(g, .fold, opt), headers: 1, geneSpan: nil)
    }
    sheets.append(pr)

    // Two-group comparison: one block per gene (level | group A ± SD | group B ± SD) and a clustered chart
    if opt.compare, let cmp = rs.comparison(opt) {
        let ga = cmp.nameA, gb = cmp.nameB
        let cname = sheetName("Compare \(ga) vs \(gb)", taken: &taken)
        let cs = Sheet(name: cname)
        cs.cols = [(1, 1, 16), (2, 5, 11)]
        let levels = cmp.pairs.map { $0.label }
        cs.set(1, 1, .str("Group comparison: \(ga) vs \(gb)"), CellStyle(size: 14, bold: true))
        let members = "\(ga): " + cmp.pairs.compactMap { $0.a }.joined(separator: ", ") + ".  \(gb): " + cmp.pairs.compactMap { $0.b }.joined(separator: ", ") + "."
        cs.set(2, 1, .str("Side by side. Red cells: fewer than \(max(opt.minReplicates, 1)) wells gave a Ct.  " + members), CellStyle(fontColor: "595959"))
        let block = max(levels.count + 4, 20)
        for (i, gene) in genes.enumerated() {
            let r0 = 4 + i * block
            let colorHex = colors.color(gene.name, i)
            cs.set(r0, 1, .str(gene.name), CellStyle(size: 13, bold: true, fontColor: shadeHex(colorHex, isDarkHex(colorHex) ? 0 : 0.35)))
            let hdr = r0 + 1
            for (k, t) in [cmp.mode == .dose ? "Dose" : (cmp.mode == .name ? "Level" : "Pair"), ga, ga + "_SD", gb, gb + "_SD"].enumerated() { cs.set(hdr, 1 + k, .str(t), bold) }
            var va: [Double?] = [], ea: [Double?] = [], vb: [Double?] = [], eb: [Double?] = [], fa: [Int] = [], fb: [Int] = []
            for (k, pair) in cmp.pairs.enumerated() {
                let r = hdr + 1 + k
                cs.set(r, 1, .str(pair.label), base)
                let a = pair.a.flatMap { rs.value(gene, $0, opt) }
                let b = pair.b.flatMap { rs.value(gene, $0, opt) }
                if let a = a { cs.set(r, 2, .num(a.value), a.low ? flag : base); cs.set(r, 3, .num(a.sd), a.low ? flag : base); if a.low { fa.append(k) } }
                if let b = b { cs.set(r, 4, .num(b.value), b.low ? flag : base); cs.set(r, 5, .num(b.sd), b.low ? flag : base); if b.low { fb.append(k) } }
                va.append(a?.value); ea.append(a?.sd); vb.append(b?.value); eb.append(b?.sd)
            }
            let first = hdr + 1, lastRow = hdr + max(levels.count, 1)
            var c = ChartSpec(title: gene.name, catRef: absRange(cname, first, lastRow, 1), categories: levels, series: [
                SeriesSpec(nameRef: absRef(cname, hdr, 2), name: ga, valRef: absRange(cname, first, lastRow, 2), values: va,
                           errRef: absRange(cname, first, lastRow, 3), errors: ea, fill: colorHex, flagged: fa),
                SeriesSpec(nameRef: absRef(cname, hdr, 4), name: gb, valRef: absRange(cname, first, lastRow, 4), values: vb,
                           errRef: absRange(cname, first, lastRow, 5), errors: eb, fill: tintHex(colorHex, 0.55), flagged: fb),
            ])
            c.gapWidth = 70; c.overlap = -8
            c.refLine = opt.refLine
            c.xTitle = opt.xTitle; c.yTitle = opt.yTitle
            c.fromCol = 6; c.toCol = 14
            c.fromRow = r0 - 1; c.toRow = r0 + block - 3
            cs.charts.append(c)
        }
        sheets.append(cs)
    }

    // The imported instrument tables, one sheet each
    var done: Set<String> = []
    for gene in genes where !gene.rows.isEmpty {
        let key = gene.source + "|" + String(gene.rows.count)
        guard !done.contains(key) else { continue }
        done.insert(key)
        let sh = Sheet(name: sheetName(gene.name, taken: &taken))
        sh.cols = [(1, 1, 10.8), (2, 2, 14)]
        for (r, row) in gene.rows.enumerated() {
            for (c, text) in row.enumerated() where !text.isEmpty {
                if let d = plainNumber(text) ?? Double(text).flatMap({ $0.isFinite && text.contains(".") ? $0 : nil }) {
                    sh.set(r + 1, c + 1, .num(d), base)
                } else {
                    sh.set(r + 1, c + 1, .str(text), base)
                }
            }
        }
        sheets.append(sh)
    }

    // Sheets kept as imported, such as the melt curve: each on its own tab, as it came
    for e in rs.extras {
        let sh = Sheet(name: sheetName(e.name, taken: &taken))
        let L = e.layout
        // the look it had: Excel's usual 11 pt type, its own colours and fonts per cell
        var plainStyle = base
        if L != nil { plainStyle.size = 11; plainStyle.v = "bottom" }
        var lookAt: [Int: [Int: CellStyle]] = [:]
        for c in L?.styled ?? [] where c.look < (L?.looks.count ?? 0) {
            let look = L!.looks[c.look]
            var st = plainStyle
            st.fill = look.fill
            if let f = look.font { st.fontColor = f }
            st.bold = look.bold
            st.italic = look.italic
            if let size = look.size { st.size = size }
            lookAt[c.row, default: [:]][c.col] = st
        }
        sh.cols = (L?.columns.isEmpty ?? true) ? [(1, 1, 12)] : L!.columns.map { ($0.min, $0.max, $0.width) }
        for h in L?.rowHeights ?? [] { sh.heights[h.row] = h.height }
        sh.merges = L?.merges ?? []
        if let z = L?.zoom { sh.zoom = z }
        sh.pictures = L?.pictures ?? []
        for (r, row) in e.rows.enumerated() {
            for (c, text) in row.enumerated() where !text.isEmpty {
                let st = lookAt[r + 1]?[c + 1] ?? plainStyle
                if let d = plainNumber(text) ?? Double(text).flatMap({ $0.isFinite && text.contains(".") ? $0 : nil }) {
                    sh.set(r + 1, c + 1, .num(d), st)
                } else {
                    sh.set(r + 1, c + 1, .str(text), st)
                }
            }
        }
        // coloured cells with nothing in them (a legend's swatches, say)
        for (r, cols) in lookAt {
            for (c, st) in cols {
                let has = r - 1 < e.rows.count && c - 1 < e.rows[r - 1].count && !e.rows[r - 1][c - 1].isEmpty
                if !has { sh.set(r, c, .blank, st) }
            }
        }
        sheets.append(sh)
    }
    return packageWorkbook(sheets)
}
