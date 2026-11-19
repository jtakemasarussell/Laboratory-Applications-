import AppKit
import CryptoKit

// MARK: - Over-the-air updates from GitHub Releases
//
// The app asks GitHub for the newest release of the repository named by `UpdateRepository` in
// Info.plist ("owner/repo"). When that release's version is newer than this one, it offers to install
// it: the release's .zip is downloaded, checked (GitHub's SHA-256, size, bundle id, version, code
// signature), and swapped in for this copy of the app by a small script that waits for the app to quit
// and then relaunches it. Plates and settings live in Application Support, so they are untouched.
//
// QPCR_UPDATE_FEED (environment) points the check at another JSON feed in the same format, for testing.

struct ReleaseInfo {
    let version: String
    let title: String
    let notes: String
    let page: URL?
    let asset: URL
    let size: Int
    let sha256: String?
}

private struct GHRelease: Decodable {
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: String?
    let draft: Bool?
    let prerelease: Bool?
    let assets: [GHAsset]
}

private struct GHAsset: Decodable {
    let name: String
    let browser_download_url: String
    let size: Int
    let digest: String?
}

final class Updater: NSObject, URLSessionDownloadDelegate {
    static let shared = Updater()

    /// "owner/repo" from Info.plist, or nil when this build was made without one.
    var repository: String? {
        let r = (Bundle.main.object(forInfoDictionaryKey: "UpdateRepository") as? String ?? "").trimmingCharacters(in: .whitespaces)
        return r.split(separator: "/").count == 2 ? r : nil
    }

    /// The repository can hold several lab apps; this app's releases are the tags that start with this.
    var tagPrefix: String { Bundle.main.object(forInfoDictionaryKey: "UpdateTagPrefix") as? String ?? "qpcr-v" }

    private var testFeed: URL? { ProcessInfo.processInfo.environment["QPCR_UPDATE_FEED"].flatMap(URL.init(string:)) }

    var feedURL: URL? {
        if let t = testFeed { return t }
        guard let r = repository else { return nil }
        return URL(string: "https://api.github.com/repos/\(r)/releases?per_page=100")
    }

    static var automatic: Bool {
        get { UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoUpdateCheck") }
    }

    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    private var checking = false
    private var session: URLSession?
    private var pending: ReleaseInfo?
    private var workDir: URL?
    private var progressPanel: NSPanel?
    private var progressBar: NSProgressIndicator?
    private var progressLabel: NSTextField?

    // MARK: Checking

    /// Once a day, a few seconds after launch, if automatic checks are on.
    func checkAtLaunch() {
        guard Self.automatic, feedURL != nil else { return }
        let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        guard testFeed != nil || Date().timeIntervalSince1970 - last > 20 * 3600 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.check(userInitiated: false) }
    }

