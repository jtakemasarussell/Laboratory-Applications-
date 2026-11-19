import SwiftUI
import AppKit
import QuartzCore

// MARK: - Export: a confocal microscope acquires the plate
//
// After the workbook is saved, a window shows the plate on a microscope stage: the objective snakes
// across the stained wells, each one lights up in its dyes as it is acquired, and a scope beside it
// plays the confocal scan for the stain under the lens (laser line, channel by channel, then the merge).
// When the last well is done the window says where the file is, with Open in Excel and Show in Finder;
// with "Open in Excel after saving" on, Excel opens then rather than over the top of the animation.
// Everything is drawn once; the shared 20-frames-a-second clock only moves and fades the pictures.

struct ScanWell {
    var index: Int
    var setIndex: Int
    var fill: String
    var glow: String          // the brightest dye of its stain, or its stain colour
}

final class ExportRun: ObservableObject {
    @Published var done = false
    let url: URL
    let total: Int
    init(url: URL, total: Int) { self.url = url; self.total = total }
}

/// Opens, runs and closes the acquisition window.
final class ExportScanController: NSObject, NSWindowDelegate {
    static let shared = ExportScanController()
    private var window: NSWindow?
    private var scan: ExportScanView?
    private var run: ExportRun?
    private var finished: (() -> Void)?
    private var autoOpen = false
    private var keyMonitor: Any?

    /// Shows the scan for `store`'s plate; `finished` runs once (the confetti), when the scan ends.
    func present(_ store: Store, url: URL, finished: @escaping () -> Void) {
        close()
        let sets = store.exp.sets
        let ids = sets.map { $0.id }
        var wells: [ScanWell] = []
        for w in 0..<96 {
            guard let id = store.exp.wells[w], let k = ids.firstIndex(of: id) else { continue }
            let dyes = panelReport(sets[k]).channels.filter { !$0.fluor.counterstain }.map { $0.fluor.hex }
            wells.append(ScanWell(index: w, setIndex: k, fill: fillHex(sets[k], k), glow: mergeHex(dyes) ?? fillHex(sets[k], k)))
        }
        // the order the stage moves in: row by row, snaking
        wells.sort { a, b in
            let ra = a.index / 12, rb = b.index / 12
            if ra != rb { return ra < rb }
            return ra % 2 == 0 ? a.index % 12 < b.index % 12 : a.index % 12 > b.index % 12
        }
        let infos = sets.indices.map { store.previewInfo(for: $0) }
        let r = ExportRun(url: url, total: wells.count)
        run = r
        self.finished = finished
        autoOpen = store.openAfterExport
        let size = NSSize(width: 860, height: 520)
        let parent = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible }
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.backgroundColor = NSColor(hex: "06101F")
        win.isReleasedWhenClosed = false
        win.delegate = self
        let v = ExportScanView(frame: NSRect(origin: .zero, size: size))
        v.configure(wells: wells, infos: infos, setTitles: sets.indices.map { "Stain \($0 + 1)" }, file: url.lastPathComponent,
                    motion: store.motion) { [weak self] in self?.complete() }
        scan = v
        let host = NSHostingView(rootView: ExportScanChrome(run: r,
                                                            open: { [weak self] in self?.openFile() },
                                                            reveal: { [weak self] in self?.revealFile() },
                                                            dismiss: { [weak self] in self?.close() },
                                                            skip: { [weak self] in self?.scan?.skip() }))
        host.frame = v.bounds
        host.autoresizingMask = [.width, .height]
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        v.autoresizingMask = [.width, .height]
        root.addSubview(v)
        v.scope.autoresizingMask = [.minXMargin, .maxYMargin]
        root.addSubview(v.scope)
        root.addSubview(host)
        win.contentView = root
        if let p = parent {
            let f = p.frame
            win.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2))
            p.addChildWindow(win, ordered: .above)
        } else {
            win.center()
        }
        win.makeKeyAndOrderFront(nil)
        window = win
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.window else { return e }
            if e.keyCode == 53 {                     // Esc: skip, then close
                if self.run?.done == true { self.close() } else { self.scan?.skip() }
                return nil
            }
            if e.keyCode == 36, self.run?.done == true { self.openFile(); return nil }   // Return
            return e
        }
        v.start()
    }

    private func complete() {
        guard let r = run, !r.done else { return }
        r.done = true
        finished?(); finished = nil
        if autoOpen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                guard let self, self.run === r, self.window != nil else { return }
                self.openFile()
            }
        }
    }

    private func openFile() {
        guard let url = run?.url else { return }
        NSWorkspace.shared.open(url)
        close()
    }

    private func revealFile() {
        guard let url = run?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func close() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let r = run, !r.done { scan?.skip() }       // the confetti still flies
        scan?.stop()
        if let w = window {
            w.parent?.removeChildWindow(w)
            w.delegate = nil
            w.orderOut(nil)
        }
        window = nil; scan = nil; run = nil
    }

    func windowWillClose(_ notification: Notification) {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let r = run, !r.done { scan?.skip() }
        scan?.stop()
        window = nil; scan = nil; run = nil
    }
}

