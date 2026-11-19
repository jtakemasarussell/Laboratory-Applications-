import SwiftUI
import AppKit
import Network
import CoreImage
import CoreImage.CIFilterBuiltins
import SystemConfiguration

// MARK: - Bench mode on the iPad
//
// The Mac serves bench mode as a web page on the local network. The iPad opens it from a QR code in
// Safari (and can keep it on its Home Screen); ticks made on either side show on the other within a
// couple of seconds. Every request carries a random key from the QR code, so nobody else on the
// network can open the protocol.

final class BenchServer {
    static let shared = BenchServer()
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "bench.server")
    private(set) var port: UInt16 = 0
    /// Made once and kept, so the iPad's Home Screen icon keeps working from day to day.
    let key: String = {
        if let k = UserDefaults.standard.string(forKey: "benchKey"), k.count >= 10 { return k }
        let k = String((0..<12).map { _ in "abcdefghjkmnpqrstuvwxyz23456789".randomElement()! })
        UserDefaults.standard.set(k, forKey: "benchKey")
        return k
    }()
    private var icon: Data?
    private var awake: NSObjectProtocol?
    var running: Bool { listener != nil }
    var onChange: (() -> Void)?

    func start() {
        guard listener == nil else { return }
        listen(on: 8765)
        // the Mac stays awake while the iPad may need it; the screen may still sleep
        awake = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: "Bench mode on iPad")
        icon = Self.iconPNG()
    }

    /// The usual port, so a saved Home Screen icon keeps working; any free one if it is taken.
    private func listen(on port: NWEndpoint.Port) {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params, on: port) else {
            if port != .any { listen(on: .any) }
            return
        }
        l.newConnectionHandler = { [weak self] c in self?.serve(c) }
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let p = l.port?.rawValue { DispatchQueue.main.async { self?.port = p; self?.onChange?() } }
            case .failed:
                l.cancel()
                if port != .any { DispatchQueue.main.async { if self?.listener === l { self?.listen(on: .any) } } }
            default: break
            }
        }
        l.start(queue: queue)
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
        if let a = awake { ProcessInfo.processInfo.endActivity(a) }
        awake = nil
        onChange?()
    }

    /// The addresses the iPad can use: the Mac's Wi-Fi/Ethernet addresses, then its local name.
    var urls: [String] {
        guard port != 0 else { return [] }
        var out = Self.addresses().map { "http://\($0):\(port)/?k=\(key)" }
        if let host = SCDynamicStoreCopyLocalHostName(nil) as String?, !host.isEmpty {
            out.append("http://\(host).local:\(port)/?k=\(key)")
        }
        return out
    }

    private static func addresses() -> [String] {
        var out: [(String, String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            guard let sa = a.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), (a.ifa_flags & UInt32(IFF_UP)) != 0, (a.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let name = String(cString: a.ifa_name)
            let ip = String(cString: host)
            guard !ip.hasPrefix("169.254"), name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            out.append((name, ip))
        }
        return out.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    private static func iconPNG() -> Data? {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let img = NSImage(contentsOf: url) else { return nil }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 180, pixelsHigh: 180, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: 180, height: 180))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: HTTP, just enough of it

    private func serve(_ c: NWConnection) {
        c.start(queue: queue)
        receive(c, Data())
    }

    private func receive(_ c: NWConnection, _ sofar: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self else { return }
            var buf = sofar
            if let data { buf.append(data) }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<end.lowerBound], as: UTF8.self)
                let length = head.split(separator: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                let body = buf[end.upperBound...]
                if body.count >= length || done || error != nil {
                    self.respond(c, head, Data(body.prefix(length)))
                    return
                }
            } else if done || error != nil || buf.count > 1_000_000 {
                c.cancel()
                return
            }
            self.receive(c, buf)
        }
    }

    private func respond(_ c: NWConnection, _ head: String, _ body: Data) {
        let line = head.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = line.split(separator: " ")
        let method = parts.first.map(String.init) ?? "GET"
        let target = parts.count > 1 ? String(parts[1]) : "/"
        let comps = URLComponents(string: "http://x" + target)
        let path = comps?.path ?? "/"
        let key = comps?.queryItems?.first { $0.name == "k" }?.value

        func send(_ status: String, _ type: String, _ data: Data, cache: Bool = false) {
            let h = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(data.count)\r\nCache-Control: \(cache ? "max-age=86400" : "no-store")\r\nConnection: close\r\n\r\n"
            c.send(content: Data(h.utf8) + data, completion: .contentProcessed { _ in c.cancel() })
        }

        // the Home Screen icon carries nothing private, and is kept by the iPad for a day
        if path == "/icon.png", let icon { send("200 OK", "image/png", icon, cache: true); return }
        guard key == self.key else {
            send("403 Forbidden", "text/plain; charset=utf-8", Data("This bench link needs the full address from the QR code on the Mac.".utf8))
            return
        }
        switch (method, path) {
        case ("GET", "/"):
            let page = Bundle.main.url(forResource: "BenchWeb", withExtension: "html").flatMap { try? Data(contentsOf: $0) } ?? Data("Bench page missing".utf8)
            send("200 OK", "text/html; charset=utf-8", page)
        case ("GET", "/state"):
            let json = DispatchQueue.main.sync { Store.current?.benchJSON(seen: true) ?? Data("{}".utf8) }
            send("200 OK", "application/json", json)
        case ("POST", "/tick"):
            let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let json = DispatchQueue.main.sync { () -> Data in
                if let id = obj?["id"] as? String, let on = obj?["done"] as? Bool { Store.current?.benchSet(id, on) }
                return Store.current?.benchJSON(seen: true) ?? Data("{}".utf8)
            }
            send("200 OK", "application/json", json)
        case ("POST", "/step"):
            let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let json = DispatchQueue.main.sync { () -> Data in
                if let n = obj?["step"] as? Int, let s = Store.current {
                    s.benchStep = max(0, min(n, max(s.benchSteps.count - 1, 0)))
                }
                return Store.current?.benchJSON(seen: true) ?? Data("{}".utf8)
            }
            send("200 OK", "application/json", json)
        case ("POST", "/reset"):
            let json = DispatchQueue.main.sync { () -> Data in
                Store.current?.benchDone.removeAll()
                Store.current?.benchStep = 0
                return Store.current?.benchJSON(seen: true) ?? Data("{}".utf8)
            }
            send("200 OK", "application/json", json)
        default:
            send("404 Not Found", "text/plain", Data())
        }
    }
}

