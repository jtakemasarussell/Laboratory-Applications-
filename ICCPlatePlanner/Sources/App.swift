import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Entry point

private var launchObserver: NSObjectProtocol?

@main
enum Main {
    static func main() {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--export-sample"), a.count > i + 1 {
            var e = sampleExperiment()
            if let j = a.firstIndex(of: "--plate"), a.count > j + 1, let d = try? Data(contentsOf: URL(fileURLWithPath: a[j + 1])),
               let loaded = try? decodePlate(d) { e = loaded }
            let data = buildWorkbook(e, Settings())
            try! data.write(to: URL(fileURLWithPath: a[i + 1]))
            return
        }
        if let i = a.firstIndex(of: "--make-icon"), a.count > i + 1 {
            makeIcon(a[i + 1])
            return
        }
        if let i = a.firstIndex(of: "--featuretest") {
            featureTest(statePath: a.count > i + 1 ? a[i + 1] : nil)
            return
        }
        if let i = a.firstIndex(of: "--selftest"), a.count > i + 2 {
            selfTest(ops: Int(a[i + 1]) ?? 1000, outDir: a[i + 2], seed: a.count > i + 3 ? UInt64(a[i + 3]) ?? 1 : 1)
            return
        }
        if let i = a.firstIndex(of: "--snapshot"), a.count > i + 1 {
            snapshot(a[i + 1])
            return
        }
        if let i = a.firstIndex(of: "--splash-snapshot"), a.count > i + 2, let t = Double(a[i + 2]) {
            splashSnapshot(a[i + 1], at: t)
            return
        }
        if let i = a.firstIndex(of: "--preview-snapshot"), a.count > i + 2, let t = Double(a[i + 2]) {
            previewSnapshot(a[i + 1], at: t)
            return
        }
        if let i = a.firstIndex(of: "--qc"), a.count > i + 1 { plateQC(a[i + 1]); return }
        if let i = a.firstIndex(of: "--lag-check"), a.count > i + 1 { lagCheck(a[i + 1]); return }
        if let i = a.firstIndex(of: "--fx-shot"), a.count > i + 2 { fxShot(a[i + 1], a[i + 2]); return }
        if a.contains("--pair-qc") { pairQC(); return }
        if let i = a.firstIndex(of: "--export-scan-snapshot"), a.count > i + 2, let t = Double(a[i + 2]) {
            exportScanSnapshot(a[i + 1], at: t, plate: a.firstIndex(of: "--plate").flatMap { a.count > $0 + 1 ? a[$0 + 1] : nil })
            return
        }
        if let i = a.firstIndex(of: "--qc-state"), a.count > i + 1 {
            // the app's own saved state from the version before loads in this one, with nothing lost
            let d = try! Data(contentsOf: URL(fileURLWithPath: a[i + 1]))
            do {
                let s = try JSONDecoder().decode(SavedState.self, from: d)
                let again = try JSONEncoder().encode(s)
                let back = try JSONDecoder().decode(SavedState.self, from: again)
                print("saved state loads: \(s.exp.sets.count) stain sets on the open plate, \(s.library.primaries.count) primaries and \(s.library.secondaries.count) secondaries in the library")
                print("saving it again changes nothing:", back.exp == s.exp && back.settings == s.settings && back.library == s.library)
            } catch { print("saved state FAILED to load:", error) }
            return
        }
        if let i = a.firstIndex(of: "--open-test"), a.count > i + 1 {
            for path in a[(i + 1)...] {
                do {
                    let e = try decodePlate(Data(contentsOf: URL(fileURLWithPath: path)))
                    print("OK", e.sets.count, "sets", e.samples.count, "samples")
                    for (k, set) in e.sets.enumerated() {
                        let r = panel(set)
                        print("  Stain \(k + 1): \(r.verdict)")
                        r.issues.forEach { print("    !", $0) }
                        r.notes.filter { $0.contains("catalogue") || $0.contains("product name") }.forEach { print("    i", $0) }
                    }
                }
                catch { print("FAILED:", error) }
            }
            return
        }
        if a.contains("--panel-check") {
            for (k, set) in sampleExperiment().sets.enumerated() {
                let r = panel(set)
                print("Stain \(k + 1): \(r.verdict)", r.channels.map { "\($0.fluor.name)→\($0.label) [\($0.localisation)]" }.joined(separator: ", "))
                for c in r.combos { print("  \(c.verdict)  \(c.marker) (\(c.host ?? "?")) → \(c.secondary ?? "none")"); c.reasons.forEach { print("      ", $0) } }
                r.notes.forEach { print("  i", $0) }
            }
            var bad = StainSet()
            let lib = Library.seed
            bad.primaries = [lib.primaries[0], lib.primaries[4], lib.primaries[1]]      // two rabbits and a goat
            bad.secondaries = [lib.secondaries[0], lib.secondaries[2], Secondary(name: "DAPI", dilution: 1000)]   // 488 rab, 488 rat, DAPI
            let r = panel(bad)
            print("Clashing set: \(r.verdict)", r.channels.map { "\($0.fluor.name)→\($0.label)" }.joined(separator: ", "))
            r.issues.forEach { print("  !", $0) }
            // a primary named with the wrong species: the maker's catalogue number wins
            var wrong = StainSet()
            var th = lib.primaries[7]; th.name = "TH (rab)"          // MAB318 is a mouse monoclonal
            wrong.primaries = [th, lib.primaries[1]]
            wrong.secondaries = [lib.secondaries[0], lib.secondaries[1]]
            let w = panel(wrong)
            print("Misnamed host: \(w.verdict)")
            w.issues.forEach { print("  !", $0) }
            var goatOnly = StainSet()
            goatOnly.primaries = [lib.primaries[1]]                 // FOXA2 (goat) with an anti-rabbit secondary only
            goatOnly.secondaries = [lib.secondaries[0]]
            let g = panel(goatOnly)
            print("FOXA2 with 488 rab: \(g.verdict)")
            g.issues.forEach { print("  !", $0) }
            return
        }
        launchObserver = NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
            SplashController.shared.showAtLaunch()
        }
        PlannerApp.main()
    }
}