/// The words and buttons over the scene: a Skip link while it runs, the result and buttons at the end.
struct ExportScanChrome: View {
    @ObservedObject var run: ExportRun
    let open: () -> Void, reveal: () -> Void, dismiss: () -> Void, skip: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                if run.done {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 18)).foregroundColor(Color(hex: "8CF5A4"))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Plate acquired · workbook saved").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                        Text(run.url.lastPathComponent).font(.system(size: 11, design: .monospaced)).foregroundColor(Color(hex: "9FB7D6"))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Button("Show in Finder", action: reveal)
                    Button("Done", action: dismiss).keyboardShortcut(.cancelAction)
                    Button("Open in Excel", action: open).keyboardShortcut(.defaultAction)
                } else {
                    Spacer()
                    Button(action: skip) {
                        Text("Skip").font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "9FB7D6"))
                    }
                    .buttonStyle(.plain)
                    .help("Skip to the end (Esc)")
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
            .background(run.done ? Color.black.opacity(0.35) : Color.clear)
            .animation(.easeOut(duration: 0.25), value: run.done)
        }
    }
}

final class ExportScanView: AmbientLayerView {
    private var wells: [ScanWell] = []
    private var infos: [PreviewInfo] = []
    private var setTitles: [String] = []
    private var file = ""
    private var motion = true
    private var onDone: (() -> Void)?
    private var clock = 0.0
    private var finishedRun = false

    private let stage = CALayer(), lens = CALayer(), laser = CALayer()
    private var lit: [CALayer] = []
    private let wellLabel = CATextLayer(), stainLabel = CATextLayer(), readout = CATextLayer(), count = CATextLayer()
    private let bar = CALayer(), barTrack = CALayer()
    /// The scope beside the plate; the window puts it next to this view.
    let scope = StainingPreviewView(frame: .zero)
    private var shownSet = -1, shownWell = -1
    private var lastReadout = ""

    // plate geometry, top-down, in this view (flipped layer geometry)
    private let pitch: CGFloat = 31, origin = CGPoint(x: 70, y: 150)
    private var lead = 0.6, per = 0.2
    private var total: Double { lead + per * Double(max(1, wells.count)) + 0.5 }

    func configure(wells: [ScanWell], infos: [PreviewInfo], setTitles: [String], file: String, motion: Bool, onDone: @escaping () -> Void) {
        self.wells = wells; self.infos = infos; self.setTitles = setTitles; self.file = file
        self.motion = motion; self.onDone = onDone
        per = min(0.32, max(0.07, 4.2 / Double(max(1, wells.count))))
        layer?.isGeometryFlipped = true
        build()
    }

