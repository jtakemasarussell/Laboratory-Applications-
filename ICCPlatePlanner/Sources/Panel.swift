import Foundation

// MARK: - Panel check
//
// What a stain set will show under the microscope: which fluorophore each secondary carries, which
// primary it finds (by the species the primary was raised in), and where in the cell that marker sits.
// The same reading drives the staining preview and the checks on each stain card: two primaries from
// one species, a primary no secondary can find, a secondary with nothing to bind, two secondaries in
// one channel.

enum Localisation { case nuclear, cytoplasm, membrane }

struct Fluor: Equatable {
    var name: String          // "488", "DAPI"
    var wavelength: Int
    var counterstain: Bool    // DAPI / Hoechst: stains nuclei without a primary
    var hex: String { fluorHex(wavelength) }
    var band: Int {           // channels that cannot be told apart share a band
        switch wavelength { case ..<450: return 0; case ..<520: return 1; case ..<580: return 2; case ..<620: return 3; default: return 4 }
    }
}

/// The colour a channel is shown in: blue, green, amber, red, and magenta for far red.
func fluorHex(_ wavelength: Int) -> String {
    switch wavelength {
    case ..<450: return "5B8CFF"
    case ..<520: return "3DDC6E"
    case ..<580: return "FFC24A"
    case ..<620: return "FF5A4E"
    default: return "E061FF"
    }
}

private let knownWavelengths = [350, 405, 430, 488, 514, 532, 546, 555, 568, 594, 633, 647, 660, 680, 700, 750, 790]

func fluor(of q: Secondary) -> Fluor? {
    let text = (q.name + " " + (q.detail ?? "")).lowercased()
    if text.contains("dapi") { return Fluor(name: "DAPI", wavelength: 405, counterstain: true) }
    if text.contains("hoechst") { return Fluor(name: "Hoechst", wavelength: 405, counterstain: true) }
    var digits = "", found: Int? = nil
    for ch in text + " " {
        if ch.isASCII && ch.isNumber { digits.append(ch); continue }
        if digits.count == 3, let v = Int(digits), knownWavelengths.contains(v) { found = v; break }
        digits = ""
    }
    if let v = found { return Fluor(name: String(v), wavelength: v, counterstain: false) }
    if text.contains("fitc") { return Fluor(name: "FITC", wavelength: 488, counterstain: false) }
    if text.contains("tritc") || text.contains("cy3") { return Fluor(name: "Cy3", wavelength: 555, counterstain: false) }
    if text.contains("texas red") { return Fluor(name: "Texas Red", wavelength: 594, counterstain: false) }
    if text.contains("cy5") { return Fluor(name: "Cy5", wavelength: 647, counterstain: false) }
    return nil
}

private let speciesWords: [(String, [String])] = [
    ("rabbit", ["rabbit", "rab", "rb", "rbt"]), ("goat", ["goat", "gt", "g"]), ("rat", ["rat", "rt"]),
    ("mouse", ["mouse", "ms", "mo", "m"]), ("sheep", ["sheep", "sh", "shp"]), ("chicken", ["chicken", "chk", "ch"]),
    ("guinea pig", ["guinea pig", "gp", "guineapig"]), ("human", ["human", "hu"]), ("donkey", ["donkey", "dk"]),
    ("hamster", ["hamster"]), ("llama", ["llama"]), ("horse", ["horse"]),
]

func species(_ word: String) -> String? {
    let w = word.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
    guard !w.isEmpty else { return nil }
    return speciesWords.first { $0.1.contains(w) }?.0
}

/// The species a primary was raised in, from "(rab)", "(goat)" and the like.
func host(ofPrimary a: Antibody) -> String? {
    // Japanese keyboards type full-width brackets: "TH（mouse)"
    let n = a.name.replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
    guard let open = n.lastIndex(of: "("), let close = n[open...].firstIndex(of: ")") else { return nil }
    return species(String(n[n.index(after: open)..<close]))
}