/// Recreates the lab's 2026-11-11 #380/#381 sheet; used to check the output against the original.
func sampleExperiment() -> Experiment {
    var e = Experiment()
    let lib = Library.seed
    e.sets = [
        StainSet(primaries: [lib.primaries[0], lib.primaries[1]],
                 secondaries: [lib.secondaries[0], lib.secondaries[1]]),
        StainSet(primaries: [lib.primaries[2], lib.primaries[3]],
                 secondaries: [lib.secondaries[2], lib.secondaries[1]]),
    ]
    // fresh ids so sets never share row identity with the library
    for i in e.sets.indices {
        for j in e.sets[i].primaries.indices { e.sets[i].primaries[j].id = UUID() }
        for j in e.sets[i].secondaries.indices { e.sets[i].secondaries[j].id = UUID() }
    }
    var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 11
    e.date = Calendar.current.date(from: c)!
    c.month = 10; c.day = 23
    let day0 = Calendar.current.date(from: c)!
    e.samples = [Sample(code: "#380", name: "Large Scale", hasDay0: true, day0: day0, day: "14"),
                 Sample(code: "#381", name: "C2_Wnt_Esc_03", hasDay0: true, day0: day0, day: "14")]
    if CommandLine.arguments.contains("--custom-colors") {   // development check: custom well colours
        e.sets[0].colorHex = "FAD7E4"
        e.sets[1].colorHex = "1E4A83"
        e.wellText[12] = "ctl"
        e.wellText[24] = "ctl"
    }
    if CommandLine.arguments.contains("--clash") {   // development check: Corin (rat) given an anti-rabbit secondary
        e.sets[1].secondaries[0] = lib.secondaries[0]
        e.sets[1].secondaries[0].id = UUID()
    }
    if CommandLine.arguments.contains("--split-days") {   // development check: different Day 0 per experiment
        e.samples[1].day0 = Calendar.current.date(byAdding: .day, value: 3, to: day0)!
        e.samples[1].day = "11"
    }
    for (row, set) in [(1, e.sets[0]), (2, e.sets[1])] {
        for col in [0, 6, 7, 8, 9, 10, 11] { e.wells[row * 12 + col] = set.id }
    }
    e.wellText[0] = "C2 boost 4.0"
    e.wellText[5] = "PG\nconc. (pM)"
    for (k, v) in ["100", "56", "32", "18", "10", "0"].enumerated() { e.wellText[6 + k] = v }
    e.wellText[12 + 5] = "#381"
    e.leftLabels[1] = "#380"
    e.topLabels[0] = "#380 Large"
    e.topLabels[3] = "#381"
    e.topLabels[4] = "C2 Wnt_Esc_03"
    return e
}

struct PlannerApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        Window("ICC Plate Planner", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1080, idealWidth: 1360, minHeight: 640, idealHeight: 860)
                .onAppear {
                    if let note = Updater.shared.noteIfJustUpdated() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { store.showToast(note, icon: "arrow.down.circle") }
                    }
                    Updater.shared.checkAtLaunch()
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About ICC Plate Planner") { SplashController.shared.showAbout() }
                Button("Check for Updates…") { Updater.shared.check(userInitiated: true) }
                Toggle("Check for Updates Automatically", isOn: Binding(get: { Updater.automatic }, set: { Updater.automatic = $0 }))
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { store.undo() }.keyboardShortcut("z").disabled(store.undoCount == 0)
                Button("Redo") { store.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(store.redoCount == 0)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Experiment…") { store.confirmNew() }.keyboardShortcut("n")
                Divider()
                Button("Open Plate…") { store.openPlate() }.keyboardShortcut("o")
                Button("Save Plate As…") { store.savePlate() }.keyboardShortcut("s")
                Divider()
                Button("Export Excel…") { store.export() }.keyboardShortcut("e")
                Divider()
                Toggle("Animations", isOn: $store.animations)
                Toggle("Trackpad Feedback", isOn: $store.haptics)
                Toggle("Show Hologram", isOn: $store.showHologram)
                Toggle("Show Splash at Launch", isOn: Binding(get: { SplashController.enabledAtLaunch }, set: { SplashController.enabledAtLaunch = $0 }))
            }
        }
    }
}

// MARK: - State

enum Tool: Hashable { case paint(UUID), erase, text, tag(UUID), duplicate }

/// What the Duplicate tool copies: a single well, or a whole row at once.
enum DuplicateScope: Hashable { case well, row }

private struct SavedState: Codable {
    var exp: Experiment
    var settings: Settings
    var library: Library
}

// MARK: - Saved plates (.iccplate)

/// The on-disk plate format: readable JSON with a version, so future versions can keep loading it.
struct PlateFile: Codable {
    var app = "ICC Plate Planner"
    var version = 1
    var exp: Experiment
}

let plateFileType = UTType(exportedAs: "lab.icc.plate", conformingTo: .json)

func encodePlate(_ e: Experiment) throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try enc.encode(PlateFile(exp: e))
}

/// Reads a saved plate back. A file that does not hold a complete 96-well plate is rejected.
func decodePlate(_ data: Data) throws -> Experiment {
    var e = try JSONDecoder().decode(PlateFile.self, from: data).exp
    guard e.wells.count == 96, e.wellText.count == 96, e.wellTags.count == 96,
          e.leftLabels.count == 8, e.topLabels.count == 12 else {
        throw NSError(domain: "ICCPlatePlanner", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "That file does not contain a complete 96-well plate."])
    }
    e.migrateDay0()
    return e
}

final class Store: ObservableObject {
    @Published var exp: Experiment { didSet { recordUndo(oldValue); save(); fxAfterChange(oldValue) } }
    @Published var settings: Settings { didSet { save() } }
    @Published var library: Library { didSet { save() } }
    @Published var tool: Tool = .erase {
        didSet {
            if tool != .duplicate { duplicateSource = nil }
            if tool != oldValue { tap(.alignment) }
        }
    }
    @Published var selectedWell: Int? = nil
    /// Short message shown for a few seconds after saving, exporting or loading.
    @Published var toast: Toast? = nil
    /// Decorative motion on or off (also follows the Mac's Reduce Motion setting).
    @Published var animations: Bool = UserDefaults.standard.object(forKey: "animations") as? Bool ?? true {
        didSet { if persist { UserDefaults.standard.set(animations, forKey: "animations") } }
    }
    /// The confocal hologram over the selected stain's well (File menu).
    @Published var showHologram: Bool = UserDefaults.standard.object(forKey: "showHologram") as? Bool ?? true {
        didSet { if persist { UserDefaults.standard.set(showHologram, forKey: "showHologram") } }
    }
    /// Bumped when the selected stain's button is clicked again, to show its hologram now.
    @Published var hologramRequest = 0
    /// Wells painted or erased during the current drag, shown at once on the plate and committed to the
    /// plan when the drag ends: painting then redraws only the plate, not every card in the window.
    let paint = PaintBuffer()
    /// How many times each stain's chip has shaken (its pairing just went wrong).
    @Published var shakes: [UUID: Int] = [:]
    private var flyWork: [UUID: DispatchWorkItem] = [:]
    private var clashWork: DispatchWorkItem?
    private var lastVerdicts: [UUID: Verdict] = [:]
    private var clashCache: (sets: [StainSet], bad: Set<UUID>)?
    /// The stains with at least one pairing that cannot work (their wells show red on the plate).
    var clashingSets: Set<UUID> {
        if let c = clashCache, c.sets == exp.sets { return c.bad }
        let bad = Set(exp.sets.filter { panel($0).verdict == .problem }.map { $0.id })
        clashCache = (exp.sets, bad)
        return bad
    }
    /// Effects stay quiet while a plate is being loaded.
    var fxQuietUntil = Date.distantPast
    /// Well the Duplicate tool is copying (row scope copies its whole row); nil = pick one first.
    @Published var duplicateSource: Int? = nil
    @Published var duplicateScope: DuplicateScope = .well
    /// A light tick on the trackpad as wells fill and tools change.
    @Published var haptics: Bool = UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true {
        didSet { if persist { UserDefaults.standard.set(haptics, forKey: "haptics") } }
    }
    /// Whether the app is in front; long-running animations pause when it is not. Starts off until the
    /// app is actually activated (it can be launched in the background).
    @Published var appActive = false
    /// When the export confetti went off.
    @Published var confettiAt = Date.distantPast
    /// The stain whose wells stand out on the plate while the pointer rests on its card or legend row.
    @Published var spotlightSet: UUID? = nil
    /// Bumped to play the staining preview from the start.
    @Published var previewReplay = 0
    private var observers: [NSObjectProtocol] = []
    private var saveWork: DispatchWorkItem?
    private var dragErases: Bool? = nil
    /// What the current Duplicate-tool drag is doing: picking the source row, copying it, or cancelling the pick.
    private enum DupDrag { case setting, copying, clearing }
    private var dupDrag: DupDrag? = nil

