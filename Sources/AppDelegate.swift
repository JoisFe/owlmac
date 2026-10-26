import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let sleepGuard = SleepGuard()
    private let watcher = ProcessWatcher()
    private let menu = NSMenu()
    private let headerItem = NSMenuItem()
    private let defaults = UserDefaults.standard

    /// Turned on by a click or a timed preset.
    private var manualOn = false
    private var deadline: Date?
    /// A click while auto-detect holds the Mac awake snoozes it until the detected work finishes.
    private var autoSnoozed = false
    private var lidOn = false

    private var face: OwlFace?
    private var wasAwake = false
    private var animationID = 0
    private var blinkTimer: Timer?
    private var tickTimer: Timer?

    private var autoDetect: Bool {
        get { defaults.bool(forKey: "autoDetect") }
        set { defaults.set(newValue, forKey: "autoDetect") }
    }

    private var keepDisplayOn: Bool {
        get { defaults.bool(forKey: "keepDisplayOn") }
        set { defaults.set(newValue, forKey: "keepDisplayOn") }
    }

    private var watchNames: [String] {
        get { defaults.stringArray(forKey: "watchNames") ?? ProcessWatcher.defaultNames }
        set {
            defaults.set(newValue, forKey: "watchNames")
            watcher.names = newValue
        }
    }

    private var autoAwake: Bool { autoDetect && !autoSnoozed && !watcher.found.isEmpty }
    private var isAwake: Bool { manualOn || lidOn || autoAwake }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["autoDetect": true])

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        menu.delegate = self
        headerItem.isEnabled = false

        watcher.names = watchNames
        watcher.onChange = { [weak self] in
            guard let self else { return }
            if self.watcher.found.isEmpty { self.autoSnoozed = false }
            self.refresh()
        }
        if autoDetect { watcher.start() }

        lidOn = LidGuard.isEnabled
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sleepGuard.release()
        if lidOn { LidGuard.setEnabled(false) }
    }

    // MARK: Clicks

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        let wantsMenu = event.type == .rightMouseUp
            || event.modifierFlags.contains(.control)
            || event.modifierFlags.contains(.option)
        if wantsMenu {
            buildMenu()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
        } else {
            toggle()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    @objc private func toggle() {
        if isAwake {
            manualOn = false
            deadline = nil
            if autoAwake { autoSnoozed = true }
            if lidOn { setLid(false) }
        } else {
            manualOn = true
        }
        refresh()
    }

    @objc private func startTimed(_ sender: NSMenuItem) {
        manualOn = true
        deadline = Date().addingTimeInterval(TimeInterval(sender.tag * 60))
        refresh()
    }

    @objc private func toggleAutoDetect() {
        autoDetect.toggle()
        autoSnoozed = false
        if autoDetect { watcher.start() } else { watcher.stop() }
        refresh()
    }

    @objc private func toggleKeepDisplayOn() {
        keepDisplayOn.toggle()
        refresh()
    }

    @objc private func toggleLid() {
        if !lidOn {
            let alert = NSAlert()
            alert.messageText = "뚜껑을 닫아도 깨어 있게 할까요?"
            alert.informativeText = """
            충전기 없이 뚜껑을 닫아도 맥이 잠들지 않아요.

            • 가방에 넣지 마세요. 뚜껑을 닫은 채 일하면 뜨거워져요.
            • 배터리가 다 되면 그냥 꺼져요. 긴 작업이면 충전기를 꽂아 두세요.
            • 부엉이를 재우거나 OwlMac을 끄면 원래대로 돌아가요. 이때 비밀번호를 한 번 더 물어요.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "켜기")
            alert.addButton(withTitle: "취소")
            activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        setLid(!lidOn)
    }

    private func setLid(_ on: Bool) {
        LidGuard.setEnabled(on)
        lidOn = LidGuard.isEnabled
        refresh()
    }

    @objc private func editWatchNames() {
        let alert = NSAlert()
        alert.messageText = "어떤 명령이 돌 때 깨어 있을까요?"
        alert.informativeText = "실행 파일 이름을 쉼표로 구분해서 적어 주세요. 대소문자를 구분해요.\n예: claude, npm, pnpm, cargo"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.stringValue = watchNames.joined(separator: ", ")
        alert.accessoryView = field
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "기본값으로")
        alert.addButton(withTitle: "취소")
        alert.window.initialFirstResponder = field
        activate()

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            watchNames = field.stringValue
                .split(whereSeparator: { $0 == "," || $0.isWhitespace })
                .map(String.init)
        case .alertSecondButtonReturn:
            defaults.removeObject(forKey: "watchNames")
            watcher.names = ProcessWatcher.defaultNames
        default:
            return
        }
        if autoDetect { watcher.scan() }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "로그인 항목을 바꾸지 못했어요"
            alert.informativeText = "\(error.localizedDescription)\n\nOwlMac이 응용 프로그램 폴더에 있는지 확인해 주세요."
            activate()
            alert.runModal()
        }
    }

    private func activate() {
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }

    // MARK: State → UI

    private func refresh() {
        let awake = isAwake
        if awake {
            sleepGuard.hold(reason: assertionReason, keepDisplayOn: keepDisplayOn)
        } else {
            sleepGuard.release()
        }

        if awake && !wasAwake {
            animate([.blink, .watching, .awake], step: 0.09)  // eyes pop open
        } else {
            show(awake ? .awake : (autoDetect ? .watching : .asleep))
        }
        wasAwake = awake

        scheduleBlink()
        updateTickTimer()
        updateLabels()
    }

    private func show(_ newFace: OwlFace) {
        animationID += 1
        setFace(newFace)
    }

    private func setFace(_ newFace: OwlFace) {
        guard newFace != face else { return }
        face = newFace
        statusItem.button?.image = OwlIcon.statusImage(newFace)
    }

    private func animate(_ frames: [OwlFace], step: TimeInterval, then done: (() -> Void)? = nil) {
        animationID += 1
        let id = animationID
        for (i, frame) in frames.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(i)) { [weak self] in
                guard let self, self.animationID == id else { return }
                self.setFace(frame)
                if i == frames.count - 1 { done?() }
            }
        }
    }

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        guard isAwake else { return }
        blinkTimer = Timer.scheduledTimer(withTimeInterval: .random(in: 3.5...8), repeats: false) { [weak self] _ in
            guard let self, self.isAwake else { return }
            let frames: [OwlFace] = Int.random(in: 0..<4) == 0
                ? [.blink, .awake, .blink, .awake]  // the occasional double blink
                : [.blink, .awake]
            self.animate(frames, step: 0.12) { [weak self] in self?.scheduleBlink() }
        }
    }

    private func updateTickTimer() {
        guard deadline != nil else {
            tickTimer?.invalidate()
            tickTimer = nil
            return
        }
        guard tickTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)  // keep counting while the menu is open
        tickTimer = timer
    }

    private func tick() {
        if let deadline, deadline <= Date() {
            manualOn = false
            self.deadline = nil
            refresh()
        } else {
            updateLabels()
        }
    }

    private func updateLabels() {
        headerItem.title = statusText
        statusItem.button?.toolTip = "OwlMac — \(statusText)\n클릭: 깨우기/재우기 · 우클릭: 메뉴"
    }

    private var statusText: String {
        if lidOn { return "깨어 있음 · 뚜껑을 닫아도 안 자요" }
        if manualOn {
            guard let deadline else { return "깨어 있음 · 끌 때까지" }
            return "깨어 있음 · \(format(deadline.timeIntervalSinceNow)) 남음"
        }
        if autoAwake { return "깨어 있음 · \(watcher.found.joined(separator: ", ")) 실행 중" }
        if autoDetect {
            return autoSnoozed ? "잠깐 쉬는 중 · 지금 작업이 끝나면 다시 지켜봐요" : "지켜보는 중 · 감지된 작업 없음"
        }
        return "잠자는 중"
    }

    private var assertionReason: String {
        if manualOn || lidOn { return "OwlMac (manual)" }
        return "OwlMac (\(watcher.found.joined(separator: ", ")))"
    }

    private func format(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Menu

    private func buildMenu() {
        lidOn = LidGuard.isEnabled  // could have been changed from Terminal
        updateLabels()
        menu.removeAllItems()

        menu.addItem(headerItem)
        menu.addItem(.separator())

        menu.addItem(item(isAwake ? "재우기" : "깨우기", #selector(toggle)))
        let timed = NSMenuItem(title: "시간 정해 깨우기", action: nil, keyEquivalent: "")
        let presets = NSMenu()
        for (title, minutes) in [("30분", 30), ("1시간", 60), ("2시간", 120), ("4시간", 240), ("8시간", 480)] {
            let preset = item(title, #selector(startTimed(_:)))
            preset.tag = minutes
            presets.addItem(preset)
        }
        timed.submenu = presets
        menu.addItem(timed)
        menu.addItem(.separator())

        let auto = item("개발 작업이 돌면 알아서 깨어 있기", #selector(toggleAutoDetect))
        auto.state = autoDetect ? .on : .off
        auto.toolTip = "감지 대상: " + watchNames.joined(separator: ", ")
        menu.addItem(auto)
        menu.addItem(item("감지할 명령 편집…", #selector(editWatchNames)))
        menu.addItem(.separator())

        let display = item("화면도 켜 두기", #selector(toggleKeepDisplayOn))
        display.state = keepDisplayOn ? .on : .off
        menu.addItem(display)
        let lid = item("뚜껑 닫아도 깨어 있기 (관리자 권한)", #selector(toggleLid))
        lid.state = lidOn ? .on : .off
        menu.addItem(lid)
        menu.addItem(.separator())

        let login = item("로그인할 때 실행", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "OwlMac 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}
