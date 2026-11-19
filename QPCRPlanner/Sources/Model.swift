import Foundation

// MARK: - Shared helpers

func fmtNum(_ d: Double, _ places: Int = 3) -> String {
    if d.isNaN || d.isInfinite { return "–" }
    if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
    var s = String(format: "%.\(places)f", d)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}

/// A value typed as a plain decimal number ("100", "0.5", "-2"); anything else stays text.
func plainNumber(_ text: String) -> Double? {
    let t = text.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty, t.count <= 24 else { return nil }
    var digits = Substring(t)
    if digits.hasPrefix("-") { digits = digits.dropFirst() }
    let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2, let whole = parts.first, !whole.isEmpty,
          parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
    if whole.count > 1 && whole.hasPrefix("0") { return nil }
    guard let d = Double(t), d.isFinite else { return nil }
    return d
}

/// Pipetting volumes: one decimal below 100 µL (1.1), whole microlitres from 100 µL up (279).
func fmtVol(_ d: Double) -> String {
    if d.isNaN || d.isInfinite { return "–" }
    if d >= 100 { return String(Int(d.rounded())) }
    let r = (d * 10).rounded() / 10
    if d > 0 && r == 0 { return "<0.1" }
    return fmtNum(r, 1)
}

/// Excel number format with the same rule: 0.0 below 100, whole numbers from 100 up.
let volumeFormat = "[<100]0.0;0"

let rowLetters = ["A", "B", "C", "D", "E", "F", "G", "H"]

/// Bar and plate-block colours, one per gene (Excel-friendly, distinct, readable with black outlines).
let genePalette = ["1E4A83", "4EA72E", "E97132", "FFC000", "7B5EA7", "C0392B", "17A2A2", "7F7F7F", "0E7C3A", "D4578C"]
/// Pale versions of the same colours for plate maps.
let genePalePalette = ["DCE6F4", "E2EFDA", "FCE4D6", "FFF2CC", "E4DFEC", "F8D7D4", "D2EFEF", "EDEDED", "D5ECDD", "F9DCE8"]
func geneColor(_ i: Int) -> String { genePalette[((i % genePalette.count) + genePalette.count) % genePalette.count] }
func genePale(_ i: Int) -> String { genePalePalette[((i % genePalePalette.count) + genePalePalette.count) % genePalePalette.count] }

private func rgb(_ hex: String) -> (Double, Double, Double) {
    let v = UInt32(hex, radix: 16) ?? 0x7F7F7F
    return (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
}

private func hex(_ r: Double, _ g: Double, _ b: Double) -> String {
    func c(_ x: Double) -> Int { Int(min(255, max(0, x.rounded()))) }
    return String(format: "%02X%02X%02X", c(r), c(g), c(b))
}

/// Mixes a colour with white: amount 0 = unchanged, 1 = white.
func tintHex(_ h: String, _ amount: Double) -> String {
    let (r, g, b) = rgb(h)
    return hex(r + (255 - r) * amount, g + (255 - g) * amount, b + (255 - b) * amount)
}

/// Mixes a colour with black: amount 0 = unchanged, 1 = black.
func shadeHex(_ h: String, _ amount: Double) -> String {
    let (r, g, b) = rgb(h)
    return hex(r * (1 - amount), g * (1 - amount), b * (1 - amount))
}

/// True when white text reads better than dark text on this colour.
func isDarkHex(_ h: String) -> Bool {
    let (r, g, b) = rgb(h)
    return 0.299 * r + 0.587 * g + 0.114 * b < 150
}

func validHex(_ h: String?) -> String? {
    guard let h = h?.uppercased(), h.count == 6, UInt32(h, radix: 16) != nil else { return nil }
    return h
}

/// Colours chosen for genes, by gene name (upper case). Shared by the primer list, the plate map and
/// the graphs, so a gene keeps the same colour everywhere.
struct GeneColors {
    var custom: [String: String] = [:]

    func custom(_ name: String) -> String? {
        validHex(custom[name.trimmingCharacters(in: .whitespaces).uppercased()])
    }
    /// The gene's colour: its custom one, otherwise the default for its position.
    func color(_ name: String, _ index: Int) -> String { custom(name) ?? geneColor(index) }
    /// The pale version used for plate maps.
    func pale(_ name: String, _ index: Int) -> String { custom(name).map { tintHex($0, 0.78) } ?? genePale(index) }
}

// MARK: - Protocol (before the run)

struct NamedItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
}

struct ProtocolSettings: Codable, Equatable {
    var mixPerWell: Double = 18      // primer mixture per well (µL)
    var extraWells: Double = 4       // excess, counted in wells
    var fw: Double = 1               // recipe of the primer mixture, as written on the lab's sheet
    var rv: Double = 1
    var water: Double = 200
    var sybr: Double = 250
    var cdnaPerWell: Double = 0.02   // undiluted cDNA per well (µL)
    var dilutedPerWell: Double = 2   // diluted cDNA pipetted per well (µL)

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mixPerWell = try c.decodeIfPresent(Double.self, forKey: .mixPerWell) ?? 18
        extraWells = try c.decodeIfPresent(Double.self, forKey: .extraWells) ?? 4
        fw = try c.decodeIfPresent(Double.self, forKey: .fw) ?? 1
        rv = try c.decodeIfPresent(Double.self, forKey: .rv) ?? 1
        water = try c.decodeIfPresent(Double.self, forKey: .water) ?? 200
        sybr = try c.decodeIfPresent(Double.self, forKey: .sybr) ?? 250
        cdnaPerWell = try c.decodeIfPresent(Double.self, forKey: .cdnaPerWell) ?? 0.02
        dilutedPerWell = try c.decodeIfPresent(Double.self, forKey: .dilutedPerWell) ?? 2
    }

    var recipeTotal: Double { fw + rv + water + sybr }
    var dilutionFactor: Double { cdnaPerWell > 0 ? dilutedPerWell / cdnaPerWell : 0 }
}

/// Where samples and primers go on a 96-well plate. Each sample–primer pair takes `n` neighbouring
/// wells (its replicates); the reference gene is always the first primer on every plate.
enum SampleLayout: String, Codable, CaseIterable, Identifiable {
    case rows           // samples down the rows A–H, primers in blocks of columns (the lab's usual)
    case columns        // samples across the columns 1–12, primers in blocks of rows
    case primerRows     // primers down the rows, samples in blocks of columns
    case primerColumns  // primers across the columns, samples in blocks of rows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rows: return "Samples in rows"
        case .columns: return "Samples in columns"
        case .primerRows: return "Primers in rows"
        case .primerColumns: return "Primers in columns"
        }
    }

    /// One line on where everything goes, for n replicates.
    func detail(_ n: Int) -> String {
        let cols = n == 1 ? "column" : "\(n) columns", rows = n == 1 ? "row" : "\(n) rows"
        switch self {
        case .rows: return "Each sample takes a row (A–H); each primer a block of \(cols)."
        case .columns: return "Each sample takes a column (1–12); each primer a block of \(rows)."
        case .primerRows: return "Each primer takes a row (A–H); each sample a block of \(cols)."
        case .primerColumns: return "Each primer takes a column (1–12); each sample a block of \(rows)."
        }
    }

    /// Samples and primers (reference included) that fit on one plate with n replicates.
    func capacity(_ n: Int) -> (samples: Int, primers: Int) {
        switch self {
        case .rows: return (8, 12 / n)
        case .columns: return (12, 8 / n)
        case .primerRows: return (12 / n, 8)
        case .primerColumns: return (8 / n, 12)
        }
    }

    /// A plate needs room for at least one sample and for the reference gene beside one other primer.
    func fits(_ n: Int) -> Bool { let c = capacity(n); return c.samples >= 1 && c.primers >= 2 }
}