/// The species a secondary recognises: "anti-Rabbit" in its product name, or the word after the
/// fluorophore in its short name ("488 rab").
func target(ofSecondary q: Secondary) -> String? {
    if let d = q.detail?.lowercased(), let r = d.range(of: "anti-") {
        let rest = d[r.upperBound...].prefix { $0.isLetter || $0 == " " }
        let words = rest.split(separator: " ").map(String.init)
        if words.count >= 2, let s = species(words[0] + " " + words[1]) { return s }
        if let w = words.first, let s = species(w) { return s }
    }
    let words = q.name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "/" }).map(String.init)
    for w in words where !(w.first?.isNumber ?? false) {
        if let s = species(w) { return s }
    }
    return nil
}

private let nuclearMarkers = ["LMX1", "FOXA", "OTX", "EN1", "EN2", "PITX", "SOX", "BARHL", "HUN", "NURR", "NR4A2", "PAX", "NKX",
                              "OLIG", "KI67", "MKI67", "FOXG", "GBX", "MSX", "NGN", "ASCL", "OCT", "NANOG", "LHX", "ISL", "HB9",
                              "MNX", "TBR", "CTIP", "SATB", "DAPI", "HOECHST", "PHH3", "H3", "TP53", "P53", "YAP", "SIX", "DLX",
                              "IRX", "ATOH", "PTF1", "PHOX", "WT1", "HOX", "MYT1", "NEUN", "RBFOX3", "FEV", "LMO"]
private let membraneMarkers = ["CORIN", "CD", "EPCAM", "NCAM", "PSA", "DAT", "SLC6A3", "GIRK", "KCNJ6", "ECAD", "CDH", "LRTM"]

func localisation(_ marker: String) -> Localisation {
    let m = marker.uppercased().replacingOccurrences(of: " ", with: "")
    if membraneMarkers.contains(where: { m.hasPrefix($0) }) { return .membrane }
    if nuclearMarkers.contains(where: { m.hasPrefix($0) }) { return .nuclear }
    return .cytoplasm
}

/// One channel under the microscope: a secondary's colour and the marker(s) it reveals.
struct Channel: Equatable {
    var fluor: Fluor
    var secondary: String
    var markers: [String]
    var localisation: Localisation
    var label: String { markers.isEmpty ? (fluor.counterstain ? "nuclei" : "no primary") : markers.joined(separator: " + ") }
}

enum Verdict: Equatable { case ok, problem, unknown }

/// A primary and the secondary that should find it, with the verdict and why.
struct Combination: Equatable {
    var primaryID: UUID
    var marker: String
    var host: String?
    var hostFacts: String?       // the maker's word on the host, when known
    var secondary: String?
    var secondaryFacts: String?
    var fluor: Fluor?
    var verdict: Verdict
    var reasons: [String]
}

struct PanelReport {
    var channels: [Channel] = []
    var combos: [Combination] = []
    var secondaryVerdicts: [UUID: (Verdict, String)] = [:]
    var issues: [String] = []    // every problem, for counts
    var notes: [String] = []     // the makers' caveats: information, not errors

    var summary: String {
        switch verdict {
        case .ok: return "Every primary has its own secondary, in its own channel."
        case .problem: return issues.joined(separator: "\n")
        case .unknown: return "Some antibodies cannot be checked yet: add the host species or the catalogue number."
        }
    }

    var verdict: Verdict {
        if !issues.isEmpty { return .problem }
        if combos.isEmpty || combos.contains(where: { $0.verdict == .unknown }) || secondaryVerdicts.values.contains(where: { $0.0 == .unknown }) { return .unknown }
        return .ok
    }
    func verdict(primary id: UUID) -> (Verdict, String) {
        guard let c = combos.first(where: { $0.primaryID == id }) else { return (.unknown, "") }
        return (c.verdict, c.reasons.joined(separator: "\n"))
    }
    func verdict(secondary id: UUID) -> (Verdict, String) { secondaryVerdicts[id] ?? (.unknown, "") }
}