    // Undo / redo: snapshots of the experiment. Changes made in quick succession (a drag across
    // wells, a burst of typing) count as one step.
    @Published private(set) var undoCount = 0
    @Published private(set) var redoCount = 0
    private var undoStack: [Experiment] = []
    private var redoStack: [Experiment] = []
    private var lastChange = Date.distantPast
    private var restoring = false
    var undoGrouping: TimeInterval = 0.5
    var persist = true

    private static var stateURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ICC Plate Planner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    init() {
        var merged = false
        if let d = try? Data(contentsOf: Self.stateURL),
           let s = try? JSONDecoder().decode(SavedState.self, from: d),
           s.exp.wells.count == 96, s.exp.wellText.count == 96, s.exp.wellTags.count == 96,
           s.exp.leftLabels.count == 8, s.exp.topLabels.count == 12 {
            var loaded = s.exp
            loaded.migrateDay0()
            var lib = s.library
            let seen = UserDefaults.standard.integer(forKey: "librarySeedVersion")
            if seen < 2 { lib.mergeSeed(); merged = true }
            if seen < 3 {
                for i in lib.secondaries.indices where Library.is488Default(lib.secondaries[i]) { lib.secondaries[i].dilution = 500 }
                for a in loaded.sets.indices {
                    for b in loaded.sets[a].secondaries.indices where Library.is488Default(loaded.sets[a].secondaries[b]) {
                        loaded.sets[a].secondaries[b].dilution = 500
                    }
                }
                merged = true
            }
            if seen < 4 {
                for i in lib.secondaries.indices where Library.is594gDefault(lib.secondaries[i]) { lib.secondaries[i].dilution = 500 }
                for a in loaded.sets.indices {
                    for b in loaded.sets[a].secondaries.indices where Library.is594gDefault(loaded.sets[a].secondaries[b]) {
                        loaded.sets[a].secondaries[b].dilution = 500
                    }
                }
                merged = true
            }
            if seen < 5 {
                // the department list gains the antibodies imported from the 2026-11-17 plate, and
                // the three secondaries the interim build set to 1:500 follow the sheet again (1:400)
                for i in lib.secondaries.indices where Library.isSecondary500FromSheet400(lib.secondaries[i]) { lib.secondaries[i].dilution = 400 }
                for a in loaded.sets.indices {
                    for b in loaded.sets[a].secondaries.indices where Library.isSecondary500FromSheet400(loaded.sets[a].secondaries[b]) {
                        loaded.sets[a].secondaries[b].dilution = 400
                    }
                }
                lib.mergeSeed()
                merged = true
            }
            exp = loaded; settings = s.settings; library = lib
        } else {
            // A saved file that cannot be read is kept as a backup instead of being overwritten.
            if FileManager.default.fileExists(atPath: Self.stateURL.path) {
                let stamp = Int(Date().timeIntervalSince1970)
                try? FileManager.default.copyItem(at: Self.stateURL, to: Self.stateURL.deletingLastPathComponent().appendingPathComponent("state.unreadable-\(stamp).json"))
            }
            exp = .starter; settings = Settings(); library = .seed
        }
        UserDefaults.standard.set(Library.seedVersion, forKey: "librarySeedVersion")
        if let first = exp.sets.first { tool = .paint(first.id) }
        if merged { save() }   // keep the newly added department antibodies
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.appActive = true })
        observers.append(nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.appActive = false
            self?.writeNow()
        })
        observers.append(nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.writeNow() })
        DispatchQueue.main.async { [weak self] in self?.appActive = NSApp?.isActive ?? false }
    }

    /// A store that never reads or writes the saved file (development checks only).
    init(inMemory experiment: Experiment) {
        exp = experiment; settings = Settings(); library = .seed
        persist = false
        haptics = false
        if let first = exp.sets.first { tool = .paint(first.id) }
    }

    /// Saving waits until changes pause: a drag across wells or a burst of typing is written once, not
    /// once per well or keystroke (writing the file on every change was one source of lag). Leaving or
    /// quitting the app writes at once.
    private func save() {
        guard persist else { return }
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.writeNow() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    func writeNow() {
        saveWork?.cancel()
        saveWork = nil
        guard persist else { return }
        let s = SavedState(exp: exp, settings: settings, library: library)
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: Self.stateURL, options: .atomic) }
    }

    private func recordUndo(_ old: Experiment) {
        guard !restoring, old != exp else { return }
        let now = Date()
        if undoStack.isEmpty || now.timeIntervalSince(lastChange) > undoGrouping {
            undoStack.append(old)
            if undoStack.count > 100 { undoStack.removeFirst() }
            undoCount = undoStack.count
        }
        lastChange = now
        if !redoStack.isEmpty { redoStack.removeAll(); redoCount = 0 }
    }

    func undo() {
        NSApp?.keyWindow?.makeFirstResponder(nil)   // commit whatever is being typed first
        guard let previous = undoStack.popLast() else { return }
        tap(.generic)
        restoring = true
        redoStack.append(exp)
        exp = previous
        restoring = false
        afterRestore()
    }

    func redo() {
        NSApp?.keyWindow?.makeFirstResponder(nil)
        guard let next = redoStack.popLast() else { return }
        restoring = true
        undoStack.append(exp)
        exp = next
        restoring = false
        afterRestore()
    }

    private func afterRestore() {
        undoCount = undoStack.count
        redoCount = redoStack.count
        lastChange = .distantPast
        validateTool()
    }

    /// The selected tool may point at a stain or sample that no longer exists.
    private func validateTool() {
        switch tool {
        case .paint(let id) where !exp.sets.contains(where: { $0.id == id }),
             .tag(let id) where !exp.samples.contains(where: { $0.id == id }):
            tool = exp.sets.first.map { .paint($0.id) } ?? .erase
        default: break
        }
    }

    // Plate interaction
    func touch(_ w: Int) {
        guard (0..<96).contains(w) else { return }
        switch tool {
        case .paint(let id):
            guard exp.sets.contains(where: { $0.id == id }) else { validateTool(); return }
            let current = paint.value(w, exp.wells[w])
            if dragErases == nil { dragErases = (current == id) }
            let new: UUID? = dragErases! ? nil : id
            if dragErases! && current != id { return }
            if current != new {
                paint.set(w, new)
                tap(.alignment)
                if new != nil { fxPaint(w, id) }
            }
        case .erase:
            if paint.value(w, exp.wells[w]) != nil { paint.set(w, nil); tap(.alignment) }
        case .text:
            if selectedWell != w { selectedWell = w }
        case .tag(let sampleID):
            // stamp this experiment onto the well; clicking a well that already carries it removes it
            guard let sample = exp.samples.first(where: { $0.id == sampleID }), !sample.tag.isEmpty else {
                validateTool()
                return
            }
            if dragErases == nil { dragErases = (exp.wellTags[w] == sampleID) }
            if dragErases! {
                if exp.wellTags[w] == sampleID { exp.wellTags[w] = nil }
            } else if exp.wellTags[w] != sampleID || !exp.wellText[w].isEmpty {
                var e = exp
                e.wellTags[w] = sampleID
                e.wellText[w] = ""
                exp = e
            }
        case .duplicate:
            // Click a well to pick it as the source; then click or drag across others to give them
            // the same stain and label (row scope: the whole row). Clicking the source again stops.
            let same: Bool
            if let src = duplicateSource {
                same = duplicateScope == .row ? (src / 12 == w / 12) : (src == w)
            } else { same = false }
            if dupDrag == nil {
                if duplicateSource == nil {
                    dupDrag = .setting
                    duplicateSource = w
                } else if same {
                    dupDrag = .clearing
                    duplicateSource = nil
                } else {
                    dupDrag = .copying
                    duplicateCopy(to: w)
                }
            } else if dupDrag != .clearing, !same {
                // dragging from the source across others copies as it goes
                dupDrag = .copying
                duplicateCopy(to: w)
            }
        }
    }

    private func duplicateCopy(to w: Int) {
        guard let src = duplicateSource else { return }
        switch duplicateScope {
        case .well: copyWell(from: src, to: w)
        case .row: copyRow(from: src / 12, to: w / 12)
        }
    }

    /// Copies one well — stain, typed label and stamped tag — onto another well.
    func copyWell(from src: Int, to dst: Int) {
        guard (0..<96).contains(src), (0..<96).contains(dst), src != dst else { return }
        var e = exp
        e.wells[dst] = e.wells[src]
        e.wellText[dst] = e.wellText[src]
        e.wellTags[dst] = e.wellTags[src]
        e.blockingOverride = nil   // stained wells may have changed, so the buffer goes back to automatic
        exp = e
    }

    /// Copies a whole row — stains, typed labels, stamped tags and the row label — onto another row.
    func copyRow(from src: Int, to dst: Int) {
        guard (0..<8).contains(src), (0..<8).contains(dst), src != dst else { return }
        var e = exp
        for j in 0..<12 {
            e.wells[dst * 12 + j] = e.wells[src * 12 + j]
            e.wellText[dst * 12 + j] = e.wellText[src * 12 + j]
            e.wellTags[dst * 12 + j] = e.wellTags[src * 12 + j]
        }
        e.leftLabels[dst] = e.leftLabels[src]
        e.blockingOverride = nil   // stained wells may have changed, so the buffer goes back to automatic
        exp = e
    }

    /// A copy of a stain set: same antibodies and settings, new identity, no wells of its own yet.
    func duplicateSet(_ id: UUID) {
        guard let i = exp.sets.firstIndex(where: { $0.id == id }) else { return }
        var copy = exp.sets[i]
        copy.id = UUID()
        for j in copy.primaries.indices { copy.primaries[j].id = UUID() }
        for j in copy.secondaries.indices { copy.secondaries[j].id = UUID() }
        var e = exp
        e.sets.insert(copy, at: i + 1)
        exp = e
        tool = .paint(copy.id)
    }

    /// Typing a label into a well replaces any experiment tag stamped there.
    func setLabel(_ w: Int, _ text: String) {
        guard (0..<96).contains(w), text != exp.label(w) else { return }
        var e = exp
        e.wellTags[w] = nil
        e.wellText[w] = text
        exp = e
    }

    /// A new sample starts with its Day 0 already filled in: the same date as the sample above it
    /// (experiments on one plate usually share it), or today for the first one.
    func addSample() {
        var s = Sample()
        s.hasDay0 = true
        if let last = exp.samples.last(where: { $0.hasDay0 }) { s.day0 = last.day0 }
        exp.samples.append(s)
    }

    func removeSample(_ id: UUID) {
        guard exp.samples.count > 1 else { return }
        var e = exp
        e.samples.removeAll { $0.id == id }
        for w in e.wellTags.indices where e.wellTags[w] == id { e.wellTags[w] = nil }
        exp = e
        validateTool()
    }

    func endDrag() {
        dragErases = nil; dupDrag = nil
        FxCenter.shared.view?.pipetteAway()
        commitPaint()
    }

    /// The wells painted during the drag go into the plan in one change (one undo step).
    func commitPaint() {
        let changes = paint.take()
        guard !changes.isEmpty else { return }
        var e = exp
        for (w, id) in changes { e.wells[w] = id }
        e.blockingOverride = nil   // stained wells changed, so the buffer goes back to automatic
        exp = e
    }

    /// Changing which wells are stained puts the blocking buffer back on automatic,
    /// so a number typed for an earlier layout never lingers.
    private func setWell(_ w: Int, _ id: UUID?) {
        var e = exp
        e.wells[w] = id
        e.blockingOverride = nil
        exp = e
        tap(.alignment)
    }

    /// A new stain set starts blank: no antibodies are pre-filled, the user adds them.
    func addSet() {
        let s = StainSet()
        exp.sets.append(s)
        tool = .paint(s.id)
    }

    func removeSet(_ id: UUID) {
        var e = exp
        for i in e.wells.indices where e.wells[i] == id { e.wells[i] = nil }
        e.sets.removeAll { $0.id == id }
        e.blockingOverride = nil
        exp = e
        if tool == .paint(id) { tool = exp.sets.first.map { .paint($0.id) } ?? .erase }
    }

    func clearPlate() {
        var e = exp
        e.wells = Array(repeating: nil, count: 96)
        e.wellText = Array(repeating: "", count: 96)
        e.wellTags = Array(repeating: nil, count: 96)
        e.leftLabels = Array(repeating: "", count: 8)
        e.topLabels = Array(repeating: "", count: 12)
        e.blockingOverride = nil
        exp = e
        selectedWell = nil
        duplicateSource = nil
    }

    func confirmNew() {
        let a = NSAlert()
        a.messageText = "Start a new experiment?"
        a.informativeText = "The plate, labels and samples are cleared. Your antibody panels are kept. You can undo this with ⌘Z."
        a.addButton(withTitle: "New Experiment")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        newExperiment()
    }

    func newExperiment() {
        var e = exp
        e.date = Date(); e.samples = [Sample()]; e.day = ""; e.hasDay0 = false; e.blockingOverride = nil
        for i in e.sets.indices { e.sets[i].volumeOverride = nil }
        exp = e
        clearPlate()
        tool = exp.sets.first.map { .paint($0.id) } ?? .erase
    }

    func confirmClearPlate() {
        let a = NSAlert()
        a.messageText = "Clear the whole plate?"
        a.informativeText = "All painted wells and labels are removed. You can undo this with ⌘Z."
        a.addButton(withTitle: "Clear Plate")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { clearPlate() }
    }

    func showToast(_ text: String, icon: String = "checkmark") {
        let t = Toast(text: text, icon: icon)
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) { [weak self] in
            if self?.toast?.id == t.id { self?.toast = nil }
        }
    }

    private func errorAlert(_ title: String, _ error: Error) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = error.localizedDescription
        a.runModal()
    }

    /// Saves the whole plate (samples, stains, wells, labels) as an .iccplate file to load again later.
    func savePlate() {
        NSApp.keyWindow?.makeFirstResponder(nil)   // commit any field still being edited
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(exp.fileName.dropLast(5)) + ".iccplate"
        panel.allowedContentTypes = [plateFileType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try encodePlate(exp).write(to: url, options: .atomic)
            showToast("Plate saved. Cryopreserved for later.")
        } catch {
            errorAlert("Could not save the plate", error)
        }
    }

    /// Loads a plate saved earlier. The current plate is not lost: loading is one undo step (⌘Z).
    func openPlate() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [plateFileType, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let loaded = try decodePlate(Data(contentsOf: url))
            lastChange = .distantPast   // loading always starts a new undo group
            fxQuietUntil = Date().addingTimeInterval(1.2)
            exp = loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.fxThaw() }
            selectedWell = nil
            duplicateSource = nil
            validateTool()
            showToast("Plate thawed and ready.")
        } catch {
            errorAlert("Could not open the plate", error)
        }
    }

    /// Whether any well holds a stain that still exists.
    var hasStainedWells: Bool { exp.wells.contains { w in w.map { id in exp.sets.contains { $0.id == id } } ?? false } }

    func export() {
        NSApp.keyWindow?.makeFirstResponder(nil)   // commit any field still being edited
        let panel = NSSavePanel()
        panel.nameFieldStringValue = exp.fileName
        if let t = UTType(filenameExtension: "xlsx") { panel.allowedContentTypes = [t] }
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try buildWorkbook(exp, settings).write(to: url, options: .atomic)
            library.remember(exp.sets)
            tap(.levelChange)
            // the export window always follows: the microscope acquires the plate (straight to the end with
            // Animations off or nothing stained), then Open in Excel, Show in Finder or Done is the user's choice
            ExportScanController.shared.present(self, url: url) { [weak self] in
                self?.confettiAt = Date()
                self?.showToast(exportLines.randomElement() ?? "Exported.")
            }
        } catch {
            errorAlert("Could not save the Excel file", error)
        }
    }
}

