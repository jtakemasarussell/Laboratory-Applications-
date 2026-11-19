import Foundation

// MARK: - Minimal .xlsx writer (no dependencies)

enum Edge: String { case none, thin, medium }

struct CellStyle: Hashable {
    var font = "Calibri"
    var size: Double = 12
    var bold = false
    var fill: String? = nil          // RRGGBB
    var l = Edge.none, r = Edge.none, t = Edge.none, b = Edge.none
    var h: String? = nil             // left | center | right
    var v: String? = "center"
    var wrap = false
    var numFmt = 0
    var fontColor = "000000"

    func box(_ e: Edge = .thin) -> CellStyle { var s = self; s.l = e; s.r = e; s.t = e; s.b = e; return s }
}

enum CellValue {
    case blank
    case num(Double)
    case str(String)
    case formula(String, Double?)
    case formulaError(String, String)
}

func xmlEscape(_ s: String) -> String {
    var out = ""
    for u in s.unicodeScalars {
        switch u {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        case "\n", "\t": out.unicodeScalars.append(u)
        default: if u.value >= 0x20 && u.value != 0xFFFE && u.value != 0xFFFF { out.unicodeScalars.append(u) }
        }
    }
    return out
}

func colName(_ c: Int) -> String {
    var n = c, s = ""
    while n > 0 {
        let r = (n - 1) % 26
        s = String(UnicodeScalar(UInt8(65 + r))) + s
        n = (n - 1) / 26
    }
    return s
}

func ref(_ row: Int, _ col: Int) -> String { colName(col) + String(row) }

private func numText(_ d: Double) -> String {
    if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
    return String(d)
}

final class StyleBook {
    private var fonts: [String] = [], fills: [String] = [], borders: [String] = [], xfs: [String] = []
    private var cache: [CellStyle: Int] = [:]

    init() {
        fonts.append(fontXML("Calibri", 12, false, "000000"))
        fills.append("<fill><patternFill patternType=\"none\"/></fill>")
        fills.append("<fill><patternFill patternType=\"gray125\"/></fill>")
        borders.append("<border><left/><right/><top/><bottom/><diagonal/></border>")
        xfs.append("<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>")
    }

    private func fontXML(_ name: String, _ size: Double, _ bold: Bool, _ color: String) -> String {
        "<font>" + (bold ? "<b/>" : "") + "<sz val=\"\(numText(size))\"/><color rgb=\"FF\(color)\"/><name val=\"\(xmlEscape(name))\"/><family val=\"2\"/></font>"
    }

    private func index(_ list: inout [String], _ xml: String) -> Int {
        if let i = list.firstIndex(of: xml) { return i }
        list.append(xml)
        return list.count - 1
    }

    func id(_ s: CellStyle) -> Int {
        if let i = cache[s] { return i }
        let f = index(&fonts, fontXML(s.font, s.size, s.bold, s.fontColor))
        var fillID = 0
        if let c = s.fill {
            fillID = index(&fills, "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"FF\(c)\"/><bgColor indexed=\"64\"/></patternFill></fill>")
        }
        func side(_ tag: String, _ e: Edge) -> String {
            e == .none ? "<\(tag)/>" : "<\(tag) style=\"\(e.rawValue)\"><color auto=\"1\"/></\(tag)>"
        }
        let b = index(&borders, "<border>" + side("left", s.l) + side("right", s.r) + side("top", s.t) + side("bottom", s.b) + "<diagonal/></border>")
        var align = "<alignment"
        if let h = s.h { align += " horizontal=\"\(h)\"" }
        if let v = s.v { align += " vertical=\"\(v)\"" }
        if s.wrap { align += " wrapText=\"1\"" }
        align += "/>"
        let xf = "<xf numFmtId=\"\(s.numFmt)\" fontId=\"\(f)\" fillId=\"\(fillID)\" borderId=\"\(b)\" xfId=\"0\" applyNumberFormat=\"1\" applyFont=\"1\" applyFill=\"1\" applyBorder=\"1\" applyAlignment=\"1\">\(align)</xf>"
        xfs.append(xf)
        cache[s] = xfs.count - 1
        return xfs.count - 1
    }