/// The species a primary was raised in: the maker's word when its catalogue number is known, else the
/// species in brackets after its name.
func effectiveHost(_ p: Antibody) -> String? { facts(for: p)?.host ?? host(ofPrimary: p) }
/// The species a secondary's own name gives ("647 rab" → rabbit), if it gives one.
func nameSpecies(_ q: Secondary) -> String? {
    let words = q.name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "/" }).map(String.init)
    for w in words where !(w.first?.isNumber ?? false) { if let s = species(w) { return s } }
    return nil
}

/// What a secondary recognises. The name shown on the card wins: it is what the lab typed and reads.
/// Product details saved behind it (catalogue number, full name) only fill in when the name says nothing.
func secondaryTarget(_ q: Secondary) -> String? { nameSpecies(q) ?? facts(for: q)?.target ?? target(ofSecondary: q) }
func secondaryRaisedIn(_ q: Secondary) -> String? {
    if let f = facts(for: q) { return f.raisedIn }
    guard let d = q.detail?.lowercased(), let r = d.range(of: " anti-") else { return nil }
    return species(String(d[..<r.lowerBound]).split(separator: " ").last.map(String.init) ?? "")
}
func secondaryFluor(_ q: Secondary) -> Fluor? {
    if let f = fluor(of: Secondary(name: q.name)) { return f }          // the dye in the name wins too
    if let f = facts(for: q) { return Fluor(name: String(f.dye), wavelength: f.dye, counterstain: false) }
    return fluor(of: q)
}

/// The maker's facts for a secondary, only when they agree with what its name says.
func agreeingFacts(_ q: Secondary) -> SecondaryFacts? {
    guard let f = facts(for: q), f.target == secondaryTarget(q) else { return nil }
    return f
}

