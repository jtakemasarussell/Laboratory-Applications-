import Foundation

// MARK: - Data model

struct Antibody: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var company = ""
    var cat = ""
    var dilution: Double = 0         // 0 = not set yet
    var rrid: String? = nil
}

struct Secondary: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var dilution: Double = 0         // 0 = not set yet
    var detail: String? = nil        // full product name, e.g. "Donkey anti-Rabbit IgG, Alexa Fluor 488"
    var company: String? = nil
    var cat: String? = nil
    var rrid: String? = nil
}

struct StainSet: Codable, Identifiable, Hashable {
    var id = UUID()
    var primaries: [Antibody] = []
    var secondaries: [Secondary] = []
    var volumeOverride: Double? = nil
    var colorHex: String? = nil      // custom well colour (RRGGBB); nil = the default for its position
}

struct Sample: Codable, Identifiable, Hashable {
    var id = UUID()
    var code = ""
    var name = ""
    var hasDay0 = true      // each experiment carries its own Day 0, filled in as soon as the sample exists
    var day0 = Date()
    var day = ""
    var fixed: Date? = nil  // date the cells were fixed; nil = automatic (Day 0 + the lab's fixation day)
    /// Short label stamped onto the plate: the experiment number, or the name if there is no number.
    var tag: String {
        let c = code.trimmingCharacters(in: .whitespaces)
        return c.isEmpty ? name.trimmingCharacters(in: .whitespaces) : c
    }
    var title: String {
        [code, name].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension Sample {
    // Tolerant decoding: samples saved before per-experiment Day 0 existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        hasDay0 = try c.decodeIfPresent(Bool.self, forKey: .hasDay0) ?? false
        day0 = try c.decodeIfPresent(Date.self, forKey: .day0) ?? Date()
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        fixed = try c.decodeIfPresent(Date.self, forKey: .fixed)
    }
}

struct Settings: Codable, Hashable {
    var ulPerWell: Double = 100      // antibody solution per well
    var extraWells: Double = 1       // excess, counted in wells
    var blockPerWell: Double = 100   // blocking step volume per stained well (µL)
    var blockExtraUl: Double = 100   // small excess added to the blocking buffer total (µL)
    var ndsPerMl: Double = 20        // µL NDS per mL blocking buffer
    var fixDay: Double = 14          // cells are fixed this many days after Day 0

    init() {}

    // Tolerant decoding so settings saved by an older version of the app still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ulPerWell = try c.decodeIfPresent(Double.self, forKey: .ulPerWell) ?? 100
        extraWells = try c.decodeIfPresent(Double.self, forKey: .extraWells) ?? 1
        blockPerWell = try c.decodeIfPresent(Double.self, forKey: .blockPerWell) ?? 100
        blockExtraUl = try c.decodeIfPresent(Double.self, forKey: .blockExtraUl) ?? 100
        ndsPerMl = try c.decodeIfPresent(Double.self, forKey: .ndsPerMl) ?? 20
        fixDay = try c.decodeIfPresent(Double.self, forKey: .fixDay) ?? 14
    }
}

struct Library: Codable, Hashable {
    var primaries: [Antibody] = []
    var secondaries: [Secondary] = []

    mutating func remember(_ sets: [StainSet]) {
        for s in sets {
            for p in s.primaries where !p.name.trimmingCharacters(in: .whitespaces).isEmpty {
                if let i = primaries.firstIndex(where: { $0.name == p.name }) {
                    let keep = primaries[i].id
                    primaries[i] = p
                    primaries[i].id = keep
                } else {
                    var n = p; n.id = UUID(); primaries.append(n)
                }
            }
            for q in s.secondaries where !q.name.trimmingCharacters(in: .whitespaces).isEmpty {
                if let i = secondaries.firstIndex(where: { $0.name == q.name }) {
                    let keep = secondaries[i].id
                    secondaries[i] = q
                    secondaries[i].id = keep
                } else {
                    var n = q; n.id = UUID(); secondaries.append(n)
                }
            }
        }
    }