    /// Asks GitHub for the latest release. Automatic checks stay silent unless there is something new.
    func check(userInitiated: Bool) {
        if session != nil { progressPanel?.makeKeyAndOrderFront(nil); return }
        guard !checking else { return }
        guard let url = feedURL else {
            if userInitiated {
                inform("Updates aren't set up in this copy",
                       "This build doesn't know which GitHub repository to check. Set UpdateRepository in Info.plist to owner/repository and rebuild.")
            }
            return
        }
        checking = true
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("qPCR-Planner-Updater", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                self.checking = false
                self.handle(data: data, response: response, error: error, userInitiated: userInitiated)
            }
        }.resume()
    }

    private func handle(data: Data?, response: URLResponse?, error: Error?, userInitiated: Bool) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if let error {
            if userInitiated { inform("Couldn't check for updates", error.localizedDescription) }
            return
        }
        guard status == 200, let data, let all = try? JSONDecoder().decode([GHRelease].self, from: data) else {
            if userInitiated {
                let why = status == 404 ? "The repository \(repository ?? "") couldn't be found." : "GitHub answered with an unexpected reply (HTTP \(status)). Try again later."
                inform("Couldn't check for updates", why)
            }
            return
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
        // newest published release of this app (other apps in the repository use other tag prefixes)
        let mine = all.filter { $0.draft != true && $0.prerelease != true && $0.tag_name.lowercased().hasPrefix(tagPrefix.lowercased()) }
        let versionOf = { (r: GHRelease) in String(r.tag_name.dropFirst(self.tagPrefix.count)) }
        guard let rel = mine.max(by: { Self.isNewer(versionOf($1), than: versionOf($0)) }) else {
            if userInitiated { inform("You're up to date", "No qPCR Planner updates have been published yet (you have \(currentVersion)).") }
            return
        }
        let version = versionOf(rel)
        guard Self.isNewer(version, than: currentVersion) else {
            if userInitiated { inform("You're up to date", "qPCR Planner \(currentVersion) is the newest version.") }
            return
        }
        if !userInitiated, UserDefaults.standard.string(forKey: "skippedUpdateVersion") == version { return }
        let zips = rel.assets.filter { $0.name.lowercased().hasSuffix(".zip") }
        guard let asset = zips.first(where: { $0.name.lowercased().contains("qpcr") }),
              let assetURL = URL(string: asset.browser_download_url) else {
            if userInitiated { inform("Update \(version) can't be installed automatically", "That release has no .zip of the app attached.") }
            return
        }
        var sha: String? = nil
        if let d = asset.digest, d.lowercased().hasPrefix("sha256:") { sha = String(d.dropFirst(7)).lowercased() }
        let info = ReleaseInfo(version: version, title: rel.name ?? "qPCR Planner \(version)", notes: rel.body ?? "",
                               page: rel.html_url.flatMap(URL.init(string:)), asset: assetURL, size: asset.size, sha256: sha)
        offer(info)
    }

    /// 1.10 is newer than 1.9; missing parts count as 0 (1.4 == 1.4.0).
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    // MARK: Offer

    private func offer(_ r: ReleaseInfo) {
        if testFeed != nil, ProcessInfo.processInfo.environment["QPCR_UPDATE_AUTOINSTALL"] == "1" { download(r); return }   // testing only
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "qPCR Planner \(r.version) is available"
        let mb = r.size > 0 ? String(format: " (%.1f MB)", Double(r.size) / 1_048_576) : ""
        a.informativeText = "You have \(currentVersion). Installing\(mb) replaces the app and relaunches it; your plates and settings are kept."

        let width: CGFloat = 440
        let box = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 210))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 30, width: width, height: 180))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.textContainerInset = NSSize(width: 6, height: 6)
        text.autoresizingMask = [.width]
        let notes = r.notes.isEmpty ? "No release notes." : r.notes
        let md = (try? NSAttributedString(markdown: notes, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? NSAttributedString(string: notes)
        let styled = NSMutableAttributedString(attributedString: md)
        styled.addAttributes([.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.textColor],
                             range: NSRange(location: 0, length: styled.length))
        text.textStorage?.setAttributedString(styled)
        scroll.documentView = text
        let auto = NSButton(checkboxWithTitle: "Check for updates automatically", target: nil, action: nil)
        auto.state = Self.automatic ? .on : .off
        auto.frame.origin = NSPoint(x: 0, y: 2)
        box.addSubview(scroll)
        box.addSubview(auto)
        a.accessoryView = box

        a.addButton(withTitle: "Install and Relaunch")
        a.addButton(withTitle: "Later")
        a.addButton(withTitle: "Skip This Version")
        let answer = a.runModal()
        Self.automatic = auto.state == .on
        switch answer {
        case .alertFirstButtonReturn: download(r)
        case .alertThirdButtonReturn: UserDefaults.standard.set(r.version, forKey: "skippedUpdateVersion")
        default: break
        }
    }

    // MARK: Download

    private func download(_ r: ReleaseInfo) {
        pending = r
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("QPCRPlannerUpdate-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        workDir = dir
        showProgress("Downloading qPCR Planner \(r.version)…")
        let s = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)
        session = s
        var req = URLRequest(url: r.asset, timeoutInterval: 60)
        req.setValue("qPCR-Planner-Updater", forHTTPHeaderField: "User-Agent")
        s.downloadTask(with: req).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Int64(pending?.size ?? 0)
        guard total > 0 else { progressBar?.isIndeterminate = true; progressBar?.startAnimation(nil); return }
        progressBar?.isIndeterminate = false
        progressBar?.doubleValue = Double(totalBytesWritten) / Double(total) * 100
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // the file is deleted when this returns, so move it first
        guard let dir = workDir, let r = pending else { return }
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            fail("The download failed (HTTP \(http.statusCode)).")
            return
        }
        let zip = dir.appendingPathComponent("update.zip")
        do {
            try FileManager.default.moveItem(at: location, to: zip)
        } catch {
            fail(error.localizedDescription)
            return
        }
        progressLabel?.stringValue = "Checking the update…"
        progressBar?.isIndeterminate = true
        progressBar?.startAnimation(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let app = try self.verify(zip: zip, release: r, in: dir)
                DispatchQueue.main.async { self.install(app) }
            } catch {
                DispatchQueue.main.async { self.fail(error.localizedDescription) }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        self.session = nil
        if let error, (error as NSError).code != NSURLErrorCancelled { fail(error.localizedDescription) }
    }

    // MARK: Verify

    private struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ s: String) { errorDescription = s }
    }

    /// Unpacks the download and makes sure it is a newer, intact copy of this same app.
    private func verify(zip: URL, release r: ReleaseInfo, in dir: URL) throws -> URL {
        let fm = FileManager.default
        let size = (try? fm.attributesOfItem(atPath: zip.path)[.size] as? Int) ?? -1
        if r.size > 0, size != r.size {
            throw UpdateError("The download is incomplete (\(size) of \(r.size) bytes). Please try again.")
        }
        if let want = r.sha256 {
            let data = try Data(contentsOf: zip, options: .mappedIfSafe)
            let got = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard got == want else { throw UpdateError("The download doesn't match the checksum GitHub published for it, so it wasn't installed.") }
        }
        let out = dir.appendingPathComponent("unzipped", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path], "The update couldn't be unpacked.")
        let found = (try? fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)) ?? []
        guard let app = found.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError("The update's .zip doesn't contain the app.")
        }
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else {
            throw UpdateError("The downloaded app is damaged (no Info.plist).")
        }
        guard info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw UpdateError("The download isn't qPCR Planner, so it wasn't installed.")
        }
        let v = info["CFBundleShortVersionString"] as? String ?? "0"
        guard Self.isNewer(v, than: currentVersion) else {
            throw UpdateError("The download is version \(v), which isn't newer than this one (\(currentVersion)).")
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], "The downloaded app's code signature is broken, so it wasn't installed.")
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path], "")
        return app
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String], _ failure: String) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw UpdateError(failure) }
        return p.terminationStatus
    }

    // MARK: Install

    private func install(_ newApp: URL) {
        hideProgress()
        guard let dir = workDir, let r = pending else { return }
        let fm = FileManager.default
        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()
        let replaceable = target.pathExtension == "app"
            && fm.isWritableFile(atPath: parent.path) && fm.isWritableFile(atPath: target.path)
            && !target.path.contains("/AppTranslocation/")
        guard replaceable else {
            // can't swap it in place (e.g. run from the disk image): hand the new copy to the user
            let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            let dest = downloads.appendingPathComponent("qPCR Planner \(r.version).app")
            try? fm.removeItem(at: dest)
            do { try fm.copyItem(at: newApp, to: dest) } catch { fail(error.localizedDescription); return }
            NSWorkspace.shared.activateFileViewerSelecting([dest])
            inform("Update downloaded",
                   "This copy of the app is in a place it can't replace itself (\(parent.path)). The new version is in Downloads: quit this app, then drag the new one into Applications.")
            return
        }
        let script = """
        #!/bin/sh
        PID="$1"; TARGET="$2"; NEW="$3"; BACKUP="$4"; WORK="$5"
        i=0
        while /bin/kill -0 "$PID" 2>/dev/null; do /bin/sleep 0.2; i=$((i+1)); [ $i -gt 300 ] && exit 1; done
        /bin/rm -rf "$BACKUP"
        if /bin/mv "$TARGET" "$BACKUP"; then
          if /usr/bin/ditto "$NEW" "$TARGET"; then /bin/rm -rf "$BACKUP"; else /bin/rm -rf "$TARGET"; /bin/mv "$BACKUP" "$TARGET"; fi
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
        /usr/bin/open "$TARGET"
        case "$WORK" in */QPCRPlannerUpdate-*) /bin/rm -rf "$WORK" ;; esac
        """
        let scriptURL = dir.appendingPathComponent("install.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [scriptURL.path, String(ProcessInfo.processInfo.processIdentifier), target.path, newApp.path,
                           dir.appendingPathComponent("previous.app").path, dir.path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
        } catch {
            fail(error.localizedDescription)
            return
        }
        UserDefaults.standard.set(currentVersion, forKey: "updatedFrom")
        NSApp.terminate(nil)
    }

    /// After relaunching into a new version, a one-line note says so.
    func noteIfJustUpdated() -> String? {
        guard let from = UserDefaults.standard.string(forKey: "updatedFrom") else { return nil }
        UserDefaults.standard.removeObject(forKey: "updatedFrom")
        return from == currentVersion ? nil : "Updated to \(currentVersion)"
    }

    // MARK: Progress window and messages

    private func showProgress(_ title: String) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 110), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Software Update"
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 20, y: 72, width: 340, height: 18)
        let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 46, width: 340, height: 20))
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 100
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelDownload))
        cancel.frame = NSRect(x: 270, y: 10, width: 90, height: 28)
        cancel.keyEquivalent = "\u{1b}"
        panel.contentView?.addSubview(label)
        panel.contentView?.addSubview(bar)
        panel.contentView?.addSubview(cancel)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        progressPanel = panel
        progressBar = bar
        progressLabel = label
    }

    private func hideProgress() {
        progressPanel?.orderOut(nil)
        progressPanel = nil
        progressBar = nil
        progressLabel = nil
    }

    @objc private func cancelDownload() {
        session?.invalidateAndCancel()
        session = nil
        hideProgress()
        cleanUp()
    }

    private func cleanUp() {
        if let d = workDir { try? FileManager.default.removeItem(at: d) }
        workDir = nil
        pending = nil
    }

    private func fail(_ message: String) {
        session?.invalidateAndCancel()
        session = nil
        hideProgress()
        cleanUp()
        inform("The update couldn't be installed", message + "\n\nNothing was changed; this version keeps working.")
    }

    private func inform(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
