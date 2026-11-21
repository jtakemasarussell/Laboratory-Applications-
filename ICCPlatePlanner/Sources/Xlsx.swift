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
    /// A custom number format ("0.0#", "yyyy/mm/dd", "\"1:\"#,##0"); overrides numFmt.
    var numFmtCode: String? = nil
    /// Border colour (RRGGBB); nil = automatic (black).
    var lineColor: String? = nil
    var italic = false

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
    private var formats: [String] = []          // custom number formats, ids from 164
    private var cache: [CellStyle: Int] = [:]

    init() {
        fonts.append(fontXML("Calibri", 12, false, "000000"))
        fills.append("<fill><patternFill patternType=\"none\"/></fill>")
        fills.append("<fill><patternFill patternType=\"gray125\"/></fill>")
        borders.append("<border><left/><right/><top/><bottom/><diagonal/></border>")
        xfs.append("<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>")
    }

    private func fontXML(_ name: String, _ size: Double, _ bold: Bool, _ color: String, _ italic: Bool = false) -> String {
        "<font>" + (bold ? "<b/>" : "") + (italic ? "<i/>" : "") + "<sz val=\"\(numText(size))\"/><color rgb=\"FF\(color)\"/><name val=\"\(xmlEscape(name))\"/><family val=\"2\"/></font>"
    }

    private func index(_ list: inout [String], _ xml: String) -> Int {
        if let i = list.firstIndex(of: xml) { return i }
        list.append(xml)
        return list.count - 1
    }

    func id(_ s: CellStyle) -> Int {
        if let i = cache[s] { return i }
        let f = index(&fonts, fontXML(s.font, s.size, s.bold, s.fontColor, s.italic))
        var fillID = 0
        if let c = s.fill {
            fillID = index(&fills, "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"FF\(c)\"/><bgColor indexed=\"64\"/></patternFill></fill>")
        }
        func side(_ tag: String, _ e: Edge) -> String {
            let color = s.lineColor.map { "<color rgb=\"FF\($0)\"/>" } ?? "<color auto=\"1\"/>"
            return e == .none ? "<\(tag)/>" : "<\(tag) style=\"\(e.rawValue)\">\(color)</\(tag)>"
        }
        let b = index(&borders, "<border>" + side("left", s.l) + side("right", s.r) + side("top", s.t) + side("bottom", s.b) + "<diagonal/></border>")
        var align = "<alignment"
        if let h = s.h { align += " horizontal=\"\(h)\"" }
        if let v = s.v { align += " vertical=\"\(v)\"" }
        if s.wrap { align += " wrapText=\"1\"" }
        align += "/>"
        var fmt = s.numFmt
        if let code = s.numFmtCode { fmt = 164 + index(&formats, code) }
        let xf = "<xf numFmtId=\"\(fmt)\" fontId=\"\(f)\" fillId=\"\(fillID)\" borderId=\"\(b)\" xfId=\"0\" applyNumberFormat=\"1\" applyFont=\"1\" applyFill=\"1\" applyBorder=\"1\" applyAlignment=\"1\">\(align)</xf>"
        xfs.append(xf)
        cache[s] = xfs.count - 1
        return xfs.count - 1
    }

    func xml() -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        + (formats.isEmpty ? "" : "<numFmts count=\"\(formats.count)\">" + formats.enumerated().map { "<numFmt numFmtId=\"\(164 + $0.offset)\" formatCode=\"\(xmlEscape($0.element))\"/>" }.joined() + "</numFmts>")
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
    /// Excel's grey cell grid; off for a clean printed look.
    var gridLines = true
    // printing
    var landscape = true
    /// Pages tall when fitting to one page wide (0 = as many as it needs).
    var fitHeight = 1
    var margins = (left: 0.5, right: 0.5, top: 0.75, bottom: 0.75, header: 0.3, footer: 0.3)
    var header: String? = nil
    var footer: String? = nil
    var centered = false
    /// Rows a printed page should end after.
    var pageBreaks: [Int] = []

    /// Merges a block of cells: the value goes in the top-left cell; every cell gets the style, so fills
    /// and borders cover the whole block.
    func merge(_ r1: Int, _ c1: Int, _ r2: Int, _ c2: Int, _ v: CellValue, _ style: CellStyle) {
        for r in r1...r2 { for c in c1...c2 { set(r, c, (r == r1 && c == c1) ? v : .blank, style) } }
        if r1 != r2 || c1 != c2 { merges.append("\(ref(r1, c1)):\(ref(r2, c2))") }
    }
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
        x += "<sheetViews><sheetView\(selected ? " tabSelected=\"1\"" : "") zoomScale=\"\(zoom)\" zoomScaleNormal=\"\(zoom)\"\(gridLines ? "" : " showGridLines=\"0\"") workbookViewId=\"0\"/></sheetViews>"
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
        if centered { x += "<printOptions horizontalCentered=\"1\"/>" }
        let m = margins
        x += "<pageMargins left=\"\(m.left)\" right=\"\(m.right)\" top=\"\(m.top)\" bottom=\"\(m.bottom)\" header=\"\(m.header)\" footer=\"\(m.footer)\"/>"
        x += "<pageSetup paperSize=\"9\" orientation=\"\(landscape ? "landscape" : "portrait")\" fitToHeight=\"\(fitHeight)\" fitToWidth=\"1\"/>"
        if header != nil || footer != nil {
            x += "<headerFooter>"
            if let h = header { x += "<oddHeader>\(xmlEscape(h))</oddHeader>" }
            if let f = footer { x += "<oddFooter>\(xmlEscape(f))</oddFooter>" }
            x += "</headerFooter>"
        }
        if !pageBreaks.isEmpty {
            x += "<rowBreaks count=\"\(pageBreaks.count)\" manualBreakCount=\"\(pageBreaks.count)\">"
                + pageBreaks.map { "<brk id=\"\($0)\" max=\"16383\" man=\"1\"/>" }.joined() + "</rowBreaks>"
        }
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


