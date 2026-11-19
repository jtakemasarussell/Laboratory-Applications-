import Foundation
import ImageIO

// MARK: - Reading spreadsheets and exported text tables (no dependencies)

/// One sheet (or one text file) as a grid of text cells. Numbers stay as the text Excel stored.
struct Table {
    var name: String
    var rows: [[String]]
    /// What an .xlsx sheet carries besides its text, so a sheet kept as its own tab looks as it did.
    var layout = SheetLayout()
}

// MARK: - A sheet's look: pictures, colours, fonts, widths, heights, merges

/// A picture on a sheet: pasted over the cells, or placed in a cell. Its file is kept as it came.
struct SheetPicture: Codable, Equatable {
    var data: Data
    var ext: String              // png, jpeg, gif…
    var col: Int, row: Int       // the cell its top-left corner sits in, counted from 0 (-1: placed by position)
    var colOff: Int, rowOff: Int // from that cell's corner (or the sheet's), in EMU
    var cx: Int, cy: Int         // its size on the sheet, in EMU
    var crop: [Int]? = nil       // left, top, right, bottom trimmed off, in thousandths of a percent
    var name = "Picture"
}

/// The parts of a cell's style worth keeping: its fill, and its font's colour, weight, slant and size.
struct CellLook: Codable, Equatable, Hashable {
    var fill: String? = nil
    var font: String? = nil
    var bold = false
    var italic = false
    var size: Double? = nil
}

struct StyledCell: Codable, Equatable { var row: Int; var col: Int; var look: Int }      // row and column from 1
struct ColumnWidth: Codable, Equatable { var min: Int; var max: Int; var width: Double }
struct RowHeight: Codable, Equatable { var row: Int; var height: Double }

struct SheetLayout: Codable, Equatable {
    var pictures: [SheetPicture] = []
    var looks: [CellLook] = []
    var styled: [StyledCell] = []
    var columns: [ColumnWidth] = []
    var rowHeights: [RowHeight] = []
    var merges: [String] = []
    var zoom: Int? = nil
    var isEmpty: Bool { pictures.isEmpty && styled.isEmpty && columns.isEmpty && rowHeights.isEmpty && merges.isEmpty }
}

enum ReadError: LocalizedError {
    case unreadable(String)
    var errorDescription: String? {
        switch self { case .unreadable(let why): return why }
    }
}

/// Reads an .xlsx workbook, or a .csv / .tsv / .txt export, into tables.
func readTables(_ url: URL) throws -> [Table] {
    switch url.pathExtension.lowercased() {
    case "xlsx", "xlsm": return try readXlsx(url)
    case "xls": return [try readXls(url)]
    default: return [try readDelimited(url)]
    }
}

// MARK: xlsx

private func unzipMember(_ archive: URL, _ member: String) -> Data? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    // -p: write the member to stdout. Square brackets are wildcards to unzip, so escape them.
    let escaped = member.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    p.arguments = ["-p", archive.path, escaped]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    do { try p.run() } catch { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return p.terminationStatus == 0 ? data : nil
}

private final class WorkbookParser: NSObject, XMLParserDelegate {
    var sheets: [(name: String, rid: String)] = []
    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if el == "sheet", let n = a["name"], let r = a["r:id"] { sheets.append((n, r)) }
    }
}

private final class RelsParser: NSObject, XMLParserDelegate {
    var targets: [String: String] = [:]
    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if el == "Relationship", let id = a["Id"], let t = a["Target"] { targets[id] = t }
    }
}

private final class StringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = ""
    private var inT = false
    private var phonetic = 0   // <rPh> holds furigana in Japanese workbooks; it is not part of the text
    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if el == "si" { current = "" }
        if el == "rPh" { phonetic += 1 }
        if el == "t" { inT = true }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) {
        if inT && phonetic == 0 { current += s }
    }
    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        if el == "t" { inT = false }
        if el == "rPh" { phonetic -= 1 }
        if el == "si" { strings.append(current) }
    }
}

private func columnIndex(_ cellRef: String) -> Int {
    var n = 0
    for u in cellRef.unicodeScalars {
        guard u.value >= 65, u.value <= 90 else { break }
        n = n * 26 + Int(u.value - 64)
    }
    return max(n, 1)
}