    /// The department's antibody list. Dilutions follow the lab's staining sheet (2026-11-17,
    /// #374/#376/#382/#383): 1:500 for 488 rab / 594 g / 488 rat, 1:400 for the ms and rab
    /// secondaries, 1:200 for 488 sheep; 0 on a primary means "set it yourself".
    static var seed: Library {
        Library(
            primaries: [
                Antibody(name: "LMX1A/B (rab)", company: "Merck", cat: "AB10533", dilution: 1000, rrid: "AB_10805970"),
                Antibody(name: "FOXA2 (g)", company: "R&D Systems", cat: "AF2400", dilution: 500, rrid: "AB_2294104"),
                Antibody(name: "Corin (rat)", company: "R&D Systems", cat: "MAB2209", dilution: 500, rrid: "AB_2082224"),
                Antibody(name: "OTX2 (g)", company: "R&D Systems", cat: "AF1979", dilution: 1000, rrid: "AB_2157172"),
                Antibody(name: "TH (rab)", company: "Merck", cat: "AB152", dilution: 0, rrid: "AB_390204"),
                Antibody(name: "Tubulin beta III (ms)", company: "BioLegend", cat: "801201", dilution: 0, rrid: "AB_2313773"),
                Antibody(name: "HuN (ms)", company: "Merck", cat: "MAB1281", dilution: 0, rrid: "AB_94090"),
                Antibody(name: "TH (mouse)", company: "Merck", cat: "MAB318", dilution: 500),
                Antibody(name: "Tubulin beta III (rab)", company: "BioLegend", cat: "RPB435-P", dilution: 1000),
                Antibody(name: "Barhl1 (rab)", company: "Novus Bio", cat: "NBO1-86513", dilution: 500),
                Antibody(name: "Pitx2 (sheep)", company: "R&D Systems", cat: "AD7388", dilution: 200),
                Antibody(name: "Pitx3 (rab)", company: "Abcam", cat: "ab313403", dilution: 500),
                Antibody(name: "SOX6 (mouse)", company: "R&D Systems", cat: "MAB7759", dilution: 500),
                Antibody(name: "EN1 (rab)", company: "Merck", cat: "AB5732", dilution: 2000),
            ],
            secondaries: [
                Secondary(name: "488 rab", dilution: 500, detail: "Donkey anti-Rabbit IgG, Alexa Fluor 488", company: "Thermo Fisher Scientific", cat: "A-21206", rrid: "AB_2535792"),
                Secondary(name: "594 g", dilution: 500, detail: "Donkey anti-Goat IgG, Alexa Fluor 594", company: "Thermo Fisher Scientific", cat: "A-11058", rrid: "AB_142540"),
                Secondary(name: "488 rat", dilution: 500, detail: "Donkey anti-Rat IgG, Alexa Fluor 488", company: "Thermo Fisher Scientific", cat: "A-21208", rrid: "AB_2535794"),
                Secondary(name: "647 ms", dilution: 400, detail: "Donkey anti-Mouse IgG, Alexa Fluor 647", company: "Thermo Fisher Scientific", cat: "A-31571", rrid: "AB_162542"),
                Secondary(name: "488 ms", dilution: 400, detail: "Donkey anti-Mouse IgG, Alexa Fluor 488", company: "Thermo Fisher Scientific", cat: "A-21202", rrid: "AB_141607"),
                Secondary(name: "594 rab", dilution: 400, detail: "Donkey anti-Rabbit IgG, Alexa Fluor 594", company: "Thermo Fisher Scientific", cat: "A-21207", rrid: "AB_141637"),
                Secondary(name: "647 rab", dilution: 400),
                Secondary(name: "488 sheep", dilution: 200),
            ])
    }

    static let seedVersion = 5

