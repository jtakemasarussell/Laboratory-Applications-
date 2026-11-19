import Foundation

// MARK: - Minimal .xlsx writer (no dependencies)

enum Edge: String { case none, thin, medium }

struct CellStyle: Hashable {
    var font = "Calibri"
    var size: Double = 12
    var bold = false
    var italic = false
    var fill: String? = nil          // RRGGBB
    var l = Edge.none, r = Edge.none, t = Edge.none, b = Edge.none
    var h: String? = nil             // left | center | right
    var v: String? = "center"
    var wrap = false
    var numFmt = 0
    var numFmtCode: String? = nil    // custom format, e.g. "[<100]0.0;0"
    var fontColor = "000000"
    var rotate = 0                   // text rotation in degrees (90 = reads upwards)

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
    private var formats: [String] = []      // custom number formats, ids 164, 165, …
    private var cache: [CellStyle: Int] = [:]

    init() {
        fonts.append(fontXML("Calibri", 12, false, "000000"))
        fills.append("<fill><patternFill patternType=\"none\"/></fill>")
        fills.append("<fill><patternFill patternType=\"gray125\"/></fill>")
        borders.append("<border><left/><right/><top/><bottom/><diagonal/></border>")
        xfs.append("<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>")
    }

    private func fontXML(_ name: String, _ size: Double, _ bold: Bool, _ color: String, italic: Bool = false) -> String {
        "<font>" + (bold ? "<b/>" : "") + (italic ? "<i/>" : "") + "<sz val=\"\(numText(size))\"/><color rgb=\"FF\(color)\"/><name val=\"\(xmlEscape(name))\"/><family val=\"2\"/></font>"
    }

    private func index(_ list: inout [String], _ xml: String) -> Int {
        if let i = list.firstIndex(of: xml) { return i }
        list.append(xml)
        return list.count - 1
    }