private final class SheetParser: NSObject, XMLParserDelegate {
    let shared: [String]
    var rows: [[String]] = []
    var styleOf: [(row: Int, col: Int, xf: Int)] = []
    var placed: [(row: Int, col: Int, vm: Int)] = []        // pictures placed in a cell
    var columns: [ColumnWidth] = []
    var heights: [RowHeight] = []
    var merges: [String] = []
    var zoom: Int?
    var defaultColWidth = 8.43, defaultRowHeight = 15.0
    private var rowIndex = 0, col = 0
    private var type = ""
    private var text = ""
    private var capturing = false
    private var inlineDepth = 0
    private var phonetic = 0

    init(shared: [String]) { self.shared = shared }

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        switch el {
        case "row":
            rowIndex = Int(a["r"] ?? "") ?? (rowIndex + 1)
            col = 0
            if let h = a["ht"].flatMap(Double.init), rowIndex >= 1, rowIndex <= 20000 { heights.append(RowHeight(row: rowIndex, height: h)) }
        case "c":
            col = a["r"].map(columnIndex) ?? (col + 1)
            type = a["t"] ?? "n"
            text = ""
            if let x = a["s"].flatMap(Int.init), x > 0 { styleOf.append((rowIndex, col, x)) }
            if let v = a["vm"].flatMap(Int.init) { placed.append((rowIndex, col, v)) }
        case "col":
            if let lo = a["min"].flatMap(Int.init), let hi = a["max"].flatMap(Int.init), let w = a["width"].flatMap(Double.init), lo <= 400 {
                columns.append(ColumnWidth(min: lo, max: min(hi, 400), width: w))
            }
        case "mergeCell": if let r = a["ref"] { merges.append(r) }
        case "sheetView": if zoom == nil { zoom = a["zoomScale"].flatMap(Int.init) }
        case "sheetFormatPr":
            if let w = a["defaultColWidth"].flatMap(Double.init) { defaultColWidth = w }
            if let h = a["defaultRowHeight"].flatMap(Double.init) { defaultRowHeight = h }
        case "v": capturing = true
        case "is": inlineDepth += 1
        case "rPh": phonetic += 1
        case "t": if inlineDepth > 0 && phonetic == 0 { capturing = true }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) {
        if capturing { text += s }
    }

    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        switch el {
        case "v", "t": capturing = false
        case "is": inlineDepth -= 1
        case "rPh": phonetic -= 1
        case "c":
            var value = text
            if type == "s" { value = Int(text).flatMap { $0 >= 0 && $0 < shared.count ? shared[$0] : nil } ?? "" }
            if type == "b" { value = text == "1" ? "TRUE" : "FALSE" }
            guard rowIndex >= 1, rowIndex <= 20000, col >= 1, col <= 400 else { return }
            while rows.count < rowIndex { rows.append([]) }
            while rows[rowIndex - 1].count < col { rows[rowIndex - 1].append("") }
            rows[rowIndex - 1][col - 1] = value
        default: break
        }
    }
}

private func parse<T: XMLParserDelegate>(_ data: Data, _ delegate: T) -> T {
    let p = XMLParser(data: data)
    p.delegate = delegate
    p.parse()
    return delegate
}

private func readXlsx(_ url: URL) throws -> [Table] {
    guard let wbData = unzipMember(url, "xl/workbook.xml") else {
        throw ReadError.unreadable("\(url.lastPathComponent) could not be opened as an Excel workbook.")
    }
    let sheets = parse(wbData, WorkbookParser()).sheets
    let rels = unzipMember(url, "xl/_rels/workbook.xml.rels").map { parse($0, RelsParser()).targets } ?? [:]
    let shared = unzipMember(url, "xl/sharedStrings.xml").map { parse($0, StringsParser()).strings } ?? []
    let looks = cellLooks(url)
    let inCell = placedPictures(url)
    var tables: [Table] = []
    for s in sheets {
        guard var target = rels[s.rid] else { continue }
        if target.hasPrefix("/") { target.removeFirst() } else { target = "xl/" + target }
        guard target.contains("worksheets/"), let data = unzipMember(url, target) else { continue }
        let p = parse(data, SheetParser(shared: shared))
        var t = Table(name: s.name, rows: p.rows)
        t.layout = sheetLayout(url, target, p, looks, inCell)
        tables.append(t)
    }
    return tables
}

