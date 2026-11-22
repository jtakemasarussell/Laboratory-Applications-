import SwiftUI
import Foundation

// MARK: - Live manufacturer check (the Antibody Registry)
//
// Every antibody with a catalogue number is looked up, live, in the Antibody Registry (antibodyregistry.org,
// run by SciCrunch), which records each manufacturer's product: vendor, catalogue number, target, the
// species it was raised in, clonality, its RRID and usually the product page. The app compares that with
// what the lab typed: the host in the name, the target, the company and, for secondaries, the species it
// recognises and its dye. A catalogue number the registry does not know is flagged, with the nearest one it
// does know (a typo such as "AD7388" for AF7388). Results are kept for 30 days so the fridge opens at once,
// and feed the compatibility check as manufacturer facts. Only the catalogue number is sent.

struct RegistryRecord: Codable, Equatable {
    var abId: Int
    var catalogNum: String
    var vendorName: String
    var abTarget: String
    var sourceOrganism: String
    var clonality: String
    var abName: String
    var url: String?
    /// Set when the record comes from the manufacturer's own page, checked for the app, rather than from the
    /// registry: the product is not listed there yet, so it has no RRID.
    var checkedOn: String? = nil

    var rrid: String { abId > 0 ? "AB_\(abId)" : "" }
    var link: URL? { url.flatMap(URL.init(string:)) ?? (abId > 0 ? URL(string: "https://scicrunch.org/resolver/RRID:\(rrid)") : nil) }

    /// A record from the manufacturer's page (no registry entry, so no RRID).
    init(catalogNum: String, vendorName: String, abTarget: String, sourceOrganism: String, clonality: String, abName: String,
         url: String?, checkedOn: String) {
        abId = 0
        self.catalogNum = catalogNum; self.vendorName = vendorName; self.abTarget = abTarget
        self.sourceOrganism = sourceOrganism; self.clonality = clonality; self.abName = abName
        self.url = url; self.checkedOn = checkedOn
    }