// MARK: - The workbook
//
// Three sheets, each laid out on an even column grid so every section lines up and prints cleanly:
//   Plan         A4 portrait, fit to the page width: samples, each stain with its antibodies and amounts,
//                the blocking buffer, and the plate map with a legend.
//   Plate map    A4 landscape on one page: the plate large enough to work from at the bench.
//   Observation  A4 landscape: one row per stained well to fill in under the microscope.
// One typeface, navy headings and light rules; the amounts and the NDS are live formulas.

private enum XL {
    static let font = "Calibri"
    static let navy = "1E3A66", mid = "4A78B8", ink = "1F2937", muted = "6B7A90", rule = "D5DDE8", pale = "F2F5FA", line = "AEBACB"
    static let good = "2F8F4E", bad = "C2362B"
    static func text(_ size: Double = 11, bold: Bool = false, color: String = ink, h: String? = "left", wrap: Bool = false) -> CellStyle {
        var c = CellStyle(font: font, size: size, bold: bold, h: h, wrap: wrap)
        c.fontColor = color
        return c
    }
    static func fmt(_ c: CellStyle, _ code: String) -> CellStyle { var x = c; x.numFmtCode = code; return x }
    static func filled(_ c: CellStyle, _ hex: String) -> CellStyle { var x = c; x.fill = hex; return x }
    /// A light rule under the cell.
    static func ruled(_ c: CellStyle) -> CellStyle { var x = c; x.b = .thin; x.lineColor = rule; return x }
    /// A table's heading row: small bold navy on a pale band, ruled underneath.
    static func colHead(_ h: String? = "left") -> CellStyle {
        var c = text(9.5, bold: true, color: navy, h: h)
        c.fill = pale; c.b = .thin; c.lineColor = line
        return c
    }
    /// A section title: small capitals in navy with a navy rule under the whole width.
    static let section: CellStyle = { var c = text(10, bold: true, color: navy); c.b = .medium; c.lineColor = navy; return c }()
    static let date = "yyyy/mm/dd"
    static let dilution = "\"1:\"0"
    static let microlitres = "#,##0.0##\" µL\""
}

private let gridFirst = 2, gridLast = 15         // B … O: the Plan sheet's 14 even columns
private func pageHeader(_ e: Experiment) -> String {
    "&L&\"Calibri,Bold\"&9ICC staining plan  ·  \(e.dateNumber)&R&\"Calibri\"&9\(Brand.department)"
}
private let pageFooter = "&L&\"Calibri\"&8Generated with \(Brand.appName)&R&\"Calibri\"&8Page &P of &N"