// MARK: xlsx: the look of a sheet

/// A part's path from a relationship target written relative to `from` (e.g. "../media/image1.png").
private func resolvePart(_ from: String, _ target: String) -> String {
    if target.hasPrefix("/") { return String(target.dropFirst()) }
    var parts = from.split(separator: "/").map(String.init)
    parts.removeLast()
    for piece in target.split(separator: "/").map(String.init) {
        if piece == ".." { if !parts.isEmpty { parts.removeLast() } } else if piece != "." { parts.append(piece) }
    }
    return parts.joined(separator: "/")
}

/// The relationships of a part, from its _rels file: id → (type, resolved path).
private func partRels(_ url: URL, _ part: String) -> [String: (type: String, path: String)] {
    let dir = (part as NSString).deletingLastPathComponent, file = (part as NSString).lastPathComponent
    guard let d = unzipMember(url, dir + "/_rels/" + file + ".rels") else { return [:] }
    var out: [String: (String, String)] = [:]
    for r in parse(d, TypedRelsParser()).rels { out[r.id] = (r.type, resolvePart(part, r.target)) }
    return out
}

private final class TypedRelsParser: NSObject, XMLParserDelegate {
    var rels: [(id: String, type: String, target: String)] = []
    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if el == "Relationship", let id = a["Id"], let t = a["Target"] { rels.append((id, a["Type"] ?? "", t)) }
    }
}

/// Element names without their prefix ("xdr:pic" → "pic").
private func local(_ el: String) -> String { el.split(separator: ":").last.map(String.init) ?? el }

private func sheetLayout(_ url: URL, _ sheetPath: String, _ p: SheetParser, _ looks: [CellLook?], _ inCell: [Int: (data: Data, ext: String)]) -> SheetLayout {
    var L = SheetLayout()
    // cell colours and fonts, kept once per distinct look
    var index: [CellLook: Int] = [:]
    for c in p.styleOf where c.xf < looks.count {
        guard let look = looks[c.xf] else { continue }
        let i = index[look] ?? { L.looks.append(look); index[look] = L.looks.count - 1; return L.looks.count - 1 }()
        L.styled.append(StyledCell(row: c.row, col: c.col, look: i))
    }
    L.columns = p.columns
    L.rowHeights = p.heights
    L.merges = p.merges
    L.zoom = p.zoom
    // pictures pasted over the cells
    for (_, rel) in partRels(url, sheetPath) where rel.type.hasSuffix("/drawing") {
        guard let d = unzipMember(url, rel.path) else { continue }
        let media = partRels(url, rel.path)
        for a in parse(d, DrawingParser()).anchors {
            guard let id = a.embed, let m = media[id], let bytes = unzipMember(url, m.path) else { continue }
            var cx = a.picCx > 0 ? a.picCx : a.extCx, cy = a.picCy > 0 ? a.picCy : a.extCy
            if cx <= 0 || cy <= 0, let px = pixelSize(bytes) { cx = Int(px.width) * 9525; cy = Int(px.height) * 9525 }
            let ext = (m.path as NSString).pathExtension.lowercased()
            if a.kind == "absoluteAnchor" {
                L.pictures.append(SheetPicture(data: bytes, ext: ext, col: -1, row: -1, colOff: a.posX, rowOff: a.posY, cx: cx, cy: cy, crop: a.crop, name: a.name))
            } else {
                L.pictures.append(SheetPicture(data: bytes, ext: ext, col: a.fromCol, row: a.fromRow, colOff: a.fromColOff, rowOff: a.fromRowOff, cx: cx, cy: cy, crop: a.crop, name: a.name))
            }
        }
    }
    // pictures placed in a cell: shown over that cell, fitted inside it
    for c in p.placed {
        guard let pic = inCell[c.vm] else { continue }
        let w = p.columns.first { $0.min <= c.col && $0.max >= c.col }?.width ?? p.defaultColWidth
        let h = p.heights.first { $0.row == c.row }?.height ?? p.defaultRowHeight
        let cellW = Double(Int(w * 7 + 5)) * 9525, cellH = h * 12700
        let px = pixelSize(pic.data) ?? CGSize(width: 1, height: 1)
        let k = min((cellW - 4 * 9525) / Double(px.width), (cellH - 4 * 9525) / Double(px.height))
        let pw = max(1, Double(px.width) * k), ph = max(1, Double(px.height) * k)
        L.pictures.append(SheetPicture(data: pic.data, ext: pic.ext, col: c.col - 1, row: c.row - 1,
                                       colOff: Int((cellW - pw) / 2), rowOff: Int((cellH - ph) / 2), cx: Int(pw), cy: Int(ph), name: "Picture in \(columnName(c.col))\(c.row)"))
    }
    return L
}