struct PlateLayout: Equatable {
    var number: Int
    var samples: [String]        // in plate order
    var primers: [String]        // in plate order; the reference gene comes first
    var primerIndex: [Int]       // colour index of each primer (0 = reference gene)
    var layout: SampleLayout = .rows
    var n = 3

    /// Row (0–7) and column (0–11) of replicate k of sample s with primer b.
    func well(_ s: Int, _ b: Int, _ k: Int) -> (r: Int, c: Int) {
        switch layout {
        case .rows: return (s, b * n + k)
        case .columns: return (b * n + k, s)
        case .primerRows: return (b, s * n + k)
        case .primerColumns: return (s * n + k, b)
        }
    }

    /// What goes in the well at row r, column c, if anything.
    func content(_ r: Int, _ c: Int) -> (sample: Int, primer: Int, rep: Int)? {
        let s: Int, b: Int, k: Int, block: Int, span: Int
        switch layout {
        case .rows: s = r; b = c / n; k = c % n; block = b; span = 12
        case .columns: s = c; b = r / n; k = r % n; block = b; span = 8
        case .primerRows: b = r; s = c / n; k = c % n; block = s; span = 12
        case .primerColumns: b = c; s = r / n; k = r % n; block = s; span = 8
        }
        guard (block + 1) * n <= span, s < samples.count, b < primers.count else { return nil }
        return (s, b, k)
    }

    var wells: Int { samples.count * primers.count * n }
}