// MARK: - Offscreen snapshots (development checks)

/// The splash as it looks `t` seconds in.
func splashSnapshot(_ path: String, at t: Double) {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let about = CommandLine.arguments.contains("--about")
    let view = SplashView(about: about, motion: true, start: Date().addingTimeInterval(1 - t)) {}
    let host = NSHostingView(rootView: view)
    let win = NSWindow(contentRect: NSRect(origin: .zero, size: SplashView.size), styleMask: [.borderless], backing: .buffered, defer: false)
    win.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

/// The staining preview `t` seconds into the protocol (--empty: the demo; --set 2: the second stain).
func previewSnapshot(_ path: String, at t: Double) {
    _ = NSApplication.shared
    let a = CommandLine.arguments
    let store = Store(inMemory: a.contains("--empty") ? Experiment() : sampleExperiment())
    if let i = a.firstIndex(of: "--set"), a.count > i + 1, let k = Int(a[i + 1]), k >= 1, k <= store.exp.sets.count {
        store.tool = .paint(store.exp.sets[k - 1].id)
    }
    let size = CGSize(width: 740, height: 300)
    let v = StainingPreviewView(frame: NSRect(origin: .zero, size: size))
    v.setInfo(store.previewInfo, replay: 0)
    v.layout()
    v.preview(at: t)
    let scale: CGFloat = 2
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.scaleBy(x: scale, y: scale)
    v.layer?.render(in: ctx)
    if let img = ctx.makeImage() {
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

func snapshot(_ path: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let store = Store(inMemory: CommandLine.arguments.contains("--empty") ? Experiment() : sampleExperiment())
    if let i = CommandLine.arguments.firstIndex(of: "--plate"), CommandLine.arguments.count > i + 1,
       let d = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[i + 1])), let e = try? decodePlate(d) {
        store.exp = e
    }
    if CommandLine.arguments.contains("--toast") { store.toast = Toast(text: exportLines[0], icon: "checkmark") }
    if let i = CommandLine.arguments.firstIndex(of: "--spotlight"), CommandLine.arguments.count > i + 1, let k = Int(CommandLine.arguments[i + 1]), k >= 1, k <= store.exp.sets.count {
        store.spotlightSet = store.exp.sets[k - 1].id
    }
    if store.exp.samples.count > 1 { store.tool = .tag(store.exp.samples[1].id) }
    if CommandLine.arguments.contains("--dup") {   // development check: duplicate tool with a source well
        store.tool = .duplicate
        store.duplicateSource = 17   // B6
    }
    let a = CommandLine.arguments
    var size = NSSize(width: 1320, height: 860)
    if let i = a.firstIndex(of: "--size"), a.count > i + 2, let w = Double(a[i + 1]), let h = Double(a[i + 2]) { size = NSSize(width: w, height: h) }
    let host = NSHostingView(rootView: ContentView().environmentObject(store).frame(width: size.width, height: size.height))
    let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
    win.appearance = NSAppearance(named: .aqua)
    win.contentView = host
    if let i = a.firstIndex(of: "--holo"), a.count > i + 2, let k = Int(a[i + 1]), let t = Double(a[i + 2]), k >= 1, k <= store.exp.sets.count {
        // the hologram over stain k, `t` seconds into the protocol
        store.tool = .paint(store.exp.sets[k - 1].id)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(HoloController.dwell + 0.9))
        func find(_ v: NSView) -> StainingPreviewView? { (v as? StainingPreviewView) ?? v.subviews.lazy.compactMap(find).first }
        find(host)?.preview(at: t)
    }
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}