/// The stain sets' amounts, worked out as the app does.
private func stainLine(_ set: StainSet) -> String {
    // Japanese keyboards type full-width brackets: "TH（mouse)" is still TH
    let first = set.primaries.map { markerName($0.name.replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")) }
        .filter { !$0.isEmpty }.joined(separator: " + ")
    let second = set.secondaries.map { $0.name.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " + ")
    return [first, second].filter { !$0.isEmpty }.joined(separator: "  →  ")
}

/// The main sheet: everything needed to run the stain, on A4 pages.
func buildPlanSheet(_ e: Experiment, _ st: Settings) -> Sheet {
    let s = Sheet(name: "Plan")
    s.zoom = 100
    s.selected = true
    s.gridLines = false
    s.landscape = false
    s.fitHeight = 0
    s.centered = true
    s.margins = (left: 0.45, right: 0.45, top: 0.7, bottom: 0.65, header: 0.3, footer: 0.3)
    s.header = pageHeader(e)
    s.footer = pageFooter
    s.cols = [(1, 1, 1.5), (2, 2, 7), (3, 14, 7.6), (15, 15, 9), (16, 16, 1.5)]
    var row = 1
    func section(_ title: String) {
        s.heights[row] = 22
        s.merge(row, gridFirst, row, gridLast, .str(title.uppercased()), XL.section)
        row += 1
        s.heights[row] = 6
        row += 1
    }

    // Title band
    s.heights[1] = 40
    let band = XL.filled(XL.text(20, bold: true, color: "FFFFFF"), XL.navy)
    s.merge(1, gridFirst, 1, 10, .str("ICC staining plan"), band)
    s.merge(1, 11, 1, gridLast, .num(excelSerialDate(e.date)), XL.fmt(XL.filled(XL.text(16, bold: true, color: "FFFFFF", h: "right"), XL.navy), XL.date))
    let titles = e.samples.map { $0.title }.filter { !$0.isEmpty }
    let line = titles.joined(separator: "   ·   ")
    // many samples wrap onto more lines rather than running off the page
    s.heights[2] = 22 + 15 * Double(max(0, (line.count - 1) / 95))
    s.merge(2, gridFirst, 2, gridLast, .str(titles.isEmpty ? " " : line),
            XL.filled(XL.text(11, bold: true, color: XL.navy, wrap: true), XL.pale))
    s.heights[3] = 18
    s.merge(3, gridFirst, 3, gridLast, .str("\(Brand.department)  ·  \(Brand.hospital)"), XL.text(9, color: XL.muted))
    row = 5

    // Samples
    section("Samples")
    s.heights[row] = 20
    s.merge(row, 2, row, 3, .str("Code"), XL.colHead())
    s.merge(row, 4, row, 8, .str("Name"), XL.colHead())
    s.merge(row, 9, row, 10, .str("Day 0"), XL.colHead("center"))
    s.merge(row, 11, row, 12, .str("Fixed"), XL.colHead("center"))
    s.merge(row, 13, row, 15, .str("Day"), XL.colHead("center"))
    row += 1
    for smp in e.samples where !smp.title.isEmpty || smp.hasDay0 {
        s.heights[row] = 20
        let cell = XL.ruled(XL.text(11))
        s.merge(row, 2, row, 3, .str(smp.code.trimmingCharacters(in: .whitespaces)), XL.ruled(XL.text(11, bold: true)))
        s.merge(row, 4, row, 8, .str(smp.name.trimmingCharacters(in: .whitespaces)), cell)
        s.merge(row, 9, row, 10, smp.hasDay0 ? .num(excelSerialDate(smp.day0)) : .blank, XL.fmt(XL.ruled(XL.text(11, h: "center")), XL.date))
        s.merge(row, 11, row, 12, e.fixedDate(smp, st).map { .num(excelSerialDate($0)) } ?? .blank, XL.fmt(XL.ruled(XL.text(11, h: "center")), XL.date))
        let day = e.dayText(smp, st)
        s.merge(row, 13, row, 15, plainNumber(day).map { .num($0) } ?? (day.isEmpty ? .blank : .str(day)), XL.ruled(XL.text(11, bold: true, h: "center")))
        row += 1
    }
    row += 1

    // Stains
    section("Stains")
    for (idx, set) in e.sets.enumerated() {
        let vol = e.volume(set, st)
        let report = panel(set)
        let hdr = row
        s.heights[hdr] = 24
        let fill = fillHex(set, idx)
        s.merge(hdr, 2, hdr, 3, .str("Stain \(idx + 1)"), XL.filled(XL.text(11, bold: true, color: isDark(fill) ? "FFFFFF" : XL.ink, h: "center"), fill))
        s.merge(hdr, 4, hdr, 11, .str(stainLine(set)), XL.text(11, bold: true))
        s.merge(hdr, 12, hdr, 13, .num(Double(e.wellCount(set))), XL.fmt(XL.text(10, color: XL.muted, h: "right"), "0\" wells\""))
        s.merge(hdr, 14, hdr, 15, .num(vol), XL.fmt(XL.text(11, bold: true, color: XL.mid, h: "right"), "#,##0.##\" µL\""))
        row += 1
        // primaries
        s.heights[row] = 18
        s.merge(row, 2, row, 5, .str("Primary antibody"), XL.colHead())
        s.merge(row, 6, row, 8, .str("Company"), XL.colHead())
        s.merge(row, 9, row, 10, .str("Cat#"), XL.colHead())
        s.merge(row, 11, row, 12, .str("Dilution"), XL.colHead("center"))
        s.merge(row, 13, row, 15, .str("Amount"), XL.colHead("right"))
        row += 1
        let volRef = ref(hdr, 14)
        for p in set.primaries where !p.name.trimmingCharacters(in: .whitespaces).isEmpty {
            s.heights[row] = 20
            s.merge(row, 2, row, 5, .str(p.name), XL.ruled(XL.text(11, bold: true)))
            s.merge(row, 6, row, 8, .str(p.company), XL.ruled(XL.text(10, color: XL.muted)))
            let catV: CellValue = plainNumber(p.cat).map { .num($0) } ?? (p.cat.trimmingCharacters(in: .whitespaces).isEmpty ? .blank : .str(p.cat))
            s.merge(row, 9, row, 10, catV, XL.ruled(XL.text(10, color: XL.muted)))
            s.merge(row, 11, row, 12, p.dilution > 0 ? .num(p.dilution) : .blank, XL.fmt(XL.ruled(XL.text(11, h: "center")), XL.dilution))
            s.merge(row, 13, row, 15, p.dilution > 0 ? .formula("\(volRef)/\(ref(row, 11))", vol / p.dilution) : .blank,
                    XL.fmt(XL.ruled(XL.text(11, bold: true, h: "right")), XL.microlitres))
            row += 1
        }
        // secondaries
        s.heights[row] = 18
        s.merge(row, 2, row, 10, .str("Secondary / counterstain"), XL.colHead())
        s.merge(row, 11, row, 12, .str("Dilution"), XL.colHead("center"))
        s.merge(row, 13, row, 15, .str("Amount"), XL.colHead("right"))
        row += 1
        for q in set.secondaries where !q.name.trimmingCharacters(in: .whitespaces).isEmpty {
            s.heights[row] = 20
            s.merge(row, 2, row, 10, .str(q.name), XL.ruled(XL.text(11, bold: true)))
            let ok = q.dilution > 0 && q.dilution.isFinite
            s.merge(row, 11, row, 12, ok ? .num(q.dilution) : .blank, XL.fmt(XL.ruled(XL.text(11, h: "center")), XL.dilution))
            s.merge(row, 13, row, 15, ok ? .formula("\(volRef)/\(ref(row, 11))", vol / q.dilution) : .blank,
                    XL.fmt(XL.ruled(XL.text(11, bold: true, h: "right")), XL.microlitres))
            row += 1
        }
        // the compatibility check, in a word
        s.heights[row] = 18
        let verdict: (String, String)
        switch report.verdict {
        case .ok: verdict = ("✓  Every pairing checks out", XL.good)
        case .problem: verdict = ("✗  " + (report.issues.first ?? "A pairing cannot work"), XL.bad)
        case .unknown: verdict = ("?  Some antibodies cannot be checked", XL.muted)
        }
        s.merge(row, 2, row, gridLast, .str(verdict.0), XL.text(9.5, bold: true, color: verdict.1))
        row += 2
    }

    // Blocking buffer
    section("Blocking buffer")
    let mL = e.blocking(st)
    s.heights[row] = 24
    s.merge(row, 2, row, 6, .str("Blocking buffer"), XL.ruled(XL.text(11)))
    s.merge(row, 7, row, 8, .num(mL), XL.fmt(XL.ruled(XL.text(13, bold: true, color: XL.navy, h: "right")), "#,##0.0##\" mL\""))
    s.merge(row, 9, row, 12, .str("NDS (\(fmtNum(st.ndsPerMl)) µL per mL)"), XL.ruled(XL.text(11, h: "right")))
    s.merge(row, 13, row, 15, .formula("\(ref(row, 7))*\(fmtNum(st.ndsPerMl))", mL * st.ndsPerMl),
            XL.fmt(XL.ruled(XL.text(13, bold: true, color: XL.navy, h: "right")), "#,##0.##\" µL\""))
    row += 3

    // Plate map: wells C…N, row letters in B, row labels in O. On longer plans it starts a new page.
    if row > 34 { s.pageBreaks.append(row - 1) }
    section("Plate map")
    let ids = e.sets.map { $0.id }
    s.heights[row] = 26
    for j in 0..<12 { s.setAuto(row, 3 + j, e.topLabels[j], XL.text(7.5, color: XL.muted, h: "center", wrap: true)) }
    row += 1
    s.heights[row] = 16
    for j in 0..<12 { s.set(row, 3 + j, .num(Double(j + 1)), XL.text(9, bold: true, color: XL.muted, h: "center")) }
    row += 1
    for i in 0..<8 {
        s.heights[row] = 30
        s.set(row, 2, .str(rowLetters[i]), XL.text(9, bold: true, color: XL.muted, h: "center"))
        for j in 0..<12 {
            let w = i * 12 + j
            let text = e.label(w)
            var cs = XL.text(text.count <= 5 ? 9 : 7, h: "center", wrap: true)
            cs.lineColor = XL.line
            cs.l = .thin; cs.r = .thin; cs.t = .thin; cs.b = .thin
            if let id = e.wells[w], let k = ids.firstIndex(of: id) {
                let hex = fillHex(e.sets[k], k)
                cs.fill = hex
                if isDark(hex) { cs.fontColor = "FFFFFF" }
            }
            s.setAuto(row, 3 + j, text, cs)
        }
        s.setAuto(row, 15, e.leftLabels[i], XL.text(8, color: XL.muted, wrap: true))
        row += 1
    }
    row += 1
    for (k, set) in e.sets.enumerated() {
        s.heights[row] = 18
        s.set(row, 2, .blank, XL.filled(XL.text(), fillHex(set, k)))
        s.merge(row, 3, row, gridLast, .str("Stain \(k + 1)   \(stainLine(set))   ·   \(e.wellCount(set)) wells"), XL.text(10))
        row += 1
    }
    row += 1
    var small = XL.text(8.5, color: XL.muted); small.italic = true
    s.merge(row, 2, row, gridLast, .str(creditLine), small)
    return s
}

/// The plate on its own landscape page, large enough to work from.
func buildPlateSheet(_ e: Experiment, _ st: Settings) -> Sheet {
    let s = Sheet(name: "Plate map")
    s.zoom = 90
    s.gridLines = false
    s.landscape = true
    s.fitHeight = 1
    s.centered = true
    s.margins = (left: 0.4, right: 0.4, top: 0.6, bottom: 0.55, header: 0.25, footer: 0.25)
    s.header = pageHeader(e)
    s.footer = pageFooter
    s.cols = [(1, 1, 1.5), (2, 2, 4), (3, 14, 11.5), (15, 15, 15), (16, 16, 1.5)]
    let titles = e.samples.map { $0.title }.filter { !$0.isEmpty }
    s.heights[1] = 34
    let band = XL.filled(XL.text(18, bold: true, color: "FFFFFF"), XL.navy)
    s.merge(1, 2, 1, 10, .str("Plate map"), band)
    s.merge(1, 11, 1, 15, .num(excelSerialDate(e.date)), XL.fmt(XL.filled(XL.text(14, bold: true, color: "FFFFFF", h: "right"), XL.navy), XL.date))
    let line = titles.joined(separator: "   ·   ")
    s.heights[2] = 20 + 15 * Double(max(0, (line.count - 1) / 140))
    s.merge(2, 2, 2, 15, .str(titles.isEmpty ? " " : line), XL.filled(XL.text(11, bold: true, color: XL.navy, wrap: true), XL.pale))
    s.heights[3] = 8
    s.heights[4] = 22; s.heights[5] = 18
    for j in 0..<12 {
        s.setAuto(4, 3 + j, e.topLabels[j], XL.text(9, color: XL.muted, h: "center", wrap: true))
        s.set(5, 3 + j, .num(Double(j + 1)), XL.text(11, bold: true, color: XL.muted, h: "center"))
    }
    let ids = e.sets.map { $0.id }
    for i in 0..<8 {
        let row = 6 + i
        s.heights[row] = 44
        s.set(row, 2, .str(rowLetters[i]), XL.text(11, bold: true, color: XL.muted, h: "center"))
        for j in 0..<12 {
            let w = i * 12 + j
            var cs = XL.text(11, h: "center", wrap: true)
            cs.lineColor = XL.line
            cs.l = .thin; cs.r = .thin; cs.t = .thin; cs.b = .thin
            if let id = e.wells[w], let k = ids.firstIndex(of: id) {
                let hex = fillHex(e.sets[k], k)
                cs.fill = hex
                if isDark(hex) { cs.fontColor = "FFFFFF" }
            }
            s.setAuto(row, 3 + j, e.label(w), cs)
        }
        s.setAuto(row, 15, e.leftLabels[i], XL.text(10, color: XL.muted, wrap: true))
    }
    var row = 15
    for (k, set) in e.sets.enumerated() {
        s.heights[row] = 20
        s.set(row, 2, .blank, XL.filled(XL.text(), fillHex(set, k)))
        s.merge(row, 3, row, 15, .str("Stain \(k + 1)   \(stainLine(set))   ·   \(e.wellCount(set)) wells"), XL.text(11))
        row += 1
    }
    return s
}

/// Observation table: one block per stain set, one row per stained well, with marker / DAPI ratio formulas.
func buildObservationSheet(_ e: Experiment) -> Sheet {
    let s = Sheet(name: "Observation")
    s.zoom = 95
    s.gridLines = false
    s.landscape = true
    s.fitHeight = 0
    s.centered = true
    s.margins = (left: 0.4, right: 0.4, top: 0.65, bottom: 0.6, header: 0.25, footer: 0.25)
    s.header = pageHeader(e)
    s.footer = pageFooter
    s.cols = [(1, 3, 6), (4, 4, 14), (5, 5, 16), (6, 6, 16), (7, 7, 2), (8, 12, 10), (13, 17, 10), (18, 18, 2), (19, 24, 11)]
    let headS = XL.colHead("center")
    let cell = XL.ruled(XL.text(10.5, h: "center"))
    let ratio = XL.fmt(XL.ruled(XL.text(10.5, h: "center")), "0.00")
    var row = 2
    for (k, set) in e.sets.enumerated() {
        let wells = (0..<96).filter { e.wells[$0] == set.id }
        if wells.isEmpty { continue }
        let markers = set.primaries.map { markerName($0.name) }.filter { !$0.isEmpty }
        let dapiCol = 13 + markers.count
        let ratioCol = max(19, dapiCol + 2)
        s.heights[row] = 22
        let fill = fillHex(set, k)
        s.merge(row, 1, row, 3, .str("Stain \(k + 1)"), XL.filled(XL.text(11, bold: true, color: isDark(fill) ? "FFFFFF" : XL.ink, h: "center"), fill))
        s.merge(row, 4, row, 12, .str(stainLine(set)), XL.text(11, bold: true))
        row += 2
        s.heights[row] = 20
        for (c, t) in [(1, "Plate"), (2, "Well"), (4, "Cell"), (5, "Condition"), (6, "Staining"), (8, "Findings")] {
            s.set(row, c, .str(t), headS)
        }
        s.set(row, 3, .blank, headS)
        for c in 9...12 { s.set(row, c, .blank, headS) }
        for (m, name) in markers.enumerated() {
            s.set(row, 13 + m, .str(name), headS)
            s.set(row, ratioCol + m, .str(name), headS)
        }
        s.set(row, dapiCol, .str("DAPI"), headS)
        row += 1
        for (n, w) in wells.enumerated() {
            s.heights[row] = 20
            for c in [1, 4, 5, 6, 8, 9, 10, 11, 12] { s.set(row, c, .blank, cell) }
            s.set(row, 2, .str(rowLetters[w / 12]), cell)
            s.set(row, 3, .num(Double(w % 12 + 1)), cell)
            let lbl = e.leftLabels[w / 12].trimmingCharacters(in: .whitespaces)
            if !lbl.isEmpty { s.setAuto(row, 4, lbl, cell) }
            if n == 0 { s.set(row, 6, .str(markers.joined(separator: "/")), cell) }
            for m in markers.indices { s.set(row, 13 + m, .blank, cell) }
            s.set(row, dapiCol, .blank, cell)
            for m in markers.indices {
                s.set(row, ratioCol + m, .formulaError("\(ref(row, 13 + m))/\(ref(row, dapiCol))", "#DIV/0!"), ratio)
            }
            row += 1
        }
        row += 2
    }
    return s
}

/// A date as Excel's serial day number (the cell's number format shows it as a date).
private func excelSerialDate(_ d: Date) -> Double { excelSerial(d) }

func buildWorkbook(_ e: Experiment, _ st: Settings) -> Data {
    packageWorkbook([buildPlanSheet(e, st), buildPlateSheet(e, st), buildObservationSheet(e)])
}