private func columnName(_ c: Int) -> String {
    var n = c, s = ""
    while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(65 + r)!) + s; n = (n - 1) / 26 }
    return s
}

private func pixelSize(_ data: Data) -> CGSize? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
          let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
    return CGSize(width: w, height: h)
}

/// One picture's anchor in a drawing part.
private final class DrawingParser: NSObject, XMLParserDelegate {
    struct Anchor {
        var kind = ""
        var fromCol = 0, fromColOff = 0, fromRow = 0, fromRowOff = 0
        var extCx = 0, extCy = 0, posX = 0, posY = 0
        var picCx = 0, picCy = 0
        var embed: String?
        var crop: [Int]?
        var name = "Picture"
        var isPic = false
    }
    var anchors: [Anchor] = []
    private var cur: Anchor?
    private var section = "", field = "", text = ""
    private var inPic = 0

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        let n = local(el)
        switch n {
        case "twoCellAnchor", "oneCellAnchor", "absoluteAnchor": cur = Anchor(kind: n)
        case "from", "to": section = n
        case "col", "colOff", "row", "rowOff": field = n; text = ""
        case "pos": cur?.posX = Int(a["x"] ?? "") ?? 0; cur?.posY = Int(a["y"] ?? "") ?? 0
        case "ext":
            guard let cx = a["cx"].flatMap(Int.init), let cy = a["cy"].flatMap(Int.init) else { break }
            if inPic > 0 { if cur?.picCx == 0 { cur?.picCx = cx; cur?.picCy = cy } } else { cur?.extCx = cx; cur?.extCy = cy }
        case "pic": inPic += 1; cur?.isPic = true
        case "cNvPr": if inPic > 0, let nm = a["name"] { cur?.name = nm }
        case "blip": if inPic > 0, cur?.embed == nil { cur?.embed = a["r:embed"] ?? a.first { $0.key.hasSuffix(":embed") }?.value }
        case "srcRect":
            if inPic > 0 {
                let v = ["l", "t", "r", "b"].map { Int(a[$0] ?? "") ?? 0 }
                if v.contains(where: { $0 != 0 }) { cur?.crop = v }
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) { if !field.isEmpty { text += s } }

    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        let n = local(el)
        switch n {
        case "col", "colOff", "row", "rowOff":
            if section == "from", let v = Int(text.trimmingCharacters(in: .whitespaces)) {
                switch n { case "col": cur?.fromCol = v; case "colOff": cur?.fromColOff = v; case "row": cur?.fromRow = v; default: cur?.fromRowOff = v }
            }
            field = ""
        case "from", "to": section = ""
        case "pic": inPic -= 1
        case "twoCellAnchor", "oneCellAnchor", "absoluteAnchor":
            if let c = cur, c.isPic, c.embed != nil { anchors.append(c) }
            cur = nil
        default: break
        }
    }
}

// MARK: xlsx: cell colours and fonts