struct ProtocolPlan: Codable, Equatable {
    var title = ""
    var date = Date()
    var description = ""
    var referenceGene = "GAPDH"
    var genes: [NamedItem] = []
    var samples: [NamedItem] = []
    var replicates = 3
    var calibratorID: UUID? = nil
    /// Your own name for the file and the sheet heading; empty = automatic (date + run title).
    var customTitle = ""
    /// Where samples and primers go on the plate, and whether to pick the layout with the fewest plates.
    var layout = SampleLayout.rows
    var autoLayout = false

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        referenceGene = try c.decodeIfPresent(String.self, forKey: .referenceGene) ?? "GAPDH"
        genes = try c.decodeIfPresent([NamedItem].self, forKey: .genes) ?? []
        samples = try c.decodeIfPresent([NamedItem].self, forKey: .samples) ?? []
        replicates = try c.decodeIfPresent(Int.self, forKey: .replicates) ?? 3
        calibratorID = try c.decodeIfPresent(UUID.self, forKey: .calibratorID)
        customTitle = try c.decodeIfPresent(String.self, forKey: .customTitle) ?? ""
        layout = (try? c.decodeIfPresent(SampleLayout.self, forKey: .layout)) ?? .rows
        autoLayout = try c.decodeIfPresent(Bool.self, forKey: .autoLayout) ?? false
    }

    /// The lab's own run of 17 Sep 2026 (#365 WNT_Esc_02), used as the starting example.
    static var example: ProtocolPlan {
        var p = ProtocolPlan()
        p.title = "365_WNT_Esc_02"
        p.description = "#365: 0 - 100 pM"
        p.genes = ["LMX1A", "CORIN", "EN1", "FOXA2", "SFRP1", "PTCH1"].map { NamedItem(name: $0) }
        p.samples = ["A3_100pM", "A3_10pM", "A3_1pM", "A3_100fM", "A3_cont_0", "C2_100pM", "C2_10pM", "C2_1pM"].map { NamedItem(name: $0) }
        p.calibratorID = p.samples[4].id
        return p
    }

    // MARK: derived

    var n: Int { min(max(replicates, 1), 6) }
    var geneNames: [String] { genes.map { $0.name.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    var sampleNames: [String] { samples.map { $0.name.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    var reference: String {
        let r = referenceGene.trimmingCharacters(in: .whitespaces)
        return r.isEmpty ? "Reference" : r
    }
    var calibratorName: String {
        samples.first { $0.id == calibratorID }?.name.trimmingCharacters(in: .whitespaces) ?? ""
    }

    private func chunks<T>(_ a: [T], _ size: Int) -> [[T]] {
        guard !a.isEmpty else { return [[]] }
        return stride(from: 0, to: a.count, by: max(1, size)).map { Array(a[$0..<min($0 + size, a.count)]) }
    }

    /// Plates needed with a layout, and how often each sample's reference gene is run.
    func plateCount(_ l: SampleLayout) -> Int {
        let cap = l.capacity(n)
        guard l.fits(n) else { return .max }
        return chunks(sampleNames, cap.samples).count * chunks(geneNames, cap.primers - 1).count
    }

    /// The layout in use: the chosen one, or with "fewest plates" on, the one that needs the fewest plates
    /// (then the fewest reference-gene repeats, then the lab's usual order).
    var activeLayout: SampleLayout {
        if autoLayout {
            return SampleLayout.allCases.filter { $0.fits(n) }.min {
                (plateCount($0), referenceRuns(for: $0)) < (plateCount($1), referenceRuns(for: $1))
            } ?? .rows
        }
        return layout.fits(n) ? layout : .rows
    }

    var samplesPerPlate: Int { activeLayout.capacity(n).samples }
    /// Genes of interest that fit beside the reference gene on one plate.
    var genesPerPlate: Int { max(1, activeLayout.capacity(n).primers - 1) }

    /// Samples are split into groups that fit on a plate, genes likewise; every sample group meets every
    /// gene group on its own plate, with the reference gene first on each.
    func plates(for l: SampleLayout) -> [PlateLayout] {
        let cap = l.fits(n) ? l.capacity(n) : SampleLayout.rows.capacity(n)
        let geneList = geneNames
        var out: [PlateLayout] = []
        var number = 1
        for sampleChunk in chunks(sampleNames, cap.samples) {
            var offset = 0
            for geneChunk in chunks(geneList, max(1, cap.primers - 1)) {
                out.append(PlateLayout(number: number, samples: sampleChunk, primers: [reference] + geneChunk,
                                       primerIndex: [0] + geneChunk.indices.map { offset + $0 + 1 },
                                       layout: l.fits(n) ? l : .rows, n: n))
                offset += geneChunk.count
                number += 1
            }
        }
        return out
    }

    var plates: [PlateLayout] { plates(for: activeLayout) }

    /// Plates each sample appears on, i.e. how many times its reference gene is run.
    func referenceRuns(for l: SampleLayout) -> Int {
        let cap = l.fits(n) ? l.capacity(n) : SampleLayout.rows.capacity(n)
        return max(1, chunks(geneNames, max(1, cap.primers - 1)).count)
    }
    var referenceRuns: Int { referenceRuns(for: activeLayout) }

    /// Where sample i sits on its plate: a row letter, a column number, or a block of them.
    func sampleTag(_ i: Int) -> String {
        let s = i % max(1, samplesPerPlate)
        switch activeLayout {
        case .rows: return rowLetters[s % 8]
        case .columns: return "\(s + 1)"
        case .primerRows: return n == 1 ? "\(s + 1)" : "\(s * n + 1)–\(s * n + n)"
        case .primerColumns: return n == 1 ? rowLetters[s % 8] : "\(rowLetters[(s * n) % 8])–\(rowLetters[(s * n + n - 1) % 8])"
        }
    }

    var wellsPerGene: Int { sampleNames.count * n }
    var wellsReference: Int { sampleNames.count * n * referenceRuns }
    var wellsPerSample: Int { n * (geneNames.count + referenceRuns) }

    func mixTotal(wells: Int, _ st: ProtocolSettings) -> Double {
        wells == 0 ? 0 : st.mixPerWell * (Double(wells) + st.extraWells)
    }

    /// Volumes of Fw, Rv, water and master mix for a tube that serves `wells` wells.
    func mix(wells: Int, _ st: ProtocolSettings) -> (fw: Double, rv: Double, water: Double, sybr: Double, total: Double) {
        let total = mixTotal(wells: wells, st)
        let k = st.recipeTotal > 0 ? total / st.recipeTotal : 0
        return (st.fw * k, st.rv * k, st.water * k, st.sybr * k, total)
    }

    /// Diluted cDNA needed per sample, and the whole-µL amount of stock that covers it with 20% spare.
    func cdna(_ st: ProtocolSettings) -> (needed: Double, stock: Double, water: Double) {
        let needed = Double(wellsPerSample) * st.dilutedPerWell
        let f = st.dilutionFactor
        guard f > 1 else { return (needed, 0, 0) }
        let stock = max(1, (needed * 1.2 / f).rounded(.up))
        return (needed, stock, stock * (f - 1))
    }

    var dateNumber: Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    private func safeName(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    var runName: String {
        let t = title.trimmingCharacters(in: .whitespaces)
        return safeName(t.isEmpty ? String(dateNumber) : "\(dateNumber)_\(t)")
    }
    var customName: String? { cleanCustomName(customTitle) }
    var protocolFileName: String { customName.map { $0 + ".xlsx" } ?? runName + "_protocol.xlsx" }
    /// The folder a protocol export goes in, holding the protocol and its melt-curve sheet.
    var folderName: String { customName ?? runName }
    /// The melt-curve sheet: the run title without the date, as the lab names it.
    var meltFileName: String {
        if let c = customName { return c + "_melt.xlsx" }
        let t = title.trimmingCharacters(in: .whitespaces)
        return (t.isEmpty ? runName : safeName(t)) + "_melt.xlsx"
    }
    var sheetHeading: String { customName ?? runName + "  qPCR protocol" }
}

/// A typed file name, tidied: trimmed, no ".xlsx" on the end, no characters a file name cannot hold.
func cleanCustomName(_ raw: String) -> String? {
    var t = raw.trimmingCharacters(in: .whitespaces)
    if t.lowercased().hasSuffix(".xlsx") { t = String(t.dropLast(5)).trimmingCharacters(in: .whitespaces) }
    t = t.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    return t.isEmpty ? nil : String(t.prefix(120))
}

// MARK: - Results (after the run)

struct SampleResult: Codable, Equatable {
    var name: String
    var type = ""
    var replicates = 0          // wells of this gene for this sample
    var cts: [Double] = []      // wells that gave a Ct
    var refCts: [Double] = []
    var normExpr: Double? = nil
    var sd: Double? = nil
    /// qTOWER's own dCt column (Ref. gene − GOI), one entry per well of this gene that has one, exactly
    /// as the file holds it. Nil for files without that column.
    var dctFile: [Double]? = nil
}

struct GeneResult: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var reference = ""
    var source = ""             // sheet or file it came from
    var runTitle = ""
    var rows: [[String]] = []   // the imported table, kept to copy into the output workbook
    var samples: [SampleResult] = []
    var recalculated = false    // true when the file had no normalised values and they were computed here

    func sample(_ name: String) -> SampleResult? { samples.first { $0.name == name } }
}

struct ComparePair: Equatable {
    var label: String
    var a: String?      // condition from group A
    var b: String?      // condition from group B
}

/// How the two groups' bars are paired up.
enum PairMode: String, Codable, CaseIterable, Identifiable {
    case auto, dose, name, order
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Automatic"
        case .dose: return "Dose"
        case .name: return "Matching names"
        case .order: return "Click order"
        }
    }
}

struct GroupComparison: Equatable {
    var nameA: String
    var nameB: String
    var pairs: [ComparePair]
    var mode = PairMode.order   // what the pairs were matched on (dose, name or order; never auto)
}

/// A concentration read from a sample name: "100pM", "0.1 uM", "1µM", "10 ng/mL"; and "0", "cont",
/// "vehicle" or "DMSO" for none.
struct Dose: Equatable {
    var value: Double       // in M, or in g/mL
    var mass: Bool          // g/mL rather than molar
    var text: String        // as written, tidied (u → µ)
    var zero: Bool { value == 0 }

    private static let amount = try! NSRegularExpression(pattern: "(\\d+(?:\\.\\d+)?)\\s*([fpnuµμm]?)(m|g/ml)(?![a-z])", options: [.caseInsensitive])
    private static let none = try! NSRegularExpression(pattern: "(?<![a-z0-9])(control|cont|ctrl|vehicle|veh|dmso|untreated|mock|0)(?![a-z0-9.])", options: [.caseInsensitive])

    /// The last concentration in the name, and the name with it taken out (what is left names the series).
    static func read(_ name: String) -> (dose: Dose, stem: String)? {
        let ns = name as NSString
        let all = NSRange(location: 0, length: ns.length)
        var dose: Dose? = nil
        var cut: [NSRange] = []
        if let m = amount.matches(in: name, range: all).last {
            let number = Double(ns.substring(with: m.range(at: 1))) ?? 0
            let prefix = ns.substring(with: m.range(at: 2)).lowercased()
            let unit = ns.substring(with: m.range(at: 3)).lowercased()
            let factor: Double = ["f": 1e-15, "p": 1e-12, "n": 1e-9, "u": 1e-6, "µ": 1e-6, "μ": 1e-6, "m": 1e-3][prefix] ?? 1
            var text = ns.substring(with: m.range).replacingOccurrences(of: " ", with: "")
            if prefix == "u" { text = text.replacingOccurrences(of: "u", with: "µ").replacingOccurrences(of: "U", with: "µ") }
            dose = Dose(value: number * factor, mass: unit != "m", text: number == 0 ? "0" : text)
            cut.append(m.range)
        }
        let zeros = none.matches(in: name, range: all)
        if dose == nil, let z = zeros.first {
            let word = ns.substring(with: z.range)
            dose = Dose(value: 0, mass: false, text: word == "0" ? "0" : word)
        }
        guard let dose else { return nil }
        if dose.zero { cut += zeros.map { $0.range } }
        var stem = name
        for r in cut.sorted(by: { $0.location > $1.location }) {
            if let rr = Range(r, in: stem) { stem.replaceSubrange(rr, with: " ") }
        }
        let parts = stem.components(separatedBy: CharacterSet(charactersIn: " _-:/"))
        let tidy = parts.filter { !$0.isEmpty }.joined(separator: "_")
        return (dose, tidy)
    }

    func same(_ o: Dose) -> Bool {
        if zero || o.zero { return zero && o.zero }
        return mass == o.mass && abs(value - o.value) <= 1e-9 * max(value, o.value)
    }
}

struct ResultsOptions: Codable, Equatable {
    var xTitle = ""
    var yTitle = "RQ"
    var minReplicates = 2       // a condition with fewer wells giving a Ct is still plotted, but flagged red
    var groupGap = false        // blank row between groups (text before the first "_")
    var notes: [String] = ["", "", "", ""]
    var customTitle = ""        // file name; empty = run title + "_graphs"
    var refLine = true          // dashed line at RQ = 1 (the calibrator)
    var compare = false         // show the two-group comparison graphs
    var groupA = ""             // e.g. "A3"; empty = first group found
    var groupB = ""             // e.g. "C2"; empty = second group found
    /// Groups picked by hand, condition by condition, instead of read from the names.
    var pickGroups = false
    var membersA: [String] = []
    var membersB: [String] = []
    var nameA = ""              // what the groups are called; empty = automatic
    var nameB = ""
    var pairBy = PairMode.auto  // how the two groups' bars are paired
    var replicateLimit = 0.5    // a replicate further than this from its partners (in Ct) is flagged
    var summaryView = SummaryView.relative   // what the summary table shows
    var deltaCalibrator = ""    // the calibrator for ΔΔCt; empty = the one qTOWER used for each gene

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        xTitle = try c.decodeIfPresent(String.self, forKey: .xTitle) ?? ""
        yTitle = try c.decodeIfPresent(String.self, forKey: .yTitle) ?? "RQ"
        minReplicates = try c.decodeIfPresent(Int.self, forKey: .minReplicates) ?? 2
        groupGap = try c.decodeIfPresent(Bool.self, forKey: .groupGap) ?? false
        var n = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
        while n.count < 4 { n.append("") }
        notes = Array(n.prefix(4))
        customTitle = try c.decodeIfPresent(String.self, forKey: .customTitle) ?? ""
        refLine = try c.decodeIfPresent(Bool.self, forKey: .refLine) ?? true
        compare = try c.decodeIfPresent(Bool.self, forKey: .compare) ?? false
        groupA = try c.decodeIfPresent(String.self, forKey: .groupA) ?? ""
        groupB = try c.decodeIfPresent(String.self, forKey: .groupB) ?? ""
        pickGroups = try c.decodeIfPresent(Bool.self, forKey: .pickGroups) ?? false
        membersA = try c.decodeIfPresent([String].self, forKey: .membersA) ?? []
        membersB = try c.decodeIfPresent([String].self, forKey: .membersB) ?? []
        nameA = try c.decodeIfPresent(String.self, forKey: .nameA) ?? ""
        nameB = try c.decodeIfPresent(String.self, forKey: .nameB) ?? ""
        pairBy = (try? c.decodeIfPresent(PairMode.self, forKey: .pairBy)) ?? .auto
        replicateLimit = try c.decodeIfPresent(Double.self, forKey: .replicateLimit) ?? 0.5
        summaryView = (try? c.decodeIfPresent(SummaryView.self, forKey: .summaryView)) ?? .relative
        deltaCalibrator = try c.decodeIfPresent(String.self, forKey: .deltaCalibrator) ?? ""
    }
}