    func id(_ s: CellStyle) -> Int {
        if let i = cache[s] { return i }
        let f = index(&fonts, fontXML(s.font, s.size, s.bold, s.fontColor, italic: s.italic))
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
        if s.rotate != 0 { align += " textRotation=\"\(s.rotate)\"" }
        align += "/>"
        var fmtID = s.numFmt
        if let code = s.numFmtCode {
            if let i = formats.firstIndex(of: code) { fmtID = 164 + i } else { formats.append(code); fmtID = 163 + formats.count }
        }
        let xf = "<xf numFmtId=\"\(fmtID)\" fontId=\"\(f)\" fillId=\"\(fillID)\" borderId=\"\(b)\" xfId=\"0\" applyNumberFormat=\"1\" applyFont=\"1\" applyFill=\"1\" applyBorder=\"1\" applyAlignment=\"1\">\(align)</xf>"
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
    var charts: [ChartSpec] = []
    /// Pictures shown over the cells (kept from an imported sheet, such as a melt curve's screenshots).
    var pictures: [SheetPicture] = []
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

    func xml(_ styles: StyleBook, drawingRel: String? = nil) -> String {
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
        if let rel = drawingRel { x += "<drawing r:id=\"\(rel)\"/>" }
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

    mutating func add(_ name: String, _ text: String) { add(name, data: Data(text.utf8)) }

    mutating func add(_ name: String, data content: Data) {
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


// MARK: - Charts (native Excel column charts with custom error bars)

/// One bar series. Values, error amounts and the name all point at cells on the sheet, so the chart
/// stays live when the numbers are edited in Excel.
struct SeriesSpec {
    var nameRef: String
    var name: String
    var valRef: String
    var values: [Double?]
    var errRef: String
    var errors: [Double?]
    var fill: String
    var line = "000000"
    var dashed = false
    var lineWidth = 9525                 // EMU; 9525 = 0.75 pt
    var flagged: [Int] = []              // points drawn as warnings (pale red, dashed red outline)
    var inLegend = true
}

/// One column chart: a title, categories, one or more bar series and an optional dashed RQ = 1 line.
struct ChartSpec {
    var title: String
    var catRef: String
    var categories: [String]
    var series: [SeriesSpec]
    var gapWidth = 80
    var overlap = -10
    var refLine = true
    var xTitle = ""
    var yTitle = "RQ"
    // anchor in zero-based sheet columns / rows
    var fromCol = 10, fromRow = 16, toCol = 16, toRow = 32
}

/// Warning colours for a result that rests on too few wells: pale red fill, dark red dashed outline.
let flagFill = "F8C9C4", flagLine = "C00000"

private func chartNum(_ d: Double) -> String { String(d) }

private func numCache(_ values: [Double?]) -> String {
    var x = "<c:numCache><c:formatCode>General</c:formatCode><c:ptCount val=\"\(values.count)\"/>"
    for (i, v) in values.enumerated() {
        if let v = v, v.isFinite { x += "<c:pt idx=\"\(i)\"><c:v>\(chartNum(v))</c:v></c:pt>" }
    }
    return x + "</c:numCache>"
}

private func textProps(_ size: Int, bold: Bool = false, color: String = "404040", rot: Int? = nil) -> String {
    let body = rot.map { "<a:bodyPr rot=\"\($0)\" vert=\"horz\"/>" } ?? "<a:bodyPr/>"
    return "<c:txPr>\(body)<a:lstStyle/><a:p><a:pPr><a:defRPr sz=\"\(size)\" b=\"\(bold ? 1 : 0)\"><a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill><a:latin typeface=\"Calibri\"/></a:defRPr></a:pPr><a:endParaRPr lang=\"en-US\"/></a:p></c:txPr>"
}

private func richTitle(_ text: String, size: Int, bold: Bool, rotated: Bool = false, color: String = "262626") -> String {
    let body = rotated ? "<a:bodyPr rot=\"-5400000\" vert=\"horz\"/>" : "<a:bodyPr/>"
    return "<c:title><c:tx><c:rich>\(body)<a:lstStyle/><a:p><a:pPr><a:defRPr sz=\"\(size)\" b=\"\(bold ? 1 : 0)\"/></a:pPr><a:r><a:rPr lang=\"en-US\" sz=\"\(size)\" b=\"\(bold ? 1 : 0)\"><a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill><a:latin typeface=\"Calibri\"/></a:rPr><a:t>\(xmlEscape(text))</a:t></a:r></a:p></c:rich></c:tx><c:overlay val=\"0\"/></c:title>"
}

private func axisTitle(_ text: String, rotated: Bool) -> String {
    text.trimmingCharacters(in: .whitespaces).isEmpty ? "" : richTitle(text, size: 1000, bold: false, rotated: rotated, color: "404040")
}

private func line(_ hex: String, _ w: Int, dashed: Bool = false) -> String {
    "<a:ln w=\"\(w)\"><a:solidFill><a:srgbClr val=\"\(hex)\"/></a:solidFill>\(dashed ? "<a:prstDash val=\"dash\"/>" : "")</a:ln>"
}

private let errLine = "<c:spPr><a:noFill/>\(line("000000", 9525))</c:spPr>"
private let axisLine = "<c:spPr><a:noFill/>\(line("595959", 9525))</c:spPr>"

func chartXML(_ c: ChartSpec) -> String {
    var cats = "<c:strCache><c:ptCount val=\"\(c.categories.count)\"/>"
    for (i, t) in c.categories.enumerated() { cats += "<c:pt idx=\"\(i)\"><c:v>\(xmlEscape(t))</c:v></c:pt>" }
    cats += "</c:strCache>"
    let catXML = "<c:cat><c:strRef><c:f>\(xmlEscape(c.catRef))</c:f>\(cats)</c:strRef></c:cat>"

    var x = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
    x += "<c:date1904 val=\"0\"/><c:roundedCorners val=\"0\"/><c:chart>"
    x += richTitle(c.title, size: 1300, bold: true) + "<c:autoTitleDeleted val=\"0\"/><c:plotArea><c:layout/>"
    x += "<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/><c:varyColors val=\"0\"/>"
    for (k, s) in c.series.enumerated() {
        let err = "<c:numRef><c:f>\(xmlEscape(s.errRef))</c:f>\(numCache(s.errors))</c:numRef>"
        x += "<c:ser><c:idx val=\"\(k)\"/><c:order val=\"\(k)\"/>"
        x += "<c:tx><c:strRef><c:f>\(xmlEscape(s.nameRef))</c:f><c:strCache><c:ptCount val=\"1\"/><c:pt idx=\"0\"><c:v>\(xmlEscape(s.name))</c:v></c:pt></c:strCache></c:strRef></c:tx>"
        x += "<c:spPr><a:solidFill><a:srgbClr val=\"\(s.fill)\"/></a:solidFill>\(line(s.line, s.lineWidth, dashed: s.dashed))</c:spPr>"
        x += "<c:invertIfNegative val=\"0\"/>"
        for i in s.flagged.sorted() {
            x += "<c:dPt><c:idx val=\"\(i)\"/><c:invertIfNegative val=\"0\"/><c:bubble3D val=\"0\"/><c:spPr><a:solidFill><a:srgbClr val=\"\(flagFill)\"/></a:solidFill>\(line(flagLine, 19050, dashed: true))</c:spPr></c:dPt>"
        }
        x += "<c:errBars><c:errBarType val=\"both\"/><c:errValType val=\"cust\"/><c:noEndCap val=\"0\"/><c:plus>\(err)</c:plus><c:minus>\(err)</c:minus>\(errLine)</c:errBars>"
        x += catXML
        x += "<c:val><c:numRef><c:f>\(xmlEscape(s.valRef))</c:f>\(numCache(s.values))</c:numRef></c:val></c:ser>"
    }
    x += "<c:gapWidth val=\"\(c.gapWidth)\"/><c:overlap val=\"\(c.overlap)\"/><c:axId val=\"111111111\"/><c:axId val=\"222222222\"/></c:barChart>"
    let refIdx = c.series.count
    if c.refLine && !c.categories.isEmpty {
        // RQ = 1 is the calibrator; a dashed grey line makes "up" and "down" easy to read
        var lit = "<c:numLit><c:formatCode>General</c:formatCode><c:ptCount val=\"\(c.categories.count)\"/>"
        for i in c.categories.indices { lit += "<c:pt idx=\"\(i)\"><c:v>1</c:v></c:pt>" }
        lit += "</c:numLit>"
        x += "<c:lineChart><c:grouping val=\"standard\"/><c:varyColors val=\"0\"/>"
        x += "<c:ser><c:idx val=\"\(refIdx)\"/><c:order val=\"\(refIdx)\"/><c:tx><c:v>RQ = 1 (calibrator)</c:v></c:tx>"
        x += "<c:spPr>\(line("8C8C8C", 12700, dashed: true))</c:spPr><c:marker><c:symbol val=\"none\"/></c:marker>"
        x += catXML + "<c:val>\(lit)</c:val><c:smooth val=\"0\"/></c:ser>"
        x += "<c:marker val=\"1\"/><c:axId val=\"111111111\"/><c:axId val=\"222222222\"/></c:lineChart>"
    }
    x += "<c:catAx><c:axId val=\"111111111\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"b\"/>"
    x += axisTitle(c.xTitle, rotated: false)
    x += "<c:numFmt formatCode=\"General\" sourceLinked=\"1\"/><c:majorTickMark val=\"out\"/><c:minorTickMark val=\"none\"/><c:tickLblPos val=\"low\"/>\(axisLine)\(textProps(900))<c:crossAx val=\"222222222\"/><c:crosses val=\"autoZero\"/><c:auto val=\"1\"/><c:lblAlgn val=\"ctr\"/><c:lblOffset val=\"100\"/><c:noMultiLvlLbl val=\"0\"/></c:catAx>"
    x += "<c:valAx><c:axId val=\"222222222\"/><c:scaling><c:orientation val=\"minMax\"/><c:min val=\"0\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"l\"/>"
    x += axisTitle(c.yTitle, rotated: true)
    x += "<c:numFmt formatCode=\"General\" sourceLinked=\"0\"/><c:majorTickMark val=\"out\"/><c:minorTickMark val=\"none\"/><c:tickLblPos val=\"nextTo\"/>\(axisLine)\(textProps(900))<c:crossAx val=\"111111111\"/><c:crosses val=\"autoZero\"/><c:crossBetween val=\"between\"/></c:valAx>"
    x += "<c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr></c:plotArea>"
    // legend at the bottom, only for entries that say something the title does not
    let hidden = c.series.indices.filter { !c.series[$0].inLegend }
    let shown = c.series.count - hidden.count + (c.refLine ? 1 : 0)
    if shown > 0 {
        x += "<c:legend><c:legendPos val=\"b\"/>"
        for i in hidden { x += "<c:legendEntry><c:idx val=\"\(i)\"/><c:delete val=\"1\"/></c:legendEntry>" }
        x += "<c:overlay val=\"0\"/>\(textProps(900))</c:legend>"
    }
    x += "<c:plotVisOnly val=\"1\"/><c:dispBlanksAs val=\"gap\"/></c:chart>"
    x += "<c:spPr><a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill>\(line("D9D9D9", 9525))</c:spPr></c:chartSpace>"
    return x
}

private func pictureXML(_ p: SheetPicture, id: Int, rel: String) -> String {
    let pic = "<xdr:pic><xdr:nvPicPr><xdr:cNvPr id=\"\(id)\" name=\"\(xmlEscape(p.name))\"/><xdr:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></xdr:cNvPicPr></xdr:nvPicPr>"
        + "<xdr:blipFill><a:blip xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" r:embed=\"\(rel)\"/>"
        + (p.crop.map { c in "<a:srcRect" + zip(["l", "t", "r", "b"], c).filter { $0.1 != 0 }.map { " \($0.0)=\"\($0.1)\"" }.joined() + "/>" } ?? "")
        + "<a:stretch><a:fillRect/></a:stretch></xdr:blipFill>"
        + "<xdr:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(p.cx)\" cy=\"\(p.cy)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/>"
    if p.col < 0 {
        return "<xdr:absoluteAnchor><xdr:pos x=\"\(p.colOff)\" y=\"\(p.rowOff)\"/><xdr:ext cx=\"\(p.cx)\" cy=\"\(p.cy)\"/>" + pic + "</xdr:absoluteAnchor>"
    }
    return "<xdr:oneCellAnchor><xdr:from><xdr:col>\(p.col)</xdr:col><xdr:colOff>\(p.colOff)</xdr:colOff><xdr:row>\(p.row)</xdr:row><xdr:rowOff>\(p.rowOff)</xdr:rowOff></xdr:from>"
        + "<xdr:ext cx=\"\(p.cx)\" cy=\"\(p.cy)\"/>" + pic + "</xdr:oneCellAnchor>"
}

private func drawingXML(_ charts: [ChartSpec], _ pictures: [SheetPicture] = []) -> String {
    var x = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<xdr:wsDr xmlns:xdr=\"http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\">"
    for (k, p) in pictures.enumerated() { x += pictureXML(p, id: charts.count + 2 + k, rel: "rId\(charts.count + 1 + k)") }
    for (i, c) in charts.enumerated() {
        x += "<xdr:twoCellAnchor><xdr:from><xdr:col>\(c.fromCol)</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>\(c.fromRow)</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>"
        x += "<xdr:to><xdr:col>\(c.toCol)</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>\(c.toRow)</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>"
        x += "<xdr:graphicFrame macro=\"\"><xdr:nvGraphicFramePr><xdr:cNvPr id=\"\(i + 2)\" name=\"Chart \(i + 1)\"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr>"
        x += "<xdr:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/></xdr:xfrm>"
        x += "<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/chart\"><c:chart xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" r:id=\"rId\(i + 1)\"/></a:graphicData></a:graphic>"
        x += "</xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor>"
    }
    return x + "</xdr:wsDr>"
}

// MARK: - Packaging

/// The file extension a picture is stored under ("jpg" is written "jpeg", unknown kinds as png).
private func Self_mediaExt(_ ext: String) -> String {
    let e = ext.lowercased()
    if e == "jpg" { return "jpeg" }
    return ["png", "jpeg", "gif", "bmp", "tiff", "tif", "emf", "wmf", "svg"].contains(e) ? e : "png"
}

private func mediaContentType(_ ext: String) -> String {
    switch ext {
    case "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "bmp": return "image/bmp"
    case "tiff", "tif": return "image/tiff"
    case "emf": return "image/x-emf"
    case "wmf": return "image/x-wmf"
    case "svg": return "image/svg+xml"
    default: return "image/png"
    }
}

func packageWorkbook(_ sheets: [Sheet]) -> Data {
    let styles = StyleBook()
    let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    let relNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    var types = head + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        + "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        + "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
        + "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
    var wb = head + "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"\(relNS)\"><bookViews><workbookView/></bookViews><sheets>"
    var rels = head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"

    var parts: [(String, String)] = []
    var media: [(String, Data)] = []
    var mediaTypes: Set<String> = []
    var drawingCount = 0, chartCount = 0
    for (i, s) in sheets.enumerated() {
        let n = i + 1
        types += "<Override PartName=\"/xl/worksheets/sheet\(n).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        wb += "<sheet name=\"\(xmlEscape(s.name))\" sheetId=\"\(n)\" r:id=\"rId\(n)\"/>"
        rels += "<Relationship Id=\"rId\(n)\" Type=\"\(relNS)/worksheet\" Target=\"worksheets/sheet\(n).xml\"/>"
        if s.charts.isEmpty && s.pictures.isEmpty {
            parts.append(("xl/worksheets/sheet\(n).xml", s.xml(styles)))
        } else {
            drawingCount += 1
            let d = drawingCount
            parts.append(("xl/worksheets/sheet\(n).xml", s.xml(styles, drawingRel: "rId1")))
            parts.append(("xl/worksheets/_rels/sheet\(n).xml.rels", head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(relNS)/drawing\" Target=\"../drawings/drawing\(d).xml\"/></Relationships>"))
            parts.append(("xl/drawings/drawing\(d).xml", drawingXML(s.charts, s.pictures)))
            types += "<Override PartName=\"/xl/drawings/drawing\(d).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawing+xml\"/>"
            var drels = head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            for (k, c) in s.charts.enumerated() {
                chartCount += 1
                drels += "<Relationship Id=\"rId\(k + 1)\" Type=\"\(relNS)/chart\" Target=\"../charts/chart\(chartCount).xml\"/>"
                parts.append(("xl/charts/chart\(chartCount).xml", chartXML(c)))
                types += "<Override PartName=\"/xl/charts/chart\(chartCount).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>"
            }
            for (k, p) in s.pictures.enumerated() {
                let ext = Self_mediaExt(p.ext)
                let name = "image\(media.count + 1).\(ext)"
                media.append(("xl/media/" + name, p.data))
                mediaTypes.insert(ext)
                drels += "<Relationship Id=\"rId\(s.charts.count + 1 + k)\" Type=\"\(relNS)/image\" Target=\"../media/\(name)\"/>"
            }
            parts.append(("xl/drawings/_rels/drawing\(d).xml.rels", drels + "</Relationships>"))
        }
    }
    for ext in mediaTypes.sorted() { types += "<Default Extension=\"\(ext)\" ContentType=\"\(mediaContentType(ext))\"/>" }
    types += "</Types>"
    wb += "</sheets><calcPr calcId=\"191029\" fullCalcOnLoad=\"1\"/></workbook>"
    rels += "<Relationship Id=\"rId\(sheets.count + 1)\" Type=\"\(relNS)/styles\" Target=\"styles.xml\"/></Relationships>"
    let root = head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(relNS)/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"

    var zip = ZipWriter()
    zip.add("[Content_Types].xml", types)
    zip.add("_rels/.rels", root)
    zip.add("xl/workbook.xml", wb)
    zip.add("xl/_rels/workbook.xml.rels", rels)
    zip.add("xl/styles.xml", styles.xml())
    for (name, text) in parts { zip.add(name, text) }
    for (name, data) in media { zip.add(name, data: data) }
    return zip.finish()
}

/// 'Sheet name'!$A$1 style reference (always quoted, so any sheet name is safe).
func absRef(_ sheet: String, _ row: Int, _ col: Int) -> String {
    "'\(sheet.replacingOccurrences(of: "'", with: "''"))'!$\(colName(col))$\(row)"
}

func absRange(_ sheet: String, _ row1: Int, _ row2: Int, _ col: Int) -> String {
    "'\(sheet.replacingOccurrences(of: "'", with: "''"))'!$\(colName(col))$\(row1):$\(colName(col))$\(row2)"
}