/// For each cell style of the workbook, what it looks like (nil: nothing worth keeping).
private func cellLooks(_ url: URL) -> [CellLook?] {
    guard let d = unzipMember(url, "xl/styles.xml") else { return [] }
    let theme = unzipMember(url, "xl/theme/theme1.xml").map { parse($0, ThemeParser()).colors } ?? []
    let st = parse(d, StylesParser())
    func hex(_ c: StylesParser.ColorRef?) -> String? {
        guard let c = c else { return nil }
        if let rgb = c.rgb, rgb.count >= 6 { return String(rgb.suffix(6)).uppercased() }
        if let t = c.theme {
            let order = [1, 0, 3, 2, 4, 5, 6, 7, 8, 9, 10, 11]      // lt1 dk1 lt2 dk2 accent1… as Excel numbers them
            let i = t < order.count ? order[t] : t
            return i < theme.count ? theme[i] : nil
        }
        if let ix = c.indexed, ix < legacyPalette.count { return legacyPalette[ix] }
        return nil
    }
    return st.xfs.map { xf in
        var look = CellLook()
        if xf.fill < st.fills.count, st.fills[xf.fill].solid { look.fill = hex(st.fills[xf.fill].color) }
        if xf.font < st.fonts.count {
            let f = st.fonts[xf.font]
            look.bold = f.bold
            look.italic = f.italic
            if let c = hex(f.color), c != "000000" { look.font = c }
            if let sz = f.size, sz != 11 { look.size = sz }
        }
        return look == CellLook() ? nil : look
    }
}

private final class StylesParser: NSObject, XMLParserDelegate {
    struct ColorRef { var rgb: String?; var theme: Int?; var indexed: Int? }
    struct Font { var bold = false; var italic = false; var size: Double?; var color: ColorRef? }
    struct Fill { var solid = false; var color: ColorRef? }
    var fonts: [Font] = [], fills: [Fill] = [], xfs: [(font: Int, fill: Int)] = []
    private var area = ""
    private var font: Font?, fill: Fill?

    private func color(_ a: [String: String]) -> ColorRef {
        ColorRef(rgb: a["rgb"], theme: a["theme"].flatMap(Int.init), indexed: a["indexed"].flatMap(Int.init))
    }

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        switch el {
        case "fonts", "fills", "cellXfs", "dxfs", "cellStyleXfs": area = el
        case "font": if area == "fonts" { font = Font() }
        case "b": if font != nil { font?.bold = a["val"] != "0" }
        case "i": if font != nil { font?.italic = a["val"] != "0" }
        case "sz": if font != nil { font?.size = a["val"].flatMap(Double.init) }
        case "color": if font != nil { font?.color = color(a) }
        case "fill": if area == "fills" { fill = Fill() }
        case "patternFill": if fill != nil { fill?.solid = a["patternType"] == "solid" }
        case "fgColor": if fill != nil { fill?.color = color(a) }
        case "xf": if area == "cellXfs" { xfs.append((Int(a["fontId"] ?? "") ?? 0, Int(a["fillId"] ?? "") ?? 0)) }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        switch el {
        case "fonts", "fills", "cellXfs", "dxfs", "cellStyleXfs": area = ""
        case "font": if let f = font { fonts.append(f); font = nil }
        case "fill": if let f = fill { fills.append(f); fill = nil }
        default: break
        }
    }
}

/// The theme's colours in file order: dk1, lt1, dk2, lt2, accent1…6, hlink, folHlink.
private final class ThemeParser: NSObject, XMLParserDelegate {
    var colors: [String] = []
    private var inScheme = false, depth = 0
    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        let n = local(el)
        if n == "clrScheme" { inScheme = true; return }
        guard inScheme else { return }
        if n == "srgbClr", let v = a["val"] { colors.append(v.uppercased()) }
        if n == "sysClr" { colors.append((a["lastClr"] ?? "000000").uppercased()) }
    }
    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        if local(el) == "clrScheme" { inScheme = false }
    }
}

/// Excel's original 56 colours, by their old index numbers.
private let legacyPalette: [String] = ["000000", "FFFFFF", "FF0000", "00FF00", "0000FF", "FFFF00", "FF00FF", "00FFFF",
    "000000", "FFFFFF", "FF0000", "00FF00", "0000FF", "FFFF00", "FF00FF", "00FFFF", "800000", "008000", "000080", "808000",
    "800080", "008080", "C0C0C0", "808080", "9999FF", "993366", "FFFFCC", "CCFFFF", "660066", "FF8080", "0066CC", "CCCCFF",
    "000080", "FF00FF", "FFFF00", "00FFFF", "800080", "800000", "008080", "0000FF", "00CCFF", "CCFFFF", "CCFFCC", "FFFF99",
    "99CCFF", "FF99CC", "CC99FF", "FFCC99", "3366FF", "33CCCC", "99CC00", "FFCC00", "FF9900", "FF6600", "666699", "969696",
    "003366", "339966", "003300", "333300", "993300", "993366", "333399", "333333"]