    func xml() -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        + "<fonts count=\"\(fonts.count)\">" + fonts.joined() + "</fonts>"
        + "<fills count=\"\(fills.count)\">" + fills.joined() + "</fills>"
        + "<borders count=\"\(borders.count)\">" + borders.joined() + "</borders>"
        + "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
        + "<cellXfs count=\"\(xfs.count)\">" + xfs.joined() + "</cellXfs>"
        + "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>"
        + "</styleSheet>"
    }
}

final class Sheet {
    let name: String
    var zoom = 100
    var cols: [(Int, Int, Double)] = []
    var heights: [Int: Double] = [:]
    var merges: [String] = []
    var selected = false
    private var cells: [Int: [Int: (CellValue, CellStyle)]] = [:]

    init(name: String) { self.name = name }

    func set(_ row: Int, _ col: Int, _ v: CellValue, _ style: CellStyle = CellStyle()) {
        cells[row, default: [:]][col] = (v, style)
    }

    /// Text that looks like a number is stored as a number (so "100" stays numeric like the template).
    func setAuto(_ row: Int, _ col: Int, _ text: String, _ style: CellStyle) {
        let t = text.trimmingCharacters(in: .whitespaces)
        if let d = plainNumber(t) { set(row, col, .num(d), style) }
        else if t.isEmpty { set(row, col, .blank, style) }
        else { set(row, col, .str(text), style) }
    }

    func xml(_ styles: StyleBook) -> String {
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        x += "<sheetPr><pageSetUpPr fitToPage=\"1\"/></sheetPr>"
        x += "<sheetViews><sheetView\(selected ? " tabSelected=\"1\"" : "") zoomScale=\"\(zoom)\" zoomScaleNormal=\"\(zoom)\" workbookViewId=\"0\"/></sheetViews>"
        x += "<sheetFormatPr baseColWidth=\"10\" defaultColWidth=\"10.6640625\" defaultRowHeight=\"16\"/>"
        if !cols.isEmpty {
            x += "<cols>"
            for (a, b, w) in cols { x += "<col min=\"\(a)\" max=\"\(b)\" width=\"\(w)\" customWidth=\"1\"/>" }
            x += "</cols>"
        }
        x += "<sheetData>"
        let rows = Set(cells.keys).union(heights.keys).sorted()
        for r in rows {
            x += "<row r=\"\(r)\""
            if let h = heights[r] { x += " ht=\"\(h)\" customHeight=\"1\"" }
            x += ">"
            if let rc = cells[r] {
                for c in rc.keys.sorted() {
                    let (v, st) = rc[c]!
                    let head = "<c r=\"\(ref(r, c))\" s=\"\(styles.id(st))\""
                    switch v {
                    case .blank: x += head + "/>"
                    case .num(let d): x += d.isFinite ? head + "><v>\(numText(d))</v></c>" : head + "/>"
                    case .str(let s): x += head + " t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xmlEscape(s))</t></is></c>"
                    case .formula(let f, let cached):
                        x += head + "><f>\(xmlEscape(f))</f>"
                        if let d = cached, d.isFinite { x += "<v>\(numText(d))</v>" }
                        x += "</c>"
                    case .formulaError(let f, let e):
                        x += head + " t=\"e\"><f>\(xmlEscape(f))</f><v>\(xmlEscape(e))</v></c>"
                    }
                }
            }
            x += "</row>"
        }
        x += "</sheetData>"
        if !merges.isEmpty {
            x += "<mergeCells count=\"\(merges.count)\">" + merges.map { "<mergeCell ref=\"\($0)\"/>" }.joined() + "</mergeCells>"
        }
        x += "<pageMargins left=\"0.7\" right=\"0.7\" top=\"0.75\" bottom=\"0.75\" header=\"0.3\" footer=\"0.3\"/>"
        x += "<pageSetup paperSize=\"9\" orientation=\"landscape\" fitToHeight=\"1\" fitToWidth=\"1\"/>"
        x += "</worksheet>"
        return x
    }
}

// MARK: Zip container (stored entries)