private func normalizedHeader(_ s: String) -> String {
    String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
}

private func mean(_ a: [Double]) -> Double? { a.isEmpty ? nil : a.reduce(0, +) / Double(a.count) }

private func sampleSD(_ a: [Double]) -> Double {
    guard a.count > 1, let m = mean(a) else { return 0 }
    return (a.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(a.count - 1)).squareRoot()
}

/// Finds the instrument's result table in a sheet ("Well | Sample name | … | Norm. Expression | …")
/// and turns it into one result per gene of interest.
func parseGenes(_ table: Table) -> [GeneResult] {
    guard let headerIndex = table.rows.firstIndex(where: { row in
        let n = row.map(normalizedHeader)
        return n.first == "well" && n.contains("samplename")
    }) else { return [] }
    let header = table.rows[headerIndex].map(normalizedHeader)
    func col(_ names: String...) -> Int? { names.compactMap { header.firstIndex(of: $0) }.first }
    guard let cSample = col("samplename"), let cGOI = col("goi", "geneofinterest") else { return [] }
    let cType = col("sampletype"), cRef = col("referencegene", "refgene")
    let cCt = col("ctgoi"), cCtRef = col("ctrefgene", "ctreferencegene")
    let cNorm = col("normexpression", "normalizedexpression"), cSD = col("stddevnormexpression", "stddevnormalizedexpression")
    // "dCt (Ref.Gen − GOI)"; the minus sign arrives as "?" in the qTOWER export
    let cDCt = header.firstIndex { $0.hasPrefix("dct") }

    var title = ""
    for row in table.rows.prefix(headerIndex) where row.count > 1 && normalizedHeader(row[0]) == "title" { title = row[1] }

    func cell(_ row: [String], _ i: Int?) -> String {
        guard let i = i, i < row.count else { return "" }
        return row[i].trimmingCharacters(in: .whitespaces)
    }

    var order: [String] = []                       // genes in order of appearance
    var bySample: [String: [String: SampleResult]] = [:]
    var sampleOrder: [String] = []
    var refCts: [String: [Double]] = [:]
    var types: [String: String] = [:]
    var reference = ""

    for row in table.rows.dropFirst(headerIndex + 1) {
        let sample = cell(row, cSample)
        guard !sample.isEmpty else { continue }
        let goi = cell(row, cGOI), ref = cell(row, cRef)
        guard !goi.isEmpty || !ref.isEmpty else { continue }
        if !sampleOrder.contains(sample) { sampleOrder.append(sample) }
        if types[sample] == nil { types[sample] = cell(row, cType) }
        if !ref.isEmpty {
            if reference.isEmpty { reference = ref }
            if let ct = Double(cell(row, cCtRef)), ct.isFinite { refCts[sample, default: []].append(ct) }
        }
        if !goi.isEmpty {
            if !order.contains(goi) { order.append(goi) }
            var r = bySample[goi]?[sample] ?? SampleResult(name: sample)
            r.replicates += 1
            if let ct = Double(cell(row, cCt)), ct.isFinite { r.cts.append(ct) }
            if r.normExpr == nil, let v = Double(cell(row, cNorm)), v.isFinite { r.normExpr = v }
            if r.sd == nil, let v = Double(cell(row, cSD)), v.isFinite { r.sd = v }
            if cDCt != nil {
                if r.dctFile == nil { r.dctFile = [] }
                if let v = Double(cell(row, cDCt)), v.isFinite { r.dctFile?.append(v) }
            }
            bySample[goi, default: [:]][sample] = r
        }
    }

    return order.map { gene in
        var g = GeneResult(name: gene, reference: reference, source: table.name, runTitle: title, rows: table.rows)
        g.samples = sampleOrder.compactMap { s in
            guard var r = bySample[gene]?[s] else { return nil }
            r.type = types[s] ?? ""
            r.refCts = refCts[s] ?? []
            return r
        }
        if !g.samples.contains(where: { $0.normExpr != nil }) { recalculate(&g) }
        return g
    }
}