    /// Version 3: 488 rab and 488 rat default to 1:500. Only values still at the old 1:400 are changed.
    static func is488Default(_ q: Secondary) -> Bool {
        let n = q.name.trimmingCharacters(in: .whitespaces).lowercased()
        return (n == "488 rab" || n == "488 rat") && q.dilution == 400
    }

    /// Version 4: 594 g defaults to 1:500 as well. Again only values still at the old 1:400 are changed.
    static func is594gDefault(_ q: Secondary) -> Bool {
        q.name.trimmingCharacters(in: .whitespaces).lowercased() == "594 g" && q.dilution == 400
    }

    /// Version 5: the department list gains the antibodies imported from the 2026-11-17 plate, and
    /// 647 ms / 488 ms / 594 rab follow the sheet at 1:400. Only values still at 1:500 — which only
    /// the short-lived "all secondaries 1:500" build would have written — are changed back.
    static func isSecondary500FromSheet400(_ q: Secondary) -> Bool {
        let n = q.name.trimmingCharacters(in: .whitespaces).lowercased()
        return ["488 ms", "594 rab", "647 ms"].contains(n) && q.dilution == 500
    }

    /// Adds the department list to a library saved by an earlier version. Entries the user already has
    /// (same catalogue number, or same short name for secondaries) keep their name and dilution and
    /// only gain the missing company / RRID details.
    mutating func mergeSeed() {
        let seed = Library.seed
        for p in seed.primaries {
            if let i = primaries.firstIndex(where: { $0.cat.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(p.cat) == .orderedSame }) {
                primaries[i].company = p.company
                primaries[i].rrid = p.rrid
            } else {
                primaries.append(p)
            }
        }
        for q in seed.secondaries {
            if let i = secondaries.firstIndex(where: { $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(q.name) == .orderedSame }) {
                secondaries[i].detail = q.detail; secondaries[i].company = q.company
                secondaries[i].cat = q.cat; secondaries[i].rrid = q.rrid
            } else {
                secondaries.append(q)
            }
        }
    }
}

struct Experiment: Codable, Equatable {
    var date = Date()
    var samples: [Sample] = [Sample()]
    var hasDay0 = false
    var day0 = Date()
    var day = ""
    var sets: [StainSet] = []
    var wells: [UUID?] = Array(repeating: nil, count: 96)
    var wellText: [String] = Array(repeating: "", count: 96)
    /// Experiment tag stamped on a well, stored as the sample's id so the label follows the sample
    /// when its number is edited later.
    var wellTags: [UUID?] = Array(repeating: nil, count: 96)
    var leftLabels: [String] = Array(repeating: "", count: 8)
    var topLabels: [String] = Array(repeating: "", count: 12)
    var blockingOverride: Double? = nil
    /// Your own name for the output file; empty = automatic (date + sample numbers). Use it when
    /// the automatic name gets too long.
    var customTitle = ""

    /// First run starts completely blank: no stain sets, no antibodies — the user adds them.
    static var starter: Experiment { Experiment() }

    /// The text shown in a well: its stamped experiment tag if it has one, otherwise its typed label.
    func label(_ w: Int) -> String {
        if let id = wellTags[w], let s = samples.first(where: { $0.id == id }) { return s.tag }
        return wellText[w]
    }

    // MARK: Calculations

    func wellCount(_ set: StainSet) -> Int { wells.filter { $0 == set.id }.count }

    var totalStainedWells: Int {
        let ids = Set(sets.map { $0.id })
        return wells.filter { $0 != nil && ids.contains($0!) }.count
    }

    func autoVolume(_ set: StainSet, _ st: Settings) -> Double {
        let n = wellCount(set)
        return n == 0 ? 0 : (Double(n) + st.extraWells) * st.ulPerWell
    }

    func volume(_ set: StainSet, _ st: Settings) -> Double {
        set.volumeOverride ?? autoVolume(set, st)
    }