// MARK: - Lag check (development)

/// The real window with a saved plate, through each moving part: CPU, the cost of each tick on the shared
/// clock, and main-thread stalls (frames the screen would wait for).
func lagCheck(_ platePath: String) {
    let a = CommandLine.arguments
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let store = Store(inMemory: sampleExperiment())
    if let d = try? Data(contentsOf: URL(fileURLWithPath: platePath)), let e = try? decodePlate(d) { store.exp = e }
    store.tool = .erase
    let host = NSHostingView(rootView: ContentView().environmentObject(store).frame(width: 1360, height: 900))
    let win = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1360, height: 900), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    win.contentView = host
    win.orderFrontRegardless()
    store.appActive = true
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    var ticks: [Double] = [], gaps: [Double] = []
    AmbientClock.probe = { ticks.append($0) }
    var lastBeat = CACurrentMediaTime()
    let beat = Timer(timeInterval: 1.0 / 120, repeats: true) { _ in
        let now = CACurrentMediaTime(); gaps.append((now - lastBeat) * 1000); lastBeat = now
    }
    beat.tolerance = 0
    RunLoop.main.add(beat, forMode: .common)
    func cpu() -> Double {
        var r = rusage(); getrusage(RUSAGE_SELF, &r)
        return Double(r.ru_utime.tv_sec + r.ru_stime.tv_sec) + Double(r.ru_utime.tv_usec + r.ru_stime.tv_usec) / 1e6
    }
    func phase(_ name: String, _ secs: Double, _ start: () -> Void = {}) {
        ticks = []; gaps = []; lastBeat = CACurrentMediaTime()
        let c0 = cpu(), t0 = Date()
        start()
        var series: [String] = []
        var cPrev = c0, tPrev = Date()
        while Date().timeIntervalSince(t0) < secs {
            RunLoop.main.run(until: min(t0.addingTimeInterval(secs), tPrev.addingTimeInterval(0.5)))
            let c = cpu(), now = Date()
            series.append(String(format: "%.0f", (c - cPrev) / now.timeIntervalSince(tPrev) * 100))
            cPrev = c; tPrev = now
        }
        if a.contains("--series") { print("   CPU every 0.5 s:", series.joined(separator: " ")) }
        let wall = Date().timeIntervalSince(t0), used = cpu() - c0
        let tickAvg = ticks.isEmpty ? 0 : ticks.reduce(0, +) / Double(ticks.count)
        let hitches = gaps.filter { $0 > 34 }
        print(String(format: "%@: CPU %.1f%% · clock %.1f ticks/s, avg %.2f ms, max %.2f ms · main-thread stalls >34 ms: %d (worst %.0f ms)",
                     name, used / wall * 100, Double(ticks.count) / wall, tickAvg, ticks.max() ?? 0, hitches.count, gaps.max() ?? 0))
    }
    if a.contains("--isolate") {
        phase("idle (3 s)", 3)
        phase("tool change only: Label tool (3 s)", 3) { store.tool = .text }
        phase("type a well label (3 s)", 3) { store.setLabel(0, "x") }
        phase("tilt, no animation (3 s)", 3) {
            guard let tilt = TiltModel.current else { return }
            let t0 = Date()
            let move = Timer(timeInterval: 1.0 / 60, repeats: true) { t in
                let e = Date().timeIntervalSince(t0); if e > 2.8 { t.invalidate(); return }
                tilt.x = CGFloat(sin(e * 2.1)); tilt.y = CGFloat(cos(e * 1.7)); tilt.lit = true
            }
            RunLoop.main.add(move, forMode: .common)
        }
        phase("tilt settles (2 s)", 2)
        beat.invalidate()
        return
    }
    if a.contains("--scroll-bench") {
        // scroll the stain cards up and down as a trackpad would, 60 times a second
        func scrollViews(_ v: NSView) -> [NSScrollView] { ((v as? NSScrollView).map { [$0] } ?? []) + v.subviews.flatMap(scrollViews) }
        let left = scrollViews(host).filter { $0.frame.width < 700 && ($0.documentView?.frame.height ?? 0) > $0.frame.height }.first
        guard let sv = left else { print("no scroll view"); return }
        print("scrolling a column \(Int(sv.documentView?.frame.height ?? 0)) pt tall")
        var t = 0.0
        let tick = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            t += 1.0 / 60
            let maxY = max(0, (sv.documentView?.frame.height ?? 0) - sv.contentView.bounds.height)
            let y = (1 - cos(t * 0.9)) / 2 * maxY
            sv.contentView.scroll(to: NSPoint(x: 0, y: y))
            sv.reflectScrolledClipView(sv.contentView)
        }
        RunLoop.main.add(tick, forMode: .common)
        phase("scrolling the stain cards (10 s)", 10)
        tick.invalidate(); beat.invalidate()
        return
    }
    if a.contains("--paint-bench") {
        // paint and clear rows continuously, for profiling
        store.tool = .paint(store.exp.sets[0].id)
        var n = 0
        let t = Timer(timeInterval: 0.08, repeats: true) { _ in
            if ProcessInfo.processInfo.environment["ICC_BENCH"] == "longdrag" {
                // one long drag across the whole plate, never released
                if n == 0 { store.tool = .paint(store.exp.sets[0].id) }
                store.touch(n % 96 == 0 && n > 0 ? 0 : n % 96)
                n += 1
                return
            }
            // paint a row in one drag, then erase it in the next, as a person would
            let w = 84 + n % 12
            if n % 12 == 0 { store.tool = n % 24 < 12 ? .paint(store.exp.sets[0].id) : .erase }
            store.touch(w)
            if n % 12 == 11 { store.endDrag() }
            n += 1
        }
        RunLoop.main.add(t, forMode: .common)
        phase("painting continuously (12 s)", 12)
        t.invalidate(); beat.invalidate()
        return
    }
    phase("plate idle, no stain picked (8 s)", 8)
    phase("hologram scanning over a stain (14 s)", 14) { store.tool = .paint(store.exp.sets[min(2, store.exp.sets.count - 1)].id) }
    phase("same stain picked again within the cooldown: stays away (3 s)", 3) {
        store.tool = .erase
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        store.tool = .paint(store.exp.sets[min(2, store.exp.sets.count - 1)].id)
    }
    phase("pointer moving over the plate: tilt (5 s)", 5) {
        guard let tilt = TiltModel.current else { return }
        let t0 = Date()
        let move = Timer(timeInterval: 1.0 / 60, repeats: true) { t in
            let e = Date().timeIntervalSince(t0)
            if e > 4.8 { t.invalidate(); return }
            tilt.x = CGFloat(sin(e * 2.1)); tilt.y = CGFloat(cos(e * 1.7)); tilt.lit = true
        }
        RunLoop.main.add(move, forMode: .common)
    }
    phase("antibodies docking after an edit (3 s)", 3) {
        store.tool = .erase
        if !store.exp.sets.isEmpty, !store.exp.sets[0].secondaries.isEmpty {
            let old = store.exp.sets[0].secondaries[0].name
            store.exp.sets[0].secondaries[0].name = "488 g"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { store.exp.sets[0].secondaries[0].name = old }
        }
    }
    phase("spotlight a stain, then let go (3 s)", 3) {
        store.spotlightSet = store.exp.sets[0].id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { store.spotlightSet = nil }
    }
    phase("antibodies fly to a stain's wells (3 s)", 3) {
        store.fxFly(store.exp.sets[0].id)
    }
    phase("frost melts off an opened plate (4 s)", 4) { store.fxThaw() }
    phase("painting a row with the pipette (3 s)", 3) {
        store.tool = .paint(store.exp.sets[0].id)
        for (n, w) in (84..<96).enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08 * Double(n)) { store.touch(w) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            store.endDrag()
            for w in 84..<96 { store.exp.wells[w] = nil }
        }
    }
    phase("export: the acquisition window (7 s)", 7) {
        ExportScanController.shared.present(store, url: URL(fileURLWithPath: NSTemporaryDirectory() + "lagcheck.xlsx")) { store.confettiAt = Date() }
    }
    phase("app in the background (4 s)", 4) { store.tool = .paint(store.exp.sets[0].id); store.appActive = false }
    beat.invalidate()
}