    init?(_ d: [String: Any]) {
        guard let id = d["abId"] as? Int else { return nil }
        abId = id
        func str(_ k: String) -> String { (d[k] as? String)?.trimmingCharacters(in: .whitespaces) ?? "" }
        catalogNum = str("catalogNum"); vendorName = str("vendorName"); abTarget = str("abTarget")
        sourceOrganism = str("sourceOrganism"); clonality = str("clonality"); abName = str("abName")
        url = (d["url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}

enum RegistryStatus: Equatable {
    case checking
    case verified                 // the registry's record agrees with the tube
    case mismatch([String])       // it disagrees: what, in words
    case notFound(RegistryRecord?) // no such catalogue number (and the nearest one it knows)
    case offline(String)          // could not ask
}

struct RegistryResult: Equatable {
    var status: RegistryStatus
    var record: RegistryRecord?
    var notes: [String] = []      // agreements worth saying, or small differences
    var checked = Date()

    var symbol: String {
        switch status {
        case .checking: return "hourglass"
        case .verified: return "checkmark.seal.fill"
        case .mismatch: return "exclamationmark.triangle.fill"
        case .notFound(let near): return near == nil ? "questionmark.circle.fill" : "xmark.octagon.fill"
        case .offline: return "wifi.slash"
        }
    }
    var colorHex: String {
        switch status {
        case .verified: return "3BB36A"
        case .mismatch: return "F2A900"
        case .notFound(let near): return near == nil ? "9FB7D6" : "E2483D"
        case .checking, .offline: return "9FB7D6"
        }
    }
    /// One or two lines for the fridge.
    var summary: String {
        let r = record
        let facts = r.map { rec in
            "\(rec.vendorName) \(rec.catalogNum): \(rec.abTarget), \(rec.sourceOrganism.lowercased()) \(rec.checkedOn == nil ? rec.clonality.lowercased() : rec.clonality)"
                + (rec.abId > 0 ? " · RRID \(rec.rrid)" : " · not in the Antibody Registry yet, so no RRID")
        } ?? ""
        switch status {
        case .checking: return "Checking with the manufacturer's record…"
        case .verified:
            if let page = r?.checkedOn { return "Matches the manufacturer's product page (\(page)). " + facts }
            return "Matches the manufacturer's record. " + facts
        case .mismatch(let why): return why.joined(separator: " ") + (facts.isEmpty ? "" : "  (" + facts + ")")
        case .notFound(let near):
            guard near != nil else {
                return "Not in the registry yet: new products can take a while to be listed. Check the catalogue number on the manufacturer's page."
            }
            return "No product with this catalogue number in the registry." + (near.map { n in
                let about = [n.vendorName, n.abTarget.isEmpty ? n.abName : n.abTarget, n.sourceOrganism.lowercased()].filter { !$0.isEmpty }.joined(separator: ", ")
                return " Did you mean \(n.catalogNum) (\(about))?" } ?? "")
        case .offline(let why): return "Could not reach the registry: \(why)"
        }
    }
}

/// Asks the registry and remembers the answers.
final class Registry: ObservableObject {
    static let shared = Registry()
    @Published private(set) var results: [String: RegistryResult] = [:]
    private var records: [String: RegistryRecord] = [:]      // by catKey, for the compatibility check
    private let maxAge: TimeInterval = 30 * 86400

    private struct Saved: Codable { var records: [String: RegistryRecord]; var dates: [String: Date] }
    private var dates: [String: Date] = [:]
    private static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ICC Plate Planner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("registry.json")
    }

    init() {
        if let d = try? Data(contentsOf: Self.file), let s = try? JSONDecoder().decode(Saved.self, from: d) {
            records = s.records; dates = s.dates
        }
    }
    private func persist() {
        if let d = try? JSONEncoder().encode(Saved(records: records, dates: dates)) { try? d.write(to: Self.file, options: .atomic) }
    }

    /// The registry's record for a catalogue number already looked up (the compatibility check uses it).
    func record(_ cat: String) -> RegistryRecord? { records[catKey(cat)] }

    func result(_ key: String) -> RegistryResult? { results[key] }
    static func key(_ cat: String, _ name: String) -> String { catKey(cat) + "|" + name }

    // MARK: checking

    func check(primary p: Antibody, force: Bool = false) {
        guard !catKey(p.cat).isEmpty else { return }
        run(key: Self.key(p.cat, p.name), cat: p.cat, company: p.company, force: force) { rec in Self.compare(primary: p, rec) }
    }

    func check(secondary q: Secondary, force: Bool = false) {
        guard let cat = q.cat, !catKey(cat).isEmpty else { return }
        run(key: Self.key(cat, q.name), cat: cat, company: q.company ?? "", force: force) { rec in Self.compare(secondary: q, rec) }
    }

    private func run(key: String, cat: String, company: String, force: Bool, compare: @escaping (RegistryRecord) -> RegistryResult) {
        let ck = catKey(cat)
        if !force, let rec = records[ck], let d = dates[ck], Date().timeIntervalSince(d) < maxAge {
            results[key] = compare(rec)
            return
        }
        if case .checking? = results[key]?.status { return }
        results[key] = RegistryResult(status: .checking)
        Task {
            let outcome = await Self.lookup(cat, company: company)
            await MainActor.run {
                switch outcome {
                case .found(let rec):
                    self.records[ck] = rec; self.dates[ck] = Date(); self.persist()
                    self.results[key] = compare(rec)
                case .missing(let near):
                    self.results[key] = RegistryResult(status: .notFound(near), record: nil)
                case .failed(let why):
                    self.results[key] = RegistryResult(status: .offline(why), record: nil)
                }
            }
        }
    }

    private enum Lookup { case found(RegistryRecord), missing(RegistryRecord?), failed(String) }

    private static func search(_ q: String) async throws -> [RegistryRecord] {
        var c = URLComponents(string: "https://www.antibodyregistry.org/api/fts-antibodies")!
        c.queryItems = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "size", value: "50")]
        var req = URLRequest(url: c.url!, timeoutInterval: 15)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("ICC-Plate-Planner", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let d = try JSONSerialization.jsonObject(with: data) as? [String: Any], let items = d["items"] as? [[String: Any]] else { return [] }
        return items.compactMap(RegistryRecord.init)
    }

    /// The catalogue numbers a record lists ("AF2400 (also AF2400-SP)" → AF2400, AF2400SP).
    private static func cats(_ r: RegistryRecord) -> Set<String> {
        var out: Set<String> = [catKey(r.catalogNum)]
        for part in r.catalogNum.components(separatedBy: CharacterSet(charactersIn: " ,;()/")) where !part.isEmpty {
            let k = catKey(part)
            if k.count >= 3 && k != "ALSO" { out.insert(k) }
        }
        return out
    }

    /// Whether a registry vendor is the company the lab wrote ("R&D" ~ "R and D Systems", "Merck" ~ "Millipore").
    static func sameMaker(_ vendor: String, _ company: String) -> Bool {
        let v = vendor.lowercased(), c = company.lowercased()
        guard !c.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        let families: [[String]] = [["r&d", "r and d", "bio-techne", "biotechne", "novus"], ["merck", "millipore", "sigma", "chemicon"],
                                    ["thermo", "invitrogen", "molecular probes", "life technologies"], ["abcam"], ["biolegend", "covance"],
                                    ["jackson"], ["cell signaling"], ["santa cruz"], ["proteintech"], ["novus"]]
        for f in families where f.contains(where: { c.contains($0) }) { return f.contains(where: { v.contains($0) }) }
        let word = c.split(separator: " ").first.map(String.init) ?? c
        return v.contains(word)
    }

    private static func lookup(_ cat: String, company: String) async -> Lookup {
        let want = catKey(cat)
        do {
            let hits = try await search(cat)
            let exact = hits.filter { cats($0).contains(want) }
            if let best = exact.first(where: { sameMaker($0.vendorName, company) }) ?? exact.first { return .found(best) }
            // not listed yet, but checked on the manufacturer's own page for the app
            if let page = checkedRecord(cat) { return .found(page) }
            // nothing with that number: look for the nearest one, by its digits
            let digits = String(want.filter { $0.isNumber })
            var pool = hits
            if digits.count >= 4, digits != want { pool += (try? await search(digits)) ?? [] }
            // a likely typo only from the same company: a near number from another maker is a different
            // product (ab313403 is not BioLegend's anti-ZAP-70 "313403")
            let near = pool
                .map { r in (r, cats(r).map { editDistance($0, want) }.min() ?? 99) }
                .filter { $0.1 <= 2 && sameMaker($0.0.vendorName, company) }
                .sorted { ($0.1, sameMaker($0.0.vendorName, company) ? 0 : 1) < ($1.1, sameMaker($1.0.vendorName, company) ? 0 : 1) }
                .first?.0
            return .missing(near)
        } catch {
            if let page = checkedRecord(cat) { return .found(page) }
            return .failed(error.localizedDescription)
        }
    }

    // MARK: comparing

    private static func words(_ s: String) -> String { String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }) }