extension Store {
    /// Everything the iPad page shows: the steps, the plates' wells in their primers' colours, and the ticks.
    func benchJSON(seen: Bool) -> Data {
        if seen { ipadSeen = Date() }
        let steps = benchSteps
        let plates: [[String: Any]] = plan.plates.map { plate in
            var wells: [[String: Any]] = []
            for r in 0..<8 {
                for c in 0..<12 {
                    guard let w = plate.content(r, c) else { continue }
                    wells.append(["i": r * 12 + c, "color": colors.color(plate.primers[w.primer], plate.primerIndex[w.primer])])
                }
            }
            let primers: [[String: Any]] = plate.primers.enumerated().map { b, name in
                ["name": name, "color": colors.color(name, plate.primerIndex[b]), "ref": b == 0]
            }
            return ["number": plate.number, "wells": wells, "primers": primers]
        }
        let obj: [String: Any] = [
            "motion": motion,                 // the Mac's Animations setting
            "title": plan.customName ?? plan.runName,
            "step": min(benchStep, max(steps.count - 1, 0)),
            "done": Array(benchDone).sorted(),
            "plates": plates,
            "steps": steps.map { s in
                ["id": s.id, "title": s.title, "note": s.note,
                 "items": s.items.map { i -> [String: Any] in
                     var o: [String: Any] = ["id": i.id, "title": i.title, "detail": i.detail]
                     if let p = i.plate { o["plate"] = p; o["wells"] = Array(i.wells).sorted() }
                     return o
                 }]
            },
        ]
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    /// A tick from the iPad: set rather than toggled, so a repeated request changes nothing.
    func benchSet(_ id: String, _ on: Bool) {
        guard benchDone.contains(id) != on else { return }
        benchTick(id)
    }
}

/// A QR code for a link, crisp at any size.
func qrImage(_ text: String) -> NSImage? {
    let f = CIFilter.qrCodeGenerator()
    f.message = Data(text.utf8)
    f.correctionLevel = "M"
    guard let out = f.outputImage else { return nil }
    let scaled = out.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
    let rep = NSCIImageRep(ciImage: scaled)
    let img = NSImage(size: rep.size)
    img.addRepresentation(rep)
    return img
}

/// The sheet on the Mac: scan this with the iPad.
struct IPadLinkView: View {
    @EnvironmentObject var store: Store
    private let tick = State(initialValue: 0)