struct ZipWriter {
    private var body = Data()
    private var central = Data()
    private var count: UInt16 = 0

    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in d { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    private static func le16(_ d: inout Data, _ v: UInt16) { d.append(UInt8(v & 0xFF)); d.append(UInt8(v >> 8)) }
    private static func le32(_ d: inout Data, _ v: UInt32) {
        for i in 0..<4 { d.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) }
    }

    mutating func add(_ name: String, _ text: String) {
        let content = Data(text.utf8)
        let n = Data(name.utf8)
        let crc = Self.crc32(content)
        let offset = UInt32(body.count)
        let size = UInt32(content.count)

        Self.le32(&body, 0x0403_4b50)
        Self.le16(&body, 20); Self.le16(&body, 0); Self.le16(&body, 0)
        Self.le16(&body, 0); Self.le16(&body, 0x0021)
        Self.le32(&body, crc); Self.le32(&body, size); Self.le32(&body, size)
        Self.le16(&body, UInt16(n.count)); Self.le16(&body, 0)
        body.append(n); body.append(content)

        Self.le32(&central, 0x0201_4b50)
        Self.le16(&central, 20); Self.le16(&central, 20); Self.le16(&central, 0); Self.le16(&central, 0)
        Self.le16(&central, 0); Self.le16(&central, 0x0021)
        Self.le32(&central, crc); Self.le32(&central, size); Self.le32(&central, size)
        Self.le16(&central, UInt16(n.count)); Self.le16(&central, 0); Self.le16(&central, 0)
        Self.le16(&central, 0); Self.le16(&central, 0); Self.le32(&central, 0)
        Self.le32(&central, offset)
        central.append(n)
        count += 1
    }

    func finish() -> Data {
        var out = body
        out.append(central)
        Self.le32(&out, 0x0605_4b50)
        Self.le16(&out, 0); Self.le16(&out, 0)
        Self.le16(&out, count); Self.le16(&out, count)
        Self.le32(&out, UInt32(central.count)); Self.le32(&out, UInt32(body.count))
        Self.le16(&out, 0)
        return out
    }
}

func packageWorkbook(_ sheets: [Sheet]) -> Data {
    let styles = StyleBook()
    let sheetXML = sheets.map { $0.xml(styles) }
    let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

    var types = head + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        + "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        + "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
        + "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
    var wb = head + "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><bookViews><workbookView/></bookViews><sheets>"
    var rels = head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
    for (i, s) in sheets.enumerated() {
        let n = i + 1
        types += "<Override PartName=\"/xl/worksheets/sheet\(n).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        wb += "<sheet name=\"\(xmlEscape(s.name))\" sheetId=\"\(n)\" r:id=\"rId\(n)\"/>"
        rels += "<Relationship Id=\"rId\(n)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(n).xml\"/>"
    }
    types += "</Types>"
    wb += "</sheets><calcPr calcId=\"191029\" fullCalcOnLoad=\"1\"/></workbook>"
    rels += "<Relationship Id=\"rId\(sheets.count + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
    let root = head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"

    var zip = ZipWriter()
    zip.add("[Content_Types].xml", types)
    zip.add("_rels/.rels", root)
    zip.add("xl/workbook.xml", wb)
    zip.add("xl/_rels/workbook.xml.rels", rels)
    zip.add("xl/styles.xml", styles.xml())
    for (i, x) in sheetXML.enumerated() { zip.add("xl/worksheets/sheet\(i + 1).xml", x) }
    return zip.finish()
}

// MARK: - Lab workbook layout

private let brandLine = "\(Brand.department) · \(Brand.hospital)"
private let creditLine = "Generated with \(Brand.appName) — created by \(Brand.author)"

private func excelSerial(_ d: Date) -> Double {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let d0 = utc.date(from: DateComponents(year: 1899, month: 12, day: 30))!
    let d1 = utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day))!
    return (d1.timeIntervalSince(d0) / 86400).rounded()
}

private let plateTop = 6      // sheet row of plate row A
private let plateLeft = 14    // column N = plate column 1