    private func center(_ w: Int) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(w % 12) + 0.5) * pitch, y: origin.y + (CGFloat(w / 12) + 0.5) * pitch)
    }

    private func build() {
        guard let root = layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let W = bounds.width, H = bounds.height
        stage.frame = bounds
        root.addSublayer(stage)
        let plateRect = CGRect(x: origin.x - 34, y: origin.y - 34, width: pitch * 12 + 52, height: pitch * 8 + 50)
        stage.contents = renderImage(bounds.size, screenScale) { c in
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            if let g = CGGradient(colorsSpace: space, colors: [cg("0A1D38"), cg("06101F"), cg("040A14")] as CFArray, locations: [0, 0.6, 1]) {
                c.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: W, y: H), options: [])
            }
            if let g = CGGradient(colorsSpace: space, colors: [cg("3B7BD6", 0.22), cg("3B7BD6", 0)] as CFArray, locations: [0, 1]) {
                c.drawRadialGradient(g, startCenter: CGPoint(x: plateRect.midX, y: plateRect.midY), startRadius: 0,
                                     endCenter: CGPoint(x: plateRect.midX, y: plateRect.midY), endRadius: 330, options: [])
            }
            drawText("CONFOCAL ACQUISITION", CGPoint(x: 30, y: 30), 10.5, NSColor(white: 1, alpha: 0.55), weight: .bold, tracking: 1.4)
            var name = self.file
            let room = W - 360
            if textWidth(name, 13, weight: .semibold) > room {
                var keep = name.count - 1
                while keep > 8 {
                    let head = name.prefix(keep / 2), tail = name.suffix(keep - keep / 2)
                    let t = head + "…" + tail
                    if textWidth(String(t), 13, weight: .semibold) <= room { name = String(t); break }
                    keep -= 2
                }
            }
            drawText(name, CGPoint(x: 30, y: 48), 13, .white, weight: .semibold)
            // the stage insert
            c.setFillColor(cg("1A2A40")); c.fill(plateRect.insetBy(dx: -14, dy: -14))
            c.setStrokeColor(cg("33496A")); c.setLineWidth(1); c.stroke(plateRect.insetBy(dx: -14, dy: -14))
            // the plate: white polymer, A1 corner cut
            let p = CGMutablePath(), r = plateRect, cut: CGFloat = 14, rad: CGFloat = 10
            p.move(to: CGPoint(x: r.minX + cut, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - rad, y: r.minY))
            p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: rad)
            p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: rad)
            p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: rad)
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + cut))
            p.closeSubpath()
            c.saveGState(); c.addPath(p); c.clip()
            if let g = CGGradient(colorsSpace: space, colors: [cg("E9EEF5"), cg("C9D3E0")] as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(g, start: CGPoint(x: 0, y: r.minY), end: CGPoint(x: 0, y: r.maxY), options: [])
            }
            c.restoreGState()
            c.addPath(p); c.setStrokeColor(cg("FFFFFF", 0.8)); c.setLineWidth(1.2); c.strokePath()
            for j in 0..<12 { drawText("\(j + 1)", CGPoint(x: self.origin.x + (CGFloat(j) + 0.5) * self.pitch, y: self.origin.y - 20), 9, NSColor(hex: "5E7290"), weight: .bold, center: true) }
            for i in 0..<8 { drawText(rowLetters[i], CGPoint(x: self.origin.x - 16, y: self.origin.y + (CGFloat(i) + 0.5) * self.pitch - 6), 9, NSColor(hex: "5E7290"), weight: .bold, center: true) }
            let stained = Dictionary(uniqueKeysWithValues: self.wells.map { ($0.index, $0.fill) })
            for w in 0..<96 {
                let ctr = self.center(w), s = self.pitch - 6
                let cell = CGRect(x: ctr.x - s / 2, y: ctr.y - s / 2, width: s, height: s)
                let path = CGPath(roundedRect: cell, cornerWidth: 5, cornerHeight: 5, transform: nil)
                c.addPath(path)
                c.setFillColor(stained[w].map { cg($0, 0.55) } ?? cg("DCE4EE"))
                c.fillPath()
                c.addPath(path); c.setStrokeColor(cg("8EA2BC")); c.setLineWidth(1); c.strokePath()
            }
            // the right-hand panel
            let px = W - 300
            c.setFillColor(cg("FFFFFF", 0.04)); c.fill(CGRect(x: px - 20, y: 0, width: 320, height: H))
            c.setFillColor(cg("FFFFFF", 0.08)); c.fill(CGRect(x: px - 20, y: 0, width: 1, height: H))
            drawText("ACQUIRING", CGPoint(x: px, y: 30), 10.5, NSColor(white: 1, alpha: 0.55), weight: .bold, tracking: 1.4)
        }

        // each stained well's light, once acquired
        lit.forEach { $0.removeFromSuperlayer() }
        var glows: [String: CGImage?] = [:]
        lit = wells.map { w in
            let img = glows[w.glow] ?? renderImage(CGSize(width: pitch * 1.8, height: pitch * 1.8), screenScale) { c in
                let space = CGColorSpace(name: CGColorSpace.sRGB)!, m = self.pitch * 0.9
                if let g = CGGradient(colorsSpace: space, colors: [cg("FFFFFF", 0.95), cg(w.glow, 0.9), cg(w.glow, 0)] as CFArray, locations: [0, 0.32, 1]) {
                    c.drawRadialGradient(g, startCenter: CGPoint(x: m, y: m), startRadius: 0, endCenter: CGPoint(x: m, y: m), endRadius: m, options: [])
                }
            }
            glows[w.glow] = img
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: pitch * 1.8, height: pitch * 1.8)
            l.position = center(w.index)
            l.contents = img
            l.opacity = 0
            stage.addSublayer(l)
            return l
        }
        // the laser line inside the well under the lens
        laser.bounds = CGRect(x: 0, y: 0, width: pitch - 8, height: 2)
        laser.backgroundColor = NSColor.white.cgColor
        laser.shadowColor = NSColor(hex: "8CF5A4").cgColor
        laser.opacity = 0
        stage.addSublayer(laser)
        lens.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
        lens.contents = PlateReaderView.lens
        lens.position = CGPoint(x: origin.x - 40, y: origin.y - 40)
        stage.addSublayer(lens)

        // the panel: well, stain, the scope, the readout, the progress
        let px = W - 300
        func text(_ t: CATextLayer, _ y: CGFloat, _ size: CGFloat, _ color: NSColor, _ weight: NSFont.Weight, mono: Bool = false) {
            t.contentsScale = screenScale
            t.frame = CGRect(x: px, y: y, width: 270, height: size + 6)
            t.font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
            t.fontSize = size
            t.foregroundColor = color.cgColor
            t.truncationMode = .end
            stage.addSublayer(t)
        }
        text(wellLabel, 50, 28, .white, .bold)
        text(stainLabel, 88, 12, NSColor(hex: "BFD9FF"), .medium)
        text(readout, H - 112, 11, NSColor(hex: "9BF0FF"), .semibold, mono: true)
        text(count, H - 92, 11, NSColor(white: 1, alpha: 0.6), .medium, mono: true)
        barTrack.frame = CGRect(x: px, y: H - 72, width: 270, height: 4)
        barTrack.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor
        barTrack.cornerRadius = 2
        stage.addSublayer(barTrack)
        bar.anchorPoint = CGPoint(x: 0, y: 0.5)
        bar.frame = CGRect(x: px, y: H - 72, width: 0, height: 4)
        bar.backgroundColor = cg("8CF5A4")
        bar.cornerRadius = 2
        stage.addSublayer(bar)

        scope.hologram = true
        scope.frame = CGRect(x: px + 30, y: bounds.height - 118 - 210, width: 210, height: 210)   // the window's coordinates
        show(0)
    }

    func start() {
        clock = 0
        ambientActive = motion
        if !motion { skip() }
    }

    func stop() {
        ambientActive = false
        scope.ambientActive = false
    }

    func skip() {
        clock = total
        CATransaction.begin(); CATransaction.setDisableActions(true)
        show(clock)
        CATransaction.commit()
        finish()
    }

    private func finish() {
        guard !finishedRun else { return }
        finishedRun = true
        ambientActive = false
        onDone?()
    }

    override func tick(_ dt: Double) {
        clock += dt
        show(clock)
        if clock >= total { finish() }
    }

    override func rest() {}

    /// Development: the scene at `t` seconds.
    func snapshot(at t: Double) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        clock = t
        show(t)
        CATransaction.commit()
    }

    private func show(_ t: Double) {
        guard !wells.isEmpty else { return }
        let n = wells.count
        let u = (t - lead) / per
        let k = max(0, min(n - 1, Int(floor(max(0, u)))))
        let into = u - Double(k)                   // 0…1 within this well's turn
        let doneCount = t >= total ? n : max(0, min(n, Int(floor(u)) + (into > 0.55 ? 1 : 0)))
        // the lens travels to the well, then holds while it is scanned
        let to = center(wells[k].index)
        let from = k == 0 ? CGPoint(x: origin.x - 40, y: origin.y - 40) : center(wells[k - 1].index)
        let e = CGFloat(easeInOut(min(1, max(0, into) / 0.45)))
        let p = t < lead ? CGPoint(x: origin.x - 40, y: origin.y - 40) : CGPoint(x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e)
        lens.position = p
        lens.opacity = Float(t >= total ? max(0, 1 - (t - total)) : min(1, t / 0.4))
        // the laser line sweeps down the well once the lens has arrived
        let scanning = t >= lead && t < total - 0.5 && into >= 0.45
        if scanning {
            let s = (into - 0.45) / 0.55
            laser.position = CGPoint(x: to.x, y: to.y - (pitch - 10) / 2 + CGFloat(s) * (pitch - 10))
            laser.backgroundColor = cg(wells[k].glow)
            laser.opacity = 0.95
        } else {
            laser.opacity = 0
        }
        for (i, l) in lit.enumerated() {
            let o: Float = i < doneCount ? 1 : 0
            if l.opacity != o { l.opacity = o }
        }
        bar.bounds.size.width = 270 * CGFloat(doneCount) / CGFloat(n)
        let w = wells[k]
        if w.index != shownWell {
            shownWell = w.index
            wellLabel.string = t >= total ? "Done" : "\(rowLetters[w.index / 12])\(w.index % 12 + 1)"
        }
        if t >= total, (wellLabel.string as? String) != "Done" { wellLabel.string = "Done" }
        if w.setIndex != shownSet, w.setIndex < infos.count {
            shownSet = w.setIndex
            let info = infos[w.setIndex]
            stainLabel.string = "\(setTitles[w.setIndex]) · \(info.subtitle)"
            scope.setInfo(info, replay: w.setIndex + 1)
            scope.ambientActive = motion
        }
        let ch = infos.indices.contains(w.setIndex) ? infos[w.setIndex].channels : []
        let line: String
        if t >= total { line = "\(n) wells · all channels acquired" }
        else if scanning, !ch.isEmpty {
            let s = (into - 0.45) / 0.55
            let c = ch[min(ch.count - 1, Int(s * Double(ch.count)))]
            line = "λ\(c.fluor.name) · line \(Int(s * 512))/512"
        } else { line = "moving stage…" }
        if line != lastReadout { lastReadout = line; readout.string = line }
        let cnt = "\(doneCount) / \(n) wells"
        if (count.string as? String) != cnt { count.string = cnt }
    }
}