// MARK: - Effects across the window (Fx.swift)

extension Store {
    /// After every change to the plan: antibodies fly to a stain whose antibodies changed, and a stain
    /// whose pairing has just gone wrong sounds the alarm.
    func fxAfterChange(_ old: Experiment) {
        if lastVerdicts.isEmpty {
            // the first change since launch: what each stain's pairing was before it
            for set in old.sets { lastVerdicts[set.id] = panel(set).verdict }
        }
        let quiet = Date() < fxQuietUntil
        if !quiet {
            for set in exp.sets {
                guard let o = old.sets.first(where: { $0.id == set.id }) else { continue }
                func names(_ s: StainSet) -> [String] { s.primaries.map { $0.name } + ["|"] + s.secondaries.map { $0.name } }
                guard names(o) != names(set) else { continue }
                let added = set.primaries.count + set.secondaries.count > o.primaries.count + o.secondaries.count
                let id = set.id
                flyWork[id]?.cancel()
                let w = DispatchWorkItem { [weak self] in self?.fxFly(id) }
                flyWork[id] = w
                // typing a name waits for a pause; adding an antibody flies at once
                DispatchQueue.main.asyncAfter(deadline: .now() + (added ? 0.25 : 1.0), execute: w)
            }
        }
        clashWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.fxCheckClash(quiet: quiet) }
        clashWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    private func wellsOf(_ id: UUID) -> [Int] { (0..<96).filter { exp.wells[$0] == id } }