/// The Staining sheet (染色 in the original template): same cell positions, fonts, borders and formulas as the hand-made template.
func buildStainSheet(_ e: Experiment, _ st: Settings) -> Sheet {
    let s = Sheet(name: "Staining")
    s.zoom = 84
    s.selected = true
    s.cols = [(1, 1, 17.5), (2, 2, 24.6640625), (3, 3, 17.1640625), (4, 4, 18.33203125), (5, 5, 12.1640625),
              (6, 6, 15.6640625), (7, 7, 22.5), (8, 8, 9.5), (9, 9, 11.33203125), (10, 10, 15.33203125),
              (11, 13, 11.33203125), (14, 25, 4.6640625), (26, 26, 5.33203125), (27, 27, 5.6640625)]
    s.heights = [1: 26, 2: 30, 3: 36, 4: 40, 16: 31.25, 31: 24, 35: 31.25, 36: 31.25, 37: 31.25, 38: 30, 39: 30, 40: 28.25]
    for r in 5...15 { s.heights[r] = 34.25 }
    for r in 17...28 { s.heights[r] = 41 }
    for r in 32...34 { s.heights[r] = 34.25 }

    let cal = CellStyle(font: "Calibri")
    let arial16 = CellStyle(font: "Arial", size: 16)
    let arial18 = CellStyle(font: "Arial", size: 18)

    // Header
    s.set(1, 1, .num(Double(e.dateNumber)), CellStyle(size: 16))
    s.set(1, 2, .str("Sample(s)"), CellStyle(size: 16, h: "center"))
    let titles = e.samples.map { $0.title }.filter { !$0.isEmpty }
    for (i, t) in titles.prefix(3).enumerated() {
        let text = (i == 2 && titles.count > 3) ? titles[2...].joined(separator: ", ") : t
        s.set(1 + i, 3, .str(text), CellStyle(size: 20, h: "left", v: i == 0 ? "center" : nil))
    }
    s.set(3, 1, .str("Preparation"), CellStyle(size: 18, h: "left", v: nil))

    // Antibody table header
    var th = arial16.box(); th.b = .none
    s.set(4, 2, .str("Antibodies"), th)
    var thWrap = th; thWrap.wrap = true
    s.set(4, 3, .str("Company"), thWrap)
    s.set(4, 4, .str("Cat#"), thWrap)
    s.set(4, 5, .str("Dilution"), th)
    var g4 = arial16; g4.h = "left"
    s.set(4, 7, .str("1st Antibody"), g4)
    s.set(4, 10, .str("2nd Antibody"), arial16)

    // Stain sets
    var r = 5
    for (idx, set) in e.sets.enumerated() {
        let hdr = r
        let vol = e.volume(set, st)
        var left18 = arial18; left18.h = "left"
        s.set(hdr, 7, .num(Double(e.wellCount(set))), left18)
        s.set(hdr, 8, .num(vol), arial18)
        s.set(hdr, 9, .str("μL"), arial18)
        s.set(hdr, 11, .num(vol), arial18)
        s.set(hdr, 12, .str("μL"), arial18)

        let n = max(set.primaries.count, set.secondaries.count, 1)
        for k in 0..<n {
            let row = hdr + 1 + k
            s.heights[row] = 34.25
            if k == 0 { s.set(row, 1, .blank, CellStyle(font: "Arial", size: 16, fill: fillHex(set, idx), h: "left")) }

            var bName = arial18.box(); bName.h = "left"
            var bComp = arial18.box(); bComp.wrap = true
            var bCat = arial18.box(); bCat.h = "left"; bCat.wrap = true
            var bDil = arial18.box(); bDil.h = "center"
            let bPlain = arial18.box()
            var bRight = arial18.box(); bRight.h = "right"

            if k < set.primaries.count {
                let p = set.primaries[k]
                s.set(row, 2, .str(p.name), bName)
                s.set(row, 3, .str(p.company), bComp)
                s.setAuto(row, 4, p.cat, bCat)
                s.set(row, 5, p.dilution > 0 ? .num(p.dilution) : .blank, bDil)   // blank until a dilution is entered
                s.set(row, 7, .str(p.name), bPlain)
                s.set(row, 8, .formula("\(ref(hdr, 8))/\(ref(row, 5))", p.dilution > 0 ? vol / p.dilution : nil), bPlain)
            } else {
                s.set(row, 2, .blank, bName); s.set(row, 3, .blank, bComp); s.set(row, 4, .blank, bCat)
                s.set(row, 5, .blank, bDil); s.set(row, 7, .blank, bPlain); s.set(row, 8, .blank, bPlain)
            }
            if k < set.primaries.count { s.set(row, 9, .str("μL"), arial18) }   // unit only beside a real amount

            if k < set.secondaries.count {
                let q = set.secondaries[k]
                s.set(row, 10, .str(q.name), bDil)
                if q.dilution > 0, q.dilution.isFinite {
                    s.set(row, 11, .formula("\(ref(hdr, 11))/\(fmtNum(q.dilution))", vol / q.dilution), bRight)
                } else {
                    s.set(row, 11, .blank, bRight)   // no dilution entered yet
                }
            } else {
                s.set(row, 10, .blank, bDil); s.set(row, 11, .blank, bRight)
            }
            if k < set.secondaries.count { s.set(row, 12, .str("μL"), arial18) }
        }
        r = hdr + n + 2
    }

    // Plate map, N6:Y13
    let ids = e.sets.map { $0.id }
    func stained(_ i: Int, _ j: Int) -> Bool {
        guard (0..<8).contains(i), (0..<12).contains(j), let id = e.wells[i * 12 + j] else { return false }
        return ids.contains(id)
    }
    for j in 0..<12 where !e.topLabels[j].trimmingCharacters(in: .whitespaces).isEmpty {
        s.setAuto(4, plateLeft + j, e.topLabels[j], cal)
    }
    for i in 0..<8 {
        if !e.leftLabels[i].trimmingCharacters(in: .whitespaces).isEmpty {
            s.setAuto(plateTop + i, 13, e.leftLabels[i], CellStyle(h: "center"))
        }
        for j in 0..<12 {
            let w = i * 12 + j
            let text = e.label(w)
            let isNumber = plainNumber(text) != nil
            // numbers and short tags such as "#381" are readable at 11 pt; longer notes shrink to fit the narrow well
            let short = text.trimmingCharacters(in: .whitespaces).count <= 5
            var cs = CellStyle(size: (isNumber || short) ? 11 : 8, h: "center", wrap: !short)
            // thick line around the plate and around each block of stained wells, as in the template
            let me = stained(i, j)
            cs.l = (j == 0 || stained(i, j - 1) != me) ? .medium : .thin
            cs.r = (j == 11 || stained(i, j + 1) != me) ? .medium : .thin
            cs.t = (i == 0 || stained(i - 1, j) != me) ? .medium : .thin
            cs.b = (i == 7 || stained(i + 1, j) != me) ? .medium : .thin
            if let id = e.wells[w], let k = ids.firstIndex(of: id) {
                let hex = fillHex(e.sets[k], k)
                cs.fill = hex
                if isDark(hex) { cs.fontColor = "FFFFFF" }
            }
            s.setAuto(plateTop + i, plateLeft + j, text, cs)
        }
    }

    // Sample list, Day 0, blocking buffer
    let sampleRow = max(17, r)
    for (i, t) in titles.enumerated() {
        s.heights[sampleRow + i] = 41
        s.set(sampleRow + i, 2, .str(t), CellStyle(size: 20, h: "left", v: i == 0 ? "center" : nil))
    }
    // Day 0 / Day. One shared pair of rows (the template layout) when every experiment has the
    // same values; otherwise one row per experiment.
    let day0Row = max(21, sampleRow + titles.count + 1)
    let dated = e.samples.filter { !$0.title.isEmpty || $0.hasDay0 || !e.dayText($0, st).isEmpty }
    let dateStyle = CellStyle(size: 18, h: "center", numFmt: 14)
    let label18 = CellStyle(font: "Arial", size: 18, h: "center")
    let cal18 = CellStyle(size: 18, h: "center")
    func serial(_ d: Date?) -> CellValue { d.map { .num(excelSerial($0)) } ?? .blank }
    func sameDays(_ a: Sample, _ b: Sample) -> Bool {
        a.hasDay0 == b.hasDay0 && e.dayText(a, st) == e.dayText(b, st)
            && (!a.hasDay0 || excelSerial(a.day0) == excelSerial(b.day0))
            && e.fixedDate(a, st).map(excelSerial) == e.fixedDate(b, st).map(excelSerial)
    }
    var lastDayRow = day0Row + 2
    if dated.isEmpty || dated.count == 1 || dated.allSatisfy({ sameDays($0, dated[0]) }) {
        // the template's layout, plus the date the cells were fixed on the row below
        let first = dated.first
        for r in 0..<3 { s.heights[day0Row + r] = 41 }
        s.set(day0Row, 2, .str("Day 0 ="), label18)
        s.set(day0Row, 3, (first?.hasDay0 ?? false) ? serial(first?.day0) : .blank, dateStyle)
        s.set(day0Row + 1, 2, .str("Day"), cal18)
        s.setAuto(day0Row + 1, 3, first.map { e.dayText($0, st) } ?? "", cal18)
        s.set(day0Row + 2, 2, .str("Date fixed ="), label18)
        s.set(day0Row + 2, 3, serial(first.flatMap { e.fixedDate($0, st) }), dateStyle)
    } else {
        for (i, smp) in dated.enumerated() {
            let row = day0Row + i
            s.heights[row] = 41
            s.set(row, 2, .str(smp.tag.isEmpty ? "Day 0 =" : "\(smp.tag)  Day 0 ="), label18)
            s.set(row, 3, smp.hasDay0 ? serial(smp.day0) : .blank, dateStyle)
            s.set(row, 4, .str("Day"), cal18)
            s.setAuto(row, 5, e.dayText(smp, st), cal18)
            s.set(row, 6, .str("Fixed"), cal18)
            s.set(row, 7, serial(e.fixedDate(smp, st)), dateStyle)
            lastDayRow = max(lastDayRow, row)
        }
    }

    let blockRow = max(31, lastDayRow + 3)
    s.heights[blockRow] = 24; s.heights[blockRow + 1] = 34.25
    let bb = CellStyle(size: 18, h: "center").box()
    let mL = e.blocking(st)
    s.set(blockRow, 2, .str("Blocking Buffer (mL)"), bb)
    s.set(blockRow, 3, .str("NDS (μL)"), bb)
    s.set(blockRow + 1, 2, .num(mL), bb)
    s.set(blockRow + 1, 3, .formula("\(ref(blockRow + 1, 2))*\(fmtNum(st.ndsPerMl))", mL * st.ndsPerMl), bb)

    // Department and credit, below everything the template uses
    s.heights[blockRow + 3] = 20; s.heights[blockRow + 4] = 20
    s.set(blockRow + 3, 2, .str(brandLine), CellStyle(size: 11, h: "left"))
    s.set(blockRow + 4, 2, .str(creditLine), CellStyle(size: 11, h: "left"))
    return s
}