/// ΔΔCt from the Ct values, for files that carry no normalised expression of their own.
/// Error bars use the usual propagation: RQ · ln2 · √(SD_GOI² + SD_ref²).
private func recalculate(_ g: inout GeneResult) {
    func dCt(_ s: SampleResult) -> Double? {
        guard let a = mean(s.cts), let b = mean(s.refCts) else { return nil }
        return a - b
    }
    let calibrator = g.samples.first { $0.type.lowercased() == "calibrator" && dCt($0) != nil } ?? g.samples.first { dCt($0) != nil }
    guard let cal = calibrator, let calD = dCt(cal) else { return }
    for i in g.samples.indices {
        guard let d = dCt(g.samples[i]) else { continue }
        let rq = pow(2, -(d - calD))
        let spread = (pow(sampleSD(g.samples[i].cts), 2) + pow(sampleSD(g.samples[i].refCts), 2)).squareRoot()
        g.samples[i].normExpr = rq
        g.samples[i].sd = rq * log(2) * spread
    }
    g.recalculated = true
}

/// A sheet kept exactly as imported from a file that holds no Ct table, such as the melt curve export.
/// It is written to the graphs workbook as its own tab.
struct ExtraSheet: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String        // tab name: "Melt curve", or the file's name
    var source: String      // the file (and sheet) it came from
    var rows: [[String]]
    var melt: Bool
    /// Its pictures, cell colours and fonts, column widths, row heights and merges (.xlsx files only).
    var layout: SheetLayout? = nil

    /// Recognises a melt curve by its file name or its contents (melt, Tm, dF/dT, a temperature column).
    static func looksLikeMelt(_ fileName: String, _ tables: [Table]) -> Bool {
        let name = fileName.lowercased()
        if ["melt", "融解", "dissociation", "tm."].contains(where: { name.contains($0) }) { return true }
        for t in tables {
            for row in t.rows.prefix(25) {
                for cell in row {
                    let c = cell.lowercased().trimmingCharacters(in: .whitespaces)
                    if c.isEmpty { continue }
                    if ["melt", "融解", "df/dt", "-d(", "derivative", "dissociation"].contains(where: { c.contains($0) }) { return true }
                    if c == "tm" || c.hasPrefix("tm ") || c.hasPrefix("tm[") || c.hasPrefix("tm (") { return true }
                }
            }
            if let header = t.rows.first(where: { !$0.allSatisfy { $0.isEmpty } })?.first?.lowercased(),
               ["temp", "温度", "°c", "℃"].contains(where: { header.contains($0) }) { return true }
        }
        return false
    }
}

struct ResultSet: Codable, Equatable {
    var genes: [GeneResult] = []
    /// Labels typed for conditions ("C2_100pM" shown as "100 pM"); a condition without one keeps its name.
    var labels: [String: String] = [:]
    /// Imported sheets without a Ct table (the melt curve), carried into the export as their own tabs.
    var extras: [ExtraSheet] = []

    /// Adds a kept sheet, replacing one from the same file and sheet.
    mutating func addExtra(_ e: ExtraSheet) {
        if let i = extras.firstIndex(where: { $0.source == e.source }) { extras[i] = e } else { extras.append(e) }
    }

    func label(_ condition: String) -> String {
        let l = labels[condition]?.trimmingCharacters(in: .whitespaces) ?? ""
        return l.isEmpty ? condition : l
    }