/// Development: the acquisition window `t` seconds in, for the sample or a saved plate.
func exportScanSnapshot(_ path: String, at t: Double, plate: String?) {
    _ = NSApplication.shared
    let store = Store(inMemory: sampleExperiment())
    if let plate, let d = try? Data(contentsOf: URL(fileURLWithPath: plate)), let e = try? decodePlate(d) { store.exp = e }
    let sets = store.exp.sets, ids = sets.map { $0.id }
    var wells: [ScanWell] = []
    for w in 0..<96 {
        guard let id = store.exp.wells[w], let k = ids.firstIndex(of: id) else { continue }
        let dyes = panelReport(sets[k]).channels.filter { !$0.fluor.counterstain }.map { $0.fluor.hex }
        wells.append(ScanWell(index: w, setIndex: k, fill: fillHex(sets[k], k), glow: mergeHex(dyes) ?? fillHex(sets[k], k)))
    }
    wells.sort { a, b in
        let ra = a.index / 12, rb = b.index / 12
        if ra != rb { return ra < rb }
        return ra % 2 == 0 ? a.index % 12 < b.index % 12 : a.index % 12 > b.index % 12
    }
    let size = NSSize(width: 860, height: 520)
    let v = ExportScanView(frame: NSRect(origin: .zero, size: size))
    v.configure(wells: wells, infos: sets.indices.map { store.previewInfo(for: $0) }, setTitles: sets.indices.map { "Stain \($0 + 1)" },
                file: store.exp.fileName, motion: true) {}
    v.snapshot(at: t)
    v.scope.layout()
    v.scope.preview(at: 12.2)
    let scale: CGFloat = 2
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.scaleBy(x: scale, y: scale)
    ctx.saveGState()
    ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)     // the scene's layers are laid out top-down
    v.layer?.render(in: ctx)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.translateBy(x: v.scope.frame.minX, y: v.scope.frame.minY)
    v.scope.layer?.render(in: ctx)
    ctx.restoreGState()
    if let img = ctx.makeImage() {
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}


/// The colour of a stain's dyes seen together (additive, like a merge): 488 + 594 looks yellow.
func mergeHex(_ hexes: [String]) -> String? {
    guard !hexes.isEmpty else { return nil }
    var r = 0.0, g = 0.0, b = 0.0
    for h in hexes {
        let v = UInt32(h, radix: 16) ?? 0
        r += Double((v >> 16) & 0xFF); g += Double((v >> 8) & 0xFF); b += Double(v & 0xFF)
    }
    let m = max(r, g, b, 1)
    let k = 255 / m
    return String(format: "%02X%02X%02X", Int(r * k), Int(g * k), Int(b * k))
}

/// The compatibility report for a stain (a name that classes with their own `panel` can still reach).
func panelReport(_ s: StainSet) -> PanelReport { panel(s) }