// MARK: xlsx: pictures placed in cells (Excel's "Place in Cell")

/// Each placed picture by the cell metadata number cells point at (vm="1" → the first).
private func placedPictures(_ url: URL) -> [Int: (data: Data, ext: String)] {
    guard let meta = unzipMember(url, "xl/metadata.xml"),
          let rvData = unzipMember(url, "xl/richData/rdrichvalue.xml"),
          let relData = unzipMember(url, "xl/richData/richValueRel.xml") else { return [:] }
    let m = parse(meta, MetadataParser())
    let values = parse(rvData, RichValueParser()).values
    let keys = unzipMember(url, "xl/richData/rdrichvaluestructure.xml").map { parse($0, StructureParser()).structures } ?? []
    let relIDs = parse(relData, RichRelParser()).ids
    let rels = partRels(url, "xl/richData/richValueRel.xml")
    var out: [Int: (Data, String)] = [:]
    for (k, rc) in m.valueRefs.enumerated() {
        guard rc < m.richIndex.count else { continue }
        let rv = m.richIndex[rc]
        guard rv < values.count else { continue }
        let (s, vs) = values[rv]
        // the picture's number is the value under the key _rvRel:LocalImageIdentifier (the first, if unnamed)
        var slot = 0
        if s < keys.count, let i = keys[s].firstIndex(where: { $0.contains("LocalImageIdentifier") }) { slot = i }
        guard slot < vs.count, let ri = Int(vs[slot]), ri < relIDs.count, let r = rels[relIDs[ri]],
              let bytes = unzipMember(url, r.path) else { continue }
        out[k + 1] = (bytes, (r.path as NSString).pathExtension.lowercased())
    }
    return out
}

private final class MetadataParser: NSObject, XMLParserDelegate {
    var valueRefs: [Int] = []     // for each value-metadata block: its record number
    var richIndex: [Int] = []     // for each rich-value block: the rich value it names
    private var area = "", future = ""
    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        let n = local(el)
        switch n {
        case "valueMetadata": area = "value"
        case "futureMetadata": area = "future"; future = a["name"] ?? ""
        case "rc": if area == "value" { valueRefs.append(Int(a["v"] ?? "") ?? 0) }
        case "rvb": if area == "future", future == "XLRICHVALUE" { richIndex.append(Int(a["i"] ?? "") ?? 0) }
        default: break
        }
    }
    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        let n = local(el)
        if n == "valueMetadata" || n == "futureMetadata" { area = "" }
    }
}

private final class RichValueParser: NSObject, XMLParserDelegate {
    var values: [(structure: Int, values: [String])] = []
    private var cur: (Int, [String])?
    private var text = "", inV = false
    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        let n = local(el)
        if n == "rv" { cur = (Int(a["s"] ?? "") ?? 0, []) }
        if n == "v" { inV = true; text = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { if inV { text += s } }
    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        let n = local(el)
        if n == "v" { inV = false; cur?.1.append(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if n == "rv", let c = cur { values.append(c); cur = nil }
    }
}

private final class StructureParser: NSObject, XMLParserDelegate {
    var structures: [[String]] = []
    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        let n = local(el)
        if n == "s" { structures.append([]) }
        if n == "k", !structures.isEmpty { structures[structures.count - 1].append(a["n"] ?? "") }
    }
}

private final class RichRelParser: NSObject, XMLParserDelegate {
    var ids: [String] = []
    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if local(el) == "rel", let id = a["r:id"] ?? a.first(where: { $0.key.hasSuffix(":id") })?.value { ids.append(id) }
    }
}

// MARK: xls (the qTOWER software's own export)