    static func compare(primary p: Antibody, _ r: RegistryRecord) -> RegistryResult {
        var problems: [String] = [], notes: [String] = []
        let regHost = species(r.sourceOrganism.lowercased()) ?? r.sourceOrganism.lowercased()
        if let named = host(ofPrimary: p), !regHost.isEmpty, named != regHost {
            problems.append("The manufacturer lists \(r.catalogNum) as raised in \(regHost), but the name says \(named).")
        }
        let marker = words(markerName(p.name)), target = words(r.abTarget + " " + r.abName)
        // "TH" is the initials of "Tyrosine Hydroxylase"
        let initials = (r.abTarget.split(whereSeparator: { !$0.isLetter }).compactMap { $0.first }).map { String($0) }.joined().lowercased()
        if !marker.isEmpty, !target.isEmpty, !target.contains(String(marker.prefix(4))), !(initials.hasPrefix(marker) && marker.count >= 2) {
            notes.append("The registry's target is \(r.abTarget), not obviously \(markerName(p.name)).")
        }
        if !sameMaker(r.vendorName, p.company) {
            notes.append("The registry lists it under \(r.vendorName), not \(p.company).")
        }
        return RegistryResult(status: problems.isEmpty ? .verified : .mismatch(problems), record: r, notes: notes)
    }

