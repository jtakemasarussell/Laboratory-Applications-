import SwiftUI
import AppKit

/// Development: the real window, photographed part-way through each of the bench effects: the hologram
/// staying away at launch, the aspirator, the lid coming off and going on, the wash, the rewind, the loupe,
/// the dye flash and the binding, the fridge door, the room lights and the printout.
func fxShot2(_ platePath: String, _ out: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let store = Store(inMemory: sampleExperiment())
    if let d = try? Data(contentsOf: URL(fileURLWithPath: platePath)), let e = try? decodePlate(d) { store.exp = e }
    // as at launch: a stain is already selected, nobody has clicked it
    store.tool = .paint(store.exp.sets[min(1, store.exp.sets.count - 1)].id)
    let host = NSHostingView(rootView: ContentView().environmentObject(store).frame(width: 1360, height: 900))
    let win = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1360, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host
    win.orderFrontRegardless()
    store.appActive = true
    func wait(_ t: Double) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }
    func shot(_ name: String, _ w: NSWindow = win) {
        guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.boundsIgnoreFraming, .bestResolution]) else { print("no capture"); return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + name + ".png"))
    }
    /// The screen over the window, so windows floating above it (the room lights) are in the picture too.
    func screenShot(_ name: String) {
        guard let screen = win.screen ?? NSScreen.main else { return }
        let f = win.frame
        let r = CGRect(x: f.minX, y: screen.frame.maxY - f.maxY, width: f.width, height: f.height)
        guard let img = CGWindowListCreateImage(r, .optionOnScreenAboveWindow, CGWindowID(win.windowNumber), [.bestResolution]),
              let below = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(win.windowNumber), [.boundsIgnoreFraming, .bestResolution])
        else { print("no capture"); return }
        // the window, with whatever floats above it laid over
        let size = CGSize(width: below.width, height: below.height)
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.draw(below, in: CGRect(origin: .zero, size: size))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: size.width, height: size.width * CGFloat(img.height) / CGFloat(img.width)))
        if let merged = ctx.makeImage() {
            try? NSBitmapImageRep(cgImage: merged).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + name + ".png"))
        }
    }
    let fx = FxCenter.shared
    wait(HoloController.dwell + 0.8)
    print("hologram at launch:", HoloController.shared.shown == nil ? "stayed away" : "SHOWN")
    print("grid", fx.gridFrame, "plate", fx.plateFrame, "stain 1 card", store.exp.sets.first.flatMap { fx.cardFrames[$0.id] } ?? .zero)
    let ids = store.exp.sets.map { $0.id }
    let stained = (0..<96).filter { store.exp.wells[$0].map { ids.contains($0) } ?? false }
    guard let first = stained.first else { print("the plate has no stained wells"); return }

    // the aspirator
    store.tool = .erase
    wait(0.3)
    store.touch(first)
    wait(0.32)
    shot("aspirate")
    store.endDrag()
    wait(0.5)
    store.undo()                      // and the rewind brings it back
    wait(0.12)
    shot("rewind-back")
    wait(0.8)

    // the lid
    store.fxLid(lowering: false)
    wait(0.22)
    shot("lid-off")
    wait(1.0)
    store.fxLid(lowering: true)
    wait(0.62)
    shot("lid-on")
    wait(1.6)

    // the wash, and the rewind putting it all back
    store.clearPlate()
    wait(0.55)
    shot("wash")
    wait(1.0)
    store.undo()
    wait(0.2)
    shot("rewind-all")
    wait(1.2)

    // painting a row, then undoing it: newest out first
    store.tool = .paint(store.exp.sets[0].id)
    let row = (0..<12).map { 84 + $0 }.filter { store.exp.wells[$0] == nil }
    for w in row { store.dragOver(w) }
    store.endDrag()
    wait(1.0)
    store.undo()
    wait(0.16)
    shot("rewind-row")
    wait(1.0)

    // the loupe, over a stained well
    let lw = stained[min(stained.count - 1, stained.count / 2)]
    let c = fx.wellCenter(lw)
    fx.view?.loupe.look(at: CGPoint(x: c.x + 8, y: c.y + 6))
    wait(0.3)
    shot("loupe")
    fx.view?.loupe.hide()
    wait(0.3)

    // the dye flash and the binding: Stain 1's secondary given the wrong host, then put back
    if !store.exp.sets.isEmpty, !store.exp.sets[0].secondaries.isEmpty {
        let before = store.exp.sets[0].secondaries[0].name
        store.exp.sets[0].secondaries[0].name = "488 m"
        wait(0.5)
        shot("bind-refused")
        wait(1.4)
        store.exp.sets[0].secondaries[0].name = before
        wait(0.34)
        shot("bind-click")
        wait(1.4)
        store.exp.sets[0].secondaries[0].name = "647 rab"     // a new dye on the same row
        wait(0.14)
        shot("dye-flash")
        wait(1.2)
        store.exp.sets[0].secondaries[0].name = before
        wait(1.2)
    }

    // the fridge, opened on its own window
    let fridge = NSHostingView(rootView: FridgeRack(secondaries: true, setID: store.exp.sets[0].id, motion: true) {}.environmentObject(store))
    fridge.layoutSubtreeIfNeeded()
    let fsize = fridge.fittingSize
    let fw = NSWindow(contentRect: NSRect(x: 80, y: 80, width: fsize.width, height: fsize.height), styleMask: [.titled], backing: .buffered, defer: false)
    fw.contentView = fridge
    fw.orderFrontRegardless()
    wait(0.3)
    shot("fridge-door0", fw)
    wait(0.6)
    shot("fridge-door", fw)
    wait(0.6)
    shot("fridge-door2", fw)
    wait(0.8)
    shot("fridge-mist", fw)
    wait(1.4)
    shot("fridge-open", fw)
    fw.orderOut(nil)
    wait(0.3)

    // opening a plate: frozen under its lid, the frost melts off the lid, then the lid comes off
    win.orderFrontRegardless()
    store.fxLid(lowering: false, holdFor: 1.95)
    store.fxThaw()
    wait(0.6); shot("open-frost")
    wait(1.1); shot("open-melt")
    wait(0.75); shot("open-lift")
    wait(1.2)

    // deep wells, the plate leaning one way and then the other
    if let t = TiltModel.current {
        t.x = 0.95; t.y = -0.95
        wait(0.4); shot("deep-a")
        t.x = -0.95; t.y = 0.95
        wait(0.4); shot("deep-b")
        t.x = 0; t.y = 0
        wait(0.4)
    }

    // a stain card on its own: its spectrum when picked, and the mixing tube when a dilution changes
    store.tool = .paint(store.exp.sets[0].id)
    let card = NSHostingView(rootView: StainCard(setID: store.exp.sets[0].id, index: 0).environmentObject(store).frame(width: 548))
    card.layoutSubtreeIfNeeded()
    let csize = card.fittingSize
    let cwin = NSWindow(contentRect: NSRect(x: 60, y: 60, width: csize.width, height: csize.height), styleMask: [.titled], backing: .buffered, defer: false)
    cwin.contentView = card
    cwin.orderFrontRegardless()
    wait(0.45); shot("spectrum-firing", cwin)
    wait(1.3); shot("spectrum", cwin)
    if !store.exp.sets[0].primaries.isEmpty {
        store.exp.sets[0].primaries[0].dilution = store.exp.sets[0].primaries[0].dilution == 500 ? 1000 : 500
        wait(0.3); shot("mix-pour", cwin)
        wait(0.6); shot("mix-swirl", cwin)
        wait(1.2); shot("mix-done", cwin)
    }
    if !store.exp.sets[0].secondaries.isEmpty {
        let before = store.exp.sets[0].secondaries[0].name
        store.exp.sets[0].secondaries[0].name = "555 rab"         // shares the 561 laser with a 594
        wait(1.8); shot("spectrum-overlap", cwin)
        store.exp.sets[0].secondaries[0].name = before
        wait(0.5)
    }
    cwin.orderOut(nil)

    // the room lights going out, then coming back on
    win.orderFrontRegardless()
    store.switchRoom(true)
    wait(0.4)
    screenShot("lights-off")
    wait(1.4)
    shot("lights-dark")
    store.switchRoom(false)
    wait(0.45)
    screenShot("lights-on")
    wait(1.4)

    // the printout
    ExportScanController.shared.present(store, url: URL(fileURLWithPath: NSTemporaryDirectory() + "fxshot2.xlsx")) {}
    wait(1.0)
    ExportScanController.shared.devSkip()
    wait(0.75)
    if let w = NSApp.windows.first(where: { $0 !== win && $0.isVisible && $0 !== fw }) { shot("printout-mid", w) }
    wait(1.0)
    if let w = NSApp.windows.first(where: { $0 !== win && $0.isVisible && $0 !== fw }) { shot("printout", w) }
    print("done")
}