    func fxFly(_ id: UUID) {
        let fx = FxCenter.shared
        guard motion, fx.usable, let k = exp.sets.firstIndex(where: { $0.id == id }), let card = fx.cardFrames[id] else { return }
        let wells = wellsOf(id)
        guard !wells.isEmpty else { return }
        let step = max(1, wells.count / 8)
        let targets = stride(from: 0, to: wells.count, by: step).prefix(8).map { fx.wellCenter(wells[$0]) }
        // one colour per pairing: its dye when the secondary can find the primary, red when it cannot
        let combos = panel(exp.sets[k]).combos
        let colours = combos.map { $0.verdict == .problem ? "BAD" : ($0.fluor?.hex ?? fillHex(exp.sets[k], k)) }
        fx.view?.fly(from: CGPoint(x: card.maxX - 70, y: card.minY + 46), to: targets, hexes: colours.isEmpty ? [fillHex(exp.sets[k], k)] : colours)
    }

    func fxCheckClash(quiet: Bool) {
        var now: [UUID: Verdict] = [:]
        for set in exp.sets { now[set.id] = panel(set).verdict }
        defer { lastVerdicts = now }
        guard !quiet, motion else { return }
        let fx = FxCenter.shared
        for (id, v) in now where v == .problem {
            guard let before = lastVerdicts[id], before != .problem else { continue }
            shakes[id, default: 0] += 1
            tap(.generic)
            if fx.usable { fx.view?.alarm(at: wellsOf(id).map { fx.wellCenter($0) }, cw: fx.cw, ch: fx.ch) }
        }
    }

    func fxThaw() {
        let fx = FxCenter.shared
        guard motion, fx.usable else { return }
        fx.view?.thaw(grid: fx.gridFrame, cw: fx.cw, ch: fx.ch)
    }

    func fxPaint(_ w: Int, _ id: UUID) {
        let fx = FxCenter.shared
        guard motion, fx.usable, let k = exp.sets.firstIndex(where: { $0.id == id }) else { return }
        let hex = fillHex(exp.sets[k], k)
        let dye = panel(exp.sets[k]).channels.first { !$0.fluor.counterstain }?.fluor.hex ?? hex
        fx.view?.pipette(over: fx.gridFrame, col: w % 12, row: w / 12, cw: fx.cw, ch: fx.ch, hex: dye)
        fx.view?.drop(at: fx.wellCenter(w), hex: hex, ch: fx.ch)
        let accent = setAccentHex(exp.sets[k], k)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { fx.view?.pop(at: fx.wellCenter(w), fill: hex, accent: accent, cw: fx.cw, ch: fx.ch) }
    }
}


