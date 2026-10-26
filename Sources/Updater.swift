import AppKit

/// Checks GitHub Releases for a newer OwlMac and swaps the app bundle the way install.sh does.
final class Updater {
    struct Release {
        let version: String  // "0.2.0"
        let zipURL: URL
        let pageURL: URL
    }

    enum Outcome {
        case upToDate(String)
        case newer(Release)
        case failed(String)
        /// A bare `swiftc` binary or a build that skipped the VERSION substitution.
        case unversioned
    }

    /// owner/repo. `defaults write io.github.owlmac updateRepo owner/repo` follows a fork (like OWLMAC_REPO in install.sh).
    private let repo: String
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var checking = false

    /// The newest release seen that is newer than the running app. Shown at the top of the menu.
    private(set) var available: Release?
    /// Called on the main thread when an automatic check finds a version that was not offered before.
    var onAutoFound: ((Release) -> Void)?

    init() {
        repo = UserDefaults.standard.string(forKey: "updateRepo") ?? "semiaurum/owlmac"
    }

    static let currentVersion: String? = {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !version.isEmpty, version != "__VERSION__" else { return nil }
        return version
    }()

    var autoCheck: Bool {
        get { defaults.bool(forKey: "autoUpdateCheck") }
        set {
            defaults.set(newValue, forKey: "autoUpdateCheck")
            scheduleAutoCheck()
        }
    }

    // MARK: Scheduling

    /// Checks shortly after launch and then once a day while auto-check is on.
    func scheduleAutoCheck() {
        timer?.invalidate()
        timer = nil
        guard autoCheck, Updater.currentVersion != nil else { return }
        let timer = Timer(timeInterval: 24 * 3600, repeats: true) { [weak self] _ in self?.check(manual: false) }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.autoCheck else { return }
            self.check(manual: false)
        }
    }

    // MARK: Checking

    /// `completion` runs on the main thread. A manual check reports every outcome; an automatic one
    /// only surfaces a release through `onAutoFound`, once per version.
    func check(manual: Bool, completion: ((Outcome) -> Void)? = nil) {
        guard let current = Updater.currentVersion else {
            completion?(.unversioned)
            return
        }
        guard !checking else { return }
        checking = true

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OwlMac/\(current)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let outcome = Updater.parse(data: data, response: response, error: error, current: current)
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                switch outcome {
                case .newer(let release): self.available = release
                case .upToDate: self.available = nil
                default: break
                }
                if !manual, case .newer(let release) = outcome,
                   self.defaults.string(forKey: "offeredUpdateVersion") != release.version {
                    self.defaults.set(release.version, forKey: "offeredUpdateVersion")
                    self.onAutoFound?(release)
                }
                completion?(outcome)
            }
        }.resume()
    }

    private static func parse(data: Data?, response: URLResponse?, error: Error?, current: String) -> Outcome {
        if let error { return .failed(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse, let data else { return .failed("응답이 없어요.") }
        guard http.statusCode == 200 else { return .failed("GitHub이 \(http.statusCode)으로 답했어요.") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
            return .failed("릴리스 정보를 읽지 못했어요.")
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isNewer(version, than: current) else { return .upToDate(current) }
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let zip = assets.first(where: { ($0["name"] as? String) == "OwlMac.zip" }),
              let url = (zip["browser_download_url"] as? String).flatMap(URL.init(string:)) else {
            return .failed("v\(version) 릴리스에 OwlMac.zip이 없어요.")
        }
        return .newer(Release(version: version, zipURL: url, pageURL: page))
    }

    /// Dotted numeric compare: "0.10.1" is newer than "0.9.3". Non-numeric parts count as 0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Installing

    /// Downloads the zip, then starts a script that waits for this process to quit, swaps the bundle
    /// (unzip → replace → drop quarantine, as install.sh does) and relaunches. The caller quits the app
    /// afterwards so applicationWillTerminate can release assertions and undo `pmset disablesleep`.
    /// `completion` runs on the main thread with an error message, or nil when the script is running.
    func install(_ release: Release, completion: @escaping (String?) -> Void) {
        let task = URLSession.shared.downloadTask(with: release.zipURL) { tmp, response, error in
            let result: String?
            do {
                if let error { throw error }
                guard let tmp, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw NSError(domain: "OwlMac", code: 1, userInfo: [NSLocalizedDescriptionKey: "OwlMac.zip을 내려받지 못했어요."])
                }
                try Updater.launchSwapScript(zipAt: tmp)
                result = nil
            } catch {
                result = error.localizedDescription
            }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
    }

    /// Where the new bundle goes: the running bundle if its folder is writable, else /Applications, else ~/Applications.
    private static var destination: URL {
        let fm = FileManager.default
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app", fm.isWritableFile(atPath: bundle.deletingLastPathComponent().path) {
            return bundle
        }
        let apps = URL(fileURLWithPath: "/Applications")
        if fm.isWritableFile(atPath: apps.path) { return apps.appendingPathComponent("OwlMac.app") }
        return fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/OwlMac.app")
    }

    private static func launchSwapScript(zipAt downloaded: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("OwlMac-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("OwlMac.zip")
        try fm.moveItem(at: downloaded, to: zip)

        let script = """
        #!/bin/bash
        # Written by OwlMac to finish an update after the app has quit.
        set -u
        pid=\(ProcessInfo.processInfo.processIdentifier)
        zip=\(quoted(zip.path))
        work=\(quoted(work.path))
        dest=\(quoted(destination.path))
        for _ in $(seq 1 150); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
        ditto -x -k "$zip" "$work" || exit 1
        [ -d "$work/OwlMac.app" ] || exit 1
        mkdir -p "$(dirname "$dest")"
        rm -rf "$dest"
        ditto "$work/OwlMac.app" "$dest" || exit 1
        xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
        open "$dest"
        rm -rf "$work"
        """
        let scriptURL = work.appendingPathComponent("swap.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