    static func compare(secondary q: Secondary, _ r: RegistryRecord) -> RegistryResult {
        var problems: [String] = [], notes: [String] = []
        // what it recognises: the species in its target ("Rabbit IgG (H+L)")
        let recognises = r.abTarget.split(whereSeparator: { !$0.isLetter }).map { String($0) }.compactMap { species($0.lowercased()) }.first
        if let named = nameSpecies(q), let reg = recognises, named != reg {
            problems.append("The manufacturer lists \(r.catalogNum) as anti-\(reg), but the name says anti-\(named).")
        }
        // its dye: the number in the name against the one in the product name
        let dyeIn: (String) -> Int? = { s in
            for w in s.split(whereSeparator: { !$0.isNumber }) { if let n = Int(w), [350, 405, 488, 532, 546, 555, 568, 594, 633, 647, 660, 680, 750].contains(n) { return n } }
            return nil
        }
        if let named = dyeIn(q.name), let reg = dyeIn(r.abName), named != reg {
            problems.append("The manufacturer's product carries Alexa Fluor \(reg), but the name says \(named).")
        }
        if let c = q.company, !sameMaker(r.vendorName, c) { notes.append("The registry lists it under \(r.vendorName), not \(c).") }
        return RegistryResult(status: problems.isEmpty ? .verified : .mismatch(problems), record: r, notes: notes)
    }
}

/// Letters changed, added or dropped between two strings.
func editDistance(_ a: String, _ b: String) -> Int {
    let x = Array(a), y = Array(b)
    if x.isEmpty { return y.count }
    if y.isEmpty { return x.count }
    var row = Array(0...y.count)
    for i in 1...x.count {
        var prev = row[0]; row[0] = i
        for j in 1...y.count {
            let cur = row[j]
            row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (x[i - 1] == y[j - 1] ? 0 : 1))
            prev = cur
        }
    }
    return row[y.count]
}

/// The line under a new tube's form, and the badge on a tube: what the manufacturer's record says.
struct RegistryBadge: View {
    let result: RegistryResult?
    var body: some View {
        if let r = result {
            Image(systemName: r.symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color(hex: r.colorHex))
                .padding(2)
                .background(Circle().fill(Color(hex: "0E1B2C")))
                .help(r.summary + (r.notes.isEmpty ? "" : "\n" + r.notes.joined(separator: "\n")))
        }
    }
}

struct RegistryLine: View {
    let result: RegistryResult?
    var use: ((RegistryRecord) -> Void)? = nil
    var body: some View {
        if let r = result {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: r.symbol).foregroundColor(Color(hex: r.colorHex)).font(.system(size: 12, weight: .bold))
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.summary).font(.system(size: 10.5)).foregroundColor(.white).fixedSize(horizontal: false, vertical: true)
                    ForEach(r.notes, id: \.self) { n in
                        Text(n).font(.system(size: 10)).foregroundColor(Color(hex: "9FB7D6")).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 12) {
                        if let rec = r.record, let use {
                            Button("Use these details") { use(rec) }
                        }
                        if case .notFound(let near?) = r.status, let use {
                            Button("Use \(near.catalogNum)") { use(near) }
                        }
                        if let link = (r.record ?? { if case .notFound(let n) = r.status { return n }; return nil }())?.link {
                            Link("Manufacturer / registry page", destination: link)
                        }
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .buttonStyle(.borderless)
                    .foregroundColor(Color(hex: "BFE3FF"))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: r.colorHex).opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: r.colorHex).opacity(0.5), lineWidth: 1))
        }
    }
}