/// The instrument writes a plain stream of old-style Excel records (text cells and number cells),
/// one gene per file. Text is in the Japanese Windows code page.
private func readXls(_ url: URL) throws -> Table {
    guard let d = try? Data(contentsOf: url) else { throw ReadError.unreadable("\(url.lastPathComponent) could not be read.") }
    let b = [UInt8](d)
    if b.count >= 4, b[0] == 0xD0, b[1] == 0xCF, b[2] == 0x11, b[3] == 0xE0 {
        throw ReadError.unreadable("\(url.lastPathComponent) is an Excel 97-2003 workbook saved by Excel itself. Open it in Excel and save it as .xlsx, then import that.")
    }
    guard b.count >= 4, b[0] == 0x09 else {
        throw ReadError.unreadable("\(url.lastPathComponent) is not a qTOWER Excel export.")
    }
    func u16(_ i: Int) -> Int { Int(b[i]) | (Int(b[i + 1]) << 8) }
    func text(_ from: Int, _ count: Int) -> String {
        let bytes = Data(b[from..<min(from + count, b.count)])
        return String(data: bytes, encoding: .shiftJIS) ?? String(data: bytes, encoding: .windowsCP1252) ?? ""
    }
    func number(_ at: Int) -> String {
        var raw: UInt64 = 0
        for k in 0..<8 { raw |= UInt64(b[at + k]) << (8 * UInt64(k)) }
        let v = Double(bitPattern: raw)
        guard v.isFinite else { return "" }
        return v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(v)
    }

    var rows: [[String]] = []
    func put(_ r: Int, _ c: Int, _ value: String) {
        guard r >= 0, r < 20000, c >= 0, c < 400 else { return }
        while rows.count <= r { rows.append([]) }
        while rows[r].count <= c { rows[r].append("") }
        rows[r][c] = value
    }

    var pos = 0
    while pos + 4 <= b.count {
        let id = u16(pos), len = u16(pos + 2)
        let body = pos + 4
        guard body + len <= b.count else { break }
        switch id {
        case 0x0004 where len >= 8:      // text cell: row, column, 3 format bytes, length, characters
            put(u16(body), u16(body + 2), text(body + 8, min(Int(b[body + 7]), len - 8)))
        case 0x0003 where len >= 15:     // number cell: row, column, 3 format bytes, 8-byte value
            put(u16(body), u16(body + 2), number(body + 7))
        case 0x0002 where len >= 9:      // small whole number
            put(u16(body), u16(body + 2), String(u16(body + 7)))
        case 0x0204 where len >= 8:      // later variants of the same two records
            put(u16(body), u16(body + 2), text(body + 8, min(u16(body + 6), len - 8)))
        case 0x0203 where len >= 14:
            put(u16(body), u16(body + 2), number(body + 6))
        default: break
        }
        if id == 0x000A { break }        // end of sheet
        pos = body + len
    }
    guard !rows.isEmpty else { throw ReadError.unreadable("\(url.lastPathComponent) has no cells that could be read.") }
    return Table(name: url.deletingPathExtension().lastPathComponent, rows: rows)
}

// MARK: delimited text

private func splitLine(_ line: String, _ delimiter: Character) -> [String] {
    var out: [String] = []
    var cur = ""
    var quoted = false
    var chars = Array(line)
    if chars.last == "\r" { chars.removeLast() }
    var i = 0
    while i < chars.count {
        let c = chars[i]
        if quoted {
            if c == "\"" {
                if i + 1 < chars.count, chars[i + 1] == "\"" { cur.append("\""); i += 1 } else { quoted = false }
            } else { cur.append(c) }
        } else if c == "\"" {
            quoted = true
        } else if c == delimiter {
            out.append(cur); cur = ""
        } else {
            cur.append(c)
        }
        i += 1
    }
    out.append(cur)
    return out
}

private func readDelimited(_ url: URL) throws -> Table {
    guard let data = try? Data(contentsOf: url) else {
        throw ReadError.unreadable("\(url.lastPathComponent) could not be read.")
    }
    let text = String(data: data, encoding: .utf8)
        ?? String(data: data, encoding: .shiftJIS)
        ?? String(data: data, encoding: .windowsCP1252)
        ?? String(decoding: data, as: UTF8.self)
    let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    // the delimiter is whichever splits the "Well ... Sample name" header line into the most cells
    let header = lines.first { $0.lowercased().contains("sample name") } ?? lines.first ?? ""
    let delimiter = ["\t", ";", ","].map { Character($0) }.max { a, b in
        header.filter { $0 == a }.count < header.filter { $0 == b }.count
    } ?? ","
    let rows = lines.map { splitLine($0, delimiter).map { $0.trimmingCharacters(in: .whitespaces) } }
    return Table(name: url.deletingPathExtension().lastPathComponent, rows: rows)
}