/// A large, printable copy of the plate map with row letters, column numbers and a stain legend.
func buildPlateSheet(_ e: Experiment, _ st: Settings) -> Sheet {
    let s = Sheet(name: "Plate layout")
    s.zoom = 90
    s.cols = [(1, 1, 16), (2, 2, 5), (3, 14, 12)]
    let titles = e.samples.map { $0.title }.filter { !$0.isEmpty }
    s.heights[1] = 30
    s.set(1, 1, .str(([String(e.dateNumber)] + titles).joined(separator: "   ")), CellStyle(size: 18, bold: true, h: "left"))
    s.heights[2] = 30; s.heights[3] = 24
    for j in 0..<12 {
        s.setAuto(2, 3 + j, e.topLabels[j], CellStyle(size: 12, h: "left"))
        s.set(3, 3 + j, .num(Double(j + 1)), CellStyle(size: 12, bold: true, h: "center"))
    }
    let ids = e.sets.map { $0.id }
    for i in 0..<8 {
        let row = 4 + i
        s.heights[row] = 54
        s.setAuto(row, 1, e.leftLabels[i], CellStyle(size: 12, h: "center", wrap: true))
        s.set(row, 2, .str(rowLetters[i]), CellStyle(size: 12, bold: true, h: "center"))
        for j in 0..<12 {
            let w = i * 12 + j
            var cs = CellStyle(size: 12, h: "center", wrap: true)
            cs.l = j == 0 ? .medium : .thin
            cs.r = j == 11 ? .medium : .thin
            cs.t = i == 0 ? .medium : .thin
            cs.b = i == 7 ? .medium : .thin
            if let id = e.wells[w], let k = ids.firstIndex(of: id) {
                let hex = fillHex(e.sets[k], k)
                cs.fill = hex
                if isDark(hex) { cs.fontColor = "FFFFFF" }
            }
            s.setAuto(row, 3 + j, e.label(w), cs)
        }
    }
    var row = 13
    for (k, set) in e.sets.enumerated() {
        s.heights[row] = 26
        s.set(row, 2, .blank, CellStyle(fill: fillHex(set, k)).box())
        let first = set.primaries.map { $0.name.trimmingCharacters(in: .whitespaces) }.joined(separator: " + ")
        let second = set.secondaries.map { $0.name.trimmingCharacters(in: .whitespaces) }.joined(separator: " + ")
        s.set(row, 3, .str("Stain \(k + 1):  \(first)   →   \(second)   (\(e.wellCount(set)) wells)"), CellStyle(size: 14, h: "left"))
        row += 1
    }
    row += 1
    s.set(row, 3, .str(brandLine), CellStyle(size: 11, h: "left"))
    s.set(row + 1, 3, .str(creditLine), CellStyle(size: 11, h: "left"))
    return s
}