    /// µL needed: blocking step for every stained well + primary diluent + secondary diluent.
    func blockingNeedUl(_ st: Settings) -> Double {
        var ul = st.blockPerWell * Double(totalStainedWells)
        for s in sets {
            let v = volume(s, st)
            if !s.primaries.isEmpty { ul += v }
            if !s.secondaries.isEmpty { ul += v }
        }
        return ul
    }

    /// What is needed plus a small excess, rounded up to the next 0.1 mL.
    func suggestedBlocking(_ st: Settings) -> Double {
        let need = blockingNeedUl(st)
        if need <= 0 { return 0 }
        return ((need + st.blockExtraUl) / 100 - 1e-9).rounded(.up) / 10
    }

    func blocking(_ st: Settings) -> Double { blockingOverride ?? suggestedBlocking(st) }

    var dateNumber: Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// The automatic file name: the staining date plus every sample's number or name.
    var autoFileName: String {
        var parts = [String(dateNumber)]
        for s in samples {
            let c = s.code.trimmingCharacters(in: .whitespaces)
            let n = s.name.trimmingCharacters(in: .whitespaces)
            if !c.isEmpty { parts.append(c) } else if !n.isEmpty { parts.append(n) }
        }
        return parts.joined(separator: "_")
    }

    var fileName: String {
        var t = customTitle.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasSuffix(".xlsx") { t = String(t.dropLast(5)).trimmingCharacters(in: .whitespaces) }
        let raw = t.isEmpty ? autoFileName : t
        return raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".xlsx"
    }

    /// Calendar days from this experiment's Day 0 to the staining date.
    func daysSinceDay0(_ sample: Sample) -> Int? {
        guard sample.hasDay0 else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: sample.day0), to: cal.startOfDay(for: date)).day
    }

    /// Fixation date when nothing was picked by hand: Day 0 plus the lab's fixation day (14).
    func autoFixedDate(_ sample: Sample, _ st: Settings) -> Date? {
        guard sample.hasDay0 else { return nil }
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: Int(st.fixDay.rounded()), to: cal.startOfDay(for: sample.day0))
    }

    /// The date the cells were fixed: the one picked by hand, otherwise the automatic one.
    func fixedDate(_ sample: Sample, _ st: Settings) -> Date? {
        guard sample.hasDay0 else { return nil }
        return sample.fixed ?? autoFixedDate(sample, st)
    }

    /// The Day written on the sheet: what was typed, or else the day the cells were fixed
    /// (date fixed minus Day 0, so 14 unless the fixed date was changed).
    func dayText(_ sample: Sample, _ st: Settings) -> String {
        let typed = sample.day.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { return typed }
        guard let f = fixedDate(sample, st) else { return "" }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: sample.day0), to: cal.startOfDay(for: f)).day.map { String($0) } ?? ""
    }

    /// Moves a plate-wide Day 0 saved by an older version onto every sample.
    mutating func migrateDay0() {
        guard hasDay0 || !day.isEmpty else { return }
        for i in samples.indices where !samples[i].hasDay0 && samples[i].day.isEmpty {
            samples[i].hasDay0 = hasDay0
            samples[i].day0 = day0
            samples[i].day = day
        }
        hasDay0 = false
        day = ""
    }
}

