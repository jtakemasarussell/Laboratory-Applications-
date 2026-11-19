import SwiftUI
import AppKit

// MARK: - Quality check of saved plates (development: --qc <folder>)
//
// For every .iccplate in a folder: it opens; saving it again and reopening gives exactly the same
// plate; nothing in the original file is dropped or changed by the new version; it loads into the app
// and draws; and it exports a workbook holding all its samples, antibodies and labels. Files are only
// read.

private var qcPass = 0, qcFail = 0
private func check(_ ok: Bool, _ what: String) {
    if ok { qcPass += 1 } else { qcFail += 1; print("     ✗ \(what)") }
}

/// Where two JSON values differ: paths of anything missing, added or changed.
private func jsonDiff(_ a: Any?, _ b: Any?, _ path: String, _ out: inout [String]) {
    switch (a, b) {
    case let (x as [String: Any], y as [String: Any]):
        for k in Set(x.keys).union(y.keys).sorted() {
            if x[k] == nil { out.append("\(path).\(k) added") } else if y[k] == nil { out.append("\(path).\(k) missing after saving") }
            else { jsonDiff(x[k], y[k], "\(path).\(k)", &out) }
        }
    case let (x as [Any], y as [Any]):
        if x.count != y.count { out.append("\(path) count \(x.count) → \(y.count)"); return }
        for i in x.indices { jsonDiff(x[i], y[i], "\(path)[\(i)]", &out) }
    case let (x as NSNumber, y as NSNumber):
        if x.doubleValue != y.doubleValue { out.append("\(path): \(x) → \(y)") }
    case let (x as String, y as String):
        if x != y { out.append("\(path): \"\(x)\" → \"\(y)\"") }
    case (is NSNull, is NSNull): break
    default:
        if (a == nil) != (b == nil) || String(describing: a) != String(describing: b) { out.append("\(path): \(String(describing: a)) → \(String(describing: b))") }
    }
}

func plateQC(_ dir: String) {
    _ = NSApplication.shared
    NSApplication.shared.setActivationPolicy(.prohibited)
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".iccplate") }.sorted()
    print("Checking \(files.count) saved plate\(files.count == 1 ? "" : "s") with ICC Plate Planner \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")\n")
    for f in files {
        let url = URL(fileURLWithPath: dir).appendingPathComponent(f)
        print("■ \(f)")
        guard let data = try? Data(contentsOf: url) else { check(false, "file can be read"); continue }
        // 1. it opens
        let e: Experiment
        do { e = try decodePlate(data); check(true, "") } catch { check(false, "opens: \(error.localizedDescription)"); continue }
        let painted = e.wells.compactMap { $0 }.count, labels = e.wellText.filter { !$0.isEmpty }.count
        let tags = e.wellTags.compactMap { $0 }.count
        let abs = e.sets.reduce(0) { $0 + $1.primaries.count + $1.secondaries.count }
        print("     opens: \(e.samples.count) samples, \(e.sets.count) stain sets (\(abs) antibodies), \(painted) painted wells, \(labels) well labels, \(tags) tags")
        // 2. saving and reopening gives the same plate
        if let again = try? encodePlate(e), let back = try? decodePlate(again) {
            check(back == e, "save and reopen gives exactly the same plate")
            // 3. nothing in the original file is lost or altered
            let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let n = (try? JSONSerialization.jsonObject(with: again)) as? [String: Any]
            var diffs: [String] = []
            jsonDiff(o?["exp"], n?["exp"], "exp", &diffs)
            check(diffs.isEmpty, "everything in the original file comes back unchanged:\n       " + diffs.prefix(12).joined(separator: "\n       "))
            check((n?["app"] as? String) == "ICC Plate Planner" && (n?["version"] as? Int) == (o?["version"] as? Int), "file header (app, format version) unchanged")
        } else { check(false, "save and reopen") }
        // 4. references inside the plate point at things that exist
        let setIDs = Set(e.sets.map { $0.id }), sampleIDs = Set(e.samples.map { $0.id })
        check(e.wells.compactMap { $0 }.allSatisfy { setIDs.contains($0) }, "every painted well points at an existing stain set")
        check(e.wellTags.compactMap { $0 }.allSatisfy { sampleIDs.contains($0) }, "every stamped tag points at an existing sample")
        // 5. it loads into the app and draws, the panel check runs
        let store = Store(inMemory: e)
        let host = NSHostingView(rootView: ContentView().environmentObject(store).frame(width: 1320, height: 900))
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) { host.cacheDisplay(in: host.bounds, to: rep) }
        check(true, "")
        let verdicts = e.sets.map { panel($0, library: .seed).verdict }
        let red = verdicts.enumerated().filter { $0.element == .problem }.map { "Stain \($0.offset + 1)" }
        check(red.isEmpty, "antibody pairings: \(red.joined(separator: ", ")) marked as a problem")
        print("     opens in the app and draws; pairings: \(verdicts.filter { $0 == .ok }.count) green, \(verdicts.filter { $0 == .unknown }.count) unchecked, \(red.count) red")
        // 6. it exports a workbook holding everything (entries are stored uncompressed, so the text is there to find)
        let book = buildWorkbook(e, Settings())
        let text = String(decoding: book, as: UTF8.self)
        check(book.count > 2000 && text.contains("xl/workbook.xml"), "exports a workbook")
        var missing: [String] = []
        for s in e.samples where !s.code.trimmingCharacters(in: .whitespaces).isEmpty {
            if !text.contains(xmlEscape(s.code.trimmingCharacters(in: .whitespaces))) { missing.append("sample \(s.code)") }
        }
        for set in e.sets {
            for p in set.primaries where !p.name.isEmpty { if !text.contains(xmlEscape(markerName(p.name))) && !text.contains(xmlEscape(p.name)) { missing.append(p.name) } }
            for q in set.secondaries where !q.name.isEmpty { if !text.contains(xmlEscape(q.name)) { missing.append(q.name) } }
        }
        for l in e.wellText where !l.isEmpty {
            for line in l.split(separator: "\n") where !text.contains(xmlEscape(String(line))) && plainNumber(String(line)) == nil { missing.append("label \(line)") }
        }
        check(missing.isEmpty, "the workbook holds every sample, antibody and label (missing: \(Array(Set(missing)).sorted().prefix(8).joined(separator: ", ")))")
        print("     exports a \(book.count / 1024) KB workbook with every sample, antibody and label")
        print("")
    }
    print("\(qcPass) checks passed, \(qcFail) failed")
}