    /// Puts genes in a familiar order: first the given names in their order, then everything else as imported.
    mutating func order(by preferred: [String]) {
        let rank = Dictionary(preferred.enumerated().map { ($0.element.uppercased(), $0.offset) }, uniquingKeysWith: { a, _ in a })
        let indexed = genes.enumerated().map { ($0.offset, $0.element) }
        genes = indexed.sorted { a, b in
            let ra = rank[a.1.name.uppercased()], rb = rank[b.1.name.uppercased()]
            switch (ra, rb) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.0 < b.0
            }
        }.map { $0.1 }
    }

    /// Conditions in the order they first appear across the imported genes.
    var conditions: [String] {
        var out: [String] = []
        for g in genes { for s in g.samples where !out.contains(s.name) { out.append(s.name) } }
        return out
    }

    /// The value that goes on the graph. Anything with at least one Ct is shown; `low` marks a result
    /// that rests on fewer wells than the threshold (for example 1 of 3), so it can be flagged in red.
    func value(_ gene: GeneResult, _ condition: String, _ opt: ResultsOptions) -> (value: Double, sd: Double, low: Bool, counted: Int, wells: Int)? {
        guard let s = gene.sample(condition), let v = s.normExpr, s.cts.count >= 1 else { return nil }
        return (v, s.sd ?? 0, s.cts.count < max(opt.minReplicates, 1), s.cts.count, s.replicates)
    }

    /// Rows of the summary table; nil marks the blank row between groups when that option is on.
    func rows(_ opt: ResultsOptions) -> [String?] {
        let c = conditions
        guard opt.groupGap else { return c }
        var out: [String?] = []
        var last: String? = nil
        for name in c {
            let group = name.split(separator: "_").first.map(String.init) ?? name
            if let l = last, l != group { out.append(nil) }
            out.append(name)
            last = group
        }
        return out
    }

    mutating func add(_ new: [GeneResult]) {
        for g in new {
            if let i = genes.firstIndex(where: { $0.name == g.name }) { genes[i] = g } else { genes.append(g) }
        }
    }

    var runTitle: String { genes.first { !$0.runTitle.isEmpty }?.runTitle ?? "" }

    // MARK: two-group comparison
    //
    // A sample name like "A3_100pM" is read as group "A3", level "100pM". Two groups are compared
    // level by level: A3_100pM beside C2_100pM, A3_cont beside C2_cont, and so on.

    static func split(_ condition: String) -> (group: String, level: String)? {
        guard let r = condition.range(of: "_") else { return nil }
        let g = condition[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
        let l = condition[r.upperBound...].trimmingCharacters(in: .whitespaces)
        return g.isEmpty || l.isEmpty ? nil : (g, l)
    }

    /// Groups in the order they first appear.
    var groups: [String] {
        var out: [String] = []
        for c in conditions { if let g = Self.split(c)?.group, !out.contains(g) { out.append(g) } }
        return out
    }

    /// The two groups to compare: the chosen ones if they exist, otherwise the first two found.
    func comparePair(_ opt: ResultsOptions) -> (String, String)? {
        let g = groups
        guard g.count >= 2 else { return nil }
        let a = g.contains(opt.groupA) ? opt.groupA : g[0]
        let b = g.contains(opt.groupB) && opt.groupB != a ? opt.groupB : (g.first { $0 != a } ?? g[1])
        return (a, b)
    }

    /// Levels found in either group, in order of appearance (group A's first).
    func levels(_ a: String, _ b: String) -> [String] {
        var out: [String] = []
        for g in [a, b] {
            for c in conditions {
                if let s = Self.split(c), s.group == g, !out.contains(s.level) { out.append(s.level) }
            }
        }
        return out
    }

    func condition(_ group: String, _ level: String) -> String? {
        conditions.first { Self.split($0).map { $0.group == group && $0.level == level } ?? false }
    }

    /// The conditions in each group: picked by hand, or read from the names (all A3_… against all C2_…).
    func compareMembers(_ opt: ResultsOptions) -> (a: [String], b: [String]) {
        let conds = conditions
        if opt.pickGroups {
            // in the order they were picked, so the first of A sits beside the first of B
            var a: [String] = [], b: [String] = []
            for c in opt.membersA where conds.contains(c) && !a.contains(c) { a.append(c) }
            for c in opt.membersB where conds.contains(c) && !a.contains(c) && !b.contains(c) { b.append(c) }
            return (a, b)
        }
        guard let (ga, gb) = comparePair(opt) else { return ([], []) }
        return (conds.filter { Self.split($0)?.group == ga }, conds.filter { Self.split($0)?.group == gb })
    }

    /// Series that can be lined up against each other, for "From names": what is left of each name once
    /// its dose is taken out (SAG / SAG+22(S), A3 / C2), or else the text before the first "_".
    var compareStems: [String] {
        let conds = conditions
        let read = conds.compactMap { Dose.read($0) }
        if read.count == conds.count {
            var out: [String] = []
            for r in read where !out.contains(r.stem) && !r.stem.isEmpty { out.append(r.stem) }
            if out.count >= 2 { return out }
        }
        return groups
    }

    /// The conditions belonging to one of compareStems, in the order they appear.
    func members(ofStem stem: String) -> [String] {
        let conds = conditions
        let read = conds.compactMap { Dose.read($0) }
        if read.count == conds.count, read.contains(where: { $0.stem == stem }) {
            return zip(conds, read).filter { $0.1.stem == stem }.map { $0.0 }
        }
        return conds.filter { Self.split($0)?.group == stem }
    }

    /// The two groups, named, and their conditions paired up for side-by-side bars: by dose when every
    /// name carries one (0 → 1 µM, whatever way it is written), by level when the names line up
    /// (A3_100pM beside C2_100pM), otherwise in the order picked. Nil until both groups have something.
    func comparison(_ opt: ResultsOptions) -> GroupComparison? {
        let (a, b) = compareMembers(opt)
        guard !a.isEmpty, !b.isEmpty else { return nil }

        // names: typed, or the series each group shares (SAG / SAG+22(S), A3 / C2), or the single
        // condition's name, or Group A / Group B
        let ra = a.map { Dose.read($0) }, rb = b.map { Dose.read($0) }
        func shared(_ m: [String], _ r: [(dose: Dose, stem: String)?]) -> String? {
            let stems = Set(r.compactMap { $0?.stem })
            if r.allSatisfy({ $0 != nil }), stems.count == 1, let s = stems.first, !s.isEmpty { return s }
            let parts = m.compactMap { Self.split($0) }
            let set = Set(parts.map { $0.group })
            return parts.count == m.count && set.count == 1 ? set.first : nil
        }
        let pa = shared(a, ra), pb = shared(b, rb)
        let distinct = pa != nil && pb != nil && pa != pb
        func autoName(_ m: [String], _ p: String?, _ fallback: String) -> String {
            if distinct, let p { return p }
            return m.count == 1 ? label(m[0]) : fallback
        }
        var na = opt.nameA.trimmingCharacters(in: .whitespaces), nb = opt.nameB.trimmingCharacters(in: .whitespaces)
        if na.isEmpty { na = autoName(a, pa, "Group A") }
        if nb.isEmpty { nb = autoName(b, pb, "Group B") }
        if na == nb { na += " (A)"; nb += " (B)" }

        // by dose: every name has one, no dose twice within a group, one kind of unit
        func byDose() -> [ComparePair]? {
            let da = ra.compactMap { $0?.dose }, db = rb.compactMap { $0?.dose }
            guard da.count == a.count, db.count == b.count else { return nil }
            func unique(_ d: [Dose]) -> Bool { !d.enumerated().contains { i, x in d[..<i].contains { $0.same(x) } } }
            guard unique(da), unique(db), Set((da + db).filter { !$0.zero }.map { $0.mass }).count <= 1 else { return nil }
            var doses: [Dose] = []
            for d in da + db where !doses.contains(where: { $0.same(d) }) { doses.append(d) }
            // in the direction the samples were listed (0 → 1 µM, or 100 pM → control)
            let lead = da.count >= 2 ? da : db
            let falling = lead.count >= 2 && lead.first!.value > lead.last!.value
            doses.sort { falling ? $0.value > $1.value : $0.value < $1.value }
            return doses.map { d in
                let ia = da.firstIndex { $0.same(d) }, ib = db.firstIndex { $0.same(d) }
                let text = ia.map { da[$0].text } ?? ib.map { db[$0].text } ?? d.text
                return ComparePair(label: text, a: ia.map { a[$0] }, b: ib.map { b[$0] })
            }
        }
        func byName() -> [ComparePair]? {
            let la = a.compactMap { Self.split($0)?.level }, lb = b.compactMap { Self.split($0)?.level }
            guard la.count == a.count, lb.count == b.count, Set(la).count == la.count, Set(lb).count == lb.count, !Set(la).isDisjoint(with: lb) else { return nil }
            var levels = la
            for l in lb where !levels.contains(l) { levels.append(l) }
            return levels.map { l in ComparePair(label: l, a: a.first { Self.split($0)?.level == l }, b: b.first { Self.split($0)?.level == l }) }
        }
        func byOrder() -> [ComparePair] {
            (0..<max(a.count, b.count)).map { i in
                let ca = i < a.count ? a[i] : nil, cb = i < b.count ? b[i] : nil
                return ComparePair(label: [ca, cb].compactMap { $0 }.map { label($0) }.joined(separator: " vs "), a: ca, b: cb)
            }
        }
        switch opt.pairBy {
        case .order: return GroupComparison(nameA: na, nameB: nb, pairs: byOrder(), mode: .order)
        case .name: if let p = byName() { return GroupComparison(nameA: na, nameB: nb, pairs: p, mode: .name) }
        case .dose, .auto: break
        }
        if let p = byDose() { return GroupComparison(nameA: na, nameB: nb, pairs: p, mode: .dose) }
        if let p = byName() { return GroupComparison(nameA: na, nameB: nb, pairs: p, mode: .name) }
        return GroupComparison(nameA: na, nameB: nb, pairs: byOrder(), mode: .order)
    }

    /// Mean Ct of a gene's wells, used to place its curve in the qTOWER animation.
    func meanCt(_ gene: GeneResult) -> Double? {
        let all = gene.samples.flatMap { $0.cts }
        return all.isEmpty ? nil : all.reduce(0, +) / Double(all.count)
    }
}