extension Experiment {
    // Tolerant decoding: a file saved by an older version (missing newer fields) still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        samples = try c.decodeIfPresent([Sample].self, forKey: .samples) ?? [Sample()]
        hasDay0 = try c.decodeIfPresent(Bool.self, forKey: .hasDay0) ?? false
        day0 = try c.decodeIfPresent(Date.self, forKey: .day0) ?? Date()
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        sets = try c.decodeIfPresent([StainSet].self, forKey: .sets) ?? []
        wells = try c.decodeIfPresent([UUID?].self, forKey: .wells) ?? wells
        wellText = try c.decodeIfPresent([String].self, forKey: .wellText) ?? wellText
        leftLabels = try c.decodeIfPresent([String].self, forKey: .leftLabels) ?? leftLabels
        topLabels = try c.decodeIfPresent([String].self, forKey: .topLabels) ?? topLabels
        blockingOverride = try c.decodeIfPresent(Double.self, forKey: .blockingOverride)
        customTitle = try c.decodeIfPresent(String.self, forKey: .customTitle) ?? ""
        fixCenturies()
        if let tags = try c.decodeIfPresent([UUID?].self, forKey: .wellTags) {
            wellTags = tags
        } else if wellText.count == 96 {
            // Older files stored a stamped tag as plain text; link those wells to their sample.
            for w in 0..<96 where !wellText[w].isEmpty {
                if let s = samples.first(where: { !$0.tag.isEmpty && $0.tag == wellText[w] }) {
                    wellTags[w] = s.id
                    wellText[w] = ""
                }
            }
        }
    }
}

// MARK: - Helpers

/// Typing "26" into a date's year box gives the year 0026. No plate was stained then, so a
/// two-digit year is read as 20xx.
func fixCentury(_ d: Date) -> Date {
    let cal = Calendar.current
    let y = cal.component(.year, from: d)
    guard y < 100 else { return d }
    return cal.date(byAdding: .year, value: 2000, to: d) ?? d
}

extension Experiment {
    mutating func fixCenturies() {
        date = fixCentury(date)
        for i in samples.indices {
            samples[i].day0 = fixCentury(samples[i].day0)
            if let f = samples[i].fixed { samples[i].fixed = fixCentury(f) }
        }
    }
}

let rowLetters = ["A", "B", "C", "D", "E", "F", "G", "H"]

/// Light fills matching Excel's "Accent, Lighter 80%" swatches (set 1 = green, set 2 = gold, as in the lab template).
let setPalette = ["E2EFDA", "FFF2CC", "DDEBF7", "FCE4D6", "E4DFEC", "EDEDED", "F8CBAD", "C6E0B4"]

func setColorHex(_ index: Int) -> String { setPalette[index % setPalette.count] }

/// The colour a stain set's wells are filled with, in the app and in the Excel sheet.
func fillHex(_ set: StainSet, _ index: Int) -> String {
    // a custom colour is only used if it really is six hex digits; anything else falls back to the default
    if let c = set.colorHex, c.count == 6, UInt32(c, radix: 16) != nil { return c.uppercased() }
    return setColorHex(index)
}

/// A value typed as a plain decimal number ("100", "0.5", "-2"). Anything else stays text, so labels
/// such as "007", "1e5" or "0x10" are never silently turned into different numbers.
func plainNumber(_ text: String) -> Double? {
    let t = text.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty, t.count <= 15 else { return nil }
    var digits = Substring(t)
    if digits.hasPrefix("-") { digits = digits.dropFirst() }
    let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2, let whole = parts.first, !whole.isEmpty,
          parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
    if whole.count > 1 && whole.hasPrefix("0") { return nil }   // keep leading zeros as text
    guard let d = Double(t), d.isFinite else { return nil }
    return d
}

/// True when black text would be hard to read on this fill.
func isDark(_ hex: String) -> Bool {
    let v = UInt32(hex, radix: 16) ?? 0xFFFFFF
    let r = Double((v >> 16) & 0xFF), g = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
    return (0.299 * r + 0.587 * g + 0.114 * b) < 140
}

func fmtNum(_ d: Double) -> String {
    if d.isNaN || d.isInfinite { return "–" }
    if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
    var s = String(format: "%.3f", d)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}

func markerName(_ antibody: String) -> String {
    var s = antibody
    if let r = s.range(of: "(") { s = String(s[..<r.lowerBound]) }
    return s.trimmingCharacters(in: .whitespaces).uppercased()
}