func panel(_ set: StainSet, library: Library = .seed) -> PanelReport {
    var r = PanelReport()
    let prim = set.primaries.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    let secs = set.secondaries.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    let dyed = secs.filter { !(secondaryFluor($0)?.counterstain ?? false) }

    // channels, for the preview and the chips
    for q in secs {
        guard let f = secondaryFluor(q) else { continue }
        if f.counterstain {
            r.channels.append(Channel(fluor: f, secondary: q.name, markers: [], localisation: .nuclear))
            continue
        }
        let t = secondaryTarget(q)
        let found = t.map { want in prim.filter { effectiveHost($0) == want } } ?? []
        let loc = found.first.map { localisation(markerName($0.name)) } ?? .cytoplasm
        r.channels.append(Channel(fluor: f, secondary: q.name, markers: found.map { markerName($0.name) }, localisation: loc))
    }

    // each primary and the secondary that should find it
    for p in prim {
        let marker = markerName(p.name)
        let kb = facts(for: p)
        let named = host(ofPrimary: p)
        let h = kb?.host ?? named
        var reasons: [String] = []
        var problem = false
        if let kb = kb, let named = named, named != kb.host {
            reasons.append("The name says \(named), but \(kb.maker) \(kb.cat) is raised in \(kb.host).")
            problem = true
        }
        guard let host = h else {
            r.combos.append(Combination(primaryID: p.id, marker: marker, host: nil, hostFacts: nil, secondary: nil, secondaryFacts: nil, fluor: nil,
                                        verdict: .unknown, reasons: ["Add the host species in brackets, e.g. \(marker) (goat), or a catalogue number the app knows, so the pairing can be checked."]))
            continue
        }
        let matches = dyed.filter { secondaryTarget($0) == host }
        let m = matches.first
        if matches.isEmpty {
            let offers = library.secondaries.filter { secondaryTarget($0) == host }.map { $0.name }
            reasons.append("\(marker) is a \(host) antibody and needs an anti-\(host) secondary" + (offers.isEmpty ? "." : ", e.g. \(offers.prefix(3).joined(separator: " or ")).") )
            problem = true
        } else if matches.count > 1 {
            reasons.append("\(matches.map { $0.name }.joined(separator: " and ")) are all anti-\(host): \(marker) would light up in \(matches.count) channels.")
            problem = true
        }
        let twins = prim.filter { $0.id != p.id && effectiveHost($0) == host }.map { markerName($0.name) }
        if !twins.isEmpty {
            reasons.append("\(twins.joined(separator: " and ")) is also raised in \(host): one anti-\(host) secondary cannot tell them apart.")
            problem = true
        }
        if let m = m, let f = secondaryFluor(m) {
            let clash = dyed.filter { $0.id != m.id && secondaryTarget($0) != host && secondaryFluor($0)?.band == f.band }
            if let c = clash.first {
                reasons.append("\(m.name) shares its channel with \(c.name): their signals cannot be told apart.")
                problem = true
            }
        }
        for q in secs where secondaryRaisedIn(q) == host && secondaryTarget(q) != host {
            reasons.append("\(q.name) is itself raised in \(host), so the anti-\(host) secondary binds it too.")
            problem = true
        }
        if !problem, let m = m {
            let mf = agreeingFacts(m)
            reasons.insert("\(marker) (\(host)) is found by \(m.name)" + (mf.map { ": \($0.summary)." } ?? ".")
                           + (kb.map { " \($0.maker) \($0.cat) is a \($0.host) \($0.clonality)." } ?? ""), at: 0)
        }
        r.combos.append(Combination(primaryID: p.id, marker: marker, host: host, hostFacts: kb?.summary, secondary: m?.name,
                                    secondaryFacts: m.flatMap { agreeingFacts($0)?.summary }, fluor: m.flatMap(secondaryFluor),
                                    verdict: problem ? .problem : .ok, reasons: reasons))
        if problem { r.issues += reasons }
        if let note = kb?.note { r.notes.append("\(marker): \(note)") }
    }

    // each secondary: does it find exactly one primary, cleanly?
    for q in secs {
        guard let f = secondaryFluor(q) else {
            r.secondaryVerdicts[q.id] = (.unknown, "Name the dye (488, 594, 647…) so the channel can be checked.")
            continue
        }
        if f.counterstain { r.secondaryVerdicts[q.id] = (.ok, "\(q.name) stains every nucleus; it needs no primary."); continue }
        guard let t = secondaryTarget(q) else {
            r.secondaryVerdicts[q.id] = (.unknown, "Add the species it recognises, e.g. \(f.name) rab, so the pairing can be checked.")
            continue
        }
        let found = prim.filter { effectiveHost($0) == t }
        if found.isEmpty {
            let why = "\(q.name) is anti-\(t), but no primary in this set is raised in \(t)."
            r.secondaryVerdicts[q.id] = (.problem, why)
            if !prim.isEmpty { r.issues.append(why) }
        } else {
            let bad = r.combos.filter { c in found.contains { $0.id == c.primaryID } && c.verdict == .problem }
            r.secondaryVerdicts[q.id] = bad.isEmpty
                ? (.ok, "\(q.name) finds \(found.map { markerName($0.name) }.joined(separator: " + ")).")
                : (.problem, bad.flatMap { $0.reasons }.joined(separator: "\n"))
        }
    }
    // saved product details that disagree with the name: worth a look, not an error
    for q in secs {
        guard let n = nameSpecies(q) else { continue }
        if let kb = facts(for: q), kb.target != n {
            r.notes.append("\(q.name): its saved catalogue number \(kb.cat) is \(kb.maker)'s anti-\(kb.target) Alexa Fluor \(kb.dye), but the name says \(n). The check follows the name; correct the catalogue number before ordering.")
        } else if facts(for: q) == nil, let d = target(ofSecondary: Secondary(name: "", detail: q.detail)), d != n {
            r.notes.append("\(q.name): its saved product name says anti-\(d), but the name says \(n). The check follows the name.")
        }
    }
    // the same problem can come from two sides; say it once
    var seen = Set<String>()
    r.issues = r.issues.filter { seen.insert($0).inserted }
    return r
}