extension ResultSet {
    /// Data saved before kept sheets existed still opens.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        genes = try c.decodeIfPresent([GeneResult].self, forKey: .genes) ?? []
        labels = try c.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        extras = try c.decodeIfPresent([ExtraSheet].self, forKey: .extras) ?? []
        // data saved before qTOWER's dCt column was read: read it again from the table kept with each gene
        for i in genes.indices where !genes[i].rows.isEmpty && genes[i].samples.allSatisfy({ $0.dctFile == nil }) {
            guard let again = parseGenes(Table(name: genes[i].source, rows: genes[i].rows)).first(where: { $0.name == genes[i].name }) else { continue }
            for j in genes[i].samples.indices { genes[i].samples[j].dctFile = again.sample(genes[i].samples[j].name)?.dctFile }
        }
    }
}

// MARK: - Replicate check and the plate as run
//
// Every qTOWER gene export lists the whole plate: each well with its sample, its target (the gene of
// interest or the reference gene) and its Ct. Put together, they give the plate as it was run, and each
// replicate can be held against its partners.

struct PlateWell: Equatable {
    var well: String            // "B5"
    var row: Int                // 0…7
    var col: Int                // 0…11
    var sample: String
    var target: String          // gene of interest, or the reference gene
    var isRef: Bool
    var ct: Double?             // nil: no Ct
    var flagged = false         // sits away from its partners
    var offBy: Double? = nil    // how far from the partners' median, in Ct
    var partners: [Double] = [] // the other replicates' Cts
}

struct PlateCheck: Equatable {
    var title: String           // the run
    var wells: [PlateWell]
    var flagged: [PlateWell] { wells.filter { $0.flagged } }
}

private func headerKey(_ s: String) -> String {
    String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
}

extension ResultSet {
    /// The plates as run, one per run title, with replicates more than `limit` Ct from their partners flagged.
    func plateChecks(limit: Double) -> [PlateCheck] {
        var plates: [String: [String: PlateWell]] = [:]
        var order: [String] = []
        for gene in genes {
            guard let h = gene.rows.firstIndex(where: { r in
                let keys = r.map(headerKey)
                return keys.contains("well") && keys.contains("samplename")
            }) else { continue }
            let keys = gene.rows[h].map(headerKey)
            func col(_ k: String) -> Int? { keys.firstIndex(of: k) }
            guard let cw = col("well"), let cs = col("samplename") else { continue }
            let cg = col("goi"), cr = col("referencegene"), cct = col("ctgoi"), cref = col("ctrefgene")
            let run = gene.runTitle.isEmpty ? "Plate" : gene.runTitle
            if plates[run] == nil { plates[run] = [:]; order.append(run) }
            for row in gene.rows[(h + 1)...] {
                func cell(_ i: Int?) -> String { i.flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces) : nil } ?? "" }
                let well = cell(cw).uppercased()
                guard let letter = well.first, let r = "ABCDEFGH".firstIndex(of: letter).map({ "ABCDEFGH".distance(from: "ABCDEFGH".startIndex, to: $0) }),
                      let c = Int(well.dropFirst()), (1...12).contains(c), plates[run]?[well] == nil else { continue }
                let sample = cell(cs)
                let goi = cell(cg), ref = cell(cr)
                if !goi.isEmpty {
                    plates[run]?[well] = PlateWell(well: well, row: r, col: c - 1, sample: sample, target: goi, isRef: false, ct: Double(cell(cct)))
                } else if !ref.isEmpty {
                    plates[run]?[well] = PlateWell(well: well, row: r, col: c - 1, sample: sample, target: ref, isRef: true, ct: Double(cell(cref)))
                }
            }
        }
        return order.map { run in
            var wells = Array(plates[run, default: [:]].values).sorted { ($0.row, $0.col) < ($1.row, $1.col) }
            // each sample's replicates of one target, held against each other
            let groups = Dictionary(grouping: wells.indices) { "\(wells[$0].sample)|\(wells[$0].target)" }
            for (_, idx) in groups {
                let withCt = idx.filter { wells[$0].ct != nil }
                guard withCt.count >= 2 else { continue }
                let all = withCt.compactMap { wells[$0].ct }.sorted()
                // three or more: each against the median of the set, so one stray well stands out alone;
                // two: against each other, and as there is no telling which is off, both are marked
                let median = all.count % 2 == 1 ? all[all.count / 2] : (all[all.count / 2 - 1] + all[all.count / 2]) / 2
                for i in withCt {
                    let ct = wells[i].ct!
                    let others = withCt.filter { $0 != i }.compactMap { wells[$0].ct }
                    let off = all.count == 2 ? ct - others[0] : ct - median
                    wells[i].partners = others
                    wells[i].offBy = off
                    if abs(off) > limit + 1e-9 { wells[i].flagged = true }
                }
            }
            return PlateCheck(title: run, wells: wells)
        }
    }

    /// Flagged replicates by sample and gene: a gene's own wells, and the reference wells it was normalised to.
    func replicateFlags(limit: Double) -> [String: [PlateWell]] {
        var out: [String: [PlateWell]] = [:]
        let flagged = plateChecks(limit: limit).flatMap { $0.flagged }
        for gene in genes {
            for w in flagged where w.target == gene.name || (w.isRef && w.target == gene.reference) {
                out["\(w.sample)|\(gene.name)", default: []].append(w)
            }
        }
        return out
    }
}


// MARK: - ΔCt, ΔΔCt and fold change, well by well
//
// From the Cts in the qTOWER exports: each well of the gene against the mean of the same sample's
// reference wells (ΔCt), then against the calibrator's mean ΔCt (ΔΔCt), then 2^−ΔΔCt. Kept per well, so
// GraphPad Prism can take the replicates and work out the mean and SD itself. From the means, 2^−ΔΔCt
// is qTOWER's own normalised expression (to the rounding of the Cts).

enum SummaryView: String, Codable, CaseIterable, Identifiable {
    case relative, ct, dct, ddct, fold
    var id: String { rawValue }
    var title: String {
        switch self {
        case .relative: return "Relative expression"
        case .ct: return "Ct"
        case .dct: return "ΔCt"
        case .ddct: return "ΔΔCt"
        case .fold: return "2^−ΔΔCt"
        }
    }
    /// What a number in this view is called in Prism and on the sheet.
    var quantity: String {
        switch self {
        case .relative: return "Normalised expression (qTOWER)"
        case .ct: return "Mean Ct"
        case .dct: return "ΔCt from qTOWER (Ref. gene − GOI)"
        case .ddct: return "ΔΔCt"
        case .fold: return "2^−ΔΔCt (fold change)"
        }
    }
}

struct Delta {
    var ct: Double?             // mean Ct of the gene's wells
    var refCt: Double?          // mean Ct of the same sample's reference wells
    var dct: [Double]           // per well: Ct − mean reference Ct
    var ddct: [Double]          // per well: ΔCt − the calibrator's mean ΔCt
    var fold: [Double]          // per well: 2^−ΔΔCt
    var calibrator: String?