    var body: some View {
        let server = BenchServer.shared
        let urls = server.urls
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "ipad.landscape").font(.system(size: 22)).foregroundColor(Brand.accent)
                Text("Bench mode on your iPad").font(.system(size: 20, weight: .bold, design: .serif)).foregroundColor(Brand.ink)
                Spacer()
            }
            HStack(alignment: .top, spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(fixed: "FFFFFF"))
                    if let url = urls.first, let qr = qrImage(url) {
                        Image(nsImage: qr).interpolation(.none).resizable().frame(width: 200, height: 200)
                    } else {
                        ProgressView().controlSize(.large)
                    }
                }
                .frame(width: 228, height: 228)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.rule, lineWidth: 1))
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Put the iPad on the same Wi-Fi as this Mac.")
                    step(2, "Open the Camera on the iPad and point it at the code, then tap the link.")
                    step(3, "In Safari, tap Share → Add to Home Screen to keep Bench mode one tap away.")
                    Text("Ticks made on the iPad show up here, and the other way round. Keep this Mac awake with qPCR Planner open while you work.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    status
                }
            }
            if !urls.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Or type this address in Safari on the iPad:").font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach(urls.prefix(2), id: \.self) { u in
                        Text(u).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).foregroundColor(Brand.ink)
                    }
                }
            }
            HStack {
                Text("If the iPad cannot reach the Mac, the network may keep devices apart (common on hospital Wi-Fi); a personal hotspot from the iPad or a phone, with the Mac on it too, works anywhere.")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                Button("Stop sharing") { BenchServer.shared.stop(); store.showIPadLink = false }
                Button("Done") { store.showIPadLink = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 620)
        .onAppear {
            BenchServer.shared.onChange = { tick.wrappedValue += 1 }
            BenchServer.shared.start()
        }
        .id(tick.wrappedValue)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                .frame(width: 18, height: 18).background(Circle().fill(Brand.navy))
            Text(text).font(.system(size: 13)).foregroundColor(Brand.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var status: some View {
        TimelineView(.periodic(from: .now, by: 2)) { ctx in
            let seen = store.ipadSeen.map { ctx.date.timeIntervalSince($0) < 6 } ?? false
            HStack(spacing: 6) {
                Circle().fill(seen ? Color(hex: "2E9E5B") : Color(hex: "B7C5D8")).frame(width: 9, height: 9)
                Text(seen ? "iPad connected" : (BenchServer.shared.running ? "Waiting for the iPad…" : "Starting…"))
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(seen ? Color(hex: "2E7D4F") : .secondary)
            }
            .padding(.top, 4)
        }
    }
}

/// Opens the iPad sheet: from the header and the File menu.
struct IPadButton: View {
    @EnvironmentObject var store: Store
    let menu: Bool

    var body: some View {
        if menu {
            Button("Bench Mode on iPad…") { store.showIPadLink = true }.keyboardShortcut("b", modifiers: [.command, .shift])
        } else {
            FunButton(action: { store.showIPadLink = true }) {
                Image(systemName: "ipad.landscape").font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Brand.accent).padding(.horizontal, 11).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Brand.card))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Brand.navy.opacity(0.35), lineWidth: 1))
            }
            .help("Bench mode on your iPad: scan a code, tick lines off at the bench (⇧⌘B)")
        }
    }
}
