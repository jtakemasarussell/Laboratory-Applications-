import Foundation

// MARK: - Manufacturer knowledge base
//
// What the makers say about the department's antibodies: the species each primary was raised in and
// what each secondary recognises, read from the manufacturers' product pages and datasheets (checked
// November 2026). The compatibility check trusts these over the short name typed in the app, so a
// primary named "(rab)" whose catalogue number belongs to a mouse antibody is caught.

struct ProductFacts {
    var maker: String
    var cat: String
    var target: String
    var host: String            // species the antibody was raised in
    var clonality: String
    var note: String? = nil     // the maker's own caveat, shown as information
    var source: String          // where the facts come from

    var summary: String { "\(maker) \(cat): \(target), \(host) \(clonality)" }
}

struct SecondaryFacts {
    var maker: String
    var cat: String
    var raisedIn: String
    var target: String          // species whose IgG it binds
    var dye: Int                // Alexa Fluor number
    var source: String

    var summary: String { "\(maker) \(cat): \(raisedIn.capitalized) anti-\(target.capitalized) IgG (H+L), highly cross-adsorbed, Alexa Fluor \(dye)" }
}

/// Catalogue numbers compared on letters and digits only, so "AB-10533", "ab10533" and "AB10533" match.
func catKey(_ s: String) -> String {
    String(s.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
}

private let primaryFacts: [ProductFacts] = [
    ProductFacts(maker: "Merck (Millipore)", cat: "AB10533", target: "LMX1A", host: "rabbit", clonality: "polyclonal (serum)",
                 note: "Merck validates AB10533 for western blot only; the lab's own ICC is its validation.",
                 source: "merckmillipore.com/product/mm/ab10533"),
    ProductFacts(maker: "R&D Systems", cat: "AF2400", target: "HNF-3β/FOXA2", host: "goat", clonality: "polyclonal IgG",
                 source: "rndsystems.com AF2400 (ICC listed)"),
    ProductFacts(maker: "R&D Systems", cat: "MAB2209", target: "Corin", host: "rat", clonality: "monoclonal IgG2A, clone 231443",
                 source: "rndsystems.com MAB2209 (validated for ICC)"),
    ProductFacts(maker: "R&D Systems", cat: "AF1979", target: "OTX2", host: "goat", clonality: "polyclonal IgG",
                 source: "rndsystems.com AF1979"),
    ProductFacts(maker: "Merck (Millipore)", cat: "AB152", target: "Tyrosine hydroxylase", host: "rabbit", clonality: "polyclonal, affinity purified",
                 source: "Merck neuroscience antibody catalogue (IF listed)"),
    ProductFacts(maker: "BioLegend", cat: "801201", target: "Tubulin β3 (TUBB3)", host: "mouse", clonality: "monoclonal IgG2a, clone TUJ1 (formerly Covance MMS-435P)",
                 source: "biolegend.com purified anti-TUBB3, TUJ1"),
    ProductFacts(maker: "Merck (Millipore)", cat: "MAB1281", target: "Human nuclei", host: "mouse", clonality: "monoclonal IgG1, clone 235-1",
                 note: "MAB1281 stains human nuclei only; mouse and rat nuclei stay dark.",
                 source: "merckmillipore.com/product/mm/mab1281"),
    ProductFacts(maker: "Merck (Millipore)", cat: "MAB318", target: "Tyrosine hydroxylase", host: "mouse", clonality: "monoclonal, clone LNC1",
                 source: "Merck neuroscience antibody catalogue"),
    ProductFacts(maker: "BioLegend", cat: "802001", target: "Tubulin β3 (TUBB3)", host: "rabbit", clonality: "polyclonal, Poly18020 (formerly Covance PRB-435P)",
                 note: "BioLegend verifies 802001 for IHC-P and western blot; ICC comes from the literature.",
                 source: "biolegend.com purified anti-TUBB3 (previously Covance PRB-435P)"),
    ProductFacts(maker: "Novus Biologicals", cat: "NBP1-86513", target: "BARHL1", host: "rabbit", clonality: "polyclonal IgG",
                 note: "Novus' current datasheet says the present lot is not validated for ICC/IF: check your lot.",
                 source: "novusbio.com NBP1-86513 datasheet"),
    ProductFacts(maker: "R&D Systems", cat: "AF7388", target: "PITX2", host: "sheep", clonality: "polyclonal IgG",
                 note: "R&D validates AF7388 for IHC.",
                 source: "bio-techne.com AF7388"),
    ProductFacts(maker: "Abcam", cat: "ab313403", target: "PITX3", host: "rabbit", clonality: "recombinant multiclonal, RP23040049",
                 source: "abcam.com ab313403 (WB, ICC/IF)"),
    ProductFacts(maker: "R&D Systems", cat: "MAB7759", target: "SOX6", host: "mouse", clonality: "monoclonal IgG2A, clone 667136",
                 source: "rndsystems.com MAB7759 (validated for ICC)"),
    ProductFacts(maker: "Merck (Millipore)", cat: "AB5732", target: "Engrailed-1", host: "rabbit", clonality: "polyclonal",
                 source: "merckmillipore.com/product/mm/AB5732"),
]

/// Earlier spellings of the same catalogue numbers, as typed in the lab's sheets.
private let catAliases: [String: String] = [
    "RPB435P": "802001", "PRB435P": "802001", "MMS435P": "801201", "NBO186513": "NBP1-86513",
]

private let secondaryFacts: [SecondaryFacts] = [
    SecondaryFacts(maker: "Thermo Fisher", cat: "A-21206", raisedIn: "donkey", target: "rabbit", dye: 488, source: "thermofisher.com A-21206"),
    SecondaryFacts(maker: "Thermo Fisher", cat: "A-11058", raisedIn: "donkey", target: "goat", dye: 594, source: "thermofisher.com A-11058"),
    SecondaryFacts(maker: "Thermo Fisher", cat: "A-21208", raisedIn: "donkey", target: "rat", dye: 488, source: "thermofisher.com A-21208"),
    SecondaryFacts(maker: "Thermo Fisher", cat: "A-31571", raisedIn: "donkey", target: "mouse", dye: 647, source: "thermofisher.com A-31571"),
    SecondaryFacts(maker: "Thermo Fisher", cat: "A-21202", raisedIn: "donkey", target: "mouse", dye: 488, source: "thermofisher.com A-21202"),
    SecondaryFacts(maker: "Thermo Fisher", cat: "A-21207", raisedIn: "donkey", target: "rabbit", dye: 594, source: "thermofisher.com A-21207"),
]

private let primaryIndex: [String: ProductFacts] = Dictionary(primaryFacts.map { (catKey($0.cat), $0) }, uniquingKeysWith: { a, _ in a })
private let secondaryIndex: [String: SecondaryFacts] = Dictionary(secondaryFacts.map { (catKey($0.cat), $0) }, uniquingKeysWith: { a, _ in a })

func facts(for p: Antibody) -> ProductFacts? {
    let k = catKey(p.cat)
    guard !k.isEmpty else { return nil }
    if let f = primaryIndex[k] { return f }
    if let alias = catAliases[k] { return primaryIndex[catKey(alias)] }
    // otherwise the manufacturer's record from the Antibody Registry, once it has been looked up
    if let r = Registry.shared.record(p.cat) {
        let host = species(r.sourceOrganism.lowercased()) ?? r.sourceOrganism.lowercased()
        guard !host.isEmpty else { return nil }
        return ProductFacts(maker: r.vendorName, cat: r.catalogNum, target: r.abTarget, host: host, clonality: r.clonality.lowercased(),
                            source: "Antibody Registry, RRID \(r.rrid)")
    }
    return nil
}

func facts(for q: Secondary) -> SecondaryFacts? {
    guard let c = q.cat, !catKey(c).isEmpty else { return nil }
    if let f = secondaryIndex[catKey(c)] { return f }
    if let r = Registry.shared.record(c),
       let target = r.abTarget.split(whereSeparator: { !$0.isLetter }).compactMap({ species(String($0).lowercased()) }).first,
       let dye = r.abName.split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }).first(where: { [350, 405, 488, 532, 546, 555, 568, 594, 633, 647, 660, 680, 750].contains($0) }) {
        return SecondaryFacts(maker: r.vendorName, cat: r.catalogNum, raisedIn: r.sourceOrganism.lowercased(), target: target, dye: dye,
                              source: "Antibody Registry, RRID \(r.rrid)")
    }
    return nil
}