    func values(_ v: SummaryView) -> [Double] {
        switch v {
        case .dct: return dct
        case .ddct: return ddct
        case .fold: return fold
        default: return []
        }
    }
}

/// Mean and sample SD (n − 1), as Prism works them out.
func meanSD(_ a: [Double]) -> (mean: Double, sd: Double, n: Int)? {
    guard !a.isEmpty else { return nil }
    let m = a.reduce(0, +) / Double(a.count)
    let sd = a.count > 1 ? (a.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(a.count - 1)).squareRoot() : 0
    return (m, sd, a.count)
}

extension ResultSet {
    /// The calibrator for a gene: the one chosen, if that sample has Cts for this gene; otherwise the one
    /// qTOWER normalised to (expression exactly 1), or the sample it marked as calibrator.
    func calibrator(_ gene: GeneResult, _ opt: ResultsOptions) -> String? {
        func usable(_ s: SampleResult) -> Bool { !s.cts.isEmpty && !s.refCts.isEmpty }
        if !opt.deltaCalibrator.isEmpty, let s = gene.sample(opt.deltaCalibrator), usable(s) { return s.name }
        if let s = gene.samples.first(where: { ($0.normExpr.map { abs($0 - 1) < 1e-9 } ?? false) && usable($0) }) { return s.name }
        return gene.samples.first { $0.type.lowercased().contains("calib") && usable($0) }?.name
    }

    func delta(_ gene: GeneResult, _ condition: String, _ opt: ResultsOptions) -> Delta? {
        guard let s = gene.sample(condition), let ref = mean(s.refCts) else { return nil }
        let dct = s.cts.map { $0 - ref }
        var d = Delta(ct: mean(s.cts), refCt: ref, dct: dct, ddct: [], fold: [], calibrator: nil)
        if let cal = calibrator(gene, opt), let c = gene.sample(cal), let cm = mean(c.cts), let cr = mean(c.refCts) {
            d.calibrator = cal
            d.ddct = dct.map { $0 - (cm - cr) }
            d.fold = d.ddct.map { pow(2, -$0) }
        }
        return d
    }

    /// qTOWER's dCt for a gene and condition, exactly as in the file: the distinct values of its wells
    /// (qTOWER repeats one value per sample in each well). Empty when the file has none.
    func fileDCt(_ gene: GeneResult, _ condition: String) -> [Double] {
        var out: [Double] = []
        for v in gene.sample(condition)?.dctFile ?? [] where !out.contains(v) { out.append(v) }
        return out
    }

    /// True when any imported file carries qTOWER's dCt column.
    var hasFileDCt: Bool { genes.contains { $0.samples.contains { $0.dctFile != nil } } }

    /// The most wells any sample has, so replicate columns line up.
    var maxReplicates: Int { max(1, genes.flatMap { $0.samples }.map { max($0.replicates, $0.cts.count) }.max() ?? 1) }

    // MARK: tables for GraphPad Prism

    /// A Prism grouped table: row titles = conditions; for each gene, its replicates side by side (blank
    /// where a well gave no Ct). The first line names each gene over its first column.
    func prismGrouped(_ v: SummaryView, _ opt: ResultsOptions) -> [[String]] {
        let n = maxReplicates
        let conds = rows(opt).compactMap { $0 }
        var out: [[String]] = [[""] + genes.flatMap { g in [g.name] + Array(repeating: "", count: n - 1) }]
        for c in conds {
            var row = [label(c)]
            for g in genes {
                let vals = v == .relative ? [] : (delta(g, c, opt)?.values(v) ?? [])
                row += (0..<n).map { $0 < vals.count ? prismNumber(vals[$0]) : "" }
            }
            out.append(row)
        }
        return out
    }

    /// A Prism grouped table entered as mean, SD and N for each gene.
    func prismMeanSD(_ v: SummaryView, _ opt: ResultsOptions) -> [[String]] {
        let conds = rows(opt).compactMap { $0 }
        var out: [[String]] = [[""] + genes.flatMap { [$0.name, "", ""] }, [""] + genes.flatMap { _ in ["Mean", "SD", "N"] }]
        for c in conds {
            var row = [label(c)]
            for g in genes {
                let s: (mean: Double, sd: Double, n: Int)?
                switch v {
                case .relative: s = value(g, c, opt).map { ($0.value, $0.sd, $0.counted) }
                case .ct: s = g.sample(c).flatMap { meanSD($0.cts) }
                default: s = delta(g, c, opt).flatMap { meanSD($0.values(v)) }
                }
                row += s.map { [prismNumber($0.mean), prismNumber($0.sd), String($0.n)] } ?? ["", "", ""]
            }
            out.append(row)
        }
        return out
    }

    /// A Prism column table for one gene: a column per condition, its replicates down the rows.
    func prismColumn(_ gene: GeneResult, _ v: SummaryView, _ opt: ResultsOptions) -> [[String]] {
        let conds = rows(opt).compactMap { $0 }
        let cols = conds.map { c -> [Double] in v == .ct ? (gene.sample(c)?.cts ?? []) : (delta(gene, c, opt)?.values(v) ?? []) }
        let n = cols.map { $0.count }.max() ?? 0
        var out: [[String]] = [conds.map { label($0) }]
        for i in 0..<n { out.append(cols.map { i < $0.count ? prismNumber($0[i]) : "" }) }
        return out
    }

    /// qTOWER's dCt, copied as it is: a Prism grouped table with one value per gene and condition.
    func prismFileDCt(_ opt: ResultsOptions) -> [[String]] {
        let conds = rows(opt).compactMap { $0 }
        var out: [[String]] = [[""] + genes.map { $0.name }]
        for c in conds { out.append([label(c)] + genes.map { g in fileDCt(g, c).map(exactNumber).joined(separator: " / ") }) }
        return out
    }

    /// Mean Ct of each gene and of its reference wells, side by side.
    func prismCt(_ opt: ResultsOptions) -> [[String]] {
        let conds = rows(opt).compactMap { $0 }
        var out: [[String]] = [[""] + genes.flatMap { [$0.name, ($0.reference.isEmpty ? "Reference" : $0.reference) + " (\($0.name) plate)"] }]
        for c in conds {
            var row = [label(c)]
            for g in genes {
                let d = delta(g, c, opt)
                row += [d?.ct.map(prismNumber) ?? "", d?.refCt.map(prismNumber) ?? ""]
            }
            out.append(row)
        }
        return out
    }
}

/// A number written the way Excel shows it in a General cell: no rounding, no padding (-5.69, -5, 0.23).
func exactNumber(_ v: Double) -> String {
    guard v.isFinite else { return "" }
    return v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(v)
}

/// Numbers for Prism: plain, four decimals, no thousands separators.
func prismNumber(_ v: Double) -> String { v.isFinite ? String(format: "%.4f", v) : "" }

/// Tab-separated text, as Prism and Excel paste it.
func tsv(_ rows: [[String]]) -> String { rows.map { $0.joined(separator: "\t") }.joined(separator: "\n") + "\n" }