/// Development: the real window, photographed part-way through the antibody flight and the frost thaw.
func fxShot(_ platePath: String, _ outPrefix: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let store = Store(inMemory: sampleExperiment())
    if let d = try? Data(contentsOf: URL(fileURLWithPath: platePath)), let e = try? decodePlate(d) { store.exp = e }
    store.tool = .erase
    let host = NSHostingView(rootView: ContentView().environmentObject(store).frame(width: 1360, height: 900))
    let win = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1360, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host
    win.orderFrontRegardless()
    store.appActive = true
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    func shot(_ name: String) {
        guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(win.windowNumber), [.boundsIgnoreFraming, .bestResolution]) else { print("no capture"); return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: outPrefix + name + ".png"))
    }
    let fx = FxCenter.shared
    print("grid frame:", fx.gridFrame, "fx view:", fx.view?.frame ?? .zero, "flipped:", fx.view?.isFlipped ?? false, "superview flipped:", fx.view?.superview?.isFlipped ?? false)
    // the last stain (lowest wells) flies
    let id = store.exp.sets[min(4, store.exp.sets.count - 1)].id
    print("its wells:", (0..<96).filter { store.exp.wells[$0] == id }.map { "\(rowLetters[$0 / 12])\($0 % 12 + 1)" })
    store.fxFly(id)
    RunLoop.main.run(until: Date().addingTimeInterval(0.75))
    shot("fly")
    RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    store.fxThaw()
    RunLoop.main.run(until: Date().addingTimeInterval(0.35))
    shot("frost1")
    RunLoop.main.run(until: Date().addingTimeInterval(0.9))
    shot("frost2")
    // a pairing goes wrong: Stain 1's rabbit primary given an anti-mouse 488
    if !store.exp.sets.isEmpty, !store.exp.sets[0].secondaries.isEmpty {
        let before = store.exp.sets[0].secondaries[0].name
        store.exp.sets[0].secondaries[0].name = "488 m"
        print("Stain 1 now:", panel(store.exp.sets[0]).verdict, "· shakes:", store.shakes[store.exp.sets[0].id] ?? 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.62))
        print("after the check:", "shakes:", store.shakes[store.exp.sets[0].id] ?? 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        shot("clash")
        RunLoop.main.run(until: Date().addingTimeInterval(1.6))
        shot("clashstill")                  // after the pulse: the wells stay outlined in red
        store.fxFly(store.exp.sets[0].id)    // antibodies for the wrong pairing fly red
        RunLoop.main.run(until: Date().addingTimeInterval(1.05))
        shot("clashfly")
        store.exp.sets[0].secondaries[0].name = before
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    }
    // painting row H with the pipette
    store.tool = .paint(store.exp.sets[0].id)
    for (n, w) in (84..<90).enumerated() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * Double(n)) { store.touch(w) }
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    shot("pipette")
    store.endDrag()
    for w in 84..<90 { store.exp.wells[w] = nil }
    store.tool = .erase
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    // pointing at Stain 2: its wells stay lit, the others sink
    store.spotlightSet = store.exp.sets[min(1, store.exp.sets.count - 1)].id
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    shot("spot")
    store.spotlightSet = nil
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    // the hologram plays and the room dims
    store.tool = .paint(store.exp.sets[min(2, store.exp.sets.count - 1)].id)
    RunLoop.main.run(until: Date().addingTimeInterval(HoloController.dwell + 1.4))
    print("hologram shown:", HoloController.shared.shown != nil)
    shot("dim")
    store.tool = .erase
    RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    // the export window, part-way through the scan
    ExportScanController.shared.present(store, url: URL(fileURLWithPath: NSTemporaryDirectory() + "fxshot.xlsx")) {}
    RunLoop.main.run(until: Date().addingTimeInterval(2.6))
    if let w = NSApp.windows.first(where: { $0 !== win && $0.isVisible }),
       let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: outPrefix + "export.png"))
    }
    ExportScanController.shared.close()
}


/// The wells changed by the drag in progress (nil = erased), observed only by the plate's grid.
final class PaintBuffer: ObservableObject {
    @Published private(set) var wells: [Int: UUID?] = [:]
    func value(_ w: Int, _ committed: UUID?) -> UUID? { wells[w] ?? committed }
    func set(_ w: Int, _ id: UUID?) { wells[w] = .some(id) }
    func take() -> [Int: UUID?] {
        let out = wells
        if !wells.isEmpty { wells = [:] }
        return out
    }
}


/// Development: every primary host against every secondary target, by short name and by product name,
/// plus the cases that must fail; prints any verdict that is not what it should be.
func pairQC() {
    let hosts: [(String, String, String)] = [   // species, the lab's short form, the product-name form
        ("rabbit", "rab", "Rabbit"), ("goat", "g", "Goat"), ("rat", "rat", "Rat"), ("mouse", "ms", "Mouse"),
        ("sheep", "sheep", "Sheep"), ("chicken", "chk", "Chicken"), ("guinea pig", "gp", "Guinea Pig"),
    ]
    var checked = 0, wrong: [String] = []
    for p in hosts {
        for t in hosts {
            for style in ["short", "product", "product name", "goat-raised"] {
                var set = StainSet()
                set.primaries = [Antibody(name: "MARKERX (\(p.1))", dilution: 500)]
                var q: Secondary
                switch style {
                case "short": q = Secondary(name: "488 \(t.1)", dilution: 500)
                case "product":                                   // a short name, the maker's name saved behind it
                    q = Secondary(name: "488 donkey", dilution: 500)
                    q.detail = "Donkey anti-\(t.2) IgG (H+L), Alexa Fluor 488"
                case "product name": q = Secondary(name: "Donkey anti-\(t.2) IgG Alexa Fluor 488", dilution: 500)
                default: q = Secondary(name: "Goat anti-\(t.2) 488", dilution: 500)
                }
                if style == "goat-raised" && (t.0 == "goat" || p.0 == "goat") { continue }   // a goat secondary is not used on goat
                set.secondaries = [q]
                let r = panel(set)
                let combo = r.combos.first?.verdict
                let should: Verdict = p.0 == t.0 ? .ok : .problem
                checked += 1
                if combo != should { wrong.append("\(p.0) primary + anti-\(t.0) (\(style)): got \(String(describing: combo)), expected \(should)") }
                // a stain with a wrong pairing is the one whose wells turn red
                if (r.verdict == .problem) != (should == .problem) { wrong.append("\(p.0)/\(t.0) (\(style)): stain verdict \(r.verdict)") }
            }
        }
    }
    func one(_ prims: [String], _ secs: [String]) -> PanelReport {
        var set = StainSet()
        set.primaries = prims.map { Antibody(name: $0, dilution: 500) }
        set.secondaries = secs.map { Secondary(name: $0, dilution: 500) }
        return panel(set)
    }
    let cases: [(String, [String], [String], Verdict)] = [
        ("two rabbit primaries with one anti-rabbit", ["A (rab)", "B (rab)"], ["488 rab"], .problem),
        ("two secondaries on the same dye", ["A (rab)", "B (g)"], ["488 rab", "488 g"], .problem),
        ("goat primary with no secondary for goat", ["A (g)"], ["488 rab"], .problem),
        ("the lab's Stain 1", ["LMX1A/B (rab)", "FOXA2 (g)"], ["488 rab", "594 g"], .ok),
        ("the lab's Stain 2", ["Corin (rat)", "OTX2 (g)"], ["488 rat", "594 g"], .ok),
        ("the lab's Stain 5", ["Pitx2 (sheep)", "LMX1A/B (rab)", "TH (mouse)"], ["488 sheep", "594 rab", "647 ms"], .ok),
        ("FOXA2 (goat) with an anti-rabbit 594", ["LMX1A/B (rab)", "FOXA2 (g)"], ["488 rab", "594 rab"], .problem),
        ("TH (mouse) with an anti-rabbit 488", ["TH (mouse)", "Barhl1 (rab)"], ["488 rab", "594 rab"], .problem),
        ("with DAPI as a counterstain", ["A (rab)"], ["488 rab", "DAPI"], .ok),
    ]
    for c in cases {
        let r = one(c.1, c.2)
        checked += 1
        if r.verdict != c.3 { wrong.append("\(c.0): got \(r.verdict), expected \(c.3) · \(r.issues.joined(separator: " | "))") }
    }
    print("pairings checked: \(checked), wrong verdicts: \(wrong.count)")
    wrong.forEach { print("  ✗", $0) }
}
