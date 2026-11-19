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
            let data = buildWorkbook(sampleExperiment(), Settings())
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
    @Published var exp: Experiment { didSet { recordUndo(oldValue); save() } }
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
    /// Well the Duplicate tool is copying (row scope copies its whole row); nil = pick one first.
    @Published var duplicateSource: Int? = nil
    @Published var duplicateScope: DuplicateScope = .well
    @Published var openAfterExport: Bool {
        didSet { if persist { UserDefaults.standard.set(openAfterExport, forKey: "openAfterExport") } }
    }
    /// A light tick on the trackpad as wells fill and tools change.
    @Published var haptics: Bool = UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true {
        didSet { if persist { UserDefaults.standard.set(haptics, forKey: "haptics") } }
    }
    /// Whether the app is in front; long-running animations pause when it is not. Starts off until the
    /// app is actually activated (it can be launched in the background).
    @Published var appActive = false
    /// When the export confetti went off.
    @Published var confettiAt = Date.distantPast
    /// When the plate reader last swept the plate (export).
    @Published var readerAt = Date.distantPast
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
        openAfterExport = UserDefaults.standard.object(forKey: "openAfterExport") as? Bool ?? true
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
        openAfterExport = false
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
            if dragErases == nil { dragErases = (exp.wells[w] == id) }
            let new: UUID? = dragErases! ? nil : id
            if dragErases! && exp.wells[w] != id { return }
            if exp.wells[w] != new { setWell(w, new) }
        case .erase:
            if exp.wells[w] != nil { setWell(w, nil) }
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

    func endDrag() { dragErases = nil; dupDrag = nil }

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
            exp = loaded
            selectedWell = nil
            duplicateSource = nil
            validateTool()
            showToast("Plate thawed and ready.")
        } catch {
            errorAlert("Could not open the plate", error)
        }
    }

    /// The plate reader sweeps the stained wells, then the confetti flies.
    func celebrateExport() {
        let now = Date()
        let stained = exp.wells.contains { w in w.map { id in exp.sets.contains { $0.id == id } } ?? false }
        if stained && motion { readerAt = now }
        confettiAt = stained && motion ? now.addingTimeInterval(readerSweepLength - 0.15) : now
    }

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
            showToast(exportLines.randomElement() ?? "Exported.")
            celebrateExport()
            tap(.levelChange)
            if openAfterExport { NSWorkspace.shared.open(url) }
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
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
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
    phase("plate idle, no stain picked (8 s)", 8)
    phase("hologram scanning over a stain (14 s)", 14) { store.tool = .paint(store.exp.sets[min(2, store.exp.sets.count - 1)].id) }
    phase("hologram for a stain picked again (3 s)", 3) {
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
    phase("export: plate reader, then confetti (6 s)", 6) { store.celebrateExport() }
    phase("app in the background (4 s)", 4) { store.tool = .paint(store.exp.sets[0].id); store.appActive = false }
    beat.invalidate()
}