/// Observation table: one block per stain set, one row per stained well, with marker / DAPI ratio formulas.
func buildObservationSheet(_ e: Experiment) -> Sheet {
    let s = Sheet(name: "Observation")
    s.zoom = 95
    s.cols = [(5, 5, 15.6640625), (10, 10, 19.33203125), (11, 11, 22), (13, 13, 13.33203125),
              (18, 18, 14.5), (19, 19, 13), (20, 20, 15.33203125), (21, 21, 14.6640625)]
    let base = CellStyle()
    var row = 4
    for set in e.sets {
        let wells = (0..<96).filter { e.wells[$0] == set.id }
        if wells.isEmpty { continue }
        let markers = set.primaries.map { markerName($0.name) }.filter { !$0.isEmpty }
        let dapiCol = 13 + markers.count
        let ratioCol = max(19, dapiCol + 2)

        s.heights[row] = 30
        s.set(row, 1, .str("Plate"), base)
        s.set(row, 2, .str("Well"), base)
        s.set(row, 4, .str("Cell"), base)
        s.set(row, 5, .str("Condition"), base)
        s.set(row, 6, .str("Staining"), base)
        s.set(row, 8, .str("Findings"), base)
        for (m, name) in markers.enumerated() {
            s.set(row, 13 + m, .str(name), base)
            s.set(row, ratioCol + m, .str(name), base)
        }
        s.set(row, dapiCol, .str("DAPI"), base)
        row += 1
        for (n, w) in wells.enumerated() {
            s.heights[row] = 30
            s.set(row, 2, .str(rowLetters[w / 12]), base)
            s.set(row, 3, .num(Double(w % 12 + 1)), base)
            let cell = e.leftLabels[w / 12].trimmingCharacters(in: .whitespaces)
            if !cell.isEmpty { s.setAuto(row, 4, cell, base) }
            if n == 0 { s.set(row, 6, .str(markers.joined(separator: "/")), base) }
            for m in markers.indices {
                s.set(row, ratioCol + m, .formulaError("\(ref(row, 13 + m))/\(ref(row, dapiCol))", "#DIV/0!"), base)
            }
            row += 1
        }
        row += 2
    }
    return s
}

func buildWorkbook(_ e: Experiment, _ st: Settings) -> Data {
    packageWorkbook([buildStainSheet(e, st), buildPlateSheet(e, st), buildObservationSheet(e)])
}
